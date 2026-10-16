"""Field points (Ctrl+Shift+F): removing the old and adding the new points of a field is one undo step,
also when the game runs network events a frame later; the clients get one event and the same network."""
import os
import run_undo_test as t

s = t.make_runtime(True)
for f in ["DeleteWayPointsEvent.lua", "CreateWayPointEvent.lua", "FieldPointsEvent.lua"]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", f)))
s.execute("""
    AutoDrive.FLAG_FIELD_POINT = 8
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    -- like the game: events sent to the own machine run later, not inside the caller
    DEFERRED = {}
    TO_CLIENTS = {}
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        table.insert(TO_CLIENTS, ev)
        if sendLocal then table.insert(DEFERRED, ev) end
    end
    function runDeferred()
        local events = DEFERRED
        DEFERRED = {}
        for _, ev in ipairs(events) do ev:run(LOCAL_CONNECTION) end
    end
""")
s.globals().setupNetwork(15, 4)
s.execute("ADUndoManager:clear()")
generate = """
    local points = {}
    for i = 0, %d do table.insert(points, {x = %d + i * 10, y = 1, z = 50 + (i %% 2) * 7}) end
    TO_CLIENTS = {}
    ADGraphManager:replaceFieldWaypoints(3, points)
    runDeferred()
"""
before = s.globals().snapshot()
s.execute(generate % (5, 100))
gen1 = s.globals().snapshot()
assert s.eval("#ADUndoManager.undoStack") == 1, s.eval("#ADUndoManager.undoStack")
assert s.eval("#TO_CLIENTS") == 1 and s.eval("TO_CLIENTS[1].fieldID") == 3
assert "f3" in gen1
# closed two-way loop
s.execute("FIRST = #ADGraphManager.wayPoints - 5")
for i in range(6):
    wp = "ADGraphManager.wayPoints[FIRST + %d]" % i
    prev_id, next_id = (i - 1) % 6, (i + 1) % 6
    assert sorted(s.eval("{%s.out[1], %s.out[2]}" % (wp, wp)).values()) == sorted([s.eval("FIRST") + prev_id, s.eval("FIRST") + next_id])
    assert sorted(s.eval("{%s.incoming[1], %s.incoming[2]}" % (wp, wp)).values()) == sorted([s.eval("FIRST") + prev_id, s.eval("FIRST") + next_id])

# a client applies the event and ends up with the same network
client = t.make_runtime(False)
client.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", "FieldPointsEvent.lua")))
client.execute("AutoDrive.FLAG_FIELD_POINT = 8")
client.globals().setupNetwork(15, 4)
n = s.eval("#TO_CLIENTS[1].points")
pts = ", ".join("{x = %r, y = %r, z = %r}" % tuple(s.eval("TO_CLIENTS[1].points[%d].%s" % (i, k)) for k in "xyz") for i in range(1, n + 1))
client.execute("AutoDriveFieldPointsEvent.new(3, {%s}):run(nil)" % pts)
assert client.globals().snapshot() == gen1

# regenerating the same field replaces its points, again one step; the loop is numbered after the removal
s.execute(generate % (7, 300))
gen2 = s.globals().snapshot()
assert s.eval("#ADUndoManager.undoStack") == 2
s.execute("FIRST = #ADGraphManager.wayPoints - 7")
assert s.eval("ADGraphManager.wayPoints[FIRST].fieldID") == 3
assert s.eval("#ADGraphManager.wayPoints") == s.eval("FIRST + 7")
s.execute("ADUndoManager:undo(nil)")
assert s.eval("LAST_TEXT").startswith("Undone: 8 waypoints created, 6 waypoints deleted"), s.eval("LAST_TEXT")
assert s.globals().snapshot() == gen1
s.execute("ADUndoManager:undo(nil)")
assert s.globals().snapshot() == before
s.execute("ADUndoManager:redo(nil); ADUndoManager:redo(nil)")
assert s.globals().snapshot() == gen2
print("OK: field points are one undo step and one event, also with events running a frame later; regenerating renumbers correctly")
