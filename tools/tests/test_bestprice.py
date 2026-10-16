"""Best price unloading: one stop for the whole load, or each product at its best selling point
(several stops), with the vehicle's own tanks left out, safe stop limits and old savegames."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    FillType = {UNKNOWN = 0}
    NAMES = {[1] = "WHEAT", [2] = "BARLEY", [3] = "DIESEL", [4] = "CANOLA"}
    g_fillTypeManager = {getFillTypeNameByIndex = function(self, i) return NAMES[i] end,
        getFillTypeTitleByIndex = function(self, i) return NAMES[i]:sub(1, 1) .. NAMES[i]:sub(2):lower() end}
    MESSAGES = {}
    ADMessagesManager = {messageTypes = {INFO = 1}}
    AutoDriveMessageEvent = {sendMessageOrNotification = function(v, t, text, d, ...) table.insert(MESSAGES, string.format(text, ...)) end}
    SETTINGS = {useFolders = true}
    AutoDrive.getSetting = function(name, vehicle)
        if vehicle ~= nil and vehicle.settings[name] ~= nil then return vehicle.settings[name] end
        return SETTINGS[name]
    end
    -- three selling points in the folder "Sell": A (mill), B (port), C (silo), and one far away target D
    ADGraphManager.wayPoints = {{id = 1, x = 0, y = 0, z = 0}, {id = 2, x = 500, y = 0, z = 0}, {id = 3, x = 1000, y = 0, z = 0}, {id = 4, x = 5000, y = 0, z = 0}}
    ADGraphManager.mapMarkers = {{name = "A", id = 1, markerIndex = 1, group = "Sell"}, {name = "B", id = 2, markerIndex = 2, group = "Sell"},
        {name = "C", id = 3, markerIndex = 3, group = "Sell"}, {name = "D", id = 4, markerIndex = 4, group = "Sell"}}
    ADGraphManager.getMapMarkersInGroup = function(self, g) local r = {} for _, m in ipairs(self.mapMarkers) do if m.group == g then table.insert(r, m) end end return r end
""")
s.execute(t.read(os.path.join(t.MOD, "scripts", "Manager", "BestPrice.lua")))
s.execute("""
    -- prices: wheat best at B (2.0), barley best at C (1.5), canola nowhere; the mill A buys both a bit cheaper
    PRICES = {[1] = {{name = "Mill", x = 10, z = 0, price = 1.8}, {name = "Port", x = 510, z = 0, price = 2.0}},
              [2] = {{name = "Mill", x = 10, z = 0, price = 1.3}, {name = "Silo", x = 1010, z = 0, price = 1.5}}}
    ADBestPrice.getStations = function(fillType) return PRICES[fillType] or {} end
    -- fill units {fillType, level}
    function unit(units) return {getFillUnits = function(self) return units end,
        getFillUnitFillType = function(self, i) return units[i][1] end, getFillUnitFillLevel = function(self, i) return units[i][2] end} end
    function makeTruck(mode, units)
        local sm = {first = ADGraphManager.mapMarkers[4], second = ADGraphManager.mapMarkers[3], name = "Truck"}
        function sm:getFirstMarker() return self.first end
        function sm:getSecondMarker() return self.second end
        function sm:setSecondMarker(i) self.second = ADGraphManager.mapMarkers[i] end
        function sm:setFirstMarker(i) self.first = ADGraphManager.mapMarkers[i] end
        function sm:getName() return self.name end
        function sm:getFillType() return 1 end
        local truck = {settings = {bestPriceUnload = mode}, ad = {stateModule = sm, trailerModule = {getHasAL = function() return false end}}}
        truck.units = units
        return truck
    end
    AutoDrive.getAllUnits = function(v) return v.units end
    AutoDrive.getAllFillLevels = function(units)
        local total = 0
        for _, u in ipairs(units) do for i, _ in ipairs(u:getFillUnits()) do if NAMES[u:getFillUnitFillType(i)] ~= "DIESEL" then total = total + u:getFillUnitFillLevel(i) end end end
        return total
    end
""")

# --- the load: own diesel tank left out
s.execute("""
    TRUCK_UNITS = {unit({{3, 400}}), unit({{1, 10000}, {2, 8000}})}   -- truck with diesel, trailer with wheat + barley
    LOAD = ADBestPrice.getLoad({units = TRUCK_UNITS})
""")
assert s.eval("LOAD[1]") == 10000 and s.eval("LOAD[2]") == 8000 and s.eval("LOAD[3]") is None
assert s.eval("ADBestPrice.getLoadedFillType({units = TRUCK_UNITS})") == 1

