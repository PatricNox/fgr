-- Modules/UI/Settings/SettingsManager.lua
local addonName, ns = ...

ns.SettingsManager = {}
local SettingsManager = ns.SettingsManager

SettingsManager.isInitialized = false
SettingsManager.currentTab = "general"

-- Tab definitions
local TABS = {
    {id = "general", name = "General", order = 1},
    {id = "recruitment", name = "Recruitment", order = 2},
    {id = "messages", name = "Messages", order = 3},
    {id = "blacklist", name = "Blacklist", order = 4},
    {id = "antispam", name = "Anti-Spam", order = 5},
    {id = "zones", name = "Zones", order = 6},
    {id = "about", name = "About", order = 7},
}

function SettingsManager:Initialize()
    if self.isInitialized then return end
    
    print("|cFF3EB9D8[FGR]|r Initializing enhanced settings...")
    
    self:CreateTabbedSettingsFrame()
    
    -- Register with WindowManager immediately after frame creation
    if ns.WindowManager and self.settingsFrame then
        ns.WindowManager:RegisterWindow(
            "settings",
            self.settingsFrame,
            function() 
                self.settingsFrame:Show()
                -- Reload the current tab content since it was cleaned up when closed
                if self.currentTab then
                    self:ShowTab(self.currentTab)
                else
                    self:ShowTab("general")
                end
            end,
            function() 
                self:CleanupAndHide()
            end
        )
    end
    
    self.isInitialized = true
    print("|cFF3EB9D8[FGR]|r Enhanced settings initialized")
end

function SettingsManager:CreateTabbedSettingsFrame()
    -- Create main settings frame
    local frame = CreateFrame("Frame", "FGRSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    
    frame:SetSize(700, 600)
    frame:SetPoint("LEFT", UIParent, "LEFT", 50, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("Fast Guild Recruiter Settings")

    if ns.Theme then
        ns.Theme:ApplyFrame(frame, "Fast Guild Recruiter Settings")
    end
    
    -- Create tab system
    self:CreateTabs(frame)
    
    -- Create content area - use the main frame instead of InsetBg
    frame.contentFrame = CreateFrame("Frame", nil, frame)
    frame.contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -80) -- Leave space for tabs and title
    frame.contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)

    if ns.Theme and not frame.contentFrame.fgrBg then
        local r, g, b, a = ns.Theme:GetColor("panel")
        local bg = frame.contentFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(frame.contentFrame)
        bg:SetColorTexture(r, g, b, a * 0.7)
        frame.contentFrame.fgrBg = bg
    end
    
    -- Create a simple scroll frame without template
    frame.scrollFrame = CreateFrame("ScrollFrame", nil, frame.contentFrame)
    frame.scrollFrame:SetAllPoints(frame.contentFrame)
    frame.scrollFrame:EnableMouse(true)
    frame.scrollFrame:EnableMouseWheel(true)
    
    -- Create scroll child
    frame.scrollChild = CreateFrame("Frame", nil, frame.scrollFrame)
    frame.scrollChild:SetSize(frame.scrollFrame:GetWidth() - 20, 1000)
    frame.scrollFrame:SetScrollChild(frame.scrollChild)
    
    -- Set up mouse wheel scrolling
    frame.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
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

    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function()
            SettingsManager:CleanupAndHide()
        end)
    end
    
    self.settingsFrame = frame
    
    -- Load initial tab
    self:ShowTab("general")
end

function SettingsManager:CleanupAndHide()
    if self.settingsFrame then
        -- Get the CURRENT scroll child from the scroll frame
        local currentScrollChild = self.settingsFrame.scrollFrame:GetScrollChild()
        
        if currentScrollChild then
            local children = {}
            for i = 1, currentScrollChild:GetNumChildren() do
                children[i] = select(i, currentScrollChild:GetChildren())
            end
            
            for i = 1, #children do
                if children[i] then
                    children[i]:Hide()
                    children[i]:ClearAllPoints()
                    children[i]:SetParent(nil)
                end
            end
            
            -- Also hide and clear the scroll child itself
            currentScrollChild:Hide()
            currentScrollChild:ClearAllPoints()
        end
        
        -- Also clean up any orphaned scroll children that might still exist
        if self.settingsFrame.scrollChild and self.settingsFrame.scrollChild ~= currentScrollChild then
            local oldScrollChild = self.settingsFrame.scrollChild
            local oldChildren = {}
            for i = 1, oldScrollChild:GetNumChildren() do
                oldChildren[i] = select(i, oldScrollChild:GetChildren())
            end
            
            for i = 1, #oldChildren do
                if oldChildren[i] then
                    oldChildren[i]:Hide()
                    oldChildren[i]:ClearAllPoints()
                    oldChildren[i]:SetParent(nil)
                end
            end
            oldScrollChild:Hide()
        end
        
        -- Reset scroll position
        self.settingsFrame.scrollFrame:SetVerticalScroll(0)
        
        -- Hide the frame
        self.settingsFrame:Hide()
    end
end

function SettingsManager:CreateTabs(frame)
    frame.tabs = {}
    local tabWidth = 80
    local tabHeight = 25
    local xOffset = 20
    local theme = ns.Theme
    
    for i, tabData in ipairs(TABS) do
        -- Create a simple button
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(tabWidth, tabHeight)
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, -50) -- Position below title
        
        -- Create background texture manually
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tab)
        if theme then
            local r, g, b = theme:GetColor("panel")
            bg:SetColorTexture(r, g, b, 0.6)
        else
            bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        end
        tab.bg = bg
        
        -- Create text
        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        text:SetText(tabData.name)
        tab.text = text
        
        tab.tabId = tabData.id
        tab.isSelected = false
        
        -- Set up tab functionality
        tab:SetScript("OnClick", function(self)
            SettingsManager:ShowTab(self.tabId)
        end)
        
        -- Hover effects
        tab:SetScript("OnEnter", function(self)
            if not self.isSelected then
                if theme then
                    local r, g, b, a = theme:GetColor("accentSoft")
                    self.bg:SetColorTexture(r, g, b, a)
                    self.text:SetTextColor(1, 1, 1)
                else
                    self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
                    self.text:SetTextColor(1, 1, 1)
                end
            end
        end)
        
        tab:SetScript("OnLeave", function(self)
            if not self.isSelected then
                if theme then
                    theme:StyleTab(self, false)
                else
                    self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                    self.text:SetTextColor(0.7, 0.7, 0.7)
                end
            end
        end)
        
        frame.tabs[tabData.id] = tab
        xOffset = xOffset + tabWidth + 5
    end
    
    -- Set first tab as selected
    if frame.tabs["general"] then
        local firstTab = frame.tabs["general"]
        firstTab.isSelected = true
        if theme then
            theme:StyleTab(firstTab, true)
        else
            firstTab.bg:SetColorTexture(0.24, 0.73, 0.85, 0.8) -- Blue background for selected
            firstTab.text:SetTextColor(1, 1, 1) -- White text for selected
        end
    end
    
    -- Set initial colors for unselected tabs
    for id, tab in pairs(frame.tabs) do
        if not tab.isSelected then
            if theme then
                theme:StyleTab(tab, false)
            else
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end
    end
