"""A client's change on a dedicated server is undone by that client, also when the game runs the server's own
copy of an event later (broadcastEvent with sendLocal is delivered after the event that sent it is done)."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2}, addMessage = function() end}
    SENT = {}
    local function connection(id, name)
        return {user = {uniqueUserId = id, nickname = name}, getIsServer = function() return false end,
            sendEvent = function(self, ev) table.insert(SENT, {to = id, event = ev}) end}
    end
    BOB = connection("idB", "Bob")
    -- the game: copies for the clients go out, the server's own copy runs later (flush)
    local captureUndo = g_server.broadcastEvent
    TO_CLIENTS, LOCAL_QUEUE = {}, {}
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil and ev.instructions ~= nil then return captureUndo(self, ev, sendLocal) end
        table.insert(TO_CLIENTS, ev)
        if sendLocal then table.insert(LOCAL_QUEUE, ev) end
    end
    SERVER_SIDE = {getIsServer = function() return true end}
    function flush()
        local queue = LOCAL_QUEUE
        LOCAL_QUEUE = {}
        for _, ev in ipairs(queue) do ev:run(SERVER_SIDE) end
    end
    function lastSentText()
        local ev = SENT[#SENT].event
        return ADUndoManager.getFeedbackText(ev.textKey, ev.undoCount, ev.redoCount, ev.parts)
    end
""")
for f in ["MoveWayPointsEvent.lua", "MoveWayPointEvent.lua", "SetConnectionEvent.lua", "DeleteWayPointsEvent.lua"]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", f)))
# the hooks are installed when UndoManager.lua is loaded, here the events come later
s.execute("ADUndoManager.installActorHooks()")
s.globals().setupNetwork(10, 3)
s.execute("ADUndoManager:clear(); BEFORE = snapshot()")


def from_bob(code):
    # Bob's game sends the event, the server receives it from Bob's connection
    s.execute("local ev = %s; ev:run(BOB); flush()" % code)


# tidy (several waypoints) from Bob
from_bob("AutoDriveMoveWayPointsEvent.new({{id = 1, x = 5, y = 10, z = 5}, {id = 2, x = 6, y = 10, z = 6, flags = 2 ^ 18}})")
assert s.eval("ADGraphManager.wayPoints[1].x") == 5 and s.eval("ADGraphManager.wayPoints[2].flags") == 2 ** 18
assert s.eval("#ADUndoManager.undoStack") == 1
assert s.eval("ADUndoManager.undoStack[1].owner.id") == "idB", s.eval("ADUndoManager.undoStack[1].owner.id")
# the other clients still get it, and the server's copy did not run a second time
assert s.eval("#TO_CLIENTS") == 1 and s.eval("#LOCAL_QUEUE") == 0
# a single move, a connection and a delete from Bob
from_bob("AutoDriveMoveWayPointEvent.new(3, 1, 10, 1, 0)")
from_bob("AutoDriveSetConnectionEvent.new(ADGraphManager.wayPoints[4], ADGraphManager.wayPoints[5], 3)")
from_bob("AutoDriveDeleteWayPointsEvent.new({6})")
assert s.eval("#ADUndoManager.undoStack") == 4
assert all(s.eval("ADUndoManager.undoStack[%d].owner.id" % i) == "idB" for i in range(1, 5))

# Bob undoes all four
for _ in range(4):
    s.execute("ADUndoManager:undo(BOB)")
    assert s.eval("lastSentText()").startswith("Undone"), s.eval("lastSentText()")
assert s.globals().snapshot() == s.eval("BEFORE")

# the server's own changes (host) are still the host's
s.execute("ADGraphManager:moveWayPoints({{id = 1, x = 7, y = 10, z = 7}}); flush()")
assert s.eval("ADUndoManager.undoStack[#ADUndoManager.undoStack].owner.id") == s.eval("ADUndoManager.LOCAL_OWNER_ID")
# broadcastEvent is back to normal after each event
assert s.eval("rawget(g_server, 'broadcastEvent') ~= nil") and s.eval("#LOCAL_QUEUE") == 0
print("OK: a client's changes on a dedicated server are its own undo steps, also when the server's copy of an event runs later")
