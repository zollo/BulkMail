-- Core.lua: Addon object creation, library handles, compat shims, shared constants

BulkMail = LibStub("AceAddon-3.0"):NewAddon("BulkMail", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceHook-3.0")

local mod = BulkMail

local VERSION = " @project-version@"
mod._VERSION = VERSION

local L        = LibStub("AceLocale-3.0"):GetLocale("BulkMail", false)
local pt       = LibStub("LibPeriodicTable-3.1")
local abacus   = LibStub("LibAbacus-3.0")
local gratuity = LibStub("LibGratuity-3.0")
local QTIP     = LibStub("LibQTip-1.0")
local LD       = LibStub("LibDropdown-1.0")
local AC       = LibStub("AceConfig-3.0")
local ACD      = LibStub("AceConfigDialog-3.0")
local ACONS    = LibStub("AceConsole-3.0")
local DB       = LibStub("AceDB-3.0")
local LDB      = LibStub("LibDataBroker-1.1", true)
local MagicUtil = LibStub("LibMagicUtil-1.0")

mod.L = L

-- Expose library handles for other modules
mod._L         = L
mod._pt        = pt
mod._abacus    = abacus
mod._gratuity  = gratuity
mod._QTIP      = QTIP
mod._LD        = LD
mod._AC        = AC
mod._ACD       = ACD
mod._DB        = DB
mod._LDB       = LDB
mod._MagicUtil = MagicUtil

-- Named color constants
mod.COLOR_GOLD   = "ffd200"
mod.COLOR_YELLOW = "ffff00"
mod.COLOR_GREEN  = "80ff80"
mod.COLOR_RED    = "ff0000"
mod.COLOR_CYAN   = "00d2ff"
mod.COLOR_WHITE  = "ffffff"
mod.COLOR_ITEM   = "fadfa8"
mod.COLOR_PT31   = "c8c8ff"

-- Shared constants
mod.SUFFIX_CHAR          = "\32"
mod.NUM_LE_ITEM_CLASSES  = _G.NUM_LE_ITEM_CLASSES or _G.NUM_LE_ITEM_CLASSS or 19

-- Color utility (used throughout all GUI modules)
local function color(text, colorCode)
    return string.format("|cff%s%s|r", colorCode, text)
end
mod._color = color

-- Utility: get numeric item id from an item link or number
local function linkToId(itemLink)
    return type(itemLink) == 'number' and itemLink or tonumber(string.match(itemLink, "|H[^:]+:(%d+)"))
end
mod._linkToId = linkToId

-- Shared QTip close helper used by both GUI modules
local function _QTipClose(tooltip)
    if not tooltip then return end
    tooltip:EnableMouse(false)
    tooltip:SetScript("OnDragStart", nil)
    tooltip:SetScript("OnDragStop", nil)
    tooltip:SetMovable(false)
    tooltip:RegisterForDrag()
    tooltip:SetFrameStrata("TOOLTIP")
    QTIP:Release(tooltip)
end
mod._QTipClose = _QTipClose

-- Shared tooltip cell helper used by both GUI modules
local function _addIndentedCell(tooltip, text, indentation, func, arg)
    local y, x = tooltip:AddLine()
    tooltip:SetCell(y, x, text, tooltip:GetFont(), "LEFT", 1, nil, indentation)
    if func then
        tooltip:SetLineScript(y, "OnMouseUp", func, arg)
    end
    return y, x
end
mod._addIndentedCell = _addIndentedCell

-- Compat shims for API differences across WoW versions
local function CompatGetAuctionItemSubClasses(i)
    return {GetAuctionItemSubClasses(i)}
end

mod._GetAddOnInfo           = GetAddOnInfo or C_AddOns.GetAddOnInfo
mod._GetAddOnMetadata       = GetAddOnMetadata or C_AddOns.GetAddOnMetadata
mod._GetAuctionItemSubClasses = (C_AuctionHouse and C_AuctionHouse.GetAuctionItemSubClasses) or CompatGetAuctionItemSubClasses
mod._GetNumAddOns           = GetNumAddOns or C_AddOns.GetNumAddOns
mod._LoadAddOn              = LoadAddOn or C_AddOns.LoadAddOn

-- Dragonlands / C_Container compat
local GetContainerItemInfo = GetContainerItemInfo
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumSlots = GetContainerNumSlots
local PickupContainerItem  = PickupContainerItem

if not GetContainerNumSlots then
    -- Reagent bag is bag #5
    NUM_BAG_SLOTS = NUM_BAG_SLOTS + 1

    GetContainerNumSlots = C_Container.GetContainerNumSlots
    GetContainerItemLink = C_Container.GetContainerItemLink
    GetContainerItemInfo = function(bag, slot)
        local item = C_Container.GetContainerItemInfo(bag, slot)
        if item == nil then return end
        return item.iconFileID, item.stackCount, item.isLocked, item.quality, item.isReadable, item.hasLoot,
               item.hyperLink, item.isFiltered, item.hasNoValue, item.itemID, item.isBound
    end
    PickupContainerItem = C_Container.PickupContainerItem
end

mod._GetContainerItemInfo = GetContainerItemInfo
mod._GetContainerItemLink = GetContainerItemLink
mod._GetContainerNumSlots = GetContainerNumSlots
mod._PickupContainerItem  = PickupContainerItem

-- Initialize shared addon state (DB-dependent state is set in Config.lua OnInitialize)
mod.sendCache     = {}
mod.destSendCache = {}
mod.cacheLock     = false
mod.sendDest      = ''
mod.rulesAltered  = true
mod.numItems      = 0