end

function SettingsManager:ShowTab(tabId)
    if not self.settingsFrame then return end
    local theme = ns.Theme
    
    -- Update tab selection
    for id, tab in pairs(self.settingsFrame.tabs) do
        if id == tabId then
            tab.isSelected = true
            if theme then
                theme:StyleTab(tab, true)
            else
                tab.bg:SetColorTexture(0.24, 0.73, 0.85, 0.8)
                tab.text:SetTextColor(1, 1, 1)
            end
        else
            tab.isSelected = false
            if theme then
                theme:StyleTab(tab, false)
            else
                tab.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end
    end
    
    self.currentTab = tabId
    
    -- Clean up existing content more thoroughly
    local currentScrollChild = self.settingsFrame.scrollFrame:GetScrollChild()
    if currentScrollChild then
        -- Clean up current scroll child
        local children = {}
        for i = 1, currentScrollChild:GetNumChildren() do
            children[i] = select(i, currentScrollChild:GetChildren())
        end
        
        for i = 1, #children do
            if children[i] then
                children[i]:Hide()
                children[i]:ClearAllPoints()
                children[i]:SetParent(nil)
            end
        end
        
        -- Hide the old scroll child
        currentScrollChild:Hide()
    end
    
    -- Create a completely new scroll child
    local newScrollChild = CreateFrame("Frame", nil, self.settingsFrame.scrollFrame)
    newScrollChild:SetSize(self.settingsFrame.scrollFrame:GetWidth() - 20, 1000)
    self.settingsFrame.scrollFrame:SetScrollChild(newScrollChild)
    
    -- Update our reference
    self.settingsFrame.scrollChild = newScrollChild
    
    -- Reset scroll position
    self.settingsFrame.scrollFrame:SetVerticalScroll(0)
    
    -- Load tab content
    if tabId == "general" then
        self:CreateGeneralTab(newScrollChild)
    elseif tabId == "recruitment" then
        self:CreateRecruitmentTab(newScrollChild)
    elseif tabId == "messages" then
        self:CreateMessagesTab(newScrollChild)
    elseif tabId == "blacklist" then
        self:CreateBlacklistTab(newScrollChild)
    elseif tabId == "antispam" then
        self:CreateAntiSpamTab(newScrollChild)
    elseif tabId == "zones" then
        self:CreateZonesTab(newScrollChild)
    elseif tabId == "about" then
        self:CreateAboutTab(newScrollChild)
    end
end

function SettingsManager:CreateGeneralTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    -- Header
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("General Settings")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 30
    
    -- Notes
    local guildWideNote = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    guildWideNote:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    guildWideNote:SetText("• |cFFFFFF00Guild-wide settings (affects all guild members)|r")
    yOffset = yOffset - 15
    
    local accountWideNote = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    accountWideNote:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    accountWideNote:SetText("• |cFF00FF00Account-wide settings (affects this character only)|r")
    yOffset = yOffset - 40
    
    -- Show What's New
    local whatsNewLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    whatsNewLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    whatsNewLabel:SetText("• Show What's New:")
    
    local whatsNewCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    whatsNewCheck:SetPoint("LEFT", whatsNewLabel, "RIGHT", 10, 0)
    whatsNewCheck.Text:SetText("Show update notifications")
    whatsNewCheck:SetChecked((ns.g and ns.g.showWhatsNew) or false)
    whatsNewCheck:SetScript("OnClick", function(self)
        if not ns.g then ns.g = {} end
        ns.g.showWhatsNew = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r What's New: " .. (ns.g.showWhatsNew and "ON" or "OFF"))
    end)
    yOffset = yOffset - 30
    
    -- Invite & Scan Settings Header
    local inviteHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    inviteHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    inviteHeader:SetText("Invite & Scan Settings:")
    inviteHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 30
    
    -- Auto Sync
    local autoSyncLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    autoSyncLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    autoSyncLabel:SetText("• Enable Auto Sync:")
    
    local autoSyncCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    autoSyncCheck:SetPoint("LEFT", autoSyncLabel, "RIGHT", 10, 0)
    autoSyncCheck.Text:SetText("Auto sync guild data")
    autoSyncCheck:SetChecked((ns.pSettings and ns.pSettings.enableAutoSync) or false)
    autoSyncCheck:SetScript("OnClick", function(self)
        if not ns.pSettings then ns.pSettings = {} end
        ns.pSettings.enableAutoSync = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r Auto Sync: " .. (ns.pSettings.enableAutoSync and "ON" or "OFF"))
    end)
    yOffset = yOffset - 30
    
    -- Performance Settings Header
    local perfHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    perfHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    perfHeader:SetText("Performance Settings:")
    perfHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 30
    
    -- Message Send Delay
    local delayLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    delayLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    delayLabel:SetText("• Message Send Delay:")
    
    local delaySlider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    delaySlider:SetPoint("LEFT", delayLabel, "RIGHT", 20, 0)
    delaySlider:SetMinMaxValues(0.1, 2.0)
    delaySlider:SetValueStep(0.1)
    delaySlider:SetValue(tonumber((ns.g and ns.g.timeBetweenMessages) or 0.2))
    delaySlider:SetWidth(200)
    delaySlider.Low:SetText("0.1s")
    delaySlider.High:SetText("2.0s")
    delaySlider.Text:SetText("Message Delay: " .. string.format("%.1f", delaySlider:GetValue()) .. "s")
    delaySlider:SetScript("OnValueChanged", function(self, value)
        if not ns.g then ns.g = {} end
        ns.g.timeBetweenMessages = string.format("%.1f", value)
        self.Text:SetText("Message Delay: " .. string.format("%.1f", value) .. "s")
    end)
    yOffset = yOffset - 50
    
    -- Scan Wait Time (Fixed at 15 seconds)
    local scanLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    scanLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    scanLabel:SetText("• Scan Wait Time:")
    
    local scanDisplay = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    scanDisplay:SetPoint("LEFT", scanLabel, "RIGHT", 20, 0)
    scanDisplay:SetText("15 seconds (Fixed)")
    if theme then
        local r, g, b = theme:GetColor("accent")
        scanDisplay:SetTextColor(r, g, b)
    else
        scanDisplay:SetTextColor(0.24, 0.73, 0.85)
    end
    
    local scanWarning = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    scanWarning:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 15)
    scanWarning:SetText("(Fixed at 15 seconds to prevent Blizzard throttling)")
    scanWarning:SetTextColor(1, 0.5, 0)
    
    -- Set the value in settings
    if not ns.g then ns.g = {} end
    ns.g.scanWaitTime = 15
    
    yOffset = yOffset - 80
    
    -- Quick Actions Header
    local actionsHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    actionsHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    actionsHeader:SetText("Quick Actions:")
    actionsHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 30
    
    -- Main Window Button
    local mainWindowBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    mainWindowBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    mainWindowBtn:SetSize(120, 25)
    mainWindowBtn:SetText("Main Window")
    mainWindowBtn:SetScript("OnClick", function()
        -- Use WindowManager to show recruitment window
        if ns.WindowManager then
            ns.WindowManager:ShowWindow("recruitment")
        elseif ns.RecruitmentFrame then
            ns.RecruitmentFrame:Show()
        end
    end)

