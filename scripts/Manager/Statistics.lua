-- Driver statistics: per vehicle, while AutoDrive drives it: distance, time driving and time standing,
-- deliveries and the amount unloaded, also per fill type and per in-game day (the last KEEP_DAYS days).
-- Counted on the server, saved with the vehicle, shown in the fleet overview. A delivery is counted from
-- the fill level: it went down by at least LOAD_MIN and then stayed for UNLOAD_END_SAMPLES, so it works
-- for every mode without looking into the tasks.

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
-- days kept for "today" and "last 7 days"
ADStatistics.KEEP_DAYS = 7
-- fill types listed per row, the ones with the most litres
ADStatistics.SHOWN_FILL_TYPES = 3

ADStatistics.KEYS = {"distance", "driveTime", "waitTime", "loads", "unloaded"}

ADStatistics.PERIOD_TOTAL = 1
ADStatistics.PERIOD_TODAY = 2
ADStatistics.PERIOD_WEEK = 3

function ADStatistics:load()
    self.timer = 0
end

-- numbers of one period; fillTypes: fill type name -> litres unloaded
function ADStatistics.newRecord()
    return {distance = 0, driveTime = 0, waitTime = 0, loads = 0, unloaded = 0, fillTypes = {}}
end

-- the totals plus days: in-game day -> record
function ADStatistics.newStats()
    local stats = ADStatistics.newRecord()
    stats.days = {}
    return stats
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

function ADStatistics.getDay()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment ~= nil then
        return environment.currentDay
    end
    return nil
end

-- the records a value is added to: the totals and the day
local function getRecords(stats, day)
    if day == nil then
        return {stats}
    end
    if stats.days[day] == nil then
        stats.days[day] = ADStatistics.newRecord()
        for oldDay, _ in pairs(stats.days) do
            if oldDay <= day - ADStatistics.KEEP_DAYS then
                stats.days[oldDay] = nil
            end
        end
    end
    return {stats, stats.days[day]}
end

local function add(records, key, value, fillTypeName)
    for _, record in ipairs(records) do
        record[key] = record[key] + value
        if fillTypeName ~= nil then
            record.fillTypes[fillTypeName] = (record.fillTypes[fillTypeName] or 0) + value
        end
    end
end

-- one sample of a vehicle AutoDrive is driving: position (x, z), total fill level and capacity of its units,
-- the in-game day and the fill type on board. tracking: per vehicle state between samples
function ADStatistics.addSample(stats, tracking, x, z, fillLevel, capacity, interval, day, fillTypeName)
    local records = getRecords(stats, day)
    if tracking.x ~= nil then
        local step = MathUtil.vector2Length(x - tracking.x, z - tracking.z)
        if step <= ADStatistics.MAX_STEP then
            add(records, "distance", step)
        end
        if step / (interval / 1000) > ADStatistics.MOVING_SPEED and step <= ADStatistics.MAX_STEP then
            add(records, "driveTime", interval)
        else
            add(records, "waitTime", interval)
        end
    end
    tracking.x, tracking.z = x, z

    if tracking.fillLevel ~= nil then
        local drop = tracking.fillLevel - fillLevel
        if drop >= ADStatistics.MIN_DROP then
            -- the fill type is the one that was on board before
            add(records, "unloaded", drop, tracking.fillType)
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
                    add(records, "loads", 1)
                end
                tracking.unloading = nil
            end
        end
    end
    tracking.fillLevel = fillLevel
    if fillLevel > 0 and fillTypeName ~= nil then
        tracking.fillType = fillTypeName
    end
end

function ADStatistics.getFillTypeName(vehicle)
    local fillType = ADBestPrice.getLoadedFillType(vehicle)
    if fillType == nil or fillType == FillType.UNKNOWN then
        return nil
    end
    return g_fillTypeManager:getFillTypeNameByIndex(fillType)
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
    local day = ADStatistics.getDay()

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
                local fillTypeName
                if (fillLevel or 0) > 0 then
                    fillTypeName = ADStatistics.getFillTypeName(vehicle)
                end
                ADStatistics.addSample(ADStatistics.getStats(vehicle), vehicle.ad.statsTracking, x, z, fillLevel or 0, capacity or 0, interval, day, fillTypeName)
            else
                vehicle.ad.statsTracking = nil
            end
        end
    end
end

