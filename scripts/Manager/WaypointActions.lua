-- Waypoint actions: a waypoint can make the vehicles driving over it wait, sound the horn or switch
-- the lights on or off. The actions are bits 10..15 of the waypoint flags, so they are saved, synced,
-- exported and undone like the flags already are. AutoDrive itself only tests the low flag bits.
--   bits 10..12  wait time index (WAIT_TIMES)
--   bit  13      horn
--   bits 14..15  lights: 0 unchanged, 1 on, 2 off
--   bit  16      unlock load: open the tension belts there, close them again when driving on
--   bits 17..18  speed zone: 0 none, 1 15 km/h, 2 30 km/h, 3 50 km/h (ADWaypointActions.ZONE_SPEEDS)

ADWaypointActions = {}

ADWaypointActions.WAIT_SHIFT = 10
ADWaypointActions.HORN_SHIFT = 13
ADWaypointActions.LIGHTS_SHIFT = 14
ADWaypointActions.UNLOCK_SHIFT = 16
ADWaypointActions.ZONE_SHIFT = 17
ADWaypointActions.ACTION_MASK_START = 2 ^ 10 -- all bits from here up to bit 18 are action bits
ADWaypointActions.ACTION_BITS_END = 2 ^ 19

-- speed zones: km/h per zone value
ADWaypointActions.ZONE_SPEEDS = {[1] = 15, [2] = 30, [3] = 50}
ADWaypointActions.ZONE_COLORS = {[1] = {1, 0.2, 0.2}, [2] = {1, 0.75, 0.1}, [3] = {0.3, 0.6, 1}}
-- braking towards a zone (m/s^2) and how far ahead (m) zones are looked for
ADWaypointActions.ZONE_DECELERATION = 1.5
ADWaypointActions.ZONE_LOOKAHEAD = 200

ADWaypointActions.WAIT_TIMES = {[0] = 0, 5, 10, 20, 30, 60, 120, 300}
ADWaypointActions.LIGHTS_UNCHANGED = 0
ADWaypointActions.LIGHTS_ON = 1
ADWaypointActions.LIGHTS_OFF = 2

ADWaypointActions.HORN_DURATION = 800
-- lights mask switched on by a waypoint: the normal front lights
ADWaypointActions.LIGHTS_ON_MASK = 1

local function getField(flags, shift, size)
    return math.floor((flags or 0) / 2 ^ shift) % size
end

local function setField(flags, shift, size, value)
    flags = flags or 0
    local old = getField(flags, shift, size)
    return flags + (value - old) * 2 ^ shift
end

function ADWaypointActions.getWaitIndex(flags)
    return getField(flags, ADWaypointActions.WAIT_SHIFT, 8)
end

function ADWaypointActions.getWaitSeconds(flags)
    return ADWaypointActions.WAIT_TIMES[ADWaypointActions.getWaitIndex(flags)]
end

function ADWaypointActions.hasHorn(flags)
    return getField(flags, ADWaypointActions.HORN_SHIFT, 2) == 1
end

function ADWaypointActions.getLights(flags)
    return getField(flags, ADWaypointActions.LIGHTS_SHIFT, 4)
end

function ADWaypointActions.getZone(flags)
    return getField(flags, ADWaypointActions.ZONE_SHIFT, 4)
end

-- km/h of the waypoint's speed zone, nil without zone
function ADWaypointActions.getZoneSpeed(flags)
    return ADWaypointActions.ZONE_SPEEDS[ADWaypointActions.getZone(flags)]
end

function ADWaypointActions.setZone(flags, zone)
    return setField(flags, ADWaypointActions.ZONE_SHIFT, 4, zone)
end

-- the action bits without the speed zone
function ADWaypointActions.getOtherActionBits(flags)
    return ADWaypointActions.getActionBits(flags) - ADWaypointActions.getZone(flags) * 2 ^ ADWaypointActions.ZONE_SHIFT
end

function ADWaypointActions.formatSpeed(kmh)
    if g_i18n ~= nil and g_i18n.getSpeed ~= nil and g_i18n.getSpeedMeasuringUnit ~= nil then
        return string.format("%d %s", math.floor(g_i18n:getSpeed(kmh) + 0.5), g_i18n:getSpeedMeasuringUnit())
    end
    return string.format("%d km/h", kmh)
end

function ADWaypointActions.hasUnlock(flags)
    return getField(flags, ADWaypointActions.UNLOCK_SHIFT, 2) == 1
end

