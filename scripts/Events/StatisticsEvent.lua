-- driver statistics for the fleet overview of a multiplayer client:
-- REQUEST (client -> server), REPLY (server -> that client, all AutoDrive vehicles), RESET (client -> server, one vehicle)
AutoDriveStatisticsEvent = {}
AutoDriveStatisticsEvent_mt = Class(AutoDriveStatisticsEvent, Event)

InitEventClass(AutoDriveStatisticsEvent, "AutoDriveStatisticsEvent")

AutoDriveStatisticsEvent.TYPE_REQUEST = 1
AutoDriveStatisticsEvent.TYPE_REPLY = 2
AutoDriveStatisticsEvent.TYPE_RESET = 3

function AutoDriveStatisticsEvent.emptyNew()
    local self = Event.new(AutoDriveStatisticsEvent_mt)
    return self
end

-- entries: for REPLY, list of {vehicle, stats}; vehicle: for RESET
function AutoDriveStatisticsEvent.new(eventType, entries, vehicle)
    local self = AutoDriveStatisticsEvent.emptyNew()
    self.eventType = eventType
    self.entries = entries or {}
    self.vehicle = vehicle
    return self
end

function AutoDriveStatisticsEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.eventType, 2)
    if self.eventType == AutoDriveStatisticsEvent.TYPE_REPLY then
        streamWriteUIntN(streamId, #self.entries, 12)
        for _, entry in ipairs(self.entries) do
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(entry.vehicle))
            streamWriteFloat32(streamId, entry.stats.distance)
            streamWriteFloat32(streamId, entry.stats.driveTime)
            streamWriteFloat32(streamId, entry.stats.waitTime)
            streamWriteInt32(streamId, entry.stats.loads)
            streamWriteFloat32(streamId, entry.stats.unloaded)
        end
    elseif self.eventType == AutoDriveStatisticsEvent.TYPE_RESET then
        NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.vehicle))
    end
end

function AutoDriveStatisticsEvent:readStream(streamId, connection)
    self.eventType = streamReadUIntN(streamId, 2)
    self.entries = {}
    if self.eventType == AutoDriveStatisticsEvent.TYPE_REPLY then
        local count = streamReadUIntN(streamId, 12)
        for i = 1, count do
            local vehicle = NetworkUtil.getObject(NetworkUtil.readNodeObjectId(streamId))
            local stats = ADStatistics.newStats()
            stats.distance = streamReadFloat32(streamId)
            stats.driveTime = streamReadFloat32(streamId)
            stats.waitTime = streamReadFloat32(streamId)
            stats.loads = streamReadInt32(streamId)
            stats.unloaded = streamReadFloat32(streamId)
            self.entries[i] = {vehicle = vehicle, stats = stats}
        end
    elseif self.eventType == AutoDriveStatisticsEvent.TYPE_RESET then
        self.vehicle = NetworkUtil.getObject(NetworkUtil.readNodeObjectId(streamId))
    end
    self:run(connection)
end

function AutoDriveStatisticsEvent:run(connection)
    if self.eventType == AutoDriveStatisticsEvent.TYPE_REPLY then
        for _, entry in ipairs(self.entries) do
            if entry.vehicle ~= nil and entry.vehicle.ad ~= nil then
                entry.vehicle.ad.stats = entry.stats
            end
        end
    elseif g_server ~= nil then
        if self.eventType == AutoDriveStatisticsEvent.TYPE_RESET and self.vehicle ~= nil and self.vehicle.ad ~= nil then
            ADStatistics.reset(self.vehicle)
        end
        -- answer with the current numbers, also after a reset
        connection:sendEvent(AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_REPLY, AutoDriveStatisticsEvent.getAllEntries()))
    end
end

function AutoDriveStatisticsEvent.getAllEntries()
    local entries = {}
    for _, vehicle in pairs(AutoDrive.getAllVehicles() or {}) do
        if vehicle.ad ~= nil and vehicle.ad.stats ~= nil then
            table.insert(entries, {vehicle = vehicle, stats = vehicle.ad.stats})
        end
    end
    return entries
end

-- client: ask for the numbers; server / single player: nothing to do, they are local
function AutoDriveStatisticsEvent.request()
    if g_server == nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_REQUEST))
    end
end

function AutoDriveStatisticsEvent.requestReset(vehicle)
    if g_server ~= nil then
        ADStatistics.reset(vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_RESET, nil, vehicle))
    end
end
