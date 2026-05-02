# jalt — WoW inventory addon

A World of Warcraft Retail addon (WoW: Midnight, patch 12.x / TOC `120005`) that tracks bags, banks, equipment, and currencies across all characters on an account. Lean by design — no DataStore-style abstraction, no plugin API, no inter-module bus.

The original design brief is `plan.CLAUDE.md`. This file documents what was actually built and the constraints that future work needs to respect.

---

## Layout

```
jalt.toc              -- load order, SavedVariables = jaltDB
jalt.lua              -- AceAddon core, event wiring, slash dispatch
Data.lua              -- scanners + item index (jalt.Data)
Tooltip.lua           -- TooltipDataProcessor hook (jalt.Tooltip)
Search.lua            -- /jalt search results frame (jalt.Search)
GearViewer.lua        -- main window + Gear tab + Profession Gear tab
                         (jalt.Window, jalt.GearViewer, jalt.ProfessionGearViewer)
CurrencyViewer.lua    -- Currency tab (jalt.CurrencyViewer)
libs/                 -- embedded Ace3 + LibStub + CallbackHandler
```

`jalt.Window` and `jalt.ProfessionGearViewer` both live in `GearViewer.lua` (not their own files). The main window is a TabGroup hosting the Gear, Profession Gear, and Currency views. The two gear viewers share `RenderGear` — each passes its own `slotOrder` and `optionalSlots` so the avg/min ilvl summary is computed independently per tab. They share `currentChar` so switching tabs doesn't reset the dropdown.

Modules attach themselves to the addon object: `jalt.Data`, `jalt.Tooltip`, `jalt.Search`, `jalt.GearViewer`, `jalt.ProfessionGearViewer`, `jalt.CurrencyViewer`, `jalt.Window`. All cross-module access goes through these fields. The addon is also exposed as `_G.jalt` for convenience while debugging.

Each file starts with `local ADDON_NAME = ...` and `LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)` — preserve that pattern when adding new files. `jalt.lua` itself uses `:NewAddon(...)`.

---

## SavedVariables (`jaltDB`)

Single AceDB table, **`global`** scope only (not per-char/per-realm — every character writes into the same global tree, keyed by `"Realm - CharName"`). Defaults are seeded in `jalt.lua`.

```lua
jaltDB.global = {
  characters = {
    ["Realm - Name"] = {
      class, level, faction, lastSeen,
      bags       = { [bagID]   = { [slot] = { itemID, count, itemLink } } },
      bank       = { [bagID]   = { name, slots = { [slot] = {...} } } },
      equipped   = { [slotID]  = { itemID, ilvl, itemLink } },
      currencies = { [currencyID] = { count, name, icon } },
      mail       = { [seq]     = { sender, slots = { [attachIndex] = { itemID, count, itemLink } } } },
    },
  },
  guildBank = {
    ["GuildName"] = { [tabIndex] = { name, slots = { [slot] = {...} } } },
  },
  warbandBank = { [bagID] = { name, slots = { [slot] = {...} } } },
}
```

Notes that bit us already:
- Character bank entries are **keyed by `bagID`**, not by an arbitrary tab index — `bagID` comes from `Enum.BagIndex.CharacterBankTab_1..6`. Same shape for the warband bank, using `Enum.BagIndex.AccountBankTab_1..5`. The Midnight bank UI is fundamentally tab-bag-based.
- The warband bank is **account-level** (top-level under `global`, not under a character).
- Stored `itemLink` strings are the source of truth for offline characters. Never assume an itemID is enough to reconstruct a link.

---

## Event wiring (in `jalt:OnEnable`)