-- the action part of the flags (0 if the waypoint has no action)
function ADWaypointActions.getActionBits(flags)
    flags = flags or 0
    return flags - (flags % ADWaypointActions.ACTION_MASK_START) - (math.floor(flags / ADWaypointActions.ACTION_BITS_END) * ADWaypointActions.ACTION_BITS_END)
end

function ADWaypointActions.hasActions(flags)
    return ADWaypointActions.getActionBits(flags) ~= 0
end

-- new flags without action bits (e.g. a section set to side road) keep the actions of the old flags
function ADWaypointActions.keepActions(oldFlags, newFlags)
    if ADWaypointActions.hasActions(newFlags) then
        return newFlags
    end
    return newFlags + ADWaypointActions.getActionBits(oldFlags)
end

function ADWaypointActions.nextWait(flags)
    return setField(flags, ADWaypointActions.WAIT_SHIFT, 8, (ADWaypointActions.getWaitIndex(flags) + 1) % 8)
end

function ADWaypointActions.toggleHorn(flags)
    local value = 1
    if ADWaypointActions.hasHorn(flags) then
        value = 0
    end
    return setField(flags, ADWaypointActions.HORN_SHIFT, 2, value)
end

function ADWaypointActions.toggleUnlock(flags)
    local value = 1
    if ADWaypointActions.hasUnlock(flags) then
        value = 0
    end
    return setField(flags, ADWaypointActions.UNLOCK_SHIFT, 2, value)
end

function ADWaypointActions.nextLights(flags)
    return setField(flags, ADWaypointActions.LIGHTS_SHIFT, 4, (ADWaypointActions.getLights(flags) + 1) % 3)
end

-- short text, e.g. "wait 10 s, horn, lights on"; nil without actions
function ADWaypointActions.getText(flags)
    local parts = {}
    local wait = ADWaypointActions.getWaitSeconds(flags)
    if wait > 0 then
        table.insert(parts, string.format(g_i18n:getText("AD_action_wait"), wait))
    end
    if ADWaypointActions.hasHorn(flags) then
        table.insert(parts, g_i18n:getText("AD_action_horn"))
    end
    local lights = ADWaypointActions.getLights(flags)
    if lights == ADWaypointActions.LIGHTS_ON then
        table.insert(parts, g_i18n:getText("AD_action_lightsOn"))
    elseif lights == ADWaypointActions.LIGHTS_OFF then
        table.insert(parts, g_i18n:getText("AD_action_lightsOff"))
    end
    if ADWaypointActions.hasUnlock(flags) then
        table.insert(parts, g_i18n:getText("AD_action_unlock"))
    end
    local zoneSpeed = ADWaypointActions.getZoneSpeed(flags)
    if zoneSpeed ~= nil then
        table.insert(parts, string.format(g_i18n:getText("AD_zone_text"), ADWaypointActions.formatSpeed(zoneSpeed)))
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

-------------------------------------------------------------------------------
-- editor: keys change the action of the waypoint under the mouse (or the selected one)
-------------------------------------------------------------------------------

function ADWaypointActions.getEditedWayPoint(vehicle)
    if not AutoDrive.isEditorModeEnabled() or vehicle == nil or vehicle.ad == nil then
        return nil
    end
    local id = vehicle.ad.hoveredNodeId or vehicle.ad.selectedNodeId
    if id == nil then
        return nil
    end
    return ADGraphManager:getWayPointById(id)
end

-- change: one of ADWaypointActions.nextWait / toggleHorn / nextLights
function ADWaypointActions.edit(vehicle, change)
    local wp = ADWaypointActions.getEditedWayPoint(vehicle)
    if wp == nil then
        if AutoDrive.isEditorModeEnabled() then
            ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, g_i18n:getText("AD_action_howTo"), 4000)
        end
        return
    end
    local flags = change(wp.flags)
    -- a move to the same position with the new flags: one undo step, synced like any edit
    ADGraphManager:moveWayPoint(wp.id, wp.x, wp.y, wp.z, flags)
    local text = ADWaypointActions.getText(flags) or g_i18n:getText("AD_action_none")
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, string.format(g_i18n:getText("AD_action_set"), text), 3000)
end

