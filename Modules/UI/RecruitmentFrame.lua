-- Modules/UI/RecruitmentFrame.lua
local addonName, ns = ...
ns.RecruitmentFrame = {}
local RecruitmentFrame = ns.RecruitmentFrame

-- Local variables for state management
local isScanning = false
local foundPlayers = {}
local selectedPlayers = {}
local currentFilter = "ALL"
local lastScanTime = 0
local scanCooldown = 15 -- Fixed at 15 seconds
local playerCheckboxes = {}
local MAX_WHISPER_LENGTH = 220

-- Reliable, one-time event frame for WHO_LIST_UPDATE (do not register per-scan)
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("WHO_LIST_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "WHO_LIST_UPDATE" and RecruitmentFrame._whoResultsExpected then
        RecruitmentFrame:_OnWhoListUpdate()
    end
end)
RecruitmentFrame._whoResultsExpected = false

-------------------------------------------------------------------------------
-- WHO Query Logic
-------------------------------------------------------------------------------

function RecruitmentFrame:SendActualWhoQuery(query, className)
    self._whoResultsExpected = true
    self.currentQueryClass = className
    self.whoQueryStartTime = GetTime()
    self.lastWhoQuery = query
    self.awaitingResults = true

    local timeSinceLastQuery = GetTime() - (self.lastWhoTime or 0)
    if timeSinceLastQuery < 5 then
        local waitTime = 5 - timeSinceLastQuery
        C_Timer.After(waitTime, function()
            self:SendActualWhoQuery(query, className)
        end)
        return
    end

    C_FriendList.SetWhoToUi(true)
    local success = pcall(function() C_FriendList.SendWho(query) end)
    if not success then
        self:HandleWhoQueryFailure("SendWho failed")
        self.awaitingResults = false
        self._whoResultsExpected = false
        return
    end

    self.lastWhoTime = GetTime()

    C_Timer.After(8, function()
        if self._whoResultsExpected then
            self:HandleWhoQueryFailure("Polling timeout")
            self.awaitingResults = false
            self._whoResultsExpected = false
        end
    end)
end

function RecruitmentFrame:_OnWhoListUpdate()
    if not self._whoResultsExpected then return end
    self._whoResultsExpected = false
    self.awaitingResults = false
    self:ProcessWhoResults_Polling()
end

function RecruitmentFrame:ProcessWhoResults_Polling()
    if FriendsFrame then FriendsFrame:Hide() end

    local results = {}
    local numResults = C_FriendList.GetNumWhoResults()

    for i = 1, numResults do
        local info = C_FriendList.GetWhoInfo(i)
        if info then
            local playerClass = info.filename or info.classStr or "Unknown"
            local playerName = info.fullName or info.name

            if playerName and playerName ~= "" then
                local playerData = {
                    name = playerName,
                    level = info.level or 1,
                    class = playerClass,
                    race = info.raceStr or "Unknown",
                    guild = info.fullGuildName,
                    zone = info.area or GetZoneText(),
                    queryTime = GetTime()
                }
                table.insert(results, playerData)
            end
        end
    end

    if #results > 0 then
        local validCount = 0
        local filteredCount = 0
        for _, playerInfo in ipairs(results) do
            if playerInfo.name and playerInfo.name ~= UnitName("player") then
                if self:PassesFilters(playerInfo) then
                    foundPlayers[playerInfo.name] = playerInfo
                    selectedPlayers[playerInfo.name] = playerInfo
                    validCount = validCount + 1
                else
                    filteredCount = filteredCount + 1
                end
            end
        end

        self.sessionStats.playersScanned = (self.sessionStats.playersScanned or 0) + #results
        self:RefreshPlayerList()
        self:UpdatePlayerCount()
        self:UpdateSelectionCount()
        self:UpdateSendInviteButtonState()
        self:UpdateSessionStats()

        local statusMsg = string.format("Found %d players (%d filtered)", validCount, filteredCount)
        self:UpdateStatus(statusMsg, validCount > 0 and "green" or "orange")
    else
        self:UpdateStatus("No WHO results", "orange")
    end

    self:UpdateActionButtonVisibility()
    self:ReEnableScanButton()
end

function RecruitmentFrame:HandleWhoQueryFailure(reason)
    self._whoResultsExpected = false
    self.awaitingResults = false
    self:UpdateStatus("WHO failed: " .. reason, "orange")
    if self.scanButton then
        self.scanButton:SetEnabled(true)
        self.scanButton:SetText("Scan")
        self:UpdateNextClassIndicator()
    end
end

function RecruitmentFrame:ReEnableScanButton()
    if self.scanButton then
        self.scanButton:SetEnabled(true)
        self.scanButton:SetText("Scan")
        self:UpdateNextClassIndicator()
    end
    self:StartCooldownTimer()
end

function RecruitmentFrame:ExecuteWhoQuery(query, className)
    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()

    local finalQuery = query
    if className then
        local token = string.lower(className)
        -- Multi-word classes (death knight, demon hunter) must be quoted in a WHO filter
        if token:find(" ") then token = '"' .. token .. '"' end
        finalQuery = "c-" .. token .. " " .. minLevel .. "-" .. maxLevel
    end

    self:SendActualWhoQuery(finalQuery, className)
end

-------------------------------------------------------------------------------
-- Scanning & Filtering
-------------------------------------------------------------------------------

function RecruitmentFrame:StartPlayerScan()
    if isScanning then
        self:UpdateStatus("Scan already in progress...", "orange")
        return
    end

    local currentTime = time()
    local remaining = scanCooldown - (currentTime - lastScanTime)
    if remaining > 0 then
        self:UpdateStatus(string.format("Cooldown: %ds remaining", math.ceil(remaining)), "orange")
        return
    end

    isScanning = true
    lastScanTime = time()

    if self.scanButton then
        self.scanButton:SetEnabled(false)
        self.scanButton:SetText("...")
    end

    self:UpdateStatus("Scanning...", "yellow")

    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()

    -- Class scan mode: cycle through selected classes
    if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
        local classIndex = self.currentClassIndex or 1
        -- Wrap around instead of dropping out of class scan mode, so repeated
        -- scans keep rotating through the selected classes.
        if classIndex > #self.selectedClassList then classIndex = 1 end

        local className = self.selectedClassList[classIndex]
        self.currentScanClass = className
        self.currentClassIndex = classIndex + 1
        self:ExecuteWhoQuery(nil, className)
    else
        -- Normal scan: all classes in level range
        local query = minLevel .. "-" .. maxLevel
        self:ExecuteWhoQuery(query, nil)
    end

    isScanning = false
end

function RecruitmentFrame:PassesFilters(playerData)
    if not playerData then return false end

    -- Filter out players already in our guild
    local myGuild = GetGuildInfo("player")
    if myGuild and playerData.guild and playerData.guild == myGuild then
        return false
    end

    -- Filter players already in a guild (optional - we recruit guildless by default)
    if playerData.guild and playerData.guild ~= "" then
        return false
    end

    -- Anti-spam check
    if ns.tblAntiSpamList and ns.tblAntiSpamList[string.lower(playerData.name)] then
        return false
    end

    -- Blacklist check
    if ns.tblBlackList and ns.tblBlackList[string.lower(playerData.name)] then
        return false
    end

    -- Zone filter
    if self.zoneFilterCheck and self.zoneFilterCheck:GetChecked() then
        if ns.invalidZones and playerData.zone then
            for _, zone in ipairs(ns.invalidZones) do
                if playerData.zone == zone then
                    return false
                end
            end
        end
    end

    return true
end

