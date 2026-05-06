-- SendQueue.lua: Send-cache management, bag iteration, item mailability, send cost

local mod = BulkMail
local new, del = mod.new, mod.del
local gratuity = mod._gratuity
local linkToId = mod._linkToId

local GetContainerItemInfo = mod._GetContainerItemInfo
local GetContainerItemLink = mod._GetContainerItemLink
local GetContainerNumSlots = mod._GetContainerNumSlots
local PickupContainerItem  = mod._PickupContainerItem

local L = mod._L

-- Bag iterator, shamelessly stolen from PeriodicTable-2.0 (written by Tekkub)
local iterbag, iterslot
local function iter()
    if iterslot > GetContainerNumSlots(iterbag) then iterbag, iterslot = iterbag + 1, 1 end
    if iterbag > NUM_BAG_SLOTS then return end
    for b = iterbag, NUM_BAG_SLOTS do
        for s = iterslot, GetContainerNumSlots(b) do
            iterslot = s + 1
            local link = GetContainerItemLink(b, s)
            if link then return b, s, link end
        end
        iterbag, iterslot = b + 1, 1
    end
end

local function bagIter()
    iterbag, iterslot = 0, 1
    return iter
end

-- Returns the frame associated with bag, slot
local function getBagSlotFrame(bag, slot)
    if bag >= 0 and bag < NUM_CONTAINER_FRAMES and slot > 0 then
        local bagslots = GetContainerNumSlots(bag)
        if bagslots >= slot then
            return _G["ContainerFrame" .. (bag + 1) .. "Item" .. (bagslots - slot + 1)]
        end
    end
end

-- Shades or unshades the given bag slot
local function shadeBagSlot(bag, slot, shade)
    local frame = getBagSlotFrame(bag, slot)
    if frame ~= nil then
        SetItemButtonDesaturated(frame, shade)
    end
end

-- Updates the "Postage" field in the Send Mail frame to reflect the total
-- price of all the items that BulkMail will send.
local function updateSendCost()
    if mod.sendCache and next(mod.sendCache) then
        local basePrice = 0
        for slot = 1, 8 do
            if GetSendMailItem(slot) ~= nil then
                basePrice = GetSendMailPrice()
                break
            end
        end
        MoneyFrame_Update('SendMailCostMoneyFrame', basePrice + 30 * mod.numItems)
    else
        MoneyFrame_Update('SendMailCostMoneyFrame', GetSendMailPrice())
    end
end

-- Tooltip text search helpers used by isItemMailable
local function findPattern(str, pattern)
    return string.find(str, pattern)
end

local function findExact(str, pattern)
    if (str == pattern) then
        return string.find(str, pattern)
    end
end

local function simpleFind(tt, exact, text)
    if not tt or not tt.lines then
        return
    end
    local searchFunction = exact and findExact or findPattern
    for _, data in ipairs(tt.lines) do
        if data.args then
            for _, field in ipairs(data.args) do
                if field.field == "leftText" then
                    if searchFunction(field.stringVal, text) then
                        return true
                    end
                    break
                end
            end
        elseif data.leftText then
            if searchFunction(data.leftText, text) then
                return true
            end
        end
    end
end

local function multiFind(tt, exact, t1, t2, t3, t4, t5, t6)
    local found = simpleFind(tt, exact, t1)
    if not found and t2 then
        return multiFind(tt, exact, t2, t3, t4, t5, t6)
    end
    return found
end

local function isItemMailable(bag, slot)
    if _G.C_TooltipInfo == nil then
        local item = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if item then
            return not C_Item.IsBound(item)
        end
        gratuity:SetBagItem(bag, slot)
        return not gratuity:MultiFind(2, 7, false, false, ITEM_SOULBOUND, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP)
                or gratuity:Find(ITEM_BIND_ON_EQUIP, 2, 7, false, false, true)
    end
    local tt = C_TooltipInfo.GetBagItem(bag, slot)
    return not (multiFind(tt, false, ITEM_BIND_QUEST, ITEM_CONJURED, ITEM_BIND_ON_PICKUP)
                or simpleFind(tt, true, ITEM_SOULBOUND))
            or simpleFind(tt, true, ITEM_BIND_ON_EQUIP)
end

-- Add a container slot to BulkMail's send queue.
local function sendCacheAdd(bag, slot, squelch)
    -- convert to (bag, slot, squelch) if called as (frame, squelch)
    if type(slot) ~= 'number' then
        bag, slot, squelch = bag:GetParent():GetID(), bag:GetID(), slot
    end
    local didAdd = false
    if GetContainerItemInfo(bag, slot) and not (mod.sendCache[bag] and mod.sendCache[bag][slot]) then
        if isItemMailable(bag, slot) then
            mod.sendCache[bag] = mod.sendCache[bag] or new()
            mod.sendCache[bag][slot] = true
            mod.numItems = mod.numItems + 1
            shadeBagSlot(bag, slot, true)
            if not squelch then mod:RefreshSendQueueGUI() end
            SendMailFrame_CanSend()
            didAdd = true
        elseif not squelch then
            mod:Print(string.format(L["Item cannot be mailed: %s."], GetContainerItemLink(bag, slot)))
        end
    end
    if not squelch and didAdd then
        updateSendCost()
    end
    return didAdd
