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
    local entryHeight = self.isCompactMode and 20 or 22
    local spacing = 1

    for _, playerData in ipairs(sorted) do
        self:CreatePlayerEntry(playerData, yOffset)
        yOffset = yOffset - (entryHeight + spacing)
    end

    self.playerScrollChild:SetHeight(math.abs(yOffset) + 10)
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
-- Theme Helper
-------------------------------------------------------------------------------

local function tc(name)
    if ns.Theme then return ns.Theme:GetColor(name) end
    local fallback = {
        background = {0.05, 0.06, 0.09, 0.95},
        panel = {0.08, 0.09, 0.14, 0.92},
        panelBorder = {0.35, 0.25, 0.55, 0.45},
        accent = {0.63, 0.43, 0.96, 1.0},
        accentSoft = {0.46, 0.36, 0.78, 0.7},
        text = {0.92, 0.92, 0.98, 1.0},
        muted = {0.65, 0.66, 0.74, 1.0},
        warning = {1.0, 0.75, 0.2, 1.0},
    }
    local c = fallback[name] or {1, 1, 1, 1}
    return c[1], c[2], c[3], c[4]
end

local function createSep(parent, yOff)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOff)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, yOff)
    sep:SetHeight(1)
    local r, g, b = tc("panelBorder")
    sep:SetColorTexture(r, g, b, 0.25)
    return sep
end

local function styleLabel(label, colorName)
    local r, g, b = tc(colorName or "accent")
    label:SetTextColor(r, g, b)
end

local function styleBtn(btn, isPrimary, fontSize)
    if ns.Theme then ns.Theme:StyleButton(btn, isPrimary) end
    if fontSize and btn:GetFontString() then
        local font, _, flags = btn:GetFontString():GetFont()
        btn:GetFontString():SetFont(font, fontSize, flags)
    end
end

-------------------------------------------------------------------------------
-- UI CREATION - Main Frame
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateFrame()
    local isCompact = self.compactMode or (ns.pSettings and ns.pSettings.isCompact) or false

    -- Destroy old frame if switching modes
    if self.frame then
        self.frame:Hide()
        self.frame:SetParent(nil)
        self.frame = nil
    end

    local frame = CreateFrame("Frame", "FGRRecruitmentFrame", UIParent, "BasicFrameTemplateWithInset")

    if isCompact then
        frame:SetSize(260, 340)
    else
        frame:SetSize(720, 540)
    end

    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject(isCompact and "GameFontNormalSmall" or "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText(isCompact and "FGR" or "Fast Guild Recruiter")

    if ns.Theme then
        ns.Theme:ApplyFrame(frame, isCompact and "FGR" or "Fast Guild Recruiter")
    end

    -- Close button
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            self:Hide()
        end)
    end

    -- Mode toggle button (top-right, before close)
    local toggleBtn = CreateFrame("Button", nil, frame)
    toggleBtn:SetSize(20, 20)
    toggleBtn:SetPoint("RIGHT", frame.CloseButton or frame, frame.CloseButton and "LEFT" or "TOPRIGHT", frame.CloseButton and -2 or -24, frame.CloseButton and 0 or -4)
    toggleBtn:SetNormalFontObject("GameFontNormalSmall")

    local toggleText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggleText:SetPoint("CENTER")
    toggleText:SetText(isCompact and "+" or "-")
    local ar, ag, ab = tc("accent")
    toggleText:SetTextColor(ar, ag, ab)

    toggleBtn:SetScript("OnClick", function()
        self:ToggleCompactMode()
    end)
    toggleBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:SetText(isCompact and "Switch to Full Mode" or "Switch to Compact Mode")
        GameTooltip:Show()
    end)
    toggleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Version text (normal mode only)
    if not isCompact then
        local verText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        verText:SetPoint("RIGHT", toggleBtn, "LEFT", -6, 0)
        verText:SetText(FGR and FGR.versionOut or "")
        local mr, mg, mb = tc("muted")
        verText:SetTextColor(mr, mg, mb, 0.6)
    end

    self.frame = frame
    self.isCompactMode = isCompact

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

    -- Save preference
    if ns.pSettings then
        ns.pSettings.isCompact = self.compactMode
    end

    -- Rebuild
    self._registeredWindow = false
    self.isInitialized = false
    self:CreateFrame()

    if wasShown then
        self.frame:Show()
        self:RefreshUI()
    end
end

