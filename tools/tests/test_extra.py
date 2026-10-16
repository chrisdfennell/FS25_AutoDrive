"""Tests for step descriptions, highlights and multi marker deletion, on top of run_undo_test."""
import os
import xml.etree.ElementTree as ET

import run_undo_test as t

EN_XML = os.path.join(t.MOD, "translations", "translation_en.xml")
TEXTS = {e.get("name"): e.get("text") for e in ET.parse(EN_XML).getroot().iter("text")}


def setup(rt):
    rt.execute("g_time = 0; DRAWN = {spheres = 0, lines = 0}")
    rt.execute("ADDrawingManager = {addSphereTask = function() DRAWN.spheres = DRAWN.spheres + 1 end, addLineTask = function() DRAWN.lines = DRAWN.lines + 1 end, addSmallSphereTask = function() end, addArrowTask = function() DRAWN.arrows = (DRAWN.arrows or 0) + 1 end, arrows = {position = {start = 1}}}")


def server_with(n, seed):
    s = t.make_runtime(True)
    setup(s)
    s.globals().setupNetwork(n, seed)
    return s


def undo_text(s, code):
    s.execute(code)
    s.execute("ADUndoManager:undo(nil)")
    text = s.eval("LAST_TEXT")
    s.execute("ADUndoManager:redo(nil)")
    redo = s.eval("LAST_TEXT")
    s.execute("ADUndoManager:undo(nil)")
    return text, redo


def test_descriptions():
    s = server_with(30, 3)
    s.execute("ADGraphManager.mapMarkers = {}")
    cases = [
        ("ADGraphManager:createWayPointWithConnections(1, 2, 3, {31}, {5}, 0, true, false, false, nil, false)", "Undone: waypoint created (0 more to undo, 1 to redo)"),
        ("ADUndoManager:beginStep() ADGraphManager:removeWayPoint(9, false) ADGraphManager:removeWayPoint(4, false) ADUndoManager:endStep()", "Undone: 2 waypoints deleted ("),
        ("ADGraphManager:moveWayPoint(3, 5, 6, 7, ADGraphManager:getWayPointById(3).flags, false)", "Undone: waypoint moved ("),
        ("local wp = ADGraphManager:getWayPointById(3); ADGraphManager:moveWayPoint(3, wp.x, wp.y, wp.z, 1 - wp.flags, false)", "Undone: side road toggled ("),
        ("ADGraphManager:toggleConnectionBetween(ADGraphManager:getWayPointById(1), ADGraphManager:getWayPointById(20), false, true, false)", "Undone: connection changed ("),
        ("ADGraphManager:createMapMarker(7, 'Farm 100%', false)", 'Undone: target "Farm 100%" created ('),
        ("ADGraphManager:createSplineConnection(1, {{x=1,y=5,z=1},{x=2,y=5,z=2}}, 9, false, false)", "Undone: 2 waypoints created ("),
    ]
    for code, expected in cases:
        text, redo = undo_text(s, code)
        assert text.startswith(expected), (code, text)
        assert redo.startswith("Redone: " + expected[len("Undone: "):].split(" (")[0]), (code, redo)
        print("  ", text, "|", redo)

    s.execute("ADGraphManager:createMapMarker(7, 'Silo', false)")
    for code, expected in [
        ("ADGraphManager:renameMapMarker('Big Silo', 1, false)", 'Undone: target "Silo" renamed to "Big Silo" ('),
        ("ADGraphManager:changeMapMarkerGroup('G1', 1, false)", 'Undone: target "Silo" moved to folder "G1" ('),
        ("ADGraphManager:removeWayPoint(7, false)", 'Undone: waypoint deleted, target "Silo" deleted ('),
    ]:
        text, _ = undo_text(s, code)
        assert text.startswith(expected), (code, text)
        print("  ", text)

    s.execute("ADUndoManager:clear(); ADUndoManager:undo(nil)")
    assert s.eval("LAST_TEXT") == "Nothing to undo", s.eval("LAST_TEXT")


def test_feedback_event():
    c = t.make_runtime(False)
    setup(c)
    c.execute("""
        STREAM = {}; STREAM_POS = 1
        AutoDriveUndoRedoEvent.newFeedback("AD_undo_done", 4, 2, {{key = "AD_undoStep_wpDeleted", args = {3}}, {key = "AD_undoStep_markerDeleted_1", args = {"Farm"}}}):writeStream(1, nil)
        local ev = AutoDriveUndoRedoEvent.emptyNew(); ev:readStream(1, nil)
        assert(STREAM_POS == #STREAM + 1, 'stream not fully read')
    """)
    assert c.eval("LAST_TEXT") == 'Undone: 3 waypoints deleted, target "Farm" deleted (4 more to undo, 2 to redo)', c.eval("LAST_TEXT")


def test_highlights():
    s = server_with(40, 8)
    # recorded drive of 300 points -> sampled to the maximum
    s.execute("""
        local group = ADUndoManager:beginGroup({})
        local wp = ADGraphManager:recordWayPoint(1, 2, 3, false, false, false, 0, 0, false)
        for i = 1, 299 do wp = ADGraphManager:recordWayPoint(i, 2, 3, true, false, false, wp.id, 0, false) end
        ADUndoManager:endGroup(group)
        ADUndoManager:undo(nil)
    """)
    assert s.eval("#ADUndoManager.highlights.points") == 200, s.eval("#ADUndoManager.highlights.points")
    assert s.eval("ADUndoManager.highlights.points[1].kind") == 3  # removed
    s.execute("g_time = 1000; ADUndoManager:drawHighlights()")
    assert s.eval("DRAWN.spheres") == 200 and s.eval("DRAWN.lines") == 200
    s.execute("g_time = 5000; ADUndoManager:drawHighlights()")
    assert s.eval("ADUndoManager.highlights") is None

    # undo of a connection toggle highlights both waypoints as changed, redo of delete: removed + changed neighbours
    s.execute("""
        g_time = 0
        ADGraphManager:toggleConnectionBetween(ADGraphManager:getWayPointById(1), ADGraphManager:getWayPointById(2), false, false, false)
        ADUndoManager:undo(nil)
    """)
    kinds = sorted(s.eval("ADUndoManager.highlights.points[%d].kind" % i) for i in range(1, s.eval("#ADUndoManager.highlights.points") + 1))
    assert kinds == [2, 2], kinds
    s.execute("ADGraphManager:removeWayPoint(5, false); ADUndoManager:undo(nil)")
    assert s.eval("ADUndoManager.highlights.points[1].kind") == 1  # restored waypoint is green
    s.execute("ADUndoManager:redo(nil)")
    kinds = [s.eval("ADUndoManager.highlights.points[%d].kind" % i) for i in range(1, s.eval("#ADUndoManager.highlights.points") + 1)]
    assert 3 in kinds, kinds


def test_multi_marker_delete():
    s = server_with(20, 4)
    s.execute("""
        ADGraphManager.mapMarkers = {}
        ADGraphManager:createMapMarker(5, 'A', false)
        ADGraphManager:createMapMarker(9, 'B', false)
        ADGraphManager:createMapMarker(5, 'C', false)
        ADGraphManager:createMapMarker(6, 'D', false)
        ADUndoManager:clear()
    """)
    before = s.globals().snapshot()
    s.execute("ADGraphManager:removeWayPoint(5, false)")
    names = [s.eval("ADGraphManager.mapMarkers[%d].name .. ':' .. ADGraphManager.mapMarkers[%d].id" % (i, i)) for i in range(1, s.eval("#ADGraphManager.mapMarkers") + 1)]
    assert names == ["B:8", "D:5"], names
    s.execute("ADUndoManager:undo(nil)")
    assert s.globals().snapshot() == before
    assert s.eval("LAST_TEXT").startswith("Undone: waypoint deleted, 2 targets deleted"), s.eval("LAST_TEXT")


if __name__ == "__main__":
    test_descriptions()
    test_feedback_event()
    test_highlights()
    test_multi_marker_delete()
    print("OK: descriptions, feedback event, highlights, multi marker delete")
