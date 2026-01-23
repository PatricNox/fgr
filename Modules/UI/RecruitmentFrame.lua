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

-- WHO query with event-driven results, single event model
function RecruitmentFrame:SendActualWhoQuery(query, className)
    self._whoResultsExpected = true
    self.currentQueryClass = className
    self.whoQueryStartTime = GetTime()
    self.lastWhoQuery = query
    self.awaitingResults = true

    local timeSinceLastQuery = GetTime() - (self.lastWhoTime or 0)
    if timeSinceLastQuery < 5 then
        local waitTime = 5 - timeSinceLastQuery
        -- print("|cFF3EB9D8[FGR-DEBUG]|r WHO query on cooldown, waiting " .. string.format("%.1f", waitTime) .. " seconds")
        C_Timer.After(waitTime, function()
            self:SendActualWhoQuery(query, className)
        end)
        return
    end

    -- print("|cFF3EB9D8[FGR-DEBUG]|r Sending WHO query: " .. query)
    C_FriendList.SetWhoToUi(true)
    local success = pcall(function() C_FriendList.SendWho(query) end)
    if not success then
        -- print("|cFF3EB9D8[FGR-DEBUG]|r SendWho failed with pcall protection")
        self:HandleWhoQueryFailure("SendWho failed")
        self.awaitingResults = false
        self._whoResultsExpected = false
        return
    end

    self.lastWhoTime = GetTime()

    -- Failsafe: After 8 seconds, if not processed, treat as failure
    C_Timer.After(8, function()
        if self._whoResultsExpected then
            -- print("|cFF3EB9D8[FGR-DEBUG]|r WHO query timed out after 8 seconds (no event received)")
            self:HandleWhoQueryFailure("Polling timeout")
            self.awaitingResults = false
            self._whoResultsExpected = false
        end
    end)
end

function RecruitmentFrame:_OnWhoListUpdate()
    -- Only process if we expected results
    if not self._whoResultsExpected then return end
    -- print("|cFF3EB9D8[FGR-DEBUG]|r WHO_LIST_UPDATE event received. Processing results!")
    self._whoResultsExpected = false
    self.awaitingResults = false
    self:ProcessWhoResults_Polling()
end

function RecruitmentFrame:ProcessWhoResults_Polling()
    if FriendsFrame then FriendsFrame:Hide() end
    
    local results = {}
    local numResults = C_FriendList.GetNumWhoResults()

    -- print("|cFF3EB9D8[FGR-DEBUG]|r Processing " .. numResults .. " WHO results via event")

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
                -- print("|cFF3EB9D8[FGR-DEBUG]|r   Added: " .. playerName .. " (" .. playerClass .. ")")
            end
        end
    end

    -- print("|cFF3EB9D8[FGR]|r Processing " .. #results .. " valid players")

    if #results > 0 then
        local validCount = 0
        local filteredCount = 0
        for _, playerInfo in ipairs(results) do
            if playerInfo.name and playerInfo.name ~= UnitName("player") then
                if self:PassesFilters(playerInfo) then
                    foundPlayers[playerInfo.name] = playerInfo
                    validCount = validCount + 1
                    -- print("|cFF3EB9D8[FGR-DEBUG]|r   -> Added to found players: " .. playerInfo.name)
                else
                    filteredCount = filteredCount + 1
                    -- print("|cFF3EB9D8[FGR-DEBUG]|r   -> Filtered out: " .. playerInfo.name)
                end
            end
        end

        self:RefreshPlayerList()
        self:UpdatePlayerCount()
        self:UpdateSessionStats()

        local statusMsg = string.format("Found %d valid players (%d filtered out)", validCount, filteredCount)
        self:UpdateStatus(statusMsg, validCount > 0 and "green" or "orange")
    else
        self:UpdateStatus("No valid WHO results", "orange")
    end

    self:UpdateActionButtonVisibility()
    self:ReEnableScanButton()
end

function RecruitmentFrame:HandleWhoQueryFailure(reason)
    self._whoResultsExpected = false
    self.awaitingResults = false

    self:UpdateStatus("WHO query failed: " .. reason, "orange")

    if self.scanButton then
        self.scanButton:SetEnabled(true)
        self.scanButton:SetText("Run")
        self:UpdateNextClassIndicator()
    end
end

function RecruitmentFrame:ReEnableScanButton()
    if self.scanButton then
        self.scanButton:SetEnabled(true)
        self.scanButton:SetText("Run")
        if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
            local nextIndex = (self.currentClassIndex or 1) + 1
            if nextIndex > #self.selectedClassList then
                self:ResetClassScanMode()
            end
        end
        self:UpdateNextClassIndicator()
    end
    self:StartCooldownTimer()
end

function RecruitmentFrame:ExecuteWhoQuery(query, className)
    -- print("|cFF3EB9D8[FGR]|r Executing WHO query: " .. query)

    -- Level range (from settings)
    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()

    -- print("|cFF3EB9D8[FGR-DEBUG]|r Settings check:")
    -- print("|cFF3EB9D8[FGR-DEBUG]|r   ns.pSettings exists: " .. tostring(ns.pSettings ~= nil))
    if ns.pSettings then
        -- print("|cFF3EB9D8[FGR-DEBUG]|r   minLevel setting: " .. tostring(ns.pSettings.minLevel))
        -- print("|cFF3EB9D8[FGR-DEBUG]|r   maxLevel setting: " .. tostring(ns.pSettings.maxLevel))
    end
    -- print("|cFF3EB9D8[FGR-DEBUG]|r   Final minLevel: " .. minLevel)
    -- print("|cFF3EB9D8[FGR-DEBUG]|r   Final maxLevel: " .. maxLevel)

    local finalQuery = query
    if className then
        finalQuery = "c-" .. string.lower(className) .. " " .. minLevel .. "-" .. maxLevel
        -- Some retail versions require: finalQuery = "class:" .. string.lower(className) .. " " .. minLevel .. "-" .. maxLevel
        -- Uncomment and test the above if needed.
    end

    -- print("|cFF3EB9D8[FGR-DEBUG]|r Final query with level range: " .. finalQuery)
    self:SendActualWhoQuery(finalQuery, className)
end

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
        print("[FGR] Recruitment frame shown directly")
    end
end

function RecruitmentFrame:Hide()
    if ns.WindowManager and self._registeredWindow then
        ns.WindowManager:HideWindow("recruitment")
    elseif self.frame then
        self.frame:Hide()
        print("[FGR] Recruitment frame hidden directly")
    end
end

function RecruitmentFrame:CreateFrame()
    local isCompact = self.compactMode or (ns.pSettings and ns.pSettings.isCompact) or false
    
    local frame = CreateFrame("Frame", "FGRRecruitmentFrame", UIParent, "BasicFrameTemplateWithInset")
    
    if isCompact then
        frame:SetSize(350, 250)
    else
        frame:SetSize(800, 600)
    end
    
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject(isCompact and "GameFontNormalSmall" or "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText(isCompact and "FGR" or "Fast Guild Recruiter - Recruitment")

    if ns.Theme then
        ns.Theme:ApplyFrame(frame, isCompact and "FGR" or "Fast Guild Recruiter - Recruitment")
    end
    
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            self:Hide()
        end)
    end
    
    self.frame = frame
    self.isCompactMode = isCompact
    
    self:CreateScanSection()
    self:CreateFilterSection()
    if not isCompact then
        self:CreateMessageSection()
    end
    self:CreatePlayerList()
    self:CreateActionButtons()
    self:CreateStatusSection()
    
    self.isInitialized = true
    self:RegisterWindowIfNeeded()
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

function RecruitmentFrame:SplitMessage(message, limit)
    local chunks = {}
    if not message or message == "" then
        return chunks
    end

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

    if current ~= "" then
        table.insert(chunks, current)
    end

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
    return string.format("https://raider.io/characters/%s/%s/%s",
        region,
        urlEncode(realm),
        urlEncode(baseName))
end

function RecruitmentFrame:SendWhisper(message, target)
    if not message or message == "" or not target or target == "" then
        return
    end

    local chunks = self:SplitMessage(message, MAX_WHISPER_LENGTH)
    if #chunks == 0 then
        return
    end

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

function RecruitmentFrame:CreateScanSection()
    local frame = self.frame
    local isCompact = self.isCompactMode
    local yOffset = isCompact and -30 or -80
    local theme = ns.Theme

    if isCompact then
        -- Ultra-compact: Just scan button and basic info
        local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        scanBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        scanBtn:SetSize(80, 22)
        scanBtn:SetText("Run")
        scanBtn:SetScript("OnClick", function()
            self:StartPlayerScan()
        end)
        self.scanButton = scanBtn

        local nextClassText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        nextClassText:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
        nextClassText:SetText("")
        nextClassText:SetTextColor(0.8, 0.8, 1)
        self.nextClassText = nextClassText

        local cooldownText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        cooldownText:SetPoint("TOPLEFT", scanBtn, "BOTTOMLEFT", 0, -4)
        cooldownText:SetText("")
        cooldownText:SetTextColor(1, 0.5, 0)
        self.cooldownText = cooldownText
        
    else
        -- Normal mode (keep existing)
        local scanHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        scanHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        scanHeader:SetText("Scanning:")
        if theme then
            local r, g, b = theme:GetColor("accent")
            scanHeader:SetTextColor(r, g, b)
        else
            scanHeader:SetTextColor(0.24, 0.73, 0.85)
        end
        yOffset = yOffset - 25

        local scanBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        scanBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        scanBtn:SetSize(120, 30)
        scanBtn:SetText("Run")
        scanBtn:SetScript("OnClick", function()
            self:StartPlayerScan()
        end)
        self.scanButton = scanBtn

        local nextClassText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        nextClassText:SetPoint("LEFT", scanBtn, "RIGHT", 10, 0)
        nextClassText:SetText("")
        nextClassText:SetTextColor(0.8, 0.8, 1)
        self.nextClassText = nextClassText

        local cooldownText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        cooldownText:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset - 35)
        cooldownText:SetText("")
        cooldownText:SetTextColor(1, 0.5, 0)
        self.cooldownText = cooldownText
    end
end

