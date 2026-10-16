-- Unload products: what a vehicle unloads at its unload target.
--   per vehicle: "unload only these products" (vehicle.ad.unloadFilter, saved with the vehicle)
--   per target:  "this target takes only these products" (targetFilters by target name, saved with the routes)
-- A trailer is only tipped if its product is allowed by both and by best price "each product". Everything
-- else stays on board. Empty lists mean: all products. The checks run on the server; clients keep copies for
-- the dialog (AutoDriveUnloadFilterEvent).

ADUnloadFilter = {}

-- a filtered stop is done when nothing has been tipped for this long (a trailer starts tipping only
-- a moment after the vehicle reached the trigger)
ADUnloadFilter.SETTLE_TIME = 3000
-- unloading points within this distance (m) of a target tell which products the target can take
ADUnloadFilter.STATION_DISTANCE = 60

ADUnloadFilter.targetFilters = {}

-- sets are {fillTypeName = true}; nil or empty means all products
function ADUnloadFilter.isEmpty(set)
    return set == nil or next(set) == nil
end

function ADUnloadFilter.allows(set, fillTypeName)
    return ADUnloadFilter.isEmpty(set) or set[fillTypeName] == true
end

function ADUnloadFilter.copy(set)
    local result = {}
    for name, value in pairs(set or {}) do
        if value then
            result[name] = true
        end
    end
    return result
end

function ADUnloadFilter.toList(set)
    local list = {}
    for name, value in pairs(set or {}) do
        if value then
            table.insert(list, name)
        end
    end
    table.sort(list)
    return list
end

function ADUnloadFilter.fromList(list)
    local set = {}
    for _, name in ipairs(list or {}) do
        if name ~= "" then
            set[name] = true
        end
    end
    return set
end

function ADUnloadFilter.toText(set)
    return table.concat(ADUnloadFilter.toList(set), ";")
end

function ADUnloadFilter.fromText(text)
    if text == nil or text == "" then
        return {}
    end
    return ADUnloadFilter.fromList(string.split(text, ";"))
end

function ADUnloadFilter.getTargetFilter(marker)
    if marker == nil or marker.name == nil then
        return nil
    end
    return ADUnloadFilter.targetFilters[marker.name]
end

function ADUnloadFilter.setTargetFilter(name, set)
    if ADUnloadFilter.isEmpty(set) then
        ADUnloadFilter.targetFilters[name] = nil
    else
        ADUnloadFilter.targetFilters[name] = ADUnloadFilter.copy(set)
    end
end

function ADUnloadFilter.setVehicleFilter(vehicle, set)
    if ADUnloadFilter.isEmpty(set) then
        vehicle.ad.unloadFilter = nil
    else
        vehicle.ad.unloadFilter = ADUnloadFilter.copy(set)
    end
end

-- a renamed target keeps its products
function ADUnloadFilter.renameTarget(oldName, newName)
    if oldName ~= nil and newName ~= nil and oldName ~= newName and ADUnloadFilter.targetFilters[oldName] ~= nil then
        ADUnloadFilter.targetFilters[newName] = ADUnloadFilter.targetFilters[oldName]
        ADUnloadFilter.targetFilters[oldName] = nil
    end
end

-- the target the vehicle unloads at (the destination it drives to)
function ADUnloadFilter.getUnloadMarker(vehicle)
    if vehicle.ad == nil or vehicle.ad.stateModule == nil then
        return nil
    end
    return vehicle.ad.stateModule:getCurrentDestination()
end

-- may a product be unloaded by the vehicle at the target? (vehicle and target lists, not best price)
function ADUnloadFilter.allowsFillType(vehicle, marker, fillType)
    local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
    if name == nil then
        return true
    end
    return ADUnloadFilter.allows(vehicle.ad.unloadFilter, name) and ADUnloadFilter.allows(ADUnloadFilter.getTargetFilter(marker), name)
end

-- is anything limiting what the vehicle unloads at its current target?
function ADUnloadFilter.isFiltering(vehicle)
    if vehicle == nil or vehicle.ad == nil then
        return false
    end
    return not ADUnloadFilter.isEmpty(vehicle.ad.unloadFilter)
        or not ADUnloadFilter.isEmpty(ADUnloadFilter.getTargetFilter(ADUnloadFilter.getUnloadMarker(vehicle)))
        or (vehicle.ad.bestPriceActive == true and vehicle.ad.bestPriceProducts ~= nil)
end

-- ADTrailerModule: may this trailer tip here?
function ADUnloadFilter.mayUnload(vehicle, trailer)
    if not ADBestPrice.mayUnload(vehicle, trailer) then
        return false
    end
    local marker = ADUnloadFilter.getUnloadMarker(vehicle)
    if ADUnloadFilter.isEmpty(vehicle.ad.unloadFilter) and ADUnloadFilter.isEmpty(ADUnloadFilter.getTargetFilter(marker)) then
        return true
    end
    if trailer.getCurrentDischargeNode == nil or trailer.getFillUnitFillType == nil then
        return true
    end
    local node = trailer:getCurrentDischargeNode()
    if node == nil or node.fillUnitIndex == nil then
        return true
    end
    return ADUnloadFilter.allowsFillType(vehicle, marker, trailer:getFillUnitFillType(node.fillUnitIndex))
end

