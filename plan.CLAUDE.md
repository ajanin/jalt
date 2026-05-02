# jalt, a WoW Inventory Addon

# This was the original prompt used to seed the project. It is not up to date. See @CLAUDE.md.

## Project Overview

A World of Warcraft addon (Retail, WoW: Midnight / patch 12.x) that tracks item inventories, equipment, and currencies across all characters on an account. Focused and lean — no DataStore abstraction layer, no unnecessary features.

**Addon name**: jalt

**Target**: Retail only. No Classic/TBC/MoP Classic support.

---

## Features

### 1. Item count tooltips
When hovering any item anywhere in the UI, append lines showing how many of that item the player has across all characters, with location detail:
- Bags (bag number and slot)
- Bank
- Guild bank (tab name/number)
- Warband bank (tab name/number)
- Equipped (slot name)

If the tab name is available, use it. Otherwise, use the tab number.

Tooltip lines must not interfere with other addons (Auctionator, TSM, etc.). See the **Tooltip Implementation** section for the correct API approach — this is the most critical technical constraint in the project.

### 2. Slash commands

#### Search
- Pattern: `/jalt <search>` (e.g. `/jalt search reflugent.*ring` matches "reflugent copper ring" and "reflugent iron ring")
- Searches all stored character data by item name
- Supports Lua string patterns natively
- Results display in a small scrollable frame, not printed to chat
- Result rows show: character name, location, count

#### Window
- Pattern: `/jalt`
- Brings up interface window with a tab for gear and a tab for currency.

### 3. Gear viewer UI
- Panel listing equipment worn by any stored character
- Character selector (dropdown)
- Each equipment slot shows: item icon + item level
- Hovering an icon shows the native item tooltip via `GameTooltip:SetHyperlink(link)`
- Must work for offline characters using stored data, not live API calls

### 4. Currency tracking
- Track all currencies held across all characters
- Update on `CURRENCY_DISPLAY_UPDATE` and `PLAYER_LOGIN`

---

## Explicitly Out of Scope

Do not implement:

- Multi-Battle.net account sharing
- Profession tracking
- Quest or achievement tracking
- Mail tracking
- Auction House integration
- Classic, TBC, or MoP Classic compatibility

Cross-realm: the user plays on a single realm. Do not actively break multi-realm data if it happens to be present, but do not design for it.

---

## Architecture

### Single SavedVariables table, no abstraction layer

All data lives in one `AddonDB` SavedVariables table managed by AceDB. There is no DataStore abstraction, no inter-module messaging bus, no plugin API. Keep it simple.

### SavedVariables structure

```lua
AddonDB = {
  characters = {
    ["Realm - CharName"] = {
      class      = "MAGE",
      level      = 80,
      faction    = "Alliance",
      lastSeen   = timestamp,
      bags       = { [bagSlot] = { itemID, count, itemLink } },
      bank       = { [slotIndex] = { itemID, count, itemLink } },
      equipped   = { [slotID] = { itemID, ilvl, itemLink } },
      currencies = { [currencyID] = { count, name, icon } },
    },
  },
  guildBank = {
    ["GuildName"] = {
      [tabIndex] = {
        name  = "Tab Name",
        slots = { [slotIndex] = { itemID, count, itemLink } },
      },
    },
  },
  warbandBank = {
    -- account-level, not per character
    [tabIndex] = {
      name  = "Tab Name",
      slots = { [slotIndex] = { itemID, count, itemLink } },
    },
  },
}
```

### Item index for tooltip performance

Build an inverted index at login and update it incrementally on data changes. Do not iterate all characters on every tooltip render.

```lua
-- itemIndex[itemID] = list of locations holding that item
itemIndex = {
  [itemID] = {
    { charKey, location, locDetail, count },
    ...
  }
}
```

`location` is one of: `"bags"`, `"bank"`, `"guildbank"`, `"warbandbank"`, `"equipped"`.
`locDetail` is a human-readable string: bag/slot number, tab name, slot name, etc.

### Data collection events

| Data | Events |
|---|---|
| Bags | `BAG_UPDATE` (debounce ~0.5s to batch rapid updates) |
| Bank | `BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED` |
| Guild bank | `GUILDBANKFRAME_OPENED`, `GUILDBANKBAGSLOTS_CHANGED` |
| Warband bank | `PLAYERREAGENTBANKSLOTS_CHANGED` + warband-specific events (verify current API — see Known API Concerns) |
| Equipment | `PLAYER_LOGIN`, `PLAYER_EQUIPMENT_CHANGED` |
| Currencies | `PLAYER_LOGIN`, `CURRENCY_DISPLAY_UPDATE` |

