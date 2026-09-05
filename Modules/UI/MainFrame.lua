-- Modules/UI/MainFrame.lua
-- The /fgr hub: status at a glance, the two ways into recruiting, and the
-- command reference. Built on the Theme design system.

local addonName, ns = ...

ns.UI = ns.UI or {}
ns.UI.MainFrame = {}
local MainFrame = ns.UI.MainFrame

local T = ns.Theme
local frame = nil

local COMMANDS = {
    { "/fgr", "Toggle this window" },
    { "/fgr config", "Open settings" },
    { "/fgr help", "Show help in chat" },
    { "/fgr status", "Show status in chat" },
    { "/fgr debug", "Toggle debug mode" },
    { "/fgr blacklist <name>", "Blacklist a player" },
}

local function countKeys(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Section: eyebrow + hairline, then whatever the caller anchors under it.
local function section(parent, titleText, yOffset, pad)
    local caption = T:Eyebrow(parent, titleText, "accentStrong")
    caption:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, yOffset)

    local rule = T:Divider(parent, "border")
    rule:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, yOffset - 14)
    rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, yOffset - 14)

    return yOffset - 14 - T.space.md
end

function MainFrame:Initialize()
    if frame then return end
    self:CreateFrame()
    if ns.Logger and ns.Logger.Debug then
        ns.Logger:Debug("Main frame initialized")
    end
end

function MainFrame:CreateFrame()
    frame = T:Window({
        name = "FGRMainFrame",
        title = "Fast Guild Recruiter",
        width = 420,
        height = 470,
    })

    local body = frame.body
    local PAD = T.space.lg
    local version = FGR and FGR.versionOut or ""
    if version ~= "" then
        local verText = T:Label(frame.TitleBg, version, "textSoft", T.type.micro)
        verText:SetPoint("RIGHT", frame.CloseButton, "LEFT", -T.space.sm, 0)
    end

    local y = -T.space.lg

    -- ===== STATUS =====
    y = section(body, "Status", y, PAD)

    local tiles = {}
    local tileDefs = {
        { key = "guild",     label = "In guild" },
        { key = "invite",    label = "Can invite" },
        { key = "blacklist", label = "Blacklist" },
        { key = "antispam",  label = "Anti-spam" },
    }
    for index, def in ipairs(tileDefs) do
        local tile = T:StatTile(body, def.label, "-")
        tile:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + ((index - 1) * 92), y)
        tiles[def.key] = tile
    end

    local function updateStatus()
        local inGuild = IsInGuild()
        local canInvite = CanGuildInvite()
        tiles.guild.value:SetText(inGuild and "Yes" or "No")
        tiles.invite.value:SetText(canInvite and "Yes" or "No")
        tiles.blacklist.value:SetText(tostring(countKeys(ns.tblBlackList)))
        tiles.antispam.value:SetText(tostring(countKeys(ns.tblAntiSpamList)))

        local gr, gg, gb = T:GetColor(inGuild and "success" or "danger")
        tiles.guild.value:SetTextColor(gr, gg, gb)
        local ir, ig, ib = T:GetColor(canInvite and "success" or "danger")
        tiles.invite.value:SetTextColor(ir, ig, ib)
    end
    frame.updateStatus = updateStatus

    y = y - 44

    -- ===== RECRUIT =====
    y = section(body, "Recruit", y, PAD)

    local function openRecruitment(compact)
        if not ns.RecruitmentFrame then
            print("|cFFFF0000[FGR]|r Recruitment system not available")
            return
        end
        if ns.pSettings then ns.pSettings.isCompact = compact end
        ns.RecruitmentFrame.compactMode = compact
        ns.RecruitmentFrame:Show()
        MainFrame:Hide()
    end

    local recruitBtn = T:Button(body, "Open Recruiter", "primary", { width = 160, height = 30, fontSize = T.type.bodyLg })
    recruitBtn:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
    recruitBtn:SetScript("OnClick", function() openRecruitment(false) end)
    recruitBtn.fgrTooltip = "Full interface: filters, columns, session stats"

    local compactBtn = T:Button(body, "Compact Mode", "secondary", { width = 130, height = 30 })
    compactBtn:SetPoint("LEFT", recruitBtn, "RIGHT", T.space.sm, 0)
    compactBtn:SetScript("OnClick", function() openRecruitment(true) end)
    compactBtn.fgrTooltip = "Narrow window for recruiting while you play"

    y = y - 30 - T.space.xl

    -- ===== QUICK ACTIONS =====
    y = section(body, "Quick actions", y, PAD)

    local settingsBtn = T:Button(body, "Settings", "secondary", { width = 110, height = 26 })
    settingsBtn:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, y)
    settingsBtn:SetScript("OnClick", function()
        if ns.SettingsManager and ns.SettingsManager.OpenSettings then
            ns.SettingsManager:OpenSettings()
            MainFrame:Hide()
        elseif Settings and Settings.OpenToCategory then
            if not pcall(Settings.OpenToCategory, "AddOns") then
                print("|cFFFF0000[FGR]|r Settings not available")
            end
        else
            print("|cFFFF0000[FGR]|r Settings not available")
        end
    end)

    local blacklistBtn = T:Button(body, "Blacklist", "secondary", { width = 110, height = 26 })
    blacklistBtn:SetPoint("LEFT", settingsBtn, "RIGHT", T.space.sm, 0)
    blacklistBtn:SetScript("OnClick", function()
        if ns.SettingsManager and ns.SettingsManager.OpenSettings then
            ns.SettingsManager:OpenSettings("blacklist")
            MainFrame:Hide()
        end
    end)

    y = y - 26 - T.space.xl

    -- ===== COMMANDS =====
    y = section(body, "Commands", y, PAD)

    for index, entry in ipairs(COMMANDS) do
        local rowY = y - ((index - 1) * 18)

        local cmd = T:Label(body, entry[1], "accentStrong", T.type.caption)
        cmd:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, rowY)

        local desc = T:Label(body, entry[2], "textSoft", T.type.caption)
        desc:SetPoint("TOPLEFT", body, "TOPLEFT", PAD + 140, rowY)
    end

    frame:SetScript("OnShow", updateStatus)
    updateStatus()
end

function MainFrame:Show()
    if not frame then self:Initialize() end
    if not frame then return end
    frame:Show()
    if frame.updateStatus then frame.updateStatus() end
end

function MainFrame:Hide()
    if frame then frame:Hide() end
end

function MainFrame:Toggle()
    if not frame then self:Initialize() end
    if not frame then return end
    if frame:IsShown() then self:Hide() else self:Show() end
end

function MainFrame:IsShown()
    return frame and frame:IsShown() or false
end
