-- Config.lua: Addon initialization, options table, LDB, AceDB, AceConfig registration

local mod  = BulkMail
local L    = mod._L
local DB   = mod._DB
local AC   = mod._AC
local ACD  = mod._ACD
local LD   = mod._LD
local LDB  = mod._LDB
local color = mod._color
local new   = mod.new
local newHash = mod.newHash

local GetAddOnInfo           = mod._GetAddOnInfo
local GetAddOnMetadata       = mod._GetAddOnMetadata
local GetAuctionItemSubClasses = mod._GetAuctionItemSubClasses
local GetNumAddOns           = mod._GetNumAddOns
local LoadAddOn              = mod._LoadAddOn

function mod:OnInitialize()
    -- Run legacy database migrations
    if not BulkMail3DB then
        mod._convertBulkMail2DB()
    end
    mod._convertBulkMail2DB     = nil
    mod._convertAce2ToAce3Realm = nil

    self.db = DB:New("BulkMail3DB", {
        factionrealm = {
            autoSendRules = {
                ['*'] = {
                    include = {
                        ['*'] = {},
                    },
                    exclude = {
                        ['*'] = {},
                    },
                },
            },
        },
        char = {
            isSink = false,
            attachMulti = true,
            globalExclude = {
                ['*'] = {}
            },
        },
        profile = {
            sizeMode = "free",
            freePosition = false,
            savedPos = nil,
        },
    }, "Default")
    self.db.char.minItemLevel     = self.db.char.minItemLevel or 1
    self.db.char.minItemLevelMisc = self.db.char.minItemLevelMisc or 1
    mod.autoSendRules = self.db.factionrealm.autoSendRules  -- shared reference for speed/convenience

    mod.destCache        = new()  -- destinations for which we have rules (or will add rules)
    mod.reverseDestCache = new()  -- integer-indexed list of destinations
    for dest in pairs(mod.autoSendRules) do
        mod.destCache[dest] = true
        table.insert(mod.reverseDestCache, dest)
    end

    mod.globalExclude = self.db.char.globalExclude  -- shared reference for speed/convenience

    local obsoletes
    if GetItemClassInfo(Enum.ItemClass.Battlepet) then
        -- retail
        obsoletes = newHash(
                Enum.ItemClass.Reagent,    true,
                Enum.ItemClass.Projectile, true,
                Enum.ItemClass.Quiver,     true,
                Enum.ItemClass.Questitem,  true, -- can't send quest items
                Enum.ItemClass.Key,        true,
                10, true,  -- Money
                14, true   -- Permanent
        )
    else
        -- classic
        obsoletes = newHash(
                (LE_ITEM_CLASS_GEM or Enum.ItemClass.Gem),                         true,
                (LE_ITEM_CLASS_GLYPH or Enum.ItemClass.Glyph),                     true,
                (LE_ITEM_CLASS_ITEM_ENHANCEMENT or Enum.ItemClass.ItemEnhancement), true,
                (LE_ITEM_CLASS_WOW_TOKEN or Enum.ItemClass.WoWToken),               true,
                (LE_ITEM_CLASS_BATTLEPET or Enum.ItemClass.Battlepet),              true,
                (LE_ITEM_CLASS_QUESTITEM or Enum.ItemClass.Questitem),              true, -- can't send quest items
                10, true,  -- Money
                14, true   -- Permanent
        )
    end

    mod.auctionItemClasses = {}  -- item type → subclasses association table
    for i = 0, mod.NUM_LE_ITEM_CLASSES - 1 do
        if not obsoletes[i] then
            mod.auctionItemClasses[i] = GetAuctionItemSubClasses(i)
        end
    end
    mod.numItems    = 0
    mod.rulesAltered = true

    local itemQualities = {}
    for k in pairs(Enum.ItemQuality) do
        local v = Enum.ItemQuality[k]
        if v < Enum.ItemQuality.Rare then
            itemQualities[v] = k
        end
    end

    self.opts = {
        type = 'group',
        handler = mod,
        args = {
            defaultdest = {
                name = L["Default destination"], type = 'input',
                desc = L["Set the default recipient of your AutoSend rules"],
                get = function() return self.db.char.defaultDestination end,
                set = function(args, dest) self.db.char.defaultDestination = dest end,
            },
            autosend = {
                name = L["Auto Send Commands"], type = 'group',
                desc = L["AutoSend Options"],
                args = {
                    edit = {
                        name = L["Edit Destinations"], type = 'execute',
                        desc = L["Edit AutoSend definitions."],
                        func = function() mod:OpenEditTooltipGUI() end,
                        order = 30,
                    },
                    clear = {
                        name = L["Clear Realm rules"], type = 'execute',
                        desc = L["Clear all rules for this realm."],
                        func = function()
                            self.db.factionrealm = new()
                            for i in pairs(mod.autoSendRules) do
                                mod.autoSendRules[i] = nil
                            end
                            mod:RefreshEditTooltipGUI()
                        end,
                        confirm = true,
                        order = 40
                    },
                },
            },
            sink = {
                name = L["Sink"], type = 'toggle',
                desc = L["Disable AutoSend queue auto-filling for this character."],
                get = function() return self.db.char.isSink end,
                set = function(args, v) self.db.char.isSink = v end,
                order = 4000,
            },
            attachmulti = {
                name = L["Attach multiple items"], type = 'toggle',
                desc = L["Attach as many items as possible per mail."],
                get = function() return self.db.char.attachMulti end,
                set = function(args, v) self.db.char.attachMulti = v end,
                order = 4100,
            },
            attachItemLevelMin = {
                name = L["Min Matched Equipped Quality"], type = 'select',
                desc = L["The minimum quality level matched for automatic destinations for equippable items / gear."],
                values = itemQualities,
                get = function() return self.db.char.minItemLevel end,
                set = function(args, v) self.db.char.minItemLevel = v end,
            },
            attachItemLevelMinMisc = {
                name = L["Min Matched Quality"], type = 'select',
                desc = L["The minimum quality level matched for automatic destinations."],
                values = itemQualities,
                get = function() return self.db.char.minItemLevelMisc end,
                set = function(args, v) self.db.char.minItemLevelMisc = v end,
            },
            sizeMode = {
                name = L["Window Size"],
                type = 'select',
                desc = L["How the window height is determined. Match sets height to mail frame. Max limits height to mail frame. Free sizes to content."],
                values = {
                    free  = L["Free"],
                    match = L["Match Mail Frame"],
                    max   = L["Max Mail Frame"],
                },
                get = function() return self.db.profile.sizeMode end,
                set = function(_, v) self.db.profile.sizeMode = v mod:RefreshSendQueueGUI() end,
                disabled = function() return self.db.profile.freePosition end,
                order = 2500,
            },
            freePosition = {
                name = L["Free Position"],
                type = 'toggle',
                desc = L["Disable automatic anchoring to the mail frame. The window will remember its position when dragged."],
                get = function() return self.db.profile.freePosition end,
                set = function(_, v)
                    self.db.profile.freePosition = v
                    if not v then
                        self.db.profile.savedPos = nil
                    end
                    mod:RefreshSendQueueGUI()
                end,
                order = 3000,
            },
        },
    }

    -- set up LDB
    if LDB then
        self.ldb = LDB:NewDataObject("BulkMail", {
            type  = "data source",
            label = L["Bulk Mail"]..mod._VERSION,
            icon  = [[Interface\Addons\BulkMail2\icon]],
            tooltiptext = color(L["Bulk Mail"]..mod._VERSION.."\n\n", mod.COLOR_YELLOW)
                    ..color(L["Hint: Click to show the AutoSend Rules editor."].."\n"
                            ..L["Middle click to open the config panel."].."\n"
                            ..L["Right click to open the config menu."], mod.COLOR_GOLD),
            OnClick = function(clickedframe, button)
                if button == "LeftButton" then
                    mod:OpenEditTooltipGUI(clickedframe)
                elseif button == "MiddleButton" then
                    mod:ToggleConfigDialog()
                elseif button == "RightButton" then
                    mod:OpenConfigMenu(clickedframe)
                end
            end,
        })
    end

    self._mainConfig = self:OptReg(L["Bulk Mail"]..mod._VERSION, self.opts, { "bm", "bulkmail" })

    -- LoD PT31 Sets; yanked from Baggins
    for i = 1, GetNumAddOns() do
        local metadata = GetAddOnMetadata(i, "X-PeriodicTable-3.1-Module")
        if metadata then
            local name, _, _, enabled = GetAddOnInfo(i)
            if enabled then
                LoadAddOn(name)
            end
        end
    end
