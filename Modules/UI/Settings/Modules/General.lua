local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

ns.Settings.Modules.General = {}
local General = ns.Settings.Modules.General

local bulletAccountWide = ns.Utils:ColorText('ff00ff00', '* ')
local bulletGuildWide = ns.Utils:ColorText('ffffff00', '* ')

function General:Initialize()
    -- Module initialization if needed
end

function General:IsEnabled()
    return true
end

function General:GetConfigTable()
    return {
        name = L['FGR_SETTINGS'],
        type = 'group',
        args = {
            genHeading1 = {
                order = 0,
                name = L['FGR_SETTINGS'],
                type = 'header',
            },
            genNoteGuildwide = {
                order = 1,
                name = bulletGuildWide..L['GEN_GUILD_WIDE'],
                type = 'description',
                fontSize = 'medium',
            },
            genNoteAccountwide = {
                order = 2,
                name = bulletAccountWide..L['GEN_ACCOUNT_WIDE'],
                type = 'description',
                fontSize = 'medium',
            },
            genNote = {
                order = 3,
                name = ns.Utils:ColorText('FFFFFF00', L['RELOAD_AFTER_CHANGE']),
                type = 'description',
                fontSize = 'medium',
            },
            
            -- UI Settings Group
            uiSettings = self:GetUISettings(),
            
            -- Performance Settings Group  
            performanceSettings = self:GetPerformanceSettings(),
            
            -- Keybinding Settings Group
            keybindingSettings = self:GetKeybindingSettings(),
        }
    }
end

function General:GetUISettings()
    return {
        name = L['UI_SETTINGS'] or 'UI Settings',
        type = 'group',
        inline = true,
        order = 10,
        args = {
            genWhatsNew = {
                order = 1,
                name = bulletAccountWide..L['GEN_WHATS_NEW'],
                desc = L['GEN_WHATS_NEW_DESC'],
                type = 'toggle',
                width = 1,
                set = function(_, val) ns.g.ui.showWhatsNew = val end,
                get = function() return ns.g.ui.showWhatsNew or false end,
            },
            genSpacer1 = {
                order = 2,
                name = '',
                type = 'description',
                width = .5,
            },
            genTooltips = {
                order = 3,
                name = bulletAccountWide..L['GEN_TOOLTIPS'],
                desc = L['GEN_TOOLTIP_DESC'],
                type = 'toggle',
                width = 1,
                set = function(_, val) ns.g.ui.showToolTips = val end,
                get = function() return ns.g.ui.showToolTips or false end,
            },
            genShowAppMessages = {
                order = 4,
                name = L['GEN_ADDON_MESSAGES'],
                desc = L['GEN_ADDON_MESSAGES_DESC'],
                type = 'toggle',
                width = 1,
                set = function(_, val) ns.pSettings.ui.showAppMsgs = val end,
                get = function() return ns.pSettings.ui.showAppMsgs or false end,
            },
            genSpacer2 = {
                order = 5,
                name = '',
                type = 'description',
                width = .5,
            },
            genIgnoreESC = {
                order = 6,
                name = L['KEEP_ADDON_OPEN'],
                desc = L['KEEP_ADDON_OPEN_DESC'],
                type = 'toggle',
                width = 1,
                set = function(_, val) ns.pSettings.ui.keepOpen = val end,
                get = function() return ns.pSettings.ui.keepOpen or false end,
            },
            genMiniMap = {
                order = 7,
                name = L['GEN_MINIMAP'],
                desc = L['GEN_MINIMAP_DESC'],
                type = 'toggle',
                width = 'full',
                set = function(_, val)
                    ns.pSettings.ui.minimap.hide = not val
                    if ns.MinimapIcon then
                        if val then
                            ns.MinimapIcon:Show()
                        else
                            ns.MinimapIcon:Hide()
                        end
                    end
                end,
                get = function() return not ns.pSettings.ui.minimap.hide end,
            },
            genCompactSize = {
                order = 8,
                name = bulletAccountWide..L['COMPACT_SIZE']..':',
                desc = 'When in compact mode, select the size of the window.',
                type = 'select',
                style = 'dropdown',
                width = 1,
                values = {
                    [1] = 'Normal',
                    [2] = 'Compact',
                },
                set = function(_, val) ns.g.ui.compactSize = tonumber(val) end,
                get = function() return ns.g.ui.compactSize or 1 end,
            },
            genDebugMode = {
                order = 9,
                name = (L['DEBUG_MODE'] or 'Debug Mode'),
                desc = (L['DEBUG_MODE_DESC'] or 'Enable verbose debug logging to chat. Useful for troubleshooting.'),
                type = 'toggle',
                width = 1,
                set = function(_, val)
                    ns.pSettings.debugMode = val
                    FGR.debug = val or (FGR.isTesting == true)
                end,
                get = function() return ns.pSettings.debugMode or false end,
            },
        }
    }
