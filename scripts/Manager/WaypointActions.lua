-- Waypoint actions: a waypoint can make the vehicles driving over it wait, sound the horn or switch
-- the lights on or off. The actions are bits 10..15 of the waypoint flags, so they are saved, synced,
-- exported and undone like the flags already are. AutoDrive itself only tests the low flag bits.
--   bits 10..12  wait time index (WAIT_TIMES)
--   bit  13      horn
--   bits 14..15  lights: 0 unchanged, 1 on, 2 off
--   bit  16      unlock load: open the tension belts there, close them again when driving on

ADWaypointActions = {}

ADWaypointActions.WAIT_SHIFT = 10
ADWaypointActions.HORN_SHIFT = 13
ADWaypointActions.LIGHTS_SHIFT = 14
ADWaypointActions.UNLOCK_SHIFT = 16
ADWaypointActions.ACTION_MASK_START = 2 ^ 10 -- all bits from here up to bit 16 are action bits
ADWaypointActions.ACTION_BITS_END = 2 ^ 17

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
            ADDrawingManager:addSphereTask(wp.x, wp.y + 1.5, wp.z, 1.5, 1, 0.6, 0.1, 0)
            local sx, sy, sz = project(wp.x, wp.y + 2.5, wp.z)
            if sz ~= nil and sz > 0 and sz < 1 and sx > 0 and sx < 1 and sy > 0 and sy < 1 then
                renderText(sx, sy, 0.012, ADWaypointActions.getText(wp.flags))
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