-- the numbers of a period: the totals, today, or the last KEEP_DAYS days
function ADStatistics.getPeriod(stats, period, today)
    if stats == nil then
        return ADStatistics.newRecord()
    end
    if period == ADStatistics.PERIOD_TOTAL or today == nil then
        return stats
    end
    local from = today
    if period == ADStatistics.PERIOD_WEEK then
        from = today - ADStatistics.KEEP_DAYS + 1
    end
    local result = ADStatistics.newRecord()
    for day, record in pairs(stats.days or {}) do
        if day >= from and day <= today then
            for _, key in ipairs(ADStatistics.KEYS) do
                result[key] = result[key] + record[key]
            end
            for name, litres in pairs(record.fillTypes) do
                result.fillTypes[name] = (result.fillTypes[name] or 0) + litres
            end
        end
    end
    return result
end

-------------------------------------------------------------------------------
-- savegame
-------------------------------------------------------------------------------

function ADStatistics.registerSavegameKeys(schemaSavegame)
    local base = "vehicles.vehicle(?).AutoDrive.statistics"
    for _, name in ipairs(ADStatistics.KEYS) do
        schemaSavegame:register(XMLValueType.FLOAT, base .. "#" .. name, "AutoDrive statistics: " .. name)
        schemaSavegame:register(XMLValueType.FLOAT, base .. ".day(?)#" .. name, "AutoDrive statistics of a day: " .. name)
    end
    schemaSavegame:register(XMLValueType.INT, base .. ".day(?)#day", "AutoDrive statistics: in-game day")
    for _, path in ipairs({base, base .. ".day(?)"}) do
        schemaSavegame:register(XMLValueType.STRING, path .. ".fillType(?)#name", "AutoDrive statistics: fill type")
        schemaSavegame:register(XMLValueType.FLOAT, path .. ".fillType(?)#litres", "AutoDrive statistics: litres unloaded")
    end
end

local function loadRecord(xmlFile, key, record)
    for _, name in ipairs(ADStatistics.KEYS) do
        record[name] = xmlFile:getValue(key .. "#" .. name) or 0
    end
    local i = 0
    while true do
        local fillTypeKey = string.format("%s.fillType(%d)", key, i)
        local name = xmlFile:getValue(fillTypeKey .. "#name")
        if name == nil then
            break
        end
        record.fillTypes[name] = xmlFile:getValue(fillTypeKey .. "#litres") or 0
        i = i + 1
    end
end

local function saveRecord(xmlFile, key, record)
    for _, name in ipairs(ADStatistics.KEYS) do
        xmlFile:setValue(key .. "#" .. name, record[name])
    end
    local names = {}
    for name, _ in pairs(record.fillTypes) do
        table.insert(names, name)
    end
    table.sort(names)
    for i, name in ipairs(names) do
        local fillTypeKey = string.format("%s.fillType(%d)", key, i - 1)
        xmlFile:setValue(fillTypeKey .. "#name", name)
        xmlFile:setValue(fillTypeKey .. "#litres", record.fillTypes[name])
    end
end

function ADStatistics.loadFromXML(vehicle, xmlFile, key)
    local statsKey = key .. ".statistics"
    if not xmlFile:hasProperty(statsKey) then
        return
    end
    local stats = ADStatistics.newStats()
    loadRecord(xmlFile, statsKey, stats)
    local i = 0
    while true do
        local dayKey = string.format("%s.day(%d)", statsKey, i)
        local day = xmlFile:getValue(dayKey .. "#day")
        if day == nil then
            break
        end
        local record = ADStatistics.newRecord()
        loadRecord(xmlFile, dayKey, record)
        stats.days[day] = record
        i = i + 1
    end
    vehicle.ad.stats = stats
end

function ADStatistics.saveToXML(vehicle, xmlFile, key)
    local stats = vehicle.ad.stats
    if stats == nil then
        return
    end
    local statsKey = key .. ".statistics"
    saveRecord(xmlFile, statsKey, stats)
    local days = {}
    for day, _ in pairs(stats.days) do
        table.insert(days, day)
    end
    table.sort(days)
    for i, day in ipairs(days) do
        local dayKey = string.format("%s.day(%d)", statsKey, i - 1)
        xmlFile:setValue(dayKey .. "#day", day)
        saveRecord(xmlFile, dayKey, stats.days[day])
    end
end

-------------------------------------------------------------------------------
-- network (AutoDriveStatisticsEvent)
-------------------------------------------------------------------------------