end

-- Remove a container slot from BulkMail's send queue.
local function sendCacheRemove(bag, slot, isBulk)
    bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
    if mod.sendCache and mod.sendCache[bag] then
        if mod.sendCache[bag][slot] then
            mod.sendCache[bag][slot] = nil
            mod.numItems = mod.numItems - 1
            shadeBagSlot(bag, slot, false)
        end
        if not next(mod.sendCache[bag]) then mod.sendCache[bag] = del(mod.sendCache[bag]) end
    end
    if not isBulk then
        mod:RefreshSendQueueGUI()
        updateSendCost()
        SendMailFrame_CanSend()
    end
end

-- Toggle all instances of the same item across bags in/out of the send queue.
local function bulkToggleBagItem(bag, slot, itemLink)
    itemLink = itemLink or GetContainerItemLink(bag, slot)
    if not itemLink then return end
    local itemId = linkToId(itemLink)
    local shouldRemove = mod.sendCache and mod.sendCache[bag] and mod.sendCache[bag][slot]
    mod:Print(string.format(L["Attempting to %s all %s."], shouldRemove and L["remove"] or L["add"], itemLink))
    for addlBag, addlSlot, item in bagIter() do
        if linkToId(item) == itemId then
            if shouldRemove then
                sendCacheRemove(addlBag, addlSlot, true)
            elseif not sendCacheAdd(addlBag, addlSlot, true) then
                mod:Print(string.format(L["Item cannot be mailed: %s."], GetContainerItemLink(addlBag, addlSlot)))
            end
        end
    end
    mod:RefreshSendQueueGUI()
    updateSendCost()
    SendMailFrame_CanSend()
end

-- Toggle a container slot's presence in BulkMail's send queue.
local function sendCacheToggle(bag, slot)
    bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
    local result
    if mod.sendCache and mod.sendCache[bag] and mod.sendCache[bag][slot] then
        result = sendCacheRemove(bag, slot)
    else
        result = sendCacheAdd(bag, slot)
    end
    return result
end

-- Removes all entries in BulkMail's send queue.
-- If passed with the argument 'true', will only remove the entries created by
-- BulkMail (used for refreshing the list as the destination changes without
-- clearing the items the user has added manually this session).
local function sendCacheCleanup(autoOnly)
    if mod.sendCache then
        for bag, slots in pairs(mod.sendCache) do
            for slot in pairs(slots) do
                local item = GetContainerItemLink(bag, slot)
                if autoOnly ~= true or mod._rulesCacheDest(item) then
                    sendCacheRemove(bag, slot, true)
                end
            end
        end
    end
    mod.cacheLock = false
    mod:RefreshSendQueueGUI()
    updateSendCost()
    SendMailFrame_CanSend()
end

-- Populate BulkMail's send queue with container slots holding items matching
-- the autosend rules for the current destination (or any destination if blank).
local function sendCacheBuild(dest)
    if not mod.cacheLock then
        sendCacheCleanup(true)
        local destLower = dest and dest:lower()
        -- Check destCache case-insensitively
        local destHasRules = false
        if dest ~= '' then
            for d in pairs(mod.destCache) do
                if d:lower() == destLower then
                    destHasRules = true
                    break
                end
            end
        end
        if mod.db.char.isSink or dest ~= '' and not destHasRules then
            -- no need to scan if this character is a sink or the destination has no rules set
            mod:RefreshSendQueueGUI()
            return
        end

        for bag, slot, item in bagIter() do
            local target = mod._rulesCacheDest(item)
            if target then
                if dest == '' or target:lower() == destLower then
                    sendCacheAdd(bag, slot, true)
                end
            end
        end
    end
    mod:RefreshSendQueueGUI()
end

-- Organize the send queue by recipient to reduce fragmentation of multi-item mails.
local function organizeSendCache()
    mod.destSendCache = mod.deepDel(mod.destSendCache)
    local dest
    for bag, slots in pairs(mod.sendCache) do
        for slot in pairs(slots) do
            dest = mod.sendDest ~= '' and mod.sendDest
                    or mod._rulesCacheDest(GetContainerItemLink(bag, slot))
                    or mod.db.char.defaultDestination
            if dest then
                mod.destSendCache = mod.destSendCache or new()
                mod.destSendCache[dest] = mod.destSendCache[dest] or new()
                table.insert(mod.destSendCache[dest], new(bag, slot))
            else
                mod:Print(L["No default destination set."])
                mod:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
            end
        end
    end
end

mod._sendCacheAdd      = sendCacheAdd
mod._sendCacheRemove   = sendCacheRemove
mod._sendCacheToggle   = sendCacheToggle
mod._sendCacheCleanup  = sendCacheCleanup
mod._sendCacheBuild    = sendCacheBuild
mod._organizeSendCache = organizeSendCache
mod._updateSendCost    = updateSendCost
mod._bagIter           = bagIter
mod._isItemMailable    = isItemMailable
mod._bulkToggleBagItem = bulkToggleBagItem
mod._shadeBagSlot      = shadeBagSlot
