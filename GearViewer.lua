local ADDON_NAME = ...
local jalt = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local AceGUI = LibStub("AceGUI-3.0")

local GearViewer = {}
jalt.GearViewer = GearViewer

local Window = {}
jalt.Window = Window

local frame
local currentChar

local GEAR_SLOT_ORDER = { 1, 2, 3, 15, 5, 4, 9, 6, 7, 8, 16, 17, 18, 19, 10, 11, 12, 13, 14 }
local GEAR_OPTIONAL_SLOTS = { [4] = true, [18] = true, [19] = true }  -- Shirt, Ranged, Tabard

local PROF_SLOT_ORDER = { 20, 21, 22, 23, 24, 25, 26, 27, 28 }
local PROF_OPTIONAL_SLOTS = {}  -- all profession slots count toward avg/min

local function ResolveIlvl(item)
    if not item then return nil end
    if item.ilvl then return item.ilvl end
    if item.itemLink and C_Item and C_Item.GetDetailedItemLevelInfo then
        local v = C_Item.GetDetailedItemLevelInfo(item.itemLink)
        if v then item.ilvl = v end
        return v
    end
    return nil
end

local function ComputeIlvlSummary(equipped, slotOrder, optionalSlots)
    if not equipped then return nil end
    local count, sum, minIlvl, minSlot = 0, 0, nil, nil
    for _, slotID in ipairs(slotOrder) do
        if not optionalSlots[slotID] then
            local ilvl = ResolveIlvl(equipped[slotID])
            if ilvl then
                count = count + 1
                sum = sum + ilvl
                if not minIlvl or ilvl < minIlvl then
                    minIlvl, minSlot = ilvl, slotID
                end
            end
        end
    end
    if count == 0 then return nil end
    return { count = count, avg = sum / count, min = minIlvl, minSlot = minSlot }
end

local function ClassColor(class)
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    end
    return "|cffffffff"
end

local function FormatCharLabel(charKey, char, slotOrder, optionalSlots)
    local color = ClassColor(char and char.class)
    local lvl = char and char.level and (" (" .. char.level .. ")") or ""
    local summary = char and ComputeIlvlSummary(char.equipped, slotOrder, optionalSlots)
    local ilvlPart = ""
    if summary then
        ilvlPart = string.format("  |cffffd200%d|r|cffaaaaaa/%d|r",
            math.floor(summary.avg + 0.5), summary.min)
    end
    return color .. charKey .. lvl .. "|r" .. ilvlPart
end

local function PickDefaultCharKey()
    local current = jalt.GetCharKey()
    if current and jalt.Data:GetCharacters()[current] then
        return current
    end
    local keys = jalt.Data:GetSortedCharacterKeys()
    return keys[1]
end

local function MakeSlotWidget(slotID, equipped)
    local icon = AceGUI:Create("Icon")
    icon:SetImageSize(32, 32)
    icon:SetWidth(140)

    local slotName = jalt.Data.EQUIPMENT_SLOTS[slotID] or ("Slot " .. slotID)

    if equipped and equipped.itemLink then
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(equipped.itemLink)
        if texture then icon:SetImage(texture) end
        local ilvl = ResolveIlvl(equipped)
        icon:SetLabel(slotName .. ": |cffffd200" .. (ilvl or "?") .. "|r")
        icon:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(equipped.itemLink)
            GameTooltip:Show()
        end)
        icon:SetCallback("OnLeave", function() GameTooltip:Hide() end)
    else
        icon:SetLabel(slotName .. ": |cff808080-|r")
    end

    return icon
end