function RecruitmentFrame:UpdateNextClassIndicator()
    if not self.nextClassText then return end
    if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
        local nextIndex = (self.currentClassIndex or 1) + 1
        if nextIndex <= #self.selectedClassList then
            local nextClass = self.selectedClassList[nextIndex]
            self.nextClassText:SetText("Next: " .. nextClass .. " (" .. nextIndex .. "/" .. #self.selectedClassList .. ")")
            self._readyForNextClass = true
            return
        end
    end
    self.nextClassText:SetText("")
    self._readyForNextClass = false
end

function RecruitmentFrame:UpdateNextClassIndicator()
    if not self.nextClassText then return end
    if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
        local nextIndex = (self.currentClassIndex or 1) + 1
        if nextIndex <= #self.selectedClassList then
            local nextClass = self.selectedClassList[nextIndex]
            self.nextClassText:SetText("Next: " .. nextClass .. " (" .. nextIndex .. "/" .. #self.selectedClassList .. ")")
            self._readyForNextClass = true
            return
        end
    end
    self.nextClassText:SetText("")
    self._readyForNextClass = false
end

function RecruitmentFrame:CreateFilterSection()
    local frame = self.frame
    local isCompact = self.isCompactMode
    local yOffset = isCompact and -55 or -160

    if isCompact then
        -- Ultra-compact: Horizontal layout for filters
        
        -- Level display (no label, just numbers)
        local levelDisplay = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        levelDisplay:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        levelDisplay:SetTextColor(0.8, 0.8, 1)
        self.levelDisplay = levelDisplay
        
        -- Class filter checkbox - smaller and to the right
        local classFilterCheck = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        classFilterCheck:SetPoint("LEFT", levelDisplay, "RIGHT", 15, 0)
        classFilterCheck:SetScale(0.7)
        classFilterCheck.Text:SetText("Class")
        classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
        classFilterCheck:SetScript("OnClick", function(self)
            if not ns.pSettings then ns.pSettings = {} end
            ns.pSettings.enableClassFilter = self:GetChecked()
            RecruitmentFrame:UpdateClassFilterDisplay()
        end)
        self.classFilterCheck = classFilterCheck
        
        -- Class filter info - below level display
        local classFilterInfo = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        classFilterInfo:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset - 15)
        classFilterInfo:SetWidth(300)
        classFilterInfo:SetTextColor(0.8, 0.8, 1)
        self.classFilterInfo = classFilterInfo
        
        -- Hide zone filter in ultra-compact mode to save space
        self.zoneFilterCheck = nil
    else
        -- Normal mode (keep your existing filter section)
        local filterHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        filterHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        filterHeader:SetText("Filters:")
        filterHeader:SetTextColor(0.24, 0.73, 0.85)

        yOffset = yOffset - 25
        local levelLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        levelLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, yOffset)
        levelLabel:SetText("Level Range:")

        local levelDisplay = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        levelDisplay:SetPoint("LEFT", levelLabel, "RIGHT", 4, 0)
        levelDisplay:SetTextColor(0.8, 0.8, 1)
        self.levelDisplay = levelDisplay

        yOffset = yOffset - 24
        local zoneFilterCheck = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        zoneFilterCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, yOffset)
        zoneFilterCheck.Text:SetText("Exclude invalid zones")
        zoneFilterCheck:SetChecked(true)
        self.zoneFilterCheck = zoneFilterCheck

        yOffset = yOffset - 24
        local classFilterCheck = CreateFrame("CheckButton", nil, frame, "InterfaceOptionsCheckButtonTemplate")
        classFilterCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 34, yOffset)
        classFilterCheck.Text:SetText("Enable class filter")
        classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
        classFilterCheck:SetScript("OnClick", function(self)
            if not ns.pSettings then ns.pSettings = {} end
            ns.pSettings.enableClassFilter = self:GetChecked()
            RecruitmentFrame:UpdateClassFilterDisplay()
        end)
        self.classFilterCheck = classFilterCheck

        local classFilterInfo = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        classFilterInfo:SetPoint("LEFT", classFilterCheck.Text, "RIGHT", 10, 0)
        classFilterInfo:SetTextColor(0.8, 0.8, 1)
        self.classFilterInfo = classFilterInfo
    end

    self:UpdateClassFilterDisplay()
    self:UpdateLevelDisplay()
end

function RecruitmentFrame:UpdateClassFilterDisplay()
    if not self.classFilterInfo then return end
    
    if not ns.pSettings or not ns.pSettings.enableClassFilter or not ns.pSettings.classFilter then
        self.classFilterInfo:SetText(self.isCompactMode and "(All)" or "(All classes)")
        self.classFilterInfo:SetTextColor(0.8, 0.8, 1)
        return
    end
    
    local selectedClasses = {}
    for className, enabled in pairs(ns.pSettings.classFilter) do
        if enabled then
            table.insert(selectedClasses, className)
        end
    end
    
    if #selectedClasses == 0 then
        self.classFilterInfo:SetText(self.isCompactMode and "(None)" or "(No classes selected)")
        self.classFilterInfo:SetTextColor(1, 0.5, 0.5)
    else
        local displayText = ""
        if self.isClassScanMode and self.currentClassIndex and self.selectedClassList and 
           self.currentClassIndex <= #self.selectedClassList then
            -- Show current progress
            if self.isCompactMode then
                displayText = self.currentClassIndex .. "/" .. #selectedClasses .. ": " .. 
                             (self.selectedClassList[self.currentClassIndex] or "?")
            else
                displayText = "(" .. self.currentClassIndex .. "/" .. #selectedClasses .. ": " .. 
                             (self.selectedClassList[self.currentClassIndex] or "Unknown") .. ")"
            end
        elseif #selectedClasses > 3 and self.isCompactMode then
            displayText = #selectedClasses .. " classes"
        elseif #selectedClasses > 5 then
            displayText = "(" .. #selectedClasses .. " classes selected)"
        else
            local shortNames = self.isCompactMode and {} or selectedClasses
            if self.isCompactMode then
                for _, class in ipairs(selectedClasses) do
                    table.insert(shortNames, string.sub(class, 1, 4)) -- First 4 chars
                end
            end
            local classList = self.isCompactMode and shortNames or selectedClasses
            displayText = self.isCompactMode and table.concat(classList, ",") or ("(" .. table.concat(classList, ", ") .. ")")
        end
        
        self.classFilterInfo:SetText(displayText)
        self.classFilterInfo:SetTextColor(0.8, 0.8, 1)
    end
end

function RecruitmentFrame:UpdateLevelDisplay()
    if not self.levelDisplay then return end
    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()
    self.levelDisplay:SetText(string.format("%d - %d", minLevel, maxLevel))
    -- print("|cFF3EB9D8[FGR-DEBUG]|r Level display updated to: " .. minLevel .. "-" .. maxLevel)
end

function RecruitmentFrame:RefreshFromSettings()
    if not self.isInitialized then return end
    self:ResetClassScanMode()
    self:UpdateLevelDisplay()
    self:UpdateClassFilterDisplay()

    if self.classFilterCheck then
        self.classFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
    end

    if self.messageDropdown then
        local recruitmentFrameRef = self
        UIDropDownMenu_Initialize(self.messageDropdown, function(dropdown, level)
            local messageList = recruitmentFrameRef:GetMessageList()
            local inviteOnlyInfo = UIDropDownMenu_CreateInfo()
            inviteOnlyInfo.text = "Invite Only (No Message)"
            inviteOnlyInfo.value = "invite_only"
            inviteOnlyInfo.func = function()
                UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "invite_only")
                recruitmentFrameRef.selectedMessage = nil
                recruitmentFrameRef.inviteMode = "invite_only"
            end
            UIDropDownMenu_AddButton(inviteOnlyInfo, level)

            for i, msgData in ipairs(messageList) do
                local inviteAndMsgInfo = UIDropDownMenu_CreateInfo()
                inviteAndMsgInfo.text = "Invite & send message: " .. (msgData.desc or ("Message " .. i))
                inviteAndMsgInfo.value = "invite_and_message_" .. i
                inviteAndMsgInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "invite_and_message_" .. i)
                    recruitmentFrameRef.selectedMessage = msgData
                    recruitmentFrameRef.inviteMode = "invite_and_message"
                end
                UIDropDownMenu_AddButton(inviteAndMsgInfo, level)

                local justMsgInfo = UIDropDownMenu_CreateInfo()
                justMsgInfo.text = "Just send message: " .. (msgData.desc or ("Message " .. i))
                justMsgInfo.value = "just_message_" .. i
                justMsgInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "just_message_" .. i)
                    recruitmentFrameRef.selectedMessage = msgData
                    recruitmentFrameRef.inviteMode = "just_message"
                end
                UIDropDownMenu_AddButton(justMsgInfo, level)
            end
        end)
    end

    if self.sendInviteBtn then
        local im = self.inviteMode
        self.sendInviteBtn:SetShown(im == "invite_only" or im == "invite_and_message" or im == "just_message")
        if im == "just_message" then
            self.sendInviteBtn:SetText("Send Message")
        else
            self.sendInviteBtn:SetText("Send Invite")
        end
    end

    -- print("|cFF3EB9D8[FGR]|r Recruitment frame refreshed from settings")
end

function RecruitmentFrame:CreateMessageSection()
    local frame = self.frame
    local yOffset = -260
    local theme = ns.Theme

    local msgHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    msgHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset)
    msgHeader:SetText("Invite style:")
    if theme then
        local r, g, b = theme:GetColor("accent")
        msgHeader:SetTextColor(r, g, b)
    else
        msgHeader:SetTextColor(0.24, 0.73, 0.85)
    end

    local msgDropdown = CreateFrame("Frame", nil, frame, "UIDropDownMenuTemplate")
    msgDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 140, -300)
    msgDropdown:SetScale(0.85)
    UIDropDownMenu_SetWidth(msgDropdown, 300)

    local recruitmentFrameRef = self
    UIDropDownMenu_Initialize(msgDropdown, function(dropdown, level)
        local messageList = recruitmentFrameRef:GetMessageList()
        local inviteOnlyInfo = UIDropDownMenu_CreateInfo()
        inviteOnlyInfo.text = "Invite Only (No Message)"
        inviteOnlyInfo.value = "invite_only"
        inviteOnlyInfo.func = function()
            UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_only")
            recruitmentFrameRef.selectedMessage = nil
            recruitmentFrameRef.inviteMode = "invite_only"
        end
        UIDropDownMenu_AddButton(inviteOnlyInfo, level)

        for i, msgData in ipairs(messageList) do
            local inviteAndMsgInfo = UIDropDownMenu_CreateInfo()
            inviteAndMsgInfo.text = "Invite & send message: " .. (msgData.desc or ("Message " .. i))
            inviteAndMsgInfo.value = "invite_and_message_" .. i
            inviteAndMsgInfo.func = function()
                UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_and_message_" .. i)
                recruitmentFrameRef.selectedMessage = msgData
                recruitmentFrameRef.inviteMode = "invite_and_message"
            end
            UIDropDownMenu_AddButton(inviteAndMsgInfo, level)

            local justMsgInfo = UIDropDownMenu_CreateInfo()
            justMsgInfo.text = "Just send message: " .. (msgData.desc or ("Message " .. i))
            justMsgInfo.value = "just_message_" .. i
            justMsgInfo.func = function()
                UIDropDownMenu_SetSelectedValue(msgDropdown, "just_message_" .. i)
                recruitmentFrameRef.selectedMessage = msgData
                recruitmentFrameRef.inviteMode = "just_message"
            end
            UIDropDownMenu_AddButton(justMsgInfo, level)
        end
    end)

    UIDropDownMenu_SetSelectedValue(msgDropdown, "invite_only")
    self.messageDropdown = msgDropdown
    self.inviteMode = "invite_only"
