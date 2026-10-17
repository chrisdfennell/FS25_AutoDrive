-- waypoint panel: several connections changed at once (direction of a whole road, or a connection removed).
-- A client asks the server, the server changes them as one undo step and tells all clients to do the same.
-- links: list of {a, b, direction}; direction as ADGraphManager:setConnectionBetween (1 forward, 2 backward,
-- 3 dual, 4 reverse) or REMOVE (no connection at all between a and b)
AutoDriveRoadEvent = {}
AutoDriveRoadEvent_mt = Class(AutoDriveRoadEvent, Event)

InitEventClass(AutoDriveRoadEvent, "AutoDriveRoadEvent")

AutoDriveRoadEvent.REMOVE = 5
AutoDriveRoadEvent.MAX_LINKS = 4095

function AutoDriveRoadEvent.emptyNew()
    local self = Event.new(AutoDriveRoadEvent_mt)
    return self
end

function AutoDriveRoadEvent.new(links)
    local self = AutoDriveRoadEvent.emptyNew()
    self.links = links or {}
    return self
end

function AutoDriveRoadEvent:writeStream(streamId, connection)
    local count = math.min(#self.links, AutoDriveRoadEvent.MAX_LINKS)
    streamWriteUIntN(streamId, count, 12)
    for i = 1, count do
        local link = self.links[i]
        streamWriteUIntN(streamId, link[1], 20)
        streamWriteUIntN(streamId, link[2], 20)
        streamWriteUIntN(streamId, link[3], 3)
    end
end

function AutoDriveRoadEvent:readStream(streamId, connection)
    self.links = {}
    for i = 1, streamReadUIntN(streamId, 12) do
        self.links[i] = {streamReadUIntN(streamId, 20), streamReadUIntN(streamId, 20), streamReadUIntN(streamId, 3)}
    end
    self:run(connection)
end

function AutoDriveRoadEvent:run(connection)
    if g_server ~= nil then
        AutoDriveRoadEvent.applyOnServer(self.links)
    else
        AutoDriveRoadEvent.apply(self.links)
    end
end

local function removeLinks(a, b)
    ADUndoManager:beginStep()
    local links = ADUndoManager:captureLinks(a, b)
    for _ = 1, 2 do
        table.removeValue(a.out, b.id)
        table.removeValue(a.incoming, b.id)
        table.removeValue(b.out, a.id)
        table.removeValue(b.incoming, a.id)
    end
    ADUndoManager:recordLinks(links)
    ADGraphManager:markChanges()
    ADUndoManager:endStep()
end

function AutoDriveRoadEvent.apply(links)
    for _, link in ipairs(links) do
        local a, b = ADGraphManager:getWayPointById(link[1]), ADGraphManager:getWayPointById(link[2])
        if a ~= nil and b ~= nil and a ~= b then
            if link[3] == AutoDriveRoadEvent.REMOVE then
                removeLinks(a, b)
            elseif link[3] >= 1 and link[3] <= 4 then
                ADGraphManager:setConnectionBetween(a, b, link[3], false)
            end
        end
    end
end

function AutoDriveRoadEvent.applyOnServer(links)
    ADUndoManager:beginStep()
    AutoDriveRoadEvent.apply(links)
    ADUndoManager:endStep()
    g_server:broadcastEvent(AutoDriveRoadEvent.new(links), false)
end

function AutoDriveRoadEvent.sendEvent(links)
    if #links == 0 then
        return
    end
    if g_server ~= nil then
        AutoDriveRoadEvent.applyOnServer(links)
    else
        g_client:getServerConnection():sendEvent(AutoDriveRoadEvent.new(links))
    end
end