| Source | Event(s) | Handler effect |
|---|---|---|
| Bags | `BAG_UPDATE` | Debounced 0.5s, then `Data:ScanBags` + `RebuildItemIndex` |
| Character bank | `BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED`, `BANK_TABS_CHANGED` | `Data:ScanBank` |
| Warband bank | `PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, `BANK_TABS_CHANGED` | `Data:ScanWarbandBank` |
| Guild bank | `GUILDBANKFRAME_OPENED`, `GUILDBANKBAGSLOTS_CHANGED` | `Data:ScanGuildBank` / `ScanGuildBankTab` |
| Equipment | `PLAYER_LOGIN`, `PLAYER_EQUIPMENT_CHANGED` | `Data:ScanEquipment` |
| Currencies | `PLAYER_LOGIN`, `CURRENCY_DISPLAY_UPDATE` | `Data:ScanCurrencies` |
| Mail (send) | `hooksecurefunc("SendMail")` + `MAIL_SEND_SUCCESS` / `MAIL_FAILED` | `Data:CaptureOutgoingMail` → `CommitOutgoingMail` / `DiscardOutgoingMail` |
| Mail (recipient) | `hooksecurefunc("TakeInboxItem")` / `AutoLootMailItem` / `DeleteInboxItem` | `Data:ConsumeMailAttachment` / `ConsumeAllMailAttachments` |

`OnPlayerLogin` does a full baseline scan (bags + equipment + currencies) and rebuilds the item index. It is also called manually from `OnEnable` if the player is already logged in (catches `/reload`).

The bag-scan debounce uses a single `pendingBagScan` flag + `C_Timer.After`. Don't replace it with per-bag scheduling — `BAG_UPDATE` floods on inventory churn and the batched scan is the whole point.

Any scanner that mutates the data model **must** call `Data:RebuildItemIndex()` afterwards or the tooltip and search become stale. The currency scan is the one exception (currencies have their own viewer and aren't in the item index).

---

## Item index

`Data.itemIndex[itemID] = { {charKey, location, locDetail, count, itemLink}, ... }`.

`location` is one of `"bags" | "bank" | "guildbank" | "warbandbank" | "equipped" | "mail"` (those exact strings are used as keys in `Tooltip.LOCATION_COLORS` — keep them in sync).

`RebuildItemIndex()` does a full wipe-and-rebuild over every character + the warband + every guild bank. That's fine at current scale; if it ever shows up in profiles, prefer incremental updates over a smarter rebuild.

Guild banks appear in the index under a synthetic `charKey` of `"<GuildName>"` (angle brackets distinguish them from real character keys). Warband appears as `"Warband"`. Anything that displays `charKey` should tolerate these.

---

## Tooltip (the load-bearing technical constraint)

Use **only** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ...)`. Do **not** hook `GameTooltip:SetItem`, `GameTooltip:OnTooltipSetItem`, or any `SetHyperlink` postscript — those taint protected functions on Midnight and break combat.

Implementation lives in `Tooltip.lua`. Two non-obvious things to preserve:

1. **Tooltip allowlist.** The processor fires for every tooltip frame in the game (including third-party ones). We early-return for anything that isn't `GameTooltip`, `ItemRefTooltip`, or `EmbeddedItemTooltip`. Adding more tooltip targets means adding them here *and* hooking their `OnTooltipCleared`/`OnHide` via `HookTooltipCleared`.
2. **De-dup by tooltip + itemID.** `TooltipDataProcessor` can fire its post-call multiple times for the same display. `seenForCurrentTooltip[tooltip] = data.id` suppresses repeats; `OnTooltipCleared` and `OnHide` clear the entry. Without this the lines duplicate visibly.

Output format: a `" "` spacer, a `"jalt"` heading line, one `AddDoubleLine(charKey, "<locDetail> x<count>")` per location, and a total line if there are 2+ locations. Per-location colors come from `LOCATION_COLORS`.

---

## UI

All UI is AceGUI-3.0. The main window (`jalt.Window:Toggle`) is created lazily and released on close — there is no persistent frame. Re-rendering swaps children rather than rebuilding the outer frame.

Gear viewer slot layout: two columns, ordered left/right by `LEFT_SLOT_ORDER` / `RIGHT_SLOT_ORDER` in `GearViewer.lua`. Slot names come from `Data.EQUIPMENT_SLOTS`.

For offline characters the gear viewer relies entirely on stored `itemLink` strings — `GetInventoryItemLink` only works on the current character. Tooltips on the gear icons use `GameTooltip:SetHyperlink(link)` which works for any link, online or not.

---

## Slash commands

Dispatcher in `jalt:OnSlashCommand`:

- `/jalt` — toggle the main window
- `/jalt search <pattern>` — Lua-pattern search by item name
- `/jalt <anything-not-a-known-cmd>` — also treated as a search pattern (convenience)
- `/jalt rescan` — force re-scan of the current character
- `/jalt clearmail [<charname>]` — wipe recorded outgoing mail (one character, or all if no arg)
- `/jalt debug` — toggle `jalt.DEBUG`
- `/jalt help` / `/jalt ?` — print command list