-------------------------------------------------------------------------------
-- NORMAL MODE UI
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateNormalUI()
    local frame = self.frame
    local yOff = -30

    -- ===== TOP BAR: Scan + Cooldown + Class info =====
    local topBar = CreateFrame("Frame", nil, frame)
    topBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOff)
    topBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, yOff)
    topBar:SetHeight(28)

    local scanBtn = CreateFrame("Button", nil, topBar, "UIPanelButtonTemplate")
    scanBtn:SetPoint("LEFT", topBar, "LEFT", 4, 0)
    scanBtn:SetSize(80, 24)
    scanBtn:SetText("Scan")
    scanBtn:SetScript("OnClick", function() self:StartPlayerScan() end)
    styleBtn(scanBtn, true)
    self.scanButton = scanBtn

    local cooldownText = topBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cooldownText:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
    cooldownText:SetText("")
    cooldownText:SetTextColor(1, 0.6, 0.2)
    self.cooldownText = cooldownText

    local nextClassText = topBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nextClassText:SetPoint("LEFT", cooldownText, "RIGHT", 8, 0)
    nextClassText:SetText("")
    styleLabel(nextClassText, "muted")
    self.nextClassText = nextClassText

    -- Session stats (right-aligned in top bar)
    local statsText = topBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    statsText:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
    statsText:SetText("")
    styleLabel(statsText, "muted")
    self.statsText = statsText

    yOff = yOff - 30
    createSep(frame, yOff)
    yOff = yOff - 6

    -- ===== FILTER ROW =====
    local filterRow = CreateFrame("Frame", nil, frame)
    filterRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOff)
    filterRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, yOff)
    filterRow:SetHeight(22)

    local levelLabel = filterRow:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    levelLabel:SetPoint("LEFT", filterRow, "LEFT", 4, 0)
    levelLabel:SetText("Level:")
    styleLabel(levelLabel, "muted")

    local levelDisplay = filterRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    levelDisplay:SetPoint("LEFT", levelLabel, "RIGHT", 4, 0)
    levelDisplay:SetTextColor(1, 1, 1)
    self.levelDisplay = levelDisplay

    local zoneFilterCheck = CreateFrame("CheckButton", nil, filterRow, "InterfaceOptionsCheckButtonTemplate")
    zoneFilterCheck:SetPoint("LEFT", levelDisplay, "RIGHT", 14, 0)
    zoneFilterCheck:SetScale(0.82)
    zoneFilterCheck.Text:SetText("Zone filter")
    zoneFilterCheck:SetChecked(true)
    self.zoneFilterCheck = zoneFilterCheck

    local classFilterCheck = CreateFrame("CheckButton", nil, filterRow, "InterfaceOptionsCheckButtonTemplate")
    classFilterCheck:SetPoint("LEFT", zoneFilterCheck.Text, "RIGHT", 10, 0)
    classFilterCheck:SetScale(0.82)
    classFilterCheck.Text:SetText("Class filter")
    classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
    classFilterCheck:SetScript("OnClick", function(cb)
        if not ns.pSettings then ns.pSettings = {} end
        ns.pSettings.enableClassFilter = cb:GetChecked()
        RecruitmentFrame:UpdateClassFilterDisplay()
    end)
    self.classFilterCheck = classFilterCheck

    local classFilterInfo = filterRow:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    classFilterInfo:SetPoint("LEFT", classFilterCheck.Text, "RIGHT", 10, 0)
    classFilterInfo:SetPoint("RIGHT", filterRow, "RIGHT", -4, 0)
    classFilterInfo:SetJustifyH("LEFT")
    styleLabel(classFilterInfo, "muted")
    self.classFilterInfo = classFilterInfo

    yOff = yOff - 24
    createSep(frame, yOff)
    yOff = yOff - 6

    -- ===== INVITE STYLE ROW =====
    local msgRow = CreateFrame("Frame", nil, frame)
    msgRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOff)
    msgRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, yOff)
    msgRow:SetHeight(26)

    local msgLabel = msgRow:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    msgLabel:SetPoint("LEFT", msgRow, "LEFT", 4, 0)
    msgLabel:SetText("Mode:")
    styleLabel(msgLabel, "accent")

    local msgDropdown = CreateFrame("Frame", nil, msgRow, "UIDropDownMenuTemplate")
    msgDropdown:SetPoint("LEFT", msgLabel, "RIGHT", -4, -2)
    msgDropdown:SetScale(0.85)
    UIDropDownMenu_SetWidth(msgDropdown, 360)

    local ref = self
    UIDropDownMenu_Initialize(msgDropdown, function(dropdown, level)
        local messageList = ref:GetMessageList()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Invite Only (No Message)"
        info.value = "invite_only"
        info.func = function()
            UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_only")
            ref.selectedMessage = nil
            ref.inviteMode = "invite_only"
            ref:UpdateInviteButtonLabel()
        end
        UIDropDownMenu_AddButton(info, level)

        for i, msgData in ipairs(messageList) do
            local invInfo = UIDropDownMenu_CreateInfo()
            invInfo.text = "Invite + Msg: " .. (msgData.desc or ("Message " .. i))
            invInfo.value = "invite_and_message_" .. i
            invInfo.func = function()
                UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_and_message_" .. i)
                ref.selectedMessage = msgData
                ref.inviteMode = "invite_and_message"
                ref:UpdateInviteButtonLabel()
            end
            UIDropDownMenu_AddButton(invInfo, level)

            local msgInfo = UIDropDownMenu_CreateInfo()
            msgInfo.text = "Message Only: " .. (msgData.desc or ("Message " .. i))
            msgInfo.value = "just_message_" .. i
            msgInfo.func = function()
                UIDropDownMenu_SetSelectedValue(msgDropdown, "just_message_" .. i)
                ref.selectedMessage = msgData
                ref.inviteMode = "just_message"
                ref:UpdateInviteButtonLabel()
            end
            UIDropDownMenu_AddButton(msgInfo, level)
        end
    end)

    UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_only")
    self.messageDropdown = msgDropdown
    self.inviteMode = "invite_only"

    yOff = yOff - 28
    createSep(frame, yOff)
    yOff = yOff - 4

    -- ===== PLAYER LIST HEADER =====
    local listHeaderRow = CreateFrame("Frame", nil, frame)
    listHeaderRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOff)
    listHeaderRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, yOff)
    listHeaderRow:SetHeight(20)

    local listHeader = listHeaderRow:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listHeader:SetPoint("LEFT", listHeaderRow, "LEFT", 4, 0)
    listHeader:SetText("Found Players: 0")
    styleLabel(listHeader, "accent")
    self.listHeader = listHeader

    local selectAllBtn = CreateFrame("Button", nil, listHeaderRow, "UIPanelButtonTemplate")
    selectAllBtn:SetPoint("LEFT", listHeader, "RIGHT", 12, 0)
    selectAllBtn:SetSize(65, 18)
    selectAllBtn:SetText("Select All")
    styleBtn(selectAllBtn, false, 10)
    selectAllBtn:SetScript("OnClick", function() self:SelectAllPlayersButton() end)
    self.selectAllBtn = selectAllBtn

    local deselectAllBtn = CreateFrame("Button", nil, listHeaderRow, "UIPanelButtonTemplate")
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    deselectAllBtn:SetSize(60, 18)
    deselectAllBtn:SetText("Deselect")
    styleBtn(deselectAllBtn, false, 10)
    deselectAllBtn:SetScript("OnClick", function() self:DeselectAllPlayersButton() end)
    self.deselectAllBtn = deselectAllBtn

    yOff = yOff - 22

    -- Column headers
    local colY = yOff
    local hdrFont = "GameFontNormalSmall"
    local cols = {
        {x = 40, text = "Name"},
        {x = 200, text = "Lvl"},
        {x = 240, text = "Class"},
        {x = 370, text = "Zone"},
        {x = 530, text = "Race"},
    }
    for _, col in ipairs(cols) do
        local h = frame:CreateFontString(nil, "ARTWORK", hdrFont)
        h:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x, colY)
        h:SetText(col.text)
        styleLabel(h, "muted")
    end

    yOff = yOff - 16

    -- ===== SCROLL FRAME =====
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, yOff)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 52)

    -- Subtle inset background
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetPoint("TOPLEFT", -1, 1)
    scrollBg:SetPoint("BOTTOMRIGHT", 1, -1)
    local pr, pg, pb, pa = tc("panel")
    scrollBg:SetColorTexture(pr, pg, pb, pa * 0.7)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 10, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local cur = sf:GetVerticalScroll()
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(cur - (delta * 24), max)))
    end)

    self.playerScrollFrame = scrollFrame
    self.playerScrollChild = scrollChild

    -- ===== BOTTOM ACTION BAR =====
    local bottomBar = CreateFrame("Frame", nil, frame)
    bottomBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 6)
    bottomBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 6)
    bottomBar:SetHeight(42)

    -- Status text
    local statusText = bottomBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", bottomBar, "BOTTOMLEFT", 4, 2)
    statusText:SetText("Ready")
    statusText:SetTextColor(0, 1, 0)
    self.statusText = statusText

    -- Action buttons (top of bottom bar)
    local sendInviteBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    sendInviteBtn:SetPoint("TOPLEFT", bottomBar, "TOPLEFT", 4, 0)
    sendInviteBtn:SetSize(110, 24)
    sendInviteBtn:SetText("Send Invite")
    sendInviteBtn:SetScript("OnClick", function() self:SendNextInvite() end)
    sendInviteBtn:Hide()
    styleBtn(sendInviteBtn, true)
    self.sendInviteBtn = sendInviteBtn

    local blacklistBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", 6, 0)
    blacklistBtn:SetSize(80, 24)
    blacklistBtn:SetText("Blacklist")
    blacklistBtn:SetScript("OnClick", function() self:BlacklistSelectedPlayers() end)
    blacklistBtn:Hide()
    self.blacklistBtn = blacklistBtn

    local clearBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 6, 0)
    clearBtn:SetSize(55, 24)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() self:ClearPlayerList() end)
    clearBtn:Hide()
    self.clearBtn = clearBtn

    -- Settings button (right side)
    local settingsBtn = CreateFrame("Button", nil, bottomBar, "UIPanelButtonTemplate")
    settingsBtn:SetPoint("TOPRIGHT", bottomBar, "TOPRIGHT", -4, 0)
    settingsBtn:SetSize(75, 24)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        if ns.SettingsManager then ns.SettingsManager:OpenSettings() end
    end)

    -- Initialize displays
    self:UpdateLevelDisplay()
    self:UpdateClassFilterDisplay()
end

-------------------------------------------------------------------------------
-- COMPACT MODE UI - Essentials only for playing at the same time
-------------------------------------------------------------------------------

function RecruitmentFrame:CreateCompactUI()
    local frame = self.frame

    -- ===== SCAN ROW =====
    local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    scanBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -28)
    scanBtn:SetSize(55, 20)
    scanBtn:SetText("Scan")
    styleBtn(scanBtn, true, 10)
    scanBtn:SetScript("OnClick", function() self:StartPlayerScan() end)
    self.scanButton = scanBtn

    local cooldownText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cooldownText:SetPoint("LEFT", scanBtn, "RIGHT", 5, 0)
    cooldownText:SetText("")
    cooldownText:SetTextColor(1, 0.6, 0.2)
    self.cooldownText = cooldownText

    local nextClassText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nextClassText:SetPoint("LEFT", cooldownText, "RIGHT", 4, 0)
    nextClassText:SetText("")
    styleLabel(nextClassText, "muted")
    self.nextClassText = nextClassText

    -- ===== PLAYER COUNT + SELECT =====
    local listHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    listHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -50)
    listHeader:SetText("Players: 0")
    styleLabel(listHeader, "accent")
    self.listHeader = listHeader

    local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllBtn:SetPoint("LEFT", listHeader, "RIGHT", 6, 0)
    selectAllBtn:SetSize(28, 16)
    selectAllBtn:SetText("All")
    styleBtn(selectAllBtn, false, 9)
    selectAllBtn:SetScript("OnClick", function() self:SelectAllPlayersButton() end)
    self.selectAllBtn = selectAllBtn

    local deselectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 2, 0)
    deselectAllBtn:SetSize(34, 16)
    deselectAllBtn:SetText("None")
    styleBtn(deselectAllBtn, false, 9)
    deselectAllBtn:SetScript("OnClick", function() self:DeselectAllPlayersButton() end)
    self.deselectAllBtn = deselectAllBtn

    -- ===== PLAYER LIST =====
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -66)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 42)

    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetPoint("TOPLEFT", -1, 1)
    scrollBg:SetPoint("BOTTOMRIGHT", 1, -1)
    local pr, pg, pb, pa = tc("panel")
    scrollBg:SetColorTexture(pr, pg, pb, pa * 0.6)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 6, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local cur = sf:GetVerticalScroll()
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(cur - (delta * 20), max)))
    end)

    self.playerScrollFrame = scrollFrame
    self.playerScrollChild = scrollChild

    -- ===== BOTTOM BUTTONS =====
    local sendInviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendInviteBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 22)
    sendInviteBtn:SetSize(55, 18)
    sendInviteBtn:SetText("Invite")
    styleBtn(sendInviteBtn, true, 10)
    sendInviteBtn:SetScript("OnClick", function() self:SendNextInvite() end)
    sendInviteBtn:Hide()
    self.sendInviteBtn = sendInviteBtn

    local blacklistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", 2, 0)
    blacklistBtn:SetSize(45, 18)
    blacklistBtn:SetText("Block")
    styleBtn(blacklistBtn, false, 10)
    blacklistBtn:SetScript("OnClick", function() self:BlacklistSelectedPlayers() end)
    blacklistBtn:Hide()
    self.blacklistBtn = blacklistBtn

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 2, 0)
    clearBtn:SetSize(40, 18)
    clearBtn:SetText("Clear")
    styleBtn(clearBtn, false, 10)
    clearBtn:SetScript("OnClick", function() self:ClearPlayerList() end)
    clearBtn:Hide()
    self.clearBtn = clearBtn

    -- Status (bottom line)
    local statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
    statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
    statusText:SetText("Ready")
    statusText:SetTextColor(0, 1, 0)
    statusText:SetJustifyH("LEFT")
    self.statusText = statusText

    -- No extras in compact mode
    self.statsText = nil
    self.zoneFilterCheck = nil
    self.classFilterCheck = nil
    self.classFilterInfo = nil
    self.messageDropdown = nil
    self.levelDisplay = nil
    self.inviteMode = "invite_only"
