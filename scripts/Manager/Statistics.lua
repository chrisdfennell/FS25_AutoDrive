-- Driver statistics: per vehicle, while AutoDrive drives it: distance, time driving and time standing,
-- deliveries and the amount unloaded. Counted on the server, saved with the vehicle, shown in the
-- fleet overview. A delivery is counted from the fill level: it went down by at least LOAD_MIN and
-- then stayed for UNLOAD_END_SAMPLES, so it works for every mode without looking into the tasks.

ADStatistics = {}

ADStatistics.SAMPLE_INTERVAL = 1000
-- faster than this (m/s) counts as driving, slower as standing / waiting
ADStatistics.MOVING_SPEED = 0.5
-- position jumps longer than this (m) in one sample are teleports, not driving
ADStatistics.MAX_STEP = 100
-- fill level drops smaller than this (l) per sample are ignored (e.g. rounding)
ADStatistics.MIN_DROP = 1
-- an unloading of at least this much (l, or the given part of the capacity if that is less) is a delivery
ADStatistics.LOAD_MIN = 500
ADStatistics.LOAD_MIN_PART = 0.25
-- samples without further drop that end an unloading
ADStatistics.UNLOAD_END_SAMPLES = 3

ADStatistics.KEYS = {"distance", "driveTime", "waitTime", "loads", "unloaded"}

function ADStatistics:load()
    self.timer = 0
end

function ADStatistics.newStats()
    return {distance = 0, driveTime = 0, waitTime = 0, loads = 0, unloaded = 0}
end

function ADStatistics.getStats(vehicle)
    if vehicle.ad.stats == nil then
        vehicle.ad.stats = ADStatistics.newStats()
    end
    return vehicle.ad.stats
end

function ADStatistics.reset(vehicle)
    vehicle.ad.stats = ADStatistics.newStats()
    vehicle.ad.statsTracking = nil
end

-- one sample of a vehicle AutoDrive is driving: position (x, z), total fill level and capacity of its units
-- tracking: per vehicle state between samples
function ADStatistics.addSample(stats, tracking, x, z, fillLevel, capacity, interval)
    if tracking.x ~= nil then
        local step = MathUtil.vector2Length(x - tracking.x, z - tracking.z)
        if step <= ADStatistics.MAX_STEP then
            stats.distance = stats.distance + step
        end
        if step / (interval / 1000) > ADStatistics.MOVING_SPEED and step <= ADStatistics.MAX_STEP then
            stats.driveTime = stats.driveTime + interval
        else
            stats.waitTime = stats.waitTime + interval
        end
    end
    tracking.x, tracking.z = x, z

    if tracking.fillLevel ~= nil then
        local drop = tracking.fillLevel - fillLevel
        if drop >= ADStatistics.MIN_DROP then
            stats.unloaded = stats.unloaded + drop
            tracking.unloading = (tracking.unloading or 0) + drop
            tracking.quietSamples = 0
        elseif tracking.unloading ~= nil then
            tracking.quietSamples = tracking.quietSamples + 1
            if tracking.quietSamples >= ADStatistics.UNLOAD_END_SAMPLES then
                local needed = ADStatistics.LOAD_MIN
                if capacity > 0 then
                    needed = math.min(needed, capacity * ADStatistics.LOAD_MIN_PART)
                end
                if tracking.unloading >= needed then
                    stats.loads = stats.loads + 1
                end
                tracking.unloading = nil
            end
        end
    end
    tracking.fillLevel = fillLevel
end

function ADStatistics:update(dt)
    if g_server == nil then
        return
    end
    self.timer = (self.timer or 0) + dt
    if self.timer < ADStatistics.SAMPLE_INTERVAL then
        return
    end
    local interval = self.timer
    self.timer = 0

    for _, vehicle in pairs(AutoDrive.getAllVehicles() or {}) do
        if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil and vehicle.components ~= nil then
            if vehicle.ad.stateModule:isActive() then
                if vehicle.ad.statsTracking == nil then
                    vehicle.ad.statsTracking = {}
                end
                local x, _, z = getWorldTranslation(vehicle.components[1].node)
                local fillLevel, capacity = 0, 0
                local units = AutoDrive.getAllUnits(vehicle)
                if units ~= nil and #units > 0 then
                    fillLevel, capacity = AutoDrive.getAllFillLevels(units)
                end
                ADStatistics.addSample(ADStatistics.getStats(vehicle), vehicle.ad.statsTracking, x, z, fillLevel or 0, capacity or 0, interval)
            else
                vehicle.ad.statsTracking = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
-- savegame
-------------------------------------------------------------------------------

function ADStatistics.registerSavegameKeys(schemaSavegame)
    for _, name in ipairs(ADStatistics.KEYS) do
        schemaSavegame:register(XMLValueType.FLOAT, "vehicles.vehicle(?).AutoDrive.statistics#" .. name, "AutoDrive statistics: " .. name)
    end
end

function ADStatistics.loadFromXML(vehicle, xmlFile, key)
    if not xmlFile:hasProperty(key .. ".statistics") then
        return
    end
    local stats = ADStatistics.newStats()
    for _, name in ipairs(ADStatistics.KEYS) do
        stats[name] = xmlFile:getValue(key .. ".statistics#" .. name) or 0
    end
    vehicle.ad.stats = stats
end

function ADStatistics.saveToXML(vehicle, xmlFile, key)
    local stats = vehicle.ad.stats
    if stats == nil then
        return
    end
    for _, name in ipairs(ADStatistics.KEYS) do
        xmlFile:setValue(key .. ".statistics#" .. name, stats[name])
    end
end

-------------------------------------------------------------------------------
-- display
-------------------------------------------------------------------------------

-- 5400000 ms -> "1:30 h"
function ADStatistics.formatTime(ms)
    local minutes = math.floor(ms / 60000)
    return string.format("%d:%02d h", math.floor(minutes / 60), minutes % 60)
end

-- e.g. "123.4 km  |  driving 5:20 h  |  waiting 1:10 h (18%)  |  12 deliveries  |  345600 l unloaded"
function ADStatistics.getText(stats)
    if stats == nil then
        stats = ADStatistics.newStats()
    end
    local total = stats.driveTime + stats.waitTime
    local waitPercent = 0
    if total > 0 then
        waitPercent = math.floor(100 * stats.waitTime / total + 0.5)
    end
    local parts = {
        string.format("%.1f km", stats.distance / 1000),
        string.format(g_i18n:getText("AD_stats_driving"), ADStatistics.formatTime(stats.driveTime)),
        string.format(g_i18n:getText("AD_stats_waiting"), ADStatistics.formatTime(stats.waitTime), waitPercent .. "%"),
        string.format(g_i18n:getText("AD_stats_loads"), stats.loads),
        string.format(g_i18n:getText("AD_stats_unloaded"), string.format("%d l", math.floor(stats.unloaded + 0.5)))
    }
    return table.concat(parts, "  |  ")
end
