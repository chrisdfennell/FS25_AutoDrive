-- Waypoint panel: while a waypoint is selected in the editor (left click), a panel next to the AutoDrive HUD
-- shows it and changes it: target (create / rename / remove, drive or send a vehicle there), side road, the
-- connections to its neighbours (switch or remove), the waypoint actions and the speed zone, and for the road
-- it is on (up to the next junctions): speed zone, side road, direction and the tidy-up tools.
-- Every click is one undo step and goes through the same events as the editor keys. User setting waypointPanel.

ADWaypointPanel = {}

ADWaypointPanel.WIDTH_PIXELS = 290
ADWaypointPanel.ROW_PIXELS = 22
ADWaypointPanel.GAP_PIXELS = 3
ADWaypointPanel.LABEL_SHARE = 0.42
ADWaypointPanel.MAX_CONNECTIONS = 6
ADWaypointPanel.MAX_ROAD = 2000
-- the neighbours are found again after this time (ms); a reverse connection into the waypoint needs a scan
ADWaypointPanel.REFRESH_TIME = 500

-- connection between the waypoint and a neighbour, seen from the waypoint (as ADGraphManager:setConnectionBetween)
ADWaypointPanel.OUT = 1
ADWaypointPanel.IN = 2
ADWaypointPanel.DUAL = 3
ADWaypointPanel.REVERSE = 4
ADWaypointPanel.REVERSE_IN = 5
ADWaypointPanel.NEXT_DIRECTION = {[1] = 2, [2] = 3, [3] = 4, [4] = 1, [5] = 1}

ADWaypointPanel.COLOR_BACKGROUND = {0, 0, 0, 0.82}
ADWaypointPanel.COLOR_BUTTON = {0.18, 0.18, 0.18, 0.95}
ADWaypointPanel.COLOR_HOVER = {0.35, 0.35, 0.35, 0.95}
ADWaypointPanel.COLOR_ACTIVE = {1, 0.6, 0.1, 0.95}

ADWaypointPanel.buttons = {}
ADWaypointPanel.cache = {}

local function contains(list, value)
    if list ~= nil then
        for _, v in ipairs(list) do
            if v == value then
                return true
            end
        end
    end
    return false
end

-- the waypoint the panel is for, or nil when the panel is hidden
function ADWaypointPanel.getWayPoint(vehicle)
    if vehicle == nil or vehicle.ad == nil or not AutoDrive.isEditorModeEnabled() or not AutoDrive.getSetting("showHUD")
        or not AutoDrive.getSetting("waypointPanel") then
        return nil
    end
    local ad = vehicle.ad
    -- not while a new route is drawn from it (Ctrl + click), or a waypoint is dragged
    if ad.selectedNodeId == nil or ad.newcreated ~= nil or ad.nodeToMoveId ~= nil or ad.keyDragNodeId ~= nil then
        return nil
    end
    return ADGraphManager:getWayPointById(ad.selectedNodeId)
end

function ADWaypointPanel.getDirection(wp, neighbour)
    local pOut, pIn = contains(wp.out, neighbour.id), contains(wp.incoming, neighbour.id)
    local nOut, nIn = contains(neighbour.out, wp.id), contains(neighbour.incoming, wp.id)
    if pOut and nOut and pIn and nIn then
        return ADWaypointPanel.DUAL
    elseif pOut and nIn then
        return ADWaypointPanel.OUT
    elseif pOut then
        return ADWaypointPanel.REVERSE
    elseif nOut and pIn then
        return ADWaypointPanel.IN
    elseif nOut then
        return ADWaypointPanel.REVERSE_IN
    end
    return nil
end

-- neighbours with the connection to each: out, incoming, and reverse connections into the waypoint
-- (those are only in the neighbour's out list, so all waypoints are looked at)
function ADWaypointPanel.findConnections(wp)
    local ids, seen = {}, {}
    local function add(id)
        if id ~= wp.id and not seen[id] and ADGraphManager:getWayPointById(id) ~= nil then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    for _, id in ipairs(wp.out or {}) do
        add(id)
    end
    for _, id in ipairs(wp.incoming or {}) do
        add(id)
    end
    for id, other in pairs(ADGraphManager:getWayPoints()) do
        if not seen[id] and contains(other.out, wp.id) then
            add(id)
        end
    end
    local connections = {}
    for _, id in ipairs(ids) do
        local neighbour = ADGraphManager:getWayPointById(id)
        local direction = ADWaypointPanel.getDirection(wp, neighbour)
        if direction ~= nil then
            table.insert(connections, {id = id, direction = direction})
        end
    end
    table.sort(connections, function(a, b) return a.id < b.id end)
    return connections
end

local function linkedIds(wp)
    local ids, seen = {}, {}
    for _, list in ipairs({wp.out or {}, wp.incoming or {}}) do
        for _, id in ipairs(list) do
            if id ~= wp.id and not seen[id] and ADGraphManager:getWayPointById(id) ~= nil then
                seen[id] = true
                table.insert(ids, id)
            end
        end
    end
    return ids
end

-- one side of the road: the waypoints from firstId on, and the junction it ends at (nil at a dead end or a loop)
local function walkRoad(startId, firstId, visited)
    local ids = {}
    local previousId, id = startId, firstId
    while id ~= nil and #ids < ADWaypointPanel.MAX_ROAD do
        if visited[id] then
            return ids, nil
        end
        local links = linkedIds(ADGraphManager:getWayPointById(id))
        if #links > 2 then
            return ids, id
        end
        visited[id] = true
        table.insert(ids, id)
        local nextId = nil
        for _, linkId in ipairs(links) do
            if linkId ~= previousId then
                nextId = linkId
            end
        end
        previousId, id = id, nextId
    end
    return ids, nil
end

-- the road the waypoint is on: along both sides until a junction (a waypoint linked to more than two others)
-- or a dead end. road: its waypoints (junctions are not part of it; a junction on its own is its own road);
-- chain: the same in driving order along the road, with the junctions at both ends (for directions and tidying)
function ADWaypointPanel.getRoadChain(startId)
    local start = ADGraphManager:getWayPointById(startId)
    if start == nil then
        return {}, {}
    end
    local startLinks = linkedIds(start)
    if #startLinks > 2 then
        return {startId}, {startId}
    end
    local visited = {[startId] = true}
    local sides = {}
    for i, firstId in ipairs(startLinks) do
        local ids, junction = walkRoad(startId, firstId, visited)
        sides[i] = {ids = ids, junction = junction}
    end
    local road, chain = {}, {}
    if sides[1] ~= nil then
        if sides[1].junction ~= nil then
            table.insert(chain, sides[1].junction)
        end
        for j = #sides[1].ids, 1, -1 do
            table.insert(chain, sides[1].ids[j])
            table.insert(road, sides[1].ids[j])
        end
    end
    table.insert(chain, startId)
    table.insert(road, startId)
    if sides[2] ~= nil then
        for _, id in ipairs(sides[2].ids) do
            table.insert(chain, id)
            table.insert(road, id)
        end
        if sides[2].junction ~= nil then
            table.insert(chain, sides[2].junction)
        end
    end
    -- driving order: the way most one-way connections along it go
    local forward, backward = 0, 0
    for i = 1, #chain - 1 do
        local direction = ADWaypointPanel.getDirection(ADGraphManager:getWayPointById(chain[i]), ADGraphManager:getWayPointById(chain[i + 1]))
        if direction == ADWaypointPanel.OUT then
            forward = forward + 1
        elseif direction == ADWaypointPanel.IN then
            backward = backward + 1
        end
    end
    if backward > forward then
        local reversed = {}
        for i = #chain, 1, -1 do
            table.insert(reversed, chain[i])
        end
        chain = reversed
    end
    return road, chain
end

function ADWaypointPanel.getRoad(startId)
    return (ADWaypointPanel.getRoadChain(startId))
end

function ADWaypointPanel.getConnections(wp)
    local cache = ADWaypointPanel.cache
    local now = g_time or 0
    if cache.id ~= wp.id or cache.time == nil or now - cache.time > ADWaypointPanel.REFRESH_TIME or now < cache.time then
        cache.id = wp.id
        cache.time = now
        cache.connections = ADWaypointPanel.findConnections(wp)
        cache.road, cache.chain = ADWaypointPanel.getRoadChain(wp.id)
    end
    return cache.connections, cache.road, cache.chain
end

function ADWaypointPanel.invalidate()
    ADWaypointPanel.cache = {}
end

-- edits -------------------------------------------------------------------------------------------------------

function ADWaypointPanel.setFlags(wp, flags)
    if flags ~= wp.flags then
        ADGraphManager:moveWayPoint(wp.id, wp.x, wp.y, wp.z, flags)
    end
end

function ADWaypointPanel.setZoneOnIds(ids, zone)
    local moves = {}
    for _, id in ipairs(ids) do
        local wp = ADGraphManager:getWayPointById(id)
        if wp ~= nil and ADWaypointActions.getZone(wp.flags) ~= zone then
            table.insert(moves, {id = id, x = wp.x, y = wp.y, z = wp.z, flags = ADWaypointActions.setZone(wp.flags, zone)})
        end
    end
    if #moves > 0 then
        ADGraphManager:moveWayPoints(moves)
    end
end

function ADWaypointPanel.setSideRoadOnIds(ids, on)
    local moves = {}
    for _, id in ipairs(ids) do
        local wp = ADGraphManager:getWayPointById(id)
        if wp ~= nil and ADGraphManager:getIsPointSubPrio(id) ~= on then
            local flags = on and (wp.flags + AutoDrive.FLAG_SUBPRIO) or (wp.flags - AutoDrive.FLAG_SUBPRIO)
            table.insert(moves, {id = id, x = wp.x, y = wp.y, z = wp.z, flags = flags})
        end
    end
    if #moves > 0 then
        ADGraphManager:moveWayPoints(moves)
    end
end

-- the connection between each two waypoints of the chain, seen from the first (getDirection)
function ADWaypointPanel.getChainDirections(chain)
    local directions = {}
    for i = 1, #chain - 1 do
        local a, b = ADGraphManager:getWayPointById(chain[i]), ADGraphManager:getWayPointById(chain[i + 1])
        directions[i] = (a ~= nil and b ~= nil) and ADWaypointPanel.getDirection(a, b) or false
    end
    return directions
end

-- "oneWay" (along the chain), "twoWay", or nil when the road is mixed
function ADWaypointPanel.getRoadDirection(chain)
    local directions = ADWaypointPanel.getChainDirections(chain)
    if #directions == 0 then
        return nil
    end
    local first = directions[1]
    for _, direction in ipairs(directions) do
        if direction ~= first then
            return nil
        end
    end
    if first == ADWaypointPanel.OUT then
        return "oneWay"
    elseif first == ADWaypointPanel.DUAL then
        return "twoWay"
    end
    return nil
end

-- the whole road one-way (in its driving order), two-way, or turned round; one undo step
function ADWaypointPanel.setRoadDirection(chain, mode)
    local links = {}
    for i, direction in ipairs(ADWaypointPanel.getChainDirections(chain)) do
        local a, b = chain[i], chain[i + 1]
        if mode == "oneWay" and direction ~= ADWaypointPanel.OUT then
            table.insert(links, {a, b, ADWaypointPanel.OUT})
        elseif mode == "twoWay" and direction ~= ADWaypointPanel.DUAL then
            table.insert(links, {a, b, ADWaypointPanel.DUAL})
        elseif mode == "flip" then
            if direction == ADWaypointPanel.OUT then
                table.insert(links, {a, b, ADWaypointPanel.IN})
            elseif direction == ADWaypointPanel.IN then
                table.insert(links, {a, b, ADWaypointPanel.OUT})
            elseif direction == ADWaypointPanel.REVERSE then
                table.insert(links, {b, a, ADWaypointPanel.REVERSE})
            elseif direction == ADWaypointPanel.REVERSE_IN then
                table.insert(links, {a, b, ADWaypointPanel.REVERSE})
            end
        end
    end
    AutoDriveRoadEvent.sendEvent(links)
end

function ADWaypointPanel.removeConnection(wp, connection)
    AutoDriveRoadEvent.sendEvent({{wp.id, connection.id, AutoDriveRoadEvent.REMOVE}})
end

function ADWaypointPanel.tidyRoad(chain, tool)
    local moves = ADTidyTools.getMoves(tool, chain, ADTidyTools.groundHeight)
    if moves == nil or #moves == 0 then
        ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, g_i18n:getText("AD_tidy_nothing"), 3000)
        return
    end
    ADGraphManager:moveWayPoints(moves)
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, string.format(g_i18n:getText("AD_tidy_done"), #moves, #chain), 4000)
end

-- the index of the target on the waypoint in the list of targets (what the targets are known by)
function ADWaypointPanel.getMarkerIndex(wayPointId)
    for index, marker in pairs(ADGraphManager:getMapMarkers()) do
        if marker.id == wayPointId and not marker.isADDebug then
            return index
        end
    end
    return nil
end

function ADWaypointPanel.driveHere(vehicle, markerIndex)
    if vehicle ~= nil and vehicle.ad ~= nil and markerIndex ~= nil then
        AutoDriveSendToEvent.sendEvent(vehicle, markerIndex)
    end
end

function ADWaypointPanel.cycleConnection(wp, connection)
    local neighbour = ADGraphManager:getWayPointById(connection.id)
    if neighbour ~= nil then
        ADGraphManager:setConnectionBetween(wp, neighbour, ADWaypointPanel.NEXT_DIRECTION[connection.direction])
    end
end

function ADWaypointPanel.createTarget(wp)
    AutoDrive.createMapMarkerWayPointId = wp.id
    AutoDrive.onOpenEnterTargetName()
end

function ADWaypointPanel.renameTarget(markerIndex)
    AutoDrive.editMapMarkerId = markerIndex
    AutoDrive.onOpenEnterTargetName()
end

-- rows -------------------------------------------------------------------------------------------------------

local function text(key, ...)
    if select("#", ...) > 0 then
        return string.format(g_i18n:getText(key), ...)
    end
    return g_i18n:getText(key)
end

local function choice(label, active, onClick, width)
    return {text = label, active = active, onClick = onClick, width = width}
end

-- a row: label on the left, buttons on the right; title rows are bold
function ADWaypointPanel.getRows(vehicle, wp)
    local A = ADWaypointActions
    local rows = {}
    local flags = wp.flags or 0

    table.insert(rows, {label = text("AD_wpPanel_title", tostring(wp.id)), bold = true, buttons = {
        choice("X", false, function() vehicle.ad.selectedNodeId = nil end)}})

    local distance = 0
    if vehicle.components ~= nil and vehicle.components[1] ~= nil then
        local x, _, z = getWorldTranslation(vehicle.components[1].node)
        distance = MathUtil.vector2Length(wp.x - x, wp.z - z)
    end
    table.insert(rows, {label = text("AD_wpPanel_info", string.format("%.1f", wp.y), string.format("%d", math.floor(distance + 0.5))), wide = true})

    local markerIndex = ADWaypointPanel.getMarkerIndex(wp.id)
    local marker = markerIndex ~= nil and ADGraphManager:getMapMarkerById(markerIndex) or nil
    if marker ~= nil then
        table.insert(rows, {label = text("AD_wpPanel_target", marker.name), buttons = {
            choice(text("AD_wpPanel_rename"), false, function() ADWaypointPanel.renameTarget(markerIndex) end),
            choice(text("AD_wpPanel_remove"), false, function() ADGraphManager:removeMapMarkerByWayPoint(wp.id) end)}})
        table.insert(rows, {label = text("AD_wpPanel_vehicles"), buttons = {
            choice(text("AD_wpPanel_driveHere"), false, function() ADWaypointPanel.driveHere(vehicle, markerIndex) end),
            choice(text("AD_wpPanel_sendVehicle"), false, function() AutoDrive.onOpenSendTo(nil, markerIndex) end)}})
    else
        table.insert(rows, {label = text("AD_wpPanel_noTarget"), buttons = {
            choice(text("AD_wpPanel_create"), false, function() ADWaypointPanel.createTarget(wp) end)}})
    end

    local subPrio = ADGraphManager:getIsPointSubPrio(wp.id)
    table.insert(rows, {label = text("AD_wpPanel_sideRoad"), buttons = {
        choice(text("gui_ad_no"), not subPrio, function() if subPrio then ADGraphManager:toggleWayPointAsSubPrio(wp.id) end end),
        choice(text("gui_ad_yes"), subPrio, function() if not subPrio then ADGraphManager:toggleWayPointAsSubPrio(wp.id) end end)}})

    local connections, road, chain = ADWaypointPanel.getConnections(wp)
    local numIn, numOut = 0, 0
    for _, connection in ipairs(connections) do
        local d = connection.direction
        if d == ADWaypointPanel.IN or d == ADWaypointPanel.DUAL or d == ADWaypointPanel.REVERSE_IN then
            numIn = numIn + 1
        end
        if d == ADWaypointPanel.OUT or d == ADWaypointPanel.DUAL or d == ADWaypointPanel.REVERSE then
            numOut = numOut + 1
        end
    end
    table.insert(rows, {label = text("AD_wpPanel_connections", numIn, numOut), bold = true, wide = true})
    for i, connection in ipairs(connections) do
        if i > ADWaypointPanel.MAX_CONNECTIONS then
            table.insert(rows, {label = text("AD_wpPanel_more", #connections - ADWaypointPanel.MAX_CONNECTIONS), wide = true})
            break
        end
        table.insert(rows, {label = text("AD_wpPanel_connection", tostring(connection.id)), highlight = connection.id, buttons = {
            choice(text("AD_wpPanel_dir_" .. connection.direction) .. "  >", false, function() ADWaypointPanel.cycleConnection(wp, connection) end, 4),
            choice("X", false, function() ADWaypointPanel.removeConnection(wp, connection) end, 1)}})
    end

    table.insert(rows, {label = text("AD_wpPanel_actions"), bold = true, wide = true})
    local waitSeconds = A.getWaitSeconds(flags)
    table.insert(rows, {label = text("AD_wpPanel_wait"), buttons = {
        choice((waitSeconds > 0 and (waitSeconds .. " s") or text("AD_wpPanel_off")) .. "  >", waitSeconds > 0, function() ADWaypointPanel.setFlags(wp, A.nextWait(flags)) end)}})
    local horn = A.hasHorn(flags)
    table.insert(rows, {label = text("AD_wpPanel_horn"), buttons = {
        choice(text("gui_ad_no"), not horn, function() if horn then ADWaypointPanel.setFlags(wp, A.toggleHorn(flags)) end end),
        choice(text("gui_ad_yes"), horn, function() if not horn then ADWaypointPanel.setFlags(wp, A.toggleHorn(flags)) end end)}})
    local lights = A.getLights(flags)
    local function setLights(value)
        return function()
            local f = flags
            for _ = 1, 3 do
                if A.getLights(f) == value then
                    break
                end
                f = A.nextLights(f)
            end
            ADWaypointPanel.setFlags(wp, f)
        end
    end
    table.insert(rows, {label = text("AD_wpPanel_lights"), buttons = {
        choice("-", lights == A.LIGHTS_UNCHANGED, setLights(A.LIGHTS_UNCHANGED)),
        choice(text("AD_wpPanel_on"), lights == A.LIGHTS_ON, setLights(A.LIGHTS_ON)),
        choice(text("AD_wpPanel_off"), lights == A.LIGHTS_OFF, setLights(A.LIGHTS_OFF))}})
    local unlock = A.hasUnlock(flags)
    table.insert(rows, {label = text("AD_wpPanel_unlock"), buttons = {
        choice(text("gui_ad_no"), not unlock, function() if unlock then ADWaypointPanel.setFlags(wp, A.toggleUnlock(flags)) end end),
        choice(text("gui_ad_yes"), unlock, function() if not unlock then ADWaypointPanel.setFlags(wp, A.toggleUnlock(flags)) end end)}})

    local zone = A.getZone(flags)
    local function zoneButtons(ids, current)
        local buttons = {choice("-", current == 0, function() ADWaypointPanel.setZoneOnIds(ids, 0) end)}
        for z = 1, 3 do
            local speed = A.formatSpeed(A.ZONE_SPEEDS[z]):match("^%d+") or tostring(A.ZONE_SPEEDS[z])
            table.insert(buttons, choice(speed, current == z, function() ADWaypointPanel.setZoneOnIds(ids, z) end))
        end
        return buttons
    end
    table.insert(rows, {label = text("AD_wpPanel_zone"), buttons = zoneButtons({wp.id}, zone)})

    -- the road up to the junctions: a button is lit when the whole road is like that
    table.insert(rows, {label = text("AD_wpPanel_road", #road), bold = true, wide = true})
    local roadZone, roadSide, roadNormal = zone, true, true
    for _, id in ipairs(road) do
        local other = ADGraphManager:getWayPointById(id)
        if other == nil or A.getZone(other.flags) ~= zone then
            roadZone = -1
        end
        if ADGraphManager:getIsPointSubPrio(id) then
            roadNormal = false
        else
            roadSide = false
        end
    end
    table.insert(rows, {label = text("AD_wpPanel_zone"), section = "road", buttons = zoneButtons(road, roadZone)})
    table.insert(rows, {label = text("AD_wpPanel_sideRoad"), section = "road", buttons = {
        choice(text("gui_ad_no"), roadNormal, function() ADWaypointPanel.setSideRoadOnIds(road, false) end),
        choice(text("gui_ad_yes"), roadSide, function() ADWaypointPanel.setSideRoadOnIds(road, true) end)}})
    if #chain >= 2 then
        local roadDirection = ADWaypointPanel.getRoadDirection(chain)
        table.insert(rows, {label = text("AD_wpPanel_direction"), section = "road", buttons = {
            choice(text("AD_wpPanel_oneWay"), roadDirection == "oneWay", function() ADWaypointPanel.setRoadDirection(chain, "oneWay") end),
            choice(text("AD_wpPanel_twoWay"), roadDirection == "twoWay", function() ADWaypointPanel.setRoadDirection(chain, "twoWay") end),
            choice(text("AD_wpPanel_flip"), false, function() ADWaypointPanel.setRoadDirection(chain, "flip") end)}})
    end
    if #chain >= 3 then
        table.insert(rows, {label = text("AD_wpPanel_tidy"), section = "road", buttons = {
            choice(text("AD_wpPanel_even"), false, function() ADWaypointPanel.tidyRoad(chain, ADTidyTools.EVEN) end),
            choice(text("AD_wpPanel_straight"), false, function() ADWaypointPanel.tidyRoad(chain, ADTidyTools.STRAIGHTEN) end),
            choice(text("AD_wpPanel_smooth"), false, function() ADWaypointPanel.tidyRoad(chain, ADTidyTools.SMOOTH) end)}})
    end
    return rows
end

-- layout and drawing -----------------------------------------------------------------------------------------

function ADWaypointPanel.getUiScale()
    local uiScale = g_gameSettings:getValue("uiScale")
    if AutoDrive.getSetting("guiScale") ~= 0 then
        uiScale = AutoDrive.getSetting("guiScale")
    end
    return uiScale
end

-- next to the HUD: right of it, or left when there is no room; the tops line up
function ADWaypointPanel.layout(hud, numRows, uiScale)
    local width = ADWaypointPanel.WIDTH_PIXELS * uiScale / g_screenWidth
    local rowHeight = ADWaypointPanel.ROW_PIXELS * uiScale / g_screenHeight
    local gapX = ADWaypointPanel.GAP_PIXELS * uiScale / g_screenWidth
    local gapY = ADWaypointPanel.GAP_PIXELS * uiScale / g_screenHeight
    local height = numRows * rowHeight + 2 * gapY
    local x = hud.posX + hud.width + gapX
    if x + width > 1 then
        x = hud.posX - gapX - width
    end
    local top = (hud.rowHeader or hud.posY) + (hud.headerHeight or 0)
    local y = math.max(0, math.min(top, 1) - height)
    if y + height > 1 then
        y = math.max(0, 1 - height)
    end
    return {x = x, y = y, width = width, height = height, rowHeight = rowHeight, gapX = gapX, gapY = gapY}
end

local function fitText(size, value, width)
    if getTextWidth(size, value) <= width then
        return value
    end
    while value:len() > 1 and getTextWidth(size, value .. "...") > width do
        value = value:sub(1, -2)
    end
    return value .. "..."
end

local function inside(rect, x, y)
    return x ~= nil and y ~= nil and x >= rect.x and x <= rect.x + rect.width and y >= rect.y and y <= rect.y + rect.height
end

function ADWaypointPanel:draw(vehicle, hud)
    self.buttons = {}
    self.rect = nil
    local wp = ADWaypointPanel.getWayPoint(vehicle)
    if wp == nil or hud == nil or hud.posX == nil then
        return
    end
    local uiScale = ADWaypointPanel.getUiScale()
    local rows = ADWaypointPanel.getRows(vehicle, wp)
    local l = ADWaypointPanel.layout(hud, #rows, uiScale)
    self.rect = l
    local fontSize = AutoDrive.FONT_SCALE * uiScale
    local mouseX, mouseY = g_lastMousePosX, g_lastMousePosY

    drawFilledRect(l.x, l.y, l.width, l.height, unpack(ADWaypointPanel.COLOR_BACKGROUND))
    local innerX, innerWidth = l.x + l.gapX, l.width - 2 * l.gapX
    local labelWidth = innerWidth * ADWaypointPanel.LABEL_SHARE
    setTextAlignment(RenderText.ALIGN_LEFT)
    self.hoveredConnection = nil
    for i, row in ipairs(rows) do
        local rowY = l.y + l.height - l.gapY - i * l.rowHeight
        local textY = rowY + (l.rowHeight - fontSize) / 2 + fontSize * 0.15
        setTextBold(row.bold == true)
        setTextColor(1, 1, 1, 1)
        local width = (row.wide or row.buttons == nil) and innerWidth or labelWidth - l.gapX
        renderText(innerX, textY, fontSize, fitText(fontSize, row.label, width))
        if row.buttons ~= nil and #row.buttons > 0 then
            local areaX = innerX + labelWidth
            local areaWidth = innerWidth - labelWidth
            -- the close button is small and on the right
            if #row.buttons == 1 and row.buttons[1].text == "X" then
                areaWidth = l.rowHeight * g_screenHeight / g_screenWidth
                areaX = innerX + innerWidth - areaWidth
            end
            local weights = 0
            for _, button in ipairs(row.buttons) do
                weights = weights + (button.width or 1)
            end
            local unit = (areaWidth - (#row.buttons - 1) * l.gapX) / weights
            local buttonX = areaX
            for _, button in ipairs(row.buttons) do
                local buttonWidth = unit * (button.width or 1)
                local rect = {x = buttonX, y = rowY + l.gapY / 2, width = buttonWidth, height = l.rowHeight - l.gapY}
                buttonX = buttonX + buttonWidth + l.gapX
                local hovered = inside(rect, mouseX, mouseY)
                local color = ADWaypointPanel.COLOR_BUTTON
                if button.active then
                    color = ADWaypointPanel.COLOR_ACTIVE
                elseif hovered then
                    color = ADWaypointPanel.COLOR_HOVER
                end
                drawFilledRect(rect.x, rect.y, rect.width, rect.height, unpack(color))
                if hovered and button.active then
                    drawFilledRect(rect.x, rect.y, rect.width, rect.height, 1, 1, 1, 0.2)
                end
                if hovered and row.highlight ~= nil then
                    self.hoveredConnection = row.highlight
                end
                setTextAlignment(RenderText.ALIGN_CENTER)
                setTextBold(false)
                if button.active then
                    setTextColor(0, 0, 0, 1)
                else
                    setTextColor(1, 1, 1, 1)
                end
                renderText(rect.x + rect.width / 2, textY, fontSize, fitText(fontSize, button.text, rect.width - l.gapX))
                setTextAlignment(RenderText.ALIGN_LEFT)
                rect.onClick = button.onClick
                rect.text, rect.row, rect.active, rect.section = button.text, row.label, button.active, row.section
                table.insert(self.buttons, rect)
            end
        end
    end
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)

    -- the neighbour under the mouse: a line from the waypoint to it
    if self.hoveredConnection ~= nil then
        local other = ADGraphManager:getWayPointById(self.hoveredConnection)
        if other ~= nil then
            ADDrawingManager:addLineTask(wp.x, wp.y + 1, wp.z, other.x, other.y + 1, other.z, 3, 1, 0.6, 0.1)
        end
    end
end

function ADWaypointPanel.isMouseOver(x, y)
    local rect = ADWaypointPanel.rect
    return rect ~= nil and inside(rect, x, y)
end

-- every mouse event over the panel is used (nothing reaches the world behind it); a left click runs a button
function ADWaypointPanel:mouseEvent(vehicle, posX, posY, isDown, isUp, button)
    if self.rect == nil or ADWaypointPanel.getWayPoint(vehicle) == nil or not inside(self.rect, posX, posY) then
        return false
    end
    if button == 1 and isUp then
        for _, rect in ipairs(self.buttons) do
            if inside(rect, posX, posY) and rect.onClick ~= nil then
                rect.onClick()
                ADWaypointPanel.invalidate()
                AutoDrive.playSample(AutoDrive.mouseClickSample, 0.45)
                break
            end
        end
    end
    return true
end

function ADWaypointPanel.safeDraw(vehicle, hud)
    if ADWaypointPanel.failed then
        return
    end
    local ok, err = pcall(ADWaypointPanel.draw, ADWaypointPanel, vehicle, hud)
    if not ok then
        ADWaypointPanel.failed = true
        ADWaypointPanel.rect = nil
        Logging.error("[AD] waypoint panel switched off after an error: %s", tostring(err))
    end
end
