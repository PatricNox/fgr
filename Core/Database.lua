-- Core/Database.lua
local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

ns.Database = {}
local Database = ns.Database

local DB = LibStub('AceDB-3.0')
local DATABASE_VERSION = 5

-- Database schema definitions
local DEFAULT_PROFILE_SCHEMA = {
    profile = {
        settings = {
            ui = {
                compactMode = false,
                keepOpen = false,
                showContextMenu = true,
                showAppMsgs = true,
                minimap = { hide = false, angle = 220, radius = 80 },
            },
            recruitment = {
                minLevel = GetMaxPlayerLevel(),
                maxLevel = GetMaxPlayerLevel(),
                activeFilter = 9999,
                activeMessage = nil,
                enableAutoSync = true,
                showWhispers = true,
                inviteFormat = 2,
                isCompact = false,
            },
            debugMode = false,
            antiSpam = {
                enabled = true,
                days = 7,
            },
            messages = {
                messageList = {},
                sendGuildGreeting = true,
                guildMessage = L['DEFAULT_GUILD_WELCOME'],
                sendWhisperGreeting = false,
                whisperMessage = '',
            },
        },
        analytics = {},
    },
    global = {
        version = DATABASE_VERSION,
        performance = {
            timeBetweenMessages = "0.2",
            scanWaitTime = 5,
        },
        ui = {
            showWhatsNew = true,
            showToolTips = true,
            compactSize = 1,
        },
        keybindings = {
            scan = 'CTRL-SHIFT-S',
            invite = 'CTRL-SHIFT-I',
        },
        zoneList = {},
        guilds = {},
    }
}

local GUILD_SCHEMA = {
    info = {
        clubID = nil,
        guildName = '',
        guildLink = '',
    },
    settings = {
        showConsoleMessages = false,
        antiSpam = true,
        antiSpamDays = 7,
        sendGuildGreeting = true,
        guildMessage = L['DEFAULT_GUILD_WELCOME'],
        sendWhisperGreeting = false,
        whisperMessage = '',
        messageList = {},
    },
    leadership = {
        isGuildLeader = false,
        guildLeaderToon = nil,
        gmActive = false,
        gmSettings = {
            forceMessageList = false,
            forceSendWhisper = false,
            forceInviteMessage = false,
            forceWhisperMessage = false,
            forceSendGuildGreeting = false,
            antiSpam = true,
            antiSpamDays = 7,
            sendGuildGreeting = true,
            guildMessage = L['DEFAULT_GUILD_WELCOME'],
            sendWhisperGreeting = false,
            whisperMessage = '',
            messageList = {},
        },
    },
    data = {
        blackList = {},
        antiSpamList = {},
        filterList = {},
        messageList = {},
        blackListRemoved = {},
    },
    analytics = {},
    sync = {
        lastSync = {},
    },
}

function Database:Initialize()
    self.db = nil
    self.isInitialized = false
    
    -- Use safe logging since Logger might not be fully initialized
    if ns.Logger and ns.Logger.Debug then
        ns.Logger:Debug("Database module initialized")
    else
        print("[FGR] Database module initialized")
    end
end

function Database:InitializeForGuild(clubID)
    self.db = DB:New(FGR.db, DEFAULT_PROFILE_SCHEMA)
    
    if not self.db then
        return false, "Failed to create database"
    end

    local needsReset = self:CheckDatabaseVersion()
    if needsReset then
        return false, "Database was reset"
    end

    if not self.db.global.guilds[clubID] then
        self.db.global.guilds[clubID] = self:CreateGuildData()
    end

    self:SetupNamespaceReferences(clubID)
    
    self.isInitialized = true
    
    -- Use safe logging
    if ns.Logger and ns.Logger.Info then
        ns.Logger:Info("Database initialized for guild ID: %s", tostring(clubID))
    else
        print(string.format("[FGR] Database initialized for guild ID: %s", tostring(clubID)))
    end
    
    return true, nil
end

function Database:CreateGuildData()
    if ns.Utils and ns.Utils.DeepCopy then
        return ns.Utils:DeepCopy(GUILD_SCHEMA)
    else
        -- Fallback deep copy function
        local function deepCopy(original)
            if type(original) ~= 'table' then return original end
            local copy = {}
            for k, v in pairs(original) do
                copy[k] = deepCopy(v)
            end
            return copy
        end
        return deepCopy(GUILD_SCHEMA)
    end
end

function Database:CheckDatabaseVersion()
    if not self.db.global.version or self.db.global.version < DATABASE_VERSION then
        local migrated = false
        
        if ns.Migration and ns.Migration.MigrateDatabase then
            migrated = ns.Migration:MigrateDatabase(self.db)
        end
        
        if not migrated then
            self:ResetDatabase()
            return true
        end
    end
    return false
end

