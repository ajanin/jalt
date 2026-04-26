local ADDON_NAME = ...
local jalt = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Data = {}
jalt.Data = Data

Data.itemIndex = {}

local EQUIPMENT_SLOTS = {
    [1]  = "Head",     [2]  = "Neck",     [3]  = "Shoulder", [4]  = "Shirt",
    [5]  = "Chest",    [6]  = "Waist",    [7]  = "Legs",     [8]  = "Feet",
    [9]  = "Wrist",    [10] = "Hands",    [11] = "Ring 1",   [12] = "Ring 2",
    [13] = "Trinket 1",[14] = "Trinket 2",[15] = "Back",     [16] = "Main Hand",
    [17] = "Off Hand", [18] = "Ranged",   [19] = "Tabard",
}
Data.EQUIPMENT_SLOTS = EQUIPMENT_SLOTS

local function GetItemIDFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local function PlayerBagIDs()
    local bags = { Enum.BagIndex.Backpack }
    for i = 1, NUM_BAG_SLOTS or 4 do
        table.insert(bags, i)
    end
    if Enum.BagIndex.ReagentBag then
        table.insert(bags, Enum.BagIndex.ReagentBag)
    end
    return bags
end

local function CharacterBankBagIDs()
    local ids = {}
    if Enum.BagIndex.CharacterBankTab_1 then
        for i = Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_6 do
            table.insert(ids, i)
        end
    end
    return ids
end

local function AccountBankBagIDs()
    local ids = {}
    if Enum.BagIndex.AccountBankTab_1 then
        for i = Enum.BagIndex.AccountBankTab_1, Enum.BagIndex.AccountBankTab_5 do
            table.insert(ids, i)
        end
    end
    return ids
end

local function GetBankTabName(bankType, tabBagID)
    if not C_Bank or not C_Bank.FetchPurchasedBankTabData then return nil end
    local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
    if not ok or not tabs then return nil end
    for _, info in ipairs(tabs) do
        if info.ID == tabBagID then
            return info.name
        end
    end
    return nil
end

local function ScanContainer(bagID)
    local out = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            out[slot] = {
                itemID   = info.itemID,
                count    = info.stackCount or 1,
                itemLink = info.hyperlink,
            }
        end
    end
    return out
end

function Data:ScanBags()
    local _, char = jalt:GetCurrentCharacter()
    if not char then return end
    char.bags = char.bags or {}
    for _, bagID in ipairs(PlayerBagIDs()) do
        char.bags[bagID] = ScanContainer(bagID)
    end
end

function Data:ScanBank()
    local _, char = jalt:GetCurrentCharacter()
    if not char then return end
    char.bank = {}
    for _, bagID in ipairs(CharacterBankBagIDs()) do
        local items = ScanContainer(bagID)
        if next(items) then
            char.bank[bagID] = {
                name  = GetBankTabName(Enum.BankType and Enum.BankType.Character, bagID),
                slots = items,
            }
        end
    end
end

function Data:ScanWarbandBank()
    if not Enum.BagIndex or not Enum.BagIndex.AccountBankTab_1 then return end
    jalt.db.global.warbandBank = {}
    local store = jalt.db.global.warbandBank
    for _, bagID in ipairs(AccountBankBagIDs()) do
        local items = ScanContainer(bagID)
        if next(items) then
            store[bagID] = {
                name  = GetBankTabName(Enum.BankType and Enum.BankType.Account, bagID),
                slots = items,
            }
        end
    end
end

function Data:ScanEquipment()
    local _, char = jalt:GetCurrentCharacter()
    if not char then return end
    char.equipped = {}
    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local itemID = GetItemIDFromLink(link)
            local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link) or nil
            char.equipped[slotID] = {
                itemID   = itemID,
                ilvl     = ilvl,
                itemLink = link,
            }
        end
    end
end

function Data:ScanCurrencies()
    local _, char = jalt:GetCurrentCharacter()
    if not char then return end
    char.currencies = {}
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyListSize then return end

    -- Walk once and expand any collapsed headers so the scan sees every currency.
    -- Track names of headers we expanded so we can restore them after.
    local expandedByUs = {}
    if C_CurrencyInfo.ExpandCurrencyList then
        local i = 1
        while i <= (C_CurrencyInfo.GetCurrencyListSize() or 0) do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and info.isHeader and info.isHeaderExpanded == false then
                expandedByUs[info.name or tostring(i)] = true
                C_CurrencyInfo.ExpandCurrencyList(i, true)
            end
            i = i + 1
        end
    end

    local size = C_CurrencyInfo.GetCurrencyListSize() or 0
    local currentHeader, currentHeaderOrder, headerOrder = nil, 0, 0
    for i = 1, size do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info then
            if info.isHeader then
                headerOrder = headerOrder + 1
                currentHeader = info.name
                currentHeaderOrder = headerOrder
            elseif info.currencyID and info.currencyID > 0 then
                char.currencies[info.currencyID] = {
                    count                 = info.quantity or 0,
                    name                  = info.name,
                    icon                  = info.iconFileID,
                    headerName            = currentHeader,
                    headerOrder           = currentHeaderOrder,
                    isAccountTransferable = info.isAccountTransferable or false,
                    isAccountWide         = info.isAccountWide or false,
                }
            end
        end
    end

    -- Restore originally-collapsed headers. Walk in reverse so collapsing higher
    -- indices first doesn't shift indices of lower headers we still need to find.
    if next(expandedByUs) and C_CurrencyInfo.ExpandCurrencyList then
        local total = C_CurrencyInfo.GetCurrencyListSize() or 0
        for i = total, 1, -1 do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and info.isHeader and info.name and expandedByUs[info.name] then
                C_CurrencyInfo.ExpandCurrencyList(i, false)
                expandedByUs[info.name] = nil
            end
        end
    end