local function writeRecord(streamId, record)
    streamWriteFloat32(streamId, record.distance)
    streamWriteFloat32(streamId, record.driveTime)
    streamWriteFloat32(streamId, record.waitTime)
    streamWriteInt32(streamId, record.loads)
    streamWriteFloat32(streamId, record.unloaded)
    local names = {}
    for name, _ in pairs(record.fillTypes) do
        table.insert(names, name)
    end
    streamWriteUIntN(streamId, #names, 8)
    for _, name in ipairs(names) do
        streamWriteString(streamId, name)
        streamWriteFloat32(streamId, record.fillTypes[name])
    end
end

local function readRecord(streamId, record)
    record.distance = streamReadFloat32(streamId)
    record.driveTime = streamReadFloat32(streamId)
    record.waitTime = streamReadFloat32(streamId)
    record.loads = streamReadInt32(streamId)
    record.unloaded = streamReadFloat32(streamId)
    local count = streamReadUIntN(streamId, 8)
    for _ = 1, count do
        local name = streamReadString(streamId)
        record.fillTypes[name] = streamReadFloat32(streamId)
    end
end

function ADStatistics.writeStream(streamId, stats)
    writeRecord(streamId, stats)
    local days = {}
    for day, _ in pairs(stats.days) do
        table.insert(days, day)
    end
    streamWriteUIntN(streamId, #days, 4)
    for _, day in ipairs(days) do
        streamWriteInt32(streamId, day)
        writeRecord(streamId, stats.days[day])
    end
end

function ADStatistics.readStream(streamId)
    local stats = ADStatistics.newStats()
    readRecord(streamId, stats)
    local count = streamReadUIntN(streamId, 4)
    for _ = 1, count do
        local day = streamReadInt32(streamId)
        local record = ADStatistics.newRecord()
        readRecord(streamId, record)
        stats.days[day] = record
    end
    return stats
end

-------------------------------------------------------------------------------
-- display
-------------------------------------------------------------------------------

-- 5400000 ms -> "1:30 h"
function ADStatistics.formatTime(ms)
    local minutes = math.floor(ms / 60000)
    return string.format("%d:%02d h", math.floor(minutes / 60), minutes % 60)
end

-- current price per litre: the best selling point, else the base price of the fill type
function ADStatistics.getPricePerLitre(fillTypeName)
    local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
    if fillTypeIndex == nil then
        return 0
    end
    local best = 0
    for _, station in ipairs(ADBestPrice.getStations(fillTypeIndex)) do
        best = math.max(best, station.price or 0)
    end
    if best <= 0 then
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        if fillType ~= nil and fillType.pricePerLiter ~= nil then
            best = fillType.pricePerLiter
        end
    end
    return best
end

function ADStatistics.getIncome(record)
    local income = 0
    for name, litres in pairs(record.fillTypes) do
        income = income + litres * ADStatistics.getPricePerLitre(name)
    end
    return income
end

function ADStatistics.getFillTypeTitle(name)
    local fillType = g_fillTypeManager:getFillTypeByName(name)
    if fillType ~= nil and fillType.title ~= nil then
        return fillType.title
    end
    return name
end

-- e.g. "123.4 km  |  driving 5:20 h  |  waiting 1:10 h (18%)  |  deliveries: 12  |  345600 l unloaded
--       |  Wheat 200000 l, Barley 145600 l  |  ~ 123,456 $"
function ADStatistics.getText(record)
    if record == nil then
        record = ADStatistics.newRecord()
    end
    local total = record.driveTime + record.waitTime
    local waitPercent = 0
    if total > 0 then
        waitPercent = math.floor(100 * record.waitTime / total + 0.5)
    end
    local parts = {
        string.format("%.1f km", record.distance / 1000),
        string.format(g_i18n:getText("AD_stats_driving"), ADStatistics.formatTime(record.driveTime)),
        string.format(g_i18n:getText("AD_stats_waiting"), ADStatistics.formatTime(record.waitTime), waitPercent .. "%"),
        string.format(g_i18n:getText("AD_stats_loads"), record.loads),
        string.format(g_i18n:getText("AD_stats_unloaded"), string.format("%d l", math.floor(record.unloaded + 0.5)))
    }
    local names = {}
    for name, _ in pairs(record.fillTypes or {}) do
        table.insert(names, name)
    end
    if #names > 0 then
        table.sort(names, function(a, b)
            return record.fillTypes[a] > record.fillTypes[b]
        end)
        local fillTypeParts = {}
        for i = 1, math.min(#names, ADStatistics.SHOWN_FILL_TYPES) do
            table.insert(fillTypeParts, string.format("%s %d l", ADStatistics.getFillTypeTitle(names[i]), math.floor(record.fillTypes[names[i]] + 0.5)))
        end
        table.insert(parts, table.concat(fillTypeParts, ", "))
        table.insert(parts, string.format(g_i18n:getText("AD_stats_income"), g_i18n:formatMoney(ADStatistics.getIncome(record), 0, true, true)))
    end
    return table.concat(parts, "  |  ")
end
