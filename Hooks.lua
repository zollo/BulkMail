-- Hooks.lua: Event hooks and item click handlers

local mod    = BulkMail
local L      = mod._L
local abacus = mod._abacus

function mod:ContainerFrameItemButton_OnModifiedClick(frame, button)
    mod:HandleItemClick(button, frame:GetParent():GetID(), frame:GetID())
end

function mod:HandleItemClick(button, bag, slot, itemLink)
    local handled = false
    if IsControlKeyDown() and IsShiftKeyDown() then
        self:QuickSend(bag, slot, itemLink)
        handled = true
    elseif IsAltKeyDown() then
        if button == "LeftButton" then
            mod._bulkToggleBagItem(bag, slot, itemLink)
        else
            mod._sendCacheToggle(bag, slot)
        end
        handled = true
    elseif not IsShiftKeyDown() then
        mod._sendCacheRemove(bag, slot)
        handled = true
    end
    return handled
end

function mod:HandleModifiedItemClick(itemLink, itemLocation)
    if itemLocation ~= nil then
        local bag, slot = itemLocation:GetBagAndSlot()
        mod:HandleItemClick(GetMouseButtonClicked(), bag, slot, itemLink)
    end
end

function mod:SendMailFrame_CanSend()
    if mod.sendCache and next(mod.sendCache)
            or GetSendMailItem(1)
            or SendMailSendMoneyButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney) > 0 then
        SendMailMailButton:Enable()
        SendMailCODButton:Enable()
    end
end

function mod:ContainerFrame_Update(...)
    local frame = ...
    local bag = tonumber(string.sub(frame:GetName(), 15))
    if bag then bag = bag - 1 else return end
    if bag and mod.sendCache and mod.sendCache[bag] then
        for slot, send in pairs(mod.sendCache[bag]) do
            if send then
                mod._shadeBagSlot(bag, slot, true)
            end
        end
    end
end

-- This allows for ctrl-clicking name links to fill the To: field.  Contributed by bigzero.
function mod:SetItemRef(link, ...)
    if SendMailNameEditBox:IsVisible() and IsControlKeyDown() then
        if string.sub(link, 1, 6) == 'player' then
            local name = strsplit(":", string.sub(link, 8))
            if name and strlen(name) > 0 then
                SendMailNameEditBox:SetText(name)
            end
        end
    end
end

function mod:SendMailMailButton_OnClick(frame, a1)
    mod.cacheLock = true
    -- Commit recipient bar if it has uncommitted text
    if mod._recipientBar and mod._recipientBar.editBox then
        local barText = mod._recipientBar.editBox:GetText()
        if barText and barText ~= "" then
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(barText)
            mod._updatingRecipient = nil
        end
    end
    mod.sendDest = SendMailNameEditBox:GetText()
    self._sendCOD = SendMailCODButton:GetChecked() and MoneyInputFrame_GetCopper(SendMailMoney)
    if GetSendMailItem(1) or mod.sendCache and next(mod.sendCache) then
        mod._organizeSendCache()
        self._sendingBulk = true
        self:Send(self._sendCOD)
    else
        if SendMailSendMoneyButton:GetChecked()
                and MoneyInputFrame_GetCopper(SendMailMoney)
                and SendMailSubjectEditBox:GetText() == ''
                and (not mod.sendCache or not next(mod.sendCache)) then
            SendMailSubjectEditBox:SetText(abacus:FormatMoneyFull(MoneyInputFrame_GetCopper(SendMailMoney)))
            if SendMailNameEditBox:GetText() == '' then
                if self.db.char.defaultDestination then
                    SendMailNameEditBox:SetText(self.db.char.defaultDestination)
                else
                    self:Print(L["No default destination set."])
                    self:Print(L["Enter a name in the To: field or set a default destination with |cff00ffaa/bulkmail defaultdest|r."])
                end
            end
        end
        return self.hooks[frame].OnClick(frame, a1)
    end
end

function mod:MailFrameTab1_OnClick(frame, a1)
    self:HideSendQueueGUI()
    return self.hooks[frame].OnClick(frame, a1)
end

function mod:MailFrameTab2_OnClick(frame, a1)
    mod._rulesCacheBuild()
    mod._sendCacheBuild(SendMailNameEditBox:GetText())
    self:ShowSendQueueGUI()
    self:ScheduleTimer(mod._updateSendCost, 0.01)
    return self.hooks[frame].OnClick(frame, a1)
end

function mod:SendMailNameEditBox_OnTextChanged(frame, a1)
    mod.sendDest = mod.cacheLock and mod.sendDest or SendMailNameEditBox:GetText()
    mod._sendCacheBuild(SendMailNameEditBox:GetText())
    -- Sync recipient bar if it wasn't the source of the change
    if not mod._updatingRecipient
            and mod._recipientBar
            and mod._recipientBar.editBox
            and mod._recipientBar.editBox:GetText() ~= SendMailNameEditBox:GetText() then
        mod._updatingRecipient = true
        mod._recipientBar.editBox:SetText(SendMailNameEditBox:GetText())
        mod._updatingRecipient = nil
    end
    return self.hooks[frame].OnTextChanged(frame, a1)
end
