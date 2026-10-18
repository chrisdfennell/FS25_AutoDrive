"""Dragging a waypoint puts it where the mouse points at the ground, also on a slope (it used to stay at the same
distance from the camera and so ended up above or below the road on a hill)."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute(t.read(os.path.join(t.MOD, "scripts", "Utils", "UtilFuncs.lua")))
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud.lua")))
s.execute("""
    -- a hill: the ground rises 0.3 m per metre towards +z
    function ground(x, z) return 0.3 * z end
    g_currentMission = g_currentMission or {}
    g_currentMission.terrainRootNode = 1
    getTerrainHeightAtWorldPos = function(node, x, y, z) return ground(x, z) end
    CollisionFlag = {DEFAULT = 1, ROAD = 2, TERRAIN = 4}
    RAYCAST = false
    -- the engine's raycast: here only the terrain, and only when RAYCAST is on
    raycastClosest = function(x, y, z, dx, dy, dz, maxDistance, callback, target, mask)
        if not RAYCAST then return end
        -- straight down (height lookup): hit the ground below
        if dx == 0 and dz == 0 then
            target[callback](target, 1, x, ground(x, z), z, y - ground(x, z))
            return
        end
        for i = 0, maxDistance * 10 do
            local d = i / 10
            local px, py, pz = x + dx * d, y + dy * d, z + dz * d
            if py <= ground(px, pz) then target[callback](target, 1, px, py, pz, d); return end
        end
    end
    -- a camera at (0, 20, -30) looking along +z and down; mouse (0.5, 0.5) is the middle of the screen
    CAM = {0, 20, -30}
    function rayDir(mx, my)
        local dx, dy, dz = (mx - 0.5) * 1.2, -0.45 + (my - 0.5) * 0.9, 1
        local l = math.sqrt(dx * dx + dy * dy + dz * dz)
        return dx / l, dy / l, dz / l
    end
    NEAR, FAR = 0.1, 1000
    unProject = function(mx, my, depth)
        local dx, dy, dz = rayDir(mx, my)
        local d = NEAR + depth * (FAR - NEAR)
        return CAM[1] + dx * d, CAM[2] + dy * d, CAM[3] + dz * d
    end
    project = function(x, y, z)
        local d = math.sqrt((x - CAM[1]) ^ 2 + (y - CAM[2]) ^ 2 + (z - CAM[3]) ^ 2)
        return 0.5, 0.5, (d - NEAR) / (FAR - NEAR)
    end
    AutoDrive.drawHeight, AutoDrive.getSetting = 0, function() return 0 end
    ADGraphManager.wayPoints = {{id = 1, x = 0, y = ground(0, 0), z = 0, out = {}, incoming = {}, flags = 0}}
    function onRay(x, y, z, mx, my)
        -- is the point on the line from the camera through the mouse?
        local dx, dy, dz = rayDir(mx, my)
        local px, py, pz = x - CAM[1], y - CAM[2], z - CAM[3]
        local along = px * dx + py * dy + pz * dz
        local ex, ey, ez = px - dx * along, py - dy * along, pz - dz * along
        return math.sqrt(ex * ex + ey * ey + ez * ez)
    end
""")

for raycast in (False, True):
    s.execute("RAYCAST = %s" % ("true" if raycast else "false"))
    # drag up the hill and down the hill
    for mx, my in [(0.5, 0.62), (0.5, 0.40), (0.62, 0.5)]:
        s.execute("""
            local wp = ADGraphManager.wayPoints[1]
            wp.x, wp.y, wp.z = 0, ground(0, 0), 0
            AutoDrive.leftLSHIFTmodifierKeyPressed = true          -- Shift is the drag key
            g_lastMousePosX, g_lastMousePosY = %s, %s
            AutoDrive.moveNodeToMousePos(1, true)
        """ % (mx, my))
        x, y, z = s.eval("ADGraphManager.wayPoints[1].x"), s.eval("ADGraphManager.wayPoints[1].y"), s.eval("ADGraphManager.wayPoints[1].z")
        assert abs(y - 0.3 * z) < 0.05, (raycast, mx, my, x, y, z)                          # on the ground
        assert s.eval("onRay(%r, %r, %r, %r, %r)" % (x, y, z, mx, my)) < 0.1, (raycast, mx, my)  # under the mouse

# the game's depth may run the other way round (far = 0): the ray starts at the camera either way
s.execute("""
    getCamera = function() return 77 end
    getWorldTranslation = function(node) if node == 77 then return CAM[1], CAM[2], CAM[3] end return 0, 0, 0 end
    local forward = unProject
    unProject = function(mx, my, depth) return forward(mx, my, 1 - depth) end
    RAYCAST = false
    GX, GY, GZ = AutoDrive.getGroundUnderMouse(0.5, 0.62)
    unProject = forward
""")
assert s.eval("GX") is not None and abs(s.eval("GY") - 0.3 * s.eval("GZ")) < 0.05
assert s.eval("onRay(GX, GY, GZ, 0.5, 0.62)") < 0.1

# the old way was off the ground under the mouse: same distance from the camera
s.execute("""
    local wp = ADGraphManager.wayPoints[1]
    wp.x, wp.y, wp.z = 0, ground(0, 0), 0
    local _, _, depth = project(wp.x, wp.y, wp.z)
    OLD = {unProject(0.5, 0.62, depth)}
""")
assert s.eval("onRay(OLD[1], ground(OLD[1], OLD[3]), OLD[3], 0.5, 0.62)") > 1

# keep the height (upstream: Shift with the right / middle button drag): the height stays
s.execute("""
    local wp = ADGraphManager.wayPoints[1]
    wp.x, wp.y, wp.z = 0, 3, 0
    AutoDrive.leftLSHIFTmodifierKeyPressed = true
    g_lastMousePosX, g_lastMousePosY = 0.5, 0.62
    AutoDrive.moveNodeToMousePos(1, false)
""")
assert s.eval("ADGraphManager.wayPoints[1].y") == 3

# the mouse at the sky: no ground, the old way is used
s.execute("RAYCAST = false; X, Y, Z = AutoDrive.getGroundUnderMouse(0.5, 1.5)")
assert s.eval("X") is None
print("OK: a dragged waypoint goes where the mouse points at the ground, up and down a hill (raycast and terrain)")
