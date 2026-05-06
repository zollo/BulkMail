-- Events.lua: Event handlers and addon lifecycle methods (OnEnable, OnDisable)

local mod      = BulkMail
local L        = mod._L
local MagicUtil = mod._MagicUtil

local mailIsVisible  -- local to this module

function mod:PLAYER_INTERACTION_MANAGER_FRAME_HIDE(_, interactionType)
    if interactionType == Enum.PlayerInteractionType.MailInfo then
        mod:MAIL_CLOSED()
    end
end

function mod:MAIL_SHOW()
    -- Allow TSM frame detection to re-scan (TSM may create its frame lazily)
    MagicUtil:ResetTSMFrameCache()
    if not mailIsVisible then
        mailIsVisible = true
        if mod.rulesAltered then mod._rulesCacheBuild() end
        if ContainerFrameItemButton_OnModifiedClick then
            self:SecureHook('ContainerFrameItemButton_OnModifiedClick')
            self:SecureHook('ContainerFrame_Update')
        else
            self:SecureHook('HandleModifiedItemClick')
            for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
                self:SecureHook(frame, "Update", 'ContainerFrame_Update')
            end
        end
        self:SecureHook('SendMailFrame_CanSend')
        self:SecureHook('MoneyInputFrame_OnTextChanged', SendMailFrame_CanSend)
        self:SecureHook('SetItemRef')
        self:RawHookScript(SendMailMailButton, 'OnClick', 'SendMailMailButton_OnClick')
        self:RawHookScript(MailFrameTab1, 'OnClick', 'MailFrameTab1_OnClick')
        self:RawHookScript(MailFrameTab2, 'OnClick', 'MailFrameTab2_OnClick')
        self:RawHookScript(SendMailNameEditBox, 'OnTextChanged', 'SendMailNameEditBox_OnTextChanged')
        self:RegisterEvent('MAIL_SEND_SUCCESS')
        self:RegisterEvent('SECURE_TRANSFER_CANCEL')
        self:RegisterEvent('MAIL_FAILED')

        SendMailMailButton:Enable()

        --[[
        -- This should have its own config option somewhere.
        -- Ideally, this operation should be done without the
        -- mail window opening to the user. The user should
        -- simply hold shift, right click on the mailbox,
        -- and BulkMail mails all items without ever opening
        -- the mail frame to the user. The only thing the user
        -- would see is 'Mail Sent' along with the sound.

        -- Note: There should likely be a config option to print
        -- to the chat frame of what items were sent and to where.
        ]]--
        if IsShiftKeyDown() then
            mod:MailFrameTab2_OnClick(MailFrameTab2)
            mod:SendMailMailButton_OnClick(MailFrameTab2)
        end
    end
    -- Watch for mail frame changes (e.g. TSM toggling between its UI and the default)
    mod._lastMailFrame = nil
    if not mod._mailFrameWatcher then
        mod._mailFrameWatcher = self:ScheduleRepeatingTimer("CheckMailFrameChanged", 0.2)
    end
end

function mod:CheckMailFrameChanged()
    local mailFrame, isTSM = MagicUtil:GetMailFrame()
    if mailFrame ~= mod._lastMailFrame then
        mod._lastMailFrame = mailFrame
        if isTSM then
            -- TSM active: always show the send queue alongside inbox
            mod._rulesCacheBuild()
            mod._sendCacheBuild(SendMailNameEditBox:GetText())
            self:ShowSendQueueGUI()
        else
            -- Switching to normal UI: show send queue only if on Send tab
            if SendMailFrame and SendMailFrame:IsShown() then
                self:ShowSendQueueGUI()
            elseif mod.sendQueueTooltip then
                self:HideSendQueueGUI()
            end
        end
    end
end

function mod:MAIL_CLOSED()
    if mailIsVisible then
        mailIsVisible = nil
        if mod._mailFrameWatcher then
            self:CancelTimer(mod._mailFrameWatcher)
            mod._mailFrameWatcher = nil
        end
        mod._lastMailFrame = nil
        self:UnhookAll()
        mod._sendCacheCleanup()
        self:HideSendQueueGUI()
        self:StopBulkSend()
    end
end

-- MAIL_CLOSED doesn't fire if e.g. the player accepts a port while the mail window is open
BulkMail.PLAYER_ENTERING_WORLD = BulkMail.MAIL_CLOSED

function mod:MAIL_SEND_SUCCESS()
    if self._sendingBulk then
        self:RefreshSendQueueGUI()
        -- Small delay to let WoW process the sent mail before loading the next one
        self:ScheduleTimer("Send", 0.1, self._sendCOD)
    end
end

function mod:SECURE_TRANSFER_CANCEL()
    if self._sendingBulk then
        self:StopBulkSend()
        SendMailNameEditBox:SetText('')
        mod.sendDest = ''
        mod._sendCacheCleanup()
        self:Print(L["Send cancelled."])
    end
end

function mod:MAIL_FAILED()
    if self._sendingBulk then
        self:StopBulkSend()
        SendMailNameEditBox:SetText('')
        mod.sendDest = ''
        mod._sendCacheCleanup()
    end
end

function mod:OnEnable()
    self:RegisterEvent('MAIL_SHOW')
    self:RegisterEvent('MAIL_CLOSED')
    self:RegisterEvent('PLAYER_ENTERING_WORLD')
    if not _G.GetContainerItemInfo then
        self:RegisterEvent('PLAYER_INTERACTION_MANAGER_FRAME_HIDE')
    end
    -- Handle being LoD loaded while at the mailbox
    if MailFrame:IsVisible() then
        self:MAIL_SHOW()
    end
end

function mod:OnDisable()
    self:UnregisterAllEvents()
    self:UnhookAll()
end