# --- one stop: whole load value per target: A (mill) = 10000*1.8 + 8000*1.3 = 28400, B = 20000, C = 12000
s.execute("ONE = makeTruck(1, TRUCK_UNITS); MESSAGES = {}")
assert s.eval("ADBestPrice.apply(ONE, false)") is True
assert s.eval("ONE.ad.stateModule.second.name") == "A"
assert s.eval("MESSAGES[1]") == "$l10n_AD_Driver_of; Truck $l10n_AD_bestPrice_switch; A (Mill)", s.eval("MESSAGES[1]")
assert s.eval("ADBestPrice.finishesUnloadEarly(ONE)")
# old savegames: "yes" is one stop
s.execute("OLD = makeTruck(true, TRUCK_UNITS)")
assert s.eval("ADBestPrice.getMode(OLD)") == 1
# off: nothing changes
s.execute("OFF = makeTruck(0, TRUCK_UNITS)")
assert s.eval("ADBestPrice.apply(OFF, false)") is False and s.eval("OFF.ad.stateModule.second.name") == "C"
assert not s.eval("ADBestPrice.finishesUnloadEarly(OFF)")

# --- each product: wheat first (10000*2.0 at B = 20000 > barley 8000*1.5 at C = 12000)
s.execute("EACH = makeTruck(2, TRUCK_UNITS); MESSAGES = {}")
assert s.eval("ADBestPrice.apply(EACH, false)") is True
assert s.eval("EACH.ad.stateModule.second.name") == "B"
assert s.eval("MESSAGES[1]").endswith("B (Port): Wheat"), s.eval("MESSAGES[1]")
# at B only the wheat is sold; the barley is left: drive on
s.execute("TRUCK_UNITS[2] = unit({{1, 0}, {2, 8000}}); EACH.units = TRUCK_UNITS")
assert s.eval("ADBestPrice.wantsNextStop(EACH, 8000)") is True
assert s.eval("ADBestPrice.apply(EACH, false)") is True
assert s.eval("EACH.ad.stateModule.second.name") == "C" and s.eval("EACH.ad.bestPriceStops") == 1

# --- a product nobody buys is left: no next stop, so no endless waiting
s.execute("""
    STUCK = makeTruck(2, {unit({{1, 5000}, {4, 3000}})})
    ADBestPrice.apply(STUCK, false)
    STUCK.units = {unit({{1, 0}, {4, 3000}})}
""")
assert s.eval("ADBestPrice.wantsNextStop(STUCK, 3000)") is False
assert s.eval("STUCK.ad.bestPriceActive") is False and s.eval("STUCK.ad.bestPriceStops") == 0
# --- a stop that sold nothing ends the chain
s.execute("NOSALE = makeTruck(2, {unit({{1, 10000}, {2, 8000}})}); ADBestPrice.apply(NOSALE, false)")
assert s.eval("ADBestPrice.wantsNextStop(NOSALE, 18000)") is False

# --- at most MAX_STOPS stops for one load
s.execute("""
    LIMIT = makeTruck(2, {unit({{1, 10000}, {2, 8000}})})
    COUNT = 0
    for i = 1, 10 do
        ADBestPrice.apply(LIMIT, false)
        if not ADBestPrice.wantsNextStop(LIMIT, LIMIT.ad.bestPriceFillBefore - 100) then break end
        COUNT = COUNT + 1
    end
""")
assert s.eval("COUNT") == s.eval("ADBestPrice.MAX_STOPS") - 1, s.eval("COUNT")
# the next load counts from 0 again
s.execute("ADBestPrice.apply(LIMIT, false)")
assert s.eval("LIMIT.ad.bestPriceStops") == 0

# --- unload at (first marker): always one stop
s.execute("UA = makeTruck(2, {unit({{1, 10000}, {2, 8000}})}); UA.ad.stateModule.first = ADGraphManager.mapMarkers[4]")
assert s.eval("ADBestPrice.apply(UA, true)") is True and s.eval("UA.ad.stateModule.first.name") == "A"
# --- target in "All": not used
s.execute("ALL = makeTruck(1, {unit({{1, 10000}})}); ALL.ad.stateModule.second = {name = 'X', id = 1, markerIndex = 9, group = 'All'}")
assert s.eval("ADBestPrice.apply(ALL, false)") is False
# --- folders switched off: not used
s.execute("SETTINGS.useFolders = false")
assert s.eval("ADBestPrice.apply(makeTruck(1, {unit({{1, 10000}})}), false)") is False
print("OK: best price (one stop for the whole load, each product with several stops, limits, own tanks, old savegames)")
