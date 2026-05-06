-- Compat.lua: Migration helpers for converting old BulkMail2 / Ace2 configuration
-- These functions are called once during OnInitialize and then nil-ed out.

local mod = BulkMail
local new = mod.new

local function _convertAce2ToAce3Realm(realm)
    -- This could be more elegant but I hate lua patterns so ... whatever :P
    local startPos = realm:find(" - Horde", 1, true)
    if startPos then
        return "Horde - ".. realm:sub(1, startPos-1)
    end
    startPos = realm:find(" - Alliance", 1, true)
    return "Alliance - ".. realm:sub(1, startPos-1)
end

local function _convertBulkMail2DB()
    if not BulkMail2DB then
        return
    end
    mod:Print("Converting BulkMail 2 configuration...")
    BulkMail3DB = new()
    if BulkMail2DB.realms then
        BulkMail3DB.factionrealm = new()
        for realm, data in pairs(BulkMail2DB.realms) do
            realm = _convertAce2ToAce3Realm(realm)
            BulkMail3DB.factionrealm[realm] = data
        end
    end
    if BulkMail2DB.chars then
        BulkMail3DB.char = new()
        for char, data in pairs(BulkMail2DB.chars) do
            BulkMail3DB.char[char] = data
        end
    end
end

mod._convertBulkMail2DB     = _convertBulkMail2DB
mod._convertAce2ToAce3Realm = _convertAce2ToAce3Realm
