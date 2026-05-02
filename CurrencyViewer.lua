local ADDON_NAME = ...
local jalt = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local AceGUI = LibStub("AceGUI-3.0")

local CurrencyViewer = {}
jalt.CurrencyViewer = CurrencyViewer

local UNGROUPED = "Other"

local function CollectGroups()
    local byID = {}
    for charKey, char in pairs(jalt.Data:GetCharacters()) do
        if char.currencies then
            for currencyID, info in pairs(char.currencies) do
                local row = byID[currencyID]
                if not row then
                    row = {
                        currencyID            = currencyID,
                        name                  = info.name,
                        icon                  = info.icon,
                        total                 = 0,
                        chars                 = {},
                        headerName            = info.headerName,
                        headerOrder           = info.headerOrder,
                        isAccountTransferable = info.isAccountTransferable,
                    }
                    byID[currencyID] = row
                else
                    row.headerName            = row.headerName            or info.headerName
                    row.headerOrder           = row.headerOrder           or info.headerOrder
                    row.isAccountTransferable = row.isAccountTransferable or info.isAccountTransferable
                end
                row.name  = row.name  or info.name
                row.icon  = row.icon  or info.icon
                row.total = row.total + (info.count or 0)
                row.chars[charKey] = info.count or 0
            end
        end
    end

    local groups = {}
    local groupByName = {}
    for _, row in pairs(byID) do
        if row.total > 0 then
            local key = row.headerName or UNGROUPED
            local g = groupByName[key]
            if not g then
                g = { name = key, order = row.headerOrder or math.huge, rows = {} }
                groupByName[key] = g
                table.insert(groups, g)
            end
            if row.headerOrder and row.headerOrder < g.order then
                g.order = row.headerOrder
            end
            table.insert(g.rows, row)
        end
    end

    -- The in-game currency list is ordered current expansion → oldest, so smaller
    -- headerOrder == newer. UNGROUPED sinks to the bottom.
    table.sort(groups, function(a, b)
        if a.name == UNGROUPED then return false end
        if b.name == UNGROUPED then return true end
        if a.order ~= b.order then return a.order < b.order end
        return (a.name or "") < (b.name or "")
    end)
    for _, g in ipairs(groups) do
        table.sort(g.rows, function(a, b) return (a.name or "") < (b.name or "") end)
        for _, row in ipairs(g.rows) do
            row.charKeys = {}
            for k in pairs(row.chars) do table.insert(row.charKeys, k) end
            table.sort(row.charKeys)
        end
    end
    return groups
end

local cachedGroups, cachedVersion = nil, nil

local function GetGroups()
    local v = jalt.Data.currenciesVersion or 0
    if cachedGroups and cachedVersion == v then return cachedGroups end
    cachedGroups = CollectGroups()
    cachedVersion = v
    return cachedGroups
end

local function FormatCurrencyHeader(row)
    local icon = row.icon and ("|T" .. row.icon .. ":16:16:0:0|t ") or ""
    local star = row.isAccountTransferable and " |cff80c0ff*|r" or ""
    return string.format("%s|cffffd200%s|r%s  |cffffffff%d|r",
        icon, row.name or ("Currency " .. row.currencyID), star, row.total)
end

local function FormatCurrencyBlock(row)
    local lines = { FormatCurrencyHeader(row) }
    for _, charKey in ipairs(row.charKeys) do
        local n = row.chars[charKey]
        if n and n > 0 then
            lines[#lines + 1] = string.format("    |cffaaaaaa%s|r  |cffffffff%d|r", charKey, n)
        end
    end
    lines[#lines + 1] = " "
    return table.concat(lines, "\n")
end

function CurrencyViewer:Render(container)
    container:ReleaseChildren()

    local groups = GetGroups()
    if #groups == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No currency data yet. Log in on a character to capture it.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    for _, g in ipairs(groups) do
        local heading = AceGUI:Create("Heading")
        heading:SetText(g.name)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        for _, row in ipairs(g.rows) do
            local block = AceGUI:Create("Label")
            block:SetText(FormatCurrencyBlock(row))
            block:SetFullWidth(true)
            block:SetFontObject(GameFontNormal)
            container:AddChild(block)
        end
    end
end
