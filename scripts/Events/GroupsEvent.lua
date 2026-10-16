AutoDriveGroupsEvent = {}
AutoDriveGroupsEvent.TYPE_ADD = 0
AutoDriveGroupsEvent.TYPE_REMOVE = 1
AutoDriveGroupsEvent.TYPE_RENAME = 2
AutoDriveGroupsEvent.TYPE_SET_COLOR = 3
AutoDriveGroupsEvent_mt = Class(AutoDriveGroupsEvent, Event)

InitEventClass(AutoDriveGroupsEvent, "AutoDriveGroupsEvent")

function AutoDriveGroupsEvent.emptyNew()
	local self = Event.new(AutoDriveGroupsEvent_mt)
	return self
end

-- newGroupName is only used for TYPE_RENAME, color ({r, g, b} or nil for default) only for TYPE_SET_COLOR
function AutoDriveGroupsEvent.new(groupName, eventType, newGroupName, color)
	local self = AutoDriveGroupsEvent.emptyNew()
	self.groupName = groupName
	self.eventType = eventType
	self.newGroupName = newGroupName
	self.color = color
	return self
end

function AutoDriveGroupsEvent:writeStream(streamId, connection)
	streamWriteUInt8(streamId, self.eventType)
	AutoDrive.streamWriteStringOrEmpty(streamId, self.groupName)
	if self.eventType == AutoDriveGroupsEvent.TYPE_RENAME then
		AutoDrive.streamWriteStringOrEmpty(streamId, self.newGroupName)
	elseif self.eventType == AutoDriveGroupsEvent.TYPE_SET_COLOR then
		if streamWriteBool(streamId, self.color ~= nil) then
			streamWriteFloat32(streamId, self.color[1])
			streamWriteFloat32(streamId, self.color[2])
			streamWriteFloat32(streamId, self.color[3])
		end
	end
end

function AutoDriveGroupsEvent:readStream(streamId, connection)
	self.eventType = streamReadUInt8(streamId)
	self.groupName = streamReadString(streamId)
	if self.eventType == AutoDriveGroupsEvent.TYPE_RENAME then
		self.newGroupName = streamReadString(streamId)
	elseif self.eventType == AutoDriveGroupsEvent.TYPE_SET_COLOR then
		if streamReadBool(streamId) then
			self.color = {streamReadFloat32(streamId), streamReadFloat32(streamId), streamReadFloat32(streamId)}
		end
	end
	self:run(connection)
end

function AutoDriveGroupsEvent:run(connection)
	if g_server ~= nil and connection:getIsServer() == false then
		-- If the event is coming from a client, server have only to broadcast
		AutoDriveGroupsEvent.sendEvent(self.groupName, self.eventType, self.newGroupName, self.color)
	else
		-- If the event is coming from the server, both clients and server have to do the job
		if self.eventType == AutoDriveGroupsEvent.TYPE_ADD then
			ADGraphManager:addGroup(self.groupName, false)
		elseif self.eventType == AutoDriveGroupsEvent.TYPE_REMOVE then
			ADGraphManager:removeGroup(self.groupName, false)
		elseif self.eventType == AutoDriveGroupsEvent.TYPE_RENAME then
			ADGraphManager:renameGroup(self.groupName, self.newGroupName, false)
		elseif self.eventType == AutoDriveGroupsEvent.TYPE_SET_COLOR then
			ADGraphManager:setGroupColor(self.groupName, self.color, false)
		end
	end
end

function AutoDriveGroupsEvent.sendEvent(groupName, eventType, newGroupName, color)
	local event = AutoDriveGroupsEvent.new(groupName, eventType, newGroupName, color)
	if g_server ~= nil then
		-- Server have to broadcast to all clients and himself
		g_server:broadcastEvent(event, true)
	else
		-- Client have to send to server
		g_client:getServerConnection():sendEvent(event)
	end
end
