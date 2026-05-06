-- GUI_SendQueue.lua: Send-queue QTip window

local mod           = BulkMail
local L             = mod._L
local QTIP          = mod._QTIP
local MagicUtil     = mod._MagicUtil
local color         = mod._color
local _QTipClose    = mod._QTipClose
local _addIndentedCell = mod._addIndentedCell

local GetContainerItemInfo = mod._GetContainerItemInfo
local GetContainerItemLink = mod._GetContainerItemLink
local GetContainerNumSlots = mod._GetContainerNumSlots
local PickupContainerItem  = mod._PickupContainerItem

local function getLockedContainerItem()
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            if select(3, GetContainerItemInfo(bag, slot)) then
                return bag, slot
            end
        end
    end
end

local function onSendQueueItemSelect(bag, slot)
    if bag and slot then
        local itemLink = GetContainerItemLink(bag, slot)
        local editBox = ChatEdit_GetActiveWindow()
        if IsAltKeyDown() then
            mod._sendCacheToggle(bag, slot)
        elseif IsShiftKeyDown() and editBox and editBox:IsVisible() then
            editBox:Insert(itemLink)
        elseif IsControlKeyDown() and not IsShiftKeyDown() then
            DressUpItemLink(itemLink)
        else
            local itemString = string.match(itemLink, "item[%-?%d:]+")
            SetItemRef(itemString, itemLink, arg1)
        end
    end
end

local function onDropClick()
    if GetSendMailItem(1) then
        mod:Print(L["WARNING: Cursor item detection is NOT well-defined when multiple items are 'locked'.   Alt-click is recommended for adding items when there is already an item in the Send Mail item frame."])
    end
    if CursorHasItem() and getLockedContainerItem() then
        mod._sendCacheAdd(getLockedContainerItem())
        PickupContainerItem(getLockedContainerItem())  -- clears the cursor
    end
    mod:RefreshSendQueueGUI()
end

local function onSendClick()
    if mod.sendCache then mod:SendMailMailButton_OnClick() end
end

function mod:HideSendQueueGUI()
    _QTipClose(BulkMail.sendQueueTooltip)
    BulkMail.sendQueueTooltip = nil
    if mod._recipientBar then
        mod._recipientBar:Hide()
        mod._recipientBar:SetParent(nil)
    end
end

function mod:RefreshSendQueueGUI()
    if BulkMail.sendQueueTooltip then
        mod:ShowSendQueueGUI()
    end
    mod._updateSendCost()
end

