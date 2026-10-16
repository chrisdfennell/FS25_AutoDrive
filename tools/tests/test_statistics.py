"""Driver statistics: distance, driving / waiting time, deliveries from the fill level, per fill type and
per in-game day (today, last 7 days), estimated income, savegame round trip, the multiplayer
request / reply / reset event and the fleet view text."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    XMLValueType = {FLOAT = 1, INT = 2, STRING = 3}
    FillType = {UNKNOWN = 0}
    FILLTYPES = {WHEAT = {index = 1, title = "Wheat", pricePerLiter = 0.5}, BARLEY = {index = 2, title = "Barley", pricePerLiter = 0.4}}
    g_fillTypeManager = {
        getFillTypeIndexByName = function(self, n) return FILLTYPES[n] and FILLTYPES[n].index end,
        getFillTypeByIndex = function(self, i) for _, f in pairs(FILLTYPES) do if f.index == i then return f end end end,
        getFillTypeByName = function(self, n) return FILLTYPES[n] end,
        getFillTypeNameByIndex = function(self, i) for n, f in pairs(FILLTYPES) do if f.index == i then return n end end end}
    ADBestPrice = {getStations = function(fillType) if fillType == 1 then return {{price = 0.8}, {price = 1.2}} end return {} end}
    g_i18n.formatMoney = function(self, v) return string.format("%d $", math.floor(v + 0.5)) end
""")
for f in [("Manager", "Statistics.lua"), ("Events", "StatisticsEvent.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))

# --- samples: 1 s apart, on day 10
s.execute("""
    STATS = ADStatistics.newStats(); TR = {}; DAY = 10
    function sample(x, fill, cap, fillType) ADStatistics.addSample(STATS, TR, x, 0, fill, cap or 20000, 1000, DAY, fillType) end
    sample(0, 0)                -- first sample: nothing to compare yet
    sample(10, 0); sample(20, 0)  -- driving 10 m/s
    sample(20, 0); sample(20.2, 0) -- standing (0.2 m/s)
    sample(5000, 0)             -- teleport: no distance, counts as standing
""")
assert abs(s.eval("STATS.distance") - 20.2) < 1e-9, s.eval("STATS.distance")
assert s.eval("STATS.driveTime") == 2000 and s.eval("STATS.waitTime") == 3000, (s.eval("STATS.driveTime"), s.eval("STATS.waitTime"))
assert s.eval("STATS.days[10].driveTime") == 2000 and abs(s.eval("STATS.days[10].distance") - 20.2) < 1e-9

# --- unloading wheat: 20000 l in steps, then quiet -> one delivery, litres per fill type
s.execute("""
    sample(5000, 20000, nil, "WHEAT"); sample(5000, 15000, nil, "WHEAT"); sample(5000, 8000, nil, "WHEAT"); sample(5000, 0)
    sample(5000, 0); sample(5000, 0)
""")
assert s.eval("STATS.loads") == 0  # not quiet long enough yet
s.execute("sample(5000, 0)")
assert s.eval("STATS.loads") == 1 and s.eval("STATS.unloaded") == 20000
assert s.eval("STATS.fillTypes.WHEAT") == 20000 and s.eval("STATS.days[10].fillTypes.WHEAT") == 20000
# loading (fill goes up) is no delivery, a tiny drop neither
s.execute("""
    sample(5000, 18000, nil, "BARLEY"); sample(5000, 17999.5, nil, "BARLEY")
    for i = 1, 4 do sample(5000, 17999.5, nil, "BARLEY") end
""")
assert s.eval("STATS.loads") == 1 and s.eval("STATS.unloaded") == 20000
# a small partial unload (200 l of a 20000 l trailer) is counted as amount, not as a delivery
s.execute("sample(5000, 17799.5, nil, 'BARLEY'); for i = 1, 4 do sample(5000, 17799.5, nil, 'BARLEY') end")
assert s.eval("STATS.loads") == 1 and abs(s.eval("STATS.unloaded") - 20200) < 1e-6
assert abs(s.eval("STATS.fillTypes.BARLEY") - 200) < 1e-6

# --- days: day 12 is a new day, day 3 is dropped when day 12 starts (more than 7 days back)
s.execute("""
    STATS.days[3] = ADStatistics.newRecord(); STATS.days[3].loads = 99
    DAY = 12
    TR = {}  -- a new drive, like after AutoDrive was stopped and started again
    sample(5000, 1500, 1600, "WHEAT"); sample(5000, 1100, 1600, "WHEAT"); for i = 1, 4 do sample(5000, 1100, 1600, "WHEAT") end
""")
assert s.eval("STATS.days[3]") is None
assert s.eval("STATS.loads") == 2 and s.eval("STATS.days[12].loads") == 1 and s.eval("STATS.days[10].loads") == 1
today = s.eval("ADStatistics.getPeriod(STATS, ADStatistics.PERIOD_TODAY, 12)")
week = s.eval("ADStatistics.getPeriod(STATS, ADStatistics.PERIOD_WEEK, 12)")
assert today.loads == 1 and today.fillTypes.WHEAT == 400
assert week.loads == 2 and week.fillTypes.WHEAT == 20400
assert s.eval("ADStatistics.getPeriod(STATS, ADStatistics.PERIOD_WEEK, 20).loads") == 0  # all older than 7 days
assert s.eval("ADStatistics.getPeriod(STATS, ADStatistics.PERIOD_TOTAL, 12).loads") == 2

# --- income: best selling point (1.2 for wheat) else the base price (0.4 for barley)
income = s.eval("ADStatistics.getIncome(STATS)")
assert abs(income - (20400 * 1.2 + 200 * 0.4)) < 1e-6, income

# --- text
s.execute("""
    REC = ADStatistics.newRecord()
    REC.distance = 123456; REC.driveTime = 5 * 3600000 + 20 * 60000; REC.waitTime = 3600000 + 10 * 60000; REC.loads = 12; REC.unloaded = 345600
    REC.fillTypes = {WHEAT = 200000, BARLEY = 145600}
""")
text = s.eval("ADStatistics.getText(REC)")
assert text == ("123.5 km  |  driving 5:20 h  |  waiting 1:10 h (18%)  |  deliveries: 12  |  345600 l unloaded"
                "  |  Wheat 200000 l, Barley 145600 l  |  about 298240 $"), text
assert s.eval("ADStatistics.getText(nil)").startswith("0.0 km")

# --- savegame round trip, with days and fill types
s.execute("""
    XML = {values = {}, setValue = function(self, k, v) self.values[k] = v end, getValue = function(self, k) return self.values[k] end,
        hasProperty = function(self, k) for key, _ in pairs(self.values) do if key:sub(1, #k) == k then return true end end return false end}
    V1 = {ad = {stats = STATS}}; V2 = {ad = {}}; V3 = {ad = {}}
    ADStatistics.saveToXML(V1, XML, "v(0).AutoDrive")
    ADStatistics.loadFromXML(V2, XML, "v(0).AutoDrive")
    ADStatistics.loadFromXML(V3, XML, "v(1).AutoDrive")   -- old savegame without statistics
    ADStatistics.saveToXML(V3, XML, "v(1).AutoDrive")     -- nothing counted: nothing written
""")
assert s.eval("ADStatistics.getText(V2.ad.stats)") == s.eval("ADStatistics.getText(STATS)")
assert s.eval("V2.ad.stats.days[12].fillTypes.WHEAT") == 400 and s.eval("V2.ad.stats.days[10].loads") == 1
assert s.eval("V3.ad.stats") is None
assert s.eval("XML.values['v(1).AutoDrive.statistics#loads']") is None

# --- event: client request -> server reply with all vehicles; reset; reply applied on the client
s.execute("""
    STREAM = {}; POS = 0
    local function w(id, v) table.insert(STREAM, v) end
    local function r() POS = POS + 1; return STREAM[POS] end
    streamWriteUIntN = w; streamWriteFloat32 = w; streamWriteInt32 = w; streamWriteString = w
    streamReadUIntN = r; streamReadFloat32 = r; streamReadInt32 = r; streamReadString = r
    NetworkUtil = {getObjectId = function(o) return o.netId end, getObject = function(id) return CLIENT_OBJECTS[id] end,
        writeNodeObjectId = w, readNodeObjectId = r}
    SV1 = {netId = 7, ad = {stats = STATS}}
    SV2 = {netId = 9, ad = {}}  -- never driven: not sent
    AutoDrive.getAllVehicles = function() return {SV1, SV2} end
    SENT = {}
    local connection = {sendEvent = function(self, ev) table.insert(SENT, ev) end}
    AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_REQUEST):run(connection)
    local reply = SENT[1]
    reply:writeStream(1, nil)
    CV1 = {ad = {}}; CLIENT_OBJECTS = {[7] = CV1}
    local received = AutoDriveStatisticsEvent.emptyNew()
    received:readStream(1, nil)
""")
assert s.eval("#SENT[1].entries") == 1
assert s.eval("ADStatistics.getText(CV1.ad.stats)") == s.eval("ADStatistics.getText(STATS)")
assert s.eval("CV1.ad.stats.days[12].fillTypes.WHEAT") == 400
s.execute("""
    AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_RESET, nil, SV1):run({sendEvent = function(self, ev) RESET_REPLY = ev end})
""")
assert s.eval("SV1.ad.stats.loads") == 0 and s.eval("RESET_REPLY.eventType") == 2
print("OK: statistics (distance, drive / wait time, deliveries, per fill type and day, income, savegame, event, text)")
