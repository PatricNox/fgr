-- Modules/UI/Theme.lua
-- FGR design system.
--
-- Palette and rhythm are ported from the Integrity RP portal's dark theme:
-- warm gold accent on near-black panels, hairline borders instead of bevels,
-- uppercase micro-labels, and a tight type scale. WoW has no border-radius or
-- box-shadow, so depth comes from layered panel values + 1px hairlines.

local addonName, ns = ...

ns.Theme = {}
local Theme = ns.Theme

-------------------------------------------------------------------------------
-- Tokens
-------------------------------------------------------------------------------

Theme.colors = {
    -- Surfaces (dark to light)
    pageBg        = { 0.027, 0.027, 0.027, 0.96 },
    panel         = { 0.067, 0.067, 0.067, 1.00 },
    panelElevated = { 0.082, 0.082, 0.082, 1.00 },
    panelSoft     = { 0.090, 0.090, 0.090, 1.00 },
    panelHover    = { 0.125, 0.125, 0.125, 1.00 },
    sidebar       = { 0.051, 0.051, 0.051, 1.00 },
    control       = { 1.000, 1.000, 1.000, 0.045 },

    -- Hairlines
    border        = { 1.000, 1.000, 1.000, 0.075 },
    borderStrong  = { 1.000, 1.000, 1.000, 0.140 },

    -- Type
    textMain      = { 0.965, 0.949, 0.918, 1.00 },
    textMuted     = { 0.722, 0.686, 0.639, 1.00 },
    textSoft      = { 0.455, 0.427, 0.392, 1.00 },

    -- Accent
    accent        = { 0.776, 0.557, 0.188, 1.00 },
    accentStrong  = { 0.906, 0.725, 0.384, 1.00 },
    accentHover   = { 0.929, 0.749, 0.400, 1.00 },
    accentSoft    = { 0.776, 0.557, 0.188, 0.16 },
    accentText    = { 0.067, 0.067, 0.067, 1.00 },

    -- Status
    success       = { 0.290, 0.871, 0.502, 1.00 },
    successSoft   = { 0.290, 0.871, 0.502, 0.11 },
    warning       = { 0.965, 0.725, 0.302, 1.00 },
    danger        = { 1.000, 0.420, 0.420, 1.00 },
    dangerSoft    = { 1.000, 0.420, 0.420, 0.12 },
    info          = { 0.659, 0.635, 0.620, 1.00 },
}

Theme.space  = { xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24 }
Theme.sizes  = { row = 26, control = 24, controlSm = 20, header = 34, hairline = 1 }

-- One knob: swap this to ship a different face across the whole addon.
Theme.fontFile = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
Theme.type = {
    micro   = 10, -- uppercase eyebrows, column headers
    caption = 11,
    body    = 12,
    bodyLg  = 13,
    title   = 15,
    display = 18,
}

-------------------------------------------------------------------------------
-- Font objects
--
-- Registered globally so `CreateFontString(nil, layer, "FGRFontBody")` works
-- anywhere in the addon and every label picks up the type scale at once.
-------------------------------------------------------------------------------

local FONT_OBJECTS = {
    FGRFontDisplay = { size = Theme.type.display, color = Theme.colors.textMain },
    FGRFontTitle   = { size = Theme.type.title,   color = Theme.colors.textMain },
    FGRFontBody    = { size = Theme.type.body,    color = Theme.colors.textMain },
    FGRFontCaption = { size = Theme.type.caption, color = Theme.colors.textMuted },
    FGRFontMicro   = { size = Theme.type.micro,   color = Theme.colors.textSoft },
    FGRFontSoft    = { size = Theme.type.body,    color = Theme.colors.textSoft },
    FGRFontAccent  = { size = Theme.type.body,    color = Theme.colors.accentStrong },
}

for name, spec in pairs(FONT_OBJECTS) do
    local font = _G[name] or CreateFont(name)
    font:SetFont(Theme.fontFile, spec.size, "")
    font:SetTextColor(spec.color[1], spec.color[2], spec.color[3], spec.color[4] or 1)
    font:SetJustifyH("LEFT")
    font:SetJustifyV("MIDDLE")
end

-------------------------------------------------------------------------------
-- Primitives
-------------------------------------------------------------------------------

function Theme:GetColor(name)
    local color = self.colors[name]
    if not color then return 1, 1, 1, 1 end
    return color[1], color[2], color[3], color[4] or 1