function RecruitmentFrame:RefreshPlayerList()
    if not self.playerScrollChild then return end

    -- Clear existing entries
    local children = { self.playerScrollChild:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    playerCheckboxes = {}

    -- Sort players by name
    local sorted = {}
    for name, data in pairs(foundPlayers) do
        table.insert(sorted, data)
    end
    table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)

    local yOffset = 0
    local entryHeight = self.isCompactMode and 20 or 26

    for _, playerData in ipairs(sorted) do
        self:CreatePlayerEntry(playerData, yOffset)
        yOffset = yOffset - entryHeight
    end

    self.playerScrollChild:SetHeight(math.abs(yOffset) + 10)

    if self.emptyState then self.emptyState:SetShown(#sorted == 0) end
    if self.playerScrollFrame and self.playerScrollFrame.fgrUpdateThumb then
        self.playerScrollFrame.fgrUpdateThumb()
    end
end

function RecruitmentFrame:UpdateActionButtonVisibility()
    local hasPlayers = false
    for _ in pairs(foundPlayers) do hasPlayers = true; break end

    if self.sendInviteBtn then self.sendInviteBtn:SetShown(hasPlayers) end
    if self.blacklistBtn then self.blacklistBtn:SetShown(hasPlayers) end
    if self.clearBtn then self.clearBtn:SetShown(hasPlayers) end
end

function RecruitmentFrame:UpdateSendInviteButtonState()
    if not self.sendInviteBtn then return end
    local hasSelected = false
    for _ in pairs(selectedPlayers) do hasSelected = true; break end
    self.sendInviteBtn:SetEnabled(hasSelected)
end

function RecruitmentFrame:SendNextInvite()
    local inviteQueue = {}
    for name, data in pairs(selectedPlayers) do
        table.insert(inviteQueue, data)
    end

    if #inviteQueue == 0 then
        self:UpdateStatus("No players selected", "orange")
        return
    end

    self:UpdateStatus(string.format("Processing %d players...", #inviteQueue), "yellow")
    self:ProcessInviteQueue(inviteQueue)
end

function RecruitmentFrame:UpdateLevelDisplay()
    if not self.levelDisplay then return end
    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()
    self.levelDisplay:SetText(string.format("%d-%d", minLevel, maxLevel))
end

function RecruitmentFrame:UpdateClassFilterDisplay()
    if not self.classFilterInfo then return end
    local enabled = self.classFilterCheck and self.classFilterCheck:GetChecked()
    if not enabled then
        self.classFilterInfo:SetText("")
        self.isClassScanMode = false
        self.classListKey = nil
        return
    end

    -- Show which classes are selected for filtering
    local classes = {}
    if ns.pSettings and ns.pSettings.classFilter then
        for className, isEnabled in pairs(ns.pSettings.classFilter) do
            if isEnabled then
                table.insert(classes, className)
            end
        end
    end

    if #classes > 0 then
        table.sort(classes) -- pairs() order is undefined; keep the cycle stable across calls
        self.classFilterInfo:SetText("Classes: " .. table.concat(classes, ", "))
        -- Set up class scan mode. Only rewind the cycle when the class set actually
        -- changed, otherwise every cooldown tick would restart it at the first class.
        local key = table.concat(classes, ",")
        if key ~= self.classListKey then
            self.classListKey = key
            self.currentClassIndex = 1
        end
        self.selectedClassList = classes
        self.isClassScanMode = true
    else
        self.classFilterInfo:SetText("No classes selected")
        self.isClassScanMode = false
        self.classListKey = nil
    end
end

function RecruitmentFrame:UpdateNextClassIndicator()
    if not self.nextClassText then return end
    if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
        local idx = self.currentClassIndex or 1
        if idx > #self.selectedClassList then idx = 1 end
        self.nextClassText:SetText("Next: " .. self.selectedClassList[idx])
    else
        self.nextClassText:SetText("")
    end
end

function RecruitmentFrame:GetRaiderIOReference()
    if _G.RaiderIO then return _G.RaiderIO end
    if _G.raiderio then return _G.raiderio end
    if _G.RaiderIO_ProfileTooltip then return _G.RaiderIO_ProfileTooltip end
    return nil
end

-------------------------------------------------------------------------------
-- Show / Hide / Window Registration
-------------------------------------------------------------------------------

function RecruitmentFrame:Show()
    if not self.isInitialized then
        self:CreateFrame()
    end

    if ns.WindowManager then
        self:RegisterWindowIfNeeded()
        ns.WindowManager:ShowWindow("recruitment")
    elseif self.frame then
        self.frame:Show()
        self:RefreshUI()
    end
end

function RecruitmentFrame:Hide()
    if ns.WindowManager and self._registeredWindow then
        ns.WindowManager:HideWindow("recruitment")
    elseif self.frame then
        self.frame:Hide()
    end
end

function RecruitmentFrame:RegisterWindowIfNeeded()
    if self._registeredWindow or not ns.WindowManager or not self.frame then
        return
    end

    ns.WindowManager:RegisterWindow("recruitment", self.frame, function()
        if self.frame then
            self.frame:Show()
            self:RefreshUI()
        end
    end, function()
        if self.frame then
            self.frame:Hide()
        end
    end)

    self._registeredWindow = true
end

-------------------------------------------------------------------------------
-- Utility functions (message splitting, URLs, whispers)
-------------------------------------------------------------------------------

function RecruitmentFrame:SplitMessage(message, limit)
    local chunks = {}
    if not message or message == "" then return chunks end

    local current = ""
    for word in string.gmatch(message, "%S+") do
        if #word > limit then
            if current ~= "" then
                table.insert(chunks, current)
                current = ""
            end
            local i = 1
            while i <= #word do
                table.insert(chunks, string.sub(word, i, i + limit - 1))
                i = i + limit
            end
        else
            if current == "" then
                current = word
            elseif #current + 1 + #word <= limit then
                current = current .. " " .. word
            else
                table.insert(chunks, current)
                current = word
            end
        end
    end
    if current ~= "" then table.insert(chunks, current) end
    return chunks
end

local function urlEncode(value)
    if not value then return "" end
    return tostring(value):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

function RecruitmentFrame:GetRegionCode()
    if GetCurrentRegion then
        local region = GetCurrentRegion()
        if region == 1 then return "us" end
        if region == 2 then return "kr" end
        if region == 3 then return "eu" end
        if region == 4 then return "tw" end
        if region == 5 then return "cn" end
    end
    return "us"
end

function RecruitmentFrame:BuildRaiderIoUrl(playerData)
    if not playerData or not playerData.name then return nil end
    local name = playerData.name
    local baseName, realm = strsplit("-", name, 2)
    if not realm or realm == "" then
        realm = GetRealmName() or ""
    end
    local region = self:GetRegionCode()
    return string.format("https://raider.io/characters/%s/%s/%s", region, urlEncode(realm), urlEncode(baseName))
end

function RecruitmentFrame:SendWhisper(message, target)
    if not message or message == "" or not target or target == "" then return end

    local chunks = self:SplitMessage(message, MAX_WHISPER_LENGTH)
    if #chunks == 0 then return end

    for i, chunk in ipairs(chunks) do
        if i == 1 then
            SendChatMessage(chunk, "WHISPER", nil, target)
        else
            C_Timer.After((i - 1) * 0.3, function()
                SendChatMessage(chunk, "WHISPER", nil, target)
            end)
        end
    end

    if #chunks > 1 then
        self:UpdateStatus("Message split into " .. #chunks .. " parts", "orange")
    end
end

-------------------------------------------------------------------------------
-- Theme Helpers
-------------------------------------------------------------------------------

local T = ns.Theme

local function tc(name)
    if T then return T:GetColor(name) end
    return 1, 1, 1, 1
end

local function label(parent, text, tone, size)
    return T:Label(parent, text, tone, size)
end

local function eyebrow(parent, text, tone)
    return T:Eyebrow(parent, text, tone)
end

local function button(parent, text, variant, opts)
    return T:Button(parent, text, variant, opts)
end

local function createSep(parent, yOff)
    local sep = T:Divider(parent, "border")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", T.space.md, yOff)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -T.space.md, yOff)
    return sep
end

-- Column geometry for the full-mode list. One table so the header row and the
-- player rows can never drift apart.
local COLUMNS = {
    check = 10,
    name  = 32,
    level = 210,
    class = 248,
    zone  = 356,
    race  = 500,
    rio   = -10, -- right-anchored
}

-------------------------------------------------------------------------------
-- UI CREATION - Window shell
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateFrame()
    local isCompact = self.compactMode
    if isCompact == nil then isCompact = (ns.pSettings and ns.pSettings.isCompact) or false end

    if self.frame then
        self.frame:Hide()
        self.frame:SetParent(nil)
        self.frame = nil
    end

    local frame = T:Window({
        name = "FGRRecruitmentFrame",
        title = isCompact and "FGR" or "Fast Guild Recruiter",
        titleSize = isCompact and T.type.body or T.type.title,
        width = isCompact and 300 or 760,
        height = isCompact and 380 or 560,
        headerHeight = isCompact and 28 or T.sizes.header,
        onClose = function() self:Hide() end,
    })

    self.frame = frame
    self.isCompactMode = isCompact

    -- Header chrome: version, then the density toggle, then close.
    -- ASCII glyphs on purpose: the game fonts don't carry box-drawing symbols.
    local toggleBtn = T:IconButton(frame.TitleBg, isCompact and "+" or "-",
        isCompact and "Switch to full mode" or "Switch to compact mode", "textMuted")
    toggleBtn:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
    toggleBtn:SetScript("OnClick", function() self:ToggleCompactMode() end)

    if not isCompact then
        local verText = label(frame.TitleBg, FGR and FGR.versionOut or "", "textSoft", T.type.micro)
        verText:SetPoint("RIGHT", toggleBtn, "LEFT", -T.space.sm, 0)
    end

    if isCompact then
        self:CreateCompactUI()
    else
        self:CreateNormalUI()
    end

    self.isInitialized = true
    self:RegisterWindowIfNeeded()
end

function RecruitmentFrame:ToggleCompactMode()
    local wasShown = self.frame and self.frame:IsShown()
    self.compactMode = not self.isCompactMode

    if ns.pSettings then
        ns.pSettings.isCompact = self.compactMode
    end

    self._registeredWindow = false
    self.isInitialized = false
    self:CreateFrame()

    if wasShown then
        self.frame:Show()
        self:RefreshUI()
    end
end

-------------------------------------------------------------------------------
-- FULL MODE UI
--
-- Vertical rhythm: toolbar / filters / mode / list / footer. Each band is its
-- own frame so the sections stay independently editable, separated by hairlines
-- rather than boxes-inside-boxes.
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateNormalUI()
    local frame = self.frame
    local body = frame.body
    local PAD = T.space.md

    -- ===== TOOLBAR =====
    local toolbar = CreateFrame("Frame", nil, body)
    toolbar:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -T.space.md)
    toolbar:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -T.space.md)
    toolbar:SetHeight(30)

    local scanBtn = button(toolbar, "Scan", "primary", { width = 88, height = 28, fontSize = T.type.bodyLg })
    scanBtn:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    scanBtn:SetScript("OnClick", function() self:StartPlayerScan() end)
    scanBtn.fgrTooltip = "Run a /who sweep for the current level range and class filter"
    self.scanButton = scanBtn

    local cooldownText = label(toolbar, "", "warning", T.type.caption)
    cooldownText:SetPoint("LEFT", scanBtn, "RIGHT", T.space.md, 0)
    self.cooldownText = cooldownText

    local nextClassText = label(toolbar, "", "textSoft", T.type.caption)
    nextClassText:SetPoint("LEFT", cooldownText, "RIGHT", T.space.sm, 0)
    self.nextClassText = nextClassText

    -- Session counters, right-aligned as stat tiles.
    local statsText = label(toolbar, "", "textMuted", T.type.caption)
    statsText:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    statsText:SetJustifyH("RIGHT")
    self.statsText = statsText

    local statsCaption = eyebrow(toolbar, "Session")
    statsCaption:SetPoint("BOTTOMRIGHT", statsText, "TOPRIGHT", 0, 1)

    local yOff = -T.space.md - 30 - T.space.md
    createSep(body, yOff)
    yOff = yOff - T.space.md

    -- ===== FILTER BAND =====
    local filterRow = CreateFrame("Frame", nil, body)
    filterRow:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, yOff)
    filterRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, yOff)
    filterRow:SetHeight(22)

    local levelLabel = eyebrow(filterRow, "Levels")
    levelLabel:SetPoint("LEFT", filterRow, "LEFT", 0, 0)

    local levelDisplay = label(filterRow, "", "textMain", T.type.body)
    levelDisplay:SetPoint("LEFT", levelLabel, "RIGHT", T.space.sm, 0)
    self.levelDisplay = levelDisplay

    local zoneFilterCheck = T:Checkbox(filterRow, "Zone filter", { fontSize = T.type.caption })
    zoneFilterCheck:SetPoint("LEFT", levelDisplay, "RIGHT", T.space.xl, 0)
    zoneFilterCheck:SetChecked(true)
    self.zoneFilterCheck = zoneFilterCheck

    local classFilterCheck = T:Checkbox(filterRow, "Class filter", { fontSize = T.type.caption })
    classFilterCheck:SetPoint("LEFT", zoneFilterCheck.Text, "RIGHT", T.space.lg, 0)
    classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
    classFilterCheck:SetScript("OnClick", function(cb)
        if not ns.pSettings then ns.pSettings = {} end
        ns.pSettings.enableClassFilter = cb:GetChecked()
        RecruitmentFrame:UpdateClassFilterDisplay()
        RecruitmentFrame:UpdateNextClassIndicator()
    end)
    self.classFilterCheck = classFilterCheck

    local classFilterInfo = label(filterRow, "", "textSoft", T.type.caption)
    classFilterInfo:SetPoint("LEFT", classFilterCheck.Text, "RIGHT", T.space.md, 0)
    classFilterInfo:SetPoint("RIGHT", filterRow, "RIGHT", 0, 0)
    classFilterInfo:SetWordWrap(false)
    self.classFilterInfo = classFilterInfo

    yOff = yOff - 22 - T.space.md
    createSep(body, yOff)
    yOff = yOff - T.space.md

    -- ===== MODE BAND =====
    local msgRow = CreateFrame("Frame", nil, body)
    msgRow:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, yOff)
    msgRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, yOff)
    msgRow:SetHeight(26)

    local msgLabel = eyebrow(msgRow, "Action")
    msgLabel:SetPoint("LEFT", msgRow, "LEFT", 0, 0)

    local msgDropdown = CreateFrame("Frame", "FGRModeDropdown", msgRow, "UIDropDownMenuTemplate")
    msgDropdown:SetPoint("LEFT", msgLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(msgDropdown, 380)
    T:StyleDropdown(msgDropdown)

    local ref = self
    UIDropDownMenu_Initialize(msgDropdown, function(dropdown, level)
        ref:BuildModeMenu(msgDropdown, level)
    end)

    UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_only")
    self.messageDropdown = msgDropdown
    self.inviteMode = "invite_only"

    yOff = yOff - 26 - T.space.md
    createSep(body, yOff)
    yOff = yOff - T.space.md

    -- ===== LIST HEADER =====
    local listHeaderRow = CreateFrame("Frame", nil, body)
    listHeaderRow:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, yOff)
    listHeaderRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, yOff)
    listHeaderRow:SetHeight(20)

    local listHeader = label(listHeaderRow, "Found Players: 0", "textMain", T.type.bodyLg)
    listHeader:SetPoint("LEFT", listHeaderRow, "LEFT", 0, 0)
    self.listHeader = listHeader

    local selectionBadge = T:Badge(listHeaderRow, "0 selected", "accent")
    selectionBadge:SetPoint("LEFT", listHeader, "RIGHT", T.space.sm, 0)
    self.selectionBadge = selectionBadge

    local deselectAllBtn = button(listHeaderRow, "Deselect", "ghost", { width = 62, height = 18, fontSize = T.type.caption })
    deselectAllBtn:SetPoint("RIGHT", listHeaderRow, "RIGHT", 0, 0)
    deselectAllBtn:SetScript("OnClick", function() self:DeselectAllPlayersButton() end)
    self.deselectAllBtn = deselectAllBtn

    local selectAllBtn = button(listHeaderRow, "Select all", "ghost", { width = 66, height = 18, fontSize = T.type.caption })
    selectAllBtn:SetPoint("RIGHT", deselectAllBtn, "LEFT", T.space.xs, 0)
    selectAllBtn:SetScript("OnClick", function() self:SelectAllPlayersButton() end)
    self.selectAllBtn = selectAllBtn

    yOff = yOff - 20 - T.space.sm

    -- ===== COLUMN HEADERS =====
    local colRow = CreateFrame("Frame", nil, body)
    colRow:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, yOff)
    colRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, yOff)
    colRow:SetHeight(16)

    for _, col in ipairs({
        { x = COLUMNS.name,  text = "Name" },
        { x = COLUMNS.level, text = "Lvl" },
        { x = COLUMNS.class, text = "Class" },
        { x = COLUMNS.zone,  text = "Zone" },
        { x = COLUMNS.race,  text = "Race" },
    }) do
        local h = eyebrow(colRow, col.text)
        h:SetPoint("LEFT", colRow, "LEFT", col.x, 0)
    end

    local colRule = T:Divider(colRow, "border")
    colRule:SetPoint("BOTTOMLEFT", colRow, "BOTTOMLEFT", 0, 0)
    colRule:SetPoint("BOTTOMRIGHT", colRow, "BOTTOMRIGHT", 0, 0)

    yOff = yOff - 16

    -- ===== LIST =====
    local scrollFrame, scrollChild = T:ScrollArea(body, { step = 30 })
    scrollFrame:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, yOff - 2)
    scrollFrame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -PAD - 5, 62)
    scrollChild:SetWidth(frame:GetWidth() - (PAD * 2) - 5)

    self.playerScrollFrame = scrollFrame
    self.playerScrollChild = scrollChild

    self.emptyState = T:EmptyState(scrollFrame, "No players yet",
        "Press Scan to sweep for unguilded players in range.")

    -- ===== FOOTER =====
    local footer = CreateFrame("Frame", nil, body)
    footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(56)
    T:Fill(footer, "sidebar")

    local footerRule = T:Divider(footer, "border")
    footerRule:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    footerRule:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)

    local sendInviteBtn = button(footer, "Send Invite", "primary", { width = 118, height = 26, fontSize = T.type.bodyLg })
    sendInviteBtn:SetPoint("TOPLEFT", footer, "TOPLEFT", PAD, -T.space.sm)
    sendInviteBtn:SetScript("OnClick", function() self:SendNextInvite() end)
    sendInviteBtn:Hide()
    self.sendInviteBtn = sendInviteBtn

    local blacklistBtn = button(footer, "Blacklist", "danger", { width = 84, height = 26 })
    blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", T.space.sm, 0)
    blacklistBtn:SetScript("OnClick", function() self:BlacklistSelectedPlayers() end)
    blacklistBtn:Hide()
    self.blacklistBtn = blacklistBtn

    local clearBtn = button(footer, "Clear", "ghost", { width = 60, height = 26 })
    clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", T.space.xs, 0)
    clearBtn:SetScript("OnClick", function() self:ClearPlayerList() end)
    clearBtn:Hide()
    self.clearBtn = clearBtn

    local settingsBtn = button(footer, "Settings", "secondary", { width = 82, height = 26 })
    settingsBtn:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -PAD, -T.space.sm)
    settingsBtn:SetScript("OnClick", function()
        if ns.SettingsManager then ns.SettingsManager:OpenSettings() end
    end)

    -- Status line sits under the actions, with a coloured dot as the indicator.
    local statusDot = footer:CreateTexture(nil, "ARTWORK")
    statusDot:SetSize(6, 6)
    statusDot:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, T.space.sm + 3)
    local sr, sg, sb = tc("success")
    statusDot:SetColorTexture(sr, sg, sb, 1)
    self.statusDot = statusDot

    local statusText = label(footer, "Ready", "textMuted", T.type.caption)
    statusText:SetPoint("LEFT", statusDot, "RIGHT", T.space.sm, 0)
    statusText:SetPoint("RIGHT", settingsBtn, "LEFT", -T.space.md, 0)
    self.statusText = statusText

    self:UpdateLevelDisplay()
    self:UpdateClassFilterDisplay()
    self:UpdateNextClassIndicator()
    self:UpdateSelectionCount()
