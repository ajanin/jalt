local ADDON_NAME = ...

local jalt = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
_G.jalt = jalt

jalt.DEBUG = false

function jalt:Debug(...)
    if self.DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fbfff[jalt]|r " .. table.concat({tostringall(...)}, " "))
    end
end

local DB_DEFAULTS = {
    global = {
        characters = {},
        guildBank = {},
        warbandBank = {},
    },
}

local function GetCharKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if not name or not realm then return nil end
    return realm .. " - " .. name
end

jalt.GetCharKey = GetCharKey

function jalt:GetCurrentCharacter()
    local key = GetCharKey()
    if not key then return nil, nil end
    local char = self.db.global.characters[key]
    if not char then
        char = {
            class      = nil,
            level      = nil,
            faction    = nil,
            lastSeen   = 0,
            bags       = {},
            bank       = {},
            equipped   = {},
            currencies = {},
        }
        self.db.global.characters[key] = char
    end
    return key, char
end

local BAG_DEBOUNCE_SECONDS = 0.5
local pendingBagScan = false

local function ScheduleBagScan()
    if pendingBagScan then return end
    pendingBagScan = true
    C_Timer.After(BAG_DEBOUNCE_SECONDS, function()
        pendingBagScan = false
        if jalt.Data then
            jalt.Data:ScanBags()
            jalt.Data:RebuildItemIndex()
        end
    end)
end

function jalt:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("jaltDB", DB_DEFAULTS, true)

    self:RegisterChatCommand("jalt", "OnSlashCommand")

    if self.Tooltip then self.Tooltip:Init() end
end

function jalt:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
    self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:RegisterEvent("BAG_UPDATE", "OnBagUpdate")
    self:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnBankSlotsChanged")
    self:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "OnAccountBankSlotsChanged")
    self:RegisterEvent("BANK_TABS_CHANGED", "OnBankTabsChanged")
    self:RegisterEvent("GUILDBANKFRAME_OPENED", "OnGuildBankOpened")
    self:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED", "OnGuildBankSlotsChanged")
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyUpdate")

    if IsLoggedIn() then
        self:OnPlayerLogin()
    end
end

function jalt:OnPlayerLogin()
    local key, char = self:GetCurrentCharacter()
    if not key then return end

    char.class   = select(2, UnitClass("player"))
    char.level   = UnitLevel("player")
    char.faction = UnitFactionGroup("player")
    char.lastSeen = time()

    if self.Data then
        self.Data:ScanBags()
        self.Data:ScanEquipment()
        self.Data:ScanCurrencies()
        self.Data:RebuildItemIndex()
        C_Timer.After(5, function()
            if jalt.Data then
                jalt.Data:ScanEquipment()
                jalt.Data:RebuildItemIndex()
            end
        end)
    end
end

function jalt:OnPlayerLogout()
    local _, char = self:GetCurrentCharacter()
    if char then char.lastSeen = time() end
end

function jalt:OnBagUpdate(_, bagID)
    ScheduleBagScan()
    if Enum.BagIndex and Enum.BagIndex.AccountBankTab_1
       and bagID and bagID >= Enum.BagIndex.AccountBankTab_1
       and bagID <= Enum.BagIndex.AccountBankTab_5
       and self.Data then
        self.Data:ScanWarbandBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnEquipmentChanged()
    if self.Data then
        self.Data:ScanEquipment()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnBankOpened()
    if self.Data then
        self.Data:ScanBank()
        self.Data:ScanWarbandBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnBankSlotsChanged()
    if self.Data then
        self.Data:ScanBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnAccountBankSlotsChanged()
    if self.Data then
        self.Data:ScanWarbandBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnBankTabsChanged()
    if self.Data then
        self.Data:ScanBank()
        self.Data:ScanWarbandBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnGuildBankOpened()
    if self.Data then
        self.Data:ScanGuildBank()
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnGuildBankSlotsChanged()
    if self.Data and GetCurrentGuildBankTab then
        self.Data:ScanGuildBankTab(GetCurrentGuildBankTab())
        self.Data:RebuildItemIndex()
    end
end

function jalt:OnCurrencyUpdate()
    if self.Data then
        self.Data:ScanCurrencies()
    end
end

function jalt:OnSlashCommand(input)
    input = input and input:match("^%s*(.-)%s*$") or ""
    if input == "" then
        if self.Window then self.Window:Toggle() end
        return
    end

    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "search" then
        if self.Search then self.Search:Run(rest) end
    elseif cmd == "debug" then
        self.DEBUG = not self.DEBUG
        self:Print("debug = " .. tostring(self.DEBUG))
    elseif cmd == "rescan" then
        if self.Data then
            self.Data:ScanBags()
            self.Data:ScanEquipment()
            self.Data:ScanCurrencies()
            self.Data:RebuildItemIndex()
            self:Print("rescanned current character")
        end
    elseif cmd == "help" or cmd == "?" then
        self:Print("|cff7fbfffjalt|r commands:")
        self:Print("  /jalt              - open the main window")
        self:Print("  /jalt search <pat> - search items by Lua pattern")
        self:Print("  /jalt rescan       - force rescan of current character")
        self:Print("  /jalt debug        - toggle debug output")
    else
        if self.Search then self.Search:Run(input) end
    end
end