end

-- Solid fill covering the whole region of `frame`.
function Theme:Fill(frame, colorName, layer, alphaScale)
    local tex = frame:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetAllPoints(frame)
    local r, g, b, a = self:GetColor(colorName)
    tex:SetColorTexture(r, g, b, a * (alphaScale or 1))
    return tex
end

-- 1px hairline border. Returns a table of the four edges so callers can recolor.
function Theme:Border(frame, colorName, inset)
    inset = inset or 0
    local r, g, b, a = self:GetColor(colorName or "border")
    local edges = {}

    edges.top = frame:CreateTexture(nil, "BORDER")
    edges.top:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    edges.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    edges.top:SetHeight(1)

    edges.bottom = frame:CreateTexture(nil, "BORDER")
    edges.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    edges.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    edges.bottom:SetHeight(1)

    edges.left = frame:CreateTexture(nil, "BORDER")
    edges.left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    edges.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    edges.left:SetWidth(1)

    edges.right = frame:CreateTexture(nil, "BORDER")
    edges.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    edges.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    edges.right:SetWidth(1)

    for _, tex in pairs(edges) do tex:SetColorTexture(r, g, b, a) end

    edges.SetColor = function(_, name, alphaScale)
        local cr, cg, cb, ca = self:GetColor(name)
        for key, tex in pairs(edges) do
            if key ~= "SetColor" then tex:SetColorTexture(cr, cg, cb, ca * (alphaScale or 1)) end
        end
    end
    frame.fgrBorder = edges
    return edges
end

function Theme:SetFont(fontString, size, tone, flags)
    fontString:SetFont(self.fontFile, size or self.type.body, flags or "")
    if tone then
        local r, g, b, a = self:GetColor(tone)
        fontString:SetTextColor(r, g, b, a)
    end
    return fontString
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------