end

-- Shared by both densities so the menu can't drift between them.
function RecruitmentFrame:BuildModeMenu(dropdown, level)
    local ref = self
    local messageList = self:GetMessageList()

    local info = UIDropDownMenu_CreateInfo()
    info.text = "Invite only"
    info.value = "invite_only"
    info.func = function()
        UIDropDownMenu_SetSelectedValue(dropdown, "invite_only")
        ref.selectedMessage = nil
        ref.inviteMode = "invite_only"
        ref:UpdateInviteButtonLabel()
    end
    UIDropDownMenu_AddButton(info, level)

    for i, msgData in ipairs(messageList) do
        local desc = msgData.desc or ("Message " .. i)

        local invInfo = UIDropDownMenu_CreateInfo()
        invInfo.text = "Invite + whisper: " .. desc
        invInfo.value = "invite_and_message_" .. i
        invInfo.func = function()
            UIDropDownMenu_SetSelectedValue(dropdown, "invite_and_message_" .. i)
            ref.selectedMessage = msgData
            ref.inviteMode = "invite_and_message"
            ref:UpdateInviteButtonLabel()
        end
        UIDropDownMenu_AddButton(invInfo, level)

        local msgInfo = UIDropDownMenu_CreateInfo()
        msgInfo.text = "Whisper only: " .. desc
        msgInfo.value = "just_message_" .. i
        msgInfo.func = function()
            UIDropDownMenu_SetSelectedValue(dropdown, "just_message_" .. i)
            ref.selectedMessage = msgData
            ref.inviteMode = "just_message"
            ref:UpdateInviteButtonLabel()
        end
        UIDropDownMenu_AddButton(msgInfo, level)
    end
