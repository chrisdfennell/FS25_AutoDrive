-- PropaineX edit: keep a waiting combine unloader out of the harvesters' way.
-- While the unloader waits on the field to be called (STATE_WAIT_TO_BE_CALLED) it checks every CHECK_INTERVAL
-- whether it stands where a working harvester is going to drive:
--   * ahead: in the strip in front of the harvester (working width + UNSAFE_MARGIN each side, AHEAD_LENGTH long)
--   * crop: closer than UNSAFE_MARGIN to standing crop (where the next passes go)
--   * headland: in the band along the field edge where the harvester turns (getHeadland)
-- When it does for UNSAFE_TIME it drives (MoveClearOfHarvesterTask, pathfinder) to the nearest spot on harvested
-- ground that is SAFE_MARGIN clear of all of that, else to just outside the field edge, and waits there again.
-- Choppers (forage harvesters, ad.isChopper) count the same as combines (user's rule: never in their way either).
ADUnloaderClear = {}

ADUnloaderClear.CHECK_INTERVAL = 1000   -- ms between checks
ADUnloaderClear.UNSAFE_TIME = 3000      -- ms in the way before it moves (the harvester may just be pulling away)
ADUnloaderClear.UNSAFE_MARGIN = 10      -- m: closer than this counts as in the way
ADUnloaderClear.SAFE_MARGIN = 15        -- m: a new spot is at least this clear
ADUnloaderClear.HARVESTER_RANGE = 200   -- m: harvesters further away are not looked at
ADUnloaderClear.AHEAD_LENGTH = 50       -- m: the strip in front of the harvester (3.4.1.4: was 80)
ADUnloaderClear.AHEAD_MARGIN = 5        -- m: the strip is this much wider than the header on each side (3.4.1.4: was 10)
ADUnloaderClear.TURN_REACH = 200        -- m: how far sideways the turn zone reaches toward the turn side (the field clips it)
ADUnloaderClear.FIELD_SCAN = 400        -- m: how far ahead it looks for the end of the field
ADUnloaderClear.MIN_WORK_WIDTH = 6      -- m
ADUnloaderClear.HEADLAND_MIN = 20       -- m: the turning band along the field edge, at least this or 2 working widths
ADUnloaderClear.SEARCH_RINGS = {15, 25, 40, 60, 80}  -- m from the unloader where new spots are tried
ADUnloaderClear.SEARCH_DIRECTIONS = 16
ADUnloaderClear.OUTSIDE_DISTANCE = 15   -- m past the field edge when no spot on the field is clear
ADUnloaderClear.MAX_FAILS = 3           -- failed moves in a row before it waits FAIL_COOLDOWN
ADUnloaderClear.FAIL_COOLDOWN = 60000   -- ms
ADUnloaderClear.MOVE_COOLDOWN = 15000   -- ms after a move before the next check
ADUnloaderClear.MAX_SPEED = 2           -- km/h: only checked while standing

local function terrainY(x, z)
    if getTerrainHeightAtWorldPos ~= nil and g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
        return getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    end
    return 0
end

local function isOnField(x, z)
    return AutoDrive.checkIsOnField(x, terrainY(x, z), z)
end

function ADUnloaderClear.getWorkWidth(harvester, root)
    local width = 0
    if AutoDrive.getFrontToolWidth ~= nil then
        width = math.max(AutoDrive.getFrontToolWidth(root) or 0, width)
    end
    -- PropaineX edit (3.10.0.0): Nexat: header width from the module (in front of it, not of the carrier) and the
    -- carrier's length is the rig's width
    local module = AutoDrive.getSidewaysHarvester(harvester)
    if module ~= nil then
        if AutoDrive.getFrontToolWidth ~= nil then
            width = math.max(AutoDrive.getFrontToolWidth(module) or 0, width)
        end
        width = math.max(width, AutoDrive.getHarvesterHalfSize(module) * 2)
    end
    for _, unit in ipairs({harvester, root}) do
        if unit.size ~= nil and unit.size.width ~= nil then
            width = math.max(width, unit.size.width)
        end
    end
    return math.max(width, ADUnloaderClear.MIN_WORK_WIDTH)
end

-- the fruit a harvester cuts (nil: unknown)
function ADUnloaderClear.getHarvestFruit(harvester)
    local spec = harvester.spec_combine
    if spec ~= nil and spec.fillUnitIndex ~= nil and spec.fillUnitIndex ~= 0 and harvester.getFillUnitFillType ~= nil then
        local fillType = harvester:getFillUnitFillType(spec.fillUnitIndex)
        if fillType ~= nil then
            return g_fruitTypeManager:getFruitTypeIndexByFillTypeIndex(fillType)
        end
    end
    return nil
end

-- the working harvesters (combines and choppers) near the vehicle: {harvester, root, width}
function ADUnloaderClear.getHarvesters(vehicle)
    local list = {}
    if ADHarvestManager == nil then
        return list
    end
    for _, harvester in pairs(ADHarvestManager.harvesters or {}) do
        if harvester ~= nil and harvester.ad ~= nil then
            local root = harvester.getRootVehicle ~= nil and harvester:getRootVehicle() or harvester
            if root ~= nil and root.components ~= nil and root ~= vehicle
                and AutoDrive.getDistanceBetween(vehicle, root) < ADUnloaderClear.HARVESTER_RANGE then
                -- PropaineX edit (3.10.0.0): frame = the vehicle facing the way it harvests (the module on a Nexat)
                table.insert(list, {harvester = harvester, root = root, frame = AutoDrive.getHarvesterFrameVehicle(root),
                    width = ADUnloaderClear.getWorkWidth(harvester, root)})
            end
        end
    end
    return list
end

-- the fruits to look for: those the harvesters cut, or every fruit when one is unknown (nil)
function ADUnloaderClear.getFruits(harvesters)
    local fruits, seen = {}, {}
    for _, entry in ipairs(harvesters) do
        local fruit = ADUnloaderClear.getHarvestFruit(entry.harvester)
        if fruit == nil then
            return nil
        end
        if not seen[fruit] then
            seen[fruit] = true
            table.insert(fruits, fruit)
        end
    end
    return fruits
end

-- the strip in front of the harvester, margin wider on each side than it works
function ADUnloaderClear.getAheadBox(entry, margin)
    local root = entry.frame or entry.root -- PropaineX edit (3.10.0.0): Nexat
    local x, y, z = getWorldTranslation(root.components[1].node)
    local dirX, _, dirZ = AutoDrive.localDirectionToWorld(root, 0, 0, 1)
    local _, halfLength = AutoDrive.getHarvesterHalfSize(root)
    local length = halfLength * 2
    local centre = length / 2 + ADUnloaderClear.AHEAD_LENGTH / 2
    return ADUnloaderEscape.makeBox(x + dirX * centre, y, z + dirZ * centre, dirX, dirZ,
        entry.width / 2 + margin, ADUnloaderClear.AHEAD_LENGTH / 2)
end

function ADUnloaderClear.getHeadland(harvesters)
    local width = 0
    for _, entry in ipairs(harvesters) do
        width = math.max(width, entry.width)
    end
    return math.max(ADUnloaderClear.HEADLAND_MIN, 2 * width)
end

-- standing crop in the box (corners as ADUnloaderEscape.makeBox: 1 and 2 one end, 4 the other side)
function ADUnloaderClear.hasCrop(box, fruits)
    local c1, c2, c4 = box[1], box[2], box[4]
    if fruits == nil then
        return AutoDrive.checkForUnknownFruitInArea({c1, c2, c4})
    end
    for _, fruit in ipairs(fruits) do
        if AutoDrive.getFruitValue(fruit, c1.x, c1.z, c2.x, c2.z, c4.x, c4.z) > 10 then
            return true
        end
    end
    return false
end

-- the field edge closer than distance (checked in 8 directions)
function ADUnloaderClear.isNearFieldEdge(x, z, distance)
    for i = 0, 7 do
        local angle = i * math.pi / 4
        local dx, dz = math.sin(angle), math.cos(angle)
        for _, d in ipairs({distance / 2, distance}) do
            if not isOnField(x + dx * d, z + dz * d) then
                return true
            end
        end
    end
    return false
end

-- why the vehicle (all its units) is in the way, or nil
function ADUnloaderClear.getDanger(vehicle, harvesters, fruits)
    local boxes = ADUnloaderEscape.getUnitBoxes(vehicle)
    for _, entry in ipairs(harvesters) do
        local ahead = ADUnloaderClear.getAheadBox(entry, ADUnloaderClear.AHEAD_MARGIN)
        for _, box in ipairs(boxes) do
            if AutoDrive.boxesIntersect(ahead, box) then
                return "ahead"
            end
        end
    end
    -- PropaineX edit (3.4.1.4): next to standing crop is fine now (no crop rule); the headland only counts where
    -- the harvester is going to turn
    for _, zone in ipairs(ADUnloaderClear.getTurnZones(harvesters, fruits)) do
        for _, box in ipairs(boxes) do
            if AutoDrive.boxesIntersect(zone, box) then
                return "turn"
            end
        end
    end
    return nil
end

-- PropaineX edit (3.4.1.4): where a harvester will turn: the headland band at the end of the field it is heading to,
-- from its own lane (header + AHEAD_MARGIN) toward the side with standing crop (it turns into the next pass). Crop on
-- neither or both sides: both directions. nil when the field end isn't found ahead.
function ADUnloaderClear.getTurnZone(entry, headland, fruits)
    local root = entry.frame or entry.root -- PropaineX edit (3.10.0.0): Nexat
    local x, y, z = getWorldTranslation(root.components[1].node)
    local dirX, _, dirZ = AutoDrive.localDirectionToWorld(root, 0, 0, 1)
    local dist = nil
    for d = 5, ADUnloaderClear.FIELD_SCAN, 5 do
        if not isOnField(x + dirX * d, z + dirZ * d) then
            dist = d
            break
        end
    end
    if dist == nil then
        return nil
    end
    -- sideways axis, the same one makeBox uses for its width
    local px, pz = -dirZ, dirX
    local side = entry.width / 2 + 8
    local function cropOn(sign)
        local cx, cz = x + px * sign * side + dirX * 10, z + pz * sign * side + dirZ * 10
        return ADUnloaderClear.hasCrop(ADUnloaderEscape.makeBox(cx, y, cz, dirX, dirZ, 5, 15), fruits)
    end
    local plus, minus = cropOn(1), cropOn(-1)
    local inner = entry.width / 2 + ADUnloaderClear.AHEAD_MARGIN
    local u0, u1 = -ADUnloaderClear.TURN_REACH, ADUnloaderClear.TURN_REACH
    if plus and not minus then
        u0 = -inner
    elseif minus and not plus then
        u1 = inner
    end
    local v0, v1 = dist - 5 - headland, dist + 5 -- the edge lies between dist - 5 (on the field) and dist
    local cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
    return ADUnloaderEscape.makeBox(x + px * cu + dirX * cv, y, z + pz * cu + dirZ * cv, dirX, dirZ, (u1 - u0) / 2, (v1 - v0) / 2)
end

function ADUnloaderClear.getTurnZones(harvesters, fruits)
    local zones = {}
    local headland = ADUnloaderClear.getHeadland(harvesters)
    for _, entry in ipairs(harvesters) do
        local zone = ADUnloaderClear.getTurnZone(entry, headland, fruits)
        if zone ~= nil then
            table.insert(zones, zone)
        end
    end
    return zones
end

-- a spot for the whole rig at x, z (pointing dirX, dirZ) that is clear by SAFE_MARGIN
function ADUnloaderClear.isSafeSpot(vehicle, x, z, dirX, dirZ, harvesters, zones, halfLength)
    local foot = ADUnloaderEscape.makeBox(x, terrainY(x, z), z, dirX, dirZ, 2, halfLength)
    for i = 1, 4 do
        if not isOnField(foot[i].x, foot[i].z) then
            return false
        end
    end
    -- PropaineX edit (3.4.1.4): clear of where the harvesters turn (was: of the whole headland)
    local grown = ADUnloaderEscape.growBox(foot, ADUnloaderClear.SAFE_MARGIN - ADUnloaderClear.UNSAFE_MARGIN)
    for _, zone in ipairs(zones) do
        if AutoDrive.boxesIntersect(zone, grown) then
            return false
        end
    end
    for _, entry in ipairs(harvesters) do
        if AutoDrive.boxesIntersect(ADUnloaderClear.getAheadBox(entry, ADUnloaderClear.SAFE_MARGIN), foot) then
            return false
        end
    end
    if AutoDrive.checkForVehiclesInBox(ADUnloaderEscape.growBox(foot, 3), {vehicle}) then
        return false
    end
    return true -- PropaineX edit (3.4.1.4): next to standing crop is fine
end

-- the nearest clear spot, tried first in the directions away from the harvesters; else just outside the field.
-- returns x, z, dirX, dirZ or nil
function ADUnloaderClear.findSafeSpot(vehicle, harvesters, fruits, minDistance)
    local x, _, z = getWorldTranslation(vehicle.components[1].node)
    local zones = ADUnloaderClear.getTurnZones(harvesters, fruits)
    local halfLength = math.max(AutoDrive.getTractorTrainLength(vehicle, true, false) or 0, 6) / 2
    -- away from the harvesters, and the direction they work in (to park along)
    local awayX, awayZ, workX, workZ = 0, 0, 0, 0
    for _, entry in ipairs(harvesters) do
        local hx, _, hz = getWorldTranslation(entry.root.components[1].node)
        local d = math.max(MathUtil.vector2Length(x - hx, z - hz), 1)
        awayX, awayZ = awayX + (x - hx) / d, awayZ + (z - hz) / d
        local dx, _, dz = AutoDrive.localDirectionToWorld(entry.frame or entry.root, 0, 0, 1) -- PropaineX edit (3.10.0.0): Nexat
        workX, workZ = workX + dx, workZ + dz
    end
    local workLength = MathUtil.vector2Length(workX, workZ)
    if workLength < 0.01 then
        workX, _, workZ = AutoDrive.localDirectionToWorld(vehicle, 0, 0, 1)
    else
        workX, workZ = workX / workLength, workZ / workLength
    end
    -- park along the working direction, the way that points away from the harvesters
    if workX * awayX + workZ * awayZ < 0 then
        workX, workZ = -workX, -workZ
    end
    local directions = {}
    for i = 0, ADUnloaderClear.SEARCH_DIRECTIONS - 1 do
        local angle = i * 2 * math.pi / ADUnloaderClear.SEARCH_DIRECTIONS
        local dx, dz = math.sin(angle), math.cos(angle)
        table.insert(directions, {x = dx, z = dz, score = dx * awayX + dz * awayZ})
    end
    table.sort(directions, function(a, b) return a.score > b.score end)
    for _, ring in ipairs(ADUnloaderClear.SEARCH_RINGS) do
        -- PropaineX edit (3.6.0.4): minDistance: only spots at least that far away (moving aside after no path)
        for _, dir in ipairs(ring >= (minDistance or 0) and directions or {}) do
            local px, pz = x + dir.x * ring, z + dir.z * ring
            if ADUnloaderClear.isSafeSpot(vehicle, px, pz, workX, workZ, harvesters, zones, halfLength) then
                return px, pz, workX, workZ
            end
        end
    end
    -- no clear spot on the field: just outside its edge
    local ex, ez = ADUnloaderEscape.findFieldEdge(x, z)
    if ex ~= nil then
        local dx, dz = ex - x, ez - z
        local d = MathUtil.vector2Length(dx, dz)
        if d > 0.01 then
            dx, dz = dx / d, dz / d
            local extra = math.max(ADUnloaderClear.OUTSIDE_DISTANCE - ADUnloaderEscape.EDGE_OUTSIDE, 0)
            if minDistance == nil or d + extra >= minDistance then
                return ex + dx * extra, ez + dz * extra, dx, dz
            end
        end
    end
    return nil
end

-- PropaineX edit (3.6.1.4): standing still while planning a route to a harvester (CatchCombinePipeTask planning or
-- waiting to plan, EmptyHarvesterTask planning)
function ADUnloaderClear.isPlanning(vehicle)
    local task = vehicle.ad.taskModule ~= nil and vehicle.ad.taskModule:getActiveTask() or nil
    if task == nil then
        return false
    end
    if task.taskType == "CatchCombinePipeTask" then
        return task.state == CatchCombinePipeTask.STATE_PATHPLANNING or task.state == CatchCombinePipeTask.STATE_DELAY_PATHPLANNING
    elseif task.taskType == "EmptyHarvesterTask" then
        return task.state == EmptyHarvesterTask.STATE_PATHPLANNING
    end
    return false
end

-- every frame from CombineUnloaderMode:monitorTasks (server); true when it has started a move.
-- PropaineX edit (3.6.1.4): also while it plans a route to a harvester, and then getting out of the way comes first: it
-- moves at the first check (no UNSAFE_TIME), lets go of the job (the next free unloader is sent, or it is called again
-- once it waits) and, without a clear spot, drives 25 m straight.
function ADUnloaderClear.monitor(mode, dt)
    local vehicle = mode.vehicle
    local planning = mode.state ~= mode.STATE_WAIT_TO_BE_CALLED and ADUnloaderClear.isPlanning(vehicle)
    if g_server == nil or (mode.state ~= mode.STATE_WAIT_TO_BE_CALLED and not planning) then
        mode.clearUnsafeTime = 0
        return false
    end
    mode.clearCheckTimer = (mode.clearCheckTimer or 0) + dt
    if mode.clearCheckTimer < ADUnloaderClear.CHECK_INTERVAL then
        return false
    end
    local elapsed = mode.clearCheckTimer
    mode.clearCheckTimer = 0
    if mode.clearCooldownUntil ~= nil and (g_time or 0) < mode.clearCooldownUntil then
        return false
    end
    if vehicle.lastSpeedReal ~= nil and vehicle.lastSpeedReal * 3600 > ADUnloaderClear.MAX_SPEED then
        return false
    end
    local x, _, z = getWorldTranslation(vehicle.components[1].node)
    local harvesters = isOnField(x, z) and ADUnloaderClear.getHarvesters(vehicle) or {}
    if #harvesters == 0 then
        mode.clearUnsafeTime = 0
        return false
    end
    local fruits = ADUnloaderClear.getFruits(harvesters)
    local danger = ADUnloaderClear.getDanger(vehicle, harvesters, fruits)
    if danger == nil then
        mode.clearUnsafeTime = 0
        return false
    end
    mode.clearUnsafeTime = (mode.clearUnsafeTime or 0) + elapsed
    if not planning and mode.clearUnsafeTime < ADUnloaderClear.UNSAFE_TIME then
        return false
    end
    mode.clearUnsafeTime = 0
    local tx, tz, dirX, dirZ = ADUnloaderClear.findSafeSpot(vehicle, harvesters, fruits)
    if planning then
        Logging.info("[AD] %s: in a harvester's way (%s) while planning a route, moving out of the way first", ADDiag.name(vehicle), danger)
        ADUnloaderClear.start(mode, tx, tz, dirX, dirZ, true)
        mode.combine = nil
        mode.followingUnloader = nil
        mode.targetUnloader = nil
        return true
    end
    if tx == nil then
        ADUnloaderClear.onMoveFailed(vehicle)
        return false
    end
    AutoDrive.debugPrint(vehicle, AutoDrive.DC_COMBINEINFO, "ADUnloaderClear: in the way of a harvester (%s), moving to %.0f %.0f", danger, tx, tz)
    ADUnloaderClear.start(mode, tx, tz, dirX, dirZ)
    return true
end

function ADUnloaderClear.start(mode, x, z, dirX, dirZ, straightFallback)
    local vehicle = mode.vehicle
    -- not idle while moving, or the harvest manager could assign it and get no answer
    ADHarvestManager:unregisterAsUnloader(vehicle)
    vehicle.ad.specialDrivingModule:releaseVehicle()
    vehicle.ad.taskModule:abortAllTasks()
    local target = x ~= nil and {x = x, y = terrainY(x, z), z = z} or nil
    local direction = dirX ~= nil and {x = dirX, z = dirZ} or nil
    mode.activeTask = MoveClearOfHarvesterTask:new(vehicle, target, direction, straightFallback)
    mode.state = mode.STATE_MOVE_CLEAR
    vehicle.ad.taskModule:addTask(mode.activeTask)
end

-- PropaineX edit (3.6.0.4): after no path to a harvester: to the closest safe spot at least minDistance away, else
-- minDistance straight ahead (MoveClearOfHarvesterTask straight fallback); then it waits for a call again
function ADUnloaderClear.moveAside(mode, minDistance)
    local vehicle = mode.vehicle
    local harvesters = ADUnloaderClear.getHarvesters(vehicle)
    local fruits = ADUnloaderClear.getFruits(harvesters)
    local x, z, dirX, dirZ = ADUnloaderClear.findSafeSpot(vehicle, harvesters, fruits, minDistance)
    ADUnloaderClear.start(mode, x, z, dirX, dirZ, true)
end

local function getMode(vehicle)
    return vehicle ~= nil and vehicle.ad ~= nil and vehicle.ad.modes ~= nil and vehicle.ad.modes[AutoDrive.MODE_UNLOAD] or nil
end

function ADUnloaderClear.onMoveDone(vehicle)
    local mode = getMode(vehicle)
    if mode ~= nil then
        mode.clearFails = 0
        mode.clearCooldownUntil = (g_time or 0) + ADUnloaderClear.MOVE_COOLDOWN
    end
end

function ADUnloaderClear.onMoveFailed(vehicle)
    local mode = getMode(vehicle)
    if mode == nil then
        return
    end
    mode.clearFails = (mode.clearFails or 0) + 1
    if mode.clearFails >= ADUnloaderClear.MAX_FAILS then
        mode.clearFails = 0
        mode.clearCooldownUntil = (g_time or 0) + ADUnloaderClear.FAIL_COOLDOWN
    else
        mode.clearCooldownUntil = (g_time or 0) + ADUnloaderClear.MOVE_COOLDOWN
    end
end
