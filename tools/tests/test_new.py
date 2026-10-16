"""Per player undo, nudge merging, undo while recording, routes import undo, notices, preview, HUD state, pointer."""
import random

import run_undo_test as t

PLAYERS_LUA = """
SENT = {}
local function connection(id, name)
    return {user = {uniqueUserId = id, nickname = name}, getIsServer = function() return false end,
        sendEvent = function(self, ev) table.insert(SENT, {to = id, event = ev}) end}
end
PLAYERS = {B = connection("idB", "Bob"), C = connection("idC", "")}
function asPlayer(name, code)
    ADUndoManager.actorConnection = PLAYERS[name]
    local ok, err = pcall(load(code))
    ADUndoManager.actorConnection = nil
    if not ok then error(err) end
end
function lastSentText()
    local ev = SENT[#SENT].event
    return ADUndoManager.getFeedbackText(ev.textKey, ev.undoCount, ev.redoCount, ev.parts)
end
DRAWN = {spheres = 0, lines = 0, arrows = 0}
ADDrawingManager = {addSphereTask = function() DRAWN.spheres = DRAWN.spheres + 1 end, addLineTask = function() DRAWN.lines = DRAWN.lines + 1 end,
    addSmallSphereTask = function() end, addArrowTask = function() DRAWN.arrows = DRAWN.arrows + 1 end, arrows = {position = {start = 1}}}
"""


def server_with(n, seed, client=False):
    s = t.make_runtime(True)
    s.execute(PLAYERS_LUA)
    s.globals().setupNetwork(n, seed)
    if not client:
        return s
    c = t.make_runtime(False)
    c.execute(PLAYERS_LUA)
    c.globals().setupNetwork(n, seed)
    return s, c


def as_player(rt, player, code):
    if player == "A":
        rt.execute(code)
    else:
        rt.globals().asPlayer(player, code)


def undo_as(rt, player, redo=False):
    action = "redo" if redo else "undo"
    if player == "A":
        rt.execute("ADUndoManager:%s(nil)" % action)
        return rt.eval("LAST_TEXT")
    rt.execute("ADUndoManager:%s(PLAYERS.%s)" % (action, player))
    return rt.eval("lastSentText()")


def snap(rt):
    return rt.globals().snapshot()


def test_per_player_scenarios():
    s = server_with(30, 11)
    s0 = snap(s)
    as_player(s, "A", "ADGraphManager:moveWayPoint(1, 5, 5, 5, ADGraphManager:getWayPointById(1).flags, false)")
    s1 = snap(s)
    as_player(s, "B", "ADGraphManager:moveWayPoint(2, 6, 6, 6, ADGraphManager:getWayPointById(2).flags, false)")
    # A undoes his older move although B moved afterwards: independent waypoints
    text = undo_as(s, "A")
    assert text.startswith("Undone: waypoint moved"), text
    assert s.eval("ADGraphManager:getWayPointById(1).x") != 5 and s.eval("ADGraphManager:getWayPointById(2).x") == 6
    text = undo_as(s, "B")
    assert text.startswith("Undone: waypoint moved"), text
    assert snap(s) == s0
    # B's undo dropped A's redo, B can redo
    assert undo_as(s, "A", redo=True) == "Nothing to redo"
    assert undo_as(s, "B", redo=True).startswith("Redone: waypoint moved")
    assert snap(s) != s0
    undo_as(s, "B")
    assert snap(s) == s0
    # a redo right after the own undo works
    as_player(s, "A", "ADGraphManager:moveWayPoint(1, 5, 5, 5, ADGraphManager:getWayPointById(1).flags, false)")
    assert snap(s) == s1
    undo_as(s, "A")
    undo_as(s, "A", redo=True)
    assert snap(s) == s1

    # structural edit of A, later edit of B: A has to wait
    s = server_with(30, 12)
    s0 = snap(s)
    as_player(s, "A", "ADGraphManager:createWayPointWithConnections(1, 2, 3, {}, {}, 0, false, false, false, nil, false)")
    as_player(s, "B", "ADGraphManager:moveWayPoint(3, 6, 6, 6, 0, false)")
    text = undo_as(s, "A")
    assert text == "Can't undo yet: Bob changed the route network after your last edit", text
    as_player(s, "C", "ADGraphManager:moveWayPoint(4, 7, 7, 7, 0, false)")
    text = undo_as(s, "A")
    assert text == "Can't undo yet: another player changed the route network after your last edit", text
    undo_as(s, "C")
    undo_as(s, "B")
    text = undo_as(s, "A")
    assert text.startswith("Undone: waypoint created"), text
    assert snap(s) == s0

    # same waypoint: conflict, no reordering
    s = server_with(30, 13)
    as_player(s, "A", "ADGraphManager:moveWayPoint(5, 1, 1, 1, 0, false)")
    as_player(s, "B", "ADGraphManager:toggleConnectionBetween(ADGraphManager:getWayPointById(5), ADGraphManager:getWayPointById(9), false, false, false)")
    assert undo_as(s, "A").startswith("Can't undo yet: Bob")
    # B cannot undo A's edits, he has none
    s.execute("ADUndoManager:undo(PLAYERS.C)")
    assert s.eval("SENT[#SENT].event.textKey") == "AD_undo_empty"


def test_per_player_random(seed):
    rnd = random.Random(seed)
    s, c = server_with(25, seed, client=True)
    for rt in (s, c):
        rt.execute("math.randomseed(%d)" % seed)
    initial = snap(s)
    players = ["A", "B", "C"]
    for _ in range(60):
        if rnd.random() < 0.6:
            res = s.globals().randomOp()
            if res is None or res[0] is None:
                continue
            s_code, c_code = res
            player = rnd.choice(players)
            s.execute("g_time = g_time + 60000")
            as_player(s, player, s_code)
            if c_code == "FROM_SERVER":
                c_code = s.eval("LAST_CLIENT_CODE")
            c.execute(c_code)
        else:
            before = s.eval("#BROADCASTS")
            undo_as(s, rnd.choice(players), redo=rnd.random() < 0.3)
            if s.eval("#BROADCASTS") > before:
                t.sync_client(s, c)
        assert snap(s) == snap(c), "client differs"
        assert s.eval("#ADUndoManager.undoStack") < 100

    # whatever was reordered, undoing every step from the top must lead back to the start
    while s.eval("#ADUndoManager.undoStack") > 0:
        owner = s.eval("ADUndoManager.undoStack[#ADUndoManager.undoStack].owner.id")
        player = {"local": "A", "idB": "B", "idC": "C"}[owner]
        before = s.eval("#ADUndoManager.undoStack")
        text = undo_as(s, player)
        assert s.eval("#ADUndoManager.undoStack") == before - 1, text
        t.sync_client(s, c)
        assert snap(s) == snap(c)
    assert snap(s) == initial, "seed %d: did not get back to the initial network" % seed


def test_nudge_merge():
    s = server_with(20, 3)
    s.execute("F = ADGraphManager:getWayPointById(4).flags; F5 = ADGraphManager:getWayPointById(5).flags")
    s0 = snap(s)
    s.execute("g_time = 1000; ADGraphManager:moveWayPoint(4, 1, 2, 3, F, false)")
    s.execute("g_time = 5000; ADGraphManager:moveWayPoint(4, 2, 2, 3, F, false)")
    s.execute("g_time = 9000; ADGraphManager:moveWayPoint(4, 3, 2, 3, F, false)")
    assert s.eval("#ADUndoManager.undoStack") == 1
    s1 = snap(s)
    s.execute("g_time = 30000; ADGraphManager:moveWayPoint(4, 4, 2, 3, F, false)")
    assert s.eval("#ADUndoManager.undoStack") == 2
    s.execute("ADUndoManager:undo(nil)")
    assert snap(s) == s1
    s.execute("ADUndoManager:undo(nil)")
    assert snap(s) == s0
    # other waypoint or other player: no merge
    s.execute("ADUndoManager:clear(); g_time = 100000; ADGraphManager:moveWayPoint(4, 1, 1, 1, F, false); ADGraphManager:moveWayPoint(5, 1, 1, 1, F5, false)")
    assert s.eval("#ADUndoManager.undoStack") == 2
    as_player(s, "B", "ADGraphManager:moveWayPoint(5, 2, 1, 1, F5, false)")
    assert s.eval("#ADUndoManager.undoStack") == 3
    # moved back to the start: the step disappears
    s = server_with(20, 3)
    s.execute("local wp = ADGraphManager:getWayPointById(4); X, Y, Z, F = wp.x, wp.y, wp.z, wp.flags")
    s.execute("g_time = 1000; ADGraphManager:moveWayPoint(4, 1, 2, 3, F, false); g_time = 2000; ADGraphManager:moveWayPoint(4, X, Y, Z, F, false)")
    assert s.eval("#ADUndoManager.undoStack") == 0


RECORD_LUA = """
MODULE = {isRecording = true}
function MODULE:getUndoState() return {lastWp = self.lastWp, secondLastWp = self.secondLastWp} end
function MODULE:restoreUndoState(state) self.lastWp = state.lastWp; self.secondLastWp = state.secondLastWp end
VEHICLE = {}
GROUP = ADUndoManager:beginGroup(VEHICLE, MODULE)
MODULE.lastWp = ADGraphManager:recordWayPoint(0, 1, 0, false, false, false, 0, 0, false)
function recordTick(x)
    local count = ADUndoManager:getGroupOpCount(GROUP)
    local state = MODULE:getUndoState()
    MODULE.secondLastWp = MODULE.lastWp
    MODULE.lastWp = ADGraphManager:recordWayPoint(x, 1, 0, true, false, false, MODULE.secondLastWp.id, 0, false)
    ADUndoManager:addGroupMark(GROUP, count, state)
end
"""


def test_recording_undo():
    s, c = server_with(20, 5, client=True)
    s0 = snap(s)
    s.execute(RECORD_LUA)
    c.execute("MODULE = {}; ADGraphManager:recordWayPoint(0, 1, 0, false, false, false, 0, 0, false)")
    snaps = {}
    for i in range(1, 16):
        snaps[i - 1] = snap(s)
        s.execute("recordTick(%d)" % (i * 3))  # a point every 3 m
        c.execute("ADGraphManager:recordWayPoint(%d, 1, 0, true, false, false, #ADGraphManager.wayPoints, 0, false)" % (i * 3))
        assert snap(s) == snap(c)
    assert s.eval("#ADUndoManager.undoStack") == 1
    # preview while recording
    s.execute("ADUndoManager:requestPreview(false)")
    assert s.eval("MESSAGES[#MESSAGES]") == "Next undo: the last 4 recorded points", s.eval("MESSAGES[#MESSAGES]")
    # undo while recording: at least 10 m, i.e. 4 points of 3 m
    text = undo_as(s, "A")
    assert text.startswith("Recording: removed the last 4 recorded points"), text
    t.sync_client(s, c)
    assert snap(s) == snaps[11] and snap(c) == snaps[11]
    assert s.eval("MODULE.lastWp.x") == 33
    # the recording continues from there
    s.execute("recordTick(40)")
    c.execute("ADGraphManager:recordWayPoint(40, 1, 0, true, false, false, #ADGraphManager.wayPoints, 0, false)")
    assert snap(s) == snap(c)
    # redo is not possible while recording, other players can not undo through the recording
    assert undo_as(s, "A", redo=True) == "Redo is not possible while recording"
    for presses in range(20):
        text = undo_as(s, "A")
        if text.startswith("Start of the recording reached"):
            break
        t.sync_client(s, c)
        assert snap(s) == snap(c)
    assert text.startswith("Start of the recording reached"), text
    # everything but the first point of the recording is gone
    assert snap(s) == snaps[0] and s.eval("MODULE.lastWp.x") == 0
    # after the recording, one undo removes all of it
    s.execute("ADUndoManager:endGroup(GROUP)")
    undo_as(s, "A")
    assert snap(s) == s0


def test_replace_network():
    s, c = server_with(20, 6, client=True)
    for rt in (s, c):
        rt.execute("ADGraphManager:addGroup('Farm', false); ADGraphManager:setGroupColor('Farm', {1, 0, 0}, false)")
    s.execute("ADUndoManager:clear()")
    s0 = snap(s)
    loaded = """
        local wps = {}
        for i = 1, 5 do wps[i] = ADGraphManager:createNode(i, i * 10, 1, 0, {}, {}, 0) end
        for i = 1, 4 do table.insert(wps[i].out, i + 1); table.insert(wps[i + 1].incoming, i) end
        ADUndoManager:beginStep()
        ADGraphManager:replaceNetwork(wps, {{id = 3, markerIndex = 1, name = 'Silo', group = 'Imported'}}, {All = 1, Imported = 2}, {})
        ADUndoManager:endStep()
    """
    s.execute(loaded)
    c.execute(loaded)
    s1 = snap(s)
    assert snap(c) == s1
    # edits on the loaded network, also of folders
    for code in ["ADGraphManager:moveWayPoint(2, 1, 1, 1, 0, false)", "ADGraphManager:renameGroup('Imported', 'Loaded', false)", "ADGraphManager:addGroup('New', false)", "ADGraphManager:removeWayPoint(4, false)"]:
        s.execute("g_time = g_time + 60000; " + code)
        c.execute(code)
    for _ in range(4):
        s.execute("ADUndoManager:undo(nil)")
        t.sync_client(s, c)
    assert snap(s) == s1 and snap(c) == s1
    s.execute("ADUndoManager:undo(nil)")
    assert s.eval("LAST_TEXT").startswith("Undone: routes loaded"), s.eval("LAST_TEXT")
    t.sync_client(s, c)
    assert snap(s) == s0 and snap(c) == s0
    s.execute("ADUndoManager:redo(nil)")
    t.sync_client(s, c)
    assert snap(s) == s1 and snap(c) == s1
    for _ in range(4):
        s.execute("ADUndoManager:redo(nil)")
        t.sync_client(s, c)
        assert snap(s) == snap(c)
    for _ in range(5):
        s.execute("ADUndoManager:undo(nil)")
        t.sync_client(s, c)
    assert snap(s) == s0 and snap(c) == s0


def test_folders():
    s = server_with(20, 7)
    s.execute("ADGraphManager.mapMarkers = {}; ADGraphManager:createMapMarker(3, 'Silo', false); ADGraphManager:createMapMarker(4, 'Barn', false)")
    s.execute("ADGraphManager:addGroup('Farm/Yard', false)")
    s.execute("ADGraphManager:changeMapMarkerGroup('Farm/Yard', 1, false); ADGraphManager:changeMapMarkerGroup('Farm', 2, false)")
    s.execute("ADGraphManager:setGroupColor('Farm', {0, 1, 0}, false)")
    s.execute("ADUndoManager:clear()")
    s0 = snap(s)
    texts = []
    for code in ["ADGraphManager:renameGroup('Farm', 'Home/Farm', false)", "ADGraphManager:removeGroup('Home/Farm', false)", "ADGraphManager:setGroupColor('Home/Farm/Yard', {0, 0, 1}, false)"]:
        s.execute(code)
    for _ in range(3):
        s.execute("ADUndoManager:undo(nil)")
        texts.append(s.eval("LAST_TEXT"))
    assert snap(s) == s0
    assert texts[0].startswith('Undone: colour of folder "Yard" changed'), texts
    assert texts[1].startswith('Undone: folder "Farm" deleted'), texts
    assert texts[2].startswith('Undone: folder "Home" created, folder "Farm" renamed to "Home/Farm"'), texts
    # markers are back in their folders, the color too
    assert s.eval("ADGraphManager.mapMarkers[1].group") == "Farm/Yard" and s.eval("ADGraphManager.mapMarkers[2].group") == "Farm"
    assert s.eval("ADGraphManager.groupColors.Farm[2]") == 1


def test_notices():
    s = server_with(20, 8)
    s.execute("ADGraphManager:moveWayPoint(4, 1, 1, 1, 0, false)")
    s.execute("ADGraphManager:createWayPointColored(1, 2, 3, {1, 0, 0})")
    assert s.eval("NOTICES[#NOTICES]") == "AD_undo_reason_colors"
    assert s.eval("BROADCAST_NOTICES[#BROADCAST_NOTICES]") == "AD_undo_reason_colors"
    assert s.eval("MESSAGES[#MESSAGES]") == "Undo history cleared: colour selection points used"
    count = s.eval("#NOTICES")
    s.execute("ADGraphManager:createWayPointColored(1, 2, 3, {1, 0, 0})")
    assert s.eval("#NOTICES") == count  # nothing left to clear, no second notice
    # notice through the stream on a client
    c = t.make_runtime(False)
    c.execute("STREAM = {}; STREAM_POS = 1; AutoDriveUndoRedoEvent.newNotice('AD_undo_reason_debug'):writeStream(1, nil); AutoDriveUndoRedoEvent.emptyNew():readStream(1, nil)")
    assert c.eval("MESSAGES[#MESSAGES]") == "Undo history cleared: debug markers changed"


def test_preview_and_state():
    s, c = server_with(20, 9, client=True)
    s.execute("ADGraphManager:removeWayPoint(6, false)")
    c.execute("ADGraphManager:removeWayPoint(6, false)")
    before = snap(s)
    # local, held
    s.execute("ADUndoManager:requestPreview(true)")
    assert snap(s) == before
    assert s.eval("ADUndoManager.highlights.isPreview") and s.eval("ADUndoManager.highlights.endTime") == float("inf")
    assert s.eval("ADUndoManager.highlights.points[1].kind") == 1  # the waypoint would come back
    assert s.eval("MESSAGES[#MESSAGES]") == "Next undo: waypoint deleted"
    s.execute("ADUndoManager:stopPreview()")
    assert s.eval("ADUndoManager.highlights") is None
    # remote: the server answers the requesting client only
    as_player(s, "B", "ADGraphManager:moveWayPoint(2, 9, 9, 9, ADGraphManager:getWayPointById(2).flags, false)")
    c.execute("ADGraphManager:moveWayPoint(2, 9, 9, 9, ADGraphManager:getWayPointById(2).flags, false)")
    s.execute("ADUndoManager:sendPreview(PLAYERS.B)")
    ev = s.globals().serialize(s.eval("SENT[#SENT].event"))
    c.execute("ADUndoManager.previewWanted = {held = false}")
    c.execute("STREAM = {}; STREAM_POS = 1; setmetatable(" + ev + ", AutoDriveUndoRedoEvent_mt):writeStream(1, nil); AutoDriveUndoRedoEvent.emptyNew():readStream(1, nil); assert(STREAM_POS == #STREAM + 1)")
    assert c.eval("MESSAGES[#MESSAGES]") == "Next undo: waypoint moved", c.eval("MESSAGES[#MESSAGES]")
    assert c.eval("ADUndoManager.highlights.points[1].fromX") is not None  # line from the old position
    assert c.eval("ADUndoManager.highlights.points[1].x") != 9
    # availability for the HUD buttons
    assert tuple(s.eval("{ADUndoManager:getClientAvailability()}").values()) == (True, False)
    s.execute("ADUndoManager:sendState(PLAYERS.C)")
    ev = s.globals().serialize(s.eval("SENT[#SENT].event"))
    c.execute("STREAM = {}; STREAM_POS = 1; setmetatable(" + ev + ", AutoDriveUndoRedoEvent_mt):writeStream(1, nil); AutoDriveUndoRedoEvent.emptyNew():readStream(1, nil)")
    assert tuple(c.eval("{ADUndoManager:getClientAvailability()}").values()) == (False, False)
    s.execute("ADUndoManager:undo(PLAYERS.B); ADUndoManager:sendState(PLAYERS.B)")
    assert s.eval("SENT[#SENT].event.canUndo") is False and s.eval("SENT[#SENT].event.canRedo") is True


def test_pointer():
    s = server_with(20, 10)
    s.execute("getWorldTranslation = function() return VX, 0, VZ end; VEHICLE = {components = {{node = 1}}}")
    s.execute("ADGraphManager:moveWayPoint(3, 500, 1, 500, 0, false); ADUndoManager:undo(nil)")
    # far away: pointer
    s.execute("VX, VZ = 2000, 2000; g_time = 10; ADUndoManager:drawHighlights(VEHICLE)")
    assert s.eval("DRAWN.arrows") == 1
    # close: no pointer
    s.execute("local p = ADUndoManager.highlights.points[1]; VX, VZ = p.x + 5, p.z; ADUndoManager:drawHighlights(VEHICLE)")
    assert s.eval("DRAWN.arrows") == 1


def test_actor_hooks():
    s = t.make_runtime(True)
    s.execute(PLAYERS_LUA)
    s.execute("""
        AutoDriveMoveWayPointEvent = {run = function(self, connection) SEEN = ADUndoManager.actorConnection; if self.fail then error('boom') end end}
        ADUndoManager.installActorHooks()
        AutoDriveMoveWayPointEvent.run({}, PLAYERS.B)
        assert(SEEN == PLAYERS.B and ADUndoManager.actorConnection == nil)
        AutoDriveMoveWayPointEvent.run({}, {getIsServer = function() return true end})
        assert(SEEN == nil)
        local ok = pcall(AutoDriveMoveWayPointEvent.run, {fail = true}, PLAYERS.B)
        assert(not ok and ADUndoManager.actorConnection == nil)
    """)
    # the own client connection of single player / host counts as local
    s.globals().setupNetwork(10, 1)
    s.execute("""
        g_currentMission.playerUserId = 7
        g_currentMission.userManager.getUserIdByConnection = function(self, c) return c.userId end
        local hostConnection = {userId = 7, user = {uniqueUserId = 'hostUnique', nickname = 'Host'}, getIsServer = function() return false end}
        assert(ADUndoManager.getOwnerByConnection(hostConnection).id == 'local')
        assert(ADUndoManager.getOwnerByConnection({streamId = 0, getIsServer = function() return false end}).id == 'local')
        local other = {userId = 8, user = {uniqueUserId = 'u8', nickname = 'Eve'}}
        assert(ADUndoManager.getOwnerByConnection(other).id == 'u8')
        -- a recording started through the own connection can be undone by the local player
        ADUndoManager.actorConnection = hostConnection
        local group = ADUndoManager:beginGroup({}, nil)
        ADUndoManager.actorConnection = nil
        ADGraphManager:recordWayPoint(1, 2, 3, false, false, false, 0, 0, false)
        ADUndoManager:endGroup(group)
        ADUndoManager:undo(nil)
        assert(FEEDBACK[#FEEDBACK] == 'AD_undo_done', FEEDBACK[#FEEDBACK])
    """)


if __name__ == "__main__":
    test_per_player_scenarios()
    for seed in range(1, 41):
        test_per_player_random(seed)
    test_nudge_merge()
    test_recording_undo()
    test_replace_network()
    test_folders()
    test_notices()
    test_preview_and_state()
    test_pointer()
    test_actor_hooks()
    print("OK: per player (scenarios + 40 random runs), nudge merge, recording undo, routes import, folders, notices, preview, HUD state, pointer, actor hooks")
