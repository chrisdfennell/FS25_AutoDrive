"""Speed zones (flags, editor keys as one undo step, braking before a zone), load products for Universal
Autoload (hook, material, choices), Universal Autoload found through the trailer, and the fleet on the map."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    FillType = {UNKNOWN = 0}
    NAMES = {[1] = "WHEAT", [2] = "MILK", [3] = "CHEESE"}
    g_fillTypeManager = {getFillTypeNameByIndex = function(self, i) return NAMES[i] end,
        getFillTypeTitleByIndex = function(self, i) return NAMES[i] end, getFillTypeIndexByName = function(self, n) for i, v in pairs(NAMES) do if v == n then return i end end end}
    MESSAGES = {}
    ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2}, addMessage = function(self, v, t, text) table.insert(MESSAGES, text) end}
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        if sendLocal then ev:run(LOCAL_CONNECTION) end
    end
""")
for f in [("Utils", "TidyTools.lua"), ("Events", "Graph", "MoveWayPointsEvent.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))
s.globals().setupNetwork(10, 2)
s.execute("ADUndoManager:clear()")

# --- zone bits: next to the actions, kept by side road changes
s.execute("""
    A = ADWaypointActions
    F = A.setZone(A.toggleHorn(1), 2)
""")
assert s.eval("A.getZone(F)") == 2 and s.eval("A.getZoneSpeed(F)") == 30 and s.eval("A.hasHorn(F)") and s.eval("F % 1024") == 1
assert s.eval("A.getZone(A.keepActions(F, 0))") == 2
assert s.eval("A.getOtherActionBits(A.setZone(0, 3))") == 0 and s.eval("A.hasActions(A.setZone(0, 3))")
assert s.eval("A.getText(A.setZone(0, 1))") == "15 km/h zone"
assert s.eval("F < 2^19")

# --- editor: zone on the route between the selected and the pointed waypoint, one undo step
s.execute("""
    ADGraphManager.wayPoints = {}
    for i = 1, 6 do
        ADGraphManager.wayPoints[i] = {id = i, x = i * 10, y = 0, z = 0, out = i < 6 and {i + 1} or {}, incoming = i > 1 and {i - 1} or {}, flags = (i == 3) and 1 or 0}
    end
    ADGraphManager.mapMarkers = {}
    ADUndoManager:clear()
    BEFORE = snapshot()
    AutoDrive.isEditorModeEnabled = function() return true end
    V = {ad = {selectedNodeId = 2, hoveredNodeId = 5}}
    A.setZoneOnRoute(V, 2)
""")
zones = [s.eval("A.getZone(ADGraphManager.wayPoints[%d].flags)" % i) for i in range(1, 7)]
assert zones == [0, 2, 2, 2, 2, 0], zones
assert s.eval("ADGraphManager.wayPoints[3].flags % 1024") == 1  # side road kept
assert s.eval("#ADUndoManager.undoStack") == 1
s.execute("ADUndoManager:undo(nil)")
assert s.eval("LAST_TEXT").startswith("Undone: speed zone changed on 4 waypoints"), s.eval("LAST_TEXT")
assert s.globals().snapshot() == s.eval("BEFORE")
s.execute("ADUndoManager:redo(nil); MESSAGES = {}; A.setZoneOnRoute(V, 0)")
assert all(s.eval("A.getZone(ADGraphManager.wayPoints[%d].flags)" % i) == 0 for i in range(1, 7))
assert "removed from 4 waypoints" in s.eval("MESSAGES[1]")
# only one waypoint pointed at
s.execute("V.ad.selectedNodeId = nil; V.ad.hoveredNodeId = 6; A.setZoneOnRoute(V, 1)")
assert s.eval("A.getZone(ADGraphManager.wayPoints[6].flags)") == 1 and s.eval("A.getZone(ADGraphManager.wayPoints[5].flags)") == 0
# the zone event carries the flags over the network
s.execute("""
    STREAM = {}; POS = 0
    local function w(id, v) table.insert(STREAM, v) end
    local function r() POS = POS + 1; return STREAM[POS] end
    streamWriteUIntN = w; streamWriteFloat32 = w; streamWriteInt32 = w
    streamReadUIntN = r; streamReadFloat32 = r; streamReadInt32 = r
    AutoDriveMoveWayPointsEvent.new({{id = 2, x = 20, y = 0, z = 0, flags = 2 ^ 18}, {id = 3, x = 31, y = 0, z = 0}}):writeStream(1, nil)
    RECEIVED = AutoDriveMoveWayPointsEvent.emptyNew()
    RECEIVED.run = function() end
    RECEIVED:readStream(1, nil)
""")
assert s.eval("RECEIVED.moves[1].flags") == 2 ** 18 and s.eval("RECEIVED.moves[2].flags") is None

# --- driving: brake before a zone, the zone speed on it
s.execute("""
    getWorldTranslation = function() return 0, 0, 0 end
    function wp(x, zone) return {x = x, y = 0, z = 0, flags = zone and A.setZone(0, zone) or 0} end
    -- a 30 km/h zone starting 100 m ahead
    DPM = {vehicle = {components = {{node = 1}}}, currentWayPoint = 2,
        wayPoints = {wp(-10), wp(20), wp(60), wp(100, 2), wp(140, 2), {x = 180, y = 0, z = 0}}}
    FAR = A.getZoneSpeedLimit(DPM)
    DPM.currentWayPoint = 4   -- on the zone
    ON = A.getZoneSpeedLimit(DPM)
    DPM.wayPoints = {wp(0), wp(500), wp(900, 1)}; DPM.currentWayPoint = 2
    NONE = A.getZoneSpeedLimit(DPM)
""")
far = s.eval("FAR")
expected = ((30 / 3.6) ** 2 + 2 * 1.5 * 100) ** 0.5 * 3.6
assert abs(far - expected) < 0.01, (far, expected)   # about 72 km/h allowed 100 m before the zone
assert s.eval("ON") == 30
assert s.eval("NONE") == float("inf")   # the zone is 900 m away, beyond the look ahead

# --- Universal Autoload found through the trailer's specializations, not a global name
s.execute("""
    UniversalAutoload = nil
    UALCLASS = {buildObjectsToUnloadTable = function() end, isValidForLoading = function(self, object) return object.loadable end}
    TRAILER = {specializations = {{}, UALCLASS}, spec_universalAutoload = {loadedObjects = {}, autoLoadingObjects = {}}}
""")
assert s.eval("ADUnloadFilter.getUAL(TRAILER) == UALCLASS")

# --- load products: Universal Autoload loads "all", AutoDrive's check chooses the pallets
s.execute("""
    UF = ADUnloadFilter
    function pallet(fillType) return {loadable = true, getFillUnits = function() return {{}} end, getFillUnitFillType = function() return fillType end,
        getFillUnitFillLevel = function() return 1000 end} end
    ACTIVE = true
    TRUCK = {ad = {stateModule = {isActive = function() return ACTIVE end}}}
    TRAILER.getRootVehicle = function() return TRUCK end
    AutoDrive.UAL_FILLTYPE_ALL = 1
""")
assert s.eval("UF.getLoadMaterial(TRAILER, TRUCK, 7)") == 7   # no list: AutoDrive's own fill type, no hook
assert s.eval("UALCLASS.adLoadFilterInstalled") is None
s.execute("UF.setVehicleLoadFilter(TRUCK, {CHEESE = true}); MATERIAL = UF.getLoadMaterial(TRAILER, TRUCK, 7)")
assert s.eval("MATERIAL") == 1 and s.eval("UALCLASS.adLoadFilterInstalled") is True
assert s.eval("UALCLASS.isValidForLoading(TRAILER, pallet(3))") is True
assert s.eval("UALCLASS.isValidForLoading(TRAILER, pallet(2))") is False
s.execute("NOTLOADABLE = pallet(3); NOTLOADABLE.loadable = false")
assert s.eval("UALCLASS.isValidForLoading(TRAILER, NOTLOADABLE)") is False   # Universal Autoload's own checks first
s.execute("FORKLIFT = pallet(2); TRAILER.spec_universalAutoload.autoLoadingObjects[FORKLIFT] = true")
assert s.eval("UALCLASS.isValidForLoading(TRAILER, FORKLIFT)") is True       # put on by hand or forklift
s.execute("ACTIVE = false")
assert s.eval("UALCLASS.isValidForLoading(TRAILER, pallet(2))") is True      # only while AutoDrive drives
s.execute("ACTIVE = true; UF.installLoadHook(TRAILER)")                     # installed once
assert s.eval("UALCLASS.isValidForLoading(TRAILER, pallet(2))") is False

# --- choices: pallets near the vehicle or its load target, counted per product
s.execute("""
    P1, P2, P3, FAR = pallet(3), pallet(3), pallet(2), pallet(2)
    for i, p in ipairs({P1, P2, P3, FAR}) do p.isPallet = true; p.rootNode = i end
    POS = {[1] = {10, 0, 0}, [2] = {15, 0, 0}, [3] = {500, 0, 0}, [4] = {2000, 0, 0}, [99] = {0, 0, 0}}
    getWorldTranslation = function(node) return unpack(POS[node]) end
    AutoDrive.getAllVehicles = function() return {P1, P2, P3, FAR} end
    AutoDrive.getAllUnits = function() return {} end
    ADGraphManager.wayPoints = {{id = 1, x = 510, y = 0, z = 0}}
    LV = {components = {{node = 99}}, ad = {stateModule = {getFirstMarker = function() return {id = 1} end}}}
    CHOICES = UF.getLoadChoices(LV)
""")
assert s.eval("CHOICES[3].count") == 2 and s.eval("CHOICES[2].count") == 1   # far pallet left out
s.execute("ROWS = UF.getRows(CHOICES, {})")
assert s.eval("ROWS[1].count") is not None

# --- fleet on the map
s.execute(t.read(os.path.join(t.MOD, "scripts", "Gui", "FleetMap.lua")))
s.execute("""
    ADFleetGui = {getLastProblem = function(v) return v.problem end}
    function mv(active, speed, problem) return {problem = problem, getLastSpeed = function() return speed end,
        ad = {stateModule = {isActive = function() return active end, getName = function() return "T" end}}} end
""")
assert s.eval("ADFleetMap.getState(mv(true, 30))") == s.eval("ADFleetMap.DRIVING")
assert s.eval("ADFleetMap.getState(mv(true, 0))") == s.eval("ADFleetMap.WAITING")
assert s.eval("ADFleetMap.getState(mv(false, 0, {}))") == s.eval("ADFleetMap.PROBLEM")
assert s.eval("ADFleetMap.getState(mv(false, 0))") == s.eval("ADFleetMap.IDLE")
s.execute("""
    g_screenWidth, g_screenHeight = 1920, 1080
    SQUARES, TEXTS = 0, {}
    createImageOverlay = function() return 1 end
    setOverlayColor = function() end; setOverlayRotation = function() end
    renderOverlay = function() SQUARES = SQUARES + 1 end
    renderText = function(x, y, size, text) table.insert(TEXTS, text) end
    setTextAlignment = function() end; setTextBold = function() end; setTextColor = function() end
    RenderText = {ALIGN_CENTER = 1, ALIGN_LEFT = 0}
    ADRoutePreview = {mapPosition = function(map, x, z) return 0.5, 0.5 end}
    SETTINGS = {showFleetOnMap = true}
    AutoDrive.getSetting = function(name) return SETTINGS[name] end
    g_localPlayer = {getFarmId = function() return 1 end}
    M1 = mv(true, 30); M1.components = {{node = 99}}; M1.getOwnerFarmId = function() return 1 end
    M2 = mv(true, 30); M2.components = {{node = 99}}; M2.getOwnerFarmId = function() return 2 end
    AutoDrive.getAllVehicles = function() return {M1, M2} end
    ADFleetMap.safeDraw({})
""")
assert s.eval("SQUARES") == 2 and s.eval("#TEXTS") == 2   # one vehicle (other farm left out): border + square, shadow + name
s.execute("SETTINGS.showFleetOnMap = false; SQUARES = 0; ADFleetMap.safeDraw({})")
assert s.eval("SQUARES") == 0
print("OK: speed zones (flags, editor, undo, network, braking), load products (hook, material, choices), Universal Autoload through the trailer, fleet on the map")