end

-------------------------------------------------------------------------------
-- COMPACT MODE UI - same actions, one column, no chrome
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateCompactUI()
    local frame = self.frame
    local body = frame.body
    local PAD = T.space.sm

    local scanBtn = button(body, "Scan", "primary", { width = 60, height = 22, fontSize = T.type.caption })
    scanBtn:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -T.space.sm)
    scanBtn:SetScript("OnClick", function() self:StartPlayerScan() end)
    self.scanButton = scanBtn

    local cooldownText = label(body, "", "warning", T.type.micro)
    cooldownText:SetPoint("LEFT", scanBtn, "RIGHT", T.space.sm, 0)
    self.cooldownText = cooldownText

    local nextClassText = label(body, "", "textSoft", T.type.micro)
    nextClassText:SetPoint("LEFT", cooldownText, "RIGHT", T.space.xs, 0)
    nextClassText:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
    nextClassText:SetWordWrap(false)
    self.nextClassText = nextClassText

    local listHeader = label(body, "Players: 0", "textMain", T.type.caption)
    listHeader:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -T.space.sm - 26)
    self.listHeader = listHeader

    local deselectAllBtn = button(body, "None", "ghost", { width = 36, height = 16, fontSize = T.type.micro })
    deselectAllBtn:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
    deselectAllBtn:SetPoint("TOP", listHeader, "TOP", 0, 2)
    deselectAllBtn:SetScript("OnClick", function() self:DeselectAllPlayersButton() end)
    self.deselectAllBtn = deselectAllBtn

    local selectAllBtn = button(body, "All", "ghost", { width = 30, height = 16, fontSize = T.type.micro })
    selectAllBtn:SetPoint("RIGHT", deselectAllBtn, "LEFT", 2, 0)
    selectAllBtn:SetScript("OnClick", function() self:SelectAllPlayersButton() end)
    self.selectAllBtn = selectAllBtn

    local headerRule = T:Divider(body, "border")
    headerRule:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -T.space.sm - 42)
    headerRule:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -T.space.sm - 42)

    local scrollFrame, scrollChild = T:ScrollArea(body, { step = 22 })
    scrollFrame:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -T.space.sm - 46)
    scrollFrame:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -PAD - 5, 50)
    scrollChild:SetWidth(frame:GetWidth() - (PAD * 2) - 5)

    self.playerScrollFrame = scrollFrame
    self.playerScrollChild = scrollChild

    self.emptyState = T:EmptyState(scrollFrame, "No players yet", "Press Scan.")

    local footer = CreateFrame("Frame", nil, body)
    footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(46)
    T:Fill(footer, "sidebar")

    local footerRule = T:Divider(footer, "border")
    footerRule:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    footerRule:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)

    local sendInviteBtn = button(footer, "Invite", "primary", { width = 62, height = 20, fontSize = T.type.caption })
    sendInviteBtn:SetPoint("TOPLEFT", footer, "TOPLEFT", PAD, -T.space.xs)
    sendInviteBtn:SetScript("OnClick", function() self:SendNextInvite() end)
    sendInviteBtn:Hide()
    self.sendInviteBtn = sendInviteBtn

    local blacklistBtn = button(footer, "Block", "danger", { width = 48, height = 20, fontSize = T.type.caption })
    blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", 3, 0)
    blacklistBtn:SetScript("OnClick", function() self:BlacklistSelectedPlayers() end)
    blacklistBtn:Hide()
    self.blacklistBtn = blacklistBtn

    local clearBtn = button(footer, "Clear", "ghost", { width = 44, height = 20, fontSize = T.type.caption })
    clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 3, 0)
    clearBtn:SetScript("OnClick", function() self:ClearPlayerList() end)
    clearBtn:Hide()
    self.clearBtn = clearBtn

    local statusDot = footer:CreateTexture(nil, "ARTWORK")
    statusDot:SetSize(5, 5)
    statusDot:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", PAD, T.space.sm)
    local sr, sg, sb = tc("success")
    statusDot:SetColorTexture(sr, sg, sb, 1)
    self.statusDot = statusDot

    local statusText = label(footer, "Ready", "textMuted", T.type.micro)
    statusText:SetPoint("LEFT", statusDot, "RIGHT", 5, 0)
    statusText:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
    statusText:SetWordWrap(false)
    self.statusText = statusText

    -- Not present at this density.
    self.statsText = nil
    self.zoneFilterCheck = nil
    self.classFilterCheck = nil
    self.classFilterInfo = nil
    self.messageDropdown = nil
    self.levelDisplay = nil
    self.selectionBadge = nil
    self.inviteMode = "invite_only"