end

-------------------------------------------------------------------------------
-- Player Entry Rendering
-------------------------------------------------------------------------------

function RecruitmentFrame:CreatePlayerEntry(playerData, yOffset)
    local classColor = RAID_CLASS_COLORS[playerData.class] or {r = 1, g = 1, b = 1}
    local isCompact = self.isCompactMode
    local entryHeight = isCompact and 18 or 22
    local parentWidth = self.playerScrollChild:GetWidth()

    local entry = CreateFrame("Frame", nil, self.playerScrollChild)
    entry:SetPoint("TOPLEFT", self.playerScrollChild, "TOPLEFT", 0, yOffset)
    entry:SetSize(parentWidth, entryHeight)

    -- Alternating row background
    local bg = entry:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(entry)
    local rowIndex = math.abs(yOffset / (entryHeight + 1))
    local pr, pg, pb, pa = tc("panel")
    if (rowIndex % 2) == 0 then
        bg:SetColorTexture(pr * 1.3, pg * 1.3, pb * 1.3, pa * 0.5)
    else
        bg:SetColorTexture(pr, pg, pb, pa * 0.3)
    end

    -- Hover highlight
    local highlight = entry:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(entry)
    local ar, ag, ab = tc("accent")
    highlight:SetColorTexture(ar, ag, ab, 0.08)

    -- Class color bar (left edge)
    local classBorder = entry:CreateTexture(nil, "OVERLAY")
    classBorder:SetPoint("LEFT", entry, "LEFT", 0, 0)
    classBorder:SetSize(2, entryHeight)
    classBorder:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.85)

    -- Checkbox
    local checkbox = CreateFrame("CheckButton", nil, entry, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("LEFT", entry, "LEFT", 4, 0)
    checkbox:SetSize(isCompact and 16 or 18, isCompact and 16 or 18)
    if isCompact then checkbox:SetScale(0.8) end
    checkbox:SetChecked(selectedPlayers[playerData.name] ~= nil)
    checkbox:SetScript("OnClick", function(cb)
        if cb:GetChecked() then
            selectedPlayers[playerData.name] = playerData
        else
            selectedPlayers[playerData.name] = nil
        end
        RecruitmentFrame:UpdateSelectionCount()
        RecruitmentFrame:UpdateSendInviteButtonState()
    end)
    playerCheckboxes[playerData.name] = checkbox

    if isCompact then
        -- COMPACT: Name (class-colored) + Level right-aligned
        local nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", entry, "LEFT", 22, 0)
        nameText:SetPoint("RIGHT", entry, "RIGHT", -30, 0)
        nameText:SetJustifyH("LEFT")
        local displayName = playerData.name
        if displayName:find("-") then
            displayName = displayName:match("([^-]+)")
        end
        nameText:SetText(displayName)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)

        local levelText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
        levelText:SetText(tostring(playerData.level))
        local mr, mg, mb = tc("muted")
        levelText:SetTextColor(mr, mg, mb)

        -- Tooltip on hover
        entry:EnableMouse(true)
        entry:SetScript("OnEnter", function(e)
            RecruitmentFrame:ShowPlayerTooltip(e, playerData)
        end)
        entry:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        -- NORMAL: Name | Level | Class | Zone | Race | RIO
        local nameFrame = CreateFrame("Frame", nil, entry)
        nameFrame:SetPoint("LEFT", entry, "LEFT", 24, 0)
        nameFrame:SetSize(160, entryHeight)
        nameFrame:EnableMouse(true)

        local nameText = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", nameFrame, "LEFT", 0, 0)
        nameText:SetText(playerData.name)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)

        nameFrame:SetScript("OnEnter", function(e)
            RecruitmentFrame:ShowPlayerTooltip(e, playerData)
        end)
        nameFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local levelText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("LEFT", entry, "LEFT", 186, 0)
        levelText:SetText(tostring(playerData.level))
        levelText:SetTextColor(0.9, 0.9, 0.9)

        local classText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        classText:SetPoint("LEFT", entry, "LEFT", 226, 0)
        classText:SetText(playerData.class)
        classText:SetTextColor(classColor.r, classColor.g, classColor.b, 0.85)

        local zoneText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        zoneText:SetPoint("LEFT", entry, "LEFT", 356, 0)
        local zoneName = playerData.zone or ""
        if #zoneName > 20 then zoneName = zoneName:sub(1, 19) .. ".." end
        zoneText:SetText(zoneName)
        local mr, mg, mb = tc("muted")
        zoneText:SetTextColor(mr, mg, mb)

        local raceText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        raceText:SetPoint("LEFT", entry, "LEFT", 516, 0)
        raceText:SetText(playerData.race or "")
        raceText:SetTextColor(mr, mg, mb)

        -- RIO button
        local rioBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
        rioBtn:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
        rioBtn:SetSize(30, 16)
        rioBtn:SetText("RIO")
        styleBtn(rioBtn, false, 9)
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
    if self.selectAllCheck and self.selectAllCheck.Text then
        self.selectAllCheck.Text:SetText("Select All (" .. selectedCount .. ")")
    end
