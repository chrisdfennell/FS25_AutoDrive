-- route check fixes (ADRouteCheck.applyFix): a client asks the server, the server applies the fix as one
-- undo step and tells all clients to do the same
AutoDriveRouteFixEvent = {}
AutoDriveRouteFixEvent_mt = Class(AutoDriveRouteFixEvent, Event)

InitEventClass(AutoDriveRouteFixEvent, "AutoDriveRouteFixEvent")

function AutoDriveRouteFixEvent.emptyNew()
    local self = Event.new(AutoDriveRouteFixEvent_mt)
    return self
end

function AutoDriveRouteFixEvent.new(fixType, a, b)
    local self = AutoDriveRouteFixEvent.emptyNew()
    self.fixType = fixType
    self.a = a
    self.b = b or 0
    return self
end

function AutoDriveRouteFixEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.fixType, 3)
    streamWriteUIntN(streamId, self.a, 20)
    streamWriteUIntN(streamId, self.b, 20)
end

function AutoDriveRouteFixEvent:readStream(streamId, connection)
    self.fixType = streamReadUIntN(streamId, 3)
    self.a = streamReadUIntN(streamId, 20)
    self.b = streamReadUIntN(streamId, 20)
    self:run(connection)
end

function AutoDriveRouteFixEvent:run(connection)
    if g_server ~= nil then
        AutoDriveRouteFixEvent.applyOnServer(self.fixType, self.a, self.b)
    else
        ADRouteCheck.applyFix(self.fixType, self.a, self.b)
    end
end

function AutoDriveRouteFixEvent.applyOnServer(fixType, a, b)
    ADUndoManager:beginStep()
    ADRouteCheck.applyFix(fixType, a, b)
    ADUndoManager:endStep()
    g_server:broadcastEvent(AutoDriveRouteFixEvent.new(fixType, a, b), false)
end

function AutoDriveRouteFixEvent.sendEvent(fixType, a, b)
    if g_server ~= nil then
        AutoDriveRouteFixEvent.applyOnServer(fixType, a, b)
    else
        g_client:getServerConnection():sendEvent(AutoDriveRouteFixEvent.new(fixType, a, b))
    end
end
