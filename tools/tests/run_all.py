"""Runs all undo / redo tests outside the game (needs: pip install lupa).

The mod code is loaded into a Lua runtime with stubs for the game API, see stubs.lua.
Lupa ships Lua 5.4/5.5 while the game runs Lua 5.1, so syntax is checked separately with luac5.1 in CI.

usage: python tools/tests/run_all.py [seeds]   (default 100 random runs)
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def run(*args):
    start = time.time()
    result = subprocess.run([sys.executable, *args], cwd=HERE, capture_output=True, text=True, encoding="utf-8")
    output = (result.stdout + result.stderr).strip()
    last_line = output.splitlines()[-1] if output else ""
    status = "ok  " if result.returncode == 0 else "FAIL"
    print("%s %-28s %5.1fs  %s" % (status, " ".join(args), time.time() - start, last_line))
    if result.returncode != 0:
        print(output)
    return result.returncode == 0


def main():
    seeds = sys.argv[1] if len(sys.argv) > 1 else "100"
    long_runs = (
        "import run_undo_test as t\n"
        "n = sum(t.run(s, n_wp=30, n_ops=260) for s in range(1000, 1003))\n"
        "print('OK: long runs past the 100 step limit, %d edits' % n)\n"
    )
    results = [
        run("run_undo_test.py", seeds),
        run("-c", long_runs),
        run("test_extra.py"),
        run("test_new.py"),
        run("test_fieldpoints.py"),
        run("test_log.py"),
        run("test_routecheck.py"),
        run("test_tidy.py"),
        run("test_features.py"),
        run("test_statistics.py"),
        run("test_more.py"),
        run("test_bestprice.py"),
        run("test_unloadfilter.py"),
        run("test_zones_load_map.py"),
        run("test_waypointpanel.py"),
        run("test_actor_deferred.py"),
    ]
    if not all(results):
        sys.exit(1)
    print("all tests passed")


if __name__ == "__main__":
    main()
