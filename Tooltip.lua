local ADDON_NAME = ...
local jalt = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Tooltip = {}
jalt.Tooltip = Tooltip

local LOCATION_COLORS = {
    bags        = "|cffaaaaaa",
    bank        = "|cff7fbfff",
    guildbank   = "|cffff80ff",
    warbandbank = "|cffffd200",
    equipped    = "|cff80ff80",
}

local function FormatRight(entry)
    local color = LOCATION_COLORS[entry.location] or "|cffffffff"
    return string.format("%s%s|r |cffffffffx%d|r", color, entry.locDetail, entry.count)
end

local seenForCurrentTooltip

local function ProcessTooltip(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip and tooltip ~= EmbeddedItemTooltip then
        return
    end
    if not data or not data.id then return end

    local locations = jalt.Data and jalt.Data:GetLocationsForItem(data.id)
    if not locations or #locations == 0 then return end

    seenForCurrentTooltip = seenForCurrentTooltip or {}
    if seenForCurrentTooltip[tooltip] == data.id then
        return
    end
    seenForCurrentTooltip[tooltip] = data.id

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff7fbfffjalt|r")

    local total = 0
    for _, entry in ipairs(locations) do
        total = total + (entry.count or 1)
        tooltip:AddDoubleLine(entry.charKey, FormatRight(entry), 1, 1, 1)
    end

    if #locations > 1 then
        tooltip:AddDoubleLine(" ", "|cffffd200total x" .. total .. "|r")
    end
end

local function HookTooltipCleared(tooltip)
    if not tooltip then return end
    if tooltip.__jaltClearedHooked then return end
    tooltip.__jaltClearedHooked = true
    tooltip:HookScript("OnTooltipCleared", function(self)
        if seenForCurrentTooltip then
            seenForCurrentTooltip[self] = nil
        end
    end)
    tooltip:HookScript("OnHide", function(self)
        if seenForCurrentTooltip then
            seenForCurrentTooltip[self] = nil
        end
    end)
end

function Tooltip:Init()
    if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then
        jalt:Print("|cffff8080[jalt]|r TooltipDataProcessor unavailable; tooltip lines disabled.")
        return
    end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ProcessTooltip)

    HookTooltipCleared(GameTooltip)
    HookTooltipCleared(ItemRefTooltip)
    if EmbeddedItemTooltip then HookTooltipCleared(EmbeddedItemTooltip) end
    if ShoppingTooltip1 then HookTooltipCleared(ShoppingTooltip1) end
    if ShoppingTooltip2 then HookTooltipCleared(ShoppingTooltip2) end
end