end

-------------------------------------------------------------------------------
-- Player Entry Rendering
-------------------------------------------------------------------------------

function RecruitmentFrame:CreatePlayerEntry(playerData, yOffset)
    local classColor = RAID_CLASS_COLORS[playerData.class] or { r = 0.9, g = 0.9, b = 0.9 }
    local isCompact = self.isCompactMode
    local entryHeight = isCompact and 20 or 26
    local parentWidth = self.playerScrollChild:GetWidth()

    local entry = CreateFrame("Button", nil, self.playerScrollChild)
    entry:SetPoint("TOPLEFT", self.playerScrollChild, "TOPLEFT", 0, yOffset)
    entry:SetSize(parentWidth, entryHeight)

    -- Row surface. Selected rows get a soft accent wash plus a left rail; the
    -- old alternating stripes are gone, they fought with the class colour.
    local bg = entry:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(entry)

    local rail = entry:CreateTexture(nil, "ARTWORK")
    rail:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, 0)
    rail:SetWidth(2)
    rail:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.9)

    local rule = T:Divider(entry, "border")
    rule:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 0, 0)
    rule:SetAlpha(0.5)

    entry.fgrHovered = false
    local function paintRow()
        local selected = selectedPlayers[playerData.name] ~= nil
        if selected then
            local ar, ag, ab = tc("accent")
            bg:SetColorTexture(ar, ag, ab, entry.fgrHovered and 0.20 or 0.13)
        elseif entry.fgrHovered then
            local hr, hg, hb = tc("panelHover")
            bg:SetColorTexture(hr, hg, hb, 1)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end
    end
    entry.fgrPaint = paintRow

    local checkSize = isCompact and 13 or 14
    local checkbox = T:Checkbox(entry, nil, { size = checkSize })
    checkbox:SetPoint("LEFT", entry, "LEFT", isCompact and 6 or COLUMNS.check, 0)
    checkbox:SetChecked(selectedPlayers[playerData.name] ~= nil)
    checkbox:SetScript("OnClick", function(cb)
        if cb:GetChecked() then
            selectedPlayers[playerData.name] = playerData
        else
            selectedPlayers[playerData.name] = nil
        end
        cb.fgrPaint()
        paintRow()
        RecruitmentFrame:UpdateSelectionCount()
        RecruitmentFrame:UpdateSendInviteButtonState()
    end)
    playerCheckboxes[playerData.name] = checkbox

    -- Clicking anywhere on the row toggles selection: the checkbox is a target
    -- of 14px, the row is the whole width.
    entry:RegisterForClicks("LeftButtonUp")
    entry:SetScript("OnClick", function()
        checkbox:SetChecked(not checkbox:GetChecked())
        if checkbox:GetChecked() then
            selectedPlayers[playerData.name] = playerData
        else
            selectedPlayers[playerData.name] = nil
        end
        paintRow()
        RecruitmentFrame:UpdateSelectionCount()
        RecruitmentFrame:UpdateSendInviteButtonState()
    end)
    entry:SetScript("OnEnter", function(e)
        e.fgrHovered = true
        paintRow()
        RecruitmentFrame:ShowPlayerTooltip(e, playerData)
    end)
    entry:SetScript("OnLeave", function(e)
        e.fgrHovered = false
        paintRow()
        GameTooltip:Hide()
    end)

    local displayName = playerData.name
    if displayName:find("-") then displayName = displayName:match("([^-]+)") end

    if isCompact then
        local nameText = T:Label(entry, displayName, nil, T.type.caption)
        nameText:SetPoint("LEFT", entry, "LEFT", 26, 0)
        nameText:SetPoint("RIGHT", entry, "RIGHT", -28, 0)
        nameText:SetWordWrap(false)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)

        local levelText = T:Label(entry, tostring(playerData.level), "textSoft", T.type.caption)
        levelText:SetPoint("RIGHT", entry, "RIGHT", -6, 0)
    else
        local nameText = T:Label(entry, displayName, nil, T.type.body)
        nameText:SetPoint("LEFT", entry, "LEFT", COLUMNS.name, 0)
        nameText:SetWidth(COLUMNS.level - COLUMNS.name - 8)
        nameText:SetWordWrap(false)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)

        local levelText = T:Label(entry, tostring(playerData.level), "textMain", T.type.body)
        levelText:SetPoint("LEFT", entry, "LEFT", COLUMNS.level, 0)

        local classText = T:Label(entry, playerData.class or "", nil, T.type.caption)
        classText:SetPoint("LEFT", entry, "LEFT", COLUMNS.class, 0)
        classText:SetTextColor(classColor.r, classColor.g, classColor.b, 0.8)

        local zoneName = playerData.zone or ""
        local zoneText = T:Label(entry, zoneName, "textMuted", T.type.caption)
        zoneText:SetPoint("LEFT", entry, "LEFT", COLUMNS.zone, 0)
        zoneText:SetWidth(COLUMNS.race - COLUMNS.zone - 8)
        zoneText:SetWordWrap(false)

        local raceText = T:Label(entry, playerData.race or "", "textSoft", T.type.caption)
        raceText:SetPoint("LEFT", entry, "LEFT", COLUMNS.race, 0)
        raceText:SetWidth(90)
        raceText:SetWordWrap(false)

        local rioBtn = T:Button(entry, "RIO", "ghost", { width = 34, height = 16, fontSize = T.type.micro })
        rioBtn:SetPoint("RIGHT", entry, "RIGHT", COLUMNS.rio, 0)
        rioBtn.fgrTooltip = "Copy this player's Raider.IO link"
        rioBtn:SetScript("OnClick", function()
            local url = RecruitmentFrame:BuildRaiderIoUrl(playerData)
            if not url then return end
            if ChatFrame_OpenChat then
                ChatFrame_OpenChat(url)
            else
                print(url)
            end
        end)
    end

    paintRow()
    self:UpdateSendInviteButtonState()
    return entry
end

-------------------------------------------------------------------------------
-- Tooltip and RaiderIO Integration
-------------------------------------------------------------------------------

