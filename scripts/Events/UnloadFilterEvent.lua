-- unload products (ADUnloadFilter):
--   VEHICLE (vehicle, products) and TARGET (target name, products): a client asks the server to change a list,
--       the server changes it and sends it to all clients
--   REQUEST (vehicle or nil): a client opening the dialog asks for the current lists, the server answers with
--       VEHICLE for the vehicle and ALL_TARGETS
AutoDriveUnloadFilterEvent = {}
AutoDriveUnloadFilterEvent_mt = Class(AutoDriveUnloadFilterEvent, Event)

InitEventClass(AutoDriveUnloadFilterEvent, "AutoDriveUnloadFilterEvent")

AutoDriveUnloadFilterEvent.TYPE_VEHICLE = 1
AutoDriveUnloadFilterEvent.TYPE_TARGET = 2
AutoDriveUnloadFilterEvent.TYPE_REQUEST = 3
AutoDriveUnloadFilterEvent.TYPE_ALL_TARGETS = 4

function AutoDriveUnloadFilterEvent.emptyNew()
    local self = Event.new(AutoDriveUnloadFilterEvent_mt)
    return self
end

-- products: list of fill type names; targets (ALL_TARGETS): name -> list
function AutoDriveUnloadFilterEvent.new(eventType, vehicle, targetName, products, targets)
    local self = AutoDriveUnloadFilterEvent.emptyNew()
    self.eventType = eventType
    self.vehicle = vehicle
    self.targetName = targetName or ""
    self.products = products or {}
    self.targets = targets or {}
    return self
end

local function writeList(streamId, list)
    streamWriteUIntN(streamId, #list, 10)
    for _, name in ipairs(list) do
        streamWriteString(streamId, name)
    end
end

local function readList(streamId)
    local list = {}
    for i = 1, streamReadUIntN(streamId, 10) do
        list[i] = streamReadString(streamId)
    end
    return list
end

function AutoDriveUnloadFilterEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.eventType, 3)
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE or self.eventType == AutoDriveUnloadFilterEvent.TYPE_REQUEST then
        streamWriteBool(streamId, self.vehicle ~= nil)
        if self.vehicle ~= nil then
            NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.vehicle))
        end
    end
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE then
        writeList(streamId, self.products)
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_TARGET then
        streamWriteString(streamId, self.targetName)
        writeList(streamId, self.products)
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_ALL_TARGETS then
        local names = {}
        for name, _ in pairs(self.targets) do
            table.insert(names, name)
        end
        streamWriteUIntN(streamId, #names, 12)
        for _, name in ipairs(names) do
            streamWriteString(streamId, name)
            writeList(streamId, self.targets[name])
        end
    end
end

function AutoDriveUnloadFilterEvent:readStream(streamId, connection)
    self.eventType = streamReadUIntN(streamId, 3)
    self.products = {}
    self.targets = {}
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE or self.eventType == AutoDriveUnloadFilterEvent.TYPE_REQUEST then
        if streamReadBool(streamId) then
            self.vehicle = NetworkUtil.getObject(NetworkUtil.readNodeObjectId(streamId))
        end
    end
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE then
        self.products = readList(streamId)
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_TARGET then
        self.targetName = streamReadString(streamId)
        self.products = readList(streamId)
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_ALL_TARGETS then
        for _ = 1, streamReadUIntN(streamId, 12) do
            local name = streamReadString(streamId)
            self.targets[name] = readList(streamId)
        end
    end
    self:run(connection)
end

function AutoDriveUnloadFilterEvent:run(connection)
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE then
        if self.vehicle ~= nil and self.vehicle.ad ~= nil then
            ADUnloadFilter.setVehicleFilter(self.vehicle, ADUnloadFilter.fromList(self.products))
        end
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_TARGET then
        ADUnloadFilter.setTargetFilter(self.targetName, ADUnloadFilter.fromList(self.products))
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_ALL_TARGETS then
        ADUnloadFilter.targetFilters = {}
        for name, list in pairs(self.targets) do
            ADUnloadFilter.setTargetFilter(name, ADUnloadFilter.fromList(list))
        end
    end
    if g_server == nil then
        return
    end
    if self.eventType == AutoDriveUnloadFilterEvent.TYPE_VEHICLE or self.eventType == AutoDriveUnloadFilterEvent.TYPE_TARGET then
        -- changed on the server: all clients get the new list
        g_server:broadcastEvent(AutoDriveUnloadFilterEvent.new(self.eventType, self.vehicle, self.targetName, self.products), false)
    elseif self.eventType == AutoDriveUnloadFilterEvent.TYPE_REQUEST and connection ~= nil then
        if self.vehicle ~= nil and self.vehicle.ad ~= nil then
            connection:sendEvent(AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_VEHICLE, self.vehicle, nil, ADUnloadFilter.toList(self.vehicle.ad.unloadFilter)))
        end
        local targets = {}
        for name, set in pairs(ADUnloadFilter.targetFilters) do
            targets[name] = ADUnloadFilter.toList(set)
        end
        connection:sendEvent(AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_ALL_TARGETS, nil, nil, nil, targets))
    end
end

local function send(event)
    if g_server ~= nil then
        event:run(nil)
    else
        g_client:getServerConnection():sendEvent(event)
    end
end

function AutoDriveUnloadFilterEvent.setVehicle(vehicle, set)
    send(AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_VEHICLE, vehicle, nil, ADUnloadFilter.toList(set)))
end

function AutoDriveUnloadFilterEvent.setTarget(name, set)
    send(AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_TARGET, nil, name, ADUnloadFilter.toList(set)))
end

function AutoDriveUnloadFilterEvent.request(vehicle)
    if g_server == nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_REQUEST, vehicle))
    end
end