Always do a full scan on `PLAYER_LOGIN` as a baseline for the current character.

---

## Tooltip Implementation (critical)

WoW: Midnight introduced "secret values" that prevent addons from reading certain protected data during combat. The old approach of hooking `GameTooltip:SetItem` or `GameTooltip:OnTooltipSetItem` causes taint errors in combat on Midnight. **Do not use those hooks.**

The correct approach uses `TooltipDataProcessor`, which fires after Blizzard and all other addons have added their lines:

```lua
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
  local itemID = data.id
  if not itemID then return end

  local locations = itemIndex[itemID]
  if not locations or #locations == 0 then return end

  tooltip:AddLine(" ")  -- spacer
  for _, entry in ipairs(locations) do
    tooltip:AddDoubleLine(entry.charKey, entry.locDetail .. " x" .. entry.count, ...)
  end
end)
```

This approach:
- Fires after Auctionator, TSM, and all other addons — no ordering conflicts
- Does not taint protected functions — no combat errors
- Is the supported Midnight-era API

---

## Equipment Slot IDs

```
1=Head       2=Neck       3=Shoulder   4=Shirt      5=Chest
6=Waist      7=Legs       8=Feet       9=Wrist      10=Hands
11=Ring1     12=Ring2     13=Trinket1  14=Trinket2  15=Back
16=MainHand  17=OffHand   18=Ranged    19=Tabard
```

For the current (online) character: `GetInventoryItemLink(unit, slotID)`.
For offline characters: use the stored `itemLink` from SavedVariables. This must be captured at login and on `PLAYER_EQUIPMENT_CHANGED`.

---

## Libraries

Use **Ace3**, embedded in `libs/` (copy from the Ace3 repository — do not rely on standalone installs). Required components:

- `AceAddon-3.0` — addon object and module system
- `AceEvent-3.0` — event registration
- `AceDB-3.0` — SavedVariables with schema defaults
- `AceConsole-3.0` — slash command registration
- `AceGUI-3.0` — gear viewer and search results windows

Do not use LibDataBroker, LibItemInfo, or any DataStore libraries. Use the raw `C_Item` and `C_Container` APIs directly for item data.

---

## File Structure

```
jalt/
├── jalt.toc
├── jalt.lua             -- AceAddon core, initialisation, event wiring
├── Data.lua             -- SavedVariables read/write, item index build/update
├── Tooltip.lua          -- TooltipDataProcessor registration and formatting
├── Search.lua           -- Slash command handler and results frame
├── GearViewer.lua       -- Gear UI window
├── CurrencyViewer.lua   -- Currency UI window
└── libs/
    ├── AceAddon-3.0/
    ├── AceEvent-3.0/
    ├── AceDB-3.0/
    ├── AceConsole-3.0/
    └── AceGUI-3.0/
```

---

## Code Style

- Lua 5.1 (WoW's embedded interpreter — no Lua 5.2+ features)
- No global namespace pollution: everything namespaced under the addon object or module locals
- No `print()` for debug output; use a `DEBUG` flag that gates to a conditional `DEFAULT_CHAT_FRAME:AddMessage()`
- One file per logical component (see file structure above)
- Use `C_Container.GetContainerItemInfo()` — the legacy `GetContainerItemInfo()` is deprecated
- Store `itemLink` strings at collection time; do not assume links can be reconstructed from itemID alone

---

## Known API Concerns

**Warband bank events**: The warband bank was temporarily disabled by Blizzard during the Midnight pre-patch (January 2026) and re-enabled. The event names and container IDs for scanning warband bank slots should be verified against the current live API before implementing that module. Check `Enum.BagIndex` for the current warband bank container ID.

**`C_Container` API**: Use `C_Container.GetContainerItemInfo(bagID, slotID)` which returns a table. The legacy positional-return version is deprecated and may be removed.

**Offline character equipment**: `GetInventoryItemLink()` only works on the currently logged-in character. For all other characters, the gear viewer depends entirely on data captured to SavedVariables during those characters' sessions. Make sure data collection is robust on login.

---

There have been significant changes in the WoW APIs. Check @../wow-ui-source (a copy of https://github.com/Gethe/wow-ui-source) for any interface that isn't extremely stable. Be careful with other sources, as they can often be out of date.