local function _createOrAttachRecipientBar(tooltip)
    local bar = mod._recipientBar
    if not bar then
        local template = (TooltipBackdropTemplateMixin and "TooltipBackdropTemplate")
                      or (BackdropTemplateMixin and "BackdropTemplate")
        bar = CreateFrame("Frame", nil, UIParent, template)
        bar:SetHeight(30)

        if TooltipBackdropTemplateMixin and GameTooltip.layoutType then
            bar.layoutType = GameTooltip.layoutType
            bar.NineSlice:SetCenterColor(GameTooltip.NineSlice:GetCenterColor())
            bar.NineSlice:SetBorderColor(GameTooltip.NineSlice:GetBorderColor())
        elseif bar.SetBackdrop then
            local backdrop = GameTooltip:GetBackdrop()
            bar:SetBackdrop(backdrop)
            if backdrop then
                bar:SetBackdropColor(GameTooltip:GetBackdropColor())
                bar:SetBackdropBorderColor(GameTooltip:GetBackdropBorderColor())
            end
        end

        local label = bar:CreateFontString(nil, nil, "GameFontNormal")
        label:SetTextColor(1, 210/255, 0, 1)
        label:SetText(L["To"]..": ")
        label:SetPoint("LEFT", bar, "LEFT", 8, 0)

        local editBox = CreateFrame("EditBox", "BulkMailRecipientEditBox", bar, "AutoCompleteEditBoxTemplate,InputBoxTemplate")
        editBox:SetHeight(20)
        editBox:SetPoint("LEFT", label, "RIGHT", 5, 0)
        editBox:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
        editBox:SetAutoFocus(false)
        AutoCompleteEditBox_SetAutoCompleteSource(editBox, GetAutoCompleteResults, AUTOCOMPLETE_LIST.MAIL.include, AUTOCOMPLETE_LIST.MAIL.exclude)
        editBox.addHighlightedText = true
        editBox.autoCompleteContext = "mail"

        editBox:SetScript("OnTextChanged", function(self, userInput)
            AutoCompleteEditBox_OnTextChanged(self, userInput)
            if mod._updatingRecipient then return end
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(self:GetText())
            mod._updatingRecipient = nil
            mod.sendDest = self:GetText()
            mod._sendCacheBuild(mod.sendDest)
        end)
        editBox:SetScript("OnTabPressed", function(self)
            AutoCompleteEditBox_OnTabPressed(self)
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            AutoCompleteEditBox_OnEditFocusLost(self)
            mod._updatingRecipient = true
            SendMailNameEditBox:SetText(self:GetText())
            mod._updatingRecipient = nil
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            if not AutoCompleteEditBox_OnEnterPressed(self) then
                mod._updatingRecipient = true
                SendMailNameEditBox:SetText(self:GetText())
                mod._updatingRecipient = nil
                self:ClearFocus()
            end
        end)
        editBox:SetScript("OnEscapePressed", function(self)
            if not AutoCompleteEditBox_OnEscapePressed(self) then
                self:ClearFocus()
            end
        end)

        bar.editBox = editBox
        bar:EnableMouse(true)
        mod._recipientBar = bar
    end

    -- Sync current recipient into the edit box (but don't disturb active typing)
    if not bar.editBox:HasFocus() then
        local currentDest = mod.sendDest or SendMailNameEditBox:GetText() or ""
        mod._updatingRecipient = true
        bar.editBox:SetText(currentDest)
        mod._updatingRecipient = nil
    end

    bar:ClearAllPoints()
    bar:SetParent(tooltip)
    bar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, 4)
    bar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", 0, 4)
    bar:Show()
end