end

function General:GetPerformanceSettings()
    return {
        name = L['PERFORMANCE_SETTINGS'] or 'Performance Settings',
        type = 'group',
        inline = true,
        order = 20,
        args = {
            genScanInterval = {
                order = 1,
                name = bulletAccountWide..L['SCAN_WAIT_TIME'],
                desc = L['SCAN_WAIT_TIME_DESC'],
                type = 'input',
                width = 1,
                validate = function(_, val)
                    local num = tonumber(val)
                    return num and num >= 2 and num <= 10
                end,
                set = function(_, val)
                    local num = tonumber(val)
                    if num and num >= 2 and num <= 10 then 
                        ns.g.performance.scanWaitTime = num
                    else 
                        ns.Logger:Error('Enter value between 2 and 10.')
                    end
                end,
                get = function() return tostring(ns.g.performance.scanWaitTime or 5) end,
            },
            genSpacer3 = {
                order = 2,
                name = '',
                type = 'description',
                width = .5,
            },
            genSendWaitTime = {
                order = 3,
                name = bulletAccountWide..L['SEND_MESSAGE_WAIT_TIME'],
                desc = L['SEND_MESSAGE_WAIT_TIME_DESC'],
                type = 'range',
                min = 0.1,
                max = 1.0,
                step = 0.1,
                width = 1,
                set = function(_, val) ns.g.performance.timeBetweenMessages = tostring(val) end,
                get = function() return tonumber(ns.g.performance.timeBetweenMessages) or 0.2 end,
            },
        }
    }
end

function General:GetKeybindingSettings()
    return {
        name = L['KEYBINDING_HEADER'],
        type = 'group',
        inline = true,
        order = 30,
        args = {
            genKeybindingInvite = {
                order = 1,
                name = bulletAccountWide..L['KEYBINDING_INVITE'],
                desc = L['KEYBINDING_INVITE_DESC'],
                type = 'keybinding',
                width = 1,
                set = function(_, val)
                    if not val or val == '' then
                        ns.g.keybindings.invite = nil
                    elseif val == ns.g.keybindings.invite then
                        if ns.Logger then ns.Logger:Info(L['KEY_BOUND_TO_INVITE']) end
                        return
                    else
                        ns.g.keybindings.invite = val
                    end
                    if ns.Keybindings then ns.Keybindings:RefreshKeybindings() end
                end,
                get = function() return ns.g.keybindings.invite end,
            },
            genSpacer4 = {
                order = 2,
                name = '',
                type = 'description',
                width = .5,
            },
            genKeybindingScan = {
                order = 3,
                name = bulletAccountWide..L['KEYBINDING_SCAN'],
                desc = L['KEYBINDING_SCAN_DESC'],
                type = 'keybinding',
                width = 1,
                set = function(_, val)
                    if not val or val == '' then
                        ns.g.keybindings.scan = nil
                    elseif val == ns.g.keybindings.scan then
                        if ns.Logger then ns.Logger:Info(L['KEY_BOUND_TO_SCAN']) end
                        return
                    else
                        ns.g.keybindings.scan = val
                    end
                    if ns.Keybindings then ns.Keybindings:RefreshKeybindings() end
                end,
                get = function() return ns.g.keybindings.scan end,
            },
        }
    }
end