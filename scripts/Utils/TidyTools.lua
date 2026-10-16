-- Tidy-up tools for the route editor: even spacing, straighten and smooth a chain of waypoints.
-- They only move waypoints. The first and the last waypoint of the chain stay where they are,
-- connections, flags and targets are not changed.

ADTidyTools = {}

ADTidyTools.EVEN = 1
ADTidyTools.STRAIGHTEN = 2
ADTidyTools.SMOOTH = 3

ADTidyTools.SMOOTH_ITERATIONS = 4
ADTidyTools.SMOOTH_STRENGTH = 0.5
-- moves shorter than this are left out
ADTidyTools.MIN_MOVE = 0.01

-- length along the chain of points {x, z}, per point
local function arcLengths(points)
    local lengths = {0}
    for i = 2, #points do
        lengths[i] = lengths[i - 1] + MathUtil.vector2Length(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z)
    end
    return lengths
end

-- position at distance d along the chain
local function pointAt(points, lengths, d)
    for i = 2, #points do
        if d <= lengths[i] or i == #points then
            local segment = lengths[i] - lengths[i - 1]
            local t = 0
            if segment > 0 then
                t = math.max(0, math.min(1, (d - lengths[i - 1]) / segment))
            end
            return points[i - 1].x + (points[i].x - points[i - 1].x) * t, points[i - 1].z + (points[i].z - points[i - 1].z) * t
        end
    end
    return points[#points].x, points[#points].z
end

-- same path, waypoints at equal distances
function ADTidyTools.evenSpacing(points)
    local lengths = arcLengths(points)
    local total = lengths[#points]
    local result = {}
    for i = 1, #points do
        local x, z = pointAt(points, lengths, total * (i - 1) / (#points - 1))
        result[i] = {x = x, z = z}
    end
    return result
end

-- straight line between the first and the last waypoint, at equal distances
function ADTidyTools.straighten(points)
    local first, last = points[1], points[#points]
    local result = {}
    for i = 1, #points do
        local t = (i - 1) / (#points - 1)
        result[i] = {x = first.x + (last.x - first.x) * t, z = first.z + (last.z - first.z) * t}
    end
    return result
end

-- removes kinks: each waypoint moves towards the middle of its neighbours, a few times
function ADTidyTools.smooth(points)
    local current = {}
    for i, p in ipairs(points) do
        current[i] = {x = p.x, z = p.z}
    end
    for _ = 1, ADTidyTools.SMOOTH_ITERATIONS do
        local nextPoints = {current[1]}
        for i = 2, #current - 1 do
            local midX = (current[i - 1].x + current[i + 1].x) / 2
            local midZ = (current[i - 1].z + current[i + 1].z) / 2
            nextPoints[i] = {
                x = current[i].x + (midX - current[i].x) * ADTidyTools.SMOOTH_STRENGTH,
                z = current[i].z + (midZ - current[i].z) * ADTidyTools.SMOOTH_STRENGTH
            }
        end
        nextPoints[#current] = current[#current]
        current = nextPoints
    end
    return current
end

-- new positions {x, z} for the points of the chain, or nil if the chain is too short
function ADTidyTools.calculate(tool, points)
    if #points < 3 then
        return nil
    end
    if tool == ADTidyTools.EVEN then
        return ADTidyTools.evenSpacing(points)
    elseif tool == ADTidyTools.STRAIGHTEN then
        return ADTidyTools.straighten(points)
    elseif tool == ADTidyTools.SMOOTH then
        return ADTidyTools.smooth(points)
    end
    return nil
end

-- moves {id, x, y, z} for the waypoint ids of a chain; heights follow the terrain like
-- the curves of the editor do, unless getHeight is nil (then the old height is kept)
function ADTidyTools.getMoves(tool, wayPointIds, getHeight)
    local points = {}
    for i, id in ipairs(wayPointIds) do
        local wp = ADGraphManager:getWayPointById(id)
        if wp == nil then
            return nil
        end
        points[i] = {x = wp.x, y = wp.y, z = wp.z, id = id}
    end
    local positions = ADTidyTools.calculate(tool, points)
    if positions == nil then
        return nil
    end
    local moves = {}
    for i = 2, #points - 1 do
        local old, new = points[i], positions[i]
        if MathUtil.vector2Length(new.x - old.x, new.z - old.z) > ADTidyTools.MIN_MOVE then
            local y = old.y
            if getHeight ~= nil then
                y = getHeight(new.x, old.y, new.z)
            end
            table.insert(moves, {id = old.id, x = new.x, y = y, z = new.z})
        end
    end
    return moves
end

-- waypoints searched at most when looking for the route between two waypoints
ADTidyTools.MAX_SEARCH = 20000

-- the shortest chain of connected waypoints from startId to endId (in either direction), or nil
function ADTidyTools.findChain(startId, endId)
    local previous = {[startId] = startId}
    local queue, head = {startId}, 1
    while head <= #queue and #queue < ADTidyTools.MAX_SEARCH do
        local id = queue[head]
        head = head + 1
        if id == endId then
            local chain = {}
            while id ~= startId do
                table.insert(chain, 1, id)
                id = previous[id]
            end
            table.insert(chain, 1, startId)
            return chain
        end
        local wp = ADGraphManager:getWayPointById(id)
        for _, list in ipairs({wp.out, wp.incoming}) do
            for _, neighbourId in ipairs(list) do
                if previous[neighbourId] == nil and ADGraphManager:getWayPointById(neighbourId) ~= nil then
                    previous[neighbourId] = id
                    queue[#queue + 1] = neighbourId
                end
            end
        end
    end
    return nil
end

-- height of the surface at the new position of a waypoint that was at height y:
-- near the old height first (bridges), else the ground (the point moved up a hill or into a dip)
function ADTidyTools.groundHeight(x, y, z)
    local height = AutoDrive:getTerrainHeightAtWorldPos(x, z, y)
    if AutoDrive.raycastHeight ~= nil then
        return height
    end
    return AutoDrive:getTerrainHeightAtWorldPos(x, z)
end

-- editor key: tidy up the route between the selected waypoint and the one under the mouse
function ADTidyTools.apply(vehicle, tool)
    if not AutoDrive.isEditorModeEnabled() or vehicle == nil or vehicle.ad == nil then
        return
    end
    local startId, endId = vehicle.ad.selectedNodeId, vehicle.ad.hoveredNodeId
    local chain
    if startId ~= nil and endId ~= nil and startId ~= endId and ADGraphManager:getWayPointById(startId) ~= nil and ADGraphManager:getWayPointById(endId) ~= nil then
        chain = ADTidyTools.findChain(startId, endId)
    end
    if chain == nil or #chain < 3 then
        ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, g_i18n:getText("AD_tidy_howTo"), 5000)
        return
    end
    local moves = ADTidyTools.getMoves(tool, chain, ADTidyTools.groundHeight)
    if moves == nil or #moves == 0 then
        ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, g_i18n:getText("AD_tidy_nothing"), 3000)
        return
    end
    ADGraphManager:moveWayPoints(moves)
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, string.format(g_i18n:getText("AD_tidy_done"), #moves, #chain), 4000)
end
