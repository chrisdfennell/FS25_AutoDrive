-- fleet overview: send a vehicle to a destination without getting in (drive to mode, then start)
AutoDriveSendToEvent = {}
AutoDriveSendToEvent_mt = Class(AutoDriveSendToEvent, Event)

InitEventClass(AutoDriveSendToEvent, "AutoDriveSendToEvent")

function AutoDriveSendToEvent.emptyNew()
    local self = Event.new(AutoDriveSendToEvent_mt)
    return self
end

function AutoDriveSendToEvent.new(vehicle, markerIndex, farmId)
    local self = AutoDriveSendToEvent.emptyNew()
    self.vehicle = vehicle
    self.markerIndex = markerIndex
    self.farmId = farmId or 0
    return self
end

function AutoDriveSendToEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(self.vehicle))
    streamWriteUIntN(streamId, self.markerIndex, 20)
    streamWriteUIntN(streamId, self.farmId, 8)
end

function AutoDriveSendToEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.getObject(NetworkUtil.readNodeObjectId(streamId))
    self.markerIndex = streamReadUIntN(streamId, 20)
    self.farmId = streamReadUIntN(streamId, 8)
    self:run(connection)
end

function AutoDriveSendToEvent:run(connection)
    if g_server ~= nil then
        AutoDriveSendToEvent.apply(self.vehicle, self.markerIndex, self.farmId)
    end
end

-- server: like the park key, switch to drive to with the new destination and (re)start
function AutoDriveSendToEvent.apply(vehicle, markerIndex, farmId)
    if vehicle == nil or vehicle.ad == nil or ADGraphManager:getMapMarkerById(markerIndex) == nil then
        return
    end
    if farmId == nil or farmId == 0 then
        farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    end
    AutoDrive:StopCP(vehicle)
    if vehicle.ad.stateModule:isActive() then
        ADInputManager:input_start_stop(vehicle, farmId)
    end
    vehicle.ad.stateModule:setMode(AutoDrive.MODE_DRIVETO)
    vehicle.ad.stateModule:setFirstMarker(markerIndex)
    ADInputManager:input_start_stop(vehicle, farmId)
    AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_sendTo_driving; %s", 5000, vehicle.ad.stateModule:getName(), ADGraphManager:getMapMarkerById(markerIndex).name)
end

function AutoDriveSendToEvent.sendEvent(vehicle, markerIndex)
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or 0
    if g_server ~= nil then
        AutoDriveSendToEvent.apply(vehicle, markerIndex, farmId)
    else
        g_client:getServerConnection():sendEvent(AutoDriveSendToEvent.new(vehicle, markerIndex, farmId))
    end
end
