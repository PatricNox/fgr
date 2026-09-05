-- Modules/Invites/InviteManager.lua
local addonName, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

ns.InviteManager = {}
local InviteManager = ns.InviteManager

-- Constants
local SCAN_TYPES = {
    WHO_LIST = 1,
    TARGET = 2,
    GUILD_ROSTER = 3,
    NEARBY_PLAYERS = 4,
}

local INVITE_RESULTS = {
    SUCCESS = "success",
    FAILED = "failed",
    BLACKLISTED = "blacklisted", 
    ANTI_SPAM = "anti_spam",
    ALREADY_GUILDED = "already_guilded",
    INVALID_LEVEL = "invalid_level",
    INVALID_TARGET = "invalid_target",
    NO_MESSAGE = "no_message",
}

function InviteManager:Initialize()
    self.isInitialized = true
    self.isScanning = false
    self.scanResults = {}
    self.inviteQueue = {}
    self.messageQueue = {}
    self.currentScanType = nil
    
    -- Throttling
    self.lastScanTime = 0
    self.lastInviteTime = 0
    self.lastMessageTime = 0
    
    if ns.Logger then
        ns.Logger:Debug("InviteManager initialized")
    end
end

-- Player Scanning Functions
function InviteManager:StartScan(scanType, filters)
    if self.isScanning then
        print("|cFFFF0000[FGR]|r Scan already in progress")
        return false
    end
    
    -- Check scan throttling (15 seconds minimum)
    local currentTime = GetTime()
    if currentTime - self.lastScanTime < 15 then
        local remaining = 15 - (currentTime - self.lastScanTime)
        print("|cFFFF0000[FGR]|r Scan on cooldown. " .. math.ceil(remaining) .. " seconds remaining")
        return false
    end
    
    self.isScanning = true
    self.currentScanType = scanType
    self.scanResults = {}
    self.lastScanTime = currentTime
    
    print("|cFF3EB9D8[FGR]|r Starting player scan...")
    
    if scanType == SCAN_TYPES.WHO_LIST then
        self:ScanWhoList(filters)
    elseif scanType == SCAN_TYPES.TARGET then
        self:ScanTarget()
    elseif scanType == SCAN_TYPES.GUILD_ROSTER then
        self:ScanGuildRoster()
    elseif scanType == SCAN_TYPES.NEARBY_PLAYERS then
        self:ScanNearbyPlayers()
    else
        self.isScanning = false
        print("|cFFFF0000[FGR]|r Invalid scan type")
        return false
    end
    
    return true
end

function InviteManager:ScanWhoList(filters)
    filters = filters or {}
    local minLevel = filters.minLevel or 10
    local maxLevel = filters.maxLevel or GetMaxPlayerLevel()
    local zone = filters.zone or GetZoneText()
    
    -- Build who query
    local query = string.format("%d-%d %s", minLevel, maxLevel, zone)
    
    if ns.Logger then
        ns.Logger:Debug("Scanning who list with query: %s", query)
    end
    
    -- Clear previous results
    FriendsFrame_SendWho(query)
    
    -- Process results after a delay
    C_Timer.After(2, function()
        self:ProcessWhoResults()
    end)
end

