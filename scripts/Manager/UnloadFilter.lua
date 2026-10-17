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
    if vehicle == nil or vehicle.ad == nil then
        return false
    end
    local hasAL = vehicle.ad.trailerModule ~= nil and vehicle.ad.trailerModule:getHasAL() == true
    if hasAL then
        -- pallets: AutoDrive waits its AL wait time; with a limit the pallets left on board must not keep it there
        if not ADUnloadFilter.isFiltering(vehicle) then
            return false
        end
    elseif not (ADUnloadFilter.isFiltering(vehicle) or ADBestPrice.finishesUnloadEarly(vehicle)) then
        return false
    end
    local settleTime = hasAL and ADUnloadFilter.AL_SETTLE_TIME or ADUnloadFilter.SETTLE_TIME
    local ad = vehicle.ad
    -- the check runs every frame while nothing is tipped; a gap means something was tipped in between
    if ad.unloadIdleLast == nil or g_time - ad.unloadIdleLast > 500 then
        ad.unloadIdleSince = g_time
    end
    ad.unloadIdleLast = g_time
    return g_time - ad.unloadIdleSince >= settleTime
end

-------------------------------------------------------------------------------
-- pallets and bales of Universal Autoload trailers
-------------------------------------------------------------------------------

-- a pallet stops being waited for this long after the unload started (AutoDrive's AL wait time 0)
ADUnloadFilter.AL_SETTLE_TIME = 10000

-- fill type and litres of a loaded object (pallet: fill units, bale: fill type and level)
function ADUnloadFilter.getObjectProduct(object)
    if object == nil then
        return nil, 0
    end
    if object.getFillUnits ~= nil and object.getFillUnitFillType ~= nil then
        local bestType, bestLevel = nil, 0
        for index, _ in ipairs(object:getFillUnits()) do
            local fillType = object:getFillUnitFillType(index)
            local level = object:getFillUnitFillLevel(index) or 0
            if fillType ~= nil and fillType ~= FillType.UNKNOWN and (bestType == nil or level > bestLevel) then
                bestType, bestLevel = fillType, level
            end
        end
        return bestType, bestLevel
    end
    if object.getFillType ~= nil then
        return object:getFillType(), object.getFillLevel ~= nil and object:getFillLevel() or 0
    end
    return object.fillType, object.fillLevel or 0
end

-- what is loaded on a Universal Autoload trailer: fill type -> litres
function ADUnloadFilter.getALLoad(trailer)
    local load = {}
    local spec = trailer ~= nil and trailer.spec_universalAutoload or nil
    if spec == nil or spec.loadedObjects == nil then
        return load
    end
    for object, _ in pairs(spec.loadedObjects) do
        local fillType, litres = ADUnloadFilter.getObjectProduct(object)
        if fillType ~= nil and fillType ~= FillType.UNKNOWN then
            load[fillType] = (load[fillType] or 0) + litres
        end
    end
    return load
end

-- may the vehicle unload this product at its current target? (vehicle list, target list, best price stop)
function ADUnloadFilter.allowsProduct(vehicle, fillType)
    if not ADUnloadFilter.allowsFillType(vehicle, ADUnloadFilter.getUnloadMarker(vehicle), fillType) then
        return false
    end
    local products = vehicle.ad.bestPriceProducts
    if vehicle.ad.bestPriceActive == true and products ~= nil then
        return products[fillType] == true
    end
    return true
end

-- does the vehicle carry pallets of Universal Autoload, and is the unload position one that can choose
-- (left / behind / right set them down; off / center only open the belts, the selling point takes everything)
function ADUnloadFilter.getPalletState(vehicle)
    local hasPallets = false
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        if unit.spec_universalAutoload ~= nil then
            hasPallets = true
        end
    end
    local position = AutoDrive.getSetting("ALUnload", vehicle) or 0
    return hasPallets, position >= 2
end

-- Universal Autoload's code table. Each mod has its own global variables, so it is found through the trailer:
-- the trailer's specializations are the code tables of its specializations. The global name is the fallback.
function ADUnloadFilter.getUAL(trailer)
    for _, specialization in ipairs(trailer ~= nil and trailer.specializations or {}) do
        if type(specialization) == "table" and specialization.isValidForLoading ~= nil and specialization.buildObjectsToUnloadTable ~= nil then
            return specialization
        end
    end
    if UniversalAutoload ~= nil then
        return UniversalAutoload
    end
    local environment = _G ~= nil and _G.FS25_UniversalAutoload or nil
    if type(environment) == "table" and environment.UniversalAutoload ~= nil then
        return environment.UniversalAutoload
    end
    return nil
end

-- AutoDrive:unloadAL (Universal Autoload, unload position left / behind / right): like Universal Autoload's own
-- unloading, but only the pallets of allowed products are set down; the rest stays and is strapped again.
-- Returns true if it handled the unloading (a limit is set), false to let Universal Autoload unload everything.
function ADUnloadFilter.unloadALSelected(trailer, vehicle, unloadPosition)
    if vehicle == nil or vehicle.ad == nil or not ADUnloadFilter.isFiltering(vehicle) then
        return false
    end
    local ual = ADUnloadFilter.getUAL(trailer)
    local spec = trailer.spec_universalAutoload
    if ual == nil or spec == nil or spec.loadedObjects == nil or ual.buildObjectsToUnloadTable == nil or ual.unloadObject == nil then
        -- an unknown Universal Autoload version: better unload nothing than everything
        Logging.warning("[AD] Unload products: this Universal Autoload version is not supported, nothing is unloaded")
        return true
    end
    local ok, err = pcall(function()
        trailer:setAllTensionBeltsActive(false)
        if ual.addPalletsToPhysicsForVehicle ~= nil then
            ual.addPalletsToPhysicsForVehicle(trailer)
        end
        ual.buildObjectsToUnloadTable(trailer, unloadPosition)
        local unloaded = 0
        for object, unloadPlace in pairs(spec.objectsToUnload or {}) do
            local fillType = ADUnloadFilter.getObjectProduct(object)
            if fillType ~= nil and ADUnloadFilter.allowsProduct(vehicle, fillType) then
                if ual.unloadObject(trailer, object, unloadPlace) then
                    unloaded = unloaded + 1
                end
            elseif unloadPlace.node ~= nil then
                delete(unloadPlace.node)
            end
        end
        spec.objectsToUnload = {}
        -- what stays on the trailer is strapped again
        if next(spec.loadedObjects) ~= nil then
            trailer:setAllTensionBeltsActive(true)
        end
    end)
    if not ok then
        Logging.warning("[AD] Unload products: unloading with Universal Autoload failed: %s", tostring(err))
    end
    return true
end

-------------------------------------------------------------------------------
-- the products to choose from in the dialog
-------------------------------------------------------------------------------

-- vehicle: only what is on board (products chosen before stay in the list via getRows)
function ADUnloadFilter.getVehicleChoices(vehicle)
    local choices = {}
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        if unit.getFillUnits ~= nil then
            for index, _ in ipairs(unit:getFillUnits()) do
                local fillType = unit:getFillUnitFillType(index)
                local level = unit:getFillUnitFillLevel(index) or 0
                if fillType ~= nil and fillType ~= FillType.UNKNOWN and level > 0 then
                    choices[fillType] = (choices[fillType] or 0) + level
                end
            end
        end
    end
    -- pallets and bales on Universal Autoload trailers
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        for fillType, litres in pairs(ADUnloadFilter.getALLoad(unit)) do
            choices[fillType] = (choices[fillType] or 0) + litres
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
    for fillType, choice in pairs(choices) do
        local name = g_fillTypeManager:getFillTypeNameByIndex(fillType)
        if name ~= nil then
            listed[name] = true
            -- a choice is litres, or {litres, count} for pallets near the vehicle (load products)
            local litres, count = choice, nil
            if type(choice) == "table" then
                litres, count = choice.litres, choice.count
            end
            table.insert(rows, {fillType = fillType, name = name, title = g_fillTypeManager:getFillTypeTitleByIndex(fillType) or name, litres = litres, count = count, selected = set ~= nil and set[name] == true})
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
    schemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?).AutoDrive#loadFilter", "AutoDrive: pallets this vehicle loads")
