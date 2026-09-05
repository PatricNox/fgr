local addonName, ns = ...

ns.Utils = {}
local Utils = ns.Utils

-- Table utilities
function Utils:DeepCopy(original)
    if type(original) ~= 'table' then return original end
    
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = self:DeepCopy(v)
    end
    return copy
end

function Utils:TableSize(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

function Utils:IsTableEmpty(tbl)
    return not tbl or next(tbl) == nil
end

function Utils:SortTableByField(tbl, field, descending)
    if not tbl then return {} end
    
    local sorted = {}
    for k, v in pairs(tbl) do
        v.key = k -- preserve original key
        table.insert(sorted, v)
    end
    
    table.sort(sorted, function(a, b)
        local aVal = a[field] or ''
        local bVal = b[field] or ''
        
        if descending then
            return aVal > bVal
        else
            return aVal < bVal
        end
    end)
    
    return sorted
end

-- String utilities
function Utils:Trim(str)
    if not str then return '' end
    return str:match('^%s*(.-)%s*$')
end

function Utils:Split(str, delimiter)
    if not str then return {} end
    delimiter = delimiter or ','
    
    local result = {}
    local pattern = '([^' .. delimiter .. ']+)'
    
    for match in str:gmatch(pattern) do
        table.insert(result, self:Trim(match))
    end
    
    return result
end

function Utils:Capitalize(str)
    if not str or str == '' then return '' end
    return str:sub(1,1):upper() .. str:sub(2):lower()
end

-- Color utilities
function Utils:ColorText(colorCode, text)
    if not colorCode or not text then return text or '' end
    
    -- Handle both hex colors and predefined colors
    if not colorCode:find('^FF') and colorCode:len() == 6 then
        colorCode = 'FF' .. colorCode
    end
    
    return '|c' .. colorCode .. text .. '|r'
end

function Utils:StripColors(text)
    if not text then return '' end
    return text:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
end

-- Player utilities
function Utils:CreatePlayerString(name, class)
    if not name then return '' end
    
    local classColor = ''
    if class then
        local classColors = RAID_CLASS_COLORS[class]
        if classColors then
            classColor = classColors.colorStr
        end
    end
    
    if classColor ~= '' then
        return '|c' .. classColor .. name .. '|r'
    else
        return name
    end
end

function Utils:IsPlayerInMyGuild(playerName)
    if not playerName or not IsInGuild() then return false end
    
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local name = GetGuildRosterInfo(i)
        if name and name:lower() == playerName:lower() then
            return true
        end
    end
    
    return false
end

-- Compression utilities (for backward compatibility)
function Utils:CompressData(data)
    -- Use LibDeflate or similar compression library if available
    -- For now, just return the data as-is
    return data
end

function Utils:DecompressData(data)
    -- Use LibDeflate or similar compression library if available
    -- For now, just return the data as-is
    return true, data
end

-- URL utilities  
function Utils:OpenURL(url)
    if not url then return end
    
    -- Create a dialog with the URL for the user to copy
    local dialog = {
        text = "Copy this URL to your clipboard:",
        button1 = "OK",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        hasEditBox = true,
        editBoxWidth = 350,
        OnShow = function(self)
            self.editBox:SetText(url)
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end,
    }
    
    StaticPopup_Show("FGR_URL_COPY", nil, nil, dialog)
end

-- Tooltip utilities
function Utils:CreateTooltip(title, body, forceShow)
    if not ns.g or (not ns.g.ui.showToolTips and not forceShow) then return end
    
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetText(title, 1, 1, 1)
    
    if body then
        GameTooltip:AddLine(body, 1, 1, 1, true)
    end
    
    GameTooltip:Show()
end

-- Math utilities
function Utils:Round(number, decimals)
    decimals = decimals or 0
    local multiplier = 10 ^ decimals
    return math.floor(number * multiplier + 0.5) / multiplier
end

function Utils:Clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

-- Time utilities
function Utils:FormatTime(seconds)
    if seconds < 60 then
        return string.format("%.1fs", seconds)
    elseif seconds < 3600 then
        return string.format("%.1fm", seconds / 60)
    elseif seconds < 86400 then
        return string.format("%.1fh", seconds / 3600)
    else
        return string.format("%.1fd", seconds / 86400)
    end
end

function Utils:FormatDate(timestamp)
    return date("%m/%d/%Y %H:%M", timestamp)
end

function Utils:ValidatePlayerName(name)
    if not name or name == '' then return false end
    if name:len() < 2 or name:len() > 12 then return false end
    if not name:match("^[%a]+$") then return false end
    return true
end

-- Create the URL copy dialog
StaticPopupDialogs["FGR_URL_COPY"] = {
    text = "Copy this URL to your clipboard:",
    button1 = "OK", 
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    hasEditBox = true,
    editBoxWidth = 350,
    OnShow = function(self, data)
        if data and data.OnShow then
            data.OnShow(self)
        end
    end,
}
-- Guild invite shim: C_GuildInfo.Invite is the modern API; the GuildInvite global
-- is not present on every client this addon supports.
function ns.GuildInvite(playerName)
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(playerName)
    elseif GuildInvite then
        GuildInvite(playerName)
    end
end
