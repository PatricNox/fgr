-- Modules/UI/ContextMenu.lua
local addonName, ns = ...

ns.ContextMenu = {}
local ContextMenu = ns.ContextMenu

local customMenuFrame = nil

function ContextMenu:Initialize()
    self:SetupChatHooks()
    
    if ns.Logger and ns.Logger.Debug then
        ns.Logger:Debug("Context menu initialized")
    end
end

function ContextMenu:SetupChatHooks()
    -- Only set up hooks if settings allow it
    local function shouldShowContextMenu()
        return ns.pSettings and ns.pSettings.ui and ns.pSettings.ui.showContextMenu
    end
    
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        if chatFrame then
            chatFrame:HookScript("OnHyperlinkClick", function(self, link, _, button)
                if button == "RightButton" and shouldShowContextMenu() then
                    local linkType, playerName = strsplit(":", link)
                    if linkType == "player" and playerName then 
                        -- Remove any server names for display
                        local displayName = strsplit("-", playerName)
                        C_Timer.After(0.1, function() 
                            ContextMenu:ShowCustomMenu(displayName or playerName) 
                        end)
                    else
                        if ns.Logger and ns.Logger.Debug then
                            ns.Logger:Debug("Invalid link data: %s, %s", tostring(linkType), tostring(playerName))
                        end
                    end
                end
            end)
        end
    end
end

function ContextMenu:CreateMenuFrame()
    if customMenuFrame then return customMenuFrame end
    
    customMenuFrame = CreateFrame("Frame", "FGRCustomChatDropdownMenu", UIParent, "UIDropDownMenuTemplate")
    return customMenuFrame
end

function ContextMenu:InitializeMenu(frame, level)
    level = level or 1
    local playerName = frame.targetName
    if not playerName then return end

    -- Check if player is already in guild
    local isInGuild = self:IsPlayerInMyGuild(playerName)
    if isInGuild then
        if ns.Logger and ns.Logger.Debug then
            ns.Logger:Debug("Player %s is already in the guild", playerName)
        end
        return
    end

    -- Add title
    local title = UIDropDownMenu_CreateInfo()
    title.text = playerName
    title.isTitle = true
    title.fontObject = FGRFontTitle
    title.notCheckable = true
    title.justifyH = "CENTER"
    UIDropDownMenu_AddButton(title, level)

    -- Add separator
    self:AddSeparator(level)

    -- Add invite options
    self:AddInviteOptions(playerName, level)
    
    -- Add separator
    self:AddSeparator(level)
    
    -- Add blacklist option
    self:AddBlacklistOption(playerName, level)
end

function ContextMenu:AddSeparator(level)
    local separator = UIDropDownMenu_CreateInfo()
    separator.text = " "
    separator.notCheckable = true
    separator.isTitle = true
    separator.disabled = true
    separator.iconOnly = true
    separator.icon = "Interface\\Common\\UI-TooltipDivider-Transparent"
    separator.iconInfo = {
        tCoordLeft = 0,
        tCoordRight = 1,
        tCoordTop = 0,
        tCoordBottom = 1,
        tSizeX = 0,
        tSizeY = 8,
        tFitDropDownSizeX = true
    }
    UIDropDownMenu_AddButton(separator, level)
end

function ContextMenu:AddInviteOptions(playerName, level)
    -- Only show invite options if we can actually invite
    if not CanGuildInvite() then
        local noInvite = UIDropDownMenu_CreateInfo()
        noInvite.text = "Cannot invite (no permission)"
        noInvite.notCheckable = true
        noInvite.disabled = true
        UIDropDownMenu_AddButton(noInvite, level)
        return
    end
    
    -- Invite without message
    local inviteNoMessage = UIDropDownMenu_CreateInfo()
    inviteNoMessage.text = "Guild Invite (No Message)"
    inviteNoMessage.notCheckable = true
    inviteNoMessage.func = function() 
        self:HandleManualInvite(playerName, false)
    end
    UIDropDownMenu_AddButton(inviteNoMessage, level)
    
    -- Invite with welcome message
    local inviteWithMessage = UIDropDownMenu_CreateInfo()
    inviteWithMessage.text = "Guild Invite + Welcome Message"
    inviteWithMessage.notCheckable = true
    inviteWithMessage.func = function() 
        self:HandleManualInvite(playerName, true)
    end
    UIDropDownMenu_AddButton(inviteWithMessage, level)
end

function ContextMenu:AddBlacklistOption(playerName, level)
    local blacklistPlayer = UIDropDownMenu_CreateInfo()
    blacklistPlayer.text = "Add to Blacklist"
    blacklistPlayer.notCheckable = true
    blacklistPlayer.func = function()
        self:HandleManualBlacklist(playerName)
    end
    UIDropDownMenu_AddButton(blacklistPlayer, level)
end

function ContextMenu:ShowCustomMenu(playerName)
    if not customMenuFrame then
        customMenuFrame = self:CreateMenuFrame()
    end
    
    customMenuFrame.targetName = playerName
    UIDropDownMenu_Initialize(customMenuFrame, function(frame, level)
        self:InitializeMenu(frame, level)
    end, "MENU")

    -- Calculate position to prevent menu from going off screen
    local screenWidth = GetScreenWidth()
    local menuWidth = 150
    local cursorX = GetCursorPosition()
    local uiScale = UIParent:GetEffectiveScale()
    cursorX = cursorX / uiScale

    local xOffset = 175
    if (cursorX + xOffset + menuWidth) > screenWidth then
        xOffset = -185
    end

    ToggleDropDownMenu(1, nil, customMenuFrame, "cursor", xOffset, 0)
end

-- Helper functions
function ContextMenu:IsPlayerInMyGuild(playerName)
    if not playerName or not IsInGuild() then return false end
    
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            -- Handle both "Name" and "Name-Server" formats
            local guildMemberName = strsplit("-", name)
            local checkName = strsplit("-", playerName)
            
            if guildMemberName and checkName and strlower(guildMemberName) == strlower(checkName) then
                return true
            end
        end
    end
    
    return false
end

function ContextMenu:HandleManualInvite(playerName, withMessage)
    if not CanGuildInvite() then
        print("|cFFFF0000[FGR]|r Cannot invite - insufficient permissions")
        return
    end
    
    if ns.InviteManager and ns.InviteManager.ManualInvite then
        ns.InviteManager:ManualInvite(playerName, withMessage, not withMessage, withMessage, false)
    else
        -- Fallback - just send guild invite
        ns.GuildInvite(playerName)
        print("|cFF3EB9D8[FGR]|r Guild invite sent to " .. playerName)
        
        if withMessage then
            print("|cFFFFFF00[FGR]|r InviteManager not available for welcome message")
        end
    end
end

function ContextMenu:HandleManualBlacklist(playerName)
    if ns.BlacklistManager and ns.BlacklistManager.Add then
        local reason = "Added via context menu"
        ns.BlacklistManager:Add(playerName, reason, false)
        print("|cFF3EB9D8[FGR]|r Added " .. playerName .. " to blacklist")
    else
        -- Fallback
        ns.tblBlackList = ns.tblBlackList or {}
        local key = strlower(playerName:match('-') and playerName or playerName..'-'..GetRealmName())
        ns.tblBlackList[key] = {
            key = key,
            name = playerName,
            reason = "Added via context menu",
            blBy = UnitName('player'),
            date = time(),
            private = false,
        }
        print("|cFF3EB9D8[FGR]|r Added " .. playerName .. " to blacklist (fallback)")
    end
end

-- Initialize the context menu system when the file loads
-- But don't error if it fails
local success, err = pcall(function()
    ContextMenu:Initialize()
end)

if not success then
    if ns.Logger and ns.Logger.Error then
        ns.Logger:Error("Context menu initialization failed: %s", tostring(err))
    else
        print("|cFFFF0000[FGR]|r Context menu initialization failed: " .. tostring(err))
    end
end