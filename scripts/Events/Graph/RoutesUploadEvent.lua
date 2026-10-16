AutoDriveRoutesUploadEvent = {}
AutoDriveRoutesUploadEvent_mt = Class(AutoDriveRoutesUploadEvent, Event)

InitEventClass(AutoDriveRoutesUploadEvent, "AutoDriveRoutesUploadEvent")

function AutoDriveRoutesUploadEvent.emptyNew()
	local self = Event.new(AutoDriveRoutesUploadEvent_mt)
	return self
end

function AutoDriveRoutesUploadEvent.new(wayPoints, mapMarkers, groups, groupColors)
	local self = AutoDriveRoutesUploadEvent.emptyNew()
	self.wayPoints = wayPoints
	self.mapMarkers = mapMarkers
	self.groups = groups
	self.groupColors = groupColors
	return self
end

function AutoDriveRoutesUploadEvent:writeStream(streamId, connection)
	AutoDriveSync.streamWriteGraph(streamId, self.wayPoints, self.mapMarkers, self.groups, self.groupColors)
end

function AutoDriveRoutesUploadEvent:readStream(streamId, connection)
	self.wayPoints, self.mapMarkers, self.groups, self.groupColors = AutoDriveSync.streamReadGraph(streamId)
	self:run(connection)
end

function AutoDriveRoutesUploadEvent:run(connection)
	if g_server ~= nil and connection:getIsServer() == false then
		-- If the event is coming from a client, server have only to broadcast
		AutoDriveRoutesUploadEvent.sendEvent(self.wayPoints, self.mapMarkers, self.groups, self.groupColors)
	else
		-- If the event is coming from the server, both clients and server have to delete the way point
		-- loading routes replaces the whole network, one undo brings the old one back
		ADUndoManager:beginStep()
		ADGraphManager:replaceNetwork(self.wayPoints, self.mapMarkers, self.groups, self.groupColors)
		ADUndoManager:endStep()
	end
end

function AutoDriveRoutesUploadEvent.sendEvent(wayPoints, mapMarkers, groups, groupColors)
	local event = AutoDriveRoutesUploadEvent.new(wayPoints, mapMarkers, groups, groupColors)
	if g_server ~= nil then
		-- Server have to broadcast to all clients and himself
		g_server:broadcastEvent(event, true)
	else
		-- Client have to send to server
		g_client:getServerConnection():sendEvent(event)
	end
end
