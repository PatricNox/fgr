-- Modules/UI/MinimapIcon.lua
local addonName, ns = ...

ns.MinimapIcon = {}
local MinimapIcon = ns.MinimapIcon

local DEFAULTS = {
    hide = false,
    angle = 220,
    radius = 80,
}

local function getSettings()
    if not ns.pSettings then ns.pSettings = {} end
    if not ns.pSettings.ui then ns.pSettings.ui = {} end
    if not ns.pSettings.ui.minimap then ns.pSettings.ui.minimap = {} end

    local settings = ns.pSettings.ui.minimap
    if settings.hide == nil then settings.hide = DEFAULTS.hide end
    if settings.angle == nil then settings.angle = DEFAULTS.angle end
    if settings.radius == nil then settings.radius = DEFAULTS.radius end

    return settings
end

function MinimapIcon:UpdatePosition()
    if not self.button then return end
    local settings = getSettings()
    local angle = tonumber(settings.angle) or DEFAULTS.angle
    local radius = tonumber(settings.radius) or DEFAULTS.radius
    local radians = math.rad(angle)

    local x = math.cos(radians) * radius
    local y = math.sin(radians) * radius
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MinimapIcon:Initialize()
    if self.button or not Minimap then return end

    local button = CreateFrame("Button", "FGRMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    background:SetSize(52, 52)
    background:SetPoint("TOPLEFT")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_GuildTabard_01")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    button.icon = icon

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            if ns.UI and ns.UI.MainFrame and ns.UI.MainFrame.Toggle then
                ns.UI.MainFrame:Toggle()
            else
                print("|cFFFF0000[FGR]|r Main window not available")
            end
        elseif mouseButton == "RightButton" then
            if ns.SettingsManager and ns.SettingsManager.OpenSettings then
                ns.SettingsManager:OpenSettings()
            elseif Settings and Settings.OpenToCategory then
                pcall(Settings.OpenToCategory, "AddOns")
            end
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Fast Guild Recruiter", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Toggle main window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Open settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function updateAngleFromCursor()
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local mx, my = Minimap:GetCenter()
        x, y = x / scale, y / scale

        local angle = math.deg(math.atan2(y - my, x - mx))
        if angle < 0 then angle = angle + 360 end

        local settings = getSettings()
        settings.angle = angle
        MinimapIcon:UpdatePosition()
    end

    button:SetScript("OnDragStart", function(self)
        self._dragging = true
        self:SetScript("OnUpdate", updateAngleFromCursor)
    end)

    button:SetScript("OnDragStop", function(self)
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        updateAngleFromCursor()
    end)

    self.button = button
    self:UpdatePosition()

    if getSettings().hide then
        button:Hide()
    end
end

function MinimapIcon:Show()
    if not self.button then
        self:Initialize()
    end
    if self.button then self.button:Show() end
end

function MinimapIcon:Hide()
    if self.button then self.button:Hide() end
end
