"""Waypoint panel: shown for the selected waypoint, connections (also reverse ones into it), the road up to the
junctions, and every button is one undo step that undoes exactly."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    MESSAGES = {}
    ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2}, addMessage = function(self, v, t, text) table.insert(MESSAGES, text) end}
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        if sendLocal then ev:run(LOCAL_CONNECTION) end
    end
""")
for f in [("Utils", "TidyTools.lua"), ("Events", "Graph", "MoveWayPointEvent.lua"), ("Events", "Graph", "MoveWayPointsEvent.lua"),
          ("Events", "Graph", "SetConnectionEvent.lua"), ("Events", "Graph", "RoadEvent.lua"), ("Gui", "WaypointPanel.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))
s.globals().setupNetwork(10, 2)
s.execute("""
    -- 1 - 2 - 3 - 4 - 5 one way, 5 is a junction (to 6 and 7); 8 has a reverse connection into 3 (only in 8.out)
    local function node(id, out, incoming) return {id = id, x = id * 10, y = 5, z = 0, out = out, incoming = incoming, flags = 0} end
    ADGraphManager.wayPoints = {node(1, {2}, {}), node(2, {3}, {1}), node(3, {4}, {2}), node(4, {5}, {3}), node(5, {6, 7}, {4}),
        node(6, {}, {5}), node(7, {}, {5}), node(8, {3}, {})}
    ADGraphManager.mapMarkers = {}
    ADUndoManager:clear()
    BEFORE = snapshot()

    SETTINGS = {showHUD = true, waypointPanel = true, guiScale = 0}
    AutoDrive.getSetting = function(name) return SETTINGS[name] end
    EDITOR = true
    AutoDrive.isEditorModeEnabled = function() return EDITOR end
    AutoDrive.FONT_SCALE = 0.0115
    AutoDrive.playSample = function() end
    OPENED = 0
    AutoDrive.onOpenEnterTargetName = function() OPENED = OPENED + 1 end
    g_gameSettings = {getValue = function() return 1 end}
    g_screenWidth, g_screenHeight = 1920, 1080
    g_time = 0
    MathUtil = MathUtil or {}
    MathUtil.vector2Length = function(x, z) return math.sqrt(x * x + z * z) end
    getWorldTranslation = function() return 0, 0, 0 end
    drawFilledRect = function() end
    TEXTS_DRAWN = {}
    renderText = function(x, y, size, text) table.insert(TEXTS_DRAWN, text) end
    getTextWidth = function(size, text) return #text * size * 0.5 * g_screenHeight / g_screenWidth end
    setTextAlignment = function() end; setTextBold = function() end; setTextColor = function() end
    RenderText = {ALIGN_CENTER = 1, ALIGN_LEFT = 0}
    LINES = 0
    ADDrawingManager = {addLineTask = function() LINES = LINES + 1 end}
    g_i18n.getSpeed = function(self, v) return v end
    g_i18n.getSpeedMeasuringUnit = function() return "km/h" end

    HUD = {posX = 0.1, posY = 0.3, width = 0.2, height = 0.25, rowHeader = 0.52, headerHeight = 0.03}
    V = {ad = {selectedNodeId = 3}, components = {{node = 1}}}
    P = ADWaypointPanel
    function draw() TEXTS_DRAWN = {}; g_time = g_time + 1000; P.safeDraw(V, HUD) end
    -- section nil: the rows of the waypoint, "road": the rows of the road
    function find(row, text, section)
        for _, b in ipairs(P.buttons) do
            if (row == nil or b.row:find(row, 1, true)) and b.text:find(text, 1, true) == 1 and b.section == section then return b end
        end
    end
    function click(row, text, section)
        draw()
        local b = find(row, text, section)
        assert(b ~= nil, "no button " .. tostring(row) .. " / " .. text)
        local used = P:mouseEvent(V, b.x + b.width / 2, b.y + b.height / 2, false, true, 1)
        draw()
        return used
    end
    function shown(text) for _, t in ipairs(TEXTS_DRAWN) do if t == text then return true end end return false end
""")
A = "ADWaypointActions"

# --- shown only for a selected waypoint in the editor, with the HUD and the setting on
s.execute("draw()")
assert s.eval("P.rect ~= nil") and s.eval("shown('Waypoint 3')") and s.eval("shown('No target')")
assert not s.eval("P.failed")
for setup in ["EDITOR = false", "SETTINGS.waypointPanel = false", "SETTINGS.showHUD = false", "V.ad.newcreated = 3", "V.ad.selectedNodeId = nil", "V.ad.selectedNodeId = 99"]:
    s.execute("%s; draw()" % setup)
    assert s.eval("P.rect == nil"), setup
    s.execute("EDITOR = true; SETTINGS.waypointPanel = true; SETTINGS.showHUD = true; V.ad.newcreated = nil; V.ad.selectedNodeId = 3; draw()")
assert s.eval("P.rect ~= nil")
# right of the HUD; left of it when there is no room on the right
assert s.eval("P.rect.x > HUD.posX + HUD.width")
s.execute("HUD.posX = 0.85; HUD.width = 0.14; draw()")
assert s.eval("P.rect.x + P.rect.width < HUD.posX")
s.execute("HUD.posX = 0.1; HUD.width = 0.2; draw()")

# --- connections, also the reverse one into the waypoint, and the road up to the junction
assert s.eval("shown('Connections: 2 in, 1 out')"), list(s.eval("TEXTS_DRAWN").values())
assert s.eval("P.cache.connections[1].id") == 2 and s.eval("P.cache.connections[1].direction") == s.eval("P.IN")
assert s.eval("P.cache.connections[2].direction") == s.eval("P.OUT")
assert s.eval("P.cache.connections[3].id") == 8 and s.eval("P.cache.connections[3].direction") == s.eval("P.REVERSE_IN")
assert sorted(s.eval("P.getRoad(3)").values()) == [1, 2, 3, 4]
assert list(s.eval("P.getRoad(5)").values()) == [5]   # a junction is a road on its own
assert s.eval("shown('Road: 4 waypoints')")
# the road in driving order with the junction at the end
assert list(s.eval("P.cache.chain").values()) == [1, 2, 3, 4, 5]
assert s.eval("find('Direction', 'One-way', 'road').active")

# --- mouse: over the panel everything is used, outside nothing
assert s.eval("P:mouseEvent(V, P.rect.x + 0.001, P.rect.y + 0.001, true, false, 1)")
assert not s.eval("P:mouseEvent(V, 0.99, 0.99, false, true, 1)")
assert s.eval("P.isMouseOver(P.rect.x + 0.001, P.rect.y + 0.001)") and not s.eval("P.isMouseOver(0.99, 0.99)")
assert s.eval("#ADUndoManager.undoStack") == 0

# --- each button is one undo step
steps = 0
def step(row, text, section=None):
    global steps
    assert s.eval("click(%r, %r, %s)" % (row, text, "'road'" if section else "nil"))
    steps += 1
    assert s.eval("#ADUndoManager.undoStack") == steps, (row, text, s.eval("#ADUndoManager.undoStack"))

step("Horn", "Yes")
assert s.eval(A + ".hasHorn(ADGraphManager.wayPoints[3].flags)")
step("Wait", "Off")
assert s.eval(A + ".getWaitSeconds(ADGraphManager.wayPoints[3].flags)") == 5
assert s.eval("find('Wait', '5 s').text") == "5 s  >"
step("Lights", "Off")
assert s.eval(A + ".getLights(ADGraphManager.wayPoints[3].flags)") == s.eval(A + ".LIGHTS_OFF")
step("Unlock", "Yes")
assert s.eval(A + ".hasUnlock(ADGraphManager.wayPoints[3].flags)")
step("Side road", "Yes")
assert s.eval("ADGraphManager:getIsPointSubPrio(3)") and s.eval(A + ".hasHorn(ADGraphManager.wayPoints[3].flags)")
step("Speed zone", "30", "road")
assert [s.eval(A + ".getZone(ADGraphManager.wayPoints[%d].flags)" % i) for i in range(1, 9)] == [2, 2, 2, 2, 0, 0, 0, 0]
assert s.eval("find('Speed zone', '30', 'road').active") and s.eval("find('Speed zone', '30').active")
step("Speed zone", "15")
assert [s.eval(A + ".getZone(ADGraphManager.wayPoints[%d].flags)" % i) for i in range(1, 5)] == [2, 2, 1, 2]
assert not s.eval("find('Speed zone', '30', 'road').active")   # the road is mixed now
# side road for the whole road (not the junction), keeping the actions
step("Side road", "Yes", "road")
assert [s.eval("ADGraphManager:getIsPointSubPrio(%d)" % i) for i in range(1, 6)] == [True, True, True, True, False]
assert s.eval("find('Side road', 'Yes', 'road').active") and s.eval(A + ".hasHorn(ADGraphManager.wayPoints[3].flags)")
step("Side road", "No", "road")
assert not any(s.eval("ADGraphManager:getIsPointSubPrio(%d)" % i) for i in range(1, 6))
# direction of the whole road, up to the junction: two-way, back to one-way, turned round
step("Direction", "Two-way", "road")
assert all(s.eval("ADWaypointPanel.getDirection(ADGraphManager.wayPoints[%d], ADGraphManager.wayPoints[%d])" % (i, i + 1)) == 3 for i in range(1, 5))
assert s.eval("find('Direction', 'Two-way', 'road').active")
step("Direction", "One-way", "road")
assert all(s.eval("ADWaypointPanel.getDirection(ADGraphManager.wayPoints[%d], ADGraphManager.wayPoints[%d])" % (i, i + 1)) == 1 for i in range(1, 5))
step("Direction", "Flip", "road")
assert all(s.eval("ADWaypointPanel.getDirection(ADGraphManager.wayPoints[%d], ADGraphManager.wayPoints[%d])" % (i, i + 1)) == 2 for i in range(1, 5))
assert s.eval("table.contains(ADGraphManager.wayPoints[5].out, 6)")    # the other roads of the junction stay
s.execute("ADUndoManager:undo(nil)")
steps -= 1
assert all(s.eval("ADWaypointPanel.getDirection(ADGraphManager.wayPoints[%d], ADGraphManager.wayPoints[%d])" % (i, i + 1)) == 1 for i in range(1, 5))
# a lit button does nothing
s.execute("click('Horn', 'Yes')")
assert s.eval("#ADUndoManager.undoStack") == steps
# connection to 4: out -> in
step("Waypoint 4", "Out")
assert s.eval("table.contains(ADGraphManager.wayPoints[3].incoming, 4) and table.contains(ADGraphManager.wayPoints[4].out, 3)")
assert not s.eval("table.contains(ADGraphManager.wayPoints[3].out, 4)")
assert s.eval("find('Waypoint 4', 'In') ~= nil")
# hovering a connection draws a line to that waypoint
s.execute("local b = find('Waypoint 4', 'In'); g_lastMousePosX, g_lastMousePosY = b.x + 0.001, b.y + 0.001; LINES = 0; draw()")
assert s.eval("LINES") == 1
s.execute("g_lastMousePosX, g_lastMousePosY = nil, nil")

# remove a connection: no link left in either direction, one undo step
step("Waypoint 4", "X")
assert not any(s.eval("table.contains(ADGraphManager.wayPoints[%d].%s, %d)" % (a, l, b)) for a, b in [(3, 4), (4, 3)] for l in ["out", "incoming"])
s.execute("ADUndoManager:undo(nil)")
steps -= 1
assert s.eval("table.contains(ADGraphManager.wayPoints[4].out, 3)")

# tidy the road: a waypoint pulled off the line is straightened back, one undo step
s.execute("""
    AutoDrive.getTerrainHeightAtWorldPos = function(self, x, z, y) return 5 end
    ADGraphManager.wayPoints[3].z = 4
""")
step("Tidy", "Straight", "road")
assert abs(s.eval("ADGraphManager.wayPoints[3].z")) < 0.01
s.execute("MESSAGES = {}; click('Tidy', 'Straight', 'road')")   # already straight: nothing to do, no step
assert s.eval("#ADUndoManager.undoStack") == steps and s.eval("MESSAGES[1]") == "This route is already tidy"
s.execute("ADUndoManager:undo(nil)"); steps -= 1
assert s.eval("ADGraphManager.wayPoints[3].z") == 4
s.execute("ADGraphManager.wayPoints[3].z = 0")

# --- target: create on this waypoint (not the closest), rename, remove
assert s.eval("click(nil, 'Create')") and s.eval("OPENED") == 1 and s.eval("AutoDrive.createMapMarkerWayPointId") == 3
s.execute("""
    AutoDrive.createMapMarkerWayPointId = nil
    ADGraphManager.mapMarkers = {{id = 3, markerIndex = 1, name = "Grain Mill", group = "All"}}
    ADUndoManager:clear(); BEFORE = snapshot(); draw()
""")
assert s.eval("shown('Target: Grain Mill')")
assert s.eval("click('Target', 'Rename')") and s.eval("AutoDrive.editMapMarkerId") == 1 and s.eval("OPENED") == 2
# drive here: this vehicle, to this target; send vehicle: the list of vehicles for this target
s.execute("""
    AutoDriveSendToEvent = {sendEvent = function(vehicle, markerIndex) SENT_TO = {vehicle, markerIndex} end}
    AutoDrive.onOpenSendTo = function(vehicle, markerIndex) SEND_DIALOG = {vehicle, markerIndex} end
""")
assert s.eval("click('Vehicles', 'Drive here')") and s.eval("SENT_TO[1] == V") and s.eval("SENT_TO[2]") == 1
assert s.eval("click('Vehicles', 'Send vehicle')") and s.eval("SEND_DIALOG[1]") is None and s.eval("SEND_DIALOG[2]") == 1
assert s.eval("#ADUndoManager.undoStack") == 0

# --- undo everything: back to the start
steps = 0
step("Horn", "No")
step("Speed zone", "-", "road")
step("Direction", "Two-way", "road")
s.execute("for i = 1, #ADUndoManager.undoStack do ADUndoManager:undo(nil) end")
assert s.globals().snapshot() == s.eval("BEFORE")

# --- close
s.execute("click(nil, 'X')")
assert s.eval("V.ad.selectedNodeId") is None and s.eval("P.rect == nil")

# --- through the HUD's own mouse handling: moving onto the panel and clicking it keeps the selected waypoint
# (a HUD element that uses a click still clears the selection, as in AutoDrive)
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud.lua")))
s.execute("""
    AutoDrive.isMouseActiveForHud = function() return true end
    AutoDrive.isMouseActiveForEditor = function() return true end
    AutoDrive.isInExtendedEditorMode = function() return true end
    AutoDrive.leftLSHIFTmodifierKeyPressed, AutoDrive.leftCTRLmodifierKeyPressed = false, false
    AutoDrive.leftALTmodifierKeyPressed, AutoDrive.rightSHIFTmodifierKeyPressed = false, false
    AutoDrive.mouseIsAtPos = function() return false end
    g_inputBinding = {getShowMouseCursor = function() return true end}
    V.getWayPointsInRange = function() return {} end
    V.ad.selectedNodeId = 3
    REALHUD = setmetatable({hudElements = {}, posX = 0.1, posY = 0.3, width = 0.2, height = 0.25, rowHeader = 0.52, headerHeight = 0.03}, {__index = AutoDriveHud})
    HUD = REALHUD
    draw()
    function hudMouse(x, y, isDown, isUp, button) REALHUD:mouseEvent(V, x, y, isDown, isUp, button); draw() end
""")
assert s.eval("P.rect ~= nil")
# mouse moves across the world to the panel, then over it
s.execute("hudMouse(0.5, 0.5, false, false, 0); hudMouse(P.rect.x + 0.002, P.rect.y + 0.002, false, false, 0)")
assert s.eval("V.ad.selectedNodeId") == 3 and s.eval("P.rect ~= nil")
# a click on a panel button: the action happens and the panel stays
s.execute("local b = find('Horn', 'Yes'); hudMouse(b.x + 0.001, b.y + 0.001, true, false, 1); hudMouse(b.x + 0.001, b.y + 0.001, false, true, 1)")
assert s.eval("V.ad.selectedNodeId") == 3 and s.eval("P.rect ~= nil")
assert s.eval("ADWaypointActions.hasHorn(ADGraphManager.wayPoints[3].flags)")
# a HUD element that uses a click still clears the selection
s.execute("""
    REALHUD.hudElements = {{layer = 1, mouseEvent = function(self, v, x, y, isDown, isUp, button) return button == 1 and isUp end}}
    REALHUD.refreshHudElementsLayerSequence = function() end
    hudMouse(0.15, 0.4, false, true, 1)
""")
assert s.eval("V.ad.selectedNodeId") is None
s.execute("REALHUD.hudElements = {}; HUD = REALHUD")

# --- construction screen (landscaping): the left button paints there. A move key "held" since Shift + P opened
# the screen must not drag waypoints, and left clicks must not select or connect them
s.execute("""
    GUI_VISIBLE = true
    g_gui = {getIsGuiVisible = function() return GUI_VISIBLE end}
    AutoDrive.isMouseActiveForHud = function() return not GUI_VISIBLE end
    WP3 = ADGraphManager.wayPoints[3]
    V.getWayPointsInRange = function() return {WP3, ADGraphManager.wayPoints[4]} end
    POINTED = 3
    AutoDrive.mouseIsAtPos = function(point) return point.id == POINTED end
    AutoDrive.moveNodeToMousePos = function(id) MOVED = id end
    AutoDrive.playSample = function() end
    V.ad.selectedNodeId = nil
    AutoDrive.moveNodeKeyPressed = true
    g_lastMousePosX, g_lastMousePosY = 0.5, 0.5
    BEFORE_LINKS = snapshot()
    REALHUD:mouseEvent(V, 0.5, 0.5, true, false, 1)            -- left down on waypoint 3
    g_lastMousePosX = 0.6
    REALHUD:mouseEvent(V, 0.6, 0.5, false, false, 0)           -- drag
    REALHUD:mouseEvent(V, 0.6, 0.5, false, true, 1)            -- left up
    POINTED = 4
    REALHUD:mouseEvent(V, 0.6, 0.5, false, true, 1)            -- a click on waypoint 4
""")
assert s.eval("MOVED") is None and s.eval("V.ad.keyDragNodeId") is None and s.eval("V.ad.nodeToMoveId") is None
assert s.eval("V.ad.selectedNodeId") is None and not s.eval("AutoDrive.moveNodeKeyPressed")
assert s.globals().snapshot() == s.eval("BEFORE_LINKS")
# back in the game the editor clicks work as before
s.execute("""
    GUI_VISIBLE = false
    POINTED = 3
    REALHUD:mouseEvent(V, 0.5, 0.5, false, true, 1)
""")
assert s.eval("V.ad.selectedNodeId") == 3
s.execute("V.ad.selectedNodeId = 3; g_lastMousePosX, g_lastMousePosY = nil, nil; draw()")

# --- the road event: through the stream, and a client applies it without asking the server again
s.execute("""
    STREAM = {}; POS = 0
    streamWriteUIntN = function(id, v) table.insert(STREAM, v) end
    streamReadUIntN = function() POS = POS + 1; return STREAM[POS] end
    AutoDriveRoadEvent.new({{1, 2, 3}, {3, 4, AutoDriveRoadEvent.REMOVE}}):writeStream(1, nil)
    RECEIVED = AutoDriveRoadEvent.emptyNew()
    RECEIVED.run = function() end
    RECEIVED:readStream(1, nil)
""")
assert [list(l.values()) for l in s.eval("RECEIVED.links").values()] == [[1, 2, 3], [3, 4, 5]]

# --- send to: the vehicles of the farm for a target, nearest first, and sending one
s.execute(t.read(os.path.join(t.MOD, "scripts", "Gui", "SendToGUI.lua")))
s.execute("""
    ADGraphManager.mapMarkers = {{id = 5, markerIndex = 1, name = "Grain Mill", group = "All"}}
    local function car(name, x, active) return {components = {{node = name}}, ad = {stateModule = {getName = function() return name end, isActive = function() return active end}}} end
    FAR, NEAR = car("Far", 900, false), car("Near", 60, true)
    POSITIONS = {Far = 900, Near = 60}
    getWorldTranslation = function(node) return POSITIONS[node] or 0, 0, 0 end
    ADFleetMap = {getVehicles = function() return {FAR, NEAR} end}
    LIST = ADSendToGui.getVehicles(1)
    GUI = setmetatable({targets = LIST, markerIndex = 1, onClickBack = function() CLOSED = true end}, {__index = ADSendToGui})
    SENT_TO = nil
    GUI:send(1)
""")
assert s.eval("LIST[1].name") == "Near" and s.eval("LIST[2].name") == "Far"
assert s.eval("ADSendToGui.getVehicleRowText(LIST[1])") == "Near  (0.0 km)  - busy"
assert s.eval("SENT_TO[1] == NEAR") and s.eval("SENT_TO[2]") == 1 and s.eval("CLOSED")

# --- an error switches the panel off instead of breaking the HUD
s.execute("V.ad.selectedNodeId = 3; local orig = P.getRows; P.getRows = function() error('boom') end; Logging = {error = function() LOGGED = true end}; draw(); P.getRows = orig")
assert s.eval("P.failed") and s.eval("LOGGED") and s.eval("P.rect == nil")
print("OK: waypoint panel (shown when, stays while the mouse is on it, construction screen ignores left clicks, road: zone, side road, direction, tidy; remove connection, drive here, send vehicle, layout, connections incl. reverse in, road to junction, every button one undo step, target, close, error guard)")
