-- RulesCache.lua: Rule-matching logic
-- Holds the local rulesCache table; exposes rulesCacheBuild and rulesCacheDest via mod.

local mod = BulkMail
local new, del, newSet, deepDel = mod.new, mod.del, mod.newSet, mod.deepDel
local pt      = mod._pt
local linkToId = mod._linkToId

-- Internal lookup table built from autoSendRules; not exposed directly
local rulesCache = {}

local function rulesCacheBuild()
    if next(rulesCache) and not mod.rulesAltered then return end
    for k in pairs(rulesCache) do
        rulesCache[k] = deepDel(rulesCache[k])
    end
    for dest, rules in pairs(mod.autoSendRules) do
        rulesCache[dest] = new()
        -- include rules
        for _, itemID in ipairs(rules.include.items) do rulesCache[dest][tonumber(itemID)] = true end
        for _, set in ipairs(rules.include.pt31Sets) do
            for itemID in pt:IterateSet(set) do rulesCache[dest][tonumber(itemID)] = true end
        end
        for _, itemTypeTable in ipairs(rules.include.itemTypes) do
            local itype, isubtype = itemTypeTable.type, itemTypeTable.subtype
            if isubtype then
                rulesCache[dest][itype] = rulesCache[dest][itype] or new()
                rulesCache[dest][itype][isubtype] = true
            else  -- need to add all subtypes individually
                if rulesCache[dest][itype] then rulesCache[dest][itype] = del(rulesCache[dest][itype]) end
                rulesCache[dest][itype] = newSet(unpack(mod.auctionItemClasses[itype]))
            end
        end
        -- exclude rules
        for _, itemID in ipairs(rules.exclude.items) do rulesCache[dest][tonumber(itemID)] = nil end
        for _, itemID in ipairs(mod.globalExclude.items) do rulesCache[dest][tonumber(itemID)] = nil end

        for _, set in ipairs(rules.exclude.pt31Sets) do
            for itemID in pt:IterateSet(set) do rulesCache[dest][itemID] = nil end
        end
        for _, set in ipairs(mod.globalExclude.pt31Sets) do
            for itemID in pt:IterateSet(set) do rulesCache[dest][itemID] = nil end
        end

        for _, itemTypeTable in ipairs(rules.exclude.itemTypes) do
            local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
            if rsubtype and rulesCache[dest][rtype] then
                rulesCache[dest][rtype][rsubtype] = nil
            else
                rulesCache[dest][rtype] = nil
            end
        end
        for _, itemTypeTable in ipairs(mod.globalExclude.itemTypes) do
            local rtype, rsubtype = itemTypeTable.type, itemTypeTable.subtype
            if rsubtype ~= rtype and rulesCache[dest][rtype] then
                rulesCache[dest][rtype][rsubtype] = nil
            else
                rulesCache[dest][rtype] = nil
            end
        end
    end
    mod.rulesAltered = false
end

-- Returns the autosend destination of an item (link or id), or nil if no rule matches.
local function rulesCacheDest(item)
    if not item then return end
    local rdest
    local itemID = linkToId(item)
    if not itemID then return end
    for _, xID in ipairs(mod.globalExclude.items) do if itemID == xID then return end end
    for _, xset in ipairs(mod.globalExclude.pt31Sets) do
        if pt:ItemInSet(itemID, xset) == true then return end
    end

    local quality   = select(3, GetItemInfo(itemID))
    local equippable = IsEquippableItem(itemID)

    if quality and ((equippable and quality < mod.db.char.minItemLevel)
            or (not equippable and quality < mod.db.char.minItemLevelMisc)) then
        return nil
    end
    local itype, isubtype = select(6, GetItemInfo(itemID))   -- old string-based lookup
    local iclass, isubclass = select(12, GetItemInfo(itemID)) -- new class-id lookup

    if C_PetJournal and not iclass then
        local name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable, isUnique, obtainable, displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if name then
            iclass, isubclass = speciesID, creatureID
            itype, isubtype = petType, name
            print(iclass, isubclass, itype, isubtype)
        end
    end
    if not itype or not iclass then
        return nil
    end
    for dest, rules in pairs(rulesCache) do
        local canddest
        if string.lower(dest) ~= string.lower(UnitName('player')) and (rules[itemID] or
                (itype and rules[itype] and rules[itype][isubtype]) or
                (iclass and rules[iclass] and rules[iclass][isubclass])) then
            canddest = dest
        end
        if canddest then
            local xrules = mod.autoSendRules[canddest].exclude
            for _, xID in ipairs(xrules.items) do if itemID == xID then canddest = nil end end
            for _, xset in ipairs(xrules.pt31Sets) do
                if pt:ItemInSet(itemID, xset) == true then canddest = nil end
            end
        end
        rdest = canddest or rdest
    end
    return rdest
end

mod._rulesCacheBuild = rulesCacheBuild
mod._rulesCacheDest  = rulesCacheDest
