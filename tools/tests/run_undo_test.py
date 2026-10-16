import os
import sys
import xml.etree.ElementTree as ET

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
# the mod is two folders up: <repo>/tools/tests
MOD = os.path.abspath(os.path.join(HERE, "..", ".."))
TEXTS = {e.get("name"): e.get("text") for e in ET.parse(os.path.join(MOD, "translations", "translation_en.xml")).getroot().iter("text")}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def make_runtime(is_server):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(read(os.path.join(HERE, "stubs.lua")))
    if is_server:
        lua.execute("""BROADCAST_POINTS = {}; BROADCAST_NOTICES = {}
        g_server = {broadcastEvent = function(self, ev, sendLocal)
            if ev.eventType == 3 then
                table.insert(BROADCASTS, ev.instructions); table.insert(BROADCAST_POINTS, ev.points)
            elseif ev.eventType == 9 then
                table.insert(BROADCAST_NOTICES, ev.textKey)
            end
        end}""")
    else:
        lua.execute("g_server = nil")
    lua.execute("g_client = nil")
    lua.execute(read(os.path.join(MOD, "scripts", "Manager", "GraphManager.lua")))
    lua.execute(read(os.path.join(MOD, "scripts", "Manager", "UndoManager.lua")))
    lua.execute(read(os.path.join(MOD, "scripts", "Events", "Graph", "UndoRedoEvent.lua")))
    texts = lua.eval("{}")
    for k, v in TEXTS.items():
        texts[k] = v
    lua.globals().TEXTS = texts
    lua.execute("g_i18n = {getText = function(self, key) local t = TEXTS[key]; if t == nil then error('missing l10n ' .. tostring(key)) end; return t end}")
    lua.execute("""NOTICES = {}
    local originalShowFeedback = ADUndoManager.showFeedback
    ADUndoManager.showFeedback = function(key, u, r, parts)
        table.insert(FEEDBACK, key)
        LAST_TEXT = ADUndoManager.getFeedbackText(key, u, r, parts)
        originalShowFeedback(key, u, r, parts)
    end
    local originalShowNotice = ADUndoManager.showNotice
    ADUndoManager.showNotice = function(reason)
        table.insert(NOTICES, reason)
        originalShowNotice(reason)
    end""")
    lua.execute(read(os.path.join(HERE, "testlib.lua")))
    lua.execute(read(os.path.join(HERE, "gen.lua")))
    return lua


def sync_client(server, client):
    """the last apply event of the server, through the stream, applied on the client"""
    ins = server.globals().serialize(server.eval("BROADCASTS[#BROADCASTS]"))
    points = server.globals().serialize(server.eval("BROADCAST_POINTS[#BROADCAST_POINTS]"))
    client.execute("STREAM = {}; STREAM_POS = 1; AutoDriveUndoRedoEvent.newApply(" + ins + ", " + points + "):writeStream(1, nil)")
    client.execute("local ev = AutoDriveUndoRedoEvent.emptyNew(); ev:readStream(1, nil); assert(STREAM_POS == #STREAM + 1, 'stream not fully read')")


def run(seed, n_wp, n_ops):
    server = make_runtime(True)
    client = make_runtime(False)
    for rt in (server, client):
        rt.globals().setupNetwork(n_wp, seed)
        rt.execute("math.randomseed(%d)" % (seed * 7 + 1))
    assert server.globals().snapshot() == client.globals().snapshot()

    snaps = [server.globals().snapshot()]
    ops = []
    while len(ops) < n_ops:
        res = server.globals().randomOp()
        if res is None or res[0] is None:
            continue
        s_code, c_code = res
        # moves of the same waypoint in a row would be merged, keep them apart in time
        server.execute("g_time = g_time + 60000")
        server.execute(s_code)
        if c_code == "FROM_SERVER":
            c_code = server.eval("LAST_CLIENT_CODE")
        client.execute(c_code)
        ss, cs = server.globals().snapshot(), client.globals().snapshot()
        if ss != cs:
            raise AssertionError("seed %d: client differs after op %d: %s" % (seed, len(ops), s_code))
        ops.append(s_code)
        snaps.append(ss)

    undo_count = server.eval("#ADUndoManager.undoStack")
    steps = [i for i in range(1, len(snaps)) if snaps[i] != snaps[i - 1]]
    expected = min(len(steps), 100)
    if undo_count != expected:
        raise AssertionError("seed %d: %d undo steps, expected %d" % (seed, undo_count, expected))

    for k, i in enumerate(reversed(steps[-expected:])):
        server.execute("ADUndoManager:undo(nil)")
        sync_client(server, client)
        ss = server.globals().snapshot()
        if ss != snaps[i - 1]:
            import difflib
            print("\n".join(difflib.unified_diff(snaps[i - 1].split("\n"), ss.split("\n"), "expected", "actual", lineterm="", n=0)))
            raise AssertionError("seed %d: undo %d (op %d: %s) did not restore state" % (seed, k + 1, i - 1, ops[i - 1]))
        if client.globals().snapshot() != ss:
            raise AssertionError("seed %d: client differs after undo %d" % (seed, k + 1))
    server.execute("ADUndoManager:undo(nil)")
    assert server.eval("FEEDBACK[#FEEDBACK]") == "AD_undo_empty"

    for k, i in enumerate(steps[-expected:]):
        server.execute("ADUndoManager:redo(nil)")
        sync_client(server, client)
        ss = server.globals().snapshot()
        if ss != snaps[i]:
            raise AssertionError("seed %d: redo %d (op %d: %s) did not restore state" % (seed, k + 1, i - 1, ops[i - 1]))
        if client.globals().snapshot() != ss:
            raise AssertionError("seed %d: client differs after redo %d" % (seed, k + 1))
    server.execute("ADUndoManager:redo(nil)")
    assert server.eval("FEEDBACK[#FEEDBACK]") == "AD_redo_empty"

    server.execute("ADUndoManager:undo(nil)")
    server.execute("ADGraphManager:createWayPointWithConnections(1, 2, 3, {}, {}, 0, false, false, false, nil, false)")
    assert server.eval("#ADUndoManager:getRedoStack(ADUndoManager.getLocalOwner())") == 0
    return len(ops)


if __name__ == "__main__":
    total = 0
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    for seed in range(1, seeds + 1):
        total += run(seed, n_wp=12 + seed % 40, n_ops=30 + seed % 60)
    print("OK: %d seeds, %d random edits undone and redone" % (seeds, total))