end

function RecruitmentFrame:CreatePlayerList()
    local frame = self.frame
    local isCompact = self.isCompactMode
    local yOffset = isCompact and -95 or -280
    local theme = ns.Theme

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)

    if isCompact then
        -- Ultra-compact: Minimal header and buttons
        local listHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        listHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        listHeader:SetText("Players: 0")
        if theme then
            local r, g, b = theme:GetColor("accent")
            listHeader:SetTextColor(r, g, b)
        else
            listHeader:SetTextColor(0.24, 0.73, 0.85)
        end
        self.listHeader = listHeader

        -- Tiny select buttons
        local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        selectAllBtn:SetPoint("LEFT", listHeader, "RIGHT", 10, 0)
        selectAllBtn:SetSize(35, 16)
        selectAllBtn:SetText("All")
        selectAllBtn:SetScript("OnClick", function()
            RecruitmentFrame:SelectAllPlayersButton()
        end)
        self.selectAllBtn = selectAllBtn

        local deselectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 3, 0)
        deselectAllBtn:SetSize(35, 16)
        deselectAllBtn:SetText("None")
        deselectAllBtn:SetScript("OnClick", function()
            RecruitmentFrame:DeselectAllPlayersButton()
        end)
        self.deselectAllBtn = deselectAllBtn

        -- Position scrollFrame for compact mode
        scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset - 20)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35) -- Even more compact - less bottom space
        
    else
        -- Normal mode
        local listHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        listHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        listHeader:SetText("Found Players: 0")
        if theme then
            local r, g, b = theme:GetColor("accent")
            listHeader:SetTextColor(r, g, b)
        else
            listHeader:SetTextColor(0.24, 0.73, 0.85)
        end
        self.listHeader = listHeader

        local selectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        selectAllBtn:SetPoint("LEFT", listHeader, "RIGHT", 20, 0)
        selectAllBtn:SetSize(90, 22)
        selectAllBtn:SetText("Select All")
        selectAllBtn:SetScript("OnClick", function()
            RecruitmentFrame:SelectAllPlayersButton()
        end)
        self.selectAllBtn = selectAllBtn

        local deselectAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 5, 0)
        deselectAllBtn:SetSize(90, 22)
        deselectAllBtn:SetText("Deselect All")
        deselectAllBtn:SetScript("OnClick", function()
            RecruitmentFrame:DeselectAllPlayersButton()
        end)
        self.deselectAllBtn = deselectAllBtn

        -- Position scrollFrame for normal mode
        scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset - 25)
        scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -40, 80)
    end
    
    -- Now scrollFrame is in scope for both modes - set up background
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(scrollFrame)
    if theme then
        local r, g, b, a = theme:GetColor("panel")
        scrollBg:SetColorTexture(r, g, b, a)
    else
        scrollBg:SetColorTexture(0.08, 0.08, 0.12, 0.85)
    end

    local scrollBorder = scrollFrame:CreateTexture(nil, "BORDER")
    scrollBorder:SetAllPoints(scrollFrame)
    if theme then
        local r, g, b, a = theme:GetColor("panelBorder")
        scrollBorder:SetColorTexture(r, g, b, a)
    else
        scrollBorder:SetColorTexture(0.24, 0.73, 0.85, 0.4)
    end
    scrollBg:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 1, -1)
    scrollBg:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -1, 1)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = current - (delta * 20)
        if newScroll < 0 then
            newScroll = 0
        elseif newScroll > maxScroll then
            newScroll = maxScroll
        end
        self:SetVerticalScroll(newScroll)
    end)

    self.playerScrollFrame = scrollFrame
    self.playerScrollChild = scrollChild
end

function RecruitmentFrame:CreateActionButtons()
    local frame = self.frame
    local isCompact = self.isCompactMode
    local theme = ns.Theme

    if isCompact then
        local buttonHeight = 18
        local gap = 2
        
        local sendInviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        sendInviteBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
        sendInviteBtn:SetSize(45, buttonHeight)
        sendInviteBtn:SetText("Invite")
        sendInviteBtn:SetScript("OnClick", function()
            self:SendNextInvite()
        end)
        sendInviteBtn:Hide()
        self.sendInviteBtn = sendInviteBtn
        if theme then theme:StyleButton(sendInviteBtn, true) end

        local blacklistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", gap, 0)
        blacklistBtn:SetSize(40, buttonHeight)
        blacklistBtn:SetText("Block")
        blacklistBtn:SetScript("OnClick", function()
            self:BlacklistSelectedPlayers()
        end)
        blacklistBtn:Hide()
        self.blacklistBtn = blacklistBtn
        if theme then theme:StyleButton(blacklistBtn, false) end

        local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", gap, 0)
        clearBtn:SetSize(35, buttonHeight)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            self:ClearPlayerList()
        end)
        clearBtn:Hide()
        self.clearBtn = clearBtn
        if theme then theme:StyleButton(clearBtn, false) end

        local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        settingsBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
        settingsBtn:SetSize(40, buttonHeight)
        settingsBtn:SetText("⚙️") -- Just gear emoji
        settingsBtn:SetScript("OnClick", function()
            if ns.SettingsManager then
                ns.SettingsManager:OpenSettings()
            end
        end)
        if theme then theme:StyleButton(settingsBtn, false) end
        
    else
        -- Normal mode (keep existing larger buttons)
        local sendInviteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        sendInviteBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 20)
        sendInviteBtn:SetSize(120, 30)
        sendInviteBtn:SetText("Send Invite")
        sendInviteBtn:SetScript("OnClick", function()
            self:SendNextInvite()
        end)
        sendInviteBtn:Hide()
        self.sendInviteBtn = sendInviteBtn
        if theme then theme:StyleButton(sendInviteBtn, true) end

        local blacklistBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        blacklistBtn:SetPoint("LEFT", sendInviteBtn, "RIGHT", 10, 0)
        blacklistBtn:SetSize(120, 30)
        blacklistBtn:SetText("Blacklist Selected")
        blacklistBtn:SetScript("OnClick", function()
            self:BlacklistSelectedPlayers()
        end)
        blacklistBtn:Hide()
        self.blacklistBtn = blacklistBtn
        if theme then theme:StyleButton(blacklistBtn, false) end

        local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        clearBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 10, 0)
        clearBtn:SetSize(80, 30)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            self:ClearPlayerList()
        end)
        clearBtn:Hide()
        self.clearBtn = clearBtn
        if theme then theme:StyleButton(clearBtn, false) end

        local settingsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        settingsBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 20)
        settingsBtn:SetSize(80, 30)
        settingsBtn:SetText("Settings")
        settingsBtn:SetScript("OnClick", function()
            if ns.SettingsManager then
                ns.SettingsManager:OpenSettings()
            end
        end)
        if theme then theme:StyleButton(settingsBtn, false) end
    end
end

function RecruitmentFrame:UpdateActionButtonVisibility()
    local hasPlayers = false
    for _ in pairs(foundPlayers) do hasPlayers = true; break end

    if self.sendInviteBtn then
        local im = self.inviteMode
        self.sendInviteBtn:SetShown(im == "invite_only" or im == "invite_and_message" or im == "just_message")
        if im == "just_message" then
            self.sendInviteBtn:SetText("Send Message")
        else
            self.sendInviteBtn:SetText("Send Invite")
        end

        self:UpdateSendInviteButtonState()
    end

    if self.blacklistBtn then self.blacklistBtn:SetShown(hasPlayers) end
    if self.clearBtn then self.clearBtn:SetShown(hasPlayers) end
end

function RecruitmentFrame:UpdateSendInviteButtonState()
    local enabled = false
    for _ in pairs(selectedPlayers) do enabled = true; break end
    if self.sendInviteBtn then
        self.sendInviteBtn:SetEnabled(enabled)
    end
end

function RecruitmentFrame:SendNextInvite()
    local im = self.inviteMode
    if im ~= "invite_only" and im ~= "invite_and_message" and im ~= "just_message" then
        self:UpdateStatus("Invite mode not selected", "orange")
        return
    end

    -- Find the next selected player as before
    local nextToSend = nil
    for name, data in pairs(selectedPlayers) do
        if not foundPlayers[name] then
            selectedPlayers[name] = nil
        elseif not self:PassesFilters(data) then
            selectedPlayers[name] = nil
        else
            nextToSend = { name = name, data = data }
            break
        end
    end

    if not nextToSend then
        self:UpdateStatus("No valid selected players", "orange")
        self:UpdateSelectionCount()
        self:UpdateActionButtonVisibility()
        return
    end

    selectedPlayers[nextToSend.name] = nil
    foundPlayers[nextToSend.name] = nil

    -- INVITE LOGIC
    if im == "invite_only" then
        GuildInvite(nextToSend.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
        -- print("|cFF3EB9D8[FGR]|r Sent guild invite to: " .. nextToSend.name)

    elseif im == "invite_and_message" then
        GuildInvite(nextToSend.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
        if self.selectedMessage and self.selectedMessage.message then
            local message = self:FormatMessage(self.selectedMessage.message, nextToSend.name)
            self:SendWhisper(message, nextToSend.name)
            -- print("|cFF3EB9D8[FGR]|r Sent guild invite and message to: " .. nextToSend.name)
        end

    elseif im == "just_message" then
        if self.selectedMessage and self.selectedMessage.message then
            local message = self:FormatMessage(self.selectedMessage.message, nextToSend.name)
            self:SendWhisper(message, nextToSend.name)
            self.sessionStats.messagesOnly = (self.sessionStats.messagesOnly or 0) + 1
            -- print("|cFF3EB9D8[FGR]|r Sent message to: " .. nextToSend.name)
        end
    end

    -- Anti-spam
    if not ns.tblAntiSpamList then ns.tblAntiSpamList = {} end
    ns.tblAntiSpamList[string.lower(nextToSend.name)] = {
        name = nextToSend.name,
        time = time()
    }

    self:RefreshPlayerList()
    self:UpdatePlayerCount()
    self:UpdateSessionStats()
    self:UpdateActionButtonVisibility()
end

function RecruitmentFrame:UpdateSendInviteButtonState()
    if self.sendInviteBtn then
        local hasSelection = false
        for _, _ in pairs(selectedPlayers) do
            hasSelection = true
            break
        end
        self.sendInviteBtn:SetEnabled(hasSelection)
    end
end

function RecruitmentFrame:CreateStatusSection()
    local frame = self.frame
    local isCompact = self.isCompactMode
    
    if isCompact then
        -- Ultra-compact: Just status, no stats
        local statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        statusText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 32)
        statusText:SetText("Ready")
        statusText:SetTextColor(0, 1, 0)
        self.statusText = statusText
        
        -- No stats in ultra-compact mode
        self.statsText = nil
        
    else
        -- Normal mode (keep existing)
        local statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        statusText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 50)
        statusText:SetText("Ready")
        statusText:SetTextColor(0, 1, 0)
        self.statusText = statusText
        
        local statsText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        statsText:SetPoint("BOTTOM", statusText, "TOP", 0, 5)
        statsText:SetText("Session: 0 invites sent | 0 players scanned")
        statsText:SetTextColor(0.7, 0.7, 0.7)
        self.statsText = statsText
    end