function Database:ResetDatabase()
    self.db.global = self.db.global and table.wipe(self.db.global) or {}
    self.db:ResetProfile()

    for profileName in pairs(self.db.profiles) do
        self.db.profiles[profileName] = nil
    end

    self.db.global.version = DATABASE_VERSION
    
    -- Use safe logging
    if ns.Logger and ns.Logger.Error then
        ns.Logger:Error(L['DATABASE_RESET'])
    else
        print("|cFFFF0000[FGR-ERROR] " .. (L['DATABASE_RESET'] or "Database reset") .. "|r")
    end
end

function Database:SetupNamespaceReferences(clubID)
    local db = self.db
    local guild = db.global.guilds[clubID]
    
    -- Set up the old-style references for backward compatibility
    ns.p = db.profile
    ns.g = db.global
    ns.guild = guild
    ns.db = db
    
    -- Set up more specific references
    ns.pAnalytics = ns.p.analytics
    ns.gAnalytics = ns.guild.analytics
    ns.pSettings = ns.p.settings
    ns.gSettings = ns.guild.settings
    ns.guildInfo = ns.guild.info
    ns.gmSettings = ns.guild.leadership.gmSettings
    ns.gFilterList = ns.guild.data.filterList
    
    -- Set up GM status
    ns.isGM = ns.guild.leadership.isGuildLeader or IsGuildLeader() or false
    
    -- Set debug mode
    FGR.debug = FGR.isTesting or (ns.pSettings.debugMode == true)
end

function Database:SaveCompressedData(key, data)
    if not self.isInitialized then return false end
    
    local compressed = data -- Will be actual compression later
    if ns.Utils and ns.Utils.CompressData then
        compressed = ns.Utils:CompressData(data)
    end
    
    if compressed then
        ns.guild.data[key] = compressed
        return true
    end
    return false
end

function Database:LoadCompressedData(key)
    if not self.isInitialized then return false, nil end
    
    if ns.Utils and ns.Utils.DecompressData then
        return ns.Utils:DecompressData(ns.guild.data[key] or {})
    else
        return true, ns.guild.data[key] or {}
    end
end

function Database:SaveData()
    if not self.isInitialized or not self.db then return false end
    
    -- Force AceDB to save by updating timestamps at multiple levels
    self.db.global.lastSave = time()
    
    if self.db.profile then
        self.db.profile.lastUpdate = time()
    end
    
    -- If we have guild data, touch it to trigger save
    if ns.guild then
        ns.guild.lastModified = time()
        
        -- Specifically touch the data that might have changed
        if ns.guild.data then
            ns.guild.data.lastUpdate = time()
            
            -- Touch message list specifically
            if ns.guild.data.messageList then
                ns.guild.data.messageListUpdated = time()
            end
        end
    end
    
    if ns.Logger then
        ns.Logger:Debug("Database save triggered - timestamp: %s", tostring(time()))
    end
    return true
end


function Database:OnAddonUnloading()
    if self.isInitialized and self.db then
        -- Force save by updating timestamps
        self.db.global.shutdownTime = time()
        if self.db.profile then
            self.db.profile.shutdownTime = time()
        end
        
        -- If we have guild data, update its timestamp too
        if ns.guild then
            ns.guild.lastShutdown = time()
            -- Specifically touch message data
            if ns.guild.data and ns.guild.data.messageList then
                ns.guild.data.messageListSaveTime = time()
            end
        end
        
        if ns.Logger then
            ns.Logger:Info("Database save triggered on addon unload")
        else
            print("[FGR] Database save triggered on addon unload")
        end
    end
end

function Database:SaveMessageList(messageList)
    if not self.isInitialized then return false end
    
    -- Ensure the path exists
    if not ns.guild then return false end
    if not ns.guild.data then ns.guild.data = {} end
    
    -- Save the message list
    ns.guild.data.messageList = messageList or {}
    
    -- Add multiple timestamps to ensure AceDB detects the change
    ns.guild.data.messageListUpdated = time()
    ns.guild.data.messageCount = #(messageList or {})
    ns.guild.lastModified = time()
    
    -- Force save
    self:SaveData()
    
    if ns.Logger then
        ns.Logger:Debug("SaveMessageList: %d messages saved with timestamp %s", 
                       #(messageList or {}), tostring(time()))
    else
        print("|cFF00FFFF[FGR-DEBUG]|r SaveMessageList: " .. #(messageList or {}) .. " messages saved")
    end
    
    return true
end

function Database:GetMessageList()
    if not self.isInitialized then return {} end
    
    -- Ensure the path exists
    if not ns.guild then ns.guild = {data = {}} end
    if not ns.guild.data then ns.guild.data = {} end
    if not ns.guild.data.messageList then ns.guild.data.messageList = {} end
    
    return ns.guild.data.messageList
end



-- Initialize the database module
Database:Initialize()