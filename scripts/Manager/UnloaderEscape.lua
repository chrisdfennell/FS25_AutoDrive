-- Drive clear when blocked (vehicle setting unloaderEscape): a combine unloader that is stuck against another
-- vehicle, or that stands in front of a harvester driven by a helper, switches off its collisions with other
-- vehicles, drives to the nearest field edge (EscapeToFieldEdgeTask) and switches them on again once it is clear.
--
-- Collisions: two shapes only collide when the group of each matches the collision mask of the other. Taking
-- VEHICLE out of the mask of the unloader's shapes (and its trailers') lets it pass through vehicles, terrain,
-- buildings and trees still stop it. The mask is only put back when no other vehicle is near: restoring it while
-- two vehicles overlap makes the physics throw them apart.
ADUnloaderEscape = {}

-- the unloader stands in front of the harvester for this long (ms), with the harvester standing too
ADUnloaderEscape.HARVESTER_BLOCK_TIME = 6000
-- no new escape for this long (ms) after one started
ADUnloaderEscape.COOLDOWN = 90000
-- an other vehicle closer than this (m) counts as touching / not clear
ADUnloaderEscape.CONTACT_MARGIN = 1.5
ADUnloaderEscape.CLEAR_MARGIN = 2.5
-- the area in front of the harvester (m): from its front, this long, at least this wide
ADUnloaderEscape.FRONT_LENGTH = 14
ADUnloaderEscape.FRONT_MIN_WIDTH = 8
-- looking for the field edge: directions, step and range (m), and how far past the edge to go
ADUnloaderEscape.EDGE_DIRECTIONS = 16
ADUnloaderEscape.EDGE_STEP = 2
ADUnloaderEscape.EDGE_RANGE = 400
ADUnloaderEscape.EDGE_OUTSIDE = 8
-- the watcher puts collisions back for vehicles that are not escaping any more (ms)
ADUnloaderEscape.WATCH_INTERVAL = 500

ADUnloaderEscape.ghosted = {}       -- vehicle -> {node -> original collision mask}
ADUnloaderEscape.watchTimer = 0

local function hasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

function ADUnloaderEscape.isEnabled(vehicle)
    return vehicle ~= nil and vehicle.ad ~= nil and AutoDrive.getSetting("unloaderEscape", vehicle) == true
end

-------------------------------------------------------------------------------
-- collisions
-------------------------------------------------------------------------------

-- the physics shapes of the vehicle and everything attached: the component nodes and their compound children
function ADUnloaderEscape.getCollisionNodes(vehicle)
    local nodes = {}
    local function collect(node, depth)
        if depth > 12 or getNumOfChildren == nil then
            return
        end
        for i = 0, getNumOfChildren(node) - 1 do
            local child = getChildAt(node, i)
            if getIsCompoundChild ~= nil and getIsCompoundChild(child) then
                table.insert(nodes, child)
            end
            collect(child, depth + 1)
        end
    end
    for _, unit in ipairs(AutoDrive.getAllImplements(vehicle, true)) do
        for _, component in ipairs(unit.components or {}) do
            if component.node ~= nil and component.node ~= 0 then
                table.insert(nodes, component.node)
                collect(component.node, 0)
            end
        end
    end
    return nodes
end

-- local engine state: the server switches it and tells the clients (AutoDriveUnloaderEscapeEvent)
function ADUnloaderEscape.applyGhost(vehicle, ghost)
    if vehicle == nil or CollisionFlag == nil or CollisionFlag.VEHICLE == nil then
        return
    end
    local flag = CollisionFlag.VEHICLE
    if ghost then
        if ADUnloaderEscape.ghosted[vehicle] ~= nil then
            return
        end
        local masks = {}
        for _, node in ipairs(ADUnloaderEscape.getCollisionNodes(vehicle)) do
            local mask = getCollisionFilterMask(node)
            if mask ~= nil and masks[node] == nil and hasFlag(mask, flag) then
                masks[node] = mask
                setCollisionFilterMask(node, mask - flag)
            end
        end
        ADUnloaderEscape.ghosted[vehicle] = masks
    else
        local masks = ADUnloaderEscape.ghosted[vehicle]
        if masks == nil then
            return
        end
        for node, mask in pairs(masks) do
            if entityExists == nil or entityExists(node) then
                setCollisionFilterMask(node, mask)
            end
        end
        ADUnloaderEscape.ghosted[vehicle] = nil
    end