-- labels above waypoints with actions, while the editor is shown
function ADWaypointActions.drawEditor(vehicle)
    if vehicle == nil or vehicle.ad == nil or not (AutoDrive.isEditorModeEnabled() or AutoDrive.isEditorShowEnabled()) then
        return
    end
    local nearby = AutoDrive.getWayPointsDistance ~= nil and AutoDrive.getWayPointsDistance(vehicle) or nil
    if nearby == nil then
        return
    end
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 0.6, 0.1, 1)
    for _, entry in pairs(nearby) do
        local wp = entry.wayPoint or entry
        if wp ~= nil and wp.flags ~= nil and ADWaypointActions.hasActions(wp.flags) then
            local zone = ADWaypointActions.getZone(wp.flags)
            local hasOther = ADWaypointActions.getOtherActionBits(wp.flags) ~= 0
            if zone > 0 then
                local r, g, b = unpack(ADWaypointActions.ZONE_COLORS[zone])
                ADDrawingManager:addSphereTask(wp.x, wp.y + 0.6, wp.z, 0.8, r, g, b, 0)
            end
            if hasOther then
                ADDrawingManager:addSphereTask(wp.x, wp.y + 1.5, wp.z, 1.5, 1, 0.6, 0.1, 0)
            end
            -- a label where other actions are, and where a speed zone starts (not on every waypoint of a zone)
            if hasOther or (zone > 0 and ADWaypointActions.isZoneStart(wp)) then
                local sx, sy, sz = project(wp.x, wp.y + 2.5, wp.z)
                if sz ~= nil and sz > 0 and sz < 1 and sx > 0 and sx < 1 and sy > 0 and sy < 1 then
                    renderText(sx, sy, 0.012, ADWaypointActions.getText(wp.flags))
                end
            end
        end
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-------------------------------------------------------------------------------
-- driving (server): actions when a vehicle reaches a waypoint
-------------------------------------------------------------------------------

function ADWaypointActions.onReached(vehicle, wp)
    if wp == nil or wp.flags == nil or not ADWaypointActions.hasActions(wp.flags) or vehicle.ad == nil then
        return
    end
    local wait = ADWaypointActions.getWaitSeconds(wp.flags)
    if wait > 0 then
        vehicle.ad.actionWaitUntil = g_time + wait * 1000
    end
    if ADWaypointActions.hasHorn(wp.flags) and vehicle.playHonk ~= nil then
        vehicle:playHonk(true)
        vehicle.ad.actionHornUntil = g_time + ADWaypointActions.HORN_DURATION
    end
    if ADWaypointActions.hasUnlock(wp.flags) then
        ADWaypointActions.setBeltsActive(vehicle, false)
        vehicle.ad.loadUnlockedWayPointId = wp.id
        vehicle.ad.loadUnlockedPath = vehicle.ad.drivePathModule ~= nil and vehicle.ad.drivePathModule:getWayPoints() or nil
    end
    local lights = ADWaypointActions.getLights(wp.flags)
    if lights ~= ADWaypointActions.LIGHTS_UNCHANGED and vehicle.setLightsTypesMask ~= nil then
        if lights == ADWaypointActions.LIGHTS_ON then
            vehicle:setLightsTypesMask(ADWaypointActions.LIGHTS_ON_MASK)
        else
            vehicle:setLightsTypesMask(0)
        end
    end
end

-- tension belts of the vehicle and everything attached (like the lock load key)
function ADWaypointActions.setBeltsActive(vehicle, active)
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        if unit.setAllTensionBeltsActive ~= nil then
            unit:setAllTensionBeltsActive(active, false)
        end
    end
end

-- after an unlock: lock the load again as soon as the vehicle gets a new route or drives on to another waypoint
function ADWaypointActions.relockWhenLeaving(vehicle)
    local ad = vehicle.ad
    if ad.loadUnlockedWayPointId == nil or ad.drivePathModule == nil then
        return
    end
    local wayPoints = ad.drivePathModule:getWayPoints()
    if wayPoints == nil or #wayPoints == 0 then
        -- standing at the target, e.g. while unloading
        return
    end
    local current = ad.drivePathModule:getCurrentWayPoint()
    if wayPoints ~= ad.loadUnlockedPath or current == nil or current.id ~= ad.loadUnlockedWayPointId then
        ADWaypointActions.setBeltsActive(vehicle, true)
        ad.loadUnlockedWayPointId = nil
        ad.loadUnlockedPath = nil
    end
end

-- called by the drive path module every frame; true while the vehicle waits at a waypoint
function ADWaypointActions.updateWaiting(vehicle, dt)
    local ad = vehicle.ad
    if ad.actionHornUntil ~= nil and g_time > ad.actionHornUntil then
        ad.actionHornUntil = nil
        if vehicle.playHonk ~= nil then
            vehicle:playHonk(false)
        end
    end
    if ad.actionWaitUntil ~= nil then
        if g_time <= ad.actionWaitUntil and ad.stateModule:isActive() then
            ad.specialDrivingModule:stopVehicle()
            ad.specialDrivingModule:update(dt)
            return true
        end
        ad.actionWaitUntil = nil
    end
    ADWaypointActions.relockWhenLeaving(vehicle)
    return false
end

-------------------------------------------------------------------------------
-- speed zones
-------------------------------------------------------------------------------

-- does a zone start at this waypoint (a waypoint leading to it has another zone)?
function ADWaypointActions.isZoneStart(wp)
    local zone = ADWaypointActions.getZone(wp.flags)
    for _, id in ipairs(wp.incoming or {}) do
        local previous = ADGraphManager:getWayPointById(id)
        if previous ~= nil and ADWaypointActions.getZone(previous.flags) ~= zone then
            return true
        end
    end
    return wp.incoming == nil or #wp.incoming == 0
end

-- editor keys: set the zone (0 = none) on the route between the selected waypoint and the one under the
-- mouse, or on the one waypoint if only one is given; one undo step
function ADWaypointActions.setZoneOnRoute(vehicle, zone)
    if not AutoDrive.isEditorModeEnabled() or vehicle == nil or vehicle.ad == nil then
        return
    end
    local startId, endId = vehicle.ad.selectedNodeId, vehicle.ad.hoveredNodeId
    local chain
    if startId ~= nil and endId ~= nil and startId ~= endId then
        chain = ADTidyTools.findChain(startId, endId)
    elseif startId ~= nil or endId ~= nil then
        chain = {startId or endId}
    end
    if chain == nil then
        ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.WARN, g_i18n:getText("AD_zone_howTo"), 5000)
        return
    end
    local moves = {}
    for _, id in ipairs(chain) do
        local wp = ADGraphManager:getWayPointById(id)
        if wp ~= nil and ADWaypointActions.getZone(wp.flags) ~= zone then
            table.insert(moves, {id = id, x = wp.x, y = wp.y, z = wp.z, flags = ADWaypointActions.setZone(wp.flags, zone)})
        end
    end
    if #moves > 0 then
        ADGraphManager:moveWayPoints(moves)
    end
    local text
    if zone == 0 then
        text = string.format(g_i18n:getText("AD_zone_cleared"), #chain)
    else
        text = string.format(g_i18n:getText("AD_zone_set"), ADWaypointActions.formatSpeed(ADWaypointActions.ZONE_SPEEDS[zone]), #chain)
    end
    ADMessagesManager:addMessage(nil, ADMessagesManager.messageTypes.INFO, text, 4000)
end

-- driving (ADDrivePathModule:followWaypoints, every frame): the highest speed in km/h that still lets the
-- vehicle slow down to the zones ahead in time, and the zone speed while on a zone; math.huge without zones
function ADWaypointActions.getZoneSpeedLimit(drivePathModule)
    local wayPoints = drivePathModule.wayPoints
    local current = drivePathModule.currentWayPoint
    if wayPoints == nil or current == nil or wayPoints[current] == nil then
        return math.huge
    end
    local limit = math.huge
    -- on a zone: the waypoint behind and the one ahead
    for _, index in ipairs({current - 1, current}) do
        local wp = wayPoints[index]
        if wp ~= nil and wp.flags ~= nil then
            local speed = ADWaypointActions.getZoneSpeed(wp.flags)
            if speed ~= nil and speed < limit then
                limit = speed
            end
        end
    end
    -- zones ahead: v^2 = vz^2 + 2 a d
    local vehicle = drivePathModule.vehicle
    local x, _, z = getWorldTranslation(vehicle.components[1].node)
    local distance = MathUtil.vector2Length(wayPoints[current].x - x, wayPoints[current].z - z)
    local index = current
    while wayPoints[index] ~= nil and distance <= ADWaypointActions.ZONE_LOOKAHEAD do
        local wp = wayPoints[index]
        if wp.flags ~= nil then
            local speed = ADWaypointActions.getZoneSpeed(wp.flags)
            if speed ~= nil then
                local allowed = math.sqrt((speed / 3.6) ^ 2 + 2 * ADWaypointActions.ZONE_DECELERATION * distance) * 3.6
                if allowed < limit then
                    limit = allowed
                end
            end
        end
        local nextWp = wayPoints[index + 1]
        if nextWp ~= nil then
            distance = distance + MathUtil.vector2Length(nextWp.x - wp.x, nextWp.z - wp.z)
        end
        index = index + 1
    end
    return limit
end
