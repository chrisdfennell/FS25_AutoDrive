-- Best price unloading: when a loaded vehicle sets off to unload, it picks a target of the unload target's
-- folder by the current prices of the selling points next to the targets. Runs on the server.
--   ONE_STOP:     the target where the whole load (all products on board) brings the most
--   EACH_PRODUCT: the most valuable product first, to the target that pays the most for it; pickup and
--                 deliver then drives on to the next stop while something sellable is left
-- Targets without a selling point nearby are left out. A stop counts as done when the selling point takes
-- nothing more, also if something is left on board (else AutoDrive would wait there forever).

ADBestPrice = {}

ADBestPrice.OFF = 0
ADBestPrice.ONE_STOP = 1
ADBestPrice.EACH_PRODUCT = 2

-- a target belongs to a selling point when the point's unload area is this close (metres)
ADBestPrice.MAX_DISTANCE = 60
-- stops in a row for one load (each product), a safety limit
ADBestPrice.MAX_STOPS = 5
-- fill types of the vehicles' own tanks, never part of the load
ADBestPrice.OWN_TANKS = {DIESEL = true, DEF = true, AIR = true, ELECTRICCHARGE = true, METHANE = true}

function ADBestPrice.getMode(vehicle)
    local mode = AutoDrive.getSetting("bestPriceUnload", vehicle)
    if mode == nil or mode == false or mode == 0 then
        return ADBestPrice.OFF
    end
    if mode == true then
        return ADBestPrice.ONE_STOP
    end
    return mode
end

-- the load on board: fill type -> litres, without the vehicles' own tanks
function ADBestPrice.getLoad(vehicle)
    local load = {}
    local units = AutoDrive.getAllUnits(vehicle)
    for _, unit in ipairs(units or {}) do
        if unit.getFillUnits ~= nil then
            for index, _ in ipairs(unit:getFillUnits()) do
                local fillType = unit:getFillUnitFillType(index)
                local level = unit:getFillUnitFillLevel(index)
                if fillType ~= nil and fillType ~= FillType.UNKNOWN and level > 0 then
                    local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
                    if not ADBestPrice.OWN_TANKS[name] then
                        load[fillType] = (load[fillType] or 0) + level
                    end
                end
            end
        end
    end
    return load
end

-- the fill type with the most on board, or the fill type selected in the HUD
function ADBestPrice.getLoadedFillType(vehicle)
    local bestFillType, bestLevel = nil, 0
    for fillType, level in pairs(ADBestPrice.getLoad(vehicle)) do
        if level > bestLevel then
            bestFillType, bestLevel = fillType, level
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

-- the nearest selling point within maxDistance of the candidate, from stations
local function nearestStation(candidate, stations, maxDistance)
    local nearest, nearestDistance = nil, maxDistance
    for _, station in ipairs(stations) do
        local distance = MathUtil.vector2Length(candidate.x - station.x, candidate.z - station.z)
        if distance <= nearestDistance then
            nearest, nearestDistance = station, distance
        end
    end
    return nearest
end

-- candidates: {marker, x, z}; stationsByFillType: fill type -> stations (getStations)
-- prices[i][fillType] = {price, station} of candidate i, if a selling point nearby takes the fill type
function ADBestPrice.getPrices(candidates, stationsByFillType, maxDistance)
    local prices = {}
    for i, candidate in ipairs(candidates) do
        prices[i] = {}
        for fillType, stations in pairs(stationsByFillType) do
            local station = nearestStation(candidate, stations, maxDistance)
            if station ~= nil then
                prices[i][fillType] = {price = station.price, station = station}
            end
        end
    end
    return prices
end

-- one stop: the candidate where the whole load brings the most; returns index, value, a station name
function ADBestPrice.pickOneStop(candidates, prices, load)
    local bestIndex, bestValue, bestStation = nil, 0, nil
    for i, _ in ipairs(candidates) do
        -- the station named is the one taking the biggest part of the value
        local value, station, stationValue = 0, nil, -1
        for fillType, litres in pairs(load) do
            local entry = prices[i][fillType]
            if entry ~= nil then
                value = value + litres * entry.price
                if litres * entry.price > stationValue then
                    station, stationValue = entry.station, litres * entry.price
                end
            end
        end
        if value > bestValue then
            bestIndex, bestValue, bestStation = i, value, station
        end
    end
    return bestIndex, bestValue, bestStation
end

-- each product: the product worth the most at its best target first; returns index, fill type, station
function ADBestPrice.pickProduct(candidates, prices, load)
    local bestIndex, bestFillType, bestValue, bestStation = nil, nil, 0, nil
    for fillType, litres in pairs(load) do
        for i, _ in ipairs(candidates) do
            local entry = prices[i][fillType]
            if entry ~= nil and litres * entry.price > bestValue then
                bestIndex, bestFillType, bestValue, bestStation = i, fillType, litres * entry.price, entry.station
            end
        end
    end
    return bestIndex, bestFillType, bestStation
end

-- is anything of the load sold by a target of the folder?
function ADBestPrice.hasSellableLoad(vehicle, group)
    local load = ADBestPrice.getLoad(vehicle)
    if next(load) == nil then
        return false
    end
    local candidates = ADBestPrice.getCandidates(group)
    for fillType, _ in pairs(load) do
        local stations = ADBestPrice.getStations(fillType)
        for _, candidate in ipairs(candidates) do
            if nearestStation(candidate, stations, ADBestPrice.MAX_DISTANCE) ~= nil then
                return true
            end
        end
    end
    return false