end

function RecruitmentFrame:UpdateStatus(text, color)
    if not self.statusText then return end
    self.statusText:SetText(text)
    if color == "red" then self.statusText:SetTextColor(1, 0, 0)
    elseif color == "yellow" or color == "orange" then self.statusText:SetTextColor(1, 1, 0)
    elseif color == "green" then self.statusText:SetTextColor(0, 1, 0)
    else self.statusText:SetTextColor(1, 1, 1) end
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
        local ref = self
        UIDropDownMenu_Initialize(self.messageDropdown, function(dropdown, level)
            local messageList = ref:GetMessageList()
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Invite Only (No Message)"
            info.value = "invite_only"
            info.func = function()
                UIDropDownMenu_SetSelectedValue(ref.messageDropdown, "invite_only")
                ref.selectedMessage = nil
                ref.inviteMode = "invite_only"
                ref:UpdateInviteButtonLabel()
            end
            UIDropDownMenu_AddButton(info, level)
            for i, msgData in ipairs(messageList) do
                local invInfo = UIDropDownMenu_CreateInfo()
                invInfo.text = "Invite + Msg: " .. (msgData.desc or ("Message " .. i))
                invInfo.value = "invite_and_message_" .. i
                invInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(ref.messageDropdown, "invite_and_message_" .. i)
                    ref.selectedMessage = msgData
                    ref.inviteMode = "invite_and_message"
                    ref:UpdateInviteButtonLabel()
                end
                UIDropDownMenu_AddButton(invInfo, level)
                local msgInfo = UIDropDownMenu_CreateInfo()
                msgInfo.text = "Message Only: " .. (msgData.desc or ("Message " .. i))
                msgInfo.value = "just_message_" .. i
                msgInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(ref.messageDropdown, "just_message_" .. i)
                    ref.selectedMessage = msgData
                    ref.inviteMode = "just_message"
                    ref:UpdateInviteButtonLabel()
                end
                UIDropDownMenu_AddButton(msgInfo, level)
            end
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
