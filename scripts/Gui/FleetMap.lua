-- Fleet on the map: the AutoDrive vehicles of the player's farm on the big map (ESC > Map), a coloured
-- square with the driver name: green driving, yellow switched on but standing, red stopped with a warning
-- or error, grey idle. User setting showFleetOnMap.

ADFleetMap = {}

ADFleetMap.DRIVING = 1
ADFleetMap.WAITING = 2
ADFleetMap.PROBLEM = 3
ADFleetMap.IDLE = 4
ADFleetMap.COLORS = {
    [ADFleetMap.DRIVING] = {0.2, 0.85, 0.2},
    [ADFleetMap.WAITING] = {1, 0.8, 0.1},
    [ADFleetMap.PROBLEM] = {1, 0.15, 0.15},
    [ADFleetMap.IDLE] = {0.6, 0.6, 0.6}
}
-- faster than this (km/h) counts as driving
ADFleetMap.MOVING_SPEED = 1
ADFleetMap.SQUARE_PIXELS = 12
ADFleetMap.BORDER_PIXELS = 2
ADFleetMap.TEXT_SIZE = 0.011

function ADFleetMap.getState(vehicle)
    local stateModule = vehicle.ad.stateModule
    if stateModule:isActive() then
        local speed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
        if speed > ADFleetMap.MOVING_SPEED then
            return ADFleetMap.DRIVING
        end
        return ADFleetMap.WAITING
    end
    if ADFleetGui.getLastProblem(vehicle) ~= nil then
        return ADFleetMap.PROBLEM
    end
    return ADFleetMap.IDLE
end

-- the vehicles to show: AutoDrive vehicles of the local player's farm
function ADFleetMap.getVehicles()
    local farmId
    if g_localPlayer ~= nil and g_localPlayer.getFarmId ~= nil then
        farmId = g_localPlayer:getFarmId()
    end
    local vehicles = {}
    for _, vehicle in pairs(AutoDrive.getAllVehicles() or {}) do
        if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil and vehicle.components ~= nil
            and (farmId == nil or vehicle.getOwnerFarmId == nil or vehicle:getOwnerFarmId() == farmId) then
            table.insert(vehicles, vehicle)
        end
    end
    return vehicles
end

function ADFleetMap.drawSquare(overlayId, x, y, pixels, r, g, b, a)
    local width, height = pixels / g_screenWidth, pixels / g_screenHeight
    setOverlayColor(overlayId, r, g, b, a)
    setOverlayRotation(overlayId, 0, 0, 0)
    renderOverlay(overlayId, x - width / 2, y - height / 2, width, height)
end

function ADFleetMap:draw(map)
    if map == nil or not AutoDrive.getSetting("showFleetOnMap") then
        return
    end
    if self.overlay == nil then
        self.overlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    local square = ADFleetMap.SQUARE_PIXELS
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    for _, vehicle in ipairs(ADFleetMap.getVehicles()) do
        local x, _, z = getWorldTranslation(vehicle.components[1].node)
        local sx, sy = ADRoutePreview.mapPosition(map, x, z, false)
        if sx ~= nil then
            local r, g, b = unpack(ADFleetMap.COLORS[ADFleetMap.getState(vehicle)])
            ADFleetMap.drawSquare(self.overlay, sx, sy, square + 2 * ADFleetMap.BORDER_PIXELS, 0, 0, 0, 0.9)
            ADFleetMap.drawSquare(self.overlay, sx, sy, square, r, g, b, 1)
            local textY = sy + (square / 2 + ADFleetMap.BORDER_PIXELS + 2) / g_screenHeight
            setTextColor(0, 0, 0, 0.8)
            renderText(sx + 1 / g_screenWidth, textY - 1 / g_screenHeight, ADFleetMap.TEXT_SIZE, vehicle.ad.stateModule:getName() or "")
            setTextColor(1, 1, 1, 1)
            renderText(sx, textY, ADFleetMap.TEXT_SIZE, vehicle.ad.stateModule:getName() or "")
        end
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- a failing map draw must not break the map: stop after the first error
function ADFleetMap.safeDraw(map)
    if ADFleetMap.drawFailed then
        return
    end
    local ok, err = pcall(ADFleetMap.draw, ADFleetMap, map)
    if not ok then
        ADFleetMap.drawFailed = true
        Logging.warning("[AD] fleet on the map can not draw: %s", tostring(err))
    end
end

-- big map of the menu (the map element gets the extended draw function again in RoutePreview.lua)
if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.onDrawPostIngameMap ~= nil then
    InGameMenuMapFrame.onDrawPostIngameMap = Utils.appendedFunction(InGameMenuMapFrame.onDrawPostIngameMap, function(frame, element, ingameMap)
        ADFleetMap.safeDraw(frame.ingameMapBase or ingameMap)
    end)
end
