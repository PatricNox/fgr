-- Data/Constants.lua
local addonName, ns = ...

-- Make sure namespace exists
ns = ns or {}

-- Addon Information
ns.ADDON_NAME = addonName
ns.ICON_PATH = 'Interface\\AddOns\\'..addonName..'\\Images\\'

-- Database
FGR = FGR or {}
FGR.commPrefix = 'FGRSync'
FGR.dbVersion = 5

-- Release Information
FGR.enableFilter = false
FGR.isPreRelease = false
FGR.preReleaseType = 'Beta'

-- Colors
ns.Colors = {
    GM = 'FFAF640C',
    DEBUG = 'FFD845D8',
    ERROR = 'FFFF0000',
    SYSTEM = 'FFFFFF40',
    DEFAULT = 'FF3EB9D8',
    SUCCESS = 'FF00FF00',
    WARNING = 'FFFFFF00',
}

-- Icons
ns.Icons = {
    MAIN = ns.ICON_PATH..'FGR_Icon',
    LOCKED = ns.ICON_PATH..'FGR_Locked',
    UNLOCKED = ns.ICON_PATH..'FGR_Unlocked',
    ABOUT = ns.ICON_PATH..'FGR_About',
    BACK = ns.ICON_PATH..'FGR_Back',
    BLACKLIST = ns.ICON_PATH..'FGR_Blacklist',
    FILTER = ns.ICON_PATH..'FGR_Filter',
    FILTER_COLOR = ns.ICON_PATH..'FGR_FilterColor',
    COMPACT = ns.ICON_PATH..'FGR_Compact',
    EXPAND = ns.ICON_PATH..'FGR_Expand',
    EXIT = ns.ICON_PATH..'FGR_Exit',
    EXIT_EMPTY = ns.ICON_PATH..'FGR_ExitEmpty',
    NEW = ns.ICON_PATH..'FGR_New',
    RESET = ns.ICON_PATH..'FGR_Reset',
    STATS = ns.ICON_PATH..'FGR_Stats',
    SYNC_ON = ns.ICON_PATH..'FGR_SyncOn',
    SYNC = ns.ICON_PATH..'FGR_Sync',
    SETTINGS = ns.ICON_PATH..'FGR_Settings',
}

-- Player Information
ns.PLAYER_PROFILE = UnitName('player')..'-'..GetRealmName()

-- Time Constants
ns.Time = {
    SECONDS_IN_DAY = 86400,
    SECONDS_IN_HOUR = 3600,
    SECONDS_IN_MINUTE = 60,
}

-- UI Constants
ns.UI = {
    HIGHLIGHTS = {
        BLUE = 'bags-glow-heirloom',
        BLUE_LONG = 'communitiesfinder_card_highlight',
    },
    FONTS = {
        ARIAL = 'Fonts\\ARIAN.ttf',
        SKURRI = 'Fonts\\SKURRI.ttf',
        DEFAULT = 'Fonts\\FRIZQT__.ttf',
        MORPHEUS = 'Fonts\\MORPHEUS.ttf',
    },
    FONT_SIZE = {
        DEFAULT = 12,
        SMALL = 10,
        LARGE = 14,
    },
}

-- Enumerations
ns.Enums = {
    InviteFormat = {
        MESSAGE_ONLY = 1,
        GUILD_INVITE_ONLY = 2,
        GUILD_INVITE_AND_MESSAGE = 3,
        MESSAGE_ONLY_IF_INVITE_DECLINED = 4,
    },
    LogLevel = {
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        DEBUG = 4,
    },
}

-- External Links
ns.Links = {
    DISCORD = 'https://discord.gg/kEUCbfySZu',
    CURSE_FORGE = 'https://www.curseforge.com/wow/addons/fast-guild-recruiter',
    BUY_ME_COFFEE = 'https://coff.ee/patricnoxdev',
}

-- Settings Categories and Modules - INITIALIZE MODULES TABLE
ns.Settings = {
    Categories = {
        GENERAL = 'general',
        RECRUITMENT = 'recruitment', 
        MESSAGES = 'messages',
        ANTI_SPAM = 'antiSpam',
        BLACKLIST = 'blacklist',
        ZONES = 'zones',
        ABOUT = 'about',
    },
    Modules = {} -- This was missing!
}

-- Register addon communication prefix (safe check)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(FGR.commPrefix)
end

-- Set max character level safely
local function setMaxLevel()
    if GetMaxPlayerLevel then
        ns.MAX_CHARACTER_LEVEL = GetMaxPlayerLevel()
    else
        -- Fallback values for different expansions
        ns.MAX_CHARACTER_LEVEL = 80 -- Adjust based on current expansion
    end
end

-- Try to set max level, use fallback if API not available yet
local success, _ = pcall(setMaxLevel)
if not success then
    ns.MAX_CHARACTER_LEVEL = 80 -- Safe fallback
end