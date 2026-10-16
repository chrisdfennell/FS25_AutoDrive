-- field points of one field (Ctrl+Shift+F), sent by the server to the clients after it changed its own network:
-- the old field points of the field are removed and a closed two-way loop through the points is added
AutoDriveFieldPointsEvent = {}
AutoDriveFieldPointsEvent_mt = Class(AutoDriveFieldPointsEvent, Event)

InitEventClass(AutoDriveFieldPointsEvent, "AutoDriveFieldPointsEvent")

function AutoDriveFieldPointsEvent.emptyNew()
    local self = Event.new(AutoDriveFieldPointsEvent_mt)
    return self
end

-- points: list of {x, y, z}
function AutoDriveFieldPointsEvent.new(fieldID, points)
    local self = AutoDriveFieldPointsEvent.emptyNew()
    self.fieldID = fieldID
    self.points = points
    return self
end

function AutoDriveFieldPointsEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.fieldID)
    streamWriteUIntN(streamId, #self.points, 20)
    for _, point in ipairs(self.points) do
        streamWriteFloat32(streamId, point.x)
        streamWriteFloat32(streamId, point.y)
        streamWriteFloat32(streamId, point.z)
    end
end

function AutoDriveFieldPointsEvent:readStream(streamId, connection)
    self.fieldID = streamReadInt32(streamId)
    local count = streamReadUIntN(streamId, 20)
    self.points = {}
    for i = 1, count do
        local x = streamReadFloat32(streamId)
        local y = streamReadFloat32(streamId)
        local z = streamReadFloat32(streamId)
        self.points[i] = {x = x, y = y, z = z}
    end
    self:run(connection)
end

function AutoDriveFieldPointsEvent:run(connection)
    if g_server == nil then
        ADGraphManager:replaceFieldWaypoints(self.fieldID, self.points, false)
    end
end

-- server only: to all clients, the server has changed its network already
function AutoDriveFieldPointsEvent.sendEvent(fieldID, points)
    if g_server ~= nil then
        g_server:broadcastEvent(AutoDriveFieldPointsEvent.new(fieldID, points), false)
    end
end
