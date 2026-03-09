-- Core/Init.lua
local addonName, ns = ...

-- Initialize namespace
ns.Core = {}
local Core = ns.Core

-- Create the main addon object
local AceAddon = LibStub and LibStub:GetLibrary("AceAddon-3.0", true)
if AceAddon then
    FGR = AceAddon:NewAddon(addonName, 'AceConsole-3.0', 'AceEvent-3.0', 'AceTimer-3.0', "AceHook-3.0")
else
    -- Fallback addon object
    FGR = {
        events = {},
        hooks = {},
        chatCommands = {},
    }
    
    local frame = CreateFrame("Frame", addonName .. "EventFrame")
    
    function FGR:RegisterEvent(event, handler)
        if not self.events[event] then
            self.events[event] = {}
            frame:RegisterEvent(event)
        end
        table.insert(self.events[event], handler)
    end
    
    function FGR:UnregisterEvent(event, handler)
        if handler then
            if self.events[event] then
                for i, h in ipairs(self.events[event]) do
                    if h == handler then
                        table.remove(self.events[event], i)
                        break
                    end
                end
            end
        else
            self.events[event] = nil
            frame:UnregisterEvent(event)
        end
    end
    
    function FGR:UnregisterAllEvents()
        frame:UnregisterAllEvents()
        self.events = {}
    end
    
    function FGR:RegisterChatCommand(command, handler)
        self.chatCommands[command] = handler
        _G["SLASH_" .. addonName .. "_" .. strupper(command) .. "1"] = "/" .. command
        SlashCmdList[addonName .. "_" .. strupper(command)] = handler
    end
    
    frame:SetScript("OnEvent", function(self, event, ...)
        if FGR.events[event] then
            for _, handler in ipairs(FGR.events[event]) do
                handler(event, ...)
            end
        end
    end)
    
    if ns.Logger then
        ns.Logger:Warn("Ace3 libraries not found, using fallback systems")
    end
end

-- Addon metadata
FGR.title = C_AddOns.GetAddOnMetadata(addonName, 'Title')
FGR.author = C_AddOns.GetAddOnMetadata(addonName, 'Author')
FGR.version = C_AddOns.GetAddOnMetadata(addonName, 'Version')
FGR.db = addonName == 'FGR' and 'FGRDB' or 'devFGRDB'
FGR.ICON_PATH = 'Interface\\AddOns\\'..addonName..'\\Images\\'
FGR.debug = false

FGR.isPreRelease = false
FGR.preReleaseType = 'Beta'
FGR.versionOut = '(v'..FGR.version..(FGR.isPreRelease and ' '..FGR.preReleaseType or '')..')'

-- Track if we've initialized basic systems
Core.basicSystemsInitialized = false

function Core:Initialize()
    self.isEnabled = false
    self.fullyStarted = false
    self.ignoreAutoSync = false
    self.minimapIcon = nil
    
    -- Set up version info
    ns.classic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or false
    ns.cata = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC or false
    ns.retail = not ns.classic and not ns.cata
    
    -- Initialize basic systems regardless of guild status
    if not self.basicSystemsInitialized then
        self:InitializeBasicSystems()
        self.basicSystemsInitialized = true
    end
    
    if ns.Logger then
        ns.Logger:Info("Fast Guild Recruiter Core initialized")
    end
end

function Core:InitializeBasicSystems()
    -- Initialize systems that don't require guild membership
    ns.tblBlackList = ns.tblBlackList or {}
    ns.tblAntiSpamList = ns.tblAntiSpamList or {}
    
    -- Initialize WindowManager EARLY (before other UI systems)
    if ns.WindowManager then
        ns.WindowManager:Initialize()
    end
    
    -- Set up player info
    if ns.Utils and ns.Utils.CreatePlayerString then
        ns.fPlayerName = ns.Utils:CreatePlayerString(GetUnitName('player', false), UnitClassBase('player'))
    else
        ns.fPlayerName = GetUnitName('player', false)
    end
end

function Core:InitializeBasicSettings()
    -- Initialize basic settings even without full database
    ns.p = ns.p or { settings = {} }
    ns.g = ns.g or {}
    
    print("|cFF3EB9D8[FGR]|r Fast Guild Recruiter loaded. Commands should be available now.")
end