end

function RecruitmentFrame:StartPlayerScan()
    if not self.scanButton:IsEnabled() then
        return
    end

    if isScanning then
        self:UpdateStatus("Already scanning...", "yellow")
        return
    end

    local currentTime = time()
    if currentTime - lastScanTime < scanCooldown then
        local remaining = scanCooldown - (currentTime - lastScanTime)
        self:UpdateStatus(string.format("Scan cooldown: %d seconds", remaining), "orange")
        return
    end

    if self.isClassScanMode and self.selectedClassList then
        if self._readyForNextClass then
            self.currentClassIndex = (self.currentClassIndex or 1) + 1
            self._readyForNextClass = false
            -- print("|cFF3EB9D8[FGR]|r Manually advancing to class " .. self.currentClassIndex)
        end
    end

    isScanning = true
    lastScanTime = currentTime

    local statusMsg = "Scanning for players"
    if self.isClassScanMode and #self.selectedClassList > 0 then
        local currentClass = self.selectedClassList[self.currentClassIndex or 1]
        statusMsg = "Scanning " .. currentClass .. " (" .. (self.currentClassIndex or 1) .. "/" .. #self.selectedClassList .. ")"
    end
    statusMsg = statusMsg .. "..."

    self:UpdateStatus(statusMsg, "yellow")
    self.scanButton:SetText("Run")
    self.scanButton:SetEnabled(false)
    self:UpdateNextClassIndicator()

    if not self.isClassScanMode or (self.currentClassIndex or 1) == 1 then
        foundPlayers = {}
        selectedPlayers = {}
    end

    self:PerformPlayerScan()
    isScanning = false
    self:StartCooldownTimer()
end

function RecruitmentFrame:PerformPlayerScan()
    selectedPlayers = {}
    self:ScanNearbyPlayers()
end