local function RenderGear(container, charKey, slotOrder, optionalSlots)
    container:ReleaseChildren()

    local chars = jalt.Data:GetCharacters()
    local keys = jalt.Data:GetSortedCharacterKeys()

    local dropdown = AceGUI:Create("Dropdown")
    dropdown:SetLabel("Character")
    local list, order = {}, {}
    for _, k in ipairs(keys) do
        list[k] = FormatCharLabel(k, chars[k], slotOrder, optionalSlots)
        table.insert(order, k)
    end
    dropdown:SetList(list, order)
    dropdown:SetValue(charKey or order[1])
    dropdown:SetWidth(360)
    dropdown:SetCallback("OnValueChanged", function(_, _, key)
        currentChar = key
        RenderGear(container, key, slotOrder, optionalSlots)
    end)
    container:AddChild(dropdown)

    local heading = AceGUI:Create("Heading")
    heading:SetText(" ")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local key = charKey or order[1]
    local char = key and chars[key]
    if not char then
        local label = AceGUI:Create("Label")
        label:SetText("No character data.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local summary = ComputeIlvlSummary(char.equipped, slotOrder, optionalSlots)
    local summaryLabel = AceGUI:Create("Label")
    if summary then
        local minSlotName = jalt.Data.EQUIPMENT_SLOTS[summary.minSlot] or ("Slot " .. summary.minSlot)
        summaryLabel:SetText(string.format(
            "|cffffd200Avg|r %.1f   |cffffd200Min|r %d  |cffaaaaaa(%s)|r",
            summary.avg, summary.min, minSlotName
        ))
    else
        summaryLabel:SetText("|cffaaaaaaNo equipped item levels yet.|r")
    end
    summaryLabel:SetFullWidth(true)
    container:AddChild(summaryLabel)

    local grid = AceGUI:Create("SimpleGroup")
    grid:SetLayout("Flow")
    grid:SetFullWidth(true)
    container:AddChild(grid)

    for _, slotID in ipairs(slotOrder) do
        grid:AddChild(MakeSlotWidget(slotID, char.equipped and char.equipped[slotID]))
    end
end

function GearViewer:Render(container)
    RenderGear(container, currentChar or PickDefaultCharKey(), GEAR_SLOT_ORDER, GEAR_OPTIONAL_SLOTS)
end

local ProfessionGearViewer = {}
jalt.ProfessionGearViewer = ProfessionGearViewer

function ProfessionGearViewer:Render(container)
    RenderGear(container, currentChar or PickDefaultCharKey(), PROF_SLOT_ORDER, PROF_OPTIONAL_SLOTS)
end

local function SelectGroup(container, _, group)
    container:ReleaseChildren()
    local inner = AceGUI:Create("ScrollFrame")
    inner:SetLayout("List")
    inner:SetFullWidth(true)
    inner:SetFullHeight(true)
    container:AddChild(inner)

    if group == "gear" then
        GearViewer:Render(inner)
    elseif group == "profgear" then
        ProfessionGearViewer:Render(inner)
    elseif group == "currency" and jalt.CurrencyViewer then
        jalt.CurrencyViewer:Render(inner)
    end
end

function Window:Toggle()
    if frame and frame.frame and frame.frame:IsShown() then
        frame:Release()
        frame = nil
        return
    end
    self:Show()
end

function Window:Show()
    if frame then
        frame:Release()
        frame = nil
    end
    frame = AceGUI:Create("Frame")
    frame:SetTitle("jalt")
    frame:SetStatusText("/jalt search <pattern> to search items")
    frame:SetLayout("Fill")
    frame:SetWidth(620)
    frame:SetHeight(560)
    frame:SetCallback("OnClose", function(widget)
        widget:Release()
        frame = nil
    end)

    if frame.frame then
        _G["JaltMainWindow"] = frame.frame
        local present = false
        for _, n in ipairs(UISpecialFrames) do
            if n == "JaltMainWindow" then present = true; break end
        end
        if not present then table.insert(UISpecialFrames, "JaltMainWindow") end
    end

    local tabs = AceGUI:Create("TabGroup")
    tabs:SetLayout("Fill")
    tabs:SetTabs({
        { text = "Gear",            value = "gear" },
        { text = "Profession Gear", value = "profgear" },
        { text = "Currency",        value = "currency" },
    })
    tabs:SetCallback("OnGroupSelected", SelectGroup)
    frame:AddChild(tabs)
    tabs:SelectTab("gear")
end
