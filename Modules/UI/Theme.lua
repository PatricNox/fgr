-- Modules/UI/Theme.lua
local addonName, ns = ...

ns.Theme = {}
local Theme = ns.Theme

Theme.colors = {
    background = { 0.05, 0.06, 0.09, 0.95 },
    panel = { 0.08, 0.09, 0.14, 0.92 },
    panelBorder = { 0.35, 0.25, 0.55, 0.45 },
    accent = { 0.63, 0.43, 0.96, 1.0 },
    accentSoft = { 0.46, 0.36, 0.78, 0.7 },
    text = { 0.92, 0.92, 0.98, 1.0 },
    muted = { 0.65, 0.66, 0.74, 1.0 },
    warning = { 1.0, 0.75, 0.2, 1.0 },
}

function Theme:GetColor(name)
    local color = self.colors[name]
    if not color then return 1, 1, 1, 1 end
    return color[1], color[2], color[3], color[4] or 1
end

function Theme:ApplyFrame(frame, titleText)
    if not frame or frame.fgrThemeApplied then return end
    frame.fgrThemeApplied = true

    local bgR, bgG, bgB, bgA = self:GetColor("background")
    local accentR, accentG, accentB, accentA = self:GetColor("accent")

    if frame.InsetBg then
        frame.InsetBg:SetColorTexture(bgR, bgG, bgB, bgA)
    end

    if frame.TitleBg then
        frame.TitleBg:SetVertexColor(accentR, accentG, accentB, 0.35)
    end

    if frame.title and titleText then
        frame.title:SetText(titleText)
        frame.title:SetTextColor(accentR, accentG, accentB)
    elseif frame.title then
        frame.title:SetTextColor(accentR, accentG, accentB)
    end

    if not frame.fgrHeaderGlow then
        local glow = frame:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
        glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        glow:SetHeight(24)
        glow:SetColorTexture(accentR, accentG, accentB, 0.08)
        frame.fgrHeaderGlow = glow
    end
end

function Theme:CreatePanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local pr, pg, pb, pa = self:GetColor("panel")
    local br, bg, bb, ba = self:GetColor("panelBorder")
    panel:SetBackdropColor(pr, pg, pb, pa)
    panel:SetBackdropBorderColor(br, bg, bb, ba)
    return panel
end

function Theme:CreateSectionHeader(parent, text)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local r, g, b = self:GetColor("accent")
    label:SetTextColor(r, g, b)
    label:SetText(text)
    return label
end

function Theme:StyleMutedText(label)
    if not label then return end
    local r, g, b = self:GetColor("muted")
    label:SetTextColor(r, g, b)
end

function Theme:StyleButton(button, isPrimary)
    if not button or button.fgrStyled then return end
    button.fgrStyled = true
    local r, g, b = self:GetColor(isPrimary and "accent" or "text")
    local fontString = button:GetFontString()
    if fontString then
        fontString:SetTextColor(r, g, b)
    end
end

function Theme:StyleTab(tab, isSelected)
    if not tab or not tab.bg or not tab.text then return end
    if isSelected then
        local r, g, b, a = self:GetColor("accent")
        tab.bg:SetColorTexture(r, g, b, 0.25)
        tab.text:SetTextColor(1, 1, 1)
    else
        local r, g, b = self:GetColor("panel")
        tab.bg:SetColorTexture(r, g, b, 0.6)
        self:StyleMutedText(tab.text)
    end
end
