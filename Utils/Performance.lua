-- Utils/Performance.lua
local addonName, ns = ...

ns.Performance = {}
local Performance = ns.Performance

local debouncedFunctions = {}
local throttledFunctions = {}

-- Initialize immediately
Performance.isInitialized = false

function Performance:Initialize()
    self.isInitialized = true
    if ns.Logger and ns.Logger.Debug then
        ns.Logger:Debug("Performance module initialized")
    end
    return true
end

function Performance:Debounce(func, delay, key)
    key = key or tostring(func)
    
    return function(...)
        if debouncedFunctions[key] then
            debouncedFunctions[key]:Cancel()
        end
        
        local args = {...}
        debouncedFunctions[key] = C_Timer.NewTimer(delay, function()
            func(unpack(args))
            debouncedFunctions[key] = nil
        end)
    end
end

function Performance:Throttle(func, delay, key)
    key = key or tostring(func)
    local lastCall = 0
    
    return function(...)
        local now = GetTime()
        if now - lastCall >= delay then
            lastCall = now
            return func(...)
        end
    end
end

function Performance:CreateCache(maxSize, ttl)
    maxSize = maxSize or 100
    ttl = ttl or 300 -- 5 minutes default
    
    local cache = {
        data = {},
        timestamps = {},
        maxSize = maxSize,
        ttl = ttl,
    }
    
    function cache:Get(key)
        local timestamp = self.timestamps[key]
        if timestamp and (GetTime() - timestamp) > self.ttl then
            self:Remove(key)
            return nil
        end
        return self.data[key]
    end
    
    function cache:Set(key, value)
        -- Remove old entries if cache is full
        if self:Size() >= self.maxSize then
            self:Clean()
        end
        
        self.data[key] = value
        self.timestamps[key] = GetTime()
    end
    
    function cache:Remove(key)
        self.data[key] = nil
        self.timestamps[key] = nil
    end
    
    function cache:Size()
        local count = 0
        for _ in pairs(self.data) do
            count = count + 1
        end
        return count
    end
    
    function cache:Clean()
        local now = GetTime()
        local toRemove = {}
        
        -- Find expired entries
        for key, timestamp in pairs(self.timestamps) do
            if (now - timestamp) > self.ttl then
                table.insert(toRemove, key)
            end
        end
        
        -- Remove expired entries
        for _, key in ipairs(toRemove) do
            self:Remove(key)
        end
        
        -- If still too full, remove oldest entries
        if self:Size() >= self.maxSize then
            local oldest = {}
            for key, timestamp in pairs(self.timestamps) do
                table.insert(oldest, {key = key, timestamp = timestamp})
            end
            
            table.sort(oldest, function(a, b) return a.timestamp < b.timestamp end)
            
            local removeCount = self:Size() - math.floor(self.maxSize * 0.8)
            for i = 1, removeCount do
                if oldest[i] then
                    self:Remove(oldest[i].key)
                end
            end
        end
    end
    
    return cache
end

-- Initialize immediately when loaded
Performance:Initialize()