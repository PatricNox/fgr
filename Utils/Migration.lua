-- Utils/Migration.lua
local addonName, ns = ...

ns.Migration = {}
local Migration = ns.Migration

function Migration:MigrateDatabase(db)
    return true
end