end

function ADUnloadFilter.loadFromXML(vehicle, xmlFile, key)
    ADUnloadFilter.setVehicleFilter(vehicle, ADUnloadFilter.fromText(xmlFile:getValue(key .. "#unloadFilter")))
    ADUnloadFilter.setVehicleLoadFilter(vehicle, ADUnloadFilter.fromText(xmlFile:getValue(key .. "#loadFilter")))
end

function ADUnloadFilter.saveToXML(vehicle, xmlFile, key)
    if not ADUnloadFilter.isEmpty(vehicle.ad.unloadFilter) then
        xmlFile:setValue(key .. "#unloadFilter", ADUnloadFilter.toText(vehicle.ad.unloadFilter))
    end
    if not ADUnloadFilter.isEmpty(vehicle.ad.loadFilter) then
        xmlFile:setValue(key .. "#loadFilter", ADUnloadFilter.toText(vehicle.ad.loadFilter))
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

-------------------------------------------------------------------------------
-- load products: which pallets / bales Universal Autoload loads while AutoDrive drives the vehicle
-- (vehicle.ad.loadFilter, saved with the vehicle). Universal Autoload checks every object with
-- isValidForLoading; an extra check is added in front of it once.
-------------------------------------------------------------------------------

-- pallets near the vehicle or its load target count as choices
ADUnloadFilter.LOAD_CHOICE_DISTANCE = 60

