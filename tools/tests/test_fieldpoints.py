import os
import run_undo_test as t

s = t.make_runtime(True)
for f in ["DeleteWayPointsEvent.lua", "CreateWayPointEvent.lua"]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", f)))
s.execute("""
    AutoDrive.FLAG_FIELD_POINT = 8
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    -- graph events are applied locally right away, like the game server does
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        if sendLocal then ev:run(LOCAL_CONNECTION) end
    end
""")
s.globals().setupNetwork(15, 4)
s.execute("ADUndoManager:clear()")
generate = """
    ADUndoManager:beginStep()
    ADGraphManager:removeFieldWaypoints(3)
    local first = #ADGraphManager.wayPoints + 1
    for i = 0, %d do
        local out, incoming = {}, {}
        if i > 0 then incoming = {first + i - 1} end
        if i < %d then out = {first + i + 1} end
        ADGraphManager:createWayPointWithConnections(%d + i * 10, 1, 50, out, incoming, AutoDrive.FLAG_FIELD_POINT, false, false, false, 3)
    end
    ADUndoManager:endStep()
"""
before = s.globals().snapshot()
s.execute(generate % (5, 5, 100))
gen1 = s.globals().snapshot()
assert s.eval("#ADUndoManager.undoStack") == 1, s.eval("#ADUndoManager.undoStack")
assert "f3" in gen1
s.execute(generate % (7, 7, 300))
gen2 = s.globals().snapshot()
assert s.eval("#ADUndoManager.undoStack") == 2
s.execute("ADUndoManager:undo(nil)")
assert s.eval("LAST_TEXT").startswith("Undone: 8 waypoints created, 6 waypoints deleted"), s.eval("LAST_TEXT")
assert s.globals().snapshot() == gen1
s.execute("ADUndoManager:undo(nil)")
assert s.globals().snapshot() == before
s.execute("ADUndoManager:redo(nil); ADUndoManager:redo(nil)")
assert s.globals().snapshot() == gen2
print("OK: field point regeneration is one undo step, field ids restored")