When adding a new subcommand, add it to the `if/elseif` chain *and* update the `help` block.

---

## Code conventions

- **Lua 5.1** only (WoW's interpreter). No `goto`, no integer division `//`, no bitwise operators, no `\z`.
- One module per file, exposed as `jalt.<Module>`. No globals other than `_G.jalt`.
- Debug output: `jalt:Debug(...)` (gated by `jalt.DEBUG`); user-facing: `jalt:Print(...)` (AceConsole). Never bare `print()`.
- Items: use `C_Container.GetContainerItemInfo(bag, slot)` (returns a table). The legacy positional version is deprecated.
- Item links: capture at scan time, store as-is. Don't try to rebuild from itemID.
- Item levels: `C_Item.GetDetailedItemLevelInfo(link)`.
- Currencies: `C_CurrencyInfo.GetCurrencyListInfo(i)` (skip `info.isHeader`).
- Guard every Midnight-introduced API behind a presence check (`if Enum.BagIndex.AccountBankTab_1 then ...`). Several of these were toggled on and off during the pre-patch.

---

## Equipment slot IDs

```
1 Head     2 Neck     3 Shoulder  4 Shirt    5 Chest
6 Waist    7 Legs     8 Feet      9 Wrist   10 Hands
11 Ring1  12 Ring2   13 Trinket1 14 Trinket2 15 Back
16 MainHand 17 OffHand 18 Ranged  19 Tabard
20 Prof1Tool 21 Prof1Gear1 22 Prof1Gear2
23 Prof2Tool 24 Prof2Gear1 25 Prof2Gear2
26 CookingTool 27 CookingGear 28 FishingTool
```

`INVSLOT_LAST_EQUIPPED` is 19 in `wow-ui-source/Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua`, so there are no `INVSLOT_*` constants for the profession slots — IDs 20–28 are hardcoded the same way Blizzard's own `Blizzard_ProfessionsCrafting.xml` does. IDs 29–30 (Fishing Gear) exist in the protocol but are commented out in current Blizzard XML; we don't scan them. Slots 1–19 render in the Gear tab; slots 20–28 render in the Profession Gear tab. Each tab has its own `optionalSlots` set: Gear excludes Shirt/Ranged/Tabard from the avg/min summary, Profession Gear excludes nothing (every equipped prof slot counts toward avg/min for that tab).

Display names live in `Data.EQUIPMENT_SLOTS` (note "Ring 1" with a space, etc. — used in tooltip and gear UI labels).

---

## Libraries

Embedded in `libs/`:

- `LibStub`, `CallbackHandler-1.0`
- `AceAddon-3.0`, `AceEvent-3.0`, `AceDB-3.0`, `AceConsole-3.0`, `AceGUI-3.0`

Do not add LibDataBroker, LibItemInfo, or any DataStore variants. If a new Ace module is genuinely needed, copy its source into `libs/` and add the `.xml` to `jalt.toc` in dependency order (LibStub → CallbackHandler → Ace).

---

## Out of scope (don't add)

Multi-Battle.net account sharing, profession tracking (recipes, skill levels, cooldowns), quests, achievements, AH integration, Classic/TBC/MoP-Classic compatibility. Cross-realm: don't break existing data if it shows up, but don't design for it.

Note: *equipped* profession gear (slots 20–28) is in scope and is tracked — those are just more inventory slots. The "no profession tracking" rule is about the profession system itself (skill points, recipes, CD timers).

Mail tracking is **send-side only**, and only between characters that already exist in `jaltDB.global.characters`. We never bulk-scan an inbox; we capture at click-Send (`hooksecurefunc("SendMail", ...)`) and clear records via per-attachment hooks (`TakeInboxItem`, `AutoLootMailItem`, `DeleteInboxItem`). Sends to non-alts are dropped silently. Mail expiry (30-day return-to-sender) and server-rejected takes can leave stale records — `/jalt clearmail` is the manual reset.

---

## Reference

For any Blizzard API that isn't extremely stable, check `@../wow-ui-source` (a clone of https://github.com/Gethe/wow-ui-source). Other API references on the web are frequently stale post-Midnight.

Known still-volatile areas: the warband bank (events and `Enum.BagIndex.AccountBankTab_*` were toggled on and off during the Midnight pre-patch in January 2026), and bank tab APIs generally (`C_Bank.FetchPurchasedBankTabData`, `BANK_TABS_CHANGED`).