function RecruitmentFrame:ShowPlayerTooltip(frame, playerData)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    local classColor = RAID_CLASS_COLORS[playerData.class] or {r = 1, g = 1, b = 1}
    local unitName = playerData.name

    if playerData.realm and playerData.realm ~= GetRealmName() then
        unitName = playerData.name .. "-" .. playerData.realm
    end

    GameTooltip.unit = unitName
    GameTooltip:SetText(playerData.name, classColor.r, classColor.g, classColor.b)
    GameTooltip:AddLine(string.format("Level %d %s", playerData.level or 0, playerData.class or "Unknown"), 1, 1, 1)

    if playerData.race then
        GameTooltip:AddLine(playerData.race, 0.8, 0.8, 1)
    end
    if playerData.zone then
        GameTooltip:AddLine("Zone: " .. playerData.zone, 0.8, 0.8, 0.8)
    end
    if playerData.guild and playerData.guild ~= "" then
        GameTooltip:AddLine("Guild: " .. playerData.guild, 0.7, 0.9, 0.7)
    else
        GameTooltip:AddLine("No Guild", 0.6, 0.6, 0.6)
    end

    GameTooltip:Show()
    self:EnhanceTooltipWithRaiderIO(playerData, unitName)
    GameTooltip:Show()
end

function RecruitmentFrame:CheckPlayerRaiderIOData(unitName, RaiderIO)
    local checkMethods = {"GetPlayerProfile", "GetProfile", "GetRaidProfile", "HasData", "GetPlayerData", "GetCharacterData"}

    local methods = {}
    local success = pcall(function()
        for k, v in pairs(RaiderIO) do
            if type(v) == "function" then
                table.insert(methods, k)
            end
        end
    end)
    if not success then return nil end

    for _, methodName in ipairs(checkMethods) do
        if RaiderIO[methodName] and type(RaiderIO[methodName]) == "function" then
            local ok, data = pcall(RaiderIO[methodName], unitName)
            if ok and data then
                if methodName == "GetRaidProfile" and type(data) == "table" then
                    self:ExtractAndDisplayRaidProfile(data)
                    return data
                end
                if methodName == "GetProfile" and type(data) == "table" then
                    self:ExtractAndDisplayRaiderIOData(data)
                    return data
                end
                return data
            end
        end
    end

    return nil
end

function RecruitmentFrame:ExtractAndDisplayRaidProfile(raidProfileData)
    if not raidProfileData then return end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Raid Progress:", 0.9, 0.7, 1)

    local raidSources = {
        raidProfileData, raidProfileData.raids, raidProfileData.raidProfile,
        raidProfileData.currentRaid, raidProfileData.raidProgress,
    }

    local raidDataFound = false
    for _, source in ipairs(raidSources) do
        if source and type(source) == "table" then
            local foundInSource = self:ProcessRaidDataSource(source, "raid_source")
            if foundInSource then raidDataFound = true; break end
        end
    end

    if not raidDataFound then
        self:ScanForRaidFields(raidProfileData)
    end

    GameTooltip:Show()
end

function RecruitmentFrame:ProcessRaidDataSource(raidData, sourceName)
    local dataFound = false
    for raidName, raidInfo in pairs(raidData) do
        if type(raidInfo) == "table" then
            local progressText = self:ExtractRaidProgress(raidInfo, raidName)
            if progressText then
                GameTooltip:AddLine("  " .. raidName .. ": " .. progressText, 0.8, 0.8, 1)
                dataFound = true
            end
        end
    end
    return dataFound
end

function RecruitmentFrame:ExtractRaidProgress(raidInfo, raidName)
    local progressFormats = {
        function() return raidInfo.summary end,
        function()
            local progress = ""
            if raidInfo.normal then
                if raidInfo.normal.cleared or raidInfo.normal.killed then progress = progress .. "N"
                elseif raidInfo.normal.progress then progress = progress .. "N(" .. raidInfo.normal.progress .. ")" end
            end
            if raidInfo.heroic then
                if raidInfo.heroic.cleared or raidInfo.heroic.killed then progress = progress .. "H"
                elseif raidInfo.heroic.progress then progress = progress .. "H(" .. raidInfo.heroic.progress .. ")" end
            end
            if raidInfo.mythic then
                if raidInfo.mythic.cleared or raidInfo.mythic.killed then progress = progress .. "M"
                elseif raidInfo.mythic.progress then progress = progress .. "M(" .. raidInfo.mythic.progress .. ")" end
            end
            return progress ~= "" and progress or nil
        end,
        function()
            if raidInfo.bossesKilled and raidInfo.totalBosses then return raidInfo.bossesKilled .. "/" .. raidInfo.totalBosses
            elseif raidInfo.killed and raidInfo.total then return raidInfo.killed .. "/" .. raidInfo.total
            elseif raidInfo.progress and type(raidInfo.progress) == "string" and raidInfo.progress:match("%d+/%d+") then return raidInfo.progress end
        end,
        function()
            for k, v in pairs(raidInfo) do
                if type(v) == "number" and v > 0 and k:lower():find("kill") then return k .. ": " .. v end
            end
        end,
        function()
            if raidInfo.cleared == true then return "Cleared"
            elseif raidInfo.completed == true then return "Completed" end
        end
    }

    for _, formatFunc in ipairs(progressFormats) do
        local result = formatFunc()
        if result then return result end
    end
    return nil
end

function RecruitmentFrame:ScanForRaidFields(data)
    local raidKeywords = {"raid", "boss", "progress", "kill", "clear", "defeat", "palace", "vault", "sanctum", "sepulcher", "castle", "temple"}

    for key, value in pairs(data) do
        local keyLower = tostring(key):lower()
        for _, keyword in ipairs(raidKeywords) do
            if keyLower:find(keyword) then
                if type(value) == "table" then
                    if self:ProcessRaidDataSource(value, key) then return end
                else
                    GameTooltip:AddLine("  " .. key .. ": " .. tostring(value), 0.7, 0.7, 0.7)
                end
                break
            end
        end
    end
end

function RecruitmentFrame:ExtractAndDisplayRaiderIOData(profileData)
    if not profileData then return end

    GameTooltip:AddLine(" ____________ ")

    if profileData.raidProfile then
        self:ProcessRaiderIORaidProfile(profileData.raidProfile)
    end

    if profileData.mythicKeystoneProfile then
        local mp = profileData.mythicKeystoneProfile
        if mp.currentScore and mp.currentScore > 0 then
            GameTooltip:AddLine("RaiderIO Score: " .. mp.currentScore, 1, 0.5, 0)
        end
        if mp.previousScore and mp.previousScore > 0 and mp.previousScore ~= mp.currentScore then
            GameTooltip:AddLine("Previous Season: " .. mp.previousScore, 0.8, 0.6, 0.2)
        end
        if mp.maxDungeonLevel and mp.maxDungeonLevel > 0 then
            GameTooltip:AddLine("Highest Key: +" .. mp.maxDungeonLevel, 0.6, 0.9, 0.6)
        end
        local dungeonData = mp.sortedDungeons or mp.dungeons
        if dungeonData then self:DisplayDungeonData(dungeonData) end
    end

    GameTooltip:Show()
end

function RecruitmentFrame:ProcessRaiderIORaidProfile(raidProfile)
    if raidProfile.progress and type(raidProfile.progress) == "table" then
        GameTooltip:AddLine("Raid Progress:", 0.9, 0.7, 1)

        for _, progress in ipairs(raidProfile.progress) do
            if progress.raid and progress.killsPerBoss then
                local raidName = progress.raid.shortName or progress.raid.name or "Unknown Raid"
                local difficulty = self:GetRaidDifficultyInfo(progress.difficulty)
                local totalKills = 0
                local maxBosses = progress.raid.bossCount or #progress.killsPerBoss

                for _, kills in ipairs(progress.killsPerBoss) do
                    if kills > 0 then totalKills = totalKills + 1 end
                end

                if totalKills > 0 then
                    local progressText = string.format("%s %s: %d/%d", difficulty.suffix or difficulty.name, raidName, totalKills, maxBosses)
                    local color = difficulty.color or {r = 1, g = 1, b = 1}
                    GameTooltip:AddLine(progressText, color.r, color.g, color.b)
                end
            end
        end
    end
end

