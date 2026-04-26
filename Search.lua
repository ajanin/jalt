local ADDON_NAME = ...
local jalt = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local AceGUI = LibStub("AceGUI-3.0")

local Search = {}
jalt.Search = Search

local function GetItemName(itemID, itemLink)
    if itemLink then
        local n = GetItemInfo(itemLink)
        if n then return n end
    end
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if n then return n end
    end
    if itemID then
        local n = GetItemInfo(itemID)
        if n then return n end
    end
    return nil
end

local function MatchesPattern(name, pattern)
    if not name or not pattern then return false end
    local ok, result = pcall(string.find, name:lower(), pattern:lower())
    if not ok then return false end
    return result ~= nil
end

local frame

local function ReleaseFrame()
    if frame then
        frame:Release()
        frame = nil
    end
end

local function BuildResults(pattern)
    local results = {}
    local nameCache = {}

    for itemID, entries in pairs(jalt.Data.itemIndex) do
        local name = nameCache[itemID]
        if name == nil then
            name = GetItemName(itemID, entries[1] and entries[1].itemLink) or false
            nameCache[itemID] = name
        end
        if name and MatchesPattern(name, pattern) then
            for _, entry in ipairs(entries) do
                table.insert(results, {
                    name      = name,
                    itemID    = itemID,
                    itemLink  = entry.itemLink,
                    charKey   = entry.charKey,
                    locDetail = entry.locDetail,
                    location  = entry.location,
                    count     = entry.count,
                })
            end
        end
    end

    table.sort(results, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.charKey ~= b.charKey then return a.charKey < b.charKey end
        return (a.locDetail or "") < (b.locDetail or "")
    end)

    return results
end

local function ShowResults(pattern, results)
    ReleaseFrame()

    frame = AceGUI:Create("Frame")
    frame:SetTitle("jalt search: " .. pattern)
    frame:SetStatusText(#results .. " result" .. (#results == 1 and "" or "s"))
    frame:SetLayout("Fill")
    frame:SetWidth(640)
    frame:SetHeight(440)
    frame:SetCallback("OnClose", function() ReleaseFrame() end)

    if frame.frame then
        _G["JaltSearchWindow"] = frame.frame
        local present = false
        for _, n in ipairs(UISpecialFrames) do
            if n == "JaltSearchWindow" then present = true; break end
        end
        if not present then table.insert(UISpecialFrames, "JaltSearchWindow") end
    end

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    frame:AddChild(scroll)

    if #results == 0 then
        local label = AceGUI:Create("Label")
        label:SetText("No matches.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
        return
    end

    for _, row in ipairs(results) do
        local label = AceGUI:Create("InteractiveLabel")
        local display = string.format(
            "%s  |cffaaaaaa|||r  %s  |cffaaaaaa|||r  %s |cffffffffx%d|r",
            row.itemLink or row.name,
            row.charKey,
            row.locDetail or "",
            row.count or 1
        )
        label:SetText(display)
        label:SetFullWidth(true)
        label:SetCallback("OnEnter", function(widget)
            if not row.itemLink then return end
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(row.itemLink)
            GameTooltip:Show()
        end)
        label:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        label:SetCallback("OnClick", function(_, _, button)
            if button == "LeftButton" and IsModifiedClick("CHATLINK") and row.itemLink then
                ChatEdit_InsertLink(row.itemLink)
            end
        end)
        scroll:AddChild(label)
    end
end

function Search:Run(pattern)
    pattern = pattern and pattern:match("^%s*(.-)%s*$") or ""
    if pattern == "" then
        jalt:Print("usage: /jalt search <pattern>")
        return
    end

    local results = BuildResults(pattern)
    ShowResults(pattern, results)
end
