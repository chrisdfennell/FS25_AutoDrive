AutoDriveUndoRedoEvent = {}
AutoDriveUndoRedoEvent_mt = Class(AutoDriveUndoRedoEvent, Event)

-- client -> server
AutoDriveUndoRedoEvent.TYPE_REQUEST_UNDO = 1
AutoDriveUndoRedoEvent.TYPE_REQUEST_REDO = 2
-- server -> clients
AutoDriveUndoRedoEvent.TYPE_APPLY = 3
AutoDriveUndoRedoEvent.TYPE_FEEDBACK = 4
-- client -> server
AutoDriveUndoRedoEvent.TYPE_REQUEST_PREVIEW = 5
-- server -> client
AutoDriveUndoRedoEvent.TYPE_PREVIEW = 6
-- client -> server
AutoDriveUndoRedoEvent.TYPE_REQUEST_STATE = 7
-- server -> client
AutoDriveUndoRedoEvent.TYPE_STATE = 8
AutoDriveUndoRedoEvent.TYPE_NOTICE = 9

InitEventClass(AutoDriveUndoRedoEvent, "AutoDriveUndoRedoEvent")

function AutoDriveUndoRedoEvent.emptyNew()
    local self = Event.new(AutoDriveUndoRedoEvent_mt)
    return self
end

function AutoDriveUndoRedoEvent.newRequest(requestType)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = requestType
    return self
end

function AutoDriveUndoRedoEvent.newApply(instructions, extraPoints)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = AutoDriveUndoRedoEvent.TYPE_APPLY
    self.instructions = instructions
    self.points = extraPoints or {}
    return self
end

function AutoDriveUndoRedoEvent.newFeedback(textKey, undoCount, redoCount, parts)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = AutoDriveUndoRedoEvent.TYPE_FEEDBACK
    self.textKey = textKey
    self.undoCount = undoCount
    self.redoCount = redoCount
    self.parts = parts or {}
    return self
end

function AutoDriveUndoRedoEvent.newPreview(textKey, parts, points)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = AutoDriveUndoRedoEvent.TYPE_PREVIEW
    self.textKey = textKey
    self.parts = parts or {}
    self.points = points or {}
    return self
end

function AutoDriveUndoRedoEvent.newState(canUndo, canRedo)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = AutoDriveUndoRedoEvent.TYPE_STATE
    self.canUndo = canUndo
    self.canRedo = canRedo
    return self
end

function AutoDriveUndoRedoEvent.newNotice(reason)
    local self = AutoDriveUndoRedoEvent.emptyNew()
    self.eventType = AutoDriveUndoRedoEvent.TYPE_NOTICE
    self.textKey = reason
    return self
end

