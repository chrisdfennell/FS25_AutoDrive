-- random editor operations, generated on the server runtime
-- returns serverCode, clientCode (the same unless the server is the dragging host)

local function r(a, b)
    return math.random(a, b)
end
local function rf()
    return math.random(0, 100000) / 100
end
local function b2s(b)
    return b and "true" or "false"
end

local function randomGroup(includeAll)
    local names = {}
    for name, _ in pairs(ADGraphManager.groups) do
        if includeAll or name ~= "All" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    if #names == 0 then
        return nil
    end
    return names[r(1, #names)]
end

local FOLDER_NAMES = {"F1", "F2", "F3", "F1/S1", "F1/S2", "F2/S1/T1", "G3"}

function randomOp()
    local n = #ADGraphManager.wayPoints
    local m = #ADGraphManager.mapMarkers
    local kind = r(1, 18)
    if kind == 15 then
        local c = string.format("ADGraphManager:addGroup(%q, false)", FOLDER_NAMES[r(1, #FOLDER_NAMES)]); return c, c
    elseif kind == 16 then
        local name = randomGroup(false)
        if name == nil then
            return nil
        end
        local c = string.format("ADGraphManager:removeGroup(%q, false)", name); return c, c
    elseif kind == 17 then
        local name = randomGroup(false)
        if name == nil then
            return nil
        end
        local c = string.format("ADGraphManager:renameGroup(%q, %q, false)", name, FOLDER_NAMES[r(1, #FOLDER_NAMES)] .. "x" .. r(1, 9)); return c, c
    elseif kind == 18 then
        local name = randomGroup(true)
        if math.random() < 0.3 then
            local c = string.format("ADGraphManager:setGroupColor(%q, nil, false)", name); return c, c
        end
        local c = string.format("ADGraphManager:setGroupColor(%q, {%s, %s, %s}, false)", name, math.random(0, 100) / 100, math.random(0, 100) / 100, math.random(0, 100) / 100); return c, c
    end
    local code
    if kind == 1 and n > 5 then
        code = string.format("ADGraphManager:removeWayPoint(%d, false)", r(1, n))
    elseif kind == 2 and n > 8 then
        -- multi selection delete event, ids sorted descending as the hud does
        local ids, set = {}, {}
        while #ids < 3 do
            local id = r(1, n)
            if not set[id] then
                set[id] = true
                ids[#ids + 1] = id
            end
        end
        table.sort(ids, function(a, b) return a > b end)
        code = "ADUndoManager:beginStep() "
        for _, id in ipairs(ids) do
            code = code .. string.format("ADGraphManager:removeWayPoint(%d, false) ", id)
        end
        code = code .. "ADUndoManager:endStep()"
    elseif kind == 3 then
        code = string.format("ADGraphManager:createWayPointWithConnections(%s, 5, %s, {}, {}, %d, false, false, false, %s, false)", rf(), rf(), r(0, 1), (math.random() < 0.5) and tostring(r(1, 9)) or "nil")
    elseif kind == 4 and n > 1 then
        code = string.format("ADGraphManager:createWayPointWithConnections(%s, 5, %s, {%d}, {%d}, 0, true, %s, %s, nil, false)", rf(), rf(), n + 1, r(1, n), b2s(math.random() < 0.3), b2s(math.random() < 0.3))
    elseif kind == 5 and n > 2 then
        local a, b = r(1, n), r(1, n)
        if a == b then
            return nil
        end
        code = string.format("ADGraphManager:toggleConnectionBetween(ADGraphManager:getWayPointById(%d), ADGraphManager:getWayPointById(%d), %s, %s, false)", a, b, b2s(math.random() < 0.3), b2s(math.random() < 0.3))
    elseif kind == 6 and n > 2 then
        local a, b = r(1, n), r(1, n)
        if a == b then
            return nil
        end
        code = string.format("ADGraphManager:setConnectionBetween(ADGraphManager:getWayPointById(%d), ADGraphManager:getWayPointById(%d), %d, false)", a, b, r(1, 4))
    elseif kind == 7 and n > 0 then
        code = string.format("ADGraphManager:moveWayPoint(%d, %s, 7, %s, %d, false)", r(1, n), rf(), rf(), r(0, 1))
    elseif kind == 8 and n > 0 then
        -- host drags a waypoint: moved locally first, the event carries the final position
        local id = r(1, n)
        local serverCode = string.format(
            "local wp = ADGraphManager:getWayPointById(%d); AutoDrive.moveNodeToMousePosSim(wp, %s, %s); AutoDrive.moveNodeToMousePosSim(wp, %s, %s); " ..
            "LAST_CLIENT_CODE = string.format('ADGraphManager:moveWayPoint(%d, %%s, %%s, %%s, %%d, false)', serialize(wp.x), serialize(wp.y), serialize(wp.z), wp.flags); " ..
            "ADGraphManager:moveWayPoint(%d, wp.x, wp.y, wp.z, wp.flags, false)",
            id, rf(), rf(), rf(), rf(), id, id)
        return serverCode, "FROM_SERVER"
    elseif kind == 9 and n > 0 then
        code = string.format("ADGraphManager:createMapMarker(%d, %q, false)", r(1, n), "N" .. r(1, 999))
    elseif kind == 10 and m > 0 then
        code = string.format("ADGraphManager:removeMapMarker(%d, false)", r(1, m))
    elseif kind == 11 and m > 0 then
        code = string.format("ADGraphManager:renameMapMarker(%q, %d, false)", "R" .. r(1, 999), r(1, m))
    elseif kind == 12 and m > 0 then
        code = string.format("ADGraphManager:changeMapMarkerGroup(%q, %d, false)", randomGroup(true), r(1, m))
    elseif kind == 13 and n > 0 then
        code = string.format("ADGraphManager:recordWayPoint(%s, 3, %s, %s, %s, %s, %d, 0, false)", rf(), rf(), b2s(math.random() < 0.7), b2s(math.random() < 0.3), b2s(math.random() < 0.2), r(0, n))
    elseif kind == 14 and n > 2 then
        local a, b = r(1, n), r(1, n)
        if a == b then
            return nil
        end
        code = string.format("ADGraphManager:createSplineConnection(%d, {{x=%s,y=5,z=%s},{x=%s,y=5.5,z=%s},{x=%s,y=9,z=%s}}, %d, %s, false)", a, rf(), rf(), rf(), rf(), rf(), rf(), b, b2s(math.random() < 0.5))
    end
    return code, code
end

-- simplified AutoDrive.moveNodeToMousePos: same undoOrigin handling, fixed target instead of the mouse
function AutoDrive.moveNodeToMousePosSim(node, x, z)
    if node.undoOrigin == nil then
        node.undoOrigin = {x = node.x, y = node.y, z = node.z}
    end
    node.x, node.z = x, z
    node.y = node.y + 1
end
