"""Route check: every kind of problem is found in a small network, nothing in a clean one,
and the check is fast enough for a big map."""
import os
import time
import run_undo_test as t

s = t.make_runtime(True)
s.execute(t.read(os.path.join(t.MOD, "scripts", "Manager", "RouteCheck.lua")))
s.execute("""
    function wp(id, x, z, out) return {id = id, x = x, y = 0, z = z, out = out, incoming = {}, flags = 0} end
    function kinds(problems)
        local r = {}
        for _, p in ipairs(problems) do r[#r + 1] = p.kind .. "@" .. p.wayPointId end
        table.sort(r)
        return table.concat(r, " ")
    end
""")

# a two-way ring 1..4 with targets, plus every kind of problem
s.execute("""
    W = {
        wp(1, 0, 0, {2, 4}), wp(2, 10, 0, {1, 3, 5}), wp(3, 10, 10, {2, 4, 9}), wp(4, 0, 10, {3, 1, 12}),
        wp(5, 20, 0, {6}),                -- one-way spur from 2 ...
        wp(6, 30, 0, {}),                 -- ... ending in a dead end
        wp(7, 50, 50, {}),                -- loose waypoint
        wp(8, 10.1, 10.1, {3}),           -- on top of 3 (0.14 m), only leads into the ring
        wp(9, 40, 10, {10}),              -- trap: 9 -> 10 -> 11 -> 10 ... no way out
        wp(10, 50, 10, {11}), wp(11, 60, 10, {10}),
        wp(12, -10, 10, {}),              -- target at a dead end: no way back
        wp(13, -50, -50, {14}), wp(14, -60, -50, {13}), -- separate loop with a target: unreachable
    }
    M = {
        {id = 1, name = "Farm"}, {id = 3, name = "Silo"}, {id = 12, name = "Shed"}, {id = 13, name = "Island"},
        {id = 6, name = "debug", isADDebug = true},
    }
""")
problems = s.eval("ADRouteCheck.analyse(W, M)")
got = s.globals().kinds(problems)
# kinds: LOOSE=1 DEAD_END=2 TRAP=3 UNREACHABLE=4 NO_WAY_BACK=5 DUPLICATE=6, the trap is entered at 10
expected = sorted(["1@7", "2@6", "6@3", "3@10", "5@12", "4@13"])
assert got == " ".join(expected), got

by_kind = {p.kind: p for p in problems.values()}
assert by_kind[3].count == 2, by_kind[3].count
assert by_kind[4].name == "Island" and by_kind[4].noWayBack
assert by_kind[5].name == "Shed"
assert by_kind[6].otherId == 8 and abs(by_kind[6].gap - 0.1414) < 0.001
assert len(by_kind[6].points) == 2

# texts
s.globals().P = problems
texts = [s.eval("ADRouteCheck.getProblemText(P[%d])" % i) for i in range(1, len(problems) + 1)]
assert all("%" not in x for x in texts), texts

# sorting and limit
s.execute("ADRouteCheck.sortByDistance(P, 0, 0)")
d = [problems[i].distance for i in range(1, len(problems) + 1)]
assert d == sorted(d)
counts = s.eval("ADRouteCheck.countKinds(P)")
assert [counts[i] for i in range(1, 7)] == [1, 1, 1, 1, 1, 1]

# clean network: two-way ring with targets, nothing found
s.execute("""
    W = {wp(1, 0, 0, {2, 3}), wp(2, 10, 0, {1, 3}), wp(3, 5, 8, {1, 2})}
    M = {{id = 1, name = "A"}, {id = 3, name = "B"}}
""")
assert len(s.eval("ADRouteCheck.analyse(W, M)")) == 0

# a separate loop without targets (e.g. a field outline) is no problem
s.execute("""
    W[4] = wp(4, 100, 0, {5}); W[5] = wp(5, 110, 0, {6}); W[6] = wp(6, 105, 8, {4})
""")
assert len(s.eval("ADRouteCheck.analyse(W, M)")) == 0, s.globals().kinds(s.eval("ADRouteCheck.analyse(W, M)"))

# big map: a 40000 waypoint chain in both directions, a long one-way chain for deep recursion
start = time.time()
s.execute("""
    W = {}
    local n = 40000
    for i = 1, n do
        local out = {}
        if i > 1 then out[#out + 1] = i - 1 end
        if i < n then out[#out + 1] = i + 1 end
        W[i] = wp(i, (i % 200) * 5, math.floor(i / 200) * 5, out)
    end
    M = {{id = 1, name = "A"}, {id = n, name = "B"}}
    BIG = ADRouteCheck.analyse(W, M)
    ONEWAY = {}
    for i = 1, n do ONEWAY[i] = wp(i, i * 3, 0, i < n and {i + 1} or {1}) end
    BIG2 = ADRouteCheck.analyse(ONEWAY, M)
""")
elapsed = time.time() - start
assert s.eval("#BIG") == 0 and s.eval("#BIG2") == 0
assert elapsed < 10, elapsed
print("OK: route check finds all 6 kinds of problems, clean networks pass, 2x40000 waypoints in %.1fs" % elapsed)