function InviteManager:ProcessWhoResults()
    local numWhoResults = C_FriendList.GetNumWhoResults()
    
    if numWhoResults == 0 then
        print("|cFFFFFF00[FGR]|r No players found in scan")
        self.isScanning = false
        return
    end
    
    print("|cFF3EB9D8[FGR]|r Found " .. numWhoResults .. " players, filtering...")
    
    local validPlayers = {}
    
    for i = 1, numWhoResults do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName then
            local player = self:ProcessPlayerInfo(info)
            if player and self:IsValidRecruitTarget(player) then
                table.insert(validPlayers, player)
            end
        end
    end
    
    self.scanResults = validPlayers
    self.isScanning = false
    
    print("|cFF3EB9D8[FGR]|r Scan complete: " .. #validPlayers .. " valid targets found")
    
    if #validPlayers > 0 then
        self:ShowScanResults()
    end
end

function InviteManager:ProcessPlayerInfo(whoInfo)
    local name = whoInfo.fullName
    local level = whoInfo.level
    local zone = whoInfo.area
    local guild = whoInfo.guild
    local classFilename = whoInfo.filename
    
    -- Split name-realm if present
    local playerName, realm = strsplit("-", name)
    if not realm or realm == "" then
        realm = GetRealmName()
    end
    
    return {
        name = playerName,
        fullName = name,
        realm = realm,
        level = level,
        zone = zone,
        guild = guild,
        class = classFilename,
        isTarget = false,
        source = "who_list"
    }
end

function InviteManager:ScanTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        print("|cFFFF0000[FGR]|r No valid player target")
        self.isScanning = false
        return
    end
    
    local name = UnitName("target")
    local level = UnitLevel("target")
    local guild = GetGuildInfo("target")
    local _, classFilename = UnitClass("target")
    
    local player = {
        name = name,
        fullName = name .. "-" .. GetRealmName(),
        realm = GetRealmName(),
        level = level,
        zone = GetZoneText(),
        guild = guild,
        class = classFilename,
        isTarget = true,
        source = "target"
    }
    
    if self:IsValidRecruitTarget(player) then
        self.scanResults = {player}
        print("|cFF3EB9D8[FGR]|r Target scan complete: " .. name .. " is valid")
    else
        self.scanResults = {}
        print("|cFFFF0000[FGR]|r Target " .. name .. " is not a valid recruitment target")
    end
    
    self.isScanning = false
    self:ShowScanResults()
end

function InviteManager:ScanNearbyPlayers()
    -- This would scan players within visual range
    -- Implementation depends on available APIs
    print("|cFFFFFF00[FGR]|r Nearby player scanning not yet implemented")
    self.isScanning = false
end

function InviteManager:ScanGuildRoster()
    -- This would scan for players who applied to guild
    print("|cFFFFFF00[FGR]|r Guild roster scanning not yet implemented")
    self.isScanning = false
end

-- Validation Functions
function InviteManager:IsValidRecruitTarget(player)
    if not player or not player.name then return false end
    
    -- Check if already in a guild
    if player.guild and player.guild ~= "" then
        if ns.Logger then
            ns.Logger:Debug("Player %s already in guild: %s", player.name, player.guild)
        end
        return false
    end
    
    -- Check blacklist
    if self:IsBlacklisted(player.name) then
        if ns.Logger then
            ns.Logger:Debug("Player %s is blacklisted", player.name)
        end
        return false
    end
    
    -- Check anti-spam
    if self:IsAntiSpamBlocked(player.name) then
        if ns.Logger then
            ns.Logger:Debug("Player %s blocked by anti-spam", player.name)
        end
        return false
    end
    
    -- Check level range
    if not self:IsValidLevel(player.level) then
        if ns.Logger then
            ns.Logger:Debug("Player %s invalid level: %d", player.name, player.level)
        end
        return false
    end
    
    -- Check if in invalid zone
    if self:IsInvalidZone(player.zone) then
        if ns.Logger then
            ns.Logger:Debug("Player %s in invalid zone: %s", player.name, player.zone)
        end
        return false
    end
    
    return true
end

function InviteManager:IsBlacklisted(playerName)
    if not ns.tblBlackList then return false end
    local key = string.lower(playerName)
    return ns.tblBlackList[key] ~= nil
end

function InviteManager:IsAntiSpamBlocked(playerName)
    if not ns.gSettings.antiSpam then return false end
    if not ns.tblAntiSpamList then return false end
    local key = string.lower(playerName)
    local entry = ns.tblAntiSpamList[key]
    
    if not entry then return false end
    
    local antiSpamDays = 7
    if ns.gSettings and ns.gSettings.antiSpamDays then
        antiSpamDays = ns.gSettings.antiSpamDays
    end
    
    local timeDiff = time() - (entry.time or 0)
    return timeDiff < (antiSpamDays * 86400)
end

function InviteManager:IsValidLevel(level)
    if not level then return false end
    
    local minLevel = 1
    local maxLevel = GetMaxPlayerLevel()
    
    if ns.pSettings and ns.pSettings.recruitment then
        minLevel = ns.pSettings.recruitment.minLevel or minLevel
        maxLevel = ns.pSettings.recruitment.maxLevel or maxLevel
    end
    
    return level >= minLevel and level <= maxLevel
end

function InviteManager:IsInvalidZone(zoneName)
    if not zoneName then return false end
    
    -- Check global invalid zones
    if ns.invalidZones then
        local key = string.lower(zoneName)
        if ns.invalidZones[key] then return true end
    end
    
    -- Check player-defined invalid zones
    if ns.g and ns.g.zoneList then
        local key = string.lower(zoneName)
        if ns.g.zoneList[key] then return true end
    end
    
    return false
end

-- Results Display
function InviteManager:ShowScanResults()
    if not self.scanResults or #self.scanResults == 0 then
        print("|cFFFFFF00[FGR]|r No valid recruitment targets found")
        return
    end
    
    print("|cFF3EB9D8[FGR]|r Scan Results (" .. #self.scanResults .. " players):")
    print("------------------------------------")
    
    for i, player in ipairs(self.scanResults) do
        local levelColor = GetQuestDifficultyColor(player.level)
        local colorCode = string.format("|cFF%02X%02X%02X", 
            levelColor.r * 255, levelColor.g * 255, levelColor.b * 255)
        
        print(string.format("%d. %s%s|r (%s%d|r) - %s", 
            i, colorCode, player.name, colorCode, player.level, player.zone or "Unknown"))
    end
    
    print("------------------------------------")
    print("Use /fgr invite <number> or /fgr message <number> to contact players")
    print("Use /fgr inviteall or /fgr messageall to contact all players")
end

-- Individual Invite/Message Functions
function InviteManager:InvitePlayer(playerIndex, skipMessage)
    if not self.scanResults or not self.scanResults[playerIndex] then
        print("|cFFFF0000[FGR]|r Invalid player index")
        return
    end
    
    local player = self.scanResults[playerIndex]
    self:SendGuildInvite(player.name, skipMessage)
end

function InviteManager:MessagePlayer(playerIndex, messageIndex)
    if not self.scanResults or not self.scanResults[playerIndex] then
        print("|cFFFF0000[FGR]|r Invalid player index")
        return
    end
    
    local player = self.scanResults[playerIndex]
    self:SendRecruitmentMessage(player.name, messageIndex)
end

-- Core Invite/Message Functions
function InviteManager:SendGuildInvite(playerName, skipMessage)
    if not CanGuildInvite() then
        print("|cFFFF0000[FGR]|r You don't have permission to invite players")
        return
    end
    
    -- Add to anti-spam list
    self:AddToAntiSpam(playerName)
    
    -- Send the invite
    ns.GuildInvite(playerName)
    
    print("|cFF3EB9D8[FGR]|r Guild invite sent to: " .. playerName)
    
    -- Send welcome message if not skipped
    if not skipMessage then
        C_Timer.After(1, function()
            self:SendWelcomeMessage(playerName)
        end)
    end
end

function InviteManager:SendRecruitmentMessage(playerName, messageIndex)
    local message = self:GetRecruitmentMessage(messageIndex)
    if not message or message == "" then
        print("|cFFFF0000[FGR]|r No recruitment message available")
        return
    end
    
    -- Process message template
    if ns.MessageTemplates then
        message = ns.MessageTemplates:ProcessMessage(message, playerName)
    end
    
    -- Send whisper
    SendChatMessage(message, "WHISPER", nil, playerName)
    
    -- Add to anti-spam list
    self:AddToAntiSpam(playerName)
    
    print("|cFF3EB9D8[FGR]|r Recruitment message sent to: " .. playerName)
end

function InviteManager:SendWelcomeMessage(playerName)
    local guildMessage = self:GetGuildWelcomeMessage()
    if not guildMessage or guildMessage == "" then return end
    
    if ns.MessageTemplates then
        guildMessage = ns.MessageTemplates:ProcessMessage(guildMessage, playerName)
    end
    
    SendChatMessage(guildMessage, "GUILD")
    print("|cFF3EB9D8[FGR]|r Guild welcome message sent")
end

-- Message Retrieval
function InviteManager:GetRecruitmentMessage(messageIndex)
    if ns.Database and ns.Database.GetMessageList then
        local messageList = ns.Database:GetMessageList()
        if messageIndex and messageList[messageIndex] then
            return messageList[messageIndex].message
        elseif #messageList > 0 then
            return messageList[1].message -- Default to first message
        end
    end
    
    return "Would you like to join our guild?"
end

function InviteManager:GetGuildWelcomeMessage()
    if ns.gSettings and ns.gSettings.sendGuildGreeting and ns.gSettings.guildMessage then
        return ns.gSettings.guildMessage
    end
    
    return L['DEFAULT_GUILD_WELCOME'] or "Welcome to the guild!"
end

-- Anti-Spam Management
function InviteManager:AddToAntiSpam(playerName)
    if not ns.tblAntiSpamList then ns.tblAntiSpamList = {} end
    
    local key = string.lower(playerName)
    ns.tblAntiSpamList[key] = {
        name = playerName,
        time = time(),
    }
    
    if ns.Logger then
        ns.Logger:Debug("Added %s to anti-spam list", playerName)
    end
end

-- Batch Operations
function InviteManager:InviteAllPlayers()
    if not self.scanResults or #self.scanResults == 0 then
        print("|cFFFF0000[FGR]|r No scan results available")
        return
    end
    
    print("|cFF3EB9D8[FGR]|r Sending guild invites to " .. #self.scanResults .. " players...")
    
    for i, player in ipairs(self.scanResults) do
        C_Timer.After(i * 0.5, function() -- Stagger invites
            self:SendGuildInvite(player.name)
        end)
    end
end

function InviteManager:MessageAllPlayers(messageIndex)
    if not self.scanResults or #self.scanResults == 0 then
        print("|cFFFF0000[FGR]|r No scan results available")
        return
    end
    
    local delay = tonumber(ns.g and ns.g.performance and ns.g.performance.timeBetweenMessages or 0.2)
    
    print("|cFF3EB9D8[FGR]|r Sending recruitment messages to " .. #self.scanResults .. " players...")
    
    for i, player in ipairs(self.scanResults) do
        C_Timer.After(i * delay, function() -- Use configured delay
            self:SendRecruitmentMessage(player.name, messageIndex)
        end)
    end
end

-- Initialize when module loads
InviteManager:Initialize()

-- Export scan types for external use
ns.SCAN_TYPES = SCAN_TYPES
ns.INVITE_RESULTS = INVITE_RESULTS