-- Route preview: the whole path from the vehicle to its destination (for pickup and deliver also on to the
-- unload target), drawn in the world, on the minimap and on the big map (ESC > Map), with distance and drive time.
-- Only reads the network, works on every machine.

ADRoutePreview = {}

ADRoutePreview.COLORS = {{0.1, 0.8, 1}, {1, 0.55, 0.1}}
ADRoutePreview.LINE_HEIGHT = 1
-- world lines are drawn up to this far from the vehicle
ADRoutePreview.WORLD_RANGE = 400
-- at most this many line pieces per leg on the maps, a long route is simplified
ADRoutePreview.MAP_MAX_SEGMENTS = 400
ADRoutePreview.MAP_LINE_PIXELS = 3

function ADRoutePreview:load()
    self.legs = nil
    self.vehicle = nil
end

-- points of one leg: {x, y, z} of the path waypoints
local function toPoints(path)
    local points = {}
    for _, wp in ipairs(path or {}) do
        if wp.x ~= nil then
            table.insert(points, {x = wp.x, y = wp.y, z = wp.z, id = wp.id})
        end
    end
    return points
end

function ADRoutePreview.getLength(points)
    local length = 0
    for i = 2, #points do
        length = length + MathUtil.vector2Length(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z)
    end
    return length
end

-- every n-th point so that a leg has at most maxSegments pieces (first and last point always)
function ADRoutePreview.simplify(points, maxSegments)
    if #points <= maxSegments + 1 then
        return points
    end
    local result = {}
    local step = (#points - 1) / maxSegments
    for i = 0, maxSegments do
        table.insert(result, points[math.floor(i * step + 0.5) + 1])
    end
    return result
end

-- drive time in seconds for the points, at the vehicle's road speed
function ADRoutePreview.getDriveTime(points, speedLimit)
    if #points < 2 then
        return 0
    end
    local time = ADGraphManager:getDriveTimeForWaypoints(points, 1, speedLimit)
    if time == nil or time <= 0 then
        -- fallback: straight driving at the speed limit
        time = ADRoutePreview.getLength(points) / math.max(1, speedLimit / 3.6)
    end
    return time
end

-- the legs to show for the vehicle's mode: {targetName, points}
function ADRoutePreview.getLegs(vehicle)
    local stateModule = vehicle.ad.stateModule
    local mode = stateModule:getMode()
    local first, second = stateModule:getFirstMarker(), stateModule:getSecondMarker()
    local legs = {}
    local target = first
    if mode == AutoDrive.MODE_DELIVERTO then
        target = second
    end
    if target == nil or target.id == nil then
        return legs
    end
    table.insert(legs, {name = target.name, points = toPoints(ADGraphManager:getPathTo(vehicle, target.id))})
    if mode == AutoDrive.MODE_PICKUPANDDELIVER and second ~= nil and second.id ~= nil and first.id ~= second.id then
        table.insert(legs, {name = second.name, points = toPoints(ADGraphManager:pathFromTo(first.id, second.id))})
    end
    return legs
end

function ADRoutePreview.formatDuration(seconds)
    local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
    if minutes < 60 then
        return string.format("%d min", minutes)
    end
    return string.format("%d:%02d h", math.floor(minutes / 60), minutes % 60)
end

-- key: show or hide the preview for the vehicle
function ADRoutePreview:toggle(vehicle)
    if vehicle == nil or vehicle.ad == nil or g_dedicatedServer ~= nil then
        return
    end
    if self.legs ~= nil and self.vehicle == vehicle then
        self.legs = nil
        self.vehicle = nil
        return
    end
    local legs = ADRoutePreview.getLegs(vehicle)
    local speedLimit = vehicle.ad.stateModule:getSpeedLimit()
    local texts = {}
    for i, leg in ipairs(legs) do
        if #leg.points < 1 then
            ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, string.format(g_i18n:getText("AD_preview_noRoute"), tostring(leg.name)), 5000)
            return
        end
        leg.length = ADRoutePreview.getLength(leg.points)
        leg.time = ADRoutePreview.getDriveTime(leg.points, speedLimit)
        leg.mapPoints = ADRoutePreview.simplify(leg.points, ADRoutePreview.MAP_MAX_SEGMENTS)
        leg.color = ADRoutePreview.COLORS[math.min(i, #ADRoutePreview.COLORS)]
        table.insert(texts, string.format(g_i18n:getText("AD_preview_leg"), leg.name, string.format("%.1f km", leg.length / 1000), ADRoutePreview.formatDuration(leg.time)))
    end
    if #legs == 0 then
        ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, g_i18n:getText("AD_preview_noTarget"), 4000)
        return
    end
    self.legs = legs
    self.vehicle = vehicle
    ADRoutePreview.installMapHooks()
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, table.concat(texts, "  |  "), 8000)
end