function mod:ShowSendQueueGUI()
    local tooltip = BulkMail.sendQueueTooltip
    if not tooltip then
        tooltip = QTIP:Acquire("BulkMail3SendQueueTooltip")
        tooltip:EnableMouse(true)
        tooltip:SetScript("OnDragStart", tooltip.StartMoving)
        tooltip:SetScript("OnDragStop", function()
            tooltip:StopMovingOrSizing()
            if mod.db.profile.freePosition then
                local point, _, relPoint, x, y = tooltip:GetPoint()
                mod.db.profile.savedPos = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end)
        tooltip:RegisterForDrag("LeftButton")
        tooltip:SetMovable(true)
        tooltip:SetColumnLayout(2, "LEFT", "RIGHT")
        self.sendQueueTooltip = tooltip
    else
        tooltip:Clear()
    end

    -- Position the send queue
    if mod.db.profile.freePosition and mod.db.profile.savedPos then
        local saved = mod.db.profile.savedPos
        tooltip:ClearAllPoints()
        tooltip:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        -- Always re-anchor to the current mail frame (may change when TSM toggles)
        local mailFrame, isTSM = MagicUtil:GetMailFrame()
        tooltip:ClearAllPoints()
        local inboxGUI     = BulkMailInbox and BulkMailInbox.inboxGUI
        local inboxToolbar = BulkMailInbox and BulkMailInbox._toolbar
        if isTSM and inboxGUI and inboxGUI:IsShown() then
            local anchor = inboxToolbar and inboxToolbar:IsShown() and inboxToolbar or inboxGUI
            tooltip:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
        elseif isTSM then
            tooltip:SetPoint("TOPLEFT", mailFrame, "TOPRIGHT", 5, 0)
        else
            tooltip:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 5, 0)
        end
    end

    local y = tooltip:AddHeader()
    tooltip:SetCell(y, 1, L["Item Send Queue"], tooltip:GetFont(), "CENTER", 2)

    tooltip:AddLine(" ")
    if mod.sendCache and next(mod.sendCache) then
        local itemLink, itemText, texture, qty, info
        for bag, slots in pairs(mod.sendCache) do
            for slot in pairs(slots) do
                itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    if C_Container then
                        info = C_Container.GetContainerItemInfo(bag, slot)
                        itemText = info.itemName
                        texture  = info.iconFileID
                        qty      = info.stackCount
                    else
                        itemText = GetItemInfo(itemLink)
                        texture, qty = GetContainerItemInfo(bag, slot)
                    end
                    if qty and qty > 1 then
                        itemText = string.format("|T%s:18|t |cffffd200%s (%d)|r", texture, itemText, qty)
                    elseif itemText then
                        itemText = string.format("|T%s:18|t |cffffd200%s|r", texture, itemText)
                    else
                        itemText = itemLink -- shouldn't happen
                    end
                    local row = _addIndentedCell(tooltip, itemText, 5, function(self)
                        onSendQueueItemSelect(bag, slot)
                    end)
                    local recipient
                    if mod.sendDest == '' or not mod.sendDest then
                        recipient = mod._rulesCacheDest(itemLink) or self.db.char.defaultDestination
                        if not recipient or strlen(recipient) == 0 then
                            recipient = color(L["Missing"], mod.COLOR_RED)
                        else
                            recipient = color(recipient, mod.COLOR_GREEN)
                        end
                    else
                        recipient = color(mod.sendDest, mod.COLOR_CYAN)
                    end
                    tooltip:SetCell(row, 2, recipient, tooltip:GetFont())
                end
            end
        end
    else
        _addIndentedCell(tooltip, color(L["No items selected"], mod.COLOR_GOLD), 5)
    end

    tooltip:AddLine(" ")

    y = tooltip:AddLine()
    tooltip:SetCell(y, 1, color(L["Drop items here for Sending"], mod.COLOR_GOLD), tooltip:GetFont(), "CENTER", 2)
    tooltip:SetLineScript(y, "OnReceiveDrag", onDropClick)
    tooltip:SetLineScript(y, "OnMouseUp", onDropClick)
    tooltip:AddLine(" ")

    if mod.sendCache and next(mod.sendCache) then
        _addIndentedCell(tooltip, color(L["Clear"], mod.COLOR_GOLD), 5, mod._sendCacheCleanup)
        if SendMailMailButton:IsEnabled() and SendMailMailButton:IsEnabled() ~= 0 then
            _addIndentedCell(tooltip, color(L["Send"], mod.COLOR_GOLD), 5, onSendClick)
        else
            _addIndentedCell(tooltip, color(L["Send"], "7f7f7f"), 5)
        end
    else
        _addIndentedCell(tooltip, color(L["Clear"], "7f7f7f"), 5)
        _addIndentedCell(tooltip, color(L["Send"],  "7f7f7f"), 5)
    end
    tooltip:AddLine(" ")

    _addIndentedCell(tooltip, color(L["Close"], mod.COLOR_GOLD), 5, BulkMail.HideSendQueueGUI, BulkMail)
    tooltip:AddLine(" ")
    tooltip:AddLine(L["Alt-Right Click item to add/remove."])
    tooltip:AddLine(L["Alt-Left Click item to bulk add/remove."])
    tooltip:SetFrameStrata("FULLSCREEN")
    tooltip:SetClampedToScreen(true)
    _createOrAttachRecipientBar(tooltip)
    tooltip:Show()
    -- UpdateScrolling needs valid bounds, so call after Show()
    if tooltip:GetTop() then
        local sizeMode = not mod.db.profile.freePosition and mod.db.profile.sizeMode or "free"
        local mailFrameH
        if sizeMode == "match" or sizeMode == "max" then
            local mailFrame = MagicUtil:GetMailFrame()
            if mailFrame and mailFrame:GetHeight() and mailFrame:GetHeight() > 0 then
                mailFrameH = mailFrame:GetHeight() / tooltip:GetScale()
            end
        end

        if mailFrameH and (sizeMode == "match" or sizeMode == "max") then
            tooltip:UpdateScrolling(mailFrameH)
        else
            tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.8)
        end

        if sizeMode == "match" and mailFrameH then
            tooltip:SetHeight(mailFrameH)
        end
    end
end
