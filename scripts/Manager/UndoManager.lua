-- Undo / redo for route network edits
--
-- The history lives on the server only, as the server applies every network change anyway.
-- Each user action (one network event) becomes one undo step, a list of exact, invertible operations.
-- Undo / redo builds the instructions to revert / repeat a step, executes them on the server
-- and sends them to all clients, so the clients do not need a history of their own.
--
-- Every step belongs to the player who made it, each player undoes his own edits.
-- An older own edit can only be undone if the later edits of other players do not depend on it.
--
-- Changes which can not be tracked (debug markers, color selection points ...) clear the history,
-- as the stored waypoint ids and marker indices would not match anymore.

ADUndoManager = {}

ADUndoManager.MAX_STEPS = 100
-- repeated moves of the same waypoint within this time are one step
ADUndoManager.NUDGE_MERGE_TIME = 10000
-- distance removed by one undo while recording
ADUndoManager.RECORDING_UNDO_DISTANCE = 10
-- clients ask for their undo / redo availability (HUD buttons) in this interval
ADUndoManager.STATE_REQUEST_INTERVAL = 2000

ADUndoManager.LOCAL_OWNER_ID = "local"

-- operations stored in an undo step
ADUndoManager.OP_APPEND_WP = 1 -- new waypoint added at the end of the list
ADUndoManager.OP_REMOVE_WP = 2 -- waypoint removed, all ids above shifted down
ADUndoManager.OP_LINKS = 3 -- out / incoming connections of a waypoint changed
ADUndoManager.OP_WP_DATA = 4 -- position or flags of a waypoint changed
ADUndoManager.OP_APPEND_MARKER = 5
ADUndoManager.OP_REMOVE_MARKER = 6
ADUndoManager.OP_MARKER_DATA = 7 -- name or folder of a marker changed
ADUndoManager.OP_REPLACE_NETWORK = 8 -- routes loaded with the routes manager
ADUndoManager.OP_GROUP_ADD = 9
ADUndoManager.OP_GROUP_REMOVE = 10
ADUndoManager.OP_GROUP_RENAME = 11
ADUndoManager.OP_GROUP_COLOR = 12

-- operations which shift waypoint ids, marker indices or folder ids, such a step can not be reordered with others
ADUndoManager.STRUCTURAL_OPS = {
    [ADUndoManager.OP_APPEND_WP] = true,
    [ADUndoManager.OP_REMOVE_WP] = true,
    [ADUndoManager.OP_APPEND_MARKER] = true,
    [ADUndoManager.OP_REMOVE_MARKER] = true,
    [ADUndoManager.OP_REPLACE_NETWORK] = true,
    [ADUndoManager.OP_GROUP_ADD] = true,
    [ADUndoManager.OP_GROUP_REMOVE] = true,
    [ADUndoManager.OP_GROUP_RENAME] = true
}

-- instructions executed on server and clients
ADUndoManager.INS_APPEND_WP = 1
ADUndoManager.INS_POP_WP = 2
ADUndoManager.INS_REMOVE_WP = 3
ADUndoManager.INS_INSERT_WP = 4
ADUndoManager.INS_SET_LINKS = 5
ADUndoManager.INS_SET_WP_DATA = 6
ADUndoManager.INS_INSERT_MARKER = 7
ADUndoManager.INS_REMOVE_MARKER = 8
ADUndoManager.INS_SET_MARKER = 9
ADUndoManager.INS_REPLACE_NETWORK = 10
ADUndoManager.INS_ADD_GROUP = 11
ADUndoManager.INS_REMOVE_GROUP = 12
ADUndoManager.INS_RENAME_GROUPS = 13
ADUndoManager.INS_SET_GROUP_COLOR = 14

-- why the history was cleared, l10n keys
ADUndoManager.REASON_NETWORK = "AD_undo_reason_network"
ADUndoManager.REASON_DEBUG = "AD_undo_reason_debug"
ADUndoManager.REASON_COLORS = "AD_undo_reason_colors"
ADUndoManager.REASON_OTHER = "AD_undo_reason_other"

-- waypoints changed by undo / redo flash for a few seconds in the editor
ADUndoManager.HIGHLIGHT_ADDED = 1
ADUndoManager.HIGHLIGHT_CHANGED = 2
ADUndoManager.HIGHLIGHT_REMOVED = 3
ADUndoManager.HIGHLIGHT_COLORS = {
    [ADUndoManager.HIGHLIGHT_ADDED] = {0, 1, 0},
    [ADUndoManager.HIGHLIGHT_CHANGED] = {1, 0.75, 0},
    [ADUndoManager.HIGHLIGHT_REMOVED] = {1, 0, 1}
}
ADUndoManager.HIGHLIGHT_DURATION = 4000
ADUndoManager.HIGHLIGHT_MAX_POINTS = 200
ADUndoManager.HIGHLIGHT_BEACON_HEIGHT = 6
-- length of the line pointing from the vehicle to a change out of sight
ADUndoManager.POINTER_LENGTH = 25

ADUndoManager.MAX_DESCRIPTION_PARTS = 8

function ADUndoManager:load()
    self.undoStack = {}
    -- owner id -> list of undone steps
    self.redoStacks = {}
    self.depth = 0
    self.currentStep = nil
    self.group = nil
    self.applying = false
    self.suppressUntracked = false
    -- client connection of the event which is currently processed on the server
    self.actorConnection = nil
    self.highlights = nil
    self.previewWanted = nil
    self.clientCanUndo = false
    self.clientCanRedo = false
    self.stateRequestTimer = 0
end

-------------------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------------------

function ADUndoManager.copyIds(ids)
    local copy = {}
    if ids ~= nil then
        for i, id in ipairs(ids) do
            copy[i] = id
        end
    end
    return copy
end

function ADUndoManager.sameIds(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

function ADUndoManager.wayPointData(wp)
    return {id = wp.id, x = wp.x, y = wp.y, z = wp.z, flags = wp.flags or 0, out = ADUndoManager.copyIds(wp.out), incoming = ADUndoManager.copyIds(wp.incoming)}
end

function ADUndoManager.markerData(marker)
    return {id = marker.id, name = marker.name, group = marker.group, isADDebug = marker.isADDebug == true}
end

-------------------------------------------------------------------------------
-- diagnostics, multiplayer only: who made a step and who asked for an undo
-------------------------------------------------------------------------------

function ADUndoManager.isMultiplayer()
    local mission = g_currentMission
    if mission ~= nil and mission.missionDynamicInfo ~= nil and mission.missionDynamicInfo.isMultiplayer ~= nil then
        return mission.missionDynamicInfo.isMultiplayer == true
    end
    return g_server ~= nil and g_server.clientConnections ~= nil and table.count(g_server.clientConnections) > 1
end

-- all arguments are passed through tostring, names may contain anything
function ADUndoManager.log(text, ...)
    if not ADUndoManager.isMultiplayer() then
        return
    end
    local args = {...}
    for i = 1, select("#", ...) do
        args[i] = tostring(args[i])
    end
    Logging.info("[AD Undo] " .. text, unpack(args, 1, select("#", ...)))
end

function ADUndoManager.ownerText(owner)
    if owner == nil then
        return "nil"
    end
    return string.format("'%s' (%s)", tostring(owner.name), tostring(owner.id))
end

function ADUndoManager.partsText(parts)
    local texts = {}
    for _, part in ipairs(parts or {}) do
        local args = {}
        for _, arg in ipairs(part.args) do
            table.insert(args, tostring(arg))
        end
        table.insert(texts, part.key .. "(" .. table.concat(args, ",") .. ")")
    end
    return table.concat(texts, " ")
end

-- how a connection was identified, logged once per connection
ADUndoManager.loggedConnections = setmetatable({}, {__mode = "k"})

function ADUndoManager.logConnection(connection, owner)
    if ADUndoManager.loggedConnections[connection] or not ADUndoManager.isMultiplayer() then
        return
    end
    ADUndoManager.loggedConnections[connection] = true
    local mission = g_currentMission
    local userManager = mission ~= nil and mission.userManager or nil
    local isLocalFlag, userId, user = "n/a", "n/a", nil
    if connection.getIsLocal ~= nil then
        isLocalFlag = connection:getIsLocal()
    end
    if userManager ~= nil and userManager.getUserIdByConnection ~= nil then
        userId = userManager:getUserIdByConnection(connection)
    end
    if userManager ~= nil and userManager.getUserByConnection ~= nil then
        user = userManager:getUserByConnection(connection)
    end
    ADUndoManager.log(
        "connection %s: getIsLocal=%s streamId=%s userId=%s playerUserId=%s uniqueUserId=%s nickname=%s -> owner %s",
        connection,
        isLocalFlag,
        connection.streamId,
        userId,
        mission ~= nil and mission.playerUserId or nil,
        user ~= nil and user.uniqueUserId or nil,
        user ~= nil and user.nickname or nil,
        ADUndoManager.ownerText(owner)
    )
end

-------------------------------------------------------------------------------
-- owners
-------------------------------------------------------------------------------

function ADUndoManager.getLocalPlayerName()
    local mission = g_currentMission
    if mission ~= nil and mission.userManager ~= nil and mission.userManager.getUserByUserId ~= nil and mission.playerUserId ~= nil then
        local user = mission.userManager:getUserByUserId(mission.playerUserId)
        if user ~= nil and user.nickname ~= nil then
            return user.nickname
        end
    end
    return ""
end

function ADUndoManager.getLocalOwner()
    local owner = {id = ADUndoManager.LOCAL_OWNER_ID, name = ADUndoManager.getLocalPlayerName()}
    if not ADUndoManager.loggedLocalOwner and ADUndoManager.isMultiplayer() then
        ADUndoManager.loggedLocalOwner = true
        ADUndoManager.log("local player: playerUserId=%s name=%s", g_currentMission ~= nil and g_currentMission.playerUserId or nil, owner.name)
    end
    return owner
end

-- input events of the local player (single player or host) also come in through a client connection
function ADUndoManager.isLocalConnection(connection)
    if g_dedicatedServer ~= nil then
        return false
    end
    if connection.getIsLocal ~= nil and connection:getIsLocal() then
        return true
    end
    if NetworkNode ~= nil and NetworkNode.LOCAL_STREAM_ID ~= nil and connection.streamId == NetworkNode.LOCAL_STREAM_ID then
        return true
    end
    local mission = g_currentMission
    if mission ~= nil and mission.userManager ~= nil and mission.userManager.getUserIdByConnection ~= nil and mission.playerUserId ~= nil then
        return mission.userManager:getUserIdByConnection(connection) == mission.playerUserId
    end
    return false
end

-- connection nil is the local player (single player or host)
function ADUndoManager.getOwnerByConnection(connection)
    if connection == nil then
        return ADUndoManager.getLocalOwner()
    end
    local owner
    if ADUndoManager.isLocalConnection(connection) then
        owner = ADUndoManager.getLocalOwner()
    else
        local user = nil
        if g_currentMission ~= nil and g_currentMission.userManager ~= nil then
            user = g_currentMission.userManager:getUserByConnection(connection)
        end
        if user ~= nil and user.uniqueUserId ~= nil then
            owner = {id = user.uniqueUserId, name = user.nickname or ""}
        else
            owner = {id = tostring(connection), name = ""}
        end
    end
    ADUndoManager.logConnection(connection, owner)
    return owner
end

-- the player who made the change which is currently applied
function ADUndoManager:getActor()
    return ADUndoManager.getOwnerByConnection(self.actorConnection)
end

-- the graph events tell, which client a change came from
function ADUndoManager.installActorHooks()
    local eventClasses = {
        AutoDriveChangeMapMarkerGroupEvent,
        AutoDriveCreateMapMarkerEvent,
        CreatePlaceableEvent,
        CreateSplineConnectionEvent,
        AutoDriveCreateWayPointEvent,
        AutoDriveDeleteMapMarkerEvent,
        AutoDriveDeleteWayPointsEvent,
        AutoDriveMoveWayPointEvent,
        AutoDriveRenameMapMarkerEvent,
        AutoDriveRoutesUploadEvent,
        AutoDriveSectionEvent,
        AutoDriveSetConnectionEvent,
        AutoDriveToggleConnectionEvent,
        AutoDriveGroupsEvent,
        -- recording is started by input events
        AutoDriveInputEventEvent,
        AutoDriveHudInputEventEvent
    }
    for _, eventClass in pairs(eventClasses) do
        if eventClass ~= nil and eventClass.run ~= nil and not eventClass.adUndoActorHook then
            local originalRun = eventClass.run
            eventClass.run = function(self, connection, ...)
                local previous = ADUndoManager.actorConnection
                if g_server ~= nil and connection ~= nil and connection.getIsServer ~= nil and not connection:getIsServer() then
                    ADUndoManager.actorConnection = connection
                end
                local ok, err = pcall(originalRun, self, connection, ...)
                ADUndoManager.actorConnection = previous
                if not ok then
                    error(err, 0)
                end
            end
            eventClass.adUndoActorHook = true
        end
    end
end

function ADUndoManager:countOwnSteps(owner)
    local count = 0
    for _, step in ipairs(self.undoStack) do
        if step.owner.id == owner.id then
            count = count + 1
        end
    end
    return count
end

function ADUndoManager:getRedoStack(owner)
    return self.redoStacks[owner.id] or {}
end

-- an undo / redo by one player makes the redo steps of the others invalid
function ADUndoManager:clearOtherRedoStacks(owner)
    local own = self.redoStacks[owner.id]
    self.redoStacks = {}
    self.redoStacks[owner.id] = own
end

function ADUndoManager:getAvailability(owner)
    return self:countOwnSteps(owner) > 0, #self:getRedoStack(owner) > 0
end

-------------------------------------------------------------------------------
-- recording the history
-------------------------------------------------------------------------------

function ADUndoManager:isRecording()
    return g_server ~= nil and self.depth > 0 and not self.applying and self.currentStep ~= nil
end

function ADUndoManager:hasHistory()
    if #self.undoStack > 0 then
        return true
    end
    for _, stack in pairs(self.redoStacks) do
        if #stack > 0 then
            return true
        end
    end
    return false
end

function ADUndoManager:clear(reason)
    local hadHistory = self:hasHistory()
    self.undoStack = {}
    self.redoStacks = {}
    if self.group ~= nil then
        self.group.marks = {}
    end
    if self.currentStep ~= nil then
        -- the step in progress can not be undone either
        self.currentStep.invalid = true
    end
    if hadHistory and reason ~= nil then
        self:notifyCleared(reason)
    end
end

-- a change to the network which is not recorded, the history does not match the network anymore
function ADUndoManager:onUntrackedChange(reason)
    if g_server ~= nil and not self.applying and not self.suppressUntracked then
        self:clear(reason or ADUndoManager.REASON_OTHER)
    end
end

-- every action which changes the network is wrapped in beginStep / endStep, nested calls end up in the same step
function ADUndoManager:beginStep()
    if g_server == nil or self.applying then
        return
    end
    self.depth = self.depth + 1
    if self.depth == 1 then
        self.currentStep = {ops = {}}
    end
end

function ADUndoManager:endStep()
    if g_server == nil or self.applying or self.depth == 0 then
        return
    end
    self.depth = self.depth - 1
    if self.depth > 0 then
        return
    end
    local step = self.currentStep
    self.currentStep = nil
    if step == nil or step.invalid or #step.ops == 0 then
        return
    end

    -- the redo steps do not fit to the network anymore
    self.redoStacks = {}

    local group = self:getActiveGroup()
    local lastStep = self.undoStack[#self.undoStack]
    if group ~= nil and lastStep ~= nil and lastStep.group == group then
        -- e.g. all waypoints of one recording drive are undone at once
        for _, op in ipairs(step.ops) do
            table.insert(lastStep.ops, op)
        end
        return
    end
    step.group = group
    if group ~= nil then
        step.owner = group.owner
    else
        step.owner = self:getActor()
    end
    step.time = g_time

    if group == nil and self:mergeNudge(lastStep, step) then
        return
    end

    table.insert(self.undoStack, step)
    while #self.undoStack > ADUndoManager.MAX_STEPS do
        table.remove(self.undoStack, 1)
    end
    ADUndoManager.log("step %s recorded for %s: %s", #self.undoStack, ADUndoManager.ownerText(step.owner), ADUndoManager.partsText(ADUndoManager.describeStep(step)))
end

-- a waypoint moved again shortly after the last move is merged into the last step
function ADUndoManager:mergeNudge(lastStep, step)
    local function singleMove(s)
        if s == nil or s.group ~= nil or #s.ops ~= 1 then
            return nil
        end
        local op = s.ops[1]
        if op.type ~= ADUndoManager.OP_WP_DATA or op.old.flags ~= op.new.flags then
            return nil
        end
        return op
    end
    local lastMove, move = singleMove(lastStep), singleMove(step)
    if lastMove == nil or move == nil or lastMove.id ~= move.id or lastStep.owner.id ~= step.owner.id then
        return false
    end
    if step.time - lastStep.time > ADUndoManager.NUDGE_MERGE_TIME then
        return false
    end
    lastMove.new = move.new
    lastStep.time = step.time
    if lastMove.old.x == lastMove.new.x and lastMove.old.y == lastMove.new.y and lastMove.old.z == lastMove.new.z then
        -- moved back to where it was
        table.remove(self.undoStack)
    end
    return true
end

-- all steps between beginGroup and endGroup are merged into one undo step
-- module: the recording module, it can drop its last points while recording
function ADUndoManager:beginGroup(vehicle, module)
    if g_server == nil then
        return nil
    end
    self.group = {vehicle = vehicle, module = module, owner = self:getActor(), marks = {}}
    ADUndoManager.log("recording started by %s", ADUndoManager.ownerText(self.group.owner))
    return self.group
end

function ADUndoManager:endGroup(group)
    if group ~= nil and self.group == group then
        self.group = nil
    end
end

function ADUndoManager:getActiveGroup()
    if self.group ~= nil and self.group.vehicle ~= nil and self.group.vehicle.isDeleted then
        -- vehicle removed while recording
        self.group = nil
    end
    return self.group
end

-- number of ops in the step of the group, nil before the first recorded point
function ADUndoManager:getGroupOpCount(group)
    local lastStep = self.undoStack[#self.undoStack]
    if group ~= nil and group == self.group and lastStep ~= nil and lastStep.group == group then
        return #lastStep.ops
    end
    return nil
end

-- the recording module marks every recorded point, an undo while recording goes back to a mark
function ADUndoManager:addGroupMark(group, opCount, state)
    local newCount = self:getGroupOpCount(group)
    if opCount ~= nil and newCount ~= nil and newCount > opCount then
        table.insert(group.marks, {opCount = opCount, state = state})
    end
end

function ADUndoManager:addOp(op)
    if self:isRecording() then
        table.insert(self.currentStep.ops, op)
    end
end

-- ops which can only be recorded inside a step, otherwise the history becomes invalid
function ADUndoManager:addOpOrInvalidate(op, reason)
    if self:isRecording() then
        table.insert(self.currentStep.ops, op)
    else
        self:onUntrackedChange(reason)
    end
end

function ADUndoManager:recordAppendWayPoint(wp)
    if self:isRecording() then
        self:addOp({type = ADUndoManager.OP_APPEND_WP, data = ADUndoManager.wayPointData(wp)})
    end
end

function ADUndoManager:recordRemoveWayPoint(data, refs, markers)
    self:addOp({type = ADUndoManager.OP_REMOVE_WP, id = data.id, data = data, refs = refs, markers = markers})
end

-- call before changing the connections of the given waypoints, pass the result to recordLinks afterwards
function ADUndoManager:captureLinks(...)
    if not self:isRecording() then
        return nil
    end
    local captured = {}
    for _, wp in pairs({...}) do
        if wp ~= nil and wp.id ~= nil and wp.id > 0 and captured[wp] == nil then
            captured[wp] = {out = ADUndoManager.copyIds(wp.out), incoming = ADUndoManager.copyIds(wp.incoming)}
        end
    end
    return captured
end

function ADUndoManager:recordLinks(captured)
    if captured == nil or not self:isRecording() then
        return
    end
    for wp, old in pairs(captured) do
        if not ADUndoManager.sameIds(old.out, wp.out) or not ADUndoManager.sameIds(old.incoming, wp.incoming) then
            self:addOp(
                {
                    type = ADUndoManager.OP_LINKS,
                    id = wp.id,
                    oldOut = old.out,
                    oldIncoming = old.incoming,
                    newOut = ADUndoManager.copyIds(wp.out),
                    newIncoming = ADUndoManager.copyIds(wp.incoming)
                }
            )
        end
    end
end

function ADUndoManager:recordWayPointData(id, old, new)
    if old.x ~= new.x or old.y ~= new.y or old.z ~= new.z or old.flags ~= new.flags then
        self:addOp({type = ADUndoManager.OP_WP_DATA, id = id, old = old, new = new})
    end
end

function ADUndoManager:recordAppendMarker(index, marker)
    if self:isRecording() then
        self:addOp({type = ADUndoManager.OP_APPEND_MARKER, index = index, data = ADUndoManager.markerData(marker)})
    end
end

function ADUndoManager:recordRemoveMarker(index, marker)
    if self:isRecording() then
        self:addOp({type = ADUndoManager.OP_REMOVE_MARKER, index = index, data = ADUndoManager.markerData(marker)})
    end
end

function ADUndoManager:recordMarkerData(index, oldName, oldGroup, newName, newGroup)
    if oldName ~= newName or oldGroup ~= newGroup then
        self:addOp({type = ADUndoManager.OP_MARKER_DATA, index = index, old = {name = oldName, group = oldGroup}, new = {name = newName, group = newGroup}})
    end
end

-- old / new: {wayPoints, mapMarkers, groups, groupColors}, the replaced tables are not changed anymore
function ADUndoManager:recordReplaceNetwork(old, new)
    self:addOp({type = ADUndoManager.OP_REPLACE_NETWORK, old = old, new = new})
end

function ADUndoManager:recordGroupAdd(name, id)
    self:addOpOrInvalidate({type = ADUndoManager.OP_GROUP_ADD, name = name, id = id})
end

-- markers: {{index, name}} of the markers in the folder, they are moved to "All"
function ADUndoManager:recordGroupRemove(name, id, color, markers)
    self:addOpOrInvalidate({type = ADUndoManager.OP_GROUP_REMOVE, name = name, id = id, color = color, markers = markers})
end

-- pairs: {{from, to}} of all renamed folders
function ADUndoManager:recordGroupRename(renamePairs)
    self:addOpOrInvalidate({type = ADUndoManager.OP_GROUP_RENAME, pairs = renamePairs})
end

function ADUndoManager:recordGroupColor(name, oldColor, newColor)
    self:addOpOrInvalidate({type = ADUndoManager.OP_GROUP_COLOR, name = name, old = oldColor, new = newColor})
end

-------------------------------------------------------------------------------
-- instructions
-------------------------------------------------------------------------------

function ADUndoManager.appendInstructions(instructions, op, undo)
    local function add(ins)
        table.insert(instructions, ins)
    end
    if op.type == ADUndoManager.OP_APPEND_WP then
        if undo then
            add({type = ADUndoManager.INS_POP_WP, id = op.data.id})
        else
            add({type = ADUndoManager.INS_APPEND_WP, data = op.data})
        end
    elseif op.type == ADUndoManager.OP_REMOVE_WP then
        if undo then
            add({type = ADUndoManager.INS_INSERT_WP, id = op.id, data = op.data, refs = op.refs, markers = op.markers})
        else
            add({type = ADUndoManager.INS_REMOVE_WP, id = op.id})
        end
    elseif op.type == ADUndoManager.OP_LINKS then
        if undo then
            add({type = ADUndoManager.INS_SET_LINKS, id = op.id, out = op.oldOut, incoming = op.oldIncoming})
        else
            add({type = ADUndoManager.INS_SET_LINKS, id = op.id, out = op.newOut, incoming = op.newIncoming})
        end
    elseif op.type == ADUndoManager.OP_WP_DATA then
        local data = undo and op.old or op.new
        add({type = ADUndoManager.INS_SET_WP_DATA, id = op.id, x = data.x, y = data.y, z = data.z, flags = data.flags})
    elseif op.type == ADUndoManager.OP_APPEND_MARKER or op.type == ADUndoManager.OP_REMOVE_MARKER then
        local insert = (op.type == ADUndoManager.OP_APPEND_MARKER) ~= undo
        if insert then
            add({type = ADUndoManager.INS_INSERT_MARKER, index = op.index, data = op.data})
        else
            add({type = ADUndoManager.INS_REMOVE_MARKER, index = op.index})
        end
    elseif op.type == ADUndoManager.OP_MARKER_DATA then
        local data = undo and op.old or op.new
        add({type = ADUndoManager.INS_SET_MARKER, index = op.index, name = data.name, group = data.group})
    elseif op.type == ADUndoManager.OP_REPLACE_NETWORK then
        add({type = ADUndoManager.INS_REPLACE_NETWORK, network = undo and op.old or op.new})
    elseif op.type == ADUndoManager.OP_GROUP_ADD then
        if undo then
            add({type = ADUndoManager.INS_REMOVE_GROUP, name = op.name})
        else
            add({type = ADUndoManager.INS_ADD_GROUP, name = op.name, id = op.id})
        end
    elseif op.type == ADUndoManager.OP_GROUP_REMOVE then
        if undo then
            add({type = ADUndoManager.INS_ADD_GROUP, name = op.name, id = op.id})
            add({type = ADUndoManager.INS_SET_GROUP_COLOR, name = op.name, color = op.color})
            for _, marker in ipairs(op.markers) do
                add({type = ADUndoManager.INS_SET_MARKER, index = marker.index, name = marker.name, group = op.name})
            end
        else
            add({type = ADUndoManager.INS_REMOVE_GROUP, name = op.name})
        end
    elseif op.type == ADUndoManager.OP_GROUP_RENAME then
        local renamePairs = op.pairs
        if undo then
            renamePairs = {}
            for _, pair in ipairs(op.pairs) do
                table.insert(renamePairs, {from = pair.to, to = pair.from})
            end
        end
        add({type = ADUndoManager.INS_RENAME_GROUPS, pairs = renamePairs})
    elseif op.type == ADUndoManager.OP_GROUP_COLOR then
        -- nil is the default color, so no "undo and old or new" here
        local color = op.new
        if undo then
            color = op.old
        end
        add({type = ADUndoManager.INS_SET_GROUP_COLOR, name = op.name, color = color})
    end
end

function ADUndoManager.getInstructions(step, undo)
    local instructions = {}
    if undo then
        for i = #step.ops, 1, -1 do
            ADUndoManager.appendInstructions(instructions, step.ops[i], true)
        end
    else
        for i = 1, #step.ops do
            ADUndoManager.appendInstructions(instructions, step.ops[i], false)
        end
    end
    return instructions
end

-- executed on server and all clients
-- extraPoints: additional highlights, e.g. the point a recording continues from
function ADUndoManager:executeInstructions(instructions, extraPoints)
    local points = ADUndoManager.simulateChanges(instructions)
    for _, point in ipairs(extraPoints or {}) do
        table.insert(points, point)
    end

    self.applying = true
    for _, ins in ipairs(instructions) do
        if ins.type == ADUndoManager.INS_APPEND_WP then
            ADGraphManager:rawAppendWayPoint(ins.data)
        elseif ins.type == ADUndoManager.INS_POP_WP then
            ADGraphManager:rawPopWayPoint(ins.id)
        elseif ins.type == ADUndoManager.INS_REMOVE_WP then
            ADGraphManager:rawRemoveWayPoint(ins.id)
        elseif ins.type == ADUndoManager.INS_INSERT_WP then
            ADGraphManager:rawInsertWayPoint(ins.id, ins.data, ins.refs, ins.markers)
        elseif ins.type == ADUndoManager.INS_SET_LINKS then
            local wp = ADGraphManager:getWayPointById(ins.id)
            if wp ~= nil then
                wp.out = ADUndoManager.copyIds(ins.out)
                wp.incoming = ADUndoManager.copyIds(ins.incoming)
            end
        elseif ins.type == ADUndoManager.INS_SET_WP_DATA then
            local wp = ADGraphManager:getWayPointById(ins.id)
            if wp ~= nil then
                wp.x, wp.y, wp.z, wp.flags = ins.x, ins.y, ins.z, ins.flags
                wp.undoOrigin = nil
            end
        elseif ins.type == ADUndoManager.INS_INSERT_MARKER then
            ADGraphManager:rawInsertMapMarker(ins.index, ins.data)
        elseif ins.type == ADUndoManager.INS_REMOVE_MARKER then
            ADGraphManager:rawRemoveMapMarker(ins.index)
        elseif ins.type == ADUndoManager.INS_SET_MARKER then
            local marker = ADGraphManager:getMapMarkerById(ins.index)
            if marker ~= nil then
                marker.name = ins.name
                if ADGraphManager:getGroupByName(ins.group) ~= nil then
                    marker.group = ins.group
                else
                    -- folder was deleted in the meantime
                    marker.group = "All"
                end
            end
        elseif ins.type == ADUndoManager.INS_REPLACE_NETWORK then
            local network = ins.network
            ADGraphManager:replaceNetwork(network.wayPoints, network.mapMarkers, network.groups, network.groupColors)
        elseif ins.type == ADUndoManager.INS_ADD_GROUP then
            ADGraphManager:rawInsertGroup(ins.name, ins.id)
        elseif ins.type == ADUndoManager.INS_REMOVE_GROUP then
            ADGraphManager:rawRemoveGroup(ins.name)
        elseif ins.type == ADUndoManager.INS_RENAME_GROUPS then
            ADGraphManager:rawRenameGroups(ins.pairs)
        elseif ins.type == ADUndoManager.INS_SET_GROUP_COLOR then
            ADGraphManager:rawSetGroupColor(ins.name, ins.color)
        end
    end
    self.applying = false

    self:setHighlights(points)

    ADGraphManager:markChanges()
    AutoDrive:notifyDestinationListeners()
    if AutoDrive.Hud ~= nil then
        AutoDrive.Hud.lastUIScale = 0
    end
    for _, vehicle in pairs(AutoDrive.getAllVehicles()) do
        if vehicle.ad ~= nil and vehicle.resetWayPointsDistance ~= nil then
            vehicle:resetWayPointsDistance()
            -- waypoint ids may have changed, drop the editor selections
            AutoDrive.resetMouseSelections(vehicle)
        end
    end
    -- the HUD buttons need the new availability
    self.stateRequestTimer = ADUndoManager.STATE_REQUEST_INTERVAL
end

-------------------------------------------------------------------------------
-- highlights
-------------------------------------------------------------------------------

-- what the instructions change, without changing anything: {x, y, z, kind, fromX, fromY, fromZ}
-- the waypoint list is simulated, so the ids of later instructions are resolved like in executeInstructions
function ADUndoManager.simulateChanges(instructions)
    local list = {}
    for i, wp in ipairs(ADGraphManager:getWayPoints()) do
        list[i] = wp
    end
    -- the waypoint each marker is on
    local markers = {}
    for i, marker in ipairs(ADGraphManager:getMapMarkers()) do
        markers[i] = list[marker.id] or false
    end

    local infos = {}
    local order = {}
    local function touch(entry, kind)
        if entry == nil or entry == false then
            return nil
        end
        local info = infos[entry]
        if info == nil then
            info = {kind = kind, x = entry.x, y = entry.y, z = entry.z}
            infos[entry] = info
            table.insert(order, entry)
        elseif kind == ADUndoManager.HIGHLIGHT_REMOVED then
            info.kind = kind
        end
        return info
    end

    for _, ins in ipairs(instructions) do
        if ins.type == ADUndoManager.INS_APPEND_WP or ins.type == ADUndoManager.INS_INSERT_WP then
            local data = ins.data
            local entry = {x = data.x, y = data.y, z = data.z, isNew = true}
            if ins.type == ADUndoManager.INS_APPEND_WP then
                table.insert(list, entry)
            else
                table.insert(list, math.min(ins.id, #list + 1), entry)
            end
            touch(entry, ADUndoManager.HIGHLIGHT_ADDED)
        elseif ins.type == ADUndoManager.INS_POP_WP then
            touch(table.remove(list), ADUndoManager.HIGHLIGHT_REMOVED)
        elseif ins.type == ADUndoManager.INS_REMOVE_WP then
            if list[ins.id] ~= nil then
                touch(table.remove(list, ins.id), ADUndoManager.HIGHLIGHT_REMOVED)
            end
        elseif ins.type == ADUndoManager.INS_SET_LINKS then
            touch(list[ins.id], ADUndoManager.HIGHLIGHT_CHANGED)
        elseif ins.type == ADUndoManager.INS_SET_WP_DATA then
            local info = touch(list[ins.id], ADUndoManager.HIGHLIGHT_CHANGED)
            if info ~= nil and (info.x ~= ins.x or info.y ~= ins.y or info.z ~= ins.z) then
                if info.fromX == nil and info.kind ~= ADUndoManager.HIGHLIGHT_ADDED then
                    info.fromX, info.fromY, info.fromZ = info.x, info.y, info.z
                end
                info.x, info.y, info.z = ins.x, ins.y, ins.z
            end
        elseif ins.type == ADUndoManager.INS_INSERT_MARKER then
            local entry = list[ins.data.id] or false
            table.insert(markers, math.min(ins.index, #markers + 1), entry)
            touch(entry, ADUndoManager.HIGHLIGHT_CHANGED)
        elseif ins.type == ADUndoManager.INS_REMOVE_MARKER then
            if markers[ins.index] ~= nil then
                touch(table.remove(markers, ins.index), ADUndoManager.HIGHLIGHT_CHANGED)
            end
        elseif ins.type == ADUndoManager.INS_SET_MARKER then
            touch(markers[ins.index], ADUndoManager.HIGHLIGHT_CHANGED)
        end
    end

    local points = {}
    for _, entry in ipairs(order) do
        local info = infos[entry]
        -- a waypoint added and removed again by the same instructions is not shown
        if not (entry.isNew and info.kind == ADUndoManager.HIGHLIGHT_REMOVED) then
            table.insert(points, {x = info.x, y = info.y, z = info.z, kind = info.kind, fromX = info.fromX, fromY = info.fromY, fromZ = info.fromZ})
        end
    end
    return points
end

function ADUndoManager.samplePoints(points)
    if #points <= ADUndoManager.HIGHLIGHT_MAX_POINTS then
        return points
    end
    -- e.g. a long recorded drive, show an evenly spread selection
    local sampled = {}
    local stepSize = #points / ADUndoManager.HIGHLIGHT_MAX_POINTS
    for i = 0, ADUndoManager.HIGHLIGHT_MAX_POINTS - 1 do
        table.insert(sampled, points[math.floor(i * stepSize) + 1])
    end
    return sampled
end

-- isPreview: shown while the preview key is held (held) or for the usual time
function ADUndoManager:setHighlights(points, isPreview, held)
    if g_dedicatedServer ~= nil or #points == 0 then
        self.highlights = nil
        return
    end
    local endTime = g_time + ADUndoManager.HIGHLIGHT_DURATION
    if held then
        endTime = math.huge
    end
    self.highlights = {points = ADUndoManager.samplePoints(points), endTime = endTime, isPreview = isPreview == true}
end

-- called while drawing the editor of the vehicle
function ADUndoManager:drawHighlights(vehicle)
    local highlights = self.highlights
    if highlights == nil then
        return
    end
    if g_time > highlights.endTime then
        self.highlights = nil
        return
    end
    local pulse = 0.5 + 0.5 * math.sin(g_time / 150)
    local vehicleX, vehicleY, vehicleZ
    if vehicle ~= nil and vehicle.components ~= nil then
        vehicleX, vehicleY, vehicleZ = getWorldTranslation(vehicle.components[1].node)
    end
    local nearest, nearestDistance = nil, math.huge

    for _, point in ipairs(highlights.points) do
        local r, g, b = unpack(ADUndoManager.HIGHLIGHT_COLORS[point.kind])
        ADDrawingManager:addSphereTask(point.x, point.y, point.z, 3 + 3 * pulse, r, g, b, 0.5)
        -- vertical beacon, to find the change from a distance
        ADDrawingManager:addLineTask(point.x, point.y, point.z, point.x, point.y + ADUndoManager.HIGHLIGHT_BEACON_HEIGHT, point.z, 2, r, g, b)
        if point.fromX ~= nil then
            -- moved waypoint: line from the old position
            ADDrawingManager:addLineTask(point.fromX, point.fromY, point.fromZ, point.x, point.y, point.z, 1.5, r, g, b)
            ADDrawingManager:addSmallSphereTask(point.fromX, point.fromY, point.fromZ, r, g, b)
        end
        if vehicleX ~= nil then
            local distance = MathUtil.vector2Length(point.x - vehicleX, point.z - vehicleZ)
            if distance < nearestDistance then
                nearest, nearestDistance = point, distance
            end
        end
    end

    if nearest ~= nil and nearestDistance > AutoDrive.drawDistance then
        -- all changes are out of sight: point from the vehicle towards the nearest one
        local dirX, dirZ = (nearest.x - vehicleX) / nearestDistance, (nearest.z - vehicleZ) / nearestDistance
        local length = ADUndoManager.POINTER_LENGTH
        local startY = vehicleY + 3
        local endX, endZ = vehicleX + dirX * length, vehicleZ + dirZ * length
        local r, g, b = unpack(ADUndoManager.HIGHLIGHT_COLORS[nearest.kind])
        ADDrawingManager:addLineTask(vehicleX, startY, vehicleZ, endX, startY, endZ, 2, r, g, b)
        ADDrawingManager:addArrowTask(vehicleX, startY, vehicleZ, endX, startY, endZ, 2, ADDrawingManager.arrows.position.start, r, g, b)
    end
end

-------------------------------------------------------------------------------
-- descriptions
-------------------------------------------------------------------------------

-- feedback text parts {key, args} describing ops, always as the original action
function ADUndoManager.describeOps(ops)
    local created, deleted, moved, sideRoads, linkedWayPoints = 0, 0, 0, 0, 0
    local markersCreated, markersDeleted, foldersCreated, foldersDeleted = {}, {}, {}, {}
    local parts = {}
    local function addCounted(count, key)
        if count == 1 then
            table.insert(parts, {key = key .. "_1", args = {}})
        elseif count > 1 then
            table.insert(parts, {key = key, args = {count}})
        end
    end
    local function addNamed(names, key)
        if #names == 1 then
            table.insert(parts, {key = key .. "_1", args = {names[1]}})
        elseif #names > 1 then
            table.insert(parts, {key = key, args = {#names}})
        end
    end

    for _, op in ipairs(ops) do
        if op.type == ADUndoManager.OP_APPEND_WP then
            created = created + 1
        elseif op.type == ADUndoManager.OP_REMOVE_WP then
            deleted = deleted + 1
        elseif op.type == ADUndoManager.OP_LINKS then
            linkedWayPoints = linkedWayPoints + 1
        elseif op.type == ADUndoManager.OP_WP_DATA then
            if op.old.x ~= op.new.x or op.old.y ~= op.new.y or op.old.z ~= op.new.z then
                moved = moved + 1
            else
                sideRoads = sideRoads + 1
            end
        elseif op.type == ADUndoManager.OP_APPEND_MARKER then
            table.insert(markersCreated, op.data.name)
        elseif op.type == ADUndoManager.OP_REMOVE_MARKER then
            table.insert(markersDeleted, op.data.name)
        elseif op.type == ADUndoManager.OP_GROUP_ADD then
            table.insert(foldersCreated, ADGraphManager:getGroupDisplayName(op.name))
        elseif op.type == ADUndoManager.OP_GROUP_REMOVE then
            table.insert(foldersDeleted, ADGraphManager:getGroupDisplayName(op.name))
        end
    end

    addCounted(created, "AD_undoStep_wpCreated")
    addCounted(deleted, "AD_undoStep_wpDeleted")
    addCounted(moved, "AD_undoStep_wpMoved")
    addCounted(sideRoads, "AD_undoStep_sideRoad")
    if created == 0 and deleted == 0 and linkedWayPoints > 0 then
        -- a connection changes 2 waypoints, a section of n waypoints has n - 1 connections
        addCounted(math.max(1, linkedWayPoints - 1), "AD_undoStep_connection")
    end
    addNamed(markersCreated, "AD_undoStep_markerCreated")
    addNamed(markersDeleted, "AD_undoStep_markerDeleted")
    addNamed(foldersCreated, "AD_undoStep_folderCreated")
    addNamed(foldersDeleted, "AD_undoStep_folderDeleted")
    for _, op in ipairs(ops) do
        if op.type == ADUndoManager.OP_MARKER_DATA then
            if op.old.name ~= op.new.name then
                table.insert(parts, {key = "AD_undoStep_markerRenamed", args = {op.old.name, op.new.name}})
            end
            if op.old.group ~= op.new.group then
                table.insert(parts, {key = "AD_undoStep_markerFolder", args = {op.new.name, ADGraphManager:getGroupDisplayName(op.new.group)}})
            end
        elseif op.type == ADUndoManager.OP_GROUP_RENAME and op.pairs[1] ~= nil then
            -- the first pair is the renamed folder itself, the others are its sub folders
            table.insert(parts, {key = "AD_undoStep_folderRenamed", args = {op.pairs[1].from, op.pairs[1].to}})
        elseif op.type == ADUndoManager.OP_GROUP_COLOR then
            table.insert(parts, {key = "AD_undoStep_folderColor", args = {ADGraphManager:getGroupDisplayName(op.name)}})
        elseif op.type == ADUndoManager.OP_REPLACE_NETWORK then
            table.insert(parts, {key = "AD_undoStep_network", args = {}})
        end
    end

    if #parts == 0 then
        table.insert(parts, {key = "AD_undoStep_edit", args = {}})
    end
    while #parts > ADUndoManager.MAX_DESCRIPTION_PARTS do
        table.remove(parts)
    end
    return parts
end

function ADUndoManager.describeStep(step)
    return ADUndoManager.describeOps(step.ops)
end

function ADUndoManager.ownerNamePart(owner)
    if owner ~= nil and owner.name ~= nil and owner.name ~= "" then
        return {key = "AD_undo_name", args = {owner.name}}
    end
    return {key = "AD_undo_otherPlayer", args = {}}
end

-------------------------------------------------------------------------------
-- undo / redo plans, worked out on the server
-------------------------------------------------------------------------------

-- keys of the waypoints / markers / folders a step changes, and if it shifts ids
function ADUndoManager.getStepKeys(step)
    local keys = {}
    local structural = false
    for _, op in ipairs(step.ops) do
        if ADUndoManager.STRUCTURAL_OPS[op.type] then
            structural = true
        elseif op.type == ADUndoManager.OP_LINKS or op.type == ADUndoManager.OP_WP_DATA then
            keys["w" .. op.id] = true
        elseif op.type == ADUndoManager.OP_MARKER_DATA then
            keys["m" .. op.index] = true
        elseif op.type == ADUndoManager.OP_GROUP_COLOR then
            keys["g" .. op.name] = true
        end
    end
    return keys, structural
end

-- plan: {instructions, extraPoints, parts, doneKey, previewKey, apply()} or nil, error {key, parts}
function ADUndoManager:planUndo(owner)
    if self.depth > 0 then
        return nil, {key = "AD_undo_blocked"}
    end
    local group = self:getActiveGroup()
    if group ~= nil and group.owner.id == owner.id and group.module ~= nil then
        return self:planRecordingUndo(group)
    end

    local index = nil
    for i = #self.undoStack, 1, -1 do
        if self.undoStack[i].owner.id == owner.id then
            index = i
            break
        end
    end
    if index == nil then
        return nil, {key = "AD_undo_empty"}
    end
    local step = self.undoStack[index]

    if index < #self.undoStack then
        -- later edits of other players must not depend on this step
        local keys, structural = ADUndoManager.getStepKeys(step)
        for i = #self.undoStack, index + 1, -1 do
            local later = self.undoStack[i]
            local laterKeys, laterStructural = ADUndoManager.getStepKeys(later)
            local conflict = structural or laterStructural
            for key in pairs(laterKeys) do
                conflict = conflict or keys[key] == true
            end
            if conflict then
                return nil, {key = "AD_undo_conflict", parts = {ADUndoManager.ownerNamePart(later.owner)}}
            end
        end
    end

    return {
        instructions = ADUndoManager.getInstructions(step, true),
        parts = ADUndoManager.describeStep(step),
        doneKey = "AD_undo_done",
        previewKey = "AD_undo_preview",
        apply = function()
            table.remove(self.undoStack, index)
            step.group = nil
            self:clearOtherRedoStacks(owner)
            self.redoStacks[owner.id] = self.redoStacks[owner.id] or {}
            table.insert(self.redoStacks[owner.id], step)
        end
    }
end

function ADUndoManager:planRedo(owner)
    local group = self:getActiveGroup()
    if self.depth > 0 or (group ~= nil and group.owner.id == owner.id) then
        return nil, {key = "AD_undo_blocked"}
    end
    local stack = self:getRedoStack(owner)
    local step = stack[#stack]
    if step == nil then
        return nil, {key = "AD_redo_empty"}
    end
    -- redo steps are dropped whenever anything else changes, so the step still fits
    return {
        instructions = ADUndoManager.getInstructions(step, false),
        parts = ADUndoManager.describeStep(step),
        doneKey = "AD_redo_done",
        previewKey = "AD_undo_preview",
        apply = function()
            table.remove(stack)
            self:clearOtherRedoStacks(owner)
            step.time = g_time
            table.insert(self.undoStack, step)
            while #self.undoStack > ADUndoManager.MAX_STEPS do
                table.remove(self.undoStack, 1)
            end
        end
    }
end

-- while recording, an undo removes the last recorded points and the recording continues from there
function ADUndoManager:planRecordingUndo(group)
    local step = self.undoStack[#self.undoStack]
    if step == nil or step.group ~= group or #group.marks == 0 then
        return nil, {key = "AD_undo_recordingStart"}
    end

    local function lastPosition(state)
        return state.lastWp or state.lastWp2
    end

    -- go back at least RECORDING_UNDO_DISTANCE along the recorded points
    local current = lastPosition(group.module:getUndoState())
    local distance = 0
    local target = #group.marks
    for k = #group.marks, 1, -1 do
        target = k
        local position = lastPosition(group.marks[k].state)
        if current ~= nil and position ~= nil then
            distance = distance + MathUtil.vector2Length(current.x - position.x, current.z - position.z)
        end
        current = position
        if distance >= ADUndoManager.RECORDING_UNDO_DISTANCE then
            break
        end
    end
    local mark = group.marks[target]

    local instructions = {}
    local removedOps = {}
    for i = #step.ops, mark.opCount + 1, -1 do
        ADUndoManager.appendInstructions(instructions, step.ops[i], true)
        table.insert(removedOps, step.ops[i])
    end
    local removedPoints = 0
    for _, op in ipairs(removedOps) do
        if op.type == ADUndoManager.OP_APPEND_WP then
            removedPoints = removedPoints + 1
        end
    end

    -- the recording continues from these points
    local extraPoints = {}
    for _, wp in pairs({mark.state.lastWp, mark.state.lastWp2}) do
        table.insert(extraPoints, {x = wp.x, y = wp.y, z = wp.z, kind = ADUndoManager.HIGHLIGHT_CHANGED})
    end

    local parts = {{key = "AD_undoStep_recordedPoints", args = {removedPoints}}}
    if removedPoints == 1 then
        parts = {{key = "AD_undoStep_recordedPoints_1", args = {}}}
    end
    return {
        instructions = instructions,
        extraPoints = extraPoints,
        parts = parts,
        doneKey = "AD_undo_recording",
        previewKey = "AD_undo_preview",
        apply = function()
            for i = #step.ops, mark.opCount + 1, -1 do
                table.remove(step.ops)
            end
            for k = #group.marks, target, -1 do
                table.remove(group.marks)
            end
            group.module:restoreUndoState(mark.state)
        end
    }
end

-------------------------------------------------------------------------------
-- undo / redo / preview on the server
-------------------------------------------------------------------------------

-- connection is the requesting client or nil for the local player
function ADUndoManager:undo(connection)
    self:perform(true, connection)
end

function ADUndoManager:redo(connection)
    self:perform(false, connection)
end

function ADUndoManager:perform(undo, connection)
    if g_server == nil then
        return
    end
    local owner = ADUndoManager.getOwnerByConnection(connection)
    local plan, err
    if undo then
        plan, err = self:planUndo(owner)
    else
        plan, err = self:planRedo(owner)
    end
    local action = undo and "undo" or "redo"
    if plan == nil then
        ADUndoManager.log("%s requested by %s: refused %s %s (own steps %s, all steps %s)", action, ADUndoManager.ownerText(owner), err.key, ADUndoManager.partsText(err.parts), self:countOwnSteps(owner), #self.undoStack)
        self:sendFeedback(connection, owner, err.key, err.parts)
        return
    end
    ADUndoManager.log("%s requested by %s: %s %s", action, ADUndoManager.ownerText(owner), plan.doneKey, ADUndoManager.partsText(plan.parts))

    self:executeInstructions(plan.instructions, plan.extraPoints)
    -- clients apply the same instructions
    g_server:broadcastEvent(AutoDriveUndoRedoEvent.newApply(plan.instructions, plan.extraPoints), false)
    plan.apply()
    self:sendFeedback(connection, owner, plan.doneKey, plan.parts)
end

function ADUndoManager:sendPreview(connection)
    if g_server == nil then
        return
    end
    local owner = ADUndoManager.getOwnerByConnection(connection)
    local plan, err = self:planUndo(owner)
    if plan == nil then
        self:sendFeedback(connection, owner, err.key, err.parts)
        return
    end
    local points = ADUndoManager.simulateChanges(plan.instructions)
    for _, point in ipairs(plan.extraPoints or {}) do
        table.insert(points, point)
    end
    points = ADUndoManager.samplePoints(points)
    if connection == nil then
        self:showPreview(plan.previewKey, plan.parts, points)
    else
        connection:sendEvent(AutoDriveUndoRedoEvent.newPreview(plan.previewKey, plan.parts, points))
    end
end

-- parts: list of {key, args} describing the step, localized on the receiving client
function ADUndoManager:sendFeedback(connection, owner, textKey, parts)
    parts = parts or {}
    local undoCount, redoCount = self:countOwnSteps(owner), #self:getRedoStack(owner)
    if connection == nil then
        ADUndoManager.showFeedback(textKey, undoCount, redoCount, parts)
    else
        connection:sendEvent(AutoDriveUndoRedoEvent.newFeedback(textKey, undoCount, redoCount, parts))
    end
end

function ADUndoManager:notifyCleared(reason)
    if g_server == nil then
        return
    end
    g_server:broadcastEvent(AutoDriveUndoRedoEvent.newNotice(reason), false)
    ADUndoManager.showNotice(reason)
end

-- availability of undo / redo for the HUD buttons of a client
function ADUndoManager:sendState(connection)
    local canUndo, canRedo = self:getAvailability(ADUndoManager.getOwnerByConnection(connection))
    connection:sendEvent(AutoDriveUndoRedoEvent.newState(canUndo, canRedo))
end

-------------------------------------------------------------------------------
-- client side
-------------------------------------------------------------------------------

function ADUndoManager.getFeedbackText(textKey, undoCount, redoCount, parts)
    local descriptions = {}
    for _, part in ipairs(parts or {}) do
        table.insert(descriptions, string.format(g_i18n:getText(part.key), unpack(part.args)))
    end
    return string.format(g_i18n:getText(textKey), table.concat(descriptions, ", "), undoCount, redoCount)
end

ADUndoManager.WARNING_KEYS = {
    AD_undo_empty = true,
    AD_redo_empty = true,
    AD_undo_blocked = true,
    AD_undo_conflict = true,
    AD_undo_recordingStart = true
}

function ADUndoManager.showFeedback(textKey, undoCount, redoCount, parts)
    ADUndoManager.stateRequestTimer = ADUndoManager.STATE_REQUEST_INTERVAL
    if g_server == nil then
        ADUndoManager.log("feedback from server: %s %s (own undo %s, redo %s)", textKey, ADUndoManager.partsText(parts), undoCount, redoCount)
    end
    if g_dedicatedServer ~= nil then
        return
    end
    local text = ADUndoManager.getFeedbackText(textKey, undoCount, redoCount, parts)
    local messageType = ADMessagesManager.messageTypes.INFO
    if ADUndoManager.WARNING_KEYS[textKey] then
        messageType = ADMessagesManager.messageTypes.WARN
    end
    ADMessagesManager:addMessage(nil, messageType, text, 4000)
    if ADUndoManager.previewWanted ~= nil and not ADUndoManager.previewWanted.held then
        ADUndoManager.previewWanted = nil
    end
end

function ADUndoManager.showNotice(reason)
    ADUndoManager.stateRequestTimer = ADUndoManager.STATE_REQUEST_INTERVAL
    if g_dedicatedServer ~= nil or not AutoDrive.isEditorModeEnabled() then
        return
    end
    local text = string.format(g_i18n:getText("AD_undo_cleared"), g_i18n:getText(reason))
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, text, 5000)
end

function ADUndoManager:showPreview(textKey, parts, points)
    local wanted = self.previewWanted
    if g_dedicatedServer ~= nil or wanted == nil then
        -- key already released
        return
    end
    self:setHighlights(points, true, wanted.held)
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, ADUndoManager.getFeedbackText(textKey, 0, 0, parts), 4000)
    if not wanted.held then
        self.previewWanted = nil
    end
end

-- called by the player
function ADUndoManager:requestUndo()
    self:request(AutoDriveUndoRedoEvent.TYPE_REQUEST_UNDO)
end

function ADUndoManager:requestRedo()
    self:request(AutoDriveUndoRedoEvent.TYPE_REQUEST_REDO)
end

-- held: shown while the key is held, otherwise for the usual time
function ADUndoManager:requestPreview(held)
    self.previewWanted = {held = held}
    self:request(AutoDriveUndoRedoEvent.TYPE_REQUEST_PREVIEW)
end

function ADUndoManager:stopPreview()
    self.previewWanted = nil
    if self.highlights ~= nil and self.highlights.isPreview then
        self.highlights = nil
    end
end

function ADUndoManager:request(requestType)
    if g_server ~= nil then
        if requestType == AutoDriveUndoRedoEvent.TYPE_REQUEST_UNDO then
            self:undo(nil)
        elseif requestType == AutoDriveUndoRedoEvent.TYPE_REQUEST_REDO then
            self:redo(nil)
        elseif requestType == AutoDriveUndoRedoEvent.TYPE_REQUEST_PREVIEW then
            self:sendPreview(nil)
        end
    else
        g_client:getServerConnection():sendEvent(AutoDriveUndoRedoEvent.newRequest(requestType))
    end
end

-- undo / redo available for the local player, for the HUD buttons
function ADUndoManager:getClientAvailability()
    if g_server ~= nil then
        return self:getAvailability(ADUndoManager.getLocalOwner())
    end
    return self.clientCanUndo, self.clientCanRedo
end

function ADUndoManager:setClientAvailability(canUndo, canRedo)
    if canUndo ~= self.clientCanUndo or canRedo ~= self.clientCanRedo then
        ADUndoManager.log("HUD buttons: undo %s, redo %s", canUndo, canRedo)
    end
    self.clientCanUndo = canUndo
    self.clientCanRedo = canRedo
end

-- clients ask the server regularly while the editor is used
function ADUndoManager:update(dt)
    if g_server ~= nil or g_client == nil or not AutoDrive.isEditorModeEnabled() then
        return
    end
    self.stateRequestTimer = self.stateRequestTimer + dt
    if self.stateRequestTimer >= ADUndoManager.STATE_REQUEST_INTERVAL then
        self.stateRequestTimer = 0
        g_client:getServerConnection():sendEvent(AutoDriveUndoRedoEvent.newRequest(AutoDriveUndoRedoEvent.TYPE_REQUEST_STATE))
    end
end

ADUndoManager.installActorHooks()