function Core:CheckIfInGuild(count, callback)
    count = count or 0
    local clubID = C_Club.GetGuildClubId()

    if clubID and CanGuildInvite() then
        self.isEnabled = true
        if callback then callback(clubID) end
        return clubID
    elseif count >= 30 then
        if ns.Logger then
            ns.Logger:Warn("Not in guild or cannot invite - limited functionality available")
        else
            print("|cFFFFFF00[FGR]|r Not in guild or cannot invite - limited functionality available")
        end
        if callback then callback(nil) end
        return
    elseif not CanGuildInvite() or not IsInGuild() or not clubID or not GetGuildInfo('player') then
        C_Timer.After(1, function() 
            self:CheckIfInGuild(count + 1, callback) 
        end)
    end
end

function Core:StartGuildRecruiter(clubID)
    if not clubID then
        if ns.Logger then
            ns.Logger:Info("Running in limited mode - not in guild or cannot invite")
        else
            print("|cFFFFFF00[FGR]|r Running in limited mode - not in guild or cannot invite")
        end
        return
    end
    
    FGR.clubID = clubID

    -- Initialize database
    local success, error = false, "Database not available"
    if ns.Database then
        success, error = ns.Database:InitializeForGuild(clubID)
    end
    
    if not success then
        self.isEnabled = false
        if FGR.UnregisterAllEvents then
            FGR:UnregisterAllEvents()
        end
        if ns.Logger then
            ns.Logger:Error("Database initialization failed: %s", tostring(error))
        else
            print("|cFFFF0000[FGR]|r Database initialization failed: " .. tostring(error))
        end
        return
    end

    -- Initialize other systems
    self:LoadDataTables()
    self:PerformMaintenance()
    self:SetupGuild(clubID)
    
    -- Initialize modules
    if ns.MinimapIcon then ns.MinimapIcon:Initialize() end
    if ns.InviteManager then ns.InviteManager:Initialize() end
    if ns.ContextMenu then ns.ContextMenu:Initialize() end
    if ns.EventManager then ns.EventManager:StartBaseEvents() end

    if ns.Logger then
        ns.Logger:Info("Fast Guild Recruiter fully enabled for guild operations")
    else
        print("|cFF3EB9D8[FGR]|r Fast Guild Recruiter fully enabled for guild operations")
    end
    
    self.isEnabled = true
end

function Core:LoadDataTables()
    ns.tblBlackList = ns.tblBlackList or {}
    ns.tblAntiSpamList = ns.tblAntiSpamList or {}

    if ns.Utils and ns.guild then
        local blSuccess, tblBL = ns.Utils:DecompressData(ns.guild.data and ns.guild.data.blackList or {})
        ns.tblBlackList = blSuccess and tblBL or {}

        local asSuccess, tblAS = ns.Utils:DecompressData(ns.guild.data and ns.guild.data.antiSpamList or {})
        ns.tblAntiSpamList = asSuccess and tblAS or {}
    end

    if ns.DataSources then
        local version = ns.retail and 'retail' or ns.classic and 'classic' or 'cata'
        ns.races = ns.DataSources:GetRaces(version)
        ns.classes = ns.DataSources:GetClasses(version)
        ns.invalidZones = ns.DataSources:GetInvalidZones(version)
    end

    if ns.Logger then
        ns.Logger:Debug("Data tables loaded successfully")
    end
end