end

-- targets of the folder with their positions
function ADBestPrice.getCandidates(group)
    local candidates = {}
    for _, marker in ipairs(ADGraphManager:getMapMarkersInGroup(group)) do
        local wp = ADGraphManager:getWayPointById(marker.id)
        if wp ~= nil and not marker.isADDebug then
            table.insert(candidates, {marker = marker, x = wp.x, z = wp.z})
        end
    end
    return candidates
end

-- the unload target the vehicle uses (second marker, or the first one for "unload at")
local function getCurrentTarget(vehicle, useFirstMarker)
    if useFirstMarker then
        return vehicle.ad.stateModule:getFirstMarker()
    end
    return vehicle.ad.stateModule:getSecondMarker()
end

-- sets the unload target to the best paying target of its folder; returns true if the setting is on and a
-- selling point was found. useFirstMarker: "unload at" mode, only one stop
function ADBestPrice.apply(vehicle, useFirstMarker)
    if vehicle == nil or vehicle.ad == nil then
        return false
    end
    vehicle.ad.bestPriceActive = false
    -- a new load starts counting its stops again, a next stop of the same load (wantsNextStop) does not
    if not vehicle.ad.bestPriceNextStop then
        vehicle.ad.bestPriceStops = 0
    end
    vehicle.ad.bestPriceNextStop = false
    local mode = ADBestPrice.getMode(vehicle)
    if mode == ADBestPrice.OFF or not AutoDrive.getSetting("useFolders") then
        return false
    end
    if useFirstMarker then
        mode = ADBestPrice.ONE_STOP
    end
    local stateModule = vehicle.ad.stateModule
    local current = getCurrentTarget(vehicle, useFirstMarker)
    if current == nil or current.group == nil or current.group == "All" then
        return false
    end
    local load = ADBestPrice.getLoad(vehicle)
    if next(load) == nil then
        local fillType = stateModule:getFillType()
        if fillType == nil or fillType == FillType.UNKNOWN then
            return false
        end
        load[fillType] = 1
    end

    local candidates = ADBestPrice.getCandidates(current.group)
    local stationsByFillType = {}
    for fillType, _ in pairs(load) do
        stationsByFillType[fillType] = ADBestPrice.getStations(fillType)
    end
    local prices = ADBestPrice.getPrices(candidates, stationsByFillType, ADBestPrice.MAX_DISTANCE)

    local index, station, productText
    if mode == ADBestPrice.EACH_PRODUCT then
        local fillType
        index, fillType, station = ADBestPrice.pickProduct(candidates, prices, load)
        if fillType ~= nil then
            productText = g_fillTypeManager:getFillTypeTitleByIndex(fillType)
        end
    else
        index, _, station = ADBestPrice.pickOneStop(candidates, prices, load)
    end
    if index == nil then
        return false
    end

    local best = candidates[index]
    vehicle.ad.bestPriceActive = true
    vehicle.ad.bestPriceFillBefore = AutoDrive.getAllFillLevels(AutoDrive.getAllUnits(vehicle) or {}) or 0
    if best.marker.markerIndex ~= current.markerIndex or productText ~= nil then
        if useFirstMarker then
            stateModule:setFirstMarker(best.marker.markerIndex)
        else
            stateModule:setSecondMarker(best.marker.markerIndex)
        end
        local where = string.format("%s (%s)", best.marker.name, station ~= nil and station.name or "")
        if productText ~= nil then
            where = where .. ": " .. productText
        end
        AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_bestPrice_switch; %s", 5000, stateModule:getName(), where)
    end
    return true
end

-- UnloadAtDestinationTask: the stop is done when the selling point takes nothing more, even with something
-- left on board (a product it does not buy)
function ADBestPrice.finishesUnloadEarly(vehicle)
    return vehicle ~= nil and vehicle.ad ~= nil and vehicle.ad.bestPriceActive == true and ADBestPrice.getMode(vehicle) ~= ADBestPrice.OFF
        and vehicle.ad.trailerModule ~= nil and vehicle.ad.trailerModule:getHasAL() ~= true
end

-- pickup and deliver after a stop: drive on to the next selling point? (each product, something sellable
-- left, the last stop sold something, not too many stops)
function ADBestPrice.wantsNextStop(vehicle, fillLevel)
    local ad = vehicle.ad
    local target = ad.stateModule:getSecondMarker()
    local wanted = ad.bestPriceActive == true and ADBestPrice.getMode(vehicle) == ADBestPrice.EACH_PRODUCT
        and (ad.bestPriceStops or 0) + 1 < ADBestPrice.MAX_STOPS
        and fillLevel < (ad.bestPriceFillBefore or 0) - 1
        and target ~= nil and target.group ~= nil and ADBestPrice.hasSellableLoad(vehicle, target.group)
    if wanted then
        ad.bestPriceStops = (ad.bestPriceStops or 0) + 1
        ad.bestPriceNextStop = true
    else
        ad.bestPriceStops = 0
        ad.bestPriceActive = false
    end
    return wanted
end