end

function ADUnloaderEscape.isGhosted(vehicle)
    return ADUnloaderEscape.ghosted[vehicle] ~= nil
end

function ADUnloaderEscape.setGhost(vehicle, ghost)
    if ADUnloaderEscape.isGhosted(vehicle) == ghost then
        return
    end
    ADUnloaderEscape.applyGhost(vehicle, ghost)
    if g_server ~= nil and AutoDriveUnloaderEscapeEvent ~= nil then
        g_server:broadcastEvent(AutoDriveUnloaderEscapeEvent.new(vehicle, ghost), false)
    end
end

-------------------------------------------------------------------------------
-- geometry
-------------------------------------------------------------------------------

-- a box {x, y, z} x 4 as AutoDrive uses: centre, direction (unit vector), half width, half length
function ADUnloaderEscape.makeBox(cx, cy, cz, dirX, dirZ, halfWidth, halfLength)
    local ox, oz = -dirZ, dirX
    return {
        {x = cx + ox * halfWidth - dirX * halfLength, y = cy, z = cz + oz * halfWidth - dirZ * halfLength},
        {x = cx - ox * halfWidth - dirX * halfLength, y = cy, z = cz - oz * halfWidth - dirZ * halfLength},
        {x = cx - ox * halfWidth + dirX * halfLength, y = cy, z = cz - oz * halfWidth + dirZ * halfLength},
        {x = cx + ox * halfWidth + dirX * halfLength, y = cy, z = cz + oz * halfWidth + dirZ * halfLength}
    }
end

-- the box grown by margin on every side
function ADUnloaderEscape.growBox(box, margin)
    local cx, cz = 0, 0
    for i = 1, 4 do
        cx, cz = cx + box[i].x / 4, cz + box[i].z / 4
    end
    -- the two axes of the box
    local ax, az = box[2].x - box[1].x, box[2].z - box[1].z
    local bx, bz = box[4].x - box[1].x, box[4].z - box[1].z
    local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
    if la == 0 or lb == 0 then
        return box
    end
    ax, az, bx, bz = ax / la, az / la, bx / lb, bz / lb
    local grown = {}
    for i = 1, 4 do
        local p = box[i]
        local sa = ((p.x - cx) * ax + (p.z - cz) * az) >= 0 and 1 or -1
        local sb = ((p.x - cx) * bx + (p.z - cz) * bz) >= 0 and 1 or -1
        grown[i] = {x = p.x + (sa * ax + sb * bx) * margin, y = p.y, z = p.z + (sa * az + sb * bz) * margin}
    end
    return grown
end

function ADUnloaderEscape.getUnitBoxes(vehicle)
    local boxes = {}
    for _, unit in ipairs(AutoDrive.getAllImplements(vehicle, true)) do
        if unit.components ~= nil and unit.size ~= nil and unit.size.width ~= nil then
            table.insert(boxes, AutoDrive.getBoundingBoxForVehicle(unit))
        end
    end
    return boxes
end

-- another vehicle (not attached to this one) closer than margin
function ADUnloaderEscape.isTouchingOtherVehicle(vehicle, margin)
    for _, box in ipairs(ADUnloaderEscape.getUnitBoxes(vehicle)) do
        if AutoDrive.checkForVehiclesInBox(ADUnloaderEscape.growBox(box, margin), {vehicle}) then
            return true
        end
    end
    return false
end

