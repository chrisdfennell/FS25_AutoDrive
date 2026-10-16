"""Work schedule, best price unloading, fleet overview rows and the route check screen,
run against small stand-ins for the game objects."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    DialogElement = {new = function(target, mt) return setmetatable({}, mt) end}
    ADGuiDebugMixin = {}
    FillType = {UNKNOWN = 0}
    SellingStation = {}
    MESSAGES = {}
    AutoDriveMessageEvent = {sendMessageOrNotification = function(vehicle, messageType, text, duration, ...)
        table.insert(MESSAGES, string.format(text, ...))
    end}
    ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2, ERROR = 3}, history = {},
        getHistory = function(self) return self.history end,
        addMessage = function(self, vehicle, messageType, text) table.insert(MESSAGES, text) end}
    ADNotificationsHistoryGui = {ICON_SLICES = {"ad_gui.info_icon", "ad_gui.warn_icon", "ad_gui.error_icon"}}
    SETTINGS = {useFolders = true}
    AutoDrive.getSetting = function(name, vehicle)
        if vehicle ~= nil and vehicle.settings ~= nil and vehicle.settings[name] ~= nil then return vehicle.settings[name] end
        return SETTINGS[name]
    end
    AutoDrive.MODE_DRIVETO = 1; AutoDrive.MODE_PICKUPANDDELIVER = 2; AutoDrive.MODE_DELIVERTO = 3
    AutoDrive.Hud = {getModeName = function(self, vehicle) return "mode" .. vehicle.ad.stateModule.mode end}
    STARTSTOP = {}
    ADInputManager = {input_start_stop = function(self, vehicle, farmId)
        table.insert(STARTSTOP, vehicle.ad.stateModule.name)
        vehicle.ad.stateModule.active = not vehicle.ad.stateModule.active
    end}
    function makeVehicle(name, mode, settings, active)
        local stateModule = {name = name, mode = mode, active = active or false, first = {name = "Field", id = 1, markerIndex = 1, group = "All"},
            second = {name = "Silo A", id = 2, markerIndex = 2, group = "Silos"}}
        function stateModule:isActive() return self.active end
        function stateModule:getName() return self.name end
        function stateModule:getMode() return self.mode end
        function stateModule:getFirstMarker() return self.first end
        function stateModule:getSecondMarker() return self.second end
        function stateModule:getFirstMarkerName() return self.first.name end
        function stateModule:getSecondMarkerName() return self.second.name end
        function stateModule:setSecondMarker(index) self.second = ADGraphManager.mapMarkers[index] end
        function stateModule:setFirstMarker(index) self.first = ADGraphManager.mapMarkers[index] end
        function stateModule:getFillType() return 7 end
        function stateModule:getCurrentLocalizedTaskInfo() return "driving to Silo A" end
        return {ad = {stateModule = stateModule}, settings = settings, getOwnerFarmId = function() return 1 end}
    end
""")
for f in [("Manager", "WorkSchedule.lua"), ("Manager", "Statistics.lua"), ("Manager", "BestPrice.lua"), ("Manager", "RouteCheck.lua"), ("Gui", "FleetGUI.lua"), ("Gui", "RouteCheckGUI.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))

# --- schedule: which hour crossings start or stop
cases = [
    # start, stop, lastHour, hour, expected
    (6, 20, 5, 6, "START"), (6, 20, 6, 7, None), (6, 20, 19, 20, "STOP"), (6, 20, 20, 20, None),
    (6, 20, None, 6, None),             # first check after loading: nothing
    (6, 20, 3, 8, "START"),             # time skip over the start hour
    (6, 20, 18, 7, "START"),            # slept over the night: stop at 20, start at 6, start comes later
    (6, 20, 4, 21, "STOP"),             # skipped the whole day: stop comes later
    (22, 5, 21, 22, "START"), (22, 5, 4, 5, "STOP"),  # night shift over midnight
    (None, 20, 19, 20, "STOP"), (6, None, 5, 6, "START"), (None, None, 5, 6, None),
]
for start, stop, last, hour, expected in cases:
    lua = lambda v: "nil" if v is None else str(v)
    got = s.eval("ADWorkSchedule.getAction(%s, %s, %s, %s)" % (lua(start), lua(stop), lua(last), lua(hour)))
    want = None if expected is None else s.eval("ADWorkSchedule." + expected)
    assert got == want, (start, stop, last, hour, got, expected)

# --- schedule: the server loop starts and stops vehicles once per crossing
s.execute("""
    ADGraphManager.wayPoints = {{id = 1, x = 0, y = 0, z = 0, out = {}, incoming = {}}, {id = 2, x = 100, y = 0, z = 0, out = {}, incoming = {}}}
    TRUCK = makeVehicle("Truck", AutoDrive.MODE_PICKUPANDDELIVER, {scheduleStart = 6, scheduleStop = 20})
    TRACTOR = makeVehicle("Tractor", AutoDrive.MODE_DRIVETO, {scheduleStart = 6, scheduleStop = 20})
    IDLE = makeVehicle("Idle", AutoDrive.MODE_DRIVETO, {scheduleStart = -1, scheduleStop = -1})
    AutoDrive.getAllVehicles = function() return {TRUCK, TRACTOR, IDLE} end
    g_currentMission = {environment = {dayTime = 5.5 * 3600000}}
    ADWorkSchedule:load()
    function tick(hour) g_currentMission.environment.dayTime = hour * 3600000; ADWorkSchedule:update(1000) end
    tick(5.5); tick(5.9); tick(6.1); tick(6.5)
""")
assert list(s.eval("STARTSTOP").values()) == ["Truck", "Tractor"], list(s.eval("STARTSTOP").values())
assert s.eval("TRUCK.ad.stateModule.active and TRACTOR.ad.stateModule.active and not IDLE.ad.stateModule.active")
s.execute("tick(19.9); tick(20.0)")
# pickup & deliver finishes its round (flag), the tractor stops right away
assert s.eval("TRUCK.ad.stateModule.active and ADWorkSchedule.isStopRequested(TRUCK)")
assert s.eval("not TRACTOR.ad.stateModule.active")
assert list(s.eval("STARTSTOP").values()) == ["Truck", "Tractor", "Tractor"]
# the truck parks (its job ends), the flag is cleared
s.execute("TRUCK.ad.stateModule.active = false; tick(20.5)")
assert not s.eval("ADWorkSchedule.isStopRequested(TRUCK)")
assert s.eval("ADWorkSchedule.getText(TRUCK)") == "06:00 - 20:00"
assert s.eval("ADWorkSchedule.getText(IDLE)") is None
texts = list(s.eval("MESSAGES").values())
assert texts[2] == "$l10n_AD_Driver_of; Truck $l10n_AD_schedule_finishing;", texts

# --- best price: nearest selling point within reach, highest price wins
s.execute("""
    CANDIDATES = {{marker = "A", x = 0, z = 0}, {marker = "B", x = 500, z = 0}, {marker = "C", x = 1000, z = 0}}
    STATIONS = {{name = "Mill", x = 10, z = 0, price = 1.2}, {name = "Port", x = 520, z = 0, price = 1.9}, {name = "Far", x = 1200, z = 0, price = 9}}
    BEST, STATION = ADBestPrice.pickBest(CANDIDATES, STATIONS, 60)
""")
assert s.eval("BEST.marker") == "B" and s.eval("STATION.name") == "Port"
s.execute("BEST2 = ADBestPrice.pickBest({{marker = 'C', x = 1000, z = 0}}, STATIONS, 60)")
assert s.eval("BEST2") is None

# --- best price apply: switches the unload target inside the folder and tells the player
s.execute("""
    ADGraphManager.wayPoints[3] = {id = 3, x = 500, y = 0, z = 0, out = {}, incoming = {}}
    ADGraphManager.mapMarkers = {{name = "Field", id = 1, markerIndex = 1, group = "All"}, {name = "Silo A", id = 2, markerIndex = 2, group = "Silos"},
        {name = "Silo B", id = 3, markerIndex = 3, group = "Silos"}}
    ADGraphManager.getMapMarkersInGroup = function(self, group)
        local r = {}
        for _, m in ipairs(self.mapMarkers) do if m.group == group then table.insert(r, m) end end
        return r
    end
    AutoDrive.getAllUnits = function() return {} end
    ADBestPrice.getStations = function(fillType) return {{name = "Mill", x = 110, z = 0, price = 1.0}, {name = "Port", x = 510, z = 0, price = 2.0}} end
    SELLER = makeVehicle("Seller", AutoDrive.MODE_PICKUPANDDELIVER, {bestPriceUnload = true})
    OFF = makeVehicle("Off", AutoDrive.MODE_PICKUPANDDELIVER, {bestPriceUnload = false})
    MESSAGES = {}
""")
assert s.eval("ADBestPrice.apply(SELLER, false)") is True
assert s.eval("SELLER.ad.stateModule:getSecondMarkerName()") == "Silo B"
assert "Silo B (Port)" in list(s.eval("MESSAGES").values())[0]
assert s.eval("ADBestPrice.apply(OFF, false)") is False
assert s.eval("OFF.ad.stateModule:getSecondMarkerName()") == "Silo A"
s.execute("SELLER.ad.stateModule.second = ADGraphManager.mapMarkers[1]")  # folder "All": not used
assert s.eval("ADBestPrice.apply(SELLER, false)") is False

# --- fleet rows
s.execute("""
    ADFleetGui.getLoadPercent = function(vehicle) return vehicle.load end
    ADFleetGui.getFuelPercent = function(vehicle) return 41.6 end
    g_localPlayer = {getFarmId = function() return 1 end}
    TRUCK.ad.stateModule.active = true; TRUCK.load = 75
    TRACTOR.ad.stateModule.active = false
    ADMessagesManager.history = {{vehicle = TRACTOR, messageType = 3, text = "is stuck"}}
    OTHERFARM = makeVehicle("Neighbour", 1, {}); OTHERFARM.getOwnerFarmId = function() return 2 end
    AutoDrive.getAllVehicles = function() return {TRACTOR, OTHERFARM, TRUCK, IDLE} end
    ROWS = ADFleetGui.getRows()
""")
rows = [s.eval("ROWS[%d].text" % i) for i in range(1, s.eval("#ROWS") + 1)]
assert len(rows) == 3, rows  # other farm left out
# by name, not by state: the selected row must stay on its vehicle when the list refreshes
assert rows[0].startswith("Idle") and rows[1].startswith("Tractor"), rows
assert rows[2].startswith("Truck  |  mode2  |  Field > Silo A  |  load 75%  |  fuel 42%  |  06:00 - 20:00  |  driving to Silo A"), rows[2]
assert rows[1].endswith("stopped: is stuck") and s.eval("ROWS[2].icon") == "ad_gui.error_icon", rows[1]

# --- route check screen: open runs the check, rows show distance, show sets the highlight
s.execute("""
    getWorldTranslation = function(node) return 0, 0, 0 end
    ADGraphManager.getWayPointsCount = function(self) return #self.wayPoints end
    ADGraphManager.getWayPoints = function(self) return self.wayPoints end
    ADGraphManager.getMapMarkers = function(self) return {} end
    OPENED = false; AutoDrive.onOpenRouteCheck = function() OPENED = true end
    g_time = 1000
    VEHICLE = {components = {{node = 1}}}
    ADRouteCheck:open(VEHICLE)
""")
assert s.eval("OPENED") and s.eval("ADRouteCheck.total") == 3  # 3 loose waypoints
assert s.eval("ADRouteCheck:getRowText(ADRouteCheck.problems[1])") == "Loose waypoint without any connection  (0 m)"
s.execute("ADRouteCheck:show(ADRouteCheck.problems[3], VEHICLE)")
assert "500 m away" in list(s.eval("MESSAGES").values())[-1], list(s.eval("MESSAGES").values())[-1]
s.execute("""
    DRAWN = 0
    ADDrawingManager = {addSphereTask = function() DRAWN = DRAWN + 1 end, addLineTask = function() DRAWN = DRAWN + 1 end,
        addArrowTask = function() DRAWN = DRAWN + 10 end, arrows = {position = {start = 1}}}
    AutoDrive.drawDistance = 200
    ADRouteCheck:draw(VEHICLE)
""")
assert s.eval("DRAWN") == 13  # sphere + beacon + pointer line + arrow
s.execute("g_time = g_time + ADRouteCheck.SHOW_DURATION + 1; ADRouteCheck:draw(VEHICLE)")
assert s.eval("ADRouteCheck.shown") is None
# --- HUD header: a wrapped header text can be grabbed on all its lines
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud", "GenericHudElement.lua")))
s.execute(t.read(os.path.join(t.MOD, "scripts", "Hud", "HudIcon.lua")))
s.execute("""
    HEADER = setmetatable({name = "header", layer = 1, position = {x = 0.5, y = 0.8}, size = {width = 0.2, height = 0.02}}, {__index = ADHudIcon})
    ICON = setmetatable({name = "background", layer = 1, position = {x = 0.5, y = 0.8}, size = {width = 0.2, height = 0.02}, extraHeight = 0.05}, {__index = ADHudIcon})
""")
assert s.eval("HEADER:hit(0.6, 0.81, 0)") and not s.eval("HEADER:hit(0.6, 0.835, 0)")
s.execute("HEADER.extraHeight = 0.025")  # second line of text
assert s.eval("HEADER:hit(0.6, 0.835, 0)") and not s.eval("HEADER:hit(0.6, 0.85, 0)")
assert not s.eval("ICON:hit(0.6, 0.835, 0)")  # only the header grows

# --- fleet overview key on foot: registered for the player, not again in a vehicle
s.execute("""
    REGISTERED = {}
    InputAction = {ADFleet = "ADFleet"}
    Utils = Utils or {}
    Utils.appendedFunction = function(original, extra) return function(...) original(...); extra(...) end end
    PlayerInputComponent = {registerGlobalPlayerActionEvents = function(self, controlling) end}
    g_inputBinding = {registerActionEvent = function(self, action, target, callback) table.insert(REGISTERED, {action, callback}); return true, "id" .. #REGISTERED end,
        setActionEventTextVisibility = function() end}
    FLEET_OPENED = 0; AutoDrive.onOpenFleet = function() FLEET_OPENED = FLEET_OPENED + 1 end
""")
s.execute(t.read(os.path.join(t.MOD, "scripts", "Gui", "FleetGUI.lua")))
s.execute("PlayerInputComponent:registerGlobalPlayerActionEvents('VEHICLE')")
assert s.eval("#REGISTERED") == 0
s.execute("PlayerInputComponent:registerGlobalPlayerActionEvents('PLAYER'); REGISTERED[1][2]()")
assert s.eval("REGISTERED[1][1]") == "ADFleet" and s.eval("FLEET_OPENED") == 1

print("OK: schedule (13 hour cases, start/stop/finish round), best price, fleet rows, route check screen, header grab area, fleet key on foot")