function RecruitmentFrame:ScanNearbyPlayers()
    foundPlayers = {}
    selectedPlayers = {}
    self:RefreshPlayerList()
    self:UpdatePlayerCount()
    self:UpdateSelectionCount()

    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()

    if ns.pSettings and ns.pSettings.enableClassFilter and ns.pSettings.classFilter then
        if not self.isClassScanMode then
            self:BuildSelectedClassList()
        end

        if #self.selectedClassList == 0 then
            self:UpdateStatus("No classes selected in filter", "orange")
            -- print("|cFF3EB9D8[FGR]|r No classes selected - cannot scan")
            return
        end

        self.isClassScanMode = true
        self.currentClassIndex = self.currentClassIndex or 1
        local currentClass = self.selectedClassList[self.currentClassIndex]
        if not currentClass then
            self:ResetClassScanMode()
            return
        end

        local classQuery = "c-" .. string.lower(currentClass)
        -- print("|cFF3EB9D8[FGR]|r Class scan mode: scanning " .. self.currentClassIndex .. "/" .. #self.selectedClassList .. ": " .. currentClass)
        -- print("|cFF3EB9D8[FGR]|r Executing class query: " .. classQuery)
        self.currentScanClass = currentClass
        self:ExecuteWhoQuery(classQuery, currentClass)

    else
        -- print("|cFF3EB9D8[FGR]|r No class filter, using level-only query")
        self.isClassScanMode = false
        self.currentScanClass = nil
        local levelQuery = string.format("%d-%d", minLevel, maxLevel)
        self:ExecuteWhoQuery(levelQuery)
    end
end

function RecruitmentFrame:BuildSelectedClassList()
    if self.selectedClassList and #self.selectedClassList > 0 then
        return
    end

    self.selectedClassList = {}
    self.currentClassIndex = 1

    if ns.pSettings and ns.pSettings.classFilter then
        for className, enabled in pairs(ns.pSettings.classFilter) do
            if enabled then
                table.insert(self.selectedClassList, className)
            end
        end
    end

    table.sort(self.selectedClassList)
end

function RecruitmentFrame:PassesFilters(player)
    local minLevel = (ns.pSettings and ns.pSettings.minLevel) or 1
    local maxLevel = (ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()
    if player.level < minLevel or player.level > maxLevel then
        return false
    end

    if player.guild and player.guild ~= "" then
        return false
    end

    if player.name == UnitName("player") then
        return false
    end

    local blacklistKey = string.lower(player.name)
    local isBlacklisted = ns.tblBlackList and ns.tblBlackList[blacklistKey]
    if isBlacklisted then
        return false
    end

    local antiSpamKey = string.lower(player.name)
    local antiSpamEntry = ns.tblAntiSpamList and ns.tblAntiSpamList[antiSpamKey]
    if antiSpamEntry and antiSpamEntry.time then
        local daysSince = (time() - antiSpamEntry.time) / 86400
        local maxDays = (ns.gSettings and ns.gSettings.antiSpamDays) or 7
        if daysSince < maxDays then
            return false
        end
    end

    if not self.isClassScanMode and ns.pSettings and ns.pSettings.enableClassFilter and ns.pSettings.classFilter then
        local playerClass = player.class or "Unknown"
        local classAllowed = ns.pSettings.classFilter[playerClass] or ns.pSettings.classFilter[string.upper(playerClass)]
        if not classAllowed then
            return false
        end
    end

    return true
end

function RecruitmentFrame:RefreshPlayerList()
    playerCheckboxes = {}
    for name in pairs(selectedPlayers) do
        if not foundPlayers[name] then
            selectedPlayers[name] = nil
        end
    end
    for i = self.playerScrollChild:GetNumChildren(), 1, -1 do
        local child = select(i, self.playerScrollChild:GetChildren())
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = -5
    local entryHeight = 25

    for playerName, playerData in pairs(foundPlayers) do
        local entry = self:CreatePlayerEntry(playerData, yOffset)
        yOffset = yOffset - entryHeight - 2
    end

    self.playerScrollChild:SetHeight(math.max(100, -yOffset))
    self:UpdateSendInviteButtonState()
    self:UpdateActionButtonVisibility()
end

function RecruitmentFrame:CreatePlayerEntry(playerData, yOffset)
    local classColor = RAID_CLASS_COLORS[playerData.class] or {r=1, g=1, b=1}
    local theme = ns.Theme
    local entry = CreateFrame("Frame", nil, self.playerScrollChild)
    entry:SetPoint("TOPLEFT", self.playerScrollChild, "TOPLEFT", 5, yOffset)
    entry:SetSize(self.playerScrollChild:GetWidth() - 10, 23)

    local bg = entry:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(entry)

    local rowIndex = math.abs(yOffset / 27)
    if theme then
        local r, g, b, a = theme:GetColor("panel")
        if (rowIndex % 2) == 0 then
            bg:SetColorTexture(r, g, b, a)
        else
            bg:SetColorTexture(r * 0.9, g * 0.9, b * 0.9, a)
        end
    else
        if (rowIndex % 2) == 0 then
            bg:SetColorTexture(0.12, 0.12, 0.16, 0.6) -- Slightly lighter
        else
            bg:SetColorTexture(0.08, 0.08, 0.12, 0.6) -- Slightly darker
        end
    end

    local classBorder = entry:CreateTexture(nil, "OVERLAY")
    classBorder:SetPoint("LEFT", entry, "LEFT", 0, 0)
    classBorder:SetSize(2, 23)
    classBorder:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.7)

    local checkbox = CreateFrame("CheckButton", nil, entry, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("LEFT", entry, "LEFT", 8, 0) 
    checkbox:SetSize(20, 20)
    checkbox:SetChecked(selectedPlayers[playerData.name] ~= nil)
    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            selectedPlayers[playerData.name] = playerData
        else
            selectedPlayers[playerData.name] = nil
        end
        RecruitmentFrame:UpdateSelectionCount()
        RecruitmentFrame:UpdateSendInviteButtonState()
    end)

    playerCheckboxes[playerData.name] = checkbox

    local nameFrame = CreateFrame("Frame", nil, entry)
    nameFrame:SetPoint("LEFT", entry, "LEFT", 8, 0) 
    nameFrame:SetSize(110, 20)
    nameFrame:EnableMouse(true)
    
    local nameText = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", nameFrame, "LEFT", 25, 0)
    nameText:SetText(playerData.name)
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    
    nameFrame:SetScript("OnMouseUp", function(self, button)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    end)

    nameFrame:SetScript("OnEnter", function(self)
        RecruitmentFrame:ShowPlayerTooltip(self, playerData)
    end)
    
    nameFrame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    nameFrame:SetScript("OnMouseDown", function(self)
        nameText:SetTextColor(0.8, 0.8, 0.8) 
    end)
    
    nameFrame:SetScript("OnMouseUp", function(self)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    end)

    local rioBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
    rioBtn:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    rioBtn:SetSize(28, 16)
    rioBtn:SetText("RIO")
    rioBtn:SetScript("OnClick", function()
        local url = RecruitmentFrame:BuildRaiderIoUrl(playerData)
        if not url then return end
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(url)
        else
            print(url)
        end
    end)
    if theme then theme:StyleButton(rioBtn, false) end
    
    local levelText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("LEFT", rioBtn, "RIGHT", 10, 0)
    levelText:SetText("Level " .. playerData.level)
    levelText:SetTextColor(0.8, 0.8, 0.8)
    
    local classText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classText:SetPoint("LEFT", levelText, "RIGHT", 15, 0)
    classText:SetText(playerData.class)
    classText:SetTextColor(0.6, 0.8, 1)

    self:UpdateSendInviteButtonState()
    return entry
end


function RecruitmentFrame:GetRaiderIOReference()
    -- Try multiple ways to access RaiderIO
    local RaiderIO = nil
    
    -- Method 1: Try LibStub with different possible names
    if LibStub then
        local possibleNames = {
            "LibRaiderIO-1.0",
            "RaiderIO-1.0", 
            "RaiderIO",
            "LibRaiderIO"
        }
        
        for _, name in ipairs(possibleNames) do
            local success, lib = pcall(LibStub, name, true) -- true = silent
            if success and lib then
                RaiderIO = lib
                -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO via LibStub: " .. name)
                break
            end
        end
    end
    
    -- Method 2: Try global RaiderIO table
    if not RaiderIO and _G.RaiderIO then
        RaiderIO = _G.RaiderIO
        -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO via global table")
    end
    
    -- Method 3: Try addon table
    if not RaiderIO and _G.RaiderIO_DB then
        -- RaiderIO might store its API elsewhere
        for name, addon in pairs(_G) do
            if type(addon) == "table" and name:find("RaiderIO") and addon.ShowTooltip then
                RaiderIO = addon
                -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO via addon scan: " .. name)
                break
            end
        end
    end
    
    return RaiderIO
end

function RecruitmentFrame:ShowPlayerTooltip(frame, playerData)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    
    local classColor = RAID_CLASS_COLORS[playerData.class] or {r=1, g=1, b=1}
    local unitName = playerData.name
    
    -- Handle cross-realm names
    if playerData.realm and playerData.realm ~= GetRealmName() then
        unitName = playerData.name .. "-" .. playerData.realm
    end
    
    -- IMPORTANT: Set the tooltip's unit BEFORE adding lines
    -- This is what RaiderIO looks for
    GameTooltip.unit = unitName
    
    -- Try to set tooltip as if it's a unit tooltip (RaiderIO expects this)
    GameTooltip:SetText(playerData.name, classColor.r, classColor.g, classColor.b)
    GameTooltip:AddLine(string.format("Level %d %s", playerData.level or 0, playerData.class or "Unknown"), 1, 1, 1)
    
    if playerData.race then
        GameTooltip:AddLine(playerData.race, 0.8, 0.8, 1)
    end
    
    if playerData.zone then
        GameTooltip:AddLine("Zone: " .. playerData.zone, 0.8, 0.8, 0.8)
    end
    
    -- Guild info
    if playerData.guild and playerData.guild ~= "" then
        GameTooltip:AddLine("Guild: " .. playerData.guild, 0.7, 0.9, 0.7)
    else
        GameTooltip:AddLine("No Guild", 0.6, 0.6, 0.6)
    end
    
    -- Show the tooltip first
    GameTooltip:Show()
    
    self:EnhanceTooltipWithRaiderIO(playerData, unitName)
    
    GameTooltip:Show()
end


function RecruitmentFrame:CheckPlayerRaiderIOData(unitName, RaiderIO)
    -- Check if RaiderIO has data for this player
    local checkMethods = {
        "GetPlayerProfile",
        "GetProfile", 
        "GetRaidProfile",
        "HasData",
        "GetPlayerData",
        "GetCharacterData"
    }
    -- First, let's discover ALL available methods and properties
    -- print("|cFF00FFFF[FGR-DEBUG]|r === COMPLETE RAIDERIO OBJECT ANALYSIS ===")
    
    local methods = {}
    local properties = {}
    local totalCount = 0
    
    -- Safely iterate through RaiderIO
    local success, error = pcall(function()
        for k, v in pairs(RaiderIO) do
            totalCount = totalCount + 1
            if type(v) == "function" then
                table.insert(methods, k)
                -- print("|cFF00FFFF[FGR-DEBUG]|r METHOD: " .. tostring(k) .. "()")
            elseif type(v) == "table" then
                -- print("|cFF00FFFF[FGR-DEBUG]|r TABLE: " .. tostring(k) .. " [table]")
                table.insert(properties, tostring(k) .. " [table]")
            else
                -- print("|cFF00FFFF[FGR-DEBUG]|r PROPERTY: " .. tostring(k) .. " = " .. tostring(v))
                table.insert(properties, tostring(k) .. " = " .. tostring(v))
            end
        end
    end)
    
    if not success then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Error analyzing RaiderIO object: " .. tostring(error))
        return nil
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r")
    -- print("|cFF00FFFF[FGR-DEBUG]|r SUMMARY:")
    -- print("|cFF00FFFF[FGR-DEBUG]|r Total items: " .. tostring(totalCount))
    -- print("|cFF00FFFF[FGR-DEBUG]|r Methods found: " .. tostring(#methods))
    -- print("|cFF00FFFF[FGR-DEBUG]|r Properties found: " .. tostring(#properties))
    
    if #methods > 0 then
        -- print("|cFF00FFFF[FGR-DEBUG]|r")
        -- print("|cFF00FFFF[FGR-DEBUG]|r ALL AVAILABLE METHODS:")
        for i, method in ipairs(methods) do
            if i <= 20 then -- Limit output to first 20 methods
                -- print("|cFF00FFFF[FGR-DEBUG]|r   - " .. tostring(method) .. "()")
            elseif i == 21 then
                -- print("|cFF00FFFF[FGR-DEBUG]|r   ... and " .. tostring(#methods - 20) .. " more methods")
                break
            end
        end
    end
    
    -- Look for tooltip or raid related methods specifically
    -- print("|cFF00FFFF[FGR-DEBUG]|r")
    -- print("|cFF00FFFF[FGR-DEBUG]|r TOOLTIP/RAID RELATED METHODS:")
    local foundPromising = false
    for _, method in ipairs(methods) do
        local lower = string.lower(tostring(method))
        if lower:find("tooltip") or lower:find("raid") or lower:find("profile") or lower:find("show") then
            -- print("|cFF00FFFF[FGR-DEBUG]|r   *** " .. tostring(method) .. "() - LOOKS PROMISING!")
            foundPromising = true
        end
    end
    
    if not foundPromising then
        -- print("|cFF00FFFF[FGR-DEBUG]|r   No obviously promising methods found")
    end

    for _, methodName in ipairs(checkMethods) do
        if RaiderIO[methodName] and type(RaiderIO[methodName]) == "function" then
            local success, data = pcall(RaiderIO[methodName], unitName)
                -- print("|cFF00FFFF[FGR-DEBUG]|r found method: " .. methodName )
            if success and data then
                -- print("|cFF00FFFF[FGR-DEBUG]|r " .. methodName .. " returned data for " .. unitName)
                 if methodName == "GetRaidProfile" and type(data) == "table" then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Found RAID profile data! Extracting...")
                    self:ExtractAndDisplayRaidProfile(data)
                    return data
                end
                if methodName == "GetProfile" and type(data) == "table" then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Found profile data, extracting...")
                    self:ExtractAndDisplayRaiderIOData(data)
                    return data
                end
                
                if type(data) == "table" then
                    for k, v in pairs(data) do
                        -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": " .. tostring(v))
                    end
                end
                return data
            elseif success then
                -- print("|cFF00FFFF[FGR-DEBUG]|r " .. methodName .. " returned no data for " .. unitName)
            end
        end
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r No data check methods found or no data available")
    return nil
end

function RecruitmentFrame:ExtractAndDisplayRaidProfile(raidProfileData)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Extracting RAID profile data...")
    
    if not raidProfileData then
        -- print("|cFF00FFFF[FGR-DEBUG]|r No raid profile data provided")
        return
    end
    
    -- Debug: Show all keys in the raid profile
    -- print("|cFF00FFFF[FGR-DEBUG]|r Raid profile structure:")
    for k, v in pairs(raidProfileData) do
        if type(v) == "table" then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": [table with " .. count .. " entries]")
        else
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": " .. tostring(v))
        end
    end
    
    -- Add raid progress section to tooltip
    local raidDataFound = false
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Raid Progress:", 0.9, 0.7, 1)
    
    -- Try different possible structures for raid data
    local raidSources = {
        raidProfileData,                    -- Direct raid data
        raidProfileData.raids,              -- raids table
        raidProfileData.raidProfile,        -- nested raidProfile
        raidProfileData.currentRaid,        -- current raid
        raidProfileData.raidProgress,       -- raid progress
    }
    
    for _, source in ipairs(raidSources) do
        if source and type(source) == "table" then
            local foundInSource = self:ProcessRaidDataSource(source, "raid_source")
            if foundInSource then
                raidDataFound = true
                break
            end
        end
    end
    
    -- If no structured raid data found, try to extract any raid-looking data
    if not raidDataFound then
        -- print("|cFF00FFFF[FGR-DEBUG]|r No structured raid data found, scanning for raid-related fields...")
        self:ScanForRaidFields(raidProfileData)
    end
    
    GameTooltip:Show()
end

function RecruitmentFrame:ProcessRaidDataSource(raidData, sourceName)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Processing raid data from " .. sourceName)
    
    local dataFound = false
    
    -- Try to iterate through raid instances
    for raidName, raidInfo in pairs(raidData) do
        if type(raidInfo) == "table" then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Processing raid: " .. raidName)
            
            -- Try different raid progress formats
            local progressText = self:ExtractRaidProgress(raidInfo, raidName)
            
            if progressText then
                GameTooltip:AddLine("  " .. raidName .. ": " .. progressText, 0.8, 0.8, 1)
                -- print("|cFF00FFFF[FGR-DEBUG]|r Added raid progress: " .. raidName .. " - " .. progressText)
                dataFound = true
            end
        end
    end
    
    return dataFound
end

function RecruitmentFrame:ExtractRaidProgress(raidInfo, raidName)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Extracting progress for " .. raidName)
    
    -- Debug raid info structure
    for k, v in pairs(raidInfo) do
        -- print("|cFF00FFFF[FGR-DEBUG]|r     " .. k .. ": " .. tostring(v))
    end
    
    -- Try multiple formats for raid progress
    local progressFormats = {
        -- Format 1: Direct summary
        function()
            if raidInfo.summary then
                return raidInfo.summary
            end
        end,
        
        -- Format 2: Difficulty-based progress (N/H/M)
        function()
            local progress = ""
            if raidInfo.normal then
                if raidInfo.normal.cleared or raidInfo.normal.killed then
                    progress = progress .. "N"
                elseif raidInfo.normal.progress then
                    progress = progress .. "N(" .. raidInfo.normal.progress .. ")"
                end
            end
            if raidInfo.heroic then
                if raidInfo.heroic.cleared or raidInfo.heroic.killed then
                    progress = progress .. "H"
                elseif raidInfo.heroic.progress then
                    progress = progress .. "H(" .. raidInfo.heroic.progress .. ")"
                end
            end
            if raidInfo.mythic then
                if raidInfo.mythic.cleared or raidInfo.mythic.killed then
                    progress = progress .. "M"
                elseif raidInfo.mythic.progress then
                    progress = progress .. "M(" .. raidInfo.mythic.progress .. ")"
                end
            end
            return progress ~= "" and progress or nil
        end,
        
        -- Format 3: Boss count format (8/8, 9/9, etc.)
        function()
            if raidInfo.bossesKilled and raidInfo.totalBosses then
                return raidInfo.bossesKilled .. "/" .. raidInfo.totalBosses
            elseif raidInfo.killed and raidInfo.total then
                return raidInfo.killed .. "/" .. raidInfo.total
            elseif raidInfo.progress and type(raidInfo.progress) == "string" and raidInfo.progress:match("%d+/%d+") then
                return raidInfo.progress
            end
        end,
        
        -- Format 4: Look for any numeric progress
        function()
            for k, v in pairs(raidInfo) do
                if type(v) == "number" and v > 0 and k:lower():find("kill") then
                    return k .. ": " .. v
                end
            end
        end,
        
        -- Format 5: Look for boolean flags
        function()
            if raidInfo.cleared == true then
                return "Cleared"
            elseif raidInfo.completed == true then
                return "Completed"
            end
        end
    }
    
    for i, formatFunc in ipairs(progressFormats) do
        local result = formatFunc()
        if result then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Format " .. i .. " succeeded: " .. result)
            return result
        end
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r No progress format matched for " .. raidName)
    return nil
end

function RecruitmentFrame:ScanForRaidFields(data)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Scanning for any raid-related fields...")
    
    local raidKeywords = {
        "raid", "boss", "progress", "kill", "clear", "defeat",
        "palace", "vault", "sanctum", "sepulcher", "castle", "temple"
    }
    
    for key, value in pairs(data) do
        local keyLower = tostring(key):lower()
        
        -- Check if key contains raid-related words
        for _, keyword in ipairs(raidKeywords) do
            if keyLower:find(keyword) then
                -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid-related field: " .. key)
                
                if type(value) == "table" then
                    -- Try to extract meaningful data from this table
                    local extractedData = self:ProcessRaidDataSource(value, key)
                    if extractedData then
                        return -- Found something useful
                    end
                else
                    -- Simple value, display it
                    GameTooltip:AddLine("  " .. key .. ": " .. tostring(value), 0.7, 0.7, 0.7)
                end
                break
            end
        end
    end
end
function RecruitmentFrame:ExtractAndDisplayRaiderIOData(profileData)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Extracting RaiderIO data from profile...")
    
    if not profileData then
        return
    end
    
    -- DEBUG: Let's see ALL top-level fields in the profile
    -- print("|cFF00FFFF[FGR-DEBUG]|r Full profile structure:")
    for k, v in pairs(profileData) do
        if type(v) == "table" then
            local count = 0
            for _ in pairs(v) do count = count + 1 end
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": [table with " .. count .. " entries]")
        else
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": " .. tostring(v))
        end
    end
    
    -- Add separator line
    GameTooltip:AddLine(" ____________ ")
    
    -- CHECK FOR RAID PROFILE FIRST
    if profileData.raidProfile then
        -- print("|cFF00FFFF[FGR-DEBUG]|r *** FOUND raidProfile! Processing...")
        self:ProcessRaiderIORaidProfile(profileData.raidProfile)
    else
        -- print("|cFF00FFFF[FGR-DEBUG]|r *** NO raidProfile found - player may not have raid data")
    end
    
    -- Extract Mythic+ data
    if profileData.mythicKeystoneProfile then
        local mp = profileData.mythicKeystoneProfile
        -- print("|cFF00FFFF[FGR-DEBUG]|r Processing mythicKeystoneProfile...")
        
        if mp.currentScore and mp.currentScore > 0 then
            GameTooltip:AddLine("RaiderIO Score: " .. mp.currentScore, 1, 0.5, 0)
            -- print("|cFF00FFFF[FGR-DEBUG]|r Added score: " .. mp.currentScore)
        end
        
        if mp.previousScore and mp.previousScore > 0 and mp.previousScore ~= mp.currentScore then
            GameTooltip:AddLine("Previous Season: " .. mp.previousScore, 0.8, 0.6, 0.2)
        end
        
        if mp.maxDungeonLevel and mp.maxDungeonLevel > 0 then
            GameTooltip:AddLine("Highest Key: +" .. mp.maxDungeonLevel, 0.6, 0.9, 0.6)
        end
        
        local dungeonData = mp.sortedDungeons or mp.dungeons
        if dungeonData then
            self:DisplayDungeonData(dungeonData)
        end
    else
        -- print("|cFF00FFFF[FGR-DEBUG]|r No mythicKeystoneProfile found")
    end
    
    GameTooltip:Show()
end

-- NEW: Process RaiderIO raid profile using their format
function RecruitmentFrame:ProcessRaiderIORaidProfile(raidProfile)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Processing RaiderIO raid profile...")
    
    -- Debug the raid profile structure
    for k, v in pairs(raidProfile) do
        if type(v) == "table" then
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": [table with " .. self:GetTableSize(v) .. " entries]")
        else
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": " .. tostring(v))
        end
    end
    
    -- Look for progress data (as seen in RaiderIO source)
    if raidProfile.progress and type(raidProfile.progress) == "table" then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid progress data!")
        
        GameTooltip:AddLine("Raid Progress:", 0.9, 0.7, 1)
        
        for i, progress in ipairs(raidProfile.progress) do
            -- print("|cFF00FFFF[FGR-DEBUG]|r Processing progress entry " .. i)
            
            if progress.raid and progress.killsPerBoss then
                local raidName = progress.raid.shortName or progress.raid.name or "Unknown Raid"
                local difficulty = self:GetRaidDifficultyInfo(progress.difficulty)
                
                -- Count total bosses killed
                local totalKills = 0
                local maxBosses = progress.raid.bossCount or #progress.killsPerBoss
                
                for j, kills in ipairs(progress.killsPerBoss) do
                    if kills > 0 then
                        totalKills = totalKills + 1
                    end
                end
                
                if totalKills > 0 then
                    local progressText = string.format("%s %s: %d/%d", 
                        difficulty.suffix or difficulty.name, 
                        raidName, 
                        totalKills, 
                        maxBosses)
                    
                    local color = difficulty.color or {r = 1, g = 1, b = 1}
                    GameTooltip:AddLine(progressText, color.r, color.g, color.b)
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Added: " .. progressText)
                end
            end
        end
    else
        -- print("|cFF00FFFF[FGR-DEBUG]|r No progress data found in raid profile")
    end
end
function RecruitmentFrame:TryRaidProviderAccess(playerName, realm, region)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Trying raid provider access...")
    
    -- Check for RaiderIO's internal namespace
    local ns = _G.RaiderIO
    if ns and ns.PROVIDER_DATA_TYPE then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO namespace with provider types")
        
        -- Try to access the providers array
        if _G.RaiderIO_DB and _G.RaiderIO_DB.db then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Checking RaiderIO_DB for providers...")
            
            -- Look for raid providers
            local db = _G.RaiderIO_DB.db
            for providerKey, providerData in pairs(db) do
                if type(providerData) == "table" and providerData.region == region then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Found provider: " .. providerKey .. " for region " .. region)
                    
                    -- Check if this provider has raid data
                    if providerKey:lower():find("raid") then
                        -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid provider!")
                        
                        -- Try to find the player in this provider
                        local playerKey = playerName .. "-" .. realm
                        if providerData.lookup and providerData.lookup[playerKey] then
                            -- print("|cFF00FFFF[FGR-DEBUG]|r Found " .. playerKey .. " in raid provider!")
                            
                            local lookupIndex = providerData.lookup[playerKey]
                            if providerData.data and providerData.data[lookupIndex] then
                                local raidData = providerData.data[lookupIndex]
                                -- print("|cFF00FFFF[FGR-DEBUG]|r Extracting raid data from provider...")
                                self:ProcessProviderRaidData(raidData, playerName)
                                return true
                            end
                        end
                    end
                end
            end
        end
    end
    
    return false
end
function RecruitmentFrame:ProcessProviderRaidData(raidData, playerName)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Processing provider raid data for " .. playerName)
    
    -- Debug the structure
    for k, v in pairs(raidData) do
        if type(v) == "table" then
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": [table]")
        else
            -- print("|cFF00FFFF[FGR-DEBUG]|r   " .. k .. ": " .. tostring(v))
        end
    end
    
    GameTooltip:AddLine("Raid Progress:", 0.9, 0.7, 1)
    
    -- Try to extract raid progress in various formats
    if raidData.raids and type(raidData.raids) == "table" then
        for _, raid in ipairs(raidData.raids) do
            local progress = self:ExtractRaidProgressFromProvider(raid)
            if progress then
                GameTooltip:AddLine("  " .. progress, 0.8, 0.8, 1)
                -- print("|cFF00FFFF[FGR-DEBUG]|r Added raid progress: " .. progress)
            end
        end
    end
end

function RecruitmentFrame:ExtractRaidProgressFromProvider(raidInfo)
    if not raidInfo then return nil end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r Extracting progress from raid info:")
    for k, v in pairs(raidInfo) do
        -- print("|cFF00FFFF[FGR-DEBUG]|r     " .. k .. ": " .. tostring(v))
    end
    
    -- Try different progress formats
    local raidName = raidInfo.name or raidInfo.shortName or "Unknown Raid"
    
    -- Format 1: Direct progress numbers
    if raidInfo.normal and type(raidInfo.normal) == "number" then
        return string.format("%s Normal: %d", raidName, raidInfo.normal)
    end
    
    -- Format 2: Kills array
    if raidInfo.kills and type(raidInfo.kills) == "table" then
        local totalKills = 0
        for _, kills in ipairs(raidInfo.kills) do
            totalKills = totalKills + (kills > 0 and 1 or 0)
        end
        local maxBosses = #raidInfo.kills
        return string.format("%s: %d/%d", raidName, totalKills, maxBosses)
    end
    
    return nil
end

function RecruitmentFrame:TriggerRaiderIORaidLoad(playerName, realm, region)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Attempting to trigger RaiderIO raid data load...")
    
    local RaiderIO = self:GetRaiderIOReference()
    if not RaiderIO then return false end
    
    -- Try to call RaiderIO's internal functions to load raid data
    local loadFunctions = {
        "LoadRaidData",
        "RefreshProfile", 
        "UpdateProfile",
        "GetRaidProfile",
    }
    
    for _, funcName in ipairs(loadFunctions) do
        if RaiderIO[funcName] then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Trying " .. funcName .. "...")
            
            local success, result = pcall(RaiderIO[funcName], playerName .. "-" .. realm)
            if not success then
                success, result = pcall(RaiderIO[funcName], playerName, realm)
            end
            
            if success and result then
                -- print("|cFF00FFFF[FGR-DEBUG]|r " .. funcName .. " succeeded!")
                
                -- Try GetProfile again after loading
                local success2, profileData = pcall(RaiderIO.GetProfile, playerName .. "-" .. realm)
                if success2 and profileData and profileData.raidProfile then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Raid profile now available after " .. funcName .. "!")
                    self:ProcessRaiderIORaidProfile(profileData.raidProfile)
                    return true
                end
            end
        end
    end
    
    return false
end

