-- Best price unloading: when a loaded vehicle sets off to unload, it picks the target of the
-- unload target's folder whose selling point pays the most for the load right now.
-- Runs on the server. Targets without a selling point nearby are left out.

ADBestPrice = {}

-- a target belongs to a selling point when the point's unload area is this close (metres)
ADBestPrice.MAX_DISTANCE = 60

-- the fill type with the most on board, or the fill type selected in the HUD
function ADBestPrice.getLoadedFillType(vehicle)
    local bestFillType, bestLevel = nil, 0
    local units = AutoDrive.getAllUnits(vehicle)
    for _, unit in ipairs(units or {}) do
        if unit.getFillUnits ~= nil then
            for index, _ in ipairs(unit:getFillUnits()) do
                local fillType = unit:getFillUnitFillType(index)
                local level = unit:getFillUnitFillLevel(index)
                if fillType ~= nil and fillType ~= FillType.UNKNOWN and level > bestLevel then
                    bestFillType, bestLevel = fillType, level
                end
            end
        end
    end
    if bestFillType == nil and vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil then
        bestFillType = vehicle.ad.stateModule:getFillType()
    end
    return bestFillType
end

-- position of the unload area of a selling point, like ADTriggerManager:getMarkerAtStation finds it
function ADBestPrice.getStationPosition(station)
    if station.getAITargetPositionAndDirection ~= nil then
        local x, z = station:getAITargetPositionAndDirection(FillType.UNKNOWN)
        if x ~= nil then
            return x, z
        end
    end
    local trigger = station.unloadTriggers ~= nil and station.unloadTriggers[1] or nil
    if trigger == nil then
        return nil
    end
    if trigger.supportsAIUnloading and trigger.getAITargetPositionAndDirection ~= nil then
        local x, z = trigger:getAITargetPositionAndDirection()
        if x ~= nil then
            return x, z
        end
    end
    local node = trigger.exactFillRootNode
    if node == nil and trigger.baleTrigger ~= nil then
        node = trigger.baleTrigger.triggerNode
    end
    if node ~= nil then
        local x, _, z = getWorldTranslation(node)
        return x, z
    end
    return nil
end

-- selling points that take the fill type: {name, x, z, price}
function ADBestPrice.getStations(fillType)
    local stations = {}
    if g_currentMission == nil or g_currentMission.storageSystem == nil then
        return stations
    end
    for _, station in pairs(g_currentMission.storageSystem:getUnloadingStations()) do
        if station:isa(SellingStation) and not station.hideFromPricesMenu and station.isSellingPoint and station.supportedFillTypes ~= nil and station.supportedFillTypes[fillType] then
            local x, z = ADBestPrice.getStationPosition(station)
            if x ~= nil then
                table.insert(stations, {name = station:getName(), x = x, z = z, price = station:getEffectiveFillTypePrice(fillType)})
            end
        end
    end
    return stations
end

-- candidates: {marker, x, z}; each gets the price of the nearest selling point within maxDistance.
-- returns the best paying candidate and its selling point, the first one on a tie
function ADBestPrice.pickBest(candidates, stations, maxDistance)
    local best, bestStation
    for _, candidate in ipairs(candidates) do
        local nearest, nearestDistance = nil, maxDistance
        for _, station in ipairs(stations) do
            local distance = MathUtil.vector2Length(candidate.x - station.x, candidate.z - station.z)
            if distance <= nearestDistance then
                nearest, nearestDistance = station, distance
            end
        end
        if nearest ~= nil and (bestStation == nil or nearest.price > bestStation.price) then
            best, bestStation = candidate, nearest
        end
    end
    return best, bestStation
end

-- sets the unload target (second marker, or the first one for "unload at") to the best paying
-- target of its folder; returns true if the setting is on and a selling point was found
function ADBestPrice.apply(vehicle, useFirstMarker)
    if vehicle == nil or vehicle.ad == nil or not AutoDrive.getSetting("bestPriceUnload", vehicle) or not AutoDrive.getSetting("useFolders") then
        return false
    end
    local stateModule = vehicle.ad.stateModule
    local current = useFirstMarker and stateModule:getFirstMarker() or stateModule:getSecondMarker()
    if current == nil or current.group == nil or current.group == "All" then
        return false
    end
    local fillType = ADBestPrice.getLoadedFillType(vehicle)
    if fillType == nil or fillType == FillType.UNKNOWN then
        return false
    end

    local candidates = {}
    for _, marker in ipairs(ADGraphManager:getMapMarkersInGroup(current.group)) do
        local wp = ADGraphManager:getWayPointById(marker.id)
        if wp ~= nil and not marker.isADDebug then
            table.insert(candidates, {marker = marker, x = wp.x, z = wp.z})
        end
    end
    local best, station = ADBestPrice.pickBest(candidates, ADBestPrice.getStations(fillType), ADBestPrice.MAX_DISTANCE)
    if best == nil then
        return false
    end
    if best.marker.markerIndex ~= current.markerIndex then
        if useFirstMarker then
            stateModule:setFirstMarker(best.marker.markerIndex)
        else
            stateModule:setSecondMarker(best.marker.markerIndex)
        end
        AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_bestPrice_switch; %s (%s)", 5000, stateModule:getName(), best.marker.name, station.name)
    end
    return true
end
