"""Unload products: per vehicle and per target lists, combined with best price, the finish guard,
savegame, network event, target rename and the rows of the dialog."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    FillType = {UNKNOWN = 0}
    NAMES = {[1] = "WHEAT", [2] = "BARLEY", [3] = "DIESEL", [4] = "CANOLA"}
    INDEX = {WHEAT = 1, BARLEY = 2, DIESEL = 3, CANOLA = 4}
    g_fillTypeManager = {getFillTypeNameByIndex = function(self, i) return NAMES[i] end,
        getFillTypeIndexByName = function(self, n) return INDEX[n] end,
        getFillTypeTitleByIndex = function(self, i) return NAMES[i]:sub(1, 1) .. NAMES[i]:sub(2):lower() end,
        getFillTypeByName = function(self, n) return {title = n} end}
    MESSAGES = {}
    ADMessagesManager = {messageTypes = {INFO = 1}}
    AutoDriveMessageEvent = {sendMessageOrNotification = function(v, t, text, d, ...) table.insert(MESSAGES, string.format(text, ...)) end}
    SETTINGS = {useFolders = true}
    AutoDrive.getSetting = function(name, vehicle)
        if vehicle ~= nil and vehicle.settings ~= nil and vehicle.settings[name] ~= nil then return vehicle.settings[name] end
        return SETTINGS[name]
    end
    string.split = string.split or function(str, sep)
        local r = {}
        for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do table.insert(r, part) end
        return r
    end
""")
for f in [("Manager", "BestPrice.lua"), ("Events", "UnloadFilterEvent.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))
s.execute("""
    UF = ADUnloadFilter
    function unit(units) return {getFillUnits = function(self) return units end,
        getFillUnitFillType = function(self, i) return units[i][1] end, getFillUnitFillLevel = function(self, i) return units[i][2] end,
        getFillUnitSupportedFillTypes = function(self, i) return units[i][3] or {} end} end
    function trailer(fillType) return {getCurrentDischargeNode = function() return {fillUnitIndex = 1} end, getFillUnitFillType = function() return fillType end} end
    ADGraphManager.wayPoints = {{id = 1, x = 0, y = 0, z = 0}, {id = 2, x = 500, y = 0, z = 0}}
    ADGraphManager.mapMarkers = {{name = "Mill", id = 1, markerIndex = 1, group = "Sell"}, {name = "Port", id = 2, markerIndex = 2, group = "Sell"}}
    ADGraphManager.getMapMarkersInGroup = function(self, g) local r = {} for _, m in ipairs(self.mapMarkers) do if m.group == g then table.insert(r, m) end end return r end
    function makeTruck(units, destination)
        local sm = {second = ADGraphManager.mapMarkers[2], destination = destination, name = "Truck"}
        function sm:getSecondMarker() return self.second end
        function sm:getFirstMarker() return self.second end
        function sm:setSecondMarker(i) self.second = ADGraphManager.mapMarkers[i] end
        function sm:getCurrentDestination() return self.destination end
        function sm:getName() return self.name end
        function sm:getFillType() return 1 end
        return {settings = {}, units = units, ad = {stateModule = sm, trailerModule = {getHasAL = function() return false end}}}
    end
    AutoDrive.getAllUnits = function(v) return v.units end
    AutoDrive.getAllFillLevels = function(units) local total = 0 for _, u in ipairs(units) do for i, _ in ipairs(u:getFillUnits()) do total = total + u:getFillUnitFillLevel(i) end end return total end
""")

# --- lists
assert s.eval("UF.toText(UF.fromText('WHEAT;BARLEY'))") == "BARLEY;WHEAT"
assert s.eval("UF.isEmpty(UF.fromText(''))") and s.eval("UF.allows(nil, 'X')") and s.eval("UF.allows({}, 'X')")
assert not s.eval("UF.allows({WHEAT = true}, 'BARLEY')")

# --- no lists: everything tips, nothing finishes early
s.execute("T = makeTruck({unit({{1, 1000}})}, ADGraphManager.mapMarkers[1])")
assert s.eval("UF.mayUnload(T, trailer(2))") and not s.eval("UF.isFiltering(T)")
assert not s.eval("UF.finishesUnloadEarly(T)")
# --- the vehicle unloads only wheat
s.execute("UF.setVehicleFilter(T, {WHEAT = true})")
assert s.eval("UF.mayUnload(T, trailer(1))") and not s.eval("UF.mayUnload(T, trailer(2))")
# --- the mill takes only barley: wheat and barley both blocked there (vehicle: wheat, target: barley)
s.execute("UF.setTargetFilter('Mill', {BARLEY = true})")
assert not s.eval("UF.mayUnload(T, trailer(1))") and not s.eval("UF.mayUnload(T, trailer(2))")
s.execute("UF.setVehicleFilter(T, {})")
assert s.eval("UF.mayUnload(T, trailer(2))") and not s.eval("UF.mayUnload(T, trailer(1))")
# another destination without a list: no limit from the target
s.execute("T.ad.stateModule.destination = ADGraphManager.mapMarkers[2]")
assert s.eval("UF.mayUnload(T, trailer(1))")

# --- finish guard: 3 s without tipping, restarted when tipping happened in between
s.execute("T.ad.stateModule.destination = ADGraphManager.mapMarkers[1]; g_time = 1000")
assert s.eval("UF.finishesUnloadEarly(T)") is False
s.execute("g_time = 2500"); assert s.eval("UF.finishesUnloadEarly(T)") is False  # gap > 500 ms: restarts
s.execute("for i = 1, 200 do g_time = g_time + 16; LAST = UF.finishesUnloadEarly(T) end")  # 3.2 s of frames
assert s.eval("LAST") is True

# --- best price respects both lists
s.execute("""
    -- port pays most for wheat and barley, the mill a bit less, and the mill only takes barley
    PRICES = {[1] = {{name = "MillS", x = 10, z = 0, price = 1.0}, {name = "PortS", x = 510, z = 0, price = 2.0}},
              [2] = {{name = "MillS", x = 10, z = 0, price = 1.9}, {name = "PortS", x = 510, z = 0, price = 1.5}}}
    ADBestPrice.getStations = function(ft) return PRICES[ft] or {} end
    BP = makeTruck({unit({{1, 10000}}), unit({{2, 10000}})})
    BP.settings.bestPriceUnload = 2
    BP.ad.stateModule.second = ADGraphManager.mapMarkers[1]
""")
# each product: wheat at the port (20000) first; barley best at the mill (19000)
assert s.eval("ADBestPrice.apply(BP, false)") and s.eval("BP.ad.stateModule.second.name") == "Port"
# the truck unloads only barley: wheat is not planned at all
s.execute("UF.setVehicleFilter(BP, {BARLEY = true}); ADBestPrice.apply(BP, false)")
assert s.eval("BP.ad.stateModule.second.name") == "Mill" and s.eval("BP.ad.bestPriceProducts[2]") and s.eval("BP.ad.bestPriceProducts[1]") is None
# the mill does not take barley any more: barley goes to the port
s.execute("UF.setTargetFilter('Mill', {CANOLA = true}); ADBestPrice.apply(BP, false)")
assert s.eval("BP.ad.stateModule.second.name") == "Port"
# nothing the truck unloads is taken anywhere: best price does not plan
s.execute("UF.setVehicleFilter(BP, {CANOLA = true})")
assert s.eval("ADBestPrice.apply(BP, false)") is False
s.execute("UF.setTargetFilter('Mill', {}); UF.setVehicleFilter(BP, {})")

# --- savegame: vehicle list with the vehicle, target lists in the config xml
s.execute("""
    VX = {values = {}, setValue = function(self, k, v) self.values[k] = v end, getValue = function(self, k) return self.values[k] end}
    V1 = makeTruck({}); UF.setVehicleFilter(V1, {WHEAT = true, CANOLA = true}); UF.saveToXML(V1, VX, "v")
    V2 = makeTruck({}); UF.loadFromXML(V2, VX, "v")
    V3 = makeTruck({}); UF.saveToXML(V3, VX, "w")
    XMLS = {}
    setXMLString = function(id, k, v) XMLS[k] = v end
    getXMLString = function(id, k) return XMLS[k] end
    hasXMLProperty = function(id, k) for key, _ in pairs(XMLS) do if key:sub(1, #k) == k then return true end end return false end
    ADGraphManager.getMapMarkerByName = function(self, n) for _, m in ipairs(self.mapMarkers) do if m.name == n then return m end end end
    UF.setTargetFilter("Mill", {BARLEY = true}); UF.setTargetFilter("Gone", {WHEAT = true})
    UF.saveTargetFilters(1)
    UF.targetFilters = {}
    UF.loadTargetFilters(1)
""")
assert s.eval("UF.toText(V2.ad.unloadFilter)") == "CANOLA;WHEAT"
assert s.eval("VX.values['w#unloadFilter']") is None
assert s.eval("UF.toText(UF.targetFilters.Mill)") == "BARLEY" and s.eval("UF.targetFilters.Gone") is None  # deleted target not saved

# --- rename keeps the list (also through the network function)
s.execute("""
    ADGraphManager.getMapMarkerById = function(self, i) return self.mapMarkers[i] end
    AutoDrive.notifyDestinationListeners = function() end
    AutoDrive.Hud = {}
    ADUndoManager:load()
    ADGraphManager:renameMapMarker("Old Mill", 1, false)
""")
assert s.eval("UF.toText(UF.targetFilters['Old Mill'])") == "BARLEY" and s.eval("UF.targetFilters.Mill") is None

# --- event: a client sets a list, the server applies it and sends it to all clients; request answers
s.execute("""
    STREAM = {}; POS = 0
    local function w(id, v) table.insert(STREAM, v) end
    local function r() POS = POS + 1; return STREAM[POS] end
    streamWriteUIntN = w; streamWriteString = w; streamWriteBool = w
    streamReadUIntN = r; streamReadString = r; streamReadBool = r
    NetworkUtil = {getObjectId = function(o) return o.netId end, getObject = function(id) return OBJECTS[id] end, writeNodeObjectId = w, readNodeObjectId = r}
    SV = makeTruck({}); SV.netId = 5; OBJECTS = {[5] = SV}
    BROADCAST = {}
    g_server.broadcastEvent = function(self, ev) table.insert(BROADCAST, ev) end
    local ev = AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_VEHICLE, SV, nil, {"BARLEY"})
    ev:writeStream(1, nil)
    AutoDriveUnloadFilterEvent.emptyNew():readStream(1, {})
    SENT = {}
    AutoDriveUnloadFilterEvent.new(AutoDriveUnloadFilterEvent.TYPE_REQUEST, SV):run({sendEvent = function(self, e) table.insert(SENT, e) end})
""")
assert s.eval("UF.toText(SV.ad.unloadFilter)") == "BARLEY"
assert s.eval("#BROADCAST") == 1 and s.eval("BROADCAST[1].products[1]") == "BARLEY"
assert s.eval("#SENT") == 3 and s.eval("SENT[1].eventType") == 1 and s.eval("SENT[2].eventType") == 5 and s.eval("SENT[3].eventType") == 4
assert s.eval("SENT[3].targets['Old Mill'][1]") == "BARLEY"

# --- dialog rows: on board first, then what the trailers can carry, chosen ones kept
s.execute("""
    RV = makeTruck({unit({{3, 300}}), unit({{1, 8000, {[1] = true, [2] = true, [4] = true}}})})
    ROWS = UF.getRows(UF.getVehicleChoices(RV), {CANOLA = true})
""")
rows = [(s.eval("ROWS[%d].name" % i), s.eval("ROWS[%d].litres" % i), s.eval("ROWS[%d].selected" % i)) for i in range(1, s.eval("#ROWS") + 1)]
assert rows == [("WHEAT", 8000, False), ("CANOLA", 0, True)], rows  # only what is on board (no diesel), plus what was chosen
# --- pallets on a Universal Autoload trailer
s.execute("""
    function pallet(fillType, litres) return {getFillUnits = function() return {{}} end, getFillUnitFillType = function() return fillType end,
        getFillUnitFillLevel = function() return litres end} end
    MILK, CHEESE1, CHEESE2 = pallet(1, 5000), pallet(2, 2500), pallet(2, 2500)
    BELTS = {}
    UALTRAILER = {spec_universalAutoload = {loadedObjects = {[MILK] = 1, [CHEESE1] = 1, [CHEESE2] = 1}},
        setAllTensionBeltsActive = function(self, active) table.insert(BELTS, active) end}
    DELETED = 0; delete = function() DELETED = DELETED + 1 end
    UNLOADED = {}
    UniversalAutoload = {
        addPalletsToPhysicsForVehicle = function(trailer) end,
        buildObjectsToUnloadTable = function(trailer, position)
            trailer.spec_universalAutoload.objectsToUnload = {}
            for object, _ in pairs(trailer.spec_universalAutoload.loadedObjects) do
                trailer.spec_universalAutoload.objectsToUnload[object] = {node = 1, position = position}
            end
        end,
        unloadObject = function(trailer, object, place)
            table.insert(UNLOADED, object); trailer.spec_universalAutoload.loadedObjects[object] = nil; return true
        end}
    PT = makeTruck({UALTRAILER}, ADGraphManager.mapMarkers[2])
    PT.settings.ALUnload = 1   -- center: belts only
    UF.targetFilters = {}
""")
# the list shows the pallets (this was empty before)
s.execute("PROWS = UF.getRows(UF.getVehicleChoices(PT), {})")
prows = [(s.eval("PROWS[%d].name" % i), s.eval("PROWS[%d].litres" % i)) for i in range(1, s.eval("#PROWS") + 1)]
assert sorted(prows) == [("BARLEY", 5000), ("WHEAT", 5000)], prows
# best price counts the pallets
assert s.eval("ADBestPrice.getLoad(PT)[2]") == 5000
# center position: hint in the dialog
assert list(s.eval("{UF.getPalletState(PT)}").values()) == [True, False]
s.execute("PT.settings.ALUnload = 3")
assert list(s.eval("{UF.getPalletState(PT)}").values()) == [True, True]
# no limit: Universal Autoload unloads everything itself
assert s.eval("UF.unloadALSelected(UALTRAILER, PT, 'behind')") is False and s.eval("#UNLOADED") == 0
# only barley (the cheese pallets): the milk pallet stays and is strapped again
s.execute("UF.setVehicleFilter(PT, {BARLEY = true})")
assert s.eval("UF.unloadALSelected(UALTRAILER, PT, 'behind')") is True
assert s.eval("#UNLOADED") == 2 and s.eval("UALTRAILER.spec_universalAutoload.loadedObjects[MILK]") == 1
assert list(s.eval("BELTS").values()) == [False, True] and s.eval("DELETED") == 1  # the unused place of the milk pallet
# the finish guard also covers pallet trailers with a limit, after 10 s
s.execute("PT.ad.trailerModule = {getHasAL = function() return true end}; g_time = 100000")
assert s.eval("UF.finishesUnloadEarly(PT)") is False
s.execute("for i = 1, 650 do g_time = g_time + 16; LAST = UF.finishesUnloadEarly(PT) end")
assert s.eval("LAST") is True
# an unknown Universal Autoload: nothing is unloaded rather than everything
s.execute("""
    WARNINGS = {}; local originalWarning = Logging.warning; Logging.warning = function(fmt, ...) table.insert(WARNINGS, fmt) end
    UNLOADED = {}; UniversalAutoload = {}; RESULT = UF.unloadALSelected(UALTRAILER, PT, 'behind')
    Logging.warning = originalWarning
""")
assert s.eval("RESULT") is True and s.eval("#UNLOADED") == 0 and "not supported" in s.eval("WARNINGS[1]")
# --- the HUD "what to load" list: on board first (most first), right after "all", then by name
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud", "GenericHudElement.lua")))
s.execute("AutoDrive.UAL_FILLTYPE_ALL = -1")
# Lua 5.5 does not allow assigning the loop variable (an upstream line, fine in the game's Lua 5.1)
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud", "PullDownList.lua")).replace("i = i - 1", "local _ = i - 1"))
s.execute("""
    LIST = setmetatable({type = ADPullDownList.TYPE_FILLTYPE, options = {{
        {displayName = "All", returnValue = -1}, {displayName = "Apple", returnValue = 9}, {displayName = "Barley", returnValue = 2},
        {displayName = "Wheat", returnValue = 1}, {displayName = "Zucchini", returnValue = 8}}}}, {__index = ADPullDownList})
    LISTTRUCK = makeTruck({unit({{1, 3000}}), unit({{2, 9000}})})
    LIST:markOnBoard(LISTTRUCK)
""")
order = [(s.eval("LIST.options[1][%d].displayName" % i), s.eval("LIST.options[1][%d].onBoard" % i)) for i in range(1, 6)]
assert order == [("All", None), ("Barley", 9000), ("Wheat", 3000), ("Apple", None), ("Zucchini", None)], order
s.execute("LISTTRUCK.units = {}; LIST:markOnBoard(LISTTRUCK)")  # unloaded: back to the name order
assert [s.eval("LIST.options[1][%d].displayName" % i) for i in range(1, 6)] == ["All", "Apple", "Barley", "Wheat", "Zucchini"]
print("OK: unload products (vehicle and target lists, best price, finish guard, savegame, event, rename, dialog rows, pallets, load list order)")