function RecruitmentFrame:CheckRaiderIOInternalData(playerName, realm, region)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Checking RaiderIO internal data structures...")
    
    -- Check various RaiderIO globals for cached data
    local dataSources = {
        _G.RaiderIO_CharacterData,
        _G.RaiderIO_Cache,
        _G.RaiderIO_ProfileCache,
        _G.RaiderIO_Data,
    }
    
    local playerKey = playerName .. "-" .. realm
    
    for i, dataSource in ipairs(dataSources) do
        if dataSource and type(dataSource) == "table" then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Checking data source " .. i)
            
            if dataSource[playerKey] then
                -- print("|cFF00FFFF[FGR-DEBUG]|r Found " .. playerKey .. " in data source " .. i)
                
                local playerData = dataSource[playerKey]
                if playerData.raidProfile or playerData.raids then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid data in cached source!")
                    
                    local raidData = playerData.raidProfile or playerData.raids
                    self:ProcessRaiderIORaidProfile(raidData)
                    return true
                end
            end
            
            -- Also check by region/realm structure
            if dataSource[region] and dataSource[region][realm] and dataSource[region][realm][playerName] then
                local playerData = dataSource[region][realm][playerName]
                if playerData.raidProfile or playerData.raids then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid data in regional cache!")
                    
                    local raidData = playerData.raidProfile or playerData.raids
                    self:ProcessRaiderIORaidProfile(raidData)
                    return true
                end
            end
        end
    end
    
    return false
end



-- Helper function to get raid difficulty info
function RecruitmentFrame:GetRaidDifficultyInfo(difficulty)
    local difficulties = {
        [1] = {name = "LFR", suffix = "L", color = {r = 0.5, g = 1, b = 0.5}},
        [2] = {name = "Normal", suffix = "N", color = {r = 1, g = 1, b = 1}},
        [3] = {name = "Heroic", suffix = "H", color = {r = 0, g = 1, b = 1}},
        [4] = {name = "Mythic", suffix = "M", color = {r = 1, g = 0.5, b = 0}},
    }
    
    return difficulties[difficulty] or {name = "Unknown", suffix = "?", color = {r = 0.7, g = 0.7, b = 0.7}}
end

-- Also check if we can access RaiderIO's provider data directly
function RecruitmentFrame:TryProviderDataAccess(playerName, realm, region)
    -- print("|cFF00FFFF[FGR-DEBUG]|r Attempting provider data access...")
    
    -- Try to access RaiderIO's internal data structures
    if _G.RaiderIO_DB and _G.RaiderIO_DB.providers then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO_DB providers")
        
        for i, provider in ipairs(_G.RaiderIO_DB.providers) do
            if provider.region == region and provider.data and provider.data == "Raid" then
                -- print("|cFF00FFFF[FGR-DEBUG]|r Found raid provider for region " .. region)
                
                -- Try to access the provider's lookup data
                if provider.lookup and provider.db then
                    local lookupKey = playerName .. "-" .. realm
                    if provider.lookup[lookupKey] then
                        -- print("|cFF00FFFF[FGR-DEBUG]|r Found player in raid provider lookup!")
                        -- Try to extract raid data from provider.db
                        return true
                    end
                end
            end
        end
    end
    
    return false
end

function RecruitmentFrame:DisplayDungeonData(dungeonData)
    if not dungeonData or type(dungeonData) ~= "table" then
        return
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r DisplayDungeonData called")
    
    local dungeonCount = 0
    for _ in pairs(dungeonData) do dungeonCount = dungeonCount + 1 end
    
    local runsDisplayed = 0
    
    -- dungeonData might be an array or a keyed table
    for key, dungeon in pairs(dungeonData) do
        if runsDisplayed >= 8 then break end -- Show up to 8 dungeons
        
        if type(dungeon) == "table" then
            
            local dungeonName = "Unknown"
            local level = 0
            local timed = nil
            local score = 0
            
            -- Extract level from top level
            level = dungeon.level or dungeon.keystoneLevel or dungeon.mythicLevel or 0
            
            -- Extract timing info - chests > 0 usually means timed
            if dungeon.chests then
                timed = dungeon.chests > 0
            elseif dungeon.fractionalTime then
                timed = dungeon.fractionalTime > 0
            end
            
            -- Extract dungeon name from nested dungeon table
            if dungeon.dungeon and type(dungeon.dungeon) == "table" then
                local nestedDungeon = dungeon.dungeon
                
                -- Try various name fields in the nested table
                dungeonName = nestedDungeon.name or 
                            nestedDungeon.shortName or 
                            nestedDungeon.short_name or
                            nestedDungeon.slug or
                            nestedDungeon.displayName or
                            nestedDungeon.zone or
                            dungeonName
                            
                -- If still unknown, try to extract from sortOrder or other fields
                if dungeonName == "Unknown" and dungeon.sortOrder then
                    -- sortOrder might be something like "92-98-HOA" where HOA is abbreviation
                    local sortParts = {strsplit("-", dungeon.sortOrder)}
                    if sortParts[3] then
                        local abbrev = sortParts[3]
                        dungeonName = self:GetDungeonNameFromAbbreviation(abbrev)
                    end
                end
            end
            
            -- Extract score if available
            score = dungeon.score or dungeon.points or 0
            
            if level > 0 then
                local levelColor = self:GetKeystoneLevelColor(level)
                local timedText = ""
                
                if timed == true then
                    timedText = " (Timed)"
                elseif timed == false then
                    timedText = " (Untimed)"
                end
                
                local scoreText = score > 0 and (" (" .. score .. ")") or ""
                local runText = string.format("%s +%d%s%s", dungeonName, level, timedText, scoreText)
                
                GameTooltip:AddLine(runText, levelColor.r, levelColor.g, levelColor.b)
                runsDisplayed = runsDisplayed + 1
            end
        end
    end
    
    if runsDisplayed == 0 then
        -- print("|cFF00FFFF[FGR-DEBUG]|r No dungeon runs could be displayed")
    else
        -- print("|cFF00FFFF[FGR-DEBUG]|r Displayed " .. runsDisplayed .. " dungeon runs")
    end
end

-- Also let's create a mapping for common dungeon abbreviations
function RecruitmentFrame:GetDungeonNameFromAbbreviation(abbrev)
    local dungeonMap = {
        ["HOA"] = "Halls of Atonement",
        ["PF"] = "Plaguefall",
        ["MOTS"] = "Mists of Tirna Scithe", 
        ["DOS"] = "De Other Side",
        ["SOA"] = "Spires of Ascension",
        ["TOP"] = "Theater of Pain",
        ["NW"] = "Necrotic Wake",
        ["SD"] = "Sanguine Depths",
        ["COT"] = "Court of Stars",
        ["LOWR"] = "Lower Karazhan",
        ["UPPR"] = "Upper Karazhan",
        ["COT"] = "Cathedral of Eternal Night",
        -- Add more as needed
    }
    
    return dungeonMap[abbrev] or abbrev
end


function RecruitmentFrame:GetTableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end


function RecruitmentFrame:EnhanceTooltipWithRaiderIO(playerData, unitName)
    local RaiderIO = self:GetRaiderIOReference()
    
    if not RaiderIO then
        -- print("|cFF00FFFF[FGR-DEBUG]|r RaiderIO not found")
        return
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r RaiderIO detected, attempting tooltip enhancement for: " .. unitName)
    
    -- First, try to get and display data manually
    local profileData = self:CheckPlayerRaiderIOData(unitName, RaiderIO)
    
    if profileData then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Profile data found, manual extraction complete")
        return true
    end
    
    -- Fallback: Try the standard ShowTooltip method
    if RaiderIO.ShowTooltip then
        local beforeLines = GameTooltip:NumLines()
        local success, result = pcall(RaiderIO.ShowTooltip, GameTooltip, unitName)
        local afterLines = GameTooltip:NumLines()
        
        -- print("|cFF00FFFF[FGR-DEBUG]|r Before: " .. beforeLines .. " lines, After: " .. afterLines .. " lines")
        
        if success and afterLines > beforeLines then
            -- print("|cFF00FFFF[FGR-DEBUG]|r RaiderIO.ShowTooltip added " .. (afterLines - beforeLines) .. " lines")
            GameTooltip:Show()
            return true
        end
    end
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r No RaiderIO data could be displayed")
    return false
end



function RecruitmentFrame:TryDirectRaiderIOInsertion(unitName, RaiderIO)
    -- Try to get RaiderIO data directly and add it manually
    
    -- Look for data in RaiderIO's database
    if RaiderIO_DB then
        -- print("|cFF00FFFF[FGR-DEBUG]|r Checking RaiderIO_DB for player data")
        
        -- RaiderIO stores data by realm and character name
        local playerName = unitName
        local realm = GetRealmName()
        
        if unitName:find("-") then
            local name, realmName = unitName:match("([^-]+)-(.+)")
            if name and realmName then
                playerName = name
                realm = realmName
            end
        end
        
        -- Try to find the player in RaiderIO's database
        if RaiderIO_DB.characters and RaiderIO_DB.characters[realm] and RaiderIO_DB.characters[realm][playerName] then
            local charData = RaiderIO_DB.characters[realm][playerName]
            -- print("|cFF00FFFF[FGR-DEBUG]|r Found player data in RaiderIO_DB")
            self:AddRaiderIODataManually(charData)
            return true
        else
            -- print("|cFF00FFFF[FGR-DEBUG]|r No player data found in RaiderIO_DB for " .. playerName .. " on " .. realm)
        end
    end
    
    return false
end

function RecruitmentFrame:AddRaiderIODataManually(charData)
    GameTooltip:AddLine(" ") -- Empty line
    
    -- Add Mythic+ score if available
    if charData.mythicKeystoneProfile then
        local mp = charData.mythicKeystoneProfile
        if mp.currentScore and mp.currentScore > 0 then
            GameTooltip:AddLine("Mythic+ Score: " .. mp.currentScore, 1, 0.5, 0)
        end
        
        -- Add best runs
        if mp.bestRuns then
            for i, run in ipairs(mp.bestRuns) do
                if i <= 3 and run.dungeon and run.mythicLevel then -- Show top 3
                    local levelColor = self:GetKeystoneLevelColor(run.mythicLevel)
                    GameTooltip:AddLine(
                        string.format("%s +%d (%s)", 
                            run.dungeon.short_name or run.dungeon.name, 
                            run.mythicLevel,
                            run.affixes and #run.affixes > 0 and "timed" or "completed"
                        ), 
                        levelColor.r, levelColor.g, levelColor.b
                    )
                end
            end
        end
    end
    
    -- Add raid progress if available
    if charData.raidProfile then
        local rp = charData.raidProfile
        for raidName, raidData in pairs(rp) do
            if raidData.summary then
                GameTooltip:AddLine(
                    string.format("%s: %s", raidName, raidData.summary),
                    0.8, 0.8, 1
                )
            end
        end
    end
    
    GameTooltip:Show()
end

function RecruitmentFrame:GetKeystoneLevelColor(level)
    if level >= 15 then
        return {r = 1, g = 0.5, b = 0} -- Orange for high keys
    elseif level >= 10 then
        return {r = 0.64, g = 0.21, b = 0.93} -- Purple for medium keys  
    else
        return {r = 0.2, g = 1, b = 0.2} -- Green for lower keys
    end
end

-- Also add a debug command to test with specific players
SLASH_FGRRIOTEST1 = "/riotest"
SlashCmdList["FGRRIOTEST"] = function(msg)
    local playerName = msg ~= "" and msg or UnitName("player")
    
    -- print("|cFF00FFFF[FGR-DEBUG]|r Testing RaiderIO integration for: " .. playerName)
    
    -- Simulate tooltip setup
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:SetText(playerName, 1, 1, 1)
    GameTooltip.unit = playerName
    
    RecruitmentFrame:EnhanceTooltipWithRaiderIO({name = playerName}, playerName)
    
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Test tooltip - close with ESC", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- Alternative: Try hooking into RaiderIO's own tooltip system
function RecruitmentFrame:SetupRaiderIOHooks()
    local RaiderIO = self:GetRaiderIOReference()
    if not RaiderIO then return end
    
    -- Look for RaiderIO's tooltip enhancement functions
    if RaiderIO.modules and RaiderIO.modules.tooltip then
        local tooltipModule = RaiderIO.modules.tooltip
        if tooltipModule.AddTooltipInfo then
            -- print("|cFF00FFFF[FGR-DEBUG]|r Found RaiderIO tooltip module")
            
            -- We could potentially hook this or call it directly
            local originalAddInfo = tooltipModule.AddTooltipInfo
            tooltipModule.AddTooltipInfo = function(tooltip, unit, ...)
                local result = originalAddInfo(tooltip, unit, ...)
                if tooltip == GameTooltip then
                    -- print("|cFF00FFFF[FGR-DEBUG]|r RaiderIO added tooltip info for: " .. tostring(unit))
                end
                return result
            end
        end
    end
end

function RecruitmentFrame:ProcessInviteQueue(inviteQueue)
    if #inviteQueue == 0 then
        self:UpdateStatus("All invites processed", "green")
        self:UpdateSessionStats()
        return
    end

    local player = table.remove(inviteQueue, 1)

    if self.inviteMode == "invite_only" then
        GuildInvite(player.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
        -- print("|cFF3EB9D8[FGR]|r Sent guild invite to: " .. player.name)
    elseif self.inviteMode == "invite_and_message" then
        GuildInvite(player.name)
        self.sessionStats.invitesSent = (self.sessionStats.invitesSent or 0) + 1
        if self.selectedMessage and self.selectedMessage.message then
            local message = self:FormatMessage(self.selectedMessage.message, player.name)
            self:SendWhisper(message, player.name)
            -- print("|cFF3EB9D8[FGR]|r Sent guild invite and message to: " .. player.name)
        end
    elseif self.inviteMode == "just_message" then
        if self.selectedMessage and self.selectedMessage.message then
            local message = self:FormatMessage(self.selectedMessage.message, player.name)
            self:SendWhisper(message, player.name)
            self.sessionStats.messagesOnly = (self.sessionStats.messagesOnly or 0) + 1
            -- print("|cFF3EB9D8[FGR]|r Sent message to: " .. player.name)
        end
    end

    if not ns.tblAntiSpamList then ns.tblAntiSpamList = {} end
    ns.tblAntiSpamList[string.lower(player.name)] = {
        name = player.name,
        time = time()
    }

    foundPlayers[player.name] = nil
    selectedPlayers[player.name] = nil
    self:UpdateSessionStats()
    local delay = tonumber((ns.g and ns.g.timeBetweenMessages) or "0.2")
    C_Timer.After(delay, function()
        self:ProcessInviteQueue(inviteQueue)
    end)
    self:RefreshPlayerList()
    self:UpdatePlayerCount()
end

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
        if not clubID and ns.guild and ns.guild.info then
            clubID = ns.guild.info.clubID
        end
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
    -- print("|cFF3EB9D8[FGR-DEBUG]|r Formatted message: " .. formattedMessage)
    -- print("|cFF3EB9D8[FGR-DEBUG]|r Guild link used: " .. guildLink)
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
            local guildLink = "|cffffd200|HclubFinder:" .. club.clubFinderGUID .. "|h[" .. club.name .. "]|h|r"
            ns.guildInfo.guildLink = guildLink
            ns.guild.info.guildLink = guildLink
            -- print("|cFF3EB9D8[FGR]|r Guild link created: " .. guildLink)
        else
            C_Timer.After(2, function()
                self:EnsureGuildLink()
            end)
        end
    end
end

function RecruitmentFrame:BlacklistSelectedPlayers()
    local count = 0
    for _ in pairs(selectedPlayers) do count = count + 1 end
    if count == 0 then
        self:UpdateStatus("No players selected", "orange")
        return
    end
    if not ns.tblBlackList then ns.tblBlackList = {} end

    for name, data in pairs(selectedPlayers) do
        local key = string.lower(name)
        ns.tblBlackList[key] = {
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

function RecruitmentFrame:UpdatePlayerCount()
    local count = 0
    for _ in pairs(foundPlayers) do count = count + 1 end
    if self.listHeader then
        self.listHeader:SetText("Found Players: " .. count)
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
    if color == "red" then
        self.statusText:SetTextColor(1, 0, 0)
    elseif color == "yellow" or color == "orange" then
        self.statusText:SetTextColor(1, 1, 0)
    elseif color == "green" then
        self.statusText:SetTextColor(0, 1, 0)
    else
        self.statusText:SetTextColor(1, 1, 1)
    end
end

function RecruitmentFrame:StartCooldownTimer()
    local function updateCooldown()
        if not self.cooldownText or not self.scanButton then return end
        local currentTime = time()
        local remaining = scanCooldown - (currentTime - lastScanTime)
        if remaining > 0 then
            self.scanButton:SetEnabled(false)
            self.scanButton:SetText("Run")
            self.cooldownText:SetText(string.format("Next scan available in: %d seconds", math.ceil(remaining)))
            self:UpdateNextClassIndicator()
            C_Timer.After(1, updateCooldown)
        else
            self.scanButton:SetEnabled(true)
            self.cooldownText:SetText("")
            self.scanButton:SetText("Run")
            if self.isClassScanMode and self.selectedClassList and #self.selectedClassList > 0 then
                local nextIndex = (self.currentClassIndex or 1) + 1
                if nextIndex > #self.selectedClassList then
                    self:ResetClassScanMode()
                end
            end
            self:UpdateNextClassIndicator()
            self:UpdateClassFilterDisplay()
        end
    end
    updateCooldown()
end

function RecruitmentFrame:ResetClassScanMode()
    self.isClassScanMode = false
    self.currentClassIndex = 1
    self.selectedClassList = {}
    self.currentScanClass = nil
    -- print("|cFF3EB9D8[FGR]|r Class scan mode reset")
end

function RecruitmentFrame:RefreshUI()
    if not self.isInitialized then return end
    self:UpdateLevelDisplay()
    self:UpdateSessionStats()
    self:UpdateClassFilterDisplay()
    self:UpdateNextClassIndicator()
    if self.messageDropdown then
        local recruitmentFrameRef = self
        UIDropDownMenu_Initialize(self.messageDropdown, function(dropdown, level)
            local messageList = recruitmentFrameRef:GetMessageList()
            local inviteOnlyInfo = UIDropDownMenu_CreateInfo()
            inviteOnlyInfo.text = "Invite Only (No Message)"
            inviteOnlyInfo.value = "invite_only"
            inviteOnlyInfo.func = function()
                UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "invite_only")
                recruitmentFrameRef.selectedMessage = nil
                recruitmentFrameRef.inviteMode = "invite_only"
            end
            UIDropDownMenu_AddButton(inviteOnlyInfo, level)
            for i, msgData in ipairs(messageList) do
                local inviteAndMsgInfo = UIDropDownMenu_CreateInfo()
                inviteAndMsgInfo.text = "Invite & send message: " .. (msgData.desc or ("Message " .. i))
                inviteAndMsgInfo.value = "invite_and_message_" .. i
                inviteAndMsgInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "invite_and_message_" .. i)
                    recruitmentFrameRef.selectedMessage = msgData
                    recruitmentFrameRef.inviteMode = "invite_and_message"
                end
                UIDropDownMenu_AddButton(inviteAndMsgInfo, level)
                local justMsgInfo = UIDropDownMenu_CreateInfo()
                justMsgInfo.text = "Just send message: " .. (msgData.desc or ("Message " .. i))
                justMsgInfo.value = "just_message_" .. i
                justMsgInfo.func = function()
                    UIDropDownMenu_SetSelectedValue(recruitmentFrameRef.messageDropdown, "just_message_" .. i)
                    recruitmentFrameRef.selectedMessage = msgData
                    recruitmentFrameRef.inviteMode = "just_message"
                end
                UIDropDownMenu_AddButton(justMsgInfo, level)
            end
        end)
    end
    self:UpdatePlayerCount()
    self:UpdateSelectionCount()

    if self.sendInviteBtn then
        local im = self.inviteMode
        self.sendInviteBtn:SetShown(im == "invite_only" or im == "invite_and_message" or im == "just_message")
        if im == "just_message" then
            self.sendInviteBtn:SetText("Send Message")
        else
            self.sendInviteBtn:SetText("Send Invite")
        end
    end
end

function RecruitmentFrame:UpdateSessionStats()
    if not self.statsText then return end
    local invites = self.sessionStats.invitesSent or 0
    local scanned = self.sessionStats.playersScanned or 0
    local messagesOnly = self.sessionStats.messagesOnly or 0
    local statsText = string.format("Session: %d invites sent | %d messages sent | %d players scanned", 
                                   invites, messagesOnly, scanned)
    self.statsText:SetText(statsText)
end

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
    self.sessionStats = {
        invitesSent = 0,
        playersScanned = 0,
        messagesOnly = 0
    }
    isScanning = false
    lastScanTime = 0
    if not ns.guild then
        ns.guild = { data = { messageList = {} } }
    end
    if not ns.guild.data then
        ns.guild.data = { messageList = {} }
    end
    if not ns.guild.data.messageList then
        ns.guild.data.messageList = {}
    end
    self:EnsureGuildLink()
      C_Timer.After(3, function()
        self:SetupRaiderIOHooks()
    end)
    -- print("[FGR] RecruitmentFrame module initialized")
end

function RecruitmentFrame:SelectAllPlayersButton()
    for name, data in pairs(foundPlayers) do
        selectedPlayers[name] = data
        if playerCheckboxes[name] then
            playerCheckboxes[name]:SetChecked(true)
        end
    end
    self:UpdateSelectionCount()
    self:UpdateSendInviteButtonState()
end

function RecruitmentFrame:DeselectAllPlayersButton()
    for name, data in pairs(foundPlayers) do
        selectedPlayers[name] = nil
        if playerCheckboxes[name] then
            playerCheckboxes[name]:SetChecked(false)
        end
    end
    self:UpdateSelectionCount()
    self:UpdateSendInviteButtonState()
end

RecruitmentFrame:Initialize()