"""Waypoint actions, route check fixes, send-to and the route preview."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    MESSAGES = {}
    ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2, ERROR = 3}, addMessage = function(self, v, t, text) table.insert(MESSAGES, text) end}
    AutoDriveMessageEvent = {sendMessageOrNotification = function(vehicle, t, text, d, ...) table.insert(MESSAGES, string.format(text, ...)) end}
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    TO_CLIENTS = {}
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        table.insert(TO_CLIENTS, ev)
        if sendLocal then ev:run(LOCAL_CONNECTION) end
    end
""")
for f in [("Events", "Graph", "MoveWayPointEvent.lua"), ("Events", "Graph", "DeleteWayPointsEvent.lua"), ("Events", "Graph", "RouteFixEvent.lua"),
          ("Manager", "RouteCheck.lua"), ("Events", "SendToEvent.lua"), ("Manager", "RoutePreview.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))
s.globals().setupNetwork(10, 2)
s.execute("ADUndoManager:clear()")

# --- action bits: independent fields, the low flag bits (side road = 1) are untouched
s.execute("""
    A = ADWaypointActions
    F = 1
    F = A.nextWait(F); F = A.nextWait(F)          -- 10 s
    F = A.toggleHorn(F)
    F = A.nextLights(F)                            -- on
""")
assert s.eval("A.getWaitSeconds(F)") == 10 and s.eval("A.hasHorn(F)") and s.eval("A.getLights(F)") == 1
assert s.eval("F % 1024") == 1 and s.eval("F < 65536")
assert s.eval("A.getText(F)") == "wait 10 s, horn, lights on"
s.execute("G = F; for i = 1, 6 do G = A.nextWait(G) end")  # 8 steps in total: back to 0
assert s.eval("A.getWaitSeconds(G)") == 0 and s.eval("A.hasHorn(G)")
assert s.eval("A.getText(A.nextLights(A.nextLights(A.toggleHorn(G))))") is None  # all off again
# a section set to side road (flags = 1) or back (0) keeps the actions
assert s.eval("A.keepActions(F, 0) % 1024") == 0 and s.eval("A.getActionBits(A.keepActions(F, 0))") == s.eval("A.getActionBits(F)")
assert s.eval("A.getActionBits(5)") == 0

# --- editing in the editor: one undo step, described as waypoint action
s.execute("""
    AutoDrive.isEditorModeEnabled = function() return true end
    VEHICLE = {ad = {hoveredNodeId = 3}}
    BEFORE = ADGraphManager.wayPoints[3].flags
    ADWaypointActions.edit(VEHICLE, ADWaypointActions.toggleHorn)
""")
assert s.eval("ADWaypointActions.hasHorn(ADGraphManager.wayPoints[3].flags)")
assert s.eval("#ADUndoManager.undoStack") == 1
s.execute("ADUndoManager:undo(nil)")
assert s.eval("LAST_TEXT").startswith("Undone: waypoint action changed"), s.eval("LAST_TEXT")
assert s.eval("ADGraphManager.wayPoints[3].flags") == s.eval("BEFORE")
s.execute("VEHICLE.ad.hoveredNodeId = nil; MESSAGES = {}; ADWaypointActions.edit(VEHICLE, ADWaypointActions.toggleHorn)")
assert "point the mouse at a waypoint" in s.eval("MESSAGES[1]")

# --- driving: reaching a waypoint with actions
s.execute("""
    g_time = 1000
    STOPPED = 0
    HONK = {}; LIGHTS = {}
    DRIVER = {ad = {stateModule = {isActive = function() return true end},
        specialDrivingModule = {stopVehicle = function() STOPPED = STOPPED + 1 end, update = function() end}},
        playHonk = function(self, on) table.insert(HONK, on) end,
        setLightsTypesMask = function(self, mask) table.insert(LIGHTS, mask) end}
    ADWaypointActions.onReached(DRIVER, {flags = F})
""")
assert list(s.eval("HONK").values()) == [True] and list(s.eval("LIGHTS").values()) == [1]
assert s.eval("ADWaypointActions.updateWaiting(DRIVER, 16)") is True and s.eval("STOPPED") == 1
s.execute("g_time = 1900")  # horn off after 800 ms, still waiting
assert s.eval("ADWaypointActions.updateWaiting(DRIVER, 16)") is True
assert list(s.eval("HONK").values()) == [True, False]
s.execute("g_time = 11001")  # 10 s later: drives on
assert s.eval("ADWaypointActions.updateWaiting(DRIVER, 16)") is False
s.execute("ADWaypointActions.onReached(DRIVER, {flags = A.nextLights(A.nextLights(0))})")  # lights off
assert list(s.eval("LIGHTS").values()) == [1, 0]
s.execute("ADWaypointActions.onReached(DRIVER, {flags = 1})")  # no actions: nothing happens
assert s.eval("DRIVER.ad.actionWaitUntil") is None

# --- unlock load: belts open at the waypoint, closed again when a new route starts or the vehicle drives on
s.execute("""
    U = A.toggleUnlock(A.toggleHorn(1))
    BELTS = {}
    TRAILER = {setAllTensionBeltsActive = function(self, active) table.insert(BELTS, active) end}
    AutoDrive.getAllUnits = function(v) return {v, TRAILER} end
    PATH = {{id = 50}, {id = 51}}
    CURRENT = PATH[1]
    DRIVER.ad.drivePathModule = {getWayPoints = function() return CURRENT_PATH end, getCurrentWayPoint = function() return CURRENT end}
    CURRENT_PATH = PATH
""")
assert s.eval("A.hasUnlock(U)") and s.eval("A.hasHorn(U)") and s.eval("U % 1024") == 1 and s.eval("U < 2^17")
assert s.eval("A.getText(U)") == "horn, unlock load"
assert s.eval("A.getActionBits(A.keepActions(U, 0))") == s.eval("A.getActionBits(U)")
s.execute("ADWaypointActions.onReached(DRIVER, {id = 50, flags = U})")
assert list(s.eval("BELTS").values()) == [False]  # the trailer, the truck has no belts
# standing at the target (no route): stays open; same route, same waypoint: stays open
s.execute("CURRENT_PATH = nil; ADWaypointActions.updateWaiting(DRIVER, 16); CURRENT_PATH = PATH; ADWaypointActions.updateWaiting(DRIVER, 16)")
assert list(s.eval("BELTS").values()) == [False]
# a new route (also starting at the same waypoint): locked again before driving off
s.execute("CURRENT_PATH = {{id = 50}, {id = 60}}; CURRENT = CURRENT_PATH[1]; ADWaypointActions.updateWaiting(DRIVER, 16)")
assert list(s.eval("BELTS").values()) == [False, True] and s.eval("DRIVER.ad.loadUnlockedWayPointId") is None
s.execute("ADWaypointActions.updateWaiting(DRIVER, 16)")  # only once
assert len(list(s.eval("BELTS").values())) == 2
# with a wait on the same waypoint in the middle of a route: locked after the wait, when driving on
s.execute("""
    CURRENT_PATH = PATH; CURRENT = PATH[1]; g_time = 20000
    ADWaypointActions.onReached(DRIVER, {id = 50, flags = A.nextWait(U)})
    STILL = ADWaypointActions.updateWaiting(DRIVER, 16)
""")
assert s.eval("STILL") is True and list(s.eval("BELTS").values())[-1] is False
s.execute("g_time = 26000; CURRENT = PATH[2]; ADWaypointActions.updateWaiting(DRIVER, 16)")
assert list(s.eval("BELTS").values())[-1] is True

# --- route check fixes
s.execute("""
    function wp(id, x, z, out, incoming) return {id = id, x = x, y = 0, z = z, out = out, incoming = incoming, flags = 0} end
    function network()
        ADGraphManager.wayPoints = {
            wp(1, 0, 0, {2}, {2}), wp(2, 10, 0, {1, 3}, {1, 3}), wp(3, 20, 0, {2, 4}, {2}),  -- 1 = 2 = 3 two-way, 3 -> 4
            wp(4, 30, 0, {}, {3}),                -- dead end
            wp(5, 10.1, 0.1, {6}, {}),            -- on top of 2, leads to 6
            wp(6, 10, 20, {}, {5}),               -- dead end, 2 is within 30 m
            wp(7, 90, 90, {}, {}),                -- loose
        }
        ADGraphManager.mapMarkers = {{id = 1, name = "Farm", markerIndex = 1, group = "All"}}
    end
    network()
    ADUndoManager:clear()
    BEFORE = snapshot()
    PROBLEMS = ADRouteCheck.analyse(ADGraphManager.wayPoints, ADGraphManager.mapMarkers)
    function problemOf(kind, id) for _, p in ipairs(PROBLEMS) do if p.kind == kind and p.wayPointId == id then return p end end end
""")
# loose waypoint: deleted
s.execute("TO_CLIENTS = {}; OK = ADRouteCheck:fix(problemOf(ADRouteCheck.LOOSE, 7))")
assert s.eval("OK") and s.eval("#ADGraphManager.wayPoints") == 6
assert s.eval("#TO_CLIENTS") == 1 and s.eval("TO_CLIENTS[1].fixType") == 1
assert s.eval("#ADUndoManager.undoStack") == 1
# merge 5 into 2: 2 gets the connection to 6, 5 is gone
s.execute("PROBLEMS = ADRouteCheck.analyse(ADGraphManager.wayPoints, ADGraphManager.mapMarkers)")
s.execute("OK = ADRouteCheck:fix(problemOf(ADRouteCheck.DUPLICATE, 2))")
assert s.eval("OK") and s.eval("#ADGraphManager.wayPoints") == 5
assert s.eval("table.contains(ADGraphManager.wayPoints[2].out, 5)")  # old 6 is now 5
assert s.eval("table.contains(ADGraphManager.wayPoints[5].incoming, 2)")
assert s.eval("#ADUndoManager.undoStack") == 2
# dead end 4 (at 30,0): nearest waypoint within 30 m that does not lead to it: 2 is 20 m away, 3 leads to it
s.execute("PROBLEMS = ADRouteCheck.analyse(ADGraphManager.wayPoints, ADGraphManager.mapMarkers)")
s.execute("OK = ADRouteCheck:fix(problemOf(ADRouteCheck.DEAD_END, 4))")
assert s.eval("OK") and s.eval("table.contains(ADGraphManager.wayPoints[4].out, 2)")
# everything back with three undos
s.execute("ADUndoManager:undo(nil); ADUndoManager:undo(nil); ADUndoManager:undo(nil)")
assert s.globals().snapshot() == s.eval("BEFORE")
# a client applies the same fixes and ends up with the same network
client = t.make_runtime(False)
client.execute(t.read(os.path.join(t.MOD, "scripts", "Manager", "RouteCheck.lua")))
client.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", "RouteFixEvent.lua")))
client.globals().setupNetwork(10, 2)
client.execute("""
    function wp(id, x, z, out, incoming) return {id = id, x = x, y = 0, z = z, out = out, incoming = incoming, flags = 0} end
""")
client.execute("""
    ADGraphManager.wayPoints = {
        wp(1, 0, 0, {2}, {2}), wp(2, 10, 0, {1, 3}, {1, 3}), wp(3, 20, 0, {2, 4}, {2}), wp(4, 30, 0, {}, {3}),
        wp(5, 10.1, 0.1, {6}, {}), wp(6, 10, 20, {}, {5}), wp(7, 90, 90, {}, {}),
    }
    ADGraphManager.mapMarkers = {{id = 1, name = "Farm", markerIndex = 1, group = "All"}}
""")
s.execute("ADUndoManager:redo(nil); ADUndoManager:redo(nil); ADUndoManager:redo(nil)")
fixes = [(s.eval("TO_CLIENTS[%d].fixType" % i), s.eval("TO_CLIENTS[%d].a" % i), s.eval("TO_CLIENTS[%d].b" % i)) for i in range(1, 4)]
for fix in fixes:
    client.execute("AutoDriveRouteFixEvent.new(%d, %d, %d):run(nil)" % fix)
assert client.globals().snapshot() == s.globals().snapshot()
# not fixable: two targets on top of each other, an outdated list
s.execute("""
    network()
    ADGraphManager.mapMarkers = {{id = 2, name = "A", markerIndex = 1, group = "All"}, {id = 5, name = "B", markerIndex = 2, group = "All"}}
    PROBLEMS = ADRouteCheck.analyse(ADGraphManager.wayPoints, ADGraphManager.mapMarkers)
    MESSAGES = {}
    OK = ADRouteCheck:fix(problemOf(ADRouteCheck.DUPLICATE, 2))
""")
assert not s.eval("OK") and "can not be merged" in s.eval("MESSAGES[1]")
s.execute("ADGraphManager.wayPoints[7].x = 50; MESSAGES = {}; OK = ADRouteCheck:fix(problemOf(ADRouteCheck.LOOSE, 7))")
assert not s.eval("OK") and "changed" in s.eval("MESSAGES[1]")

# --- send to: drive to mode, new destination, (re)started, message
s.execute("""
    AutoDrive.MODE_DRIVETO = 1; AutoDrive.MODE_PICKUPANDDELIVER = 2; AutoDrive.MODE_DELIVERTO = 3
    network()
    CALLS = {}
    AutoDrive.StopCP = function() end
    ADInputManager = {input_start_stop = function(self, v, farmId) table.insert(CALLS, "startstop"); v.ad.stateModule.active = not v.ad.stateModule.active end}
    ADGraphManager.getMapMarkerById = function(self, i) return self.mapMarkers[i] end
    SM = {active = true, mode = 2, isActive = function(self) return self.active end, setMode = function(self, m) self.mode = m end,
        setFirstMarker = function(self, i) self.first = i end, getName = function() return "Truck" end}
    TRUCK = {ad = {stateModule = SM}, getOwnerFarmId = function() return 1 end}
    MESSAGES = {}
    AutoDriveSendToEvent.sendEvent(TRUCK, 1)
""")
assert list(s.eval("CALLS").values()) == ["startstop", "startstop"]
assert s.eval("SM.active") and s.eval("SM.mode") == 1 and s.eval("SM.first") == 1
assert s.eval("MESSAGES[1]") == "$l10n_AD_Driver_of; Truck $l10n_AD_sendTo_driving; Farm"

# --- route preview: legs, length, simplification, map positions and lines
s.execute("""
    ADGraphManager.getPathTo = function(self, vehicle, id) return {self.wayPoints[1], self.wayPoints[2], self.wayPoints[3]} end
    ADGraphManager.pathFromTo = function(self, a, b) return {self.wayPoints[3], self.wayPoints[4]} end
    ADGraphManager.getDriveTimeForWaypoints = function() return 90 end
    PV = {ad = {stateModule = {getMode = function() return 2 end, getFirstMarker = function() return {id = 3, name = "Field"} end,
        getSecondMarker = function() return {id = 4, name = "Silo"} end, getSpeedLimit = function() return 40 end}}}
    MESSAGES = {}
    ADRoutePreview.installMapHooks = function() end
    ADRoutePreview:toggle(PV)
""")
assert s.eval("#ADRoutePreview.legs") == 2
assert s.eval("ADRoutePreview.legs[1].length") == 20 and s.eval("ADRoutePreview.legs[2].length") == 10
assert s.eval("MESSAGES[1]") == "To Field: 0.0 km, about 2 min  |  To Silo: 0.0 km, about 2 min", s.eval("MESSAGES[1]")
s.execute("ADRoutePreview:toggle(PV)")
assert s.eval("ADRoutePreview.legs") is None
s.execute("""
    PTS = {}; for i = 1, 1000 do PTS[i] = {x = i, z = 0} end
    SIMPLE = ADRoutePreview.simplify(PTS, 100)
""")
assert s.eval("#SIMPLE") == 101 and s.eval("SIMPLE[1].x") == 1 and s.eval("SIMPLE[101].x") == 1000
s.execute("""
    MAP = {worldCenterOffsetX = 1024, worldCenterOffsetZ = 1024, worldSizeX = 2048, worldSizeZ = 2048,
        fullScreenLayout = {getMapObjectPosition = function(self, u, v) return u, 1 - v end}}
    MX, MY = ADRoutePreview.mapPosition(MAP, 0, 0, false)
""")
assert s.eval("MX") == 0.5 and s.eval("MY") == 0.5
s.execute("""
    g_screenWidth = 1920; g_screenHeight = 1080
    RENDERED = {}
    setOverlayColor = function() end
    setOverlayRotation = function(id, rot) ROT = rot end
    renderOverlay = function(id, x, y, w, h) table.insert(RENDERED, w) end
    ADRoutePreview.drawMapLine(1, 0.5, 0.5, 0.5, 0.6, 0.002, 1, 1, 1)  -- straight up on the screen
""")
assert abs(s.eval("ROT") - 3.14159265 / 2) < 1e-6 and abs(s.eval("RENDERED[1]") - 108 / 1920) < 1e-9
print("OK: waypoint actions, route check fixes (with undo and clients), send to, route preview")
