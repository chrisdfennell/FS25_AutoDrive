import run_undo_test as t
import test_new as n

s, c = n.server_with(20, 21, client=True)
# single player: no log lines
s.execute("ADGraphManager:moveWayPoint(3, 1, 1, 1, 0, false); ADUndoManager:undo(nil)")
assert s.eval("#LOGS") == 0, s.eval("LOGS[1]")

# multiplayer
for rt in (s, c):
    rt.execute("g_currentMission.missionDynamicInfo = {isMultiplayer = true}; g_currentMission.playerUserId = 1")
s.execute("g_currentMission.userManager.getUserIdByConnection = function(self, conn) return conn.userId end; PLAYERS.B.userId = 2; PLAYERS.B.streamId = 5")
n.as_player(s, "A", "ADGraphManager:createWayPointWithConnections(1, 2, 3, {}, {}, 0, false, false, false, nil, false)")
n.as_player(s, "B", "ADGraphManager:moveWayPoint(4, 6, 6, 6, 0, false)")
n.undo_as(s, "A")
n.undo_as(s, "B")
n.undo_as(s, "A")
s.execute("ADUndoManager:beginGroup({}, nil)")
# a name with format characters must not break the log
s.execute("PLAYERS.C.user.nickname = '100%% %s'")
n.undo_as(s, "C")
for line in s.eval("LOGS").values():
    print("server:", line)
# client side
c.execute("ADUndoManager:setClientAvailability(true, false); ADUndoManager.showFeedback('AD_undo_empty', 0, 0, {})")
for line in c.eval("LOGS").values():
    print("client:", line)
print("OK")