function Core:PerformMaintenance()
    -- Move Player Message List to GM Message List if needed
    if ns.isGM and ns.pSettings and ns.pSettings.messages and ns.pSettings.messages.messageList and #ns.pSettings.messages.messageList > 0 then
        if ns.gmSettings and ns.gmSettings.messageList then
            for _, v in pairs(ns.pSettings.messages.messageList) do
                table.insert(ns.gmSettings.messageList, v)
            end
            ns.pSettings.messages.messageList = {}
            if ns.Logger then
                ns.Logger:Debug("Moved player messages to GM message list")
            end
        end
    end

    -- Clean old anti-spam records
    if ns.tblAntiSpamList then
        local currentTime = time()
        local antiSpamDays = 7
        
        if ns.gmSettings and ns.gmSettings.antiSpamDays then
            antiSpamDays = ns.gmSettings.antiSpamDays
        elseif ns.gSettings and ns.gSettings.antiSpamDays then
            antiSpamDays = ns.gSettings.antiSpamDays
        end
        
        local removed = 0
        for name, data in pairs(ns.tblAntiSpamList) do
            if data and data.time then
                local timeDiff = currentTime - data.time
                if timeDiff >= antiSpamDays * 86400 then
                    ns.tblAntiSpamList[name] = nil
                    removed = removed + 1
                end
            end
        end
        
        if removed > 0 and ns.Logger then
            ns.Logger:Debug("Removed %d expired anti-spam entries", removed)
        end
    end
    
    -- Validate message list data structure
    if ns.Database and ns.Database.isInitialized then
        local messageList = ns.Database:GetMessageList()
        if ns.Logger then
            ns.Logger:Debug("Maintenance check - found %d message templates", #messageList)
        end
    end
end

function Core:SetupGuild(clubID)
    local guildName = GetGuildInfo('player')
    
    if ns.guildInfo then
        ns.guildInfo.clubID = clubID
        ns.guildInfo.guildName = guildName
    end

    -- Set up GM status
    ns.isGM = (ns.guild and ns.guild.leadership and ns.guild.leadership.isGuildLeader) or IsGuildLeader() or false
    
    if ns.isGM then
        if ns.guild and ns.guild.leadership then
            ns.guild.leadership.isGuildLeader = true
            ns.guild.leadership.guildLeaderToon = GetUnitName('player', true)
        end
        if ns.Logger then
            ns.Logger:Info("Guild Master detected: %s", GetUnitName('player', true))
        end
    else
        if ns.guild and ns.guild.leadership then
            ns.gmActive = ns.guild.leadership.gmActive or false
            
            if GetUnitName('player', true) == ns.guild.leadership.guildLeaderToon then
                ns.guild.leadership.isGuildLeader = false
                ns.guild.leadership.guildLeaderToon = nil
                if ns.Logger then
                    ns.Logger:Info("Player is no longer guild leader")
                end
            end
        end
    end

    -- Set up guild link for retail
    if not ns.classic then
        self:CreateGuildLink(0, clubID, guildName)
    end
end

function Core:CreateGuildLink(retry, clubID, guildName)
    retry = retry + 1
    local club = clubID and ClubFinderGetCurrentClubListingInfo and ClubFinderGetCurrentClubListingInfo(clubID) or nil

    if club then
        local guildLink = "|cffffd200|HclubFinder:"..club.clubFinderGUID.."|h["..club.name.."]|h|r"
        if ns.guildInfo then
            ns.guildInfo.guildLink = guildLink
        end
        if ns.Logger then
            ns.Logger:Debug("Guild link created successfully")
        end
        return
    elseif retry >= 10 then
        if ns.guildInfo then
            ns.guildInfo.guildLink = nil
        end
        if ns.Logger then
            ns.Logger:Warn("Could not create guild link")
        else
            print("|cFFFFFF00[FGR]|r Could not create guild link")
        end
        return
    else 
        C_Timer.After(1, function() 
            self:CreateGuildLink(retry, clubID, guildName) 
        end) 
    end
end

-- Event handlers
local function OnPlayerLogin()
    if FGR.UnregisterEvent then
        FGR:UnregisterEvent('PLAYER_LOGIN', OnPlayerLogin)
    end
    
    Core:CheckIfInGuild(0, function(clubID)
        if clubID then 
            Core:StartGuildRecruiter(clubID) 
        end
    end)
end

-- Register the login event
if FGR.RegisterEvent then
    FGR:RegisterEvent('PLAYER_LOGIN', OnPlayerLogin)
end

-- Initialize the core
Core:Initialize()

-- Database persistence event handler
local persistenceFrame = CreateFrame("Frame")
persistenceFrame:RegisterEvent("ADDON_LOADED")
persistenceFrame:RegisterEvent("PLAYER_LOGOUT")
persistenceFrame:RegisterEvent("PLAYER_CAMPING")
persistenceFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "FastGuildRecruiter" then
        if ns.Logger then
            ns.Logger:Debug("Registered database persistence events")
        else
            print("[FGR] Registered database persistence events")
        end
    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_CAMPING" then
        if ns.Database and ns.Database.OnAddonUnloading then
            ns.Database:OnAddonUnloading()
        end
        -- Force save any pending data
        if ns.Database and ns.Database.isInitialized and ns.Database.db then
            ns.Database.db.global.shutdownTime = time()
            if ns.Logger then
                ns.Logger:Info("Database saved on logout/camping")
            else
                print("[FGR] Database saved on logout/camping")
            end
        end
    end
end)