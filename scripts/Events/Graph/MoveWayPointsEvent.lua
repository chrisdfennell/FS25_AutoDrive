-- moves several waypoints at once (tidy-up tools), as one undo step
AutoDriveMoveWayPointsEvent = {}
AutoDriveMoveWayPointsEvent_mt = Class(AutoDriveMoveWayPointsEvent, Event)

InitEventClass(AutoDriveMoveWayPointsEvent, "AutoDriveMoveWayPointsEvent")

function AutoDriveMoveWayPointsEvent.emptyNew()
    local self = Event.new(AutoDriveMoveWayPointsEvent_mt)
    return self
end

-- moves: list of {id, x, y, z}
function AutoDriveMoveWayPointsEvent.new(moves)
    local self = AutoDriveMoveWayPointsEvent.emptyNew()
    self.moves = moves
    return self
end

function AutoDriveMoveWayPointsEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, #self.moves, 20)
    for _, move in ipairs(self.moves) do
        streamWriteUIntN(streamId, move.id, 20)
        streamWriteFloat32(streamId, move.x)
        streamWriteFloat32(streamId, move.y)
        streamWriteFloat32(streamId, move.z)
    end
end

function AutoDriveMoveWayPointsEvent:readStream(streamId, connection)
    local count = streamReadUIntN(streamId, 20)
    self.moves = {}
    for i = 1, count do
        local id = streamReadUIntN(streamId, 20)
        local x = streamReadFloat32(streamId)
        local y = streamReadFloat32(streamId)
        local z = streamReadFloat32(streamId)
        self.moves[i] = {id = id, x = x, y = y, z = z}
    end
    self:run(connection)
end

function AutoDriveMoveWayPointsEvent:run(connection)
    if g_server ~= nil and connection:getIsServer() == false then
        -- If the event is coming from a client, server have only to broadcast
        AutoDriveMoveWayPointsEvent.sendEvent(self.moves)
    else
        -- If the event is coming from the server, both clients and server have to move the way points
        ADGraphManager:moveWayPoints(self.moves, false)
    end
end

function AutoDriveMoveWayPointsEvent.sendEvent(moves)
    local event = AutoDriveMoveWayPointsEvent.new(moves)
    if g_server ~= nil then
        -- Server have to broadcast to all clients and himself
        g_server:broadcastEvent(event, true)
    else
        -- Client have to send to server
        g_client:getServerConnection():sendEvent(event)
    end
end