function Theme:Label(parent, text, tone, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    self:SetFont(fs, size or self.type.body, tone or "textMain", flags)
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

-- Uppercase micro-label. The portal uses these as section eyebrows and column
-- headers; letter-spacing isn't available in WoW so size + case carry it.
function Theme:Eyebrow(parent, text, tone)
    local fs = self:Label(parent, string.upper(text or ""), tone or "textSoft", self.type.micro)
    return fs
end

function Theme:Divider(parent, colorName)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    local r, g, b, a = self:GetColor(colorName or "border")
    tex:SetColorTexture(r, g, b, a)
    return tex
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

local BUTTON_VARIANTS = {
    primary   = { fill = "accent",      fillHover = "accentHover", text = "accentText", border = "accent",       borderHover = "accentHover" },
    secondary = { fill = "control",     fillHover = "panelHover",  text = "textMain",   border = "border",       borderHover = "borderStrong" },
    ghost     = { fill = nil,           fillHover = "control",     text = "textMuted",  border = nil,            borderHover = "border" },
    danger    = { fill = "dangerSoft",  fillHover = "danger",      text = "danger",     border = "dangerSoft",   borderHover = "danger", textHover = "accentText" },
}

function Theme:Button(parent, text, variant, opts)
    opts = opts or {}
    local spec = BUTTON_VARIANTS[variant or "secondary"] or BUTTON_VARIANTS.secondary
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(opts.width or 90, opts.height or self.sizes.control)

    btn.fgrFill = btn:CreateTexture(nil, "BACKGROUND")
    btn.fgrFill:SetAllPoints(btn)
    btn.fgrBorderEdges = self:Border(btn, spec.border or "border")

    local label = btn:CreateFontString(nil, "OVERLAY")
    self:SetFont(label, opts.fontSize or self.type.body, spec.text)
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText(text or "")
    btn.fgrLabel = label
    btn:SetFontString(label)

    btn.fgrSpec = spec
    btn.fgrHovered = false

    local function paint()
        local spec = btn.fgrSpec
        local enabled = btn:IsEnabled()
        local hovered = btn.fgrHovered and enabled
        local fillName = hovered and spec.fillHover or spec.fill
        if fillName then
            local r, g, b, a = self:GetColor(fillName)
            btn.fgrFill:SetColorTexture(r, g, b, enabled and a or a * 0.4)
        else
            btn.fgrFill:SetColorTexture(0, 0, 0, 0)
        end

        local borderName = hovered and (spec.borderHover or spec.border) or spec.border
        if borderName then
            btn.fgrBorderEdges:SetColor(borderName, enabled and 1 or 0.35)
        else
            btn.fgrBorderEdges:SetColor("border", hovered and 1 or 0)
        end

        local toneName = (hovered and spec.textHover) or spec.text
        local r, g, b = self:GetColor(toneName)
        if enabled then
            label:SetTextColor(r, g, b, 1)
        else
            label:SetTextColor(r, g, b, 0.35)
        end
    end
    btn.fgrPaint = paint

    btn:SetScript("OnEnter", function(self_)
        self_.fgrHovered = true
        paint()
        if self_.fgrTooltip then
            GameTooltip:SetOwner(self_, "ANCHOR_TOP")
            GameTooltip:SetText(self_.fgrTooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self_)
        self_.fgrHovered = false
        paint()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnMouseDown", function(self_)
        if not self_:IsEnabled() then return end
        label:ClearAllPoints()
        label:SetPoint("CENTER", self_, "CENTER", 0, -1)
    end)
    btn:SetScript("OnMouseUp", function(self_)
        label:ClearAllPoints()
        label:SetPoint("CENTER", self_, "CENTER", 0, 0)
    end)
    btn:SetScript("OnEnable", paint)
    btn:SetScript("OnDisable", paint)

    paint()
    return btn
end

-- Square icon/glyph button for window chrome (close, collapse, etc.)
function Theme:IconButton(parent, glyph, tooltip, tone)
    local btn = self:Button(parent, glyph, "ghost", { width = 22, height = 22, fontSize = self.type.bodyLg })
    btn.fgrTooltip = tooltip
    if tone then
        btn.fgrSpec = { fill = nil, fillHover = "control", text = tone, border = nil, borderHover = "border" }
        btn.fgrPaint()
    end
    return btn
end

-------------------------------------------------------------------------------
-- Checkbox
-------------------------------------------------------------------------------

function Theme:Checkbox(parent, text, opts)
    opts = opts or {}
    local size = opts.size or 15
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(size, size)

    cb.fgrBox = cb:CreateTexture(nil, "BACKGROUND")
    cb.fgrBox:SetAllPoints(cb)
    cb.fgrBorderEdges = self:Border(cb, "borderStrong")

    -- The tick is a filled inset square: crisper than the Blizzard check art
    -- at these sizes and it inherits the accent colour.
    cb.fgrTick = cb:CreateTexture(nil, "ARTWORK")
    cb.fgrTick:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    cb.fgrTick:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)

    local label = self:Label(cb, text, "textMain", opts.fontSize or self.type.body)
    label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
    cb.Text = label

    cb.fgrHovered = false
    local function paint()
        local enabled = cb:IsEnabled()
        local checked = cb:GetChecked()
        local r, g, b, a = self:GetColor(cb.fgrHovered and enabled and "panelHover" or "control")
        cb.fgrBox:SetColorTexture(r, g, b, a)
        cb.fgrBorderEdges:SetColor(checked and "accent" or (cb.fgrHovered and "borderStrong" or "border"), enabled and 1 or 0.4)
        local ar, ag, ab = self:GetColor("accent")
        cb.fgrTick:SetColorTexture(ar, ag, ab, checked and (enabled and 1 or 0.35) or 0)
        local tr, tg, tb = self:GetColor(enabled and "textMain" or "textSoft")
        label:SetTextColor(tr, tg, tb, enabled and 1 or 0.5)
    end
    cb.fgrPaint = paint

    cb:SetScript("OnEnter", function(s) s.fgrHovered = true; paint() end)
    cb:SetScript("OnLeave", function(s) s.fgrHovered = false; paint() end)
    cb:SetScript("OnEnable", paint)
    cb:SetScript("OnDisable", paint)
    -- PostClick fires after the consumer's OnClick, so their handler can never
    -- stomp the repaint. hooksecurefunc covers programmatic SetChecked calls.
    cb:HookScript("PostClick", paint)
    hooksecurefunc(cb, "SetChecked", paint)

    paint()
    return cb
end

-------------------------------------------------------------------------------
-- Text input
-------------------------------------------------------------------------------

