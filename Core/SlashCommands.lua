-- Core/SlashCommands.lua
local addonName, ns = ...
local L = LibStub and LibStub:GetLibrary("AceLocale-3.0", true)
if L then
    L = L:GetLocale(addonName, true)
end
L = L or {}

ns.SlashCommands = {}
local SlashCommands = ns.SlashCommands

function SlashCommands:Initialize()
    self:RegisterCommands()
    if ns.Logger and ns.Logger.Debug then
        ns.Logger:Debug("Slash commands initialized")
    end
end

function SlashCommands:RegisterCommands()
    local function slashCommand(msg)
        msg = msg and strtrim(strlower(msg)) or ""

        if not msg or msg == '' then
            self:HandleEmptyCommand()
        elseif msg == strlower(L['HELP'] or 'help') then
            self:ShowHelp()
        elseif msg == strlower(L['CONFIG'] or 'config') or msg == 'config' or msg == 'settings' then
            self:OpenSettings()
        elseif msg:match(strlower(L['BLACKLIST'] or 'blacklist')) or msg:match('blacklist') then
            self:HandleBlacklistCommand(msg)
        elseif msg == 'debug' then
            self:ToggleDebug()
        elseif msg == 'status' then
            self:ShowStatus()
        else
            self:ShowHelp()
        end
    end

    -- Register multiple command variants
    local commands = {'fgr', 'gr', 'recruiter', 'guildrecruiter'}
    for _, cmd in ipairs(commands) do
        if FGR and FGR.RegisterChatCommand then
            FGR:RegisterChatCommand(cmd, slashCommand)
        else
            -- Fallback registration
            _G["SLASH_" .. strupper(cmd) .. "1"] = "/" .. cmd
            SlashCmdList[strupper(cmd)] = slashCommand
        end
    end
    
    print("|cFF3EB9D8[FGR]|r Slash commands registered: /fgr, /gr, /recruiter")
end

function SlashCommands:HandleEmptyCommand()
    -- Check if MainFrame exists and is available
    if ns.UI and ns.UI.MainFrame and ns.UI.MainFrame.Toggle then
        ns.UI.MainFrame:Toggle()
    else
        print("|cFF3EB9D8[FGR]|r Main UI not available yet. Use /fgr config to open settings.")
        print("|cFF3EB9D8[FGR]|r Available commands: /fgr help")
    end
end

function SlashCommands:ShowHelp()
    local help = {
        "|cFF3EB9D8Fast Guild Recruiter Commands:|r",
        "/fgr - Toggle main window",
        "/fgr config - Open settings",
        "/fgr help - Show this help",
        "/fgr status - Show addon status",
        "/fgr debug - Toggle debug mode",
        "/fgr blacklist <name> - Add player to blacklist",
    }
    
    for _, line in ipairs(help) do
        print(line)
    end
end

function SlashCommands:OpenSettings()
    if ns.SettingsManager and ns.SettingsManager.OpenSettings then
        ns.SettingsManager:OpenSettings()
    elseif Settings and Settings.OpenToCategory then
        Settings.OpenToCategory('Fast Guild Recruiter')
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory('Fast Guild Recruiter')
    else
        print("|cFFFF0000[FGR]|r Settings not available - addon may not be fully loaded")
    end
end


function SlashCommands:HandleBlacklistCommand(msg)
    local name = msg:gsub('blacklist', ''):trim()
    if name and name ~= '' then
        name = strupper(strsub(name,1,1))..strlower(strsub(name,2))
        if ns.BlacklistManager then
            ns.BlacklistManager:Add(name, "Added via slash command")
            print("|cFF3EB9D8[FGR]|r Added " .. name .. " to blacklist")
        else
            print("|cFFFF0000[FGR]|r Blacklist manager not available")
        end
    else
        print("|cFFFF0000[FGR]|r Usage: /fgr blacklist <playername>")
    end
end

function SlashCommands:ToggleDebug()
    FGR.debug = not FGR.debug
    print("|cFF3EB9D8[FGR]|r Debug mode: " .. (FGR.debug and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
end

function SlashCommands:ShowStatus()
    local status = {
        "|cFF3EB9D8Fast Guild Recruiter Status:|r",
        "Version: " .. (FGR.version or "Unknown"),
        "Core Enabled: " .. (ns.Core and ns.Core.isEnabled and "Yes" or "No"),
        "In Guild: " .. (IsInGuild() and "Yes" or "No"),
        "Can Invite: " .. (CanGuildInvite() and "Yes" or "No"),
        "Debug Mode: " .. (FGR.debug and "On" or "Off"),
        "Main UI Available: " .. (ns.UI and ns.UI.MainFrame and "Yes" or "No"),
    }
    
    if ns.tblBlackList then
        local blCount = 0
        for _ in pairs(ns.tblBlackList) do blCount = blCount + 1 end
        table.insert(status, "Blacklisted Players: " .. blCount)
    end
    
    if ns.tblAntiSpamList then
        local asCount = 0
        for _ in pairs(ns.tblAntiSpamList) do asCount = asCount + 1 end
        table.insert(status, "Anti-Spam Entries: " .. asCount)
    end
    
    for _, line in ipairs(status) do
        print(line)
    end
end

-- Helper function for string trimming
function string:trim()
    return self:match("^%s*(.-)%s*$")
end

-- Initialize slash commands when this file loads, but with a delay to ensure FGR exists
local function InitializeSlashCommands()
    if FGR then
        SlashCommands:Initialize()
    else
        -- If FGR doesn't exist yet, wait and try again
        C_Timer.After(0.1, InitializeSlashCommands)
    end
end

InitializeSlashCommands()