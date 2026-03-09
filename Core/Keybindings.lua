-- Core/Keybindings.lua
-- Runtime keybinding handler for scan and invite actions
local addonName, ns = ...

ns.Keybindings = {}
local Keybindings = ns.Keybindings

-- Hidden button frames that keybinds trigger via SetOverrideBindingClick
local scanButton, inviteButton

function Keybindings:Initialize()
    -- Create invisible click-target buttons for keybind actions
    scanButton = CreateFrame("Button", "FGR_KeybindScan", UIParent, "SecureActionButtonTemplate")
    scanButton:SetSize(1, 1)
    scanButton:Hide()
    scanButton:SetScript("OnClick", function()
        if ns.RecruitmentFrame then
            -- Auto-show the frame if hidden
            if not ns.RecruitmentFrame.isInitialized or not ns.RecruitmentFrame.frame or not ns.RecruitmentFrame.frame:IsShown() then
                ns.RecruitmentFrame:Show()
            end
            ns.RecruitmentFrame:StartPlayerScan()
        end
    end)

    inviteButton = CreateFrame("Button", "FGR_KeybindInvite", UIParent, "SecureActionButtonTemplate")
    inviteButton:SetSize(1, 1)
    inviteButton:Hide()
    inviteButton:SetScript("OnClick", function()
        if ns.RecruitmentFrame then
            ns.RecruitmentFrame:SendNextInvite()
        end
    end)

    -- Apply saved keybinds after a short delay (DB may not be ready yet)
    C_Timer.After(2, function()
        self:ApplyKeybindings()
    end)

    if ns.Logger then
        ns.Logger:Debug("Keybindings module initialized")
    end
end

function Keybindings:ApplyKeybindings()
    -- Clear any previous overrides
    ClearOverrideBindings(scanButton)
    ClearOverrideBindings(inviteButton)

    local bindings = ns.g and ns.g.keybindings
    if not bindings then return end

    if bindings.scan and bindings.scan ~= "" then
        SetOverrideBindingClick(scanButton, false, bindings.scan, "FGR_KeybindScan")
        if ns.Logger then
            ns.Logger:Debug("Scan keybind set to: %s", bindings.scan)
        end
    end

    if bindings.invite and bindings.invite ~= "" then
        SetOverrideBindingClick(inviteButton, false, bindings.invite, "FGR_KeybindInvite")
        if ns.Logger then
            ns.Logger:Debug("Invite keybind set to: %s", bindings.invite)
        end
    end
end

-- Call this after keybind settings change
function Keybindings:RefreshKeybindings()
    self:ApplyKeybindings()
end

-- Initialize when loaded
Keybindings:Initialize()