end

-- Convenience function for registering options tables
function mod:OptReg(optname, tbl, cmd)
    local regtable
    local configPanes = self.configPanes or new()
    self.configPanes = configPanes
    AC:RegisterOptionsTable(optname, tbl, cmd)
    regtable = ACD:AddToBlizOptions(optname, L["Bulk Mail"])
    configPanes[#configPanes+1] = optname
    return regtable
end

function mod:OpenConfigMenu(parentframe)
    local frame = LD:OpenAce3Menu(mod.opts)
    frame:SetPoint("TOPLEFT", parentframe, "BOTTOMLEFT", 0, 0)
    frame:SetFrameLevel(parentframe:GetFrameLevel() + 100)
end

function mod:ToggleConfigDialog()
    InterfaceOptionsFrame_OpenToCategory(self._mainConfig)
end

StaticPopupDialogs['BULKMAIL_ADD_DESTINATION'] = {
    text = L["BulkMail - New AutoSend Destination"],
    button1 = L["Accept"], button2 = L["Cancel"],
    hasEditBox = 1, maxLetters = 20,
    OnAccept = function(self)
        mod:AddDestination(_G[self:GetName().."EditBox"]:GetText())
        mod:RefreshEditTooltipGUI()
    end,
    OnShow = function(self)
        _G[self:GetName().."EditBox"]:SetFocus()
    end,
    OnHide = function(self)
        local activeWindow = ChatEdit_GetActiveWindow()
        if activeWindow then
            _G[self:GetName().."EditBox"]:SetText('')
            activeWindow:Insert('')
        end
    end,
    EditBoxOnEnterPressed = function(self)
        mod:AddDestination(_G[self:GetName()]:GetText())
        mod:RefreshEditTooltipGUI()
        mod.rulesAltered = true
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0, exclusive = 1, whileDead = 1, hideOnEscape = 1,
}

StaticPopupDialogs['BULKMAIL_REMOVE_DESTINATION'] = {
    text = L["BulkMail - Confirm removal of destination"],
    button1 = L["Accept"], button2 = L["Cancel"],
    OnAccept = function(self)
        if self.data then
            mod:RemoveDestination(self.data)
            mod:RefreshEditTooltipGUI()
            mod.rulesAltered = true
        end
    end,
    timeout = 0, exclusive = 1, hideOnEscape = 1,
}