-- in the world, near the vehicle
function ADRoutePreview:draw(vehicle)
    if self.legs == nil or vehicle ~= self.vehicle or vehicle.components == nil then
        return
    end
    local vx, _, vz = getWorldTranslation(vehicle.components[1].node)
    local range = ADRoutePreview.WORLD_RANGE
    local h = ADRoutePreview.LINE_HEIGHT
    for _, leg in ipairs(self.legs) do
        local r, g, b = unpack(leg.color)
        local points = leg.points
        for i = 2, #points do
            local a, c = points[i - 1], points[i]
            if math.abs(a.x - vx) < range and math.abs(a.z - vz) < range then
                ADDrawingManager:addLineTask(a.x, a.y + h, a.z, c.x, c.y + h, c.z, 1.5, r, g, b)
                if i % 8 == 0 then
                    ADDrawingManager:addArrowTask(a.x, a.y + h, a.z, c.x, c.y + h, c.z, 1.5, ADDrawingManager.arrows.position.middle, r, g, b)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- maps: the minimap of the HUD and the big map of the menu
-------------------------------------------------------------------------------

-- screen position of a world position on a map, nil if it can not be shown
function ADRoutePreview.mapPosition(map, x, z, isHudMap)
    local u = (x + map.worldCenterOffsetX) / map.worldSizeX
    local v = (z + map.worldCenterOffsetZ) / map.worldSizeZ
    if isHudMap then
        u = u * map.mapExtensionScaleFactor + map.mapExtensionOffsetX
        v = v * map.mapExtensionScaleFactor + map.mapExtensionOffsetZ
        local sx, sy, _, visible = map.layout:getMapObjectPosition(u, v, 0, 0, 0, false)
        if visible == false then
            return nil
        end
        return sx, sy
    end
    local sx, sy = map.fullScreenLayout:getMapObjectPosition(u * 0.5 + 0.25, v * 0.5 + 0.25, 0, 0, 0, true)
    return sx, sy
end

function ADRoutePreview.drawMapLine(overlayId, x1, y1, x2, y2, thickness, r, g, b)
    local dxPixels = (x2 - x1) * g_screenWidth
    local dyPixels = (y2 - y1) * g_screenHeight
    local lengthPixels = math.sqrt(dxPixels * dxPixels + dyPixels * dyPixels)
    if lengthPixels < 0.5 then
        return
    end
    setOverlayColor(overlayId, r, g, b, 0.9)
    setOverlayRotation(overlayId, math.atan2(dyPixels, dxPixels), 0, thickness / 2)
    renderOverlay(overlayId, x1, y1, lengthPixels / g_screenWidth, thickness)
end

function ADRoutePreview:drawOnMap(map, isHudMap)
    if self.legs == nil or map == nil then
        return
    end
    if self.lineOverlay == nil then
        self.lineOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    local thickness = ADRoutePreview.MAP_LINE_PIXELS / g_screenHeight
    for _, leg in ipairs(self.legs) do
        local r, g, b = unpack(leg.color)
        local lastX, lastY
        for _, point in ipairs(leg.mapPoints) do
            local sx, sy = ADRoutePreview.mapPosition(map, point.x, point.z, isHudMap)
            if sx ~= nil and lastX ~= nil then
                ADRoutePreview.drawMapLine(self.lineOverlay, lastX, lastY, sx, sy, thickness, r, g, b)
            end
            lastX, lastY = sx, sy
        end
    end
end

-- a failing map draw must not break the map: draw once more only if it worked
function ADRoutePreview.safeDrawOnMap(map, isHudMap)
    if ADRoutePreview.mapDrawFailed then
        return
    end
    local ok, err = pcall(ADRoutePreview.drawOnMap, ADRoutePreview, map, isHudMap)
    if not ok then
        ADRoutePreview.mapDrawFailed = true
        Logging.warning("[AD] route preview can not draw on the map: %s", tostring(err))
    end
end

function ADRoutePreview.installMapHooks()
    local mission = g_currentMission
    if not ADRoutePreview.hudMapHooked and mission ~= nil and mission.hud ~= nil and mission.hud.ingameMap ~= nil and mission.hud.ingameMap.drawFields ~= nil then
        ADRoutePreview.hudMapHooked = true
        mission.hud.ingameMap.drawFields = Utils.appendedFunction(mission.hud.ingameMap.drawFields, function(map)
            ADRoutePreview.safeDrawOnMap(map, true)
        end)
    end
end

-- big map of the menu: drawn after the map, before the hotspots
if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.onDrawPostIngameMap ~= nil then
    InGameMenuMapFrame.onDrawPostIngameMap = Utils.appendedFunction(InGameMenuMapFrame.onDrawPostIngameMap, function(frame, element, ingameMap)
        if ADRoutePreview.legs ~= nil then
            ADRoutePreview.safeDrawOnMap(frame.ingameMapBase or ingameMap, false)
        end
    end)
    if InGameMenuMapFrame.onLoadMapFinished ~= nil then
        -- the map element keeps the draw function it got at loading, give it the extended one
        InGameMenuMapFrame.onLoadMapFinished = Utils.appendedFunction(InGameMenuMapFrame.onLoadMapFinished, function(frame)
            if frame.ingameMap ~= nil then
                frame.ingameMap.onDrawPostIngameMapCallback = InGameMenuMapFrame.onDrawPostIngameMap
            end
        end)
    end
end