-- A themed EditBox that IS the edit box (drop-in for InputBoxTemplate).
function Theme:EditBox(parent, opts)
    opts = opts or {}
    local edit = CreateFrame("EditBox", nil, parent)
    edit:SetSize(opts.width or 200, opts.height or self.sizes.control)
    edit:SetAutoFocus(false)
    edit:SetMultiLine(opts.multiLine or false)
    edit:SetTextInsets(8, 8, 4, 4)
    edit:SetFont(self.fontFile, opts.fontSize or self.type.body, "")
    local r, g, b = self:GetColor("textMain")
    edit:SetTextColor(r, g, b)
    if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end

    self:Fill(edit, "control")
    local edges = self:Border(edit, "border")

    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    if not opts.multiLine then
        edit:SetScript("OnEnterPressed", edit.ClearFocus)
    end
    edit:HookScript("OnEditFocusGained", function() edges:SetColor("accent") end)
    edit:HookScript("OnEditFocusLost", function() edges:SetColor("border") end)

    if opts.placeholder then
        local hint = self:Label(edit, opts.placeholder, "textSoft", opts.fontSize or self.type.body)
        hint:SetPoint("LEFT", edit, "LEFT", 8, 0)
        local function refresh() hint:SetShown(edit:GetText() == "" and not edit:HasFocus()) end
        edit:HookScript("OnTextChanged", refresh)
        edit:HookScript("OnEditFocusGained", refresh)
        edit:HookScript("OnEditFocusLost", refresh)
        refresh()
    end

    return edit
end

-- Flattens a Blizzard OptionsSliderTemplate in place.
function Theme:StyleSlider(slider)
    if slider.fgrStyled then return slider end
    slider.fgrStyled = true

    if slider.SetBackdrop then slider:SetBackdrop(nil) end
    if slider.NineSlice then slider.NineSlice:SetAlpha(0) end

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(3)
    local br, bg, bb, ba = self:GetColor("borderStrong")
    track:SetColorTexture(br, bg, bb, ba)

    local thumb = slider:GetThumbTexture()
    if thumb then
        local ar, ag, ab = self:GetColor("accent")
        thumb:SetColorTexture(ar, ag, ab, 1)
        thumb:SetSize(8, 14)
    end

    local name = slider:GetName()
    for _, key in ipairs({ "Low", "High", "Text" }) do
        local fs = slider[key] or (name and _G[name .. key])
        if fs then
            self:SetFont(fs, self.type.micro, key == "Text" and "textMuted" or "textSoft")
        end
    end
    return slider
end

-------------------------------------------------------------------------------
-- Dropdown (restyles the Blizzard widget rather than reimplementing menus)
-------------------------------------------------------------------------------

function Theme:StyleDropdown(dropdown, width)
    local name = dropdown:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
            local tex = _G[name .. suffix]
            if tex then tex:SetAlpha(0) end
        end
        -- The expand arrow keeps working; only its art goes away, replaced by
        -- the chevron drawn on the skin below.
        local button = _G[name .. "Button"]
        if button then
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                local tex = button[getter] and button[getter](button)
                if tex then tex:SetAlpha(0) end
            end
        end
        local text = _G[name .. "Text"]
        if text then self:SetFont(text, self.type.body, "textMain") end
    end

    if not dropdown.fgrSkin then
        local skin = CreateFrame("Frame", nil, dropdown)
        skin:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, -3)
        skin:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -16, 7)
        skin:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))
        self:Fill(skin, "control")
        self:Border(skin, "border")

        local chevron = self:Label(skin, "v", "textSoft", self.type.caption)
        chevron:SetPoint("RIGHT", skin, "RIGHT", -8, 0)

        dropdown.fgrSkin = skin
    end

    if width then UIDropDownMenu_SetWidth(dropdown, width) end
    return dropdown
end

-------------------------------------------------------------------------------
-- Scroll area with a hairline scrollbar
-------------------------------------------------------------------------------

function Theme:ScrollArea(parent, opts)
    opts = opts or {}
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local cur = sf:GetVerticalScroll()
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(cur - (delta * (opts.step or 28)), max)))
        if sf.fgrUpdateThumb then sf.fgrUpdateThumb() end
    end)

    -- Track + thumb drawn as thin bars; no Blizzard scrollbar art.
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(3)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 3, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 3, 0)
    self:Fill(track, "border")

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(3)
    local tr, tg, tb = self:GetColor("textSoft")
    thumb:SetColorTexture(tr, tg, tb, 0.85)

    local function updateThumb()
        local range = scroll:GetVerticalScrollRange() or 0
        local height = scroll:GetHeight()
        if range <= 0 or height <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local visibleRatio = height / (height + range)
        local thumbHeight = math.max(20, height * visibleRatio)
        local progress = scroll:GetVerticalScroll() / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -progress * (height - thumbHeight))
        thumb:SetHeight(thumbHeight)
    end
    scroll.fgrUpdateThumb = updateThumb
    scroll:SetScript("OnVerticalScroll", updateThumb)
    scroll:SetScript("OnScrollRangeChanged", updateThumb)
    scroll:SetScript("OnShow", updateThumb)

    scroll.child = child
    scroll.track = track
    return scroll, child
end

-------------------------------------------------------------------------------
-- Window shell
-------------------------------------------------------------------------------

-- Flat window: solid panel, hairline border, 34px header with title + controls.
-- `frame.body` is the content region below the header; `frame.TitleBg` is the
-- header itself, for callers that want to hang extra chrome next to the title.
function Theme:Window(opts)
    opts = opts or {}
    local frame = CreateFrame("Frame", opts.name, opts.parent or UIParent)
    frame:SetSize(opts.width or 640, opts.height or 480)
    frame:SetPoint(opts.point or "CENTER", UIParent, opts.point or "CENTER", opts.x or 0, opts.y or 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata(opts.strata or "MEDIUM")

    self:Fill(frame, "pageBg")
    self:Border(frame, "borderStrong")

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    header:SetHeight(opts.headerHeight or self.sizes.header)
    self:Fill(header, "sidebar")

    local headerRule = self:Divider(header, "border")
    headerRule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)

    -- Accent rail across the top edge: the one piece of colour in the chrome.
    local rail = header:CreateTexture(nil, "ARTWORK")
    rail:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    rail:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    rail:SetHeight(2)
    local ar, ag, ab = self:GetColor("accent")
    rail:SetColorTexture(ar, ag, ab, 0.9)

    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if opts.onMove then opts.onMove(frame) end
    end)

    local title = self:Label(header, opts.title or "", "textMain", opts.titleSize or self.type.title)
    title:SetPoint("LEFT", header, "LEFT", self.space.md, 0)
    frame.title = title

    local close = self:IconButton(header, "X", "Close", "textMuted")
    close:SetPoint("RIGHT", header, "RIGHT", -self.space.sm, 0)
    close:SetScript("OnClick", function()
        if opts.onClose then opts.onClose(frame) else frame:Hide() end
    end)
    frame.CloseButton = close

    -- Body region below the header; content anchors here.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.body = body

    frame.TitleBg = header

    if opts.name then
        -- Escape closes it. Guard against re-registering when a window is
        -- rebuilt (the recruiter recreates itself on density toggle).
        local already = false
        for _, entry in ipairs(UISpecialFrames) do
            if entry == opts.name then already = true break end
        end
        if not already then tinsert(UISpecialFrames, opts.name) end
    end

    frame:Hide()
    return frame
end

-------------------------------------------------------------------------------
-- Composites
-------------------------------------------------------------------------------

function Theme:Badge(parent, text, tone)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(16)
    local r, g, b = self:GetColor(tone or "accent")
    local bg = badge:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(badge)
    bg:SetColorTexture(r, g, b, 0.14)
    local label = self:Label(badge, string.upper(text or ""), nil, self.type.micro)
    label:SetTextColor(r, g, b)
    label:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badge:SetWidth(label:GetStringWidth() + 14)
    badge.label = label
    badge.SetBadgeText = function(_, value)
        label:SetText(string.upper(value or ""))
        badge:SetWidth(label:GetStringWidth() + 14)
    end
    return badge
end

-- Label above value, used for the session counters.
function Theme:StatTile(parent, labelText, valueText)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(72, 32)
    local caption = self:Eyebrow(tile, labelText)
    caption:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    local value = self:Label(tile, valueText or "0", "textMain", self.type.bodyLg)
    value:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -3)
    tile.value = value
    tile.caption = caption
    return tile
end

function Theme:EmptyState(parent, titleText, bodyText)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints(parent)
    local title = self:Label(holder, titleText or "", "textMuted", self.type.bodyLg)
    title:SetPoint("CENTER", holder, "CENTER", 0, 8)
    title:SetJustifyH("CENTER")
    local body = self:Label(holder, bodyText or "", "textSoft", self.type.caption)
    body:SetPoint("TOP", title, "BOTTOM", 0, -6)
    body:SetJustifyH("CENTER")
    holder.title = title
    holder.body = body
    return holder
end