end

function SettingsManager:CreateRecruitmentTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("Recruitment Settings")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 40
    
    -- Level Range Section
    local levelHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    levelHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    levelHeader:SetText("Level Range for Scanning:")
    levelHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25

    local minLevelLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    minLevelLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    minLevelLabel:SetText("Minimum Level:")

    local minLevelInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    minLevelInput:SetPoint("LEFT", minLevelLabel, "RIGHT", 10, 0)
    minLevelInput:SetSize(50, 20)
    minLevelInput:SetNumeric(true)
    minLevelInput:SetText(tostring((ns.pSettings and ns.pSettings.minLevel) or 1))
    minLevelInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 1
        if value < 1 then value = 1 end
        if value > GetMaxPlayerLevel() then value = GetMaxPlayerLevel() end
        self:SetText(tostring(value))
        self:ClearFocus()
        print("|cFF3EB9D8[FGR]|r Minimum level set to: " .. value)
        
        if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
            ns.RecruitmentFrame:RefreshFromSettings()
        end
    end)
    minLevelInput:SetScript("OnTextChanged", function(self)
        if not ns.pSettings then ns.pSettings = {} end
        local value = tonumber(self:GetText()) or 1
        if value < 1 then value = 1 end
        if value > GetMaxPlayerLevel() then value = GetMaxPlayerLevel() end
        ns.pSettings.minLevel = value
        
        -- Force save
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)

    local maxLevelLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    maxLevelLabel:SetPoint("LEFT", minLevelInput, "RIGHT", 20, 0)
    maxLevelLabel:SetText("Maximum Level:")

    local maxLevelInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    maxLevelInput:SetPoint("LEFT", maxLevelLabel, "RIGHT", 10, 0)
    maxLevelInput:SetSize(50, 20)
    maxLevelInput:SetNumeric(true)
    maxLevelInput:SetText(tostring((ns.pSettings and ns.pSettings.maxLevel) or GetMaxPlayerLevel()))
    maxLevelInput:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or GetMaxPlayerLevel()
        if value < 1 then value = 1 end
        if value > GetMaxPlayerLevel() then value = GetMaxPlayerLevel() end
        self:SetText(tostring(value))
        self:ClearFocus()
        print("|cFF3EB9D8[FGR]|r Maximum level set to: " .. value)
        
        if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
            ns.RecruitmentFrame:RefreshFromSettings()
        end
    end)
    maxLevelInput:SetScript("OnTextChanged", function(self)
        if not ns.pSettings then ns.pSettings = {} end
        local value = tonumber(self:GetText()) or GetMaxPlayerLevel()
        if value < 1 then value = 1 end
        if value > GetMaxPlayerLevel() then value = GetMaxPlayerLevel() end
        ns.pSettings.maxLevel = value
        
        -- Force save
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 60

    -- Filter Options Section
    local filterHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    filterHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    filterHeader:SetText("Filter Options:")
    filterHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25

    -- Class Filter Section
    local classFilterHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    classFilterHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    classFilterHeader:SetText("Class Filter:")
    classFilterHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25

    -- Initialize class filter settings if they don't exist
    if not ns.pSettings then ns.pSettings = {} end
    if not ns.pSettings.classFilter then 
        ns.pSettings.classFilter = {}
        local availableClasses = {
            "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", 
            "Mage", "Warlock", "Druid", "Death Knight", "Monk", "Demon Hunter", "Evoker"
        }
        for _, className in ipairs(availableClasses) do
            ns.pSettings.classFilter[className] = true
        end
    end

    -- Enable Class Filter checkbox
    local enableClassFilterLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    enableClassFilterLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    enableClassFilterLabel:SetText("• Enable Class Filter:")

    local enableClassFilterCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    enableClassFilterCheck:SetPoint("LEFT", enableClassFilterLabel, "RIGHT", 10, 0)
    enableClassFilterCheck.Text:SetText("Only show selected classes")
    enableClassFilterCheck:SetChecked((ns.pSettings and ns.pSettings.enableClassFilter) or false)
    yOffset = yOffset - 40

    -- Class selection checkboxes
    local classLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    classLabel:SetText("Select Classes:")
    yOffset = yOffset - 20

    -- Define available classes
    local availableClasses = {
        "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", 
        "Mage", "Warlock", "Druid", "Death Knight", "Monk", "Demon Hunter", "Evoker"
    }

    -- Create class checkboxes
    local classCheckboxes = {}
    local xOffset = 40
    local checkboxWidth = 120
    local checkboxesPerRow = 4
    local currentRow = 0

    -- Function to update checkbox states
    local function updateClassCheckboxStates()
        local isEnabled = enableClassFilterCheck:GetChecked()
        for className, checkbox in pairs(classCheckboxes) do
            checkbox:SetEnabled(isEnabled)
            if isEnabled then
                checkbox.Text:SetTextColor(1, 1, 1)
            else
                checkbox.Text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end

    for i, className in ipairs(availableClasses) do
        local checkbox = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
        
        -- Position calculation
        local row = math.floor((i - 1) / checkboxesPerRow)
        local col = (i - 1) % checkboxesPerRow
        
        checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset + (col * checkboxWidth), yOffset - (row * 25))
        checkbox.Text:SetText(className)
        checkbox:SetChecked(ns.pSettings.classFilter[className] or false)
        
        checkbox:SetScript("OnClick", function(self)
            if not ns.pSettings.classFilter then ns.pSettings.classFilter = {} end
            ns.pSettings.classFilter[className] = self:GetChecked()
            print("|cFF3EB9D8[FGR]|r " .. className .. " filter: " .. (self:GetChecked() and "ON" or "OFF"))
            
            if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
                ns.RecruitmentFrame:RefreshFromSettings()
            end
            
            -- IMMEDIATE SAVE  
            if ns.Database and ns.Database.SaveData then
                ns.Database:SaveData()
            end
        end)
        
        classCheckboxes[className] = checkbox
        currentRow = row
    end

    -- NOW set up the main checkbox handler (after classCheckboxes is populated)
    enableClassFilterCheck:SetScript("OnClick", function(self)
        if not ns.pSettings then ns.pSettings = {} end
        ns.pSettings.enableClassFilter = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r Class Filter: " .. (ns.pSettings.enableClassFilter and "ON" or "OFF"))
        
        updateClassCheckboxStates()
        
        if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
            ns.RecruitmentFrame:RefreshFromSettings()
        end
        
        -- IMMEDIATE SAVE
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)

    -- Initialize checkbox states
    updateClassCheckboxStates()

    -- Adjust yOffset based on number of rows
    yOffset = yOffset - ((currentRow + 1) * 25) - 20

    -- Select All/None buttons
    local selectAllBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    selectAllBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 40, yOffset)
    selectAllBtn:SetSize(80, 25)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        if not ns.pSettings.classFilter then ns.pSettings.classFilter = {} end
        for className, checkbox in pairs(classCheckboxes) do
            if checkbox:IsEnabled() then
                checkbox:SetChecked(true)
                ns.pSettings.classFilter[className] = true
            end
        end
        print("|cFF3EB9D8[FGR]|r All classes selected")
        
        if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
            ns.RecruitmentFrame:RefreshFromSettings()
        end
        
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)

    local selectNoneBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    selectNoneBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 10, 0)
    selectNoneBtn:SetSize(80, 25)
    selectNoneBtn:SetText("Select None")
    selectNoneBtn:SetScript("OnClick", function()
        if not ns.pSettings.classFilter then ns.pSettings.classFilter = {} end
        for className, checkbox in pairs(classCheckboxes) do
            if checkbox:IsEnabled() then
                checkbox:SetChecked(false)
                ns.pSettings.classFilter[className] = false
            end
        end
        print("|cFF3EB9D8[FGR]|r All classes deselected")
        
        if ns.RecruitmentFrame and ns.RecruitmentFrame.RefreshFromSettings then
            ns.RecruitmentFrame:RefreshFromSettings()
        end
        
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)

    yOffset = yOffset - 60

    -- Anti-Spam Enable
    local antiSpamLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    antiSpamLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    antiSpamLabel:SetText("• Enable Anti-Spam:")
    
    local antiSpamCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    antiSpamCheck:SetPoint("LEFT", antiSpamLabel, "RIGHT", 10, 0)
    antiSpamCheck.Text:SetText("Prevent messaging same player repeatedly")
    antiSpamCheck:SetChecked((ns.gSettings and ns.gSettings.antiSpam) or true)
    antiSpamCheck:SetScript("OnClick", function(self)
        if not ns.gSettings then ns.gSettings = {} end
        ns.gSettings.antiSpam = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r Anti-Spam: " .. (ns.gSettings.antiSpam and "ON" or "OFF"))
        
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 30
    
    -- Anti-Spam Days
    local antiSpamDaysLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    antiSpamDaysLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    antiSpamDaysLabel:SetText("• Anti-Spam Duration:")
    
    local antiSpamDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    antiSpamDropdown:SetPoint("LEFT", antiSpamDaysLabel, "RIGHT", 0, -5)
    antiSpamDropdown:SetScale(0.8)
    
    local antiSpamDays = {
        [7] = "7 days",
        [14] = "14 days", 
        [30] = "30 days (1 month)",
        [90] = "90 days (3 months)",
        [180] = "180 days (6 months)"
    }
    
    UIDropDownMenu_SetWidth(antiSpamDropdown, 150)
    UIDropDownMenu_Initialize(antiSpamDropdown, function(self, level)
        for value, text in pairs(antiSpamDays) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = function()
                if not ns.gSettings then ns.gSettings = {} end
                ns.gSettings.antiSpamDays = value
                UIDropDownMenu_SetSelectedValue(antiSpamDropdown, value)
                print("|cFF3EB9D8[FGR]|r Anti-Spam Days: " .. text)
                
                if ns.Database and ns.Database.SaveData then
                    ns.Database:SaveData()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(antiSpamDropdown, (ns.gSettings and ns.gSettings.antiSpamDays) or 7)
    yOffset = yOffset - 60
    
    -- Guild Welcome Message Section
    local guildWelcomeHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guildWelcomeHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    guildWelcomeHeader:SetText("Guild Welcome Message:")
    guildWelcomeHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 30
    
    local guildGreetingLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guildGreetingLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    guildGreetingLabel:SetText("• Send Guild Greeting:")
    
    local guildGreetingCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    guildGreetingCheck:SetPoint("LEFT", guildGreetingLabel, "RIGHT", 10, 0)
    guildGreetingCheck.Text:SetText("Send welcome message to new members")
    guildGreetingCheck:SetChecked((ns.gSettings and ns.gSettings.sendGuildGreeting) or false)
    guildGreetingCheck:SetScript("OnClick", function(self)
        if not ns.gSettings then ns.gSettings = {} end
        ns.gSettings.sendGuildGreeting = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r Guild Greeting: " .. (ns.gSettings.sendGuildGreeting and "ON" or "OFF"))
        
        -- Save to database
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 30
    
    -- Guild Message Input
    local guildMsgLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guildMsgLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    guildMsgLabel:SetText("Guild Message:")
    
    local guildMsgInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    guildMsgInput:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 25)
    guildMsgInput:SetSize(500, 20)
    guildMsgInput:SetText((ns.gSettings and ns.gSettings.guildMessage) or "Welcome to our guild!")
    guildMsgInput:SetScript("OnEnterPressed", function(self)
        if not ns.gSettings then ns.gSettings = {} end
        ns.gSettings.guildMessage = self:GetText()
        print("|cFF3EB9D8[FGR]|r Guild message updated")
        self:ClearFocus()
        
        -- Save to database
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 80
    
    -- Whisper Welcome Message Section
    local whisperWelcomeHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    whisperWelcomeHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    whisperWelcomeHeader:SetText("Whisper Welcome Message:")
    whisperWelcomeHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 30
    
    local whisperGreetingLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    whisperGreetingLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    whisperGreetingLabel:SetText("• Send Whisper Greeting:")
    
    local whisperGreetingCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    whisperGreetingCheck:SetPoint("LEFT", whisperGreetingLabel, "RIGHT", 10, 0)
    whisperGreetingCheck.Text:SetText("Send whisper to recruited players")
    whisperGreetingCheck:SetChecked((ns.gSettings and ns.gSettings.sendWhisperGreeting) or false)
    whisperGreetingCheck:SetScript("OnClick", function(self)
        if not ns.gSettings then ns.gSettings = {} end
        ns.gSettings.sendWhisperGreeting = self:GetChecked()
        print("|cFF3EB9D8[FGR]|r Whisper Greeting: " .. (ns.gSettings.sendWhisperGreeting and "ON" or "OFF"))
        
        -- Save to database
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 30
    
    -- Whisper Message Input
    local whisperMsgLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    whisperMsgLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    whisperMsgLabel:SetText("Whisper Message:")
    
    -- Create a simple frame with colored background
    local whisperMsgFrame = CreateFrame("Frame", nil, parent)
    whisperMsgFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 25)
    whisperMsgFrame:SetSize(500, 60)
    
    -- Create background texture
    local bg = whisperMsgFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(whisperMsgFrame)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Create border
    local border = whisperMsgFrame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(whisperMsgFrame)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)
    
    -- Make border slightly smaller to show as outline
    bg:SetPoint("TOPLEFT", whisperMsgFrame, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", whisperMsgFrame, "BOTTOMRIGHT", -1, 1)
    
    local whisperMsgInput = CreateFrame("EditBox", nil, whisperMsgFrame)
    whisperMsgInput:SetMultiLine(true)
    whisperMsgInput:SetFontObject(ChatFontNormal)
    whisperMsgInput:SetPoint("TOPLEFT", whisperMsgFrame, "TOPLEFT", 8, -8)
    whisperMsgInput:SetPoint("BOTTOMRIGHT", whisperMsgFrame, "BOTTOMRIGHT", -8, 8)
    whisperMsgInput:SetText((ns.gSettings and ns.gSettings.whisperMessage) or "")
    whisperMsgInput:SetScript("OnEscapePressed", function(self)
        if not ns.gSettings then ns.gSettings = {} end
        ns.gSettings.whisperMessage = self:GetText()
        print("|cFF3EB9D8[FGR]|r Whisper message updated")
        self:ClearFocus()
        
        -- Save to database
        if ns.Database and ns.Database.SaveData then
            ns.Database:SaveData()
        end
    end)
    yOffset = yOffset - 100
    
    -- Instructions
    local instructionsHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    instructionsHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    instructionsHeader:SetText("Message Instructions:")
    instructionsHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local instructions = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    instructions:SetText("Use these keywords in your messages:\n" ..
                        "• |cFFFFFF00GUILDNAME|r - Replaced with guild name\n" ..
                        "• |cFFFFFF00PLAYERNAME|r - Replaced with target player name\n" ..
                        "• |cFFFFFF00GUILDLINK|r - Replaced with guild link (retail only)")
    instructions:SetJustifyH("LEFT")
    instructions:SetWidth(500)

    yOffset = yOffset - 60
    local saveChangesBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    saveChangesBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    saveChangesBtn:SetSize(120, 30)
    saveChangesBtn:SetText("Save Changes")
    saveChangesBtn:SetScript("OnClick", function()
        -- Force save all recruitment settings
        if ns.Database and ns.Database.SaveData then
            local success = ns.Database:SaveData()
            if success then
                print("|cFF3EB9D8[FGR]|r Recruitment settings saved!")
            else
                print("|cFFFF0000[FGR]|r Failed to save settings!")
            end
        else
            print("|cFFFF0000[FGR]|r Database not available!")
        end
    end)
end

function SettingsManager:CreateMessagesTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("Message Templates")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 40
    
    -- Get the message list from the database
    local function getMessageList()
        if ns.Database and ns.Database.GetMessageList then
            return ns.Database:GetMessageList()
        else
            -- Fallback to guild data structure
            if not ns.guild then ns.guild = {data = {}} end
            if not ns.guild.data then ns.guild.data = {} end
            if not ns.guild.data.messageList then ns.guild.data.messageList = {} end
            return ns.guild.data.messageList
        end
    end
    
    -- Save message list to database
    local function saveMessageList(messageList)
        if ns.Database and ns.Database.SaveMessageList then
            return ns.Database:SaveMessageList(messageList)
        else
            -- Fallback save
            if not ns.guild then ns.guild = {data = {}} end
            if not ns.guild.data then ns.guild.data = {} end
            ns.guild.data.messageList = messageList
            return true
        end
    end
    
    -- Current Message Dropdown
    local messageLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    messageLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    messageLabel:SetText("Select Message Template:")
    
    local messageDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    messageDropdown:SetPoint("LEFT", messageLabel, "RIGHT", 10, -5)
    messageDropdown:SetScale(0.8)
    
    local selectedMessage = nil
    local messageData = {
        desc = "",
        message = "",
        gmSync = false
    }
    
    -- UI elements that need to be referenced
    local descInput, msgInput, gmSyncCheck, previewText, charCount
    
    -- Function to refresh dropdown
    local function refreshDropdown()
        UIDropDownMenu_Initialize(messageDropdown, function(self, level)
            -- Add "New Message" option
            local newInfo = UIDropDownMenu_CreateInfo()
            newInfo.text = "|cFF00FF00Create New Message|r"
            newInfo.value = "new"
            newInfo.func = function()
                selectedMessage = nil
                messageData = {desc = "", message = "", gmSync = false}
                UIDropDownMenu_SetSelectedValue(messageDropdown, "new")
                if descInput then descInput:SetText("") end
                if msgInput then msgInput:SetText("") end
                if gmSyncCheck then gmSyncCheck:SetChecked(false) end
                updatePreview()
            end
            UIDropDownMenu_AddButton(newInfo, level)
            
            -- Add existing messages
            local messageList = getMessageList()
            for k, v in pairs(messageList) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = v.desc or ("Message " .. k)
                info.value = k
                info.func = function()
                    selectedMessage = k
                    messageData = {
                        desc = v.desc or "",
                        message = v.message or "",
                        gmSync = v.gmSync or false
                    }
                    UIDropDownMenu_SetSelectedValue(messageDropdown, k)
                    if descInput then descInput:SetText(messageData.desc) end
                    if msgInput then msgInput:SetText(messageData.message) end
                    if gmSyncCheck then gmSyncCheck:SetChecked(messageData.gmSync) end
                    updatePreview()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    
    UIDropDownMenu_SetWidth(messageDropdown, 200)
    yOffset = yOffset - 60
    
    -- Message Description
    local descLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    descLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    descLabel:SetText("Message Description:")
    
    descInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    descInput:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset - 25)
    descInput:SetSize(400, 20)
    descInput:SetScript("OnTextChanged", function(self)
        messageData.desc = self:GetText()
    end)
    descInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    yOffset = yOffset - 60
    
    -- GM Sync Checkbox
    local gmSyncLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gmSyncLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    gmSyncLabel:SetText("Guild Master Sync:")
    
    gmSyncCheck = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    gmSyncCheck:SetPoint("LEFT", gmSyncLabel, "RIGHT", 10, 0)
    gmSyncCheck.Text:SetText("Sync with Guild Master")
    gmSyncCheck:SetScript("OnClick", function(self)
        messageData.gmSync = self:GetChecked()
    end)
    yOffset = yOffset - 40
    
    -- Message Content
    local msgLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    msgLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    msgLabel:SetText("Message Content:")
    yOffset = yOffset - 25
    
    -- Message input frame
    local msgFrame = CreateFrame("Frame", nil, parent)
    msgFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    msgFrame:SetSize(550, 120)
    
    local msgBg = msgFrame:CreateTexture(nil, "BACKGROUND")
    msgBg:SetAllPoints(msgFrame)
    msgBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    local msgBorder = msgFrame:CreateTexture(nil, "BORDER")
    msgBorder:SetAllPoints(msgFrame)
    msgBorder:SetColorTexture(0.5, 0.5, 0.5, 1)
    msgBg:SetPoint("TOPLEFT", msgFrame, "TOPLEFT", 1, -1)
    msgBg:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -1, 1)
    
    msgInput = CreateFrame("EditBox", nil, msgFrame)
    msgInput:SetMultiLine(true)
    msgInput:SetFontObject(ChatFontNormal)
    msgInput:SetPoint("TOPLEFT", msgFrame, "TOPLEFT", 8, -8)
    msgInput:SetPoint("BOTTOMRIGHT", msgFrame, "BOTTOMRIGHT", -8, 8)
    msgInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    yOffset = yOffset - 140
    
    -- Message Preview
    local previewLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    previewLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    previewLabel:SetText("Preview:")
    
    previewText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    previewText:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset - 20)
    previewText:SetWidth(550)
    previewText:SetJustifyH("LEFT")
    previewText:SetTextColor(0.8, 0.8, 1)
    yOffset = yOffset - 60
    
    -- Character Count
    charCount = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    charCount:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    charCount:SetTextColor(0, 1, 0)
    yOffset = yOffset - 40
    
    -- Update function for preview and character count
    function updatePreview()
        local msg = messageData.message or ""
        if msg ~= "" then
            local preview = msg:gsub("GUILDNAME", GetGuildInfo("player") or "[Guild Name]")
            preview = preview:gsub("PLAYERNAME", UnitName("player"))
            preview = preview:gsub("GUILDLINK", "[Guild Link]")
            if previewText then
                previewText:SetText("|cFFFF80FF[Preview]: |r" .. preview)
            end
            
            local length = string.len(msg)
            local color = length > 255 and "|cFFFF0000" or "|cFF00FF00"
            if charCount then
                charCount:SetText("Characters: " .. color .. length .. "|r / 255")
            end
        else
            if previewText then previewText:SetText("") end
            if charCount then charCount:SetText("") end
        end
    end
    
    -- Set up message input change handler
    msgInput:SetScript("OnTextChanged", function(self)
        messageData.message = self:GetText()
        updatePreview()
    end)
    
    
-- Buttons (Debug Version)
local saveBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
saveBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
saveBtn:SetSize(80, 25)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    if messageData.desc == "" or messageData.message == "" then
        print("|cFFFF0000[FGR]|r Please fill in both description and message")
        return
    end
    
    -- Debug: Check current state
    print("|cFF00FFFF[FGR-DEBUG]|r Saving message...")
    print("|cFF00FFFF[FGR-DEBUG]|r Description: " .. messageData.desc)
    print("|cFF00FFFF[FGR-DEBUG]|r Message: " .. messageData.message)
    
    local messageList = getMessageList()
    print("|cFF00FFFF[FGR-DEBUG]|r Current message list count: " .. #messageList)
    
    local newMessage = {
        desc = messageData.desc,
        message = messageData.message,
        gmSync = messageData.gmSync
    }
    
    if selectedMessage and messageList[selectedMessage] then
        -- Update existing message
        messageList[selectedMessage] = newMessage
        print("|cFF00FFFF[FGR-DEBUG]|r Updated existing message at index: " .. selectedMessage)
    else
        -- Add new message
        table.insert(messageList, newMessage)
        selectedMessage = #messageList
        print("|cFF00FFFF[FGR-DEBUG]|r Added new message at index: " .. selectedMessage)
    end
    
    -- Save to database
    local saved = saveMessageList(messageList)
    print("|cFF00FFFF[FGR-DEBUG]|r Save result: " .. tostring(saved))
    print("|cFF00FFFF[FGR-DEBUG]|r New message list count: " .. #messageList)
    
    -- Debug: Check if data structure exists
    print("|cFF00FFFF[FGR-DEBUG]|r ns.guild exists: " .. tostring(ns.guild ~= nil))
    if ns.guild then
        print("|cFF00FFFF[FGR-DEBUG]|r ns.guild.data exists: " .. tostring(ns.guild.data ~= nil))
        if ns.guild.data then
            print("|cFF00FFFF[FGR-DEBUG]|r ns.guild.data.messageList exists: " .. tostring(ns.guild.data.messageList ~= nil))
            if ns.guild.data.messageList then
                print("|cFF00FFFF[FGR-DEBUG]|r Actual messageList count: " .. #ns.guild.data.messageList)
            end
        end
    end
    
    -- Refresh the dropdown to show the new/updated message
    refreshDropdown()
    UIDropDownMenu_SetSelectedValue(messageDropdown, selectedMessage)
    
    print("|cFF3EB9D8[FGR]|r Message template saved!")
end)

-- Add a debug button
local debugBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
debugBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
debugBtn:SetSize(80, 25)
debugBtn:SetText("Debug")
debugBtn:SetScript("OnClick", function()
    print("|cFF00FFFF[FGR-DEBUG]|r === MESSAGE DEBUG INFO ===")
    print("|cFF00FFFF[FGR-DEBUG]|r ns.guild: " .. tostring(ns.guild))
    if ns.guild then
        print("|cFF00FFFF[FGR-DEBUG]|r ns.guild.data: " .. tostring(ns.guild.data))
        if ns.guild.data then
            print("|cFF00FFFF[FGR-DEBUG]|r ns.guild.data.messageList: " .. tostring(ns.guild.data.messageList))
            if ns.guild.data.messageList then
                print("|cFF00FFFF[FGR-DEBUG]|r Message count: " .. #ns.guild.data.messageList)
                for i, msg in ipairs(ns.guild.data.messageList) do
                    print("|cFF00FFFF[FGR-DEBUG]|r Message " .. i .. ": " .. (msg.desc or "No desc"))
                end
            end
        end
    end
    
    print("|cFF00FFFF[FGR-DEBUG]|r Database initialized: " .. tostring(ns.Database and ns.Database.isInitialized))
    
    -- Try to get message list through function
    local messageList = getMessageList()
    print("|cFF00FFFF[FGR-DEBUG]|r getMessageList() returned " .. #messageList .. " messages")
end)

local deleteBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
deleteBtn:SetPoint("LEFT", debugBtn, "RIGHT", 10, 0)
deleteBtn:SetSize(80, 25)
deleteBtn:SetText("Delete")
deleteBtn:SetScript("OnClick", function()
    if selectedMessage then
        local messageList = getMessageList()
        if messageList[selectedMessage] then
            -- Remove the message
            table.remove(messageList, selectedMessage)
            
            -- Save to database
            saveMessageList(messageList)
            
            -- Reset form
            selectedMessage = nil
            messageData = {desc = "", message = "", gmSync = false}
            descInput:SetText("")
            msgInput:SetText("")
            gmSyncCheck:SetChecked(false)
            updatePreview()
            
            -- Refresh dropdown
            refreshDropdown()
            UIDropDownMenu_SetSelectedValue(messageDropdown, "new")
            
            print("|cFF3EB9D8[FGR]|r Message template deleted!")
        end
    end
end)

local newBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
newBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 10, 0)
newBtn:SetSize(80, 25)
newBtn:SetText("New")
newBtn:SetScript("OnClick", function()
    selectedMessage = nil
    messageData = {desc = "", message = "", gmSync = false}
    descInput:SetText("")
    msgInput:SetText("")
    gmSyncCheck:SetChecked(false)
    updatePreview()
    UIDropDownMenu_SetSelectedValue(messageDropdown, "new")
end)
    yOffset = yOffset - 60
    
    -- Enhanced Message Instructions Section
    local instructionsHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    instructionsHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    instructionsHeader:SetText("Message Instructions:")
    instructionsHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local instructions = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    instructions:SetText("Use these keywords in your messages:\n" ..
                        "• |cFFFFFF00GUILDNAME|r - Replaced with guild name\n" ..
                        "• |cFFFFFF00PLAYERNAME|r - Replaced with target player name\n" ..
                        "• |cFFFFFF00GUILDLINK|r - Replaced with guild link (retail only)")
    instructions:SetJustifyH("LEFT")
    instructions:SetWidth(500)
    instructions:SetTextColor(1, 1, 1)
    
    -- Add a visual separator
    yOffset = yOffset - 80
    local separator = parent:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    separator:SetSize(550, 1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.8)
    yOffset = yOffset - 20
    
    -- Example section
    local exampleHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    exampleHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    exampleHeader:SetText("Example:")
    exampleHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local exampleText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    exampleText:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    exampleText:SetText("\"Hello PLAYERNAME! Would you like to join GUILDNAME? Check us out: GUILDLINK\"\n\n" ..
                       "This would become:\n" ..
                       "\"Hello PlayerName! Would you like to join MyGuild? Check us out: [MyGuild]\"")
    exampleText:SetJustifyH("LEFT")
    exampleText:SetWidth(500)
    exampleText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Initialize dropdown and form
    refreshDropdown()
    UIDropDownMenu_SetSelectedValue(messageDropdown, "new")
    updatePreview()
end

function SettingsManager:CreateBlacklistTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("Blacklist Management")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 30
    
    -- Stats
    local count = 0
    if ns.tblBlackList then
        for _ in pairs(ns.tblBlackList) do count = count + 1 end
    end
    
    local stats = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stats:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    stats:SetText("Currently blacklisted players: " .. count)
    yOffset = yOffset - 40
    
    -- Add Player Section
    local addLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    addLabel:SetText("Add Player to Blacklist:")
    addLabel:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local playerNameLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    playerNameLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    playerNameLabel:SetText("Player Name:")
    
    local playerNameInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    playerNameInput:SetPoint("LEFT", playerNameLabel, "RIGHT", 10, 0)
    playerNameInput:SetSize(150, 20)
    yOffset = yOffset - 30
    
    local reasonLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    reasonLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    reasonLabel:SetText("Reason:")
    
    local reasonInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    reasonInput:SetPoint("LEFT", reasonLabel, "RIGHT", 10, 0)
    reasonInput:SetSize(300, 20)
    yOffset = yOffset - 40
    
    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    addBtn:SetSize(100, 25)
    addBtn:SetText("Add to Blacklist")
    addBtn:SetScript("OnClick", function()
        local name = playerNameInput:GetText():trim()
        local reason = reasonInput:GetText():trim()
        
        if name == "" then
            print("|cFFFF0000[FGR]|r Please enter a player name")
            return
        end
        
        if reason == "" then
            reason = "No reason provided"
        end
        
        if not ns.tblBlackList then ns.tblBlackList = {} end
        local key = string.lower(name)
        ns.tblBlackList[key] = {
            name = name,
            reason = reason,
            blBy = UnitName("player"),
            date = date("%m/%d/%Y %H:%M"),
            private = false
        }
        
        playerNameInput:SetText("")
        reasonInput:SetText("")
        print("|cFF3EB9D8[FGR]|r Player added to blacklist: " .. name)
    end)
    yOffset = yOffset - 60
    
    -- Blacklist Display
    local listLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    listLabel:SetText("Blacklisted Players:")
    listLabel:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    -- Create scroll frame for blacklist
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    scrollFrame:SetSize(550, 200)
    
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(scrollFrame)
    scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(530, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Function to populate blacklist
    local function populateBlacklist()
        -- Clear existing children
        for i = scrollChild:GetNumChildren(), 1, -1 do
            local child = select(i, scrollChild:GetChildren())
            child:Hide()
            child:SetParent(nil)
        end
        
        if not ns.tblBlackList then return end
        
        local yPos = -10
        local entryHeight = 25
        
        for key, data in pairs(ns.tblBlackList) do
            local entry = CreateFrame("Frame", nil, scrollChild)
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yPos)
            entry:SetSize(520, entryHeight)
            
            -- Background
            local entryBg = entry:CreateTexture(nil, "BACKGROUND")
            entryBg:SetAllPoints(entry)
            entryBg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
            
            -- Player name
            local nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", entry, "LEFT", 5, 0)
            nameText:SetText(data.name or key)
            nameText:SetTextColor(1, 0.5, 0.5)
            
            -- Reason
            local reasonText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            reasonText:SetPoint("LEFT", nameText, "RIGHT", 20, 0)
            reasonText:SetWidth(200)
            reasonText:SetJustifyH("LEFT")
            local displayReason = data.private and "<Private>" or (data.reason or "No reason")
            reasonText:SetText("Reason: " .. displayReason)
            
            -- Date and who added
            local infoText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetPoint("LEFT", reasonText, "RIGHT", 10, 0)
            infoText:SetTextColor(0.7, 0.7, 0.7)
            infoText:SetText("By: " .. (data.blBy or "Unknown") .. " - " .. (data.date or "Unknown"))
            
            -- Remove button
            local removeBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
            removeBtn:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
            removeBtn:SetSize(60, 20)
            removeBtn:SetText("Remove")
            removeBtn:SetScript("OnClick", function()
                ns.tblBlackList[key] = nil
                populateBlacklist()
                print("|cFF3EB9D8[FGR]|r Removed " .. (data.name or key) .. " from blacklist")
            end)
            
            yPos = yPos - entryHeight - 2
        end
        
        scrollChild:SetHeight(math.max(1, -yPos))
    end
    
    -- Initial population
    populateBlacklist()
    
    yOffset = yOffset - 220
    
    -- Management buttons
    local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    refreshBtn:SetSize(80, 25)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        populateBlacklist()
        print("|cFF3EB9D8[FGR]|r Blacklist refreshed")
    end)
    
    local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
    clearBtn:SetSize(100, 25)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        if ns.tblBlackList then
            table.wipe(ns.tblBlackList)
            populateBlacklist()
            print("|cFF3EB9D8[FGR]|r Blacklist cleared")
        end
    end)
end

function SettingsManager:CreateAntiSpamTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("Anti-Spam Management")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 30
    
    -- Stats
    local count = 0
    if ns.tblAntiSpamList then
        for _ in pairs(ns.tblAntiSpamList) do count = count + 1 end
    end
    
    local stats = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stats:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    stats:SetText("Currently tracked players: " .. count)
    yOffset = yOffset - 30
    
    local noteText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    noteText:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    noteText:SetText("Players in this list have been recently contacted and won't receive duplicate messages.")
    noteText:SetTextColor(1, 1, 0)
    yOffset = yOffset - 40
    
    -- Anti-Spam List Display
    local listLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    listLabel:SetText("Recently Contacted Players:")
    listLabel:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    -- Create scroll frame for anti-spam list
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    scrollFrame:SetSize(550, 250)
    
    local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(scrollFrame)
    scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(530, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Function to populate anti-spam list
    local function populateAntiSpamList()
        -- Clear existing children
        for i = scrollChild:GetNumChildren(), 1, -1 do
            local child = select(i, scrollChild:GetChildren())
            child:Hide()
            child:SetParent(nil)
        end
        
        if not ns.tblAntiSpamList then return end
        
        local yPos = -10
        local entryHeight = 25
        
        -- Sort by date (most recent first)
        local sortedList = {}
        for key, data in pairs(ns.tblAntiSpamList) do
            table.insert(sortedList, {key = key, data = data})
        end
        table.sort(sortedList, function(a, b)
            return (a.data.time or 0) > (b.data.time or 0)
        end)
        
        for _, item in ipairs(sortedList) do
            local key = item.key
            local data = item.data
            
            local entry = CreateFrame("Frame", nil, scrollChild)
            entry:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yPos)
            entry:SetSize(520, entryHeight)
            
            -- Background (alternating colors)
            local entryBg = entry:CreateTexture(nil, "BACKGROUND")
            entryBg:SetAllPoints(entry)
            local bgColor = (yPos % 50 == -10) and 0.15 or 0.25
            entryBg:SetColorTexture(bgColor, bgColor, 0.3, 0.3)
            
            -- Player name
            local nameText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", entry, "LEFT", 5, 0)
            nameText:SetText(data.name or key)
            nameText:SetTextColor(0.8, 0.8, 1)
            
            -- Time contacted
            local timeText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeText:SetPoint("LEFT", nameText, "RIGHT", 30, 0)
            timeText:SetTextColor(0.7, 0.7, 0.7)
            if data.time then
                timeText:SetText("Contacted: " .. date("%m/%d/%Y %H:%M", data.time))
            else
                timeText:SetText("Contacted: Unknown")
            end
            
            -- Days since contact
            local daysSince = 0
            if data.time then
                daysSince = math.floor((time() - data.time) / 86400)
            end
            
            local daysText = entry:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            daysText:SetPoint("LEFT", timeText, "RIGHT", 30, 0)
            daysText:SetTextColor(0.5, 1, 0.5)
            daysText:SetText(daysSince .. " days ago")
            
            -- Remove button (for manual cleanup)
            local removeBtn = CreateFrame("Button", nil, entry, "UIPanelButtonTemplate")
            removeBtn:SetPoint("RIGHT", entry, "RIGHT", -5, 0)
            removeBtn:SetSize(60, 20)
            removeBtn:SetText("Remove")
            removeBtn:SetScript("OnClick", function()
                ns.tblAntiSpamList[key] = nil
                populateAntiSpamList()
                print("|cFF3EB9D8[FGR]|r Removed " .. (data.name or key) .. " from anti-spam list")
            end)
            
            yPos = yPos - entryHeight - 2
        end
        
        scrollChild:SetHeight(math.max(1, -yPos))
    end
    
    -- Initial population
    populateAntiSpamList()
    
    yOffset = yOffset - 270
    
    -- Management buttons
    local refreshBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    refreshBtn:SetSize(80, 25)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        populateAntiSpamList()
        print("|cFF3EB9D8[FGR]|r Anti-spam list refreshed")
    end)
    
    local cleanupBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    cleanupBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
    cleanupBtn:SetSize(120, 25)
    cleanupBtn:SetText("Cleanup Old Entries")
    cleanupBtn:SetScript("OnClick", function()
        if not ns.tblAntiSpamList then return end
        
        local currentTime = time()
        local maxAge = (ns.gSettings and ns.gSettings.antiSpamDays or 7) * 86400
        local removed = 0
        
        for key, data in pairs(ns.tblAntiSpamList) do
            if data.time and (currentTime - data.time) > maxAge then
                ns.tblAntiSpamList[key] = nil
                removed = removed + 1
            end
        end
        
        populateAntiSpamList()
        print("|cFF3EB9D8[FGR]|r Removed " .. removed .. " old entries from anti-spam list")
    end)
    
    local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearBtn:SetPoint("LEFT", cleanupBtn, "RIGHT", 10, 0)
    clearBtn:SetSize(80, 25)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        if ns.tblAntiSpamList then
            local count = 0
            for _ in pairs(ns.tblAntiSpamList) do count = count + 1 end
            table.wipe(ns.tblAntiSpamList)
            populateAntiSpamList()
            print("|cFF3EB9D8[FGR]|r Cleared " .. count .. " entries from anti-spam list")
        end
    end)
    yOffset = yOffset - 60
    
    -- Information section
    local infoLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    infoLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    infoLabel:SetText("Information:")
    infoLabel:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local infoText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    infoText:SetText("• Players are automatically added when you send them recruitment messages\n" ..
                     "• Old entries are automatically cleaned up based on your anti-spam duration setting\n" ..
                     "• You can manually remove players if you want to contact them again\n" ..
                     "• This prevents accidental spam and respects player preferences")
    infoText:SetJustifyH("LEFT")
    infoText:SetWidth(500)