local function writeIds(streamId, ids)
    streamWriteUInt16(streamId, #ids)
    for _, id in ipairs(ids) do
        streamWriteInt32(streamId, id)
    end
end

local function readIds(streamId)
    local ids = {}
    local count = streamReadUInt16(streamId)
    for i = 1, count do
        ids[i] = streamReadInt32(streamId)
    end
    return ids
end

local function writeWayPointData(streamId, data)
    streamWriteInt32(streamId, data.id)
    streamWriteFloat32(streamId, data.x)
    streamWriteFloat32(streamId, data.y)
    streamWriteFloat32(streamId, data.z)
    streamWriteInt32(streamId, data.flags)
    writeIds(streamId, data.out)
    writeIds(streamId, data.incoming)
end

local function readWayPointData(streamId)
    local data = {}
    data.id = streamReadInt32(streamId)
    data.x = streamReadFloat32(streamId)
    data.y = streamReadFloat32(streamId)
    data.z = streamReadFloat32(streamId)
    data.flags = streamReadInt32(streamId)
    data.out = readIds(streamId)
    data.incoming = readIds(streamId)
    return data
end

local function writeParts(streamId, parts)
    streamWriteUInt8(streamId, #parts)
    for _, part in ipairs(parts) do
        AutoDrive.streamWriteStringOrEmpty(streamId, part.key)
        streamWriteUInt8(streamId, #part.args)
        for _, arg in ipairs(part.args) do
            AutoDrive.streamWriteStringOrEmpty(streamId, tostring(arg))
        end
    end
end

local function readParts(streamId)
    local parts = {}
    local partCount = streamReadUInt8(streamId)
    for i = 1, partCount do
        local part = {key = AutoDrive.streamReadStringOrEmpty(streamId), args = {}}
        local argCount = streamReadUInt8(streamId)
        for a = 1, argCount do
            part.args[a] = AutoDrive.streamReadStringOrEmpty(streamId)
        end
        parts[i] = part
    end
    return parts
end

local function writePoints(streamId, points)
    streamWriteUInt16(streamId, #points)
    for _, point in ipairs(points) do
        streamWriteFloat32(streamId, point.x)
        streamWriteFloat32(streamId, point.y)
        streamWriteFloat32(streamId, point.z)
        streamWriteUInt8(streamId, point.kind)
        if streamWriteBool(streamId, point.fromX ~= nil) then
            streamWriteFloat32(streamId, point.fromX)
            streamWriteFloat32(streamId, point.fromY)
            streamWriteFloat32(streamId, point.fromZ)
        end
    end
end

local function readPoints(streamId)
    local points = {}
    local count = streamReadUInt16(streamId)
    for i = 1, count do
        local point = {x = streamReadFloat32(streamId), y = streamReadFloat32(streamId), z = streamReadFloat32(streamId), kind = streamReadUInt8(streamId)}
        if streamReadBool(streamId) then
            point.fromX = streamReadFloat32(streamId)
            point.fromY = streamReadFloat32(streamId)
            point.fromZ = streamReadFloat32(streamId)
        end
        points[i] = point
    end
    return points
end

local function writeInstruction(streamId, ins)
    streamWriteUInt8(streamId, ins.type)
    if ins.type == ADUndoManager.INS_APPEND_WP then
        writeWayPointData(streamId, ins.data)
    elseif ins.type == ADUndoManager.INS_POP_WP or ins.type == ADUndoManager.INS_REMOVE_WP then
        streamWriteInt32(streamId, ins.id)
    elseif ins.type == ADUndoManager.INS_INSERT_WP then
        streamWriteInt32(streamId, ins.id)
        writeWayPointData(streamId, ins.data)
        streamWriteInt32(streamId, #ins.refs)
        for _, ref in ipairs(ins.refs) do
            streamWriteInt32(streamId, ref.nodeId)
            streamWriteBool(streamId, ref.isOut)
            streamWriteUInt16(streamId, ref.pos)
        end
        writeIds(streamId, ins.markers or {})
    elseif ins.type == ADUndoManager.INS_SET_LINKS then
        streamWriteInt32(streamId, ins.id)
        writeIds(streamId, ins.out)
        writeIds(streamId, ins.incoming)
    elseif ins.type == ADUndoManager.INS_SET_WP_DATA then
        streamWriteInt32(streamId, ins.id)
        streamWriteFloat32(streamId, ins.x)
        streamWriteFloat32(streamId, ins.y)
        streamWriteFloat32(streamId, ins.z)
        streamWriteInt32(streamId, ins.flags)
    elseif ins.type == ADUndoManager.INS_INSERT_MARKER then
        streamWriteInt32(streamId, ins.index)
        streamWriteInt32(streamId, ins.data.id)
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.data.name)
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.data.group)
        streamWriteBool(streamId, ins.data.isADDebug == true)
    elseif ins.type == ADUndoManager.INS_REMOVE_MARKER then
        streamWriteInt32(streamId, ins.index)
    elseif ins.type == ADUndoManager.INS_SET_MARKER then
        streamWriteInt32(streamId, ins.index)
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.name)
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.group)
    elseif ins.type == ADUndoManager.INS_REPLACE_NETWORK then
        local network = ins.network
        AutoDriveSync.streamWriteGraph(streamId, network.wayPoints, network.mapMarkers, network.groups, network.groupColors)
    elseif ins.type == ADUndoManager.INS_ADD_GROUP then
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.name)
        streamWriteInt32(streamId, ins.id)
    elseif ins.type == ADUndoManager.INS_REMOVE_GROUP then
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.name)
    elseif ins.type == ADUndoManager.INS_RENAME_GROUPS then
        streamWriteUInt16(streamId, #ins.pairs)
        for _, pair in ipairs(ins.pairs) do
            AutoDrive.streamWriteStringOrEmpty(streamId, pair.from)
            AutoDrive.streamWriteStringOrEmpty(streamId, pair.to)
        end
    elseif ins.type == ADUndoManager.INS_SET_GROUP_COLOR then
        AutoDrive.streamWriteStringOrEmpty(streamId, ins.name)
        if streamWriteBool(streamId, ins.color ~= nil) then
            streamWriteFloat32(streamId, ins.color[1])
            streamWriteFloat32(streamId, ins.color[2])
            streamWriteFloat32(streamId, ins.color[3])
        end
    end
end

local function readInstruction(streamId)
    local ins = {type = streamReadUInt8(streamId)}
    if ins.type == ADUndoManager.INS_APPEND_WP then
        ins.data = readWayPointData(streamId)
    elseif ins.type == ADUndoManager.INS_POP_WP or ins.type == ADUndoManager.INS_REMOVE_WP then
        ins.id = streamReadInt32(streamId)
    elseif ins.type == ADUndoManager.INS_INSERT_WP then
        ins.id = streamReadInt32(streamId)
        ins.data = readWayPointData(streamId)
        ins.refs = {}
        local refCount = streamReadInt32(streamId)
        for r = 1, refCount do
            ins.refs[r] = {nodeId = streamReadInt32(streamId), isOut = streamReadBool(streamId), pos = streamReadUInt16(streamId)}
        end
        ins.markers = readIds(streamId)
    elseif ins.type == ADUndoManager.INS_SET_LINKS then
        ins.id = streamReadInt32(streamId)
        ins.out = readIds(streamId)
        ins.incoming = readIds(streamId)
    elseif ins.type == ADUndoManager.INS_SET_WP_DATA then
        ins.id = streamReadInt32(streamId)
        ins.x = streamReadFloat32(streamId)
        ins.y = streamReadFloat32(streamId)
        ins.z = streamReadFloat32(streamId)
        ins.flags = streamReadInt32(streamId)
    elseif ins.type == ADUndoManager.INS_INSERT_MARKER then
        ins.index = streamReadInt32(streamId)
        ins.data = {id = streamReadInt32(streamId)}
        ins.data.name = AutoDrive.streamReadStringOrEmpty(streamId)
        ins.data.group = AutoDrive.streamReadStringOrEmpty(streamId)
        ins.data.isADDebug = streamReadBool(streamId)
    elseif ins.type == ADUndoManager.INS_REMOVE_MARKER then
        ins.index = streamReadInt32(streamId)
    elseif ins.type == ADUndoManager.INS_SET_MARKER then
        ins.index = streamReadInt32(streamId)
        ins.name = AutoDrive.streamReadStringOrEmpty(streamId)
        ins.group = AutoDrive.streamReadStringOrEmpty(streamId)
    elseif ins.type == ADUndoManager.INS_REPLACE_NETWORK then
        local wayPoints, mapMarkers, groups, groupColors = AutoDriveSync.streamReadGraph(streamId)
        ins.network = {wayPoints = wayPoints, mapMarkers = mapMarkers, groups = groups, groupColors = groupColors}
    elseif ins.type == ADUndoManager.INS_ADD_GROUP then
        ins.name = AutoDrive.streamReadStringOrEmpty(streamId)
        ins.id = streamReadInt32(streamId)
    elseif ins.type == ADUndoManager.INS_REMOVE_GROUP then
        ins.name = AutoDrive.streamReadStringOrEmpty(streamId)
    elseif ins.type == ADUndoManager.INS_RENAME_GROUPS then
        ins.pairs = {}
        local count = streamReadUInt16(streamId)
        for i = 1, count do
            ins.pairs[i] = {from = AutoDrive.streamReadStringOrEmpty(streamId), to = AutoDrive.streamReadStringOrEmpty(streamId)}
        end
    elseif ins.type == ADUndoManager.INS_SET_GROUP_COLOR then
        ins.name = AutoDrive.streamReadStringOrEmpty(streamId)
        if streamReadBool(streamId) then
            ins.color = {streamReadFloat32(streamId), streamReadFloat32(streamId), streamReadFloat32(streamId)}
        end
    end
    return ins
end

function AutoDriveUndoRedoEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.eventType)
    if self.eventType == AutoDriveUndoRedoEvent.TYPE_APPLY then
        streamWriteInt32(streamId, #self.instructions)
        for _, ins in ipairs(self.instructions) do
            writeInstruction(streamId, ins)
        end
        writePoints(streamId, self.points)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_FEEDBACK then
        AutoDrive.streamWriteStringOrEmpty(streamId, self.textKey)
        streamWriteInt32(streamId, self.undoCount)
        streamWriteInt32(streamId, self.redoCount)
        writeParts(streamId, self.parts)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_PREVIEW then
        AutoDrive.streamWriteStringOrEmpty(streamId, self.textKey)
        writeParts(streamId, self.parts)
        writePoints(streamId, self.points)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_STATE then
        streamWriteBool(streamId, self.canUndo)
        streamWriteBool(streamId, self.canRedo)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_NOTICE then
        AutoDrive.streamWriteStringOrEmpty(streamId, self.textKey)
    end
end

function AutoDriveUndoRedoEvent:readStream(streamId, connection)
    self.eventType = streamReadUInt8(streamId)
    if self.eventType == AutoDriveUndoRedoEvent.TYPE_APPLY then
        self.instructions = {}
        local count = streamReadInt32(streamId)
        for i = 1, count do
            self.instructions[i] = readInstruction(streamId)
        end
        self.points = readPoints(streamId)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_FEEDBACK then
        self.textKey = AutoDrive.streamReadStringOrEmpty(streamId)
        self.undoCount = streamReadInt32(streamId)
        self.redoCount = streamReadInt32(streamId)
        self.parts = readParts(streamId)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_PREVIEW then
        self.textKey = AutoDrive.streamReadStringOrEmpty(streamId)
        self.parts = readParts(streamId)
        self.points = readPoints(streamId)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_STATE then
        self.canUndo = streamReadBool(streamId)
        self.canRedo = streamReadBool(streamId)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_NOTICE then
        self.textKey = AutoDrive.streamReadStringOrEmpty(streamId)
    end
    self:run(connection)
end

function AutoDriveUndoRedoEvent:run(connection)
    if self.eventType == AutoDriveUndoRedoEvent.TYPE_REQUEST_UNDO then
        if g_server ~= nil then
            ADUndoManager:undo(connection)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_REQUEST_REDO then
        if g_server ~= nil then
            ADUndoManager:redo(connection)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_REQUEST_PREVIEW then
        if g_server ~= nil then
            ADUndoManager:sendPreview(connection)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_REQUEST_STATE then
        if g_server ~= nil then
            ADUndoManager:sendState(connection)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_APPLY then
        if g_server == nil then
            ADUndoManager:executeInstructions(self.instructions, self.points)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_FEEDBACK then
        ADUndoManager.showFeedback(self.textKey, self.undoCount, self.redoCount, self.parts)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_PREVIEW then
        ADUndoManager:showPreview(self.textKey, self.parts, self.points)
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_STATE then
        if g_server == nil then
            ADUndoManager:setClientAvailability(self.canUndo, self.canRedo)
        end
    elseif self.eventType == AutoDriveUndoRedoEvent.TYPE_NOTICE then
        if g_server == nil then
            -- the server shows it itself
            ADUndoManager.showNotice(self.textKey)
        end
    end
end