function ADUnloadFilter.setVehicleLoadFilter(vehicle, set)
    if ADUnloadFilter.isEmpty(set) then
        vehicle.ad.loadFilter = nil
    else
        vehicle.ad.loadFilter = ADUnloadFilter.copy(set)
    end
end

function ADUnloadFilter.hasLoadFilter(vehicle)
    return vehicle ~= nil and vehicle.ad ~= nil and not ADUnloadFilter.isEmpty(vehicle.ad.loadFilter)
end

-- may Universal Autoload load this object onto the trailer?
function ADUnloadFilter.allowsLoad(trailer, object)
    local spec = trailer.spec_universalAutoload
    if spec ~= nil and spec.autoLoadingObjects ~= nil and spec.autoLoadingObjects[object] ~= nil then
        -- put on by a forklift or by hand
        return true
    end
    local vehicle = trailer.getRootVehicle ~= nil and trailer:getRootVehicle() or trailer
    if not ADUnloadFilter.hasLoadFilter(vehicle) or vehicle.ad.stateModule == nil or not vehicle.ad.stateModule:isActive() then
        return true
    end
    local fillType = ADUnloadFilter.getObjectProduct(object)
    local name = fillType ~= nil and g_fillTypeManager:getFillTypeNameByIndex(fillType) or nil
    return name ~= nil and vehicle.ad.loadFilter[name] == true
end

-- adds the check to Universal Autoload (once per code table)
function ADUnloadFilter.installLoadHook(trailer)
    local ual = ADUnloadFilter.getUAL(trailer)
    if ual == nil or ual.isValidForLoading == nil or ual.adLoadFilterInstalled then
        return ual ~= nil and ual.adLoadFilterInstalled == true
    end
    local original = ual.isValidForLoading
    ual.isValidForLoading = function(self, object, ...)
        if not original(self, object, ...) then
            return false
        end
        local ok, allowed = pcall(ADUnloadFilter.allowsLoad, self, object)
        return not ok or allowed
    end
    ual.adLoadFilterInstalled = true
    return true
end

-- AutoDrive:setALOn: the material Universal Autoload is set to before loading. With load products the
-- material is "all" and the check above chooses the objects (Universal Autoload takes one material only)
function ADUnloadFilter.getLoadMaterial(trailer, vehicle, fillType)
    if ADUnloadFilter.hasLoadFilter(vehicle) and ADUnloadFilter.installLoadHook(trailer) then
        return AutoDrive.UAL_FILLTYPE_ALL
    end
    return fillType
end

-- choices for the dialog: pallets and bales near the vehicle or its load target, and what is loaded
-- returns fillType -> {litres, count}
function ADUnloadFilter.getLoadChoices(vehicle)
    local places = {}
    if vehicle.components ~= nil then
        local x, _, z = getWorldTranslation(vehicle.components[1].node)
        table.insert(places, {x = x, z = z})
    end
    local target = vehicle.ad.stateModule:getFirstMarker()
    local wp = target ~= nil and ADGraphManager:getWayPointById(target.id) or nil
    if wp ~= nil then
        table.insert(places, {x = wp.x, z = wp.z})
    end
    local choices = {}
    local function add(object)
        local fillType, litres = ADUnloadFilter.getObjectProduct(object)
        if fillType ~= nil and fillType ~= FillType.UNKNOWN then
            local entry = choices[fillType] or {litres = 0, count = 0}
            entry.litres = entry.litres + (litres or 0)
            entry.count = entry.count + 1
            choices[fillType] = entry
        end
    end
    local function isNear(object)
        local node = object.rootNode or (object.components ~= nil and object.components[1] ~= nil and object.components[1].node) or object.nodeId
        if node == nil or node == 0 then
            return false
        end
        local x, _, z = getWorldTranslation(node)
        for _, place in ipairs(places) do
            if MathUtil.vector2Length(x - place.x, z - place.z) <= ADUnloadFilter.LOAD_CHOICE_DISTANCE then
                return true
            end
        end
        return false
    end
    -- pallets are vehicles of their own, bales are items
    for _, object in pairs(AutoDrive.getAllVehicles() or {}) do
        if (object.isPallet or object.spec_pallet ~= nil) and isNear(object) then
            add(object)
        end
    end
    local itemSystem = g_currentMission ~= nil and g_currentMission.itemSystem or nil
    for _, object in pairs(itemSystem ~= nil and itemSystem.itemsToSave or {}) do
        local item = object.item or object
        if type(item) == "table" and item.isa ~= nil and Bale ~= nil and item:isa(Bale) and isNear(item) then
            add(item)
        end
    end
    -- what the vehicle's trailers have in reach right now
    for _, unit in ipairs(AutoDrive.getAllUnits(vehicle) or {}) do
        local spec = unit.spec_universalAutoload
        for object, _ in pairs(spec ~= nil and spec.availableObjects or {}) do
            if not isNear(object) then
                add(object)
            end
        end
    end
    return choices
end