function RecruitmentFrame:GetRaidDifficultyInfo(difficulty)
    local difficulties = {
        [1] = {name = "LFR", suffix = "L", color = {r = 0.5, g = 1, b = 0.5}},
        [2] = {name = "Normal", suffix = "N", color = {r = 1, g = 1, b = 1}},
        [3] = {name = "Heroic", suffix = "H", color = {r = 0, g = 1, b = 1}},
        [4] = {name = "Mythic", suffix = "M", color = {r = 1, g = 0.5, b = 0}},
    }
    return difficulties[difficulty] or {name = "Unknown", suffix = "?", color = {r = 0.7, g = 0.7, b = 0.7}}
end

function RecruitmentFrame:DisplayDungeonData(dungeonData)
    if not dungeonData or type(dungeonData) ~= "table" then return end

    local runsDisplayed = 0
    for _, dungeon in pairs(dungeonData) do
        if runsDisplayed >= 8 then break end
        if type(dungeon) == "table" then
            local dungeonName = "Unknown"
            local level = dungeon.level or dungeon.keystoneLevel or dungeon.mythicLevel or 0
            local timed = nil
            local score = 0

            if dungeon.chests then timed = dungeon.chests > 0
            elseif dungeon.fractionalTime then timed = dungeon.fractionalTime > 0 end

            if dungeon.dungeon and type(dungeon.dungeon) == "table" then
                local nd = dungeon.dungeon
                dungeonName = nd.name or nd.shortName or nd.short_name or nd.slug or nd.displayName or nd.zone or dungeonName
                if dungeonName == "Unknown" and dungeon.sortOrder then
                    local sortParts = {strsplit("-", dungeon.sortOrder)}
                    if sortParts[3] then dungeonName = self:GetDungeonNameFromAbbreviation(sortParts[3]) end
                end
            end

            score = dungeon.score or dungeon.points or 0

            if level > 0 then
                local levelColor = self:GetKeystoneLevelColor(level)
                local timedText = timed == true and " (Timed)" or timed == false and " (Untimed)" or ""
                local scoreText = score > 0 and (" (" .. score .. ")") or ""
                GameTooltip:AddLine(string.format("%s +%d%s%s", dungeonName, level, timedText, scoreText), levelColor.r, levelColor.g, levelColor.b)
                runsDisplayed = runsDisplayed + 1
            end
        end
    end
end

function RecruitmentFrame:GetDungeonNameFromAbbreviation(abbrev)
    local dungeonMap = {
        ["HOA"] = "Halls of Atonement", ["PF"] = "Plaguefall", ["MOTS"] = "Mists of Tirna Scithe",
        ["DOS"] = "De Other Side", ["SOA"] = "Spires of Ascension", ["TOP"] = "Theater of Pain",
        ["NW"] = "Necrotic Wake", ["SD"] = "Sanguine Depths", ["COT"] = "Court of Stars",
        ["LOWR"] = "Lower Karazhan", ["UPPR"] = "Upper Karazhan",
    }
    return dungeonMap[abbrev] or abbrev
end

function RecruitmentFrame:EnhanceTooltipWithRaiderIO(playerData, unitName)
    local RaiderIO = self:GetRaiderIOReference()
    if not RaiderIO then return end

    local profileData = self:CheckPlayerRaiderIOData(unitName, RaiderIO)
    if profileData then return true end

    if RaiderIO.ShowTooltip then
        local beforeLines = GameTooltip:NumLines()
        local ok = pcall(RaiderIO.ShowTooltip, GameTooltip, unitName)
        if ok and GameTooltip:NumLines() > beforeLines then
            GameTooltip:Show()
            return true
        end
    end

    return false
end

function RecruitmentFrame:GetKeystoneLevelColor(level)
    if level >= 15 then return {r = 1, g = 0.5, b = 0}
    elseif level >= 10 then return {r = 0.64, g = 0.21, b = 0.93}
    else return {r = 0.2, g = 1, b = 0.2} end
end

function RecruitmentFrame:SetupRaiderIOHooks()
    local RaiderIO = self:GetRaiderIOReference()
    if not RaiderIO then return end

    if RaiderIO.modules and RaiderIO.modules.tooltip then
        local tooltipModule = RaiderIO.modules.tooltip
        if tooltipModule.AddTooltipInfo then
            local originalAddInfo = tooltipModule.AddTooltipInfo
            tooltipModule.AddTooltipInfo = function(tooltip, unit, ...)
                return originalAddInfo(tooltip, unit, ...)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Invite Queue Processing
-------------------------------------------------------------------------------

function RecruitmentFrame:ProcessInviteQueue(inviteQueue)
    if #inviteQueue == 0 then
        self:UpdateStatus("All invites processed", "green")
        self:UpdateSessionStats()
        self:UpdateSelectionCount()
        self:UpdateSendInviteButtonState()
        self:UpdateActionButtonVisibility()
        return
    end

    local player = table.remove(inviteQueue, 1)

    if self.inviteMode == "invite_only" then
        ns.GuildInvite(player.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
    elseif self.inviteMode == "invite_and_message" then
        ns.GuildInvite(player.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
        if self.selectedMessage and self.selectedMessage.message then
            self:SendWhisper(self:FormatMessage(self.selectedMessage.message, player.name), player.name)
        end
    elseif self.inviteMode == "just_message" then
        if self.selectedMessage and self.selectedMessage.message then
            self:SendWhisper(self:FormatMessage(self.selectedMessage.message, player.name), player.name)
            self.sessionStats.messagesOnly = (self.sessionStats.messagesOnly or 0) + 1
        end
    end

    if not ns.tblAntiSpamList then ns.tblAntiSpamList = {} end
    ns.tblAntiSpamList[string.lower(player.name)] = { name = player.name, time = time() }

    foundPlayers[player.name] = nil
    selectedPlayers[player.name] = nil
    self:UpdateSessionStats()
    self:UpdateSelectionCount()
    self:UpdateSendInviteButtonState()
    local delay = tonumber((ns.g and ns.g.timeBetweenMessages) or "0.2")
    C_Timer.After(delay, function() self:ProcessInviteQueue(inviteQueue) end)
    self:RefreshPlayerList()
    self:UpdatePlayerCount()
end

-------------------------------------------------------------------------------
-- Message Formatting
-------------------------------------------------------------------------------

function RecruitmentFrame:FormatMessage(message, playerName)
    local formattedMessage = message
    formattedMessage = formattedMessage:gsub("PLAYERNAME", playerName)
    local guildName = GetGuildInfo("player") or "[Guild]"
    formattedMessage = formattedMessage:gsub("GUILDNAME", guildName)

    local guildLink = "[Guild]"
    if ns.guildInfo and ns.guildInfo.guildLink and ns.guildInfo.guildLink ~= "" then
        guildLink = ns.guildInfo.guildLink
    elseif ns.guild and ns.guild.info and ns.guild.info.guildLink and ns.guild.info.guildLink ~= "" then
        guildLink = ns.guild.info.guildLink
    else
        local clubID = ns.guildInfo and ns.guildInfo.clubID
        if not clubID and ns.guild and ns.guild.info then clubID = ns.guild.info.clubID end
        if clubID and not ns.classic then
            local club = ClubFinderGetCurrentClubListingInfo(clubID)
            if club and club.clubFinderGUID then
                guildLink = "|cffffd200|HclubFinder:" .. club.clubFinderGUID .. "|h[" .. (club.name or guildName) .. "]|h|r"
            else
                guildLink = "[" .. guildName .. "]"
            end
        else
            guildLink = "[" .. guildName .. "]"
        end
    end
    formattedMessage = formattedMessage:gsub("GUILDLINK", guildLink)
    return formattedMessage
end

function RecruitmentFrame:EnsureGuildLink()
    if not ns.guildInfo then ns.guildInfo = {} end
    if not ns.guild then ns.guild = {info = {}} end
    if not ns.guild.info then ns.guild.info = {} end
    local guildName = GetGuildInfo("player")
    if not guildName then return end
    ns.guildInfo.guildName = guildName
    ns.guild.info.guildName = guildName
    if ns.classic then
        ns.guildInfo.guildLink = "[" .. guildName .. "]"
        ns.guild.info.guildLink = "[" .. guildName .. "]"
        return
    end
    local clubID = C_Club.GetGuildClubId()
    if clubID then
        ns.guildInfo.clubID = clubID
        ns.guild.info.clubID = clubID
        local club = ClubFinderGetCurrentClubListingInfo(clubID)
        if club and club.clubFinderGUID then
            local link = "|cffffd200|HclubFinder:" .. club.clubFinderGUID .. "|h[" .. club.name .. "]|h|r"
            ns.guildInfo.guildLink = link
            ns.guild.info.guildLink = link
        else
            C_Timer.After(2, function() self:EnsureGuildLink() end)
        end
    end
end

-------------------------------------------------------------------------------
-- Blacklist / Clear / Message List
-------------------------------------------------------------------------------

function RecruitmentFrame:BlacklistSelectedPlayers()
    local count = 0
    for _ in pairs(selectedPlayers) do count = count + 1 end
    if count == 0 then
        self:UpdateStatus("No players selected", "orange")
        return
    end
    if not ns.tblBlackList then ns.tblBlackList = {} end

    for name, data in pairs(selectedPlayers) do
        ns.tblBlackList[string.lower(name)] = {
            name = name,
            reason = "Blacklisted via recruitment interface",
            blBy = UnitName("player"),
            date = date("%m/%d/%Y %H:%M"),
            private = false
        }
        foundPlayers[name] = nil
    end

    selectedPlayers = {}
    self:RefreshPlayerList()
    self:UpdatePlayerCount()
    self:UpdateActionButtonVisibility()
    self:UpdateStatus(string.format("%d players blacklisted", count), "green")
end

function RecruitmentFrame:ClearPlayerList()
    foundPlayers = {}
    selectedPlayers = {}
    self:RefreshPlayerList()
    self:UpdatePlayerCount()
    self:UpdateActionButtonVisibility()
    self:UpdateStatus("Player list cleared", "green")
end

function RecruitmentFrame:GetMessageList()
    if ns.Database and ns.Database.GetMessageList then
        return ns.Database:GetMessageList()
    elseif ns.guild and ns.guild.data and ns.guild.data.messageList then
        return ns.guild.data.messageList
    elseif ns.guild and ns.guild.messageList then
        return ns.guild.messageList
    else
        return {}
    end
end

-------------------------------------------------------------------------------
-- Status / Stats / Count Updates
-------------------------------------------------------------------------------

function RecruitmentFrame:UpdatePlayerCount()
    local count = 0
    for _ in pairs(foundPlayers) do count = count + 1 end
    if self.listHeader then
        self.listHeader:SetText((self.isCompactMode and "Players: " or "Found Players: ") .. count)
    end
end

function RecruitmentFrame:UpdateSelectionCount()
    local selectedCount = 0
    for _ in pairs(selectedPlayers) do selectedCount = selectedCount + 1 end
    if self.selectionBadge then
        self.selectionBadge:SetBadgeText(selectedCount .. " selected")
        self.selectionBadge:SetShown(selectedCount > 0)
    end
end

-- Status is a muted line plus a coloured dot; the text itself stays readable
-- instead of turning into a block of saturated red or green.
local STATUS_TONES = {
    red = "danger", orange = "warning", yellow = "warning",
    green = "success", white = "textMuted",
}

function RecruitmentFrame:UpdateStatus(text, color)
    if not self.statusText then return end
    self.statusText:SetText(text or "")
    local tone = STATUS_TONES[color or "white"] or "textMuted"
    if self.statusDot then
        local r, g, b = T:GetColor(tone)
        self.statusDot:SetColorTexture(r, g, b, 1)
    end
    local tr, tg, tb = T:GetColor(color and color ~= "white" and tone or "textMuted")
    self.statusText:SetTextColor(tr, tg, tb)
end

function RecruitmentFrame:UpdateInviteButtonLabel()
    if not self.sendInviteBtn then return end
    local im = self.inviteMode
    if im == "just_message" then
        self.sendInviteBtn:SetText(self.isCompactMode and "Msg" or "Send Message")
    else
        self.sendInviteBtn:SetText(self.isCompactMode and "Invite" or "Send Invite")
    end
end

function RecruitmentFrame:StartCooldownTimer()
    local function updateCooldown()
        if not self.cooldownText or not self.scanButton then return end
        local currentTime = time()
        local remaining = scanCooldown - (currentTime - lastScanTime)
        if remaining > 0 then
            self.scanButton:SetEnabled(false)
            self.scanButton:SetText("Scan")
            self.cooldownText:SetText(self.isCompactMode and string.format("%ds", math.ceil(remaining)) or string.format("Cooldown: %ds", math.ceil(remaining)))
            self:UpdateNextClassIndicator()
            C_Timer.After(1, updateCooldown)
        else
            self.scanButton:SetEnabled(true)
            self.cooldownText:SetText("")
            self.scanButton:SetText("Scan")
            self:UpdateClassFilterDisplay()
            self:UpdateNextClassIndicator()
        end
    end
    updateCooldown()
end

function RecruitmentFrame:ResetClassScanMode()
    self.isClassScanMode = false
    self.currentClassIndex = 1
    self.selectedClassList = {}
    self.currentScanClass = nil
    self.classListKey = nil -- let UpdateClassFilterDisplay re-arm the cycle from the start
end

-- Called by the settings panel when class/level options change
function RecruitmentFrame:RefreshFromSettings()
    if not self.isInitialized then return end
    if self.classFilterCheck then
        self.classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
    end
    self:UpdateLevelDisplay()
    self:UpdateClassFilterDisplay()
    self:UpdateNextClassIndicator()
end

function RecruitmentFrame:RefreshUI()
    if not self.isInitialized then return end
    self:UpdateLevelDisplay()
    self:UpdateSessionStats()
    self:UpdateClassFilterDisplay()
    self:UpdateNextClassIndicator()
    if self.messageDropdown then
        UIDropDownMenu_Initialize(self.messageDropdown, function(dropdown, level)
            self:BuildModeMenu(self.messageDropdown, level)
        end)
    end
    self:UpdatePlayerCount()
    self:UpdateSelectionCount()
    self:UpdateInviteButtonLabel()
end

function RecruitmentFrame:UpdateSessionStats()
    if not self.statsText then return end
    local invites = self.sessionStats.invitesSent or 0
    local scanned = self.sessionStats.playersScanned or 0
    local messagesOnly = self.sessionStats.messagesOnly or 0
    self.statsText:SetText(string.format("%d inv | %d msg | %d scanned", invites, messagesOnly, scanned))
end

-------------------------------------------------------------------------------
-- Initialize
-------------------------------------------------------------------------------

function RecruitmentFrame:Initialize()
    self.isInitialized = false
    self.frame = nil
    self.playerList = {}
    self.scanButton = nil
    self.sendinviteButton = nil
    self.messageDropdown = nil
    self.playerScrollFrame = nil
    self.statusText = nil
    self.selectedMessage = nil
    self.whoResults = nil
    self._whoResultsExpected = false
    self.lastWhoTime = 0
    self.selectedClassList = {}
    self.currentClassIndex = 1
    self.isClassScanMode = false
    self.sessionStats = { invitesSent = 0, playersScanned = 0, messagesOnly = 0 }
    isScanning = false
    lastScanTime = 0
    if not ns.guild then ns.guild = { data = { messageList = {} } } end
    if not ns.guild.data then ns.guild.data = { messageList = {} } end
    if not ns.guild.data.messageList then ns.guild.data.messageList = {} end
    self:EnsureGuildLink()
    C_Timer.After(3, function() self:SetupRaiderIOHooks() end)
end

function RecruitmentFrame:SelectAllPlayersButton()
    for name, data in pairs(foundPlayers) do
        selectedPlayers[name] = data
        if playerCheckboxes[name] then playerCheckboxes[name]:SetChecked(true) end
    end
    self:UpdateSelectionCount()
    self:UpdateSendInviteButtonState()
end

function RecruitmentFrame:DeselectAllPlayersButton()
    for name in pairs(foundPlayers) do
        selectedPlayers[name] = nil
        if playerCheckboxes[name] then playerCheckboxes[name]:SetChecked(false) end
    end
    self:UpdateSelectionCount()
    self:UpdateSendInviteButtonState()
end

RecruitmentFrame:Initialize()
