"""Tidy-up tools: geometry, the route search between two waypoints, and one undo step per tidy-up."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute(t.read(os.path.join(t.MOD, "scripts", "Utils", "TidyTools.lua")))
s.execute(t.read(os.path.join(t.MOD, "scripts", "Events", "Graph", "MoveWayPointsEvent.lua")))
s.execute("""
    LOCAL_CONNECTION = {getIsServer = function() return true end}
    local captureUndo = g_server.broadcastEvent
    g_server.broadcastEvent = function(self, ev, sendLocal)
        if ev.eventType ~= nil then return captureUndo(self, ev, sendLocal) end
        if sendLocal then ev:run(LOCAL_CONNECTION) end
    end
    function chainNetwork(points)
        ADGraphManager.wayPoints = {}
        ADGraphManager.mapMarkers = {}
        for i, p in ipairs(points) do
            local out, incoming = {}, {}
            if i < #points then out = {i + 1} end
            if i > 1 then incoming = {i - 1} end
            ADGraphManager.wayPoints[i] = {id = i, x = p[1], y = 0, z = p[2], out = out, incoming = incoming, flags = 0}
        end
    end
    function pos(i) local wp = ADGraphManager.wayPoints[i]; return wp.x, wp.z end
""")

def positions(n):
    return [tuple(round(v, 4) for v in s.eval("{pos(%d)}" % i).values()) for i in range(1, n + 1)]

s.globals().setupNetwork(5, 1)
# a zig-zag line from (0,0) to (40,0) with uneven spacing
s.execute("chainNetwork({{0,0},{3,2},{15,-3},{22,1},{40,0}})")
s.execute("ADUndoManager:clear()")
before = s.globals().snapshot()

# straighten: on the line, equal distances, ends fixed
s.execute("MOVES = ADTidyTools.getMoves(ADTidyTools.STRAIGHTEN, {1,2,3,4,5}, nil); ADGraphManager:moveWayPoints(MOVES)")
assert positions(5) == [(0, 0), (10, 0), (20, 0), (30, 0), (40, 0)], positions(5)
assert s.eval("#ADUndoManager.undoStack") == 1
s.execute("ADUndoManager:undo(nil)")
assert s.globals().snapshot() == before
assert "3 waypoints moved" in s.eval("LAST_TEXT"), s.eval("LAST_TEXT")
s.execute("ADUndoManager:redo(nil)")
assert positions(5)[2] == (20, 0)
s.execute("ADUndoManager:undo(nil)")

# even spacing: same path, equal steps along it
s.execute("chainNetwork({{0,0},{1,0},{2,0},{10,0},{30,0}})")
s.execute("ADGraphManager:moveWayPoints(ADTidyTools.getMoves(ADTidyTools.EVEN, {1,2,3,4,5}, nil))")
assert positions(5) == [(0, 0), (7.5, 0), (15, 0), (22.5, 0), (30, 0)], positions(5)
# even spacing keeps the corner of an L shaped route on the path
s.execute("chainNetwork({{0,0},{1,0},{10,0},{10,5},{10,10}})")
s.execute("ADGraphManager:moveWayPoints(ADTidyTools.getMoves(ADTidyTools.EVEN, {1,2,3,4,5}, nil))")
assert positions(5) == [(0, 0), (5, 0), (10, 0), (10, 5), (10, 10)], positions(5)

# smooth: a single spike gets flatter, ends fixed
s.execute("chainNetwork({{0,0},{10,0},{20,8},{30,0},{40,0}})")
s.execute("ADGraphManager:moveWayPoints(ADTidyTools.getMoves(ADTidyTools.SMOOTH, {1,2,3,4,5}, nil))")
p = positions(5)
assert p[0] == (0, 0) and p[4] == (40, 0)
assert 0 < p[2][1] < 4, p

# heights follow the given height function
s.execute("chainNetwork({{0,0},{3,2},{15,-3},{40,0}})")
s.execute("ADGraphManager:moveWayPoints(ADTidyTools.getMoves(ADTidyTools.STRAIGHTEN, {1,2,3,4}, function(x, y, z) return x / 10 end))")
assert abs(s.eval("ADGraphManager.wayPoints[2].y") - 40 / 3 / 10) < 1e-6

# ground height: a surface near the old height (bridge) wins, otherwise the ground below
s.execute("""
    BRIDGE_AT = 10
    function AutoDrive:getTerrainHeightAtWorldPos(x, z, startingHeight)
        self.raycastHeight = nil
        if startingHeight ~= nil and math.abs(startingHeight - BRIDGE_AT) < 2 then self.raycastHeight = BRIDGE_AT end
        return self.raycastHeight or startingHeight or 1
    end
""")
assert s.eval("ADTidyTools.groundHeight(0, 10.5, 0)") == 10   # on the bridge
assert s.eval("ADTidyTools.groundHeight(0, 40, 0)") == 1      # was high up, nothing there: ground

# nothing to do: already straight
s.execute("chainNetwork({{0,0},{10,0},{20,0}})")
assert s.eval("#ADTidyTools.getMoves(ADTidyTools.STRAIGHTEN, {1,2,3}, nil)") == 0
# too short
assert s.eval("ADTidyTools.getMoves(ADTidyTools.STRAIGHTEN, {1,2}, nil)") is None

# route search: shortest chain over connections in both directions, also against one-way direction
s.execute("""
    chainNetwork({{0,0},{10,0},{20,0},{30,0},{40,0},{50,0}})
    -- shortcut 2 -> 5 (one-way), searched from 6 back to 1 against the direction
    table.insert(ADGraphManager.wayPoints[2].out, 5); table.insert(ADGraphManager.wayPoints[5].incoming, 2)
""")
chain = list(s.eval("ADTidyTools.findChain(6, 1)").values())
assert chain == [6, 5, 2, 1], chain
s.execute("ADGraphManager.wayPoints[7] = {id = 7, x = 99, y = 0, z = 99, out = {}, incoming = {}, flags = 0}")
assert s.eval("ADTidyTools.findChain(1, 7)") is None

# the event: a client sends the moves, the server applies them as one step and broadcasts
s.execute("chainNetwork({{0,0},{3,2},{15,-3},{22,1},{40,0}})")
s.execute("""
    STREAM = {}
    streamWriteUIntN = function(id, v) table.insert(STREAM, v) end
    streamWriteFloat32 = function(id, v) table.insert(STREAM, v) end
    local pos = 0
    streamReadUIntN = function() pos = pos + 1; return STREAM[pos] end
    streamReadFloat32 = streamReadUIntN
    local ev = AutoDriveMoveWayPointsEvent.new(ADTidyTools.getMoves(ADTidyTools.STRAIGHTEN, {1,2,3,4,5}, nil))
    ev:writeStream(1, nil)
    local received = AutoDriveMoveWayPointsEvent.emptyNew()
    UNDO_BEFORE = #ADUndoManager.undoStack
    received:readStream(1, {getIsServer = function() return false end})
""")
assert positions(5)[1] == (10, 0)
assert s.eval("#ADUndoManager.undoStack - UNDO_BEFORE") == 1
print("OK: tidy-up tools (straighten, even spacing, smooth, heights, route search, event) are one undo step each")