end

local function ScanGuildBankTabSlots(tab)
    local slots = {}
    for slot = 1, 98 do
        local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot) or nil
        if link then
            local _, count = GetGuildBankItemInfo(tab, slot)
            local itemID = GetItemIDFromLink(link)
            if itemID then
                slots[slot] = {
                    itemID   = itemID,
                    count    = count or 1,
                    itemLink = link,
                }
            end
        end
    end
    return slots
end

function Data:ScanGuildBankTab(tab)
    if not IsInGuild() or not tab or tab < 1 then return end
    local guildName = GetGuildInfo("player")
    if not guildName then return end

    jalt.db.global.guildBank = jalt.db.global.guildBank or {}
    local store = jalt.db.global.guildBank
    store[guildName] = store[guildName] or {}

    local tabName = GetGuildBankTabInfo and select(1, GetGuildBankTabInfo(tab)) or nil
    store[guildName][tab] = {
        name  = tabName,
        slots = ScanGuildBankTabSlots(tab),
    }
end

function Data:ScanGuildBank()
    if not IsInGuild() or not GetNumGuildBankTabs then return end
    local numTabs = GetNumGuildBankTabs() or 0
    for tab = 1, numTabs do
        if QueryGuildBankTab then QueryGuildBankTab(tab) end
        self:ScanGuildBankTab(tab)
    end
end

local function AddIndexEntry(itemID, charKey, location, locDetail, count, itemLink)
    if not itemID then return end
    local list = Data.itemIndex[itemID]
    if not list then
        list = {}
        Data.itemIndex[itemID] = list
    end
    table.insert(list, {
        charKey   = charKey,
        location  = location,
        locDetail = locDetail,
        count     = count or 1,
        itemLink  = itemLink,
    })
end

local function BagLabel(bagID)
    if Enum.BagIndex and bagID == Enum.BagIndex.Backpack then
        return "Backpack"
    elseif Enum.BagIndex and Enum.BagIndex.ReagentBag and bagID == Enum.BagIndex.ReagentBag then
        return "Reagent Bag"
    end
    return "Bag " .. tostring(bagID)
end

function Data:RebuildItemIndex()
    wipe(self.itemIndex)

    local chars = jalt.db and jalt.db.global and jalt.db.global.characters or {}
    for charKey, char in pairs(chars) do
        if char.bags then
            for bagID, slots in pairs(char.bags) do
                for slotIdx, entry in pairs(slots) do
                    AddIndexEntry(
                        entry.itemID,
                        charKey,
                        "bags",
                        BagLabel(bagID) .. " slot " .. slotIdx,
                        entry.count,
                        entry.itemLink
                    )
                end
            end
        end
        if char.bank then
            for bagID, tab in pairs(char.bank) do
                local label = tab.name or ("Bank Tab " .. tostring(bagID - (Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1 or 0) + 1))
                for slotIdx, entry in pairs(tab.slots or {}) do
                    AddIndexEntry(
                        entry.itemID,
                        charKey,
                        "bank",
                        label .. " slot " .. slotIdx,
                        entry.count,
                        entry.itemLink
                    )
                end
            end
        end
        if char.equipped then
            for slotID, entry in pairs(char.equipped) do
                AddIndexEntry(
                    entry.itemID,
                    charKey,
                    "equipped",
                    EQUIPMENT_SLOTS[slotID] or ("Slot " .. slotID),
                    1,
                    entry.itemLink
                )
            end
        end
    end

    local warband = jalt.db and jalt.db.global and jalt.db.global.warbandBank or {}
    for bagID, tab in pairs(warband) do
        local label = tab.name or ("Warband Tab " .. tostring(bagID - (Enum.BagIndex and Enum.BagIndex.AccountBankTab_1 or 0) + 1))
        for slotIdx, entry in pairs(tab.slots or {}) do
            AddIndexEntry(
                entry.itemID,
                "Warband",
                "warbandbank",
                label .. " slot " .. slotIdx,
                entry.count,
                entry.itemLink
            )
        end
    end

    local guildBanks = jalt.db and jalt.db.global and jalt.db.global.guildBank or {}
    for guildName, tabs in pairs(guildBanks) do
        for tabIdx, tab in pairs(tabs) do
            local label = tab.name or ("Tab " .. tabIdx)
            for slotIdx, entry in pairs(tab.slots or {}) do
                AddIndexEntry(
                    entry.itemID,
                    "<" .. guildName .. ">",
                    "guildbank",
                    label .. " slot " .. slotIdx,
                    entry.count,
                    entry.itemLink
                )
            end
        end
    end
end

function Data:GetLocationsForItem(itemID)
    return self.itemIndex[itemID]
end

function Data:GetCharacters()
    return jalt.db and jalt.db.global and jalt.db.global.characters or {}
end

function Data:GetSortedCharacterKeys()
    local keys = {}
    for k in pairs(self:GetCharacters()) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end