end

function SettingsManager:CreateZonesTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("Zone Management")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 40
    
    local comingSoon = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    comingSoon:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    comingSoon:SetText("Zone management will be available soon.\nThis will allow you to mark zones as invalid for recruitment.")
    comingSoon:SetJustifyH("LEFT")
    comingSoon:SetWidth(500)
end

function SettingsManager:CreateAboutTab(parent)
    local yOffset = -10
    local theme = ns.Theme
    
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    header:SetText("About Fast Guild Recruiter")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header:SetTextColor(r, g, b)
    else
        header:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 40
    
    local version = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    version:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    version:SetText("Version: " .. (FGR.version or "Unknown"))
    yOffset = yOffset - 25
    
    local author = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    author:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    author:SetText("Author: " .. (FGR.author or "Unknown"))
    yOffset = yOffset - 40
    
    local linksHeader = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    linksHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
    linksHeader:SetText("Links:")
    linksHeader:SetTextColor(1, 1, 0)
    yOffset = yOffset - 25
    
    local discord = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    discord:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    discord:SetText("Discord: " .. (ns.Links and ns.Links.DISCORD or ""))
    yOffset = yOffset - 20
    
    local curseforge = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    curseforge:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    curseforge:SetText("CurseForge: " .. (ns.Links and ns.Links.CURSE_FORGE or ""))

    local header2 = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header2:SetPoint("CENTER", parent, "CENTER", 10, yOffset)
    header2:SetText("Buy me a Coffee @ https://buymeacoffee.com/patricnoxdev")
    if theme then
        local r, g, b = theme:GetColor("accent")
        header2:SetTextColor(r, g, b)
    else
        header2:SetTextColor(0.24, 0.73, 0.85)
    end
    yOffset = yOffset - 40
end

function SettingsManager:OpenSettings()
    print("|cFF3EB9D8[FGR]|r Opening FGR settings window...")
    
    -- Initialize if not already done
    if not self.isInitialized then
        self:Initialize()
    end
    
    -- Use WindowManager to show this window (and close others)
    if ns.WindowManager then
        ns.WindowManager:ShowWindow("settings")
    else
        -- Fallback if WindowManager not available
        if self.settingsFrame then
            if self.settingsFrame:IsShown() then
                self:CleanupAndHide()
            else
                self.settingsFrame:Show()
                if self.currentTab then
                    self:ShowTab(self.currentTab)
                else
                    self:ShowTab("general")
                end
            end
        end
    end
end
