-- GUI_EditRules.lua: AutoSend Rules editor QTip window

local mod          = BulkMail
local L            = mod._L
local QTIP         = mod._QTIP
local LD           = mod._LD
local pt           = mod._pt
local new, del     = mod.new, mod.del
local newHash      = mod.newHash
local deepDel      = mod.deepDel
local color        = mod._color
local _QTipClose   = mod._QTipClose
local _addIndentedCell = mod._addIndentedCell

local shown = {}   -- keeps track of collapsed/expanded state in the tooltip
local curRuleSet   -- for adding rules via the menu dropdown
local dupeCheck = {}

local function newDest()
    StaticPopup_Show("BULKMAIL_ADD_DESTINATION")
end

local function _insertOrRemoveRule(ruletype, value)
    local removed
    for i, v in ipairs(curRuleSet[ruletype]) do
        if ruletype == "itemTypes" then
            if v.type == value.type and v.subtype == value.subtype then
                removed = true
            end
        elseif v == value then
            removed = true
        end
        if removed then
            table.remove(curRuleSet[ruletype], i)
            if type(value) == "table" then
                del(value)
            end
            break
        end
    end
    if not removed then
        table.insert(curRuleSet[ruletype], value)
    end
    mod.rulesAltered = true
    mod:RefreshEditTooltipGUI()
end

local function _editCallbackMethod(args, val)
    -- get the value based on the type of data
    local value
    local ruletype = table.remove(args, 1)
    if ruletype == "itemIDs" then
        local uniqueids = new()
        for id in val:gmatch("([^% ]+)") do
            id = tonumber(id)
            if id then uniqueids[id] = true end
        end
        for id in pairs(uniqueids) do
            _insertOrRemoveRule("items", id)
        end
        return
    elseif ruletype == "pt31Sets" then
        value = table.concat(args, ".")
    elseif ruletype == "items" then
        value = tonumber(args[1])
    elseif ruletype == "itemTypes" then
        value = newHash('type', args[1],
                'subtype', #args > 1 and args[2])
    end
    _insertOrRemoveRule(ruletype, value)
end

local Ace3ConfigTable = {
    type = "group",
    handler = BulkMail,
    set = _editCallbackMethod,
    get = function() return nil end,
    args = {
        inline = {
            type = "header",
            name = L["Add rule"],
            inline = true,
            order = 0,
        },
        itemIDs = {
            type = "input",
            name = L["ItemID(s)"],
            desc = L["Usage: <itemID> [itemID2, ...]"]
        }
    }
}

local menuFrame
local PT31ConfigTable
local ItemTypesConfigTable
local InventoryConfigTable

local function updateInventoryConfigTable()
    deepDel(InventoryConfigTable)
    InventoryConfigTable = newHash(
            'type', "group",
            'name', L["Items from Bags"],
            'desc', L["Mailable items in your bags."],
            'args', new()
    )

    for k in pairs(dupeCheck) do dupeCheck[k] = nil end

    -- Mailable items in bags
    for bag, slot, item in mod._bagIter() do
        local itemID = tonumber(string.match(item or '', "item:(%d+)"))
        if itemID and not dupeCheck[itemID] then
            dupeCheck[itemID] = true
            if mod._isItemMailable(bag, slot) then
                local link    = select(2, GetItemInfo(itemID))
                local texture = select(10, GetItemInfo(itemID))
                InventoryConfigTable.args[tostring(itemID)] = newHash(
                        "type", "toggle",
                        "name", string.format("|T%s:18|t%s", texture, link)
                )
            end
        end
    end
end

local function createPT31SetsConfigTable()
    if PT31ConfigTable then return end

    PT31ConfigTable = newHash(
            'type', "group",
            'name', L["Periodic Table Set"],
            'args', new()
    )

    local pathtable = new()
    local curmenu, prevmenu
    for setname in pairs(pt.sets) do
        for k in ipairs(pathtable) do pathtable[k] = nil end
        curmenu = PT31ConfigTable.args
        for cat in setname:gmatch("([^%.]+)") do
            table.insert(pathtable, cat)
            if not curmenu[cat] then
                curmenu[cat] = newHash('name', cat,
                        'type', 'group',
                        'args', new())
            end
            prevmenu, curmenu = curmenu[cat], curmenu[cat].args
        end
        prevmenu.type = "toggle"
    end
end

local function createBlizzardCategoryConfigTable()
    if ItemTypesConfigTable then return end

    ItemTypesConfigTable = newHash(
            'type', "group",
            'name', L["Item Type"],
            'args', new()
    )

    for itype, subtypes in pairs(mod.auctionItemClasses) do
        local iname = GetItemClassInfo(itype)
        if #subtypes == 0 then
            ItemTypesConfigTable.args[itype] = newHash('type', "toggle", 'name', iname)
        else
            local supertype = new()
            ItemTypesConfigTable.args[itype] = newHash(
                    'type', "group",
                    'name', iname,
                    'args', supertype
            )
            for _, isubtype in ipairs(subtypes) do
                local name = GetItemSubClassInfo(itype, isubtype)
                supertype[isubtype] = newHash('type', "toggle", 'name', name)
            end
        end
    end
end

-- Show the add-new-rule dropdown menu
local function _showmenu(parentFrame, args)
    -- release if already shown
    menuFrame = menuFrame and menuFrame:Release()

    -- Create the config structures
    createBlizzardCategoryConfigTable()
    createPT31SetsConfigTable()
    updateInventoryConfigTable()

    -- Inject into the overall structure
    Ace3ConfigTable.args.pt31Sets  = PT31ConfigTable
    Ace3ConfigTable.args.itemTypes = ItemTypesConfigTable
    Ace3ConfigTable.args.items     = InventoryConfigTable

    -- save the current ruleset
    curRuleSet = args

    -- create the menu
    menuFrame = LD:OpenAce3Menu(Ace3ConfigTable)

    -- Anchor the menu to the mouse
    local xpos, ypos = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", xpos / scale, ypos / scale)
    menuFrame:SetFrameLevel(parentFrame:GetFrameLevel() + 100)
end

local function _plusminus(enabled)
    return string.format("|TInterface\\Buttons\\UI-%sButton-Up:18|t", enabled and "Minus" or "Plus")
end

local function _toggleEditHeader(frame, dest)
    menuFrame = menuFrame and menuFrame:Release()
    if IsAltKeyDown() and dest ~= "globalExclude" then
        StaticPopup_Show('BULKMAIL_REMOVE_DESTINATION', nil, nil, dest)
    else
        shown[dest] = not shown[dest]
    end
    mod:RefreshEditTooltipGUI()
end

local function _namesForItemRule(rule)
    if type(rule) == "string" then
        return rule.type, rule.subtype
    else
        local subtype
        if rule.subtype ~= nil then
            subtype = GetItemSubClassInfo(rule.type, rule.subtype)
        end
        return GetItemClassInfo(rule.type), subtype
    end
end

local function _listRulesQTip(tooltip, ruleset)
    local x, y
    local addedRule
    if ruleset then
        for ruletype, rules in pairs(ruleset) do
            for k, rule in ipairs(rules) do
                local checkIcon
                local text, ruleColor = tostring(rule), mod.COLOR_WHITE
                local func = function(frame)
                    menuFrame = menuFrame and menuFrame:Release()
                    if IsAltKeyDown() then
                        table.remove(rules, k)
                        mod:RefreshEditTooltipGUI()
                        mod.rulesAltered = true
                    end
                end

                if ruletype == 'items' then
                    text = select(2, GetItemInfo(rule))
                    checkIcon = select(10, GetItemInfo(rule))
                elseif ruletype == 'itemTypes' then
                    local name, subtype = _namesForItemRule(rule)
                    if subtype ~= nil then
                        text = string.format("|cff%sItem Type: %s - %s|r", mod.COLOR_ITEM, name, subtype)
                    else
                        text = string.format("|cff%sItem Type: %s|r", mod.COLOR_ITEM, name)
                    end
                elseif ruletype == 'pt31Sets' then
                    text = string.format("|cff%sPT31 Set: %s|r", mod.COLOR_PT31, rule)
                end
                addedRule = true
                if checkIcon then
                    _addIndentedCell(tooltip, string.format("|T%s:18|t%s", checkIcon, text), 30, func)
                else
                    _addIndentedCell(tooltip, text, 30, func)
                end
            end
        end
    end
    if not addedRule then
        y, x = tooltip:AddLine()
        tooltip:SetCell(y, x, L["None"], tooltip:GetFont(), "LEFT", 1, nil, 30)
        return
    end
end

local function _sendEditQueueClose()
    _QTipClose(BulkMail.editQueueTooltip)
    BulkMail.editQueueTooltip = nil
    menuFrame = menuFrame and menuFrame:Release()
end

function mod:RefreshEditTooltipGUI()
    if mod.rulesAltered then
        mod._sendCacheCleanup(true)
        mod._rulesCacheBuild()
        mod._sendCacheBuild(SendMailNameEditBox:GetText())
        mod:RefreshSendQueueGUI()
    end
    if BulkMail.editQueueTooltip then
        mod:OpenEditTooltipGUI()
    end
end

function mod:OpenEditTooltipGUI(parentframe)
    local tooltip = BulkMail.editQueueTooltip
    if not tooltip then
        tooltip = QTIP:Acquire("BulkMail3EditQueueTooltip")
        tooltip:EnableMouse(true)
        tooltip:SetScript("OnDragStart", function(this)
            menuFrame = menuFrame and menuFrame:Release()
            tooltip.StartMoving(this)
        end)
        tooltip:SetScript("OnDragStop", tooltip.StopMovingOrSizing)
        tooltip:RegisterForDrag("LeftButton")
        tooltip:SetMovable(true)
        tooltip:SetColumnLayout(1, "LEFT")
        if parentframe then
            tooltip:SetPoint("TOPLEFT", parentframe, "BOTTOMLEFT", 0, 0)
        else
            tooltip:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        self.editQueueTooltip = tooltip
    else
        tooltip:Clear()
    end

    local y = tooltip:AddHeader()
    tooltip:SetCell(y, 1, color(L["AutoSend Rules"], mod.COLOR_GOLD), tooltip:GetHeaderFont(), "CENTER", 1)
    tooltip:AddLine(" ")

    for dest, rulesets in pairs(mod.autoSendRules) do
        if mod.destCache[dest] then
            -- category title (destination character's name)
            y = tooltip:AddLine(_plusminus(shown[dest])..dest)
            tooltip:SetLineScript(y, "OnMouseUp", _toggleEditHeader, dest)
            if shown[dest] then
                _addIndentedCell(tooltip, color(L["Include"], mod.COLOR_GOLD), 20, _showmenu, rulesets.include)
                _listRulesQTip(tooltip, rulesets.include)
                _addIndentedCell(tooltip, color(L["Exclude"], mod.COLOR_GOLD), 20, _showmenu, rulesets.exclude)
                _listRulesQTip(tooltip, rulesets.exclude)
                tooltip:AddLine(" ")
            end
        end
    end

    -- Global Exclude Rules
    y = tooltip:AddLine(_plusminus(shown.globalExclude)..L["Global Exclude"])
    tooltip:SetLineScript(y, "OnMouseUp", _toggleEditHeader, "globalExclude")

    if shown.globalExclude then
        _addIndentedCell(tooltip, color(L["Exclude"], mod.COLOR_GOLD), 20, _showmenu, mod.globalExclude)
        _listRulesQTip(tooltip, mod.globalExclude)
    end

    tooltip:AddLine(" ")
    tooltip:SetLineScript(tooltip:AddLine(color(L["New Destination"], mod.COLOR_GOLD)), "OnMouseUp", newDest)
    y = tooltip:AddLine(color(L["Close"], mod.COLOR_GOLD))
    tooltip:SetLineScript(y, "OnMouseUp", _sendEditQueueClose)

    tooltip:AddLine(" ")
    y = tooltip:AddLine()
    tooltip:SetCell(y, 1,
        color(L["Hint: "]..L["Click Include/Exclude headers to modify a ruleset.  Alt-Click destinations and rules to delete them."], mod.COLOR_YELLOW),
        tooltip:GetFont(), "LEFT", 1, nil, nil, nil, 250)

    tooltip:SetFrameStrata("DIALOG")
    tooltip:UpdateScrolling(UIParent:GetHeight() / tooltip:GetScale() * 0.9)
    tooltip:SetClampedToScreen(true)
    tooltip:Show()
end
