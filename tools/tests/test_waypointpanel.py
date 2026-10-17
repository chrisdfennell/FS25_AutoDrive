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
          ("Events", "Graph", "SetConnectionEvent.lua"), ("Gui", "WaypointPanel.lua")]:
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
    function find(row, text)
        for _, b in ipairs(P.buttons) do
            if (row == nil or b.row:find(row, 1, true)) and b.text:find(text, 1, true) == 1 then return b end
        end
    end
    function click(row, text)
        draw()
        local b = find(row, text)
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
assert s.eval("shown('Zone on road (4)')")

# --- mouse: over the panel everything is used, outside nothing
assert s.eval("P:mouseEvent(V, P.rect.x + 0.001, P.rect.y + 0.001, true, false, 1)")
assert not s.eval("P:mouseEvent(V, 0.99, 0.99, false, true, 1)")
assert s.eval("P.isMouseOver(P.rect.x + 0.001, P.rect.y + 0.001)") and not s.eval("P.isMouseOver(0.99, 0.99)")
assert s.eval("#ADUndoManager.undoStack") == 0

# --- each button is one undo step
steps = 0
def step(row, text):
    global steps
    assert s.eval("click(%r, %r)" % (row, text))
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
step("Zone on road", "30")
assert [s.eval(A + ".getZone(ADGraphManager.wayPoints[%d].flags)" % i) for i in range(1, 9)] == [2, 2, 2, 2, 0, 0, 0, 0]
assert s.eval("find('Zone on road', '30').active") and s.eval("find('Speed zone', '30').active")
step("Speed zone", "15")
assert [s.eval(A + ".getZone(ADGraphManager.wayPoints[%d].flags)" % i) for i in range(1, 5)] == [2, 2, 1, 2]
assert not s.eval("find('Zone on road', '30').active")   # the road is mixed now
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

# --- target: create on this waypoint (not the closest), rename, remove
assert s.eval("click(nil, 'Create')") and s.eval("OPENED") == 1 and s.eval("AutoDrive.createMapMarkerWayPointId") == 3
s.execute("""
    AutoDrive.createMapMarkerWayPointId = nil
    ADGraphManager.mapMarkers = {{id = 3, markerIndex = 1, name = "Grain Mill", group = "All"}}
    ADUndoManager:clear(); BEFORE = snapshot(); draw()
""")
assert s.eval("shown('Target: Grain Mill')")
assert s.eval("click('Target', 'Rename')") and s.eval("AutoDrive.editMapMarkerId") == 1 and s.eval("OPENED") == 2

# --- undo everything: back to the start
steps = 0
step("Horn", "No")
step("Zone on road", "-")
s.execute("for i = 1, #ADUndoManager.undoStack do ADUndoManager:undo(nil) end")
assert s.globals().snapshot() == s.eval("BEFORE")

# --- close
s.execute("click(nil, 'X')")
assert s.eval("V.ad.selectedNodeId") is None and s.eval("P.rect == nil")

# --- an error switches the panel off instead of breaking the HUD
s.execute("V.ad.selectedNodeId = 3; local orig = P.getRows; P.getRows = function() error('boom') end; Logging = {error = function() LOGGED = true end}; draw(); P.getRows = orig")
assert s.eval("P.failed") and s.eval("LOGGED") and s.eval("P.rect == nil")
print("OK: waypoint panel (shown when, layout, connections incl. reverse in, road to junction, every button one undo step, target, close, error guard)")
