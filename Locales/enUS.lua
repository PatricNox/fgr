local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true)

L['DEFAULT_GUILD_WELCOME'] = 'Welcome PLAYERNAME to GUILDNAME!'

-- General Settings
L['FGR_SETTINGS'] = 'General Settings'
L['GEN_GUILD_WIDE'] = 'Guild-wide setting'
L['GEN_ACCOUNT_WIDE'] = 'Account-wide setting'
L['RELOAD_AFTER_CHANGE'] = 'Some changes may require a /reload to take effect.'
L['UI_SETTINGS'] = 'UI Settings'
L['GEN_WHATS_NEW'] = "Show What's New"
L['GEN_WHATS_NEW_DESC'] = 'Show the changelog popup on new versions.'
L['GEN_TOOLTIPS'] = 'Show Tooltips'
L['GEN_TOOLTIP_DESC'] = 'Enable addon tooltips.'
L['GEN_ADDON_MESSAGES'] = 'Show Addon Messages'
L['GEN_ADDON_MESSAGES_DESC'] = 'Show FGR messages in chat.'
L['KEEP_ADDON_OPEN'] = 'Keep Addon Open on ESC'
L['KEEP_ADDON_OPEN_DESC'] = 'Prevent closing the addon window when pressing Escape.'
L['GEN_MINIMAP'] = 'Show Minimap Icon'
L['GEN_MINIMAP_DESC'] = 'Toggle the minimap button.'
L['COMPACT_SIZE'] = 'Window Size'
L['DEBUG_MODE'] = 'Debug Mode'
L['DEBUG_MODE_DESC'] = 'Enable verbose debug logging to chat. Useful for troubleshooting.'

-- Performance Settings
L['PERFORMANCE_SETTINGS'] = 'Performance Settings'
L['SCAN_WAIT_TIME'] = 'Scan Interval (seconds)'
L['SCAN_WAIT_TIME_DESC'] = 'Time between WHO queries (2-10 seconds).'
L['SEND_MESSAGE_WAIT_TIME'] = 'Message Delay'
L['SEND_MESSAGE_WAIT_TIME_DESC'] = 'Delay between sending messages to players.'

-- Keybinding Settings
L['KEYBINDING_HEADER'] = 'Keybindings'
L['KEYBINDING_INVITE'] = 'Invite Keybind'
L['KEYBINDING_INVITE_DESC'] = 'Keybind to send invites to selected players.'
L['KEYBINDING_SCAN'] = 'Scan Keybind'
L['KEYBINDING_SCAN_DESC'] = 'Keybind to start a player scan.'
L['KEY_BOUND_TO_INVITE'] = 'Key is already bound to invite.'
L['KEY_BOUND_TO_SCAN'] = 'Key is already bound to scan.'

-- Database
L['DATABASE_RESET'] = 'Database has been reset due to version change.'
