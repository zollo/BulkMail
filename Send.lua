-- Send.lua: Mail sending methods and destination management

local mod = BulkMail
local del = mod.del
local L   = mod._L

local PickupContainerItem = mod._PickupContainerItem

local suffix = mod.SUFFIX_CHAR  -- tracks subject suffix to ensure mail uniqueness

-- Sends the current item in the SendMailItemButton to the currently-specified
-- destination (or the default if that field is blank), then supplies items and
-- destinations from BulkMail's send queue and sends them.
function mod:Send(cod)
    if GetSendMailItem(1) then
        SendMailNameEditBox:SetText(
            (mod.sendDest ~= '' and mod.sendDest
             or mod._rulesCacheDest(GetSendMailItemLink(1))
             or self.db.char.defaultDestination) or '')
        if SendMailNameEditBox:GetText() ~= '' then
            if #suffix > 10 then suffix = mod.SUFFIX_CHAR else suffix = suffix..mod.SUFFIX_CHAR end
            return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
        elseif not self.db.char.defaultDestination then
            self:Print(L["No default destination set."])
            self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
            self:StopBulkSend()
            return
        end
        return
    end
    if mod.destSendCache and next(mod.destSendCache) then
        local dest, bagslots = next(mod.destSendCache)
        local bag, slot
        for i = 1, math.min(self.db.char.attachMulti and ATTACHMENTS_MAX_SEND or 1, #bagslots) do
            bag, slot = unpack(table.remove(bagslots))
            PickupContainerItem(bag, slot)
            ClickSendMailItemButton(i)
        end
        mod.destSendCache[dest] = next(bagslots) and bagslots or del(bagslots)

        SendMailSubjectEditBox:SetText(SendMailSubjectEditBox:GetText()..suffix)
        if cod then
            SendMailSendMoneyButton:SetChecked(nil)
            MoneyInputFrame_SetCopper(SendMailMoney, cod)
        end
        -- Items are now in the mail slots; set destination and trigger the actual send
        mod.sendDest = dest
        SendMailNameEditBox:SetText(dest)
        if #suffix > 10 then suffix = mod.SUFFIX_CHAR else suffix = suffix..mod.SUFFIX_CHAR end
        return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
    else
        SendMailNameEditBox:SetText('')
        mod.sendDest = ''
        self._sendingBulk = false
        return mod._sendCacheCleanup()
    end
end

function mod:StopBulkSend()
    mod.cacheLock = false
    self._sendingBulk = false
    self._sendCOD = nil
end

-- Send the container slot's item immediately to its autosend destination
-- (or the default destination if no destination is specified).
-- Triggered by Ctrl-Shift-LeftClick on an item in the bags.
function mod:QuickSend(bag, slot)
    bag, slot = slot and bag or bag:GetParent():GetID(), slot or bag:GetID()  -- convert to (bag, slot) if called as (frame)
    if bag and slot then
        PickupContainerItem(bag, slot)
        ClickSendMailItemButton()
        if GetSendMailItem(1) then
            local dest = SendMailNameEditBox:GetText()
            if dest == '' then
                SendMailNameEditBox:SetText(
                    mod._rulesCacheDest(GetSendMailItemLink(1))
                    or self.db.char.defaultDestination or '')
            end
            if SendMailNameEditBox:GetText() ~= '' then
                return self.hooks[SendMailMailButton].OnClick(SendMailMailButton)
            elseif not self.db.char.defaultDestination then
                self:Print(L["No default destination set."])
                self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
            end
        end
    else
        self:Print(L["Cannot determine the item clicked."])
    end
end

function mod:AddDestination(dest)
    local _ = mod.autoSendRules[dest]  -- trigger the table creation by accessing it
    mod.destCache[dest] = true
    table.insert(mod.reverseDestCache, dest)
    mod.rulesAltered = true
end

function mod:RemoveDestination(dest)
    mod.autoSendRules[dest] = nil
    mod.destCache[dest] = nil
    for i = 1, #mod.reverseDestCache do
        if mod.reverseDestCache[i] == dest then
            table.remove(mod.reverseDestCache, i)
            mod.rulesAltered = true
            break
        end
    end
end