-- the area right in front of the harvester
function ADUnloaderEscape.getHarvesterFrontBox(harvester)
    local x, y, z = getWorldTranslation(harvester.components[1].node)
    local dirX, _, dirZ = AutoDrive.localDirectionToWorld(harvester, 0, 0, 1)
    local length = AutoDrive.getVehicleDimensions ~= nil and select(2, AutoDrive.getVehicleDimensions(harvester)) or 10
    local width = math.max(select(1, AutoDrive.getVehicleDimensions(harvester)) or 0, ADUnloaderEscape.FRONT_MIN_WIDTH)
    -- PropaineX edit (3.10.0.0): Nexat: the carrier drives crab-wise, so the front is the harvester module's front and
    -- the carrier's length is the width
    local module = AutoDrive.getSidewaysHarvester(harvester)
    if module ~= nil then
        x, y, z = getWorldTranslation(module.components[1].node)
        dirX, _, dirZ = AutoDrive.localDirectionToWorld(module, 0, 0, 1)
        local halfW, halfL = AutoDrive.getHarvesterHalfSize(module)
        length = halfL * 2
        width = math.max(halfW * 2, AutoDrive.getFrontToolWidth ~= nil and AutoDrive.getFrontToolWidth(module) or 0, ADUnloaderEscape.FRONT_MIN_WIDTH)
    end
    local ahead = length / 2 + ADUnloaderEscape.FRONT_LENGTH / 2
    return ADUnloaderEscape.makeBox(x + dirX * ahead, y, z + dirZ * ahead, dirX, dirZ, width / 2, ADUnloaderEscape.FRONT_LENGTH / 2)
end

function ADUnloaderEscape.isInFrontOfHarvester(vehicle, harvester)
    local front = ADUnloaderEscape.getHarvesterFrontBox(harvester)
    for _, box in ipairs(ADUnloaderEscape.getUnitBoxes(vehicle)) do
        if AutoDrive.boxesIntersect(front, box) then
            return true
        end
    end
    return false
end

-- the nearest point just outside the field: the shortest of several straight lines out of the field.
-- nil when the position is not on a field or no edge is within range
function ADUnloaderEscape.findFieldEdge(x, z)
    local y = getTerrainHeightAtWorldPos ~= nil and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil
        and getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) or 0
    if not AutoDrive.checkIsOnField(x, y, z) then
        return nil
    end
    local best, bestDirX, bestDirZ = nil, nil, nil
    for i = 0, ADUnloaderEscape.EDGE_DIRECTIONS - 1 do
        local angle = i * 2 * math.pi / ADUnloaderEscape.EDGE_DIRECTIONS
        local dirX, dirZ = math.sin(angle), math.cos(angle)
        local d = ADUnloaderEscape.EDGE_STEP
        while d <= ADUnloaderEscape.EDGE_RANGE and (best == nil or d - ADUnloaderEscape.EDGE_STEP < best) do
            if not AutoDrive.checkIsOnField(x + dirX * d, y, z + dirZ * d) then
                -- the edge exactly: halve the last step
                local inside, outside = d - ADUnloaderEscape.EDGE_STEP, d
                for _ = 1, 8 do
                    local middle = (inside + outside) / 2
                    if AutoDrive.checkIsOnField(x + dirX * middle, y, z + dirZ * middle) then
                        inside = middle
                    else
                        outside = middle
                    end
                end
                if best == nil or outside < best then
                    best, bestDirX, bestDirZ = outside, dirX, dirZ
                end
                break
            end
            d = d + ADUnloaderEscape.EDGE_STEP
        end
    end
    if best == nil then
        return nil
    end
    local d = best + ADUnloaderEscape.EDGE_OUTSIDE
    return x + bestDirX * d, z + bestDirZ * d
end

-------------------------------------------------------------------------------
-- deciding (server, CombineUnloaderMode:monitorTasks)
-------------------------------------------------------------------------------

function ADUnloaderEscape.isHelperDriven(harvester)
    return harvester ~= nil and harvester.getIsAIActive ~= nil and harvester:getIsAIActive()
end

-- the harvesters to look at: the one the unloader works for and every other one nearby
function ADUnloaderEscape.getHarvesters(mode)
    local list = {}
    if mode.combine ~= nil then
        table.insert(list, mode.combine)
    end
    if ADHarvestManager ~= nil then
        for _, harvester in pairs(ADHarvestManager.harvesters or {}) do
            if harvester ~= mode.combine then
                table.insert(list, harvester)
            end
        end
    end
    return list
end

-- the harvester that the unloader stands in front of, while both stand still; nil if none
function ADUnloaderEscape.getBlockedHarvester(mode)
    local vehicle = mode.vehicle
    if vehicle.lastSpeedReal * 3600 > 1 then
        return nil
    end
    for _, harvester in ipairs(ADUnloaderEscape.getHarvesters(mode)) do
        local root = harvester.getRootVehicle ~= nil and harvester:getRootVehicle() or harvester
        if root ~= nil and root.components ~= nil and root.lastSpeedReal ~= nil and root.lastSpeedReal * 3600 < 1
            and ADUnloaderEscape.isHelperDriven(root) and not AutoDrive.combineIsTurning(harvester)
            and ADUnloaderEscape.isInFrontOfHarvester(vehicle, root) then
            return root
        end
    end
    return nil
end

-- every frame from CombineUnloaderMode:monitorTasks; returns true when the escape owns the vehicle (the upstream
-- stuck handling must not run then). stuck: the upstream "we are stuck" condition
function ADUnloaderEscape.monitor(mode, dt, stuck)
    if mode.state == mode.STATE_ESCAPE then
        return true
    end
    local vehicle = mode.vehicle
    if g_server == nil or not ADUnloaderEscape.isEnabled(vehicle) then
        mode.escapeHarvesterTime = 0
        return false
    end
    if mode.escapeCooldownUntil ~= nil and (g_time or 0) < mode.escapeCooldownUntil then
        return false
    end
    -- blocking a harvester: the time it stands with the unloader in front of it, while nothing is unloaded into it
    local fillLevel = mode.trailers ~= nil and #mode.trailers > 0 and AutoDrive.getAllFillLevels(mode.trailers) or 0
    local filling = mode.escapeLastFill ~= nil and fillLevel > mode.escapeLastFill + 1
    mode.escapeLastFill = fillLevel
    if not filling and ADUnloaderEscape.getBlockedHarvester(mode) ~= nil then
        mode.escapeHarvesterTime = (mode.escapeHarvesterTime or 0) + dt
    else
        mode.escapeHarvesterTime = 0
    end
    local reason = nil
    if mode.escapeHarvesterTime >= ADUnloaderEscape.HARVESTER_BLOCK_TIME then
        reason = "harvester"
    elseif stuck and ADUnloaderEscape.isTouchingOtherVehicle(vehicle, ADUnloaderEscape.CONTACT_MARGIN) then
        reason = "stuck"
    end
    if reason == nil then
        return false
    end
    ADUnloaderEscape.start(mode, reason)
    return true
end

function ADUnloaderEscape.start(mode, reason)
    local vehicle = mode.vehicle
    mode.escapeHarvesterTime = 0
    mode.escapeCooldownUntil = (g_time or 0) + ADUnloaderEscape.COOLDOWN
    vehicle.ad.specialDrivingModule:releaseVehicle()
    vehicle.ad.taskModule:abortAllTasks()
    mode.activeTask = EscapeToFieldEdgeTask:new(vehicle)
    mode.state = mode.STATE_ESCAPE
    mode.failedPathFinder = 0
    vehicle.ad.taskModule:addTask(mode.activeTask)
    if AutoDriveMessageEvent ~= nil and ADMessagesManager ~= nil then
        if reason == "harvester" then
            local harvester = ADUnloaderEscape.getBlockedHarvester(mode)
            AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_escape_harvester; (%s)", 8000,
                vehicle.ad.stateModule:getName(), harvester ~= nil and ADDiag.unitName(harvester) or "?")
        else
            AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_escape_stuck;", 8000, vehicle.ad.stateModule:getName())
        end
    end
end

-------------------------------------------------------------------------------
-- watcher (server): collisions back on for vehicles that are not escaping any more, once they are clear
-------------------------------------------------------------------------------

function ADUnloaderEscape:update(dt)
    if g_server == nil or next(self.ghosted) == nil then
        return
    end
    self.watchTimer = self.watchTimer + dt
    if self.watchTimer < self.WATCH_INTERVAL then
        return
    end
    self.watchTimer = 0
    for vehicle, _ in pairs(self.ghosted) do
        if vehicle.isDeleted or vehicle.ad == nil then
            self.ghosted[vehicle] = nil
        elseif not vehicle.ad.escapeActive and not self.isTouchingOtherVehicle(vehicle, self.CLEAR_MARGIN) then
            self.setGhost(vehicle, false)
        end
    end
end