-- UnloadAtDestinationTask: the stop is done when nothing has been tipped for SETTLE_TIME, even with something
-- left on board (a product that is not unloaded here). Without a limit or best price, AutoDrive waits as before.
function ADUnloadFilter.finishesUnloadEarly(vehicle)
    if vehicle == nil or vehicle.ad == nil or (vehicle.ad.trailerModule ~= nil and vehicle.ad.trailerModule:getHasAL() == true) then
        return false
    end
    if not (ADUnloadFilter.isFiltering(vehicle) or ADBestPrice.finishesUnloadEarly(vehicle)) then
        return false
    end
    local ad = vehicle.ad
    -- the check runs every frame while nothing is tipped; a gap means something was tipped in between
    if ad.unloadIdleLast == nil or g_time - ad.unloadIdleLast > 500 then
        ad.unloadIdleSince = g_time
    end
    ad.unloadIdleLast = g_time
    return g_time - ad.unloadIdleSince >= ADUnloadFilter.SETTLE_TIME
end

-------------------------------------------------------------------------------
-- the products to choose from in the dialog
-------------------------------------------------------------------------------

-- vehicle: what is on board and what its trailers can carry
function ADUnloadFilter.getVehicleChoices(vehicle)
    local choices = {}
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        if unit.getFillUnits ~= nil then
            for index, _ in ipairs(unit:getFillUnits()) do
                if unit.getFillUnitSupportedFillTypes ~= nil then
                    for fillType, supported in pairs(unit:getFillUnitSupportedFillTypes(index) or {}) do
                        if supported then
                            choices[fillType] = choices[fillType] or 0
                        end
                    end
                end
                local fillType = unit:getFillUnitFillType(index)
                if fillType ~= nil and fillType ~= FillType.UNKNOWN then
                    choices[fillType] = (choices[fillType] or 0) + unit:getFillUnitFillLevel(index)
                end
            end
        end
    end
    -- the vehicles' own tanks are no products
    for fillType, _ in pairs(choices) do
        if ADBestPrice.OWN_TANKS[g_fillTypeManager:getFillTypeNameByIndex(fillType)] then
            choices[fillType] = nil
        end
    end
    return choices
end

-- target: what the unloading points next to it take
function ADUnloadFilter.getTargetChoices(marker)
    local choices = {}
    local wp = marker ~= nil and ADGraphManager:getWayPointById(marker.id) or nil
    if wp == nil or g_currentMission == nil or g_currentMission.storageSystem == nil then
        return choices
    end
    for _, station in pairs(g_currentMission.storageSystem:getUnloadingStations()) do
        local x, z = ADBestPrice.getStationPosition(station)
        if x ~= nil and MathUtil.vector2Length(x - wp.x, z - wp.z) <= ADUnloadFilter.STATION_DISTANCE then
            for fillType, supported in pairs(station.supportedFillTypes or {}) do
                if supported then
                    choices[fillType] = 0
                end
            end
        end
    end
    return choices
end

-- rows for the dialog: {fillType, name, title, litres, selected}, the chosen ones first, then by title
function ADUnloadFilter.getRows(choices, set)
    local rows = {}
    local listed = {}
    for fillType, litres in pairs(choices) do
        local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
        if name ~= nil then
            listed[name] = true
            table.insert(rows, {fillType = fillType, name = name, title = g_fillTypeManager:getFillTypeTitleByIndex(fillType) or name, litres = litres, selected = set ~= nil and set[name] == true})
        end
    end
    -- chosen products that are not on board / not taken nearby any more
    for name, _ in pairs(set or {}) do
        if not listed[name] then
            local fillType = g_fillTypeManager:getFillTypeIndexByName(name)
            table.insert(rows, {fillType = fillType, name = name, title = fillType and g_fillTypeManager:getFillTypeTitleByIndex(fillType) or name, litres = 0, selected = true})
        end
    end
    table.sort(rows, function(a, b)
        if (a.litres > 0) ~= (b.litres > 0) then
            return a.litres > 0
        end
        return string.lower(a.title) < string.lower(b.title)
    end)
    return rows
end

-------------------------------------------------------------------------------
-- savegame: vehicle lists with the vehicle, target lists in the AutoDrive config of the savegame
-------------------------------------------------------------------------------

function ADUnloadFilter.registerSavegameKeys(schemaSavegame)
    schemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).AutoDrive#unloadFilter", "AutoDrive: products this vehicle unloads")
end

function ADUnloadFilter.loadFromXML(vehicle, xmlFile, key)
    ADUnloadFilter.setVehicleFilter(vehicle, ADUnloadFilter.fromText(xmlFile:getValue(key .. "#unloadFilter")))
end

function ADUnloadFilter.saveToXML(vehicle, xmlFile, key)
    if not ADUnloadFilter.isEmpty(vehicle.ad.unloadFilter) then
        xmlFile:setValue(key .. "#unloadFilter", ADUnloadFilter.toText(vehicle.ad.unloadFilter))
    end
end

-- AutoDrive_config.xml (old xml functions like the rest of XML.lua)
function ADUnloadFilter.loadTargetFilters(xmlFile)
    ADUnloadFilter.targetFilters = {}
    local i = 0
    while true do
        local key = string.format("AutoDrive.unloadFilters.t(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local name = getXMLString(xmlFile, key .. "#name")
        if name ~= nil and name ~= "" then
            ADUnloadFilter.setTargetFilter(name, ADUnloadFilter.fromText(getXMLString(xmlFile, key .. "#fillTypes")))
        end
        i = i + 1
    end
end

function ADUnloadFilter.saveTargetFilters(xmlFile)
    local names = {}
    for name, set in pairs(ADUnloadFilter.targetFilters) do
        if not ADUnloadFilter.isEmpty(set) and ADGraphManager:getMapMarkerByName(name) ~= nil then
            table.insert(names, name)
        end
    end
    table.sort(names)
    for i, name in ipairs(names) do
        local key = string.format("AutoDrive.unloadFilters.t(%d)", i - 1)
        setXMLString(xmlFile, key .. "#name", name)
        setXMLString(xmlFile, key .. "#fillTypes", ADUnloadFilter.toText(ADUnloadFilter.targetFilters[name]))
    end
end
