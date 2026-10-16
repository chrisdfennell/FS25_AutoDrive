"""Driver statistics: distance, driving / waiting time, deliveries from the fill level,
savegame round trip, the multiplayer request / reply / reset event and the fleet view text."""
import os
import run_undo_test as t

s = t.make_runtime(True)
s.execute("""
    Class = function(c, super) local mt = {__index = c}; setmetatable(c, {__index = super}); return mt end
    Event = {new = function(mt) return setmetatable({}, mt) end}
    InitEventClass = function() end
    XMLValueType = {FLOAT = 1}
""")
for f in [("Manager", "Statistics.lua"), ("Events", "StatisticsEvent.lua")]:
    s.execute(t.read(os.path.join(t.MOD, "scripts", *f)))

# --- samples: 1 s apart
s.execute("""
    STATS = ADStatistics.newStats(); TR = {}
    function sample(x, fill, cap) ADStatistics.addSample(STATS, TR, x, 0, fill, cap or 20000, 1000) end
    sample(0, 0)                -- first sample: nothing to compare yet
    sample(10, 0); sample(20, 0)  -- driving 10 m/s
    sample(20, 0); sample(20.2, 0) -- standing (0.2 m/s)
    sample(5000, 0)             -- teleport: no distance, counts as standing
""")
assert s.eval("STATS.distance") == 20.2 or abs(s.eval("STATS.distance") - 20.2) < 1e-9, s.eval("STATS.distance")
assert s.eval("STATS.driveTime") == 2000 and s.eval("STATS.waitTime") == 3000, (s.eval("STATS.driveTime"), s.eval("STATS.waitTime"))

# --- unloading: 20000 l in steps, then quiet -> one delivery
s.execute("""
    sample(5000, 20000); sample(5000, 15000); sample(5000, 8000); sample(5000, 0)
    sample(5000, 0); sample(5000, 0)
""")
assert s.eval("STATS.loads") == 0  # not quiet long enough yet
s.execute("sample(5000, 0)")
assert s.eval("STATS.loads") == 1 and s.eval("STATS.unloaded") == 20000
# loading (fill goes up) is no delivery, a tiny drop neither
s.execute("""
    sample(5000, 18000); sample(5000, 17999.5)
    for i = 1, 4 do sample(5000, 17999.5) end
""")
assert s.eval("STATS.loads") == 1 and s.eval("STATS.unloaded") == 20000
# a small partial unload (200 l of a 20000 l trailer) is counted as amount, not as a delivery
s.execute("sample(5000, 17799.5); for i = 1, 4 do sample(5000, 17799.5) end")
assert s.eval("STATS.loads") == 1 and abs(s.eval("STATS.unloaded") - 20200) < 1e-6
# a small trailer: a quarter of its capacity is enough
s.execute("sample(5000, 1500, 1600); sample(5000, 1100, 1600); for i = 1, 4 do sample(5000, 1100, 1600) end")
assert s.eval("STATS.loads") == 2

# --- text
s.execute("STATS = {distance = 123456, driveTime = 5 * 3600000 + 20 * 60000, waitTime = 3600000 + 10 * 60000, loads = 12, unloaded = 345600}")
text = s.eval("ADStatistics.getText(STATS)")
assert text == "123.5 km  |  driving 5:20 h  |  waiting 1:10 h (18%)  |  deliveries: 12  |  345600 l unloaded", text
assert s.eval("ADStatistics.getText(nil)").startswith("0.0 km")

# --- savegame round trip
s.execute("""
    XML = {values = {}, setValue = function(self, k, v) self.values[k] = v end, getValue = function(self, k) return self.values[k] end,
        hasProperty = function(self, k) for key, _ in pairs(self.values) do if key:sub(1, #k) == k then return true end end return false end}
    V1 = {ad = {stats = STATS}}; V2 = {ad = {}}; V3 = {ad = {}}
    ADStatistics.saveToXML(V1, XML, "v(0).AutoDrive")
    ADStatistics.loadFromXML(V2, XML, "v(0).AutoDrive")
    ADStatistics.loadFromXML(V3, XML, "v(1).AutoDrive")   -- old savegame without statistics
    ADStatistics.saveToXML(V3, XML, "v(1).AutoDrive")     -- nothing counted: nothing written
""")
assert s.eval("ADStatistics.getText(V2.ad.stats)") == text
assert s.eval("V3.ad.stats") is None
assert s.eval("XML.values['v(1).AutoDrive.statistics#loads']") is None

# --- event: client request -> server reply with all vehicles; reset; reply applied on the client
s.execute("""
    STREAM = {}; POS = 0
    local function w(id, v) table.insert(STREAM, v) end
    local function r() POS = POS + 1; return STREAM[POS] end
    streamWriteUIntN = w; streamWriteFloat32 = w; streamWriteInt32 = w
    streamReadUIntN = r; streamReadFloat32 = r; streamReadInt32 = r
    OBJECTS = {}
    NetworkUtil = {getObjectId = function(o) OBJECTS[o.netId] = o; return o.netId end, getObject = function(id) return CLIENT_OBJECTS[id] end,
        writeNodeObjectId = w, readNodeObjectId = r}
    SV1 = {netId = 7, ad = {stats = {distance = 1000, driveTime = 60000, waitTime = 0, loads = 2, unloaded = 4000}}}
    SV2 = {netId = 9, ad = {}}  -- never driven: not sent
    AutoDrive.getAllVehicles = function() return {SV1, SV2} end
    SENT = {}
    local connection = {sendEvent = function(self, ev) table.insert(SENT, ev) end}
    AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_REQUEST):run(connection)
    -- the reply travels to the client
    local reply = SENT[1]
    reply:writeStream(1, nil)
    CV1 = {ad = {}}; CLIENT_OBJECTS = {[7] = CV1}
    local received = AutoDriveStatisticsEvent.emptyNew()
    received:readStream(1, nil)
""")
assert s.eval("#SENT[1].entries") == 1
assert s.eval("CV1.ad.stats.loads") == 2 and s.eval("CV1.ad.stats.unloaded") == 4000
s.execute("""
    AutoDriveStatisticsEvent.new(AutoDriveStatisticsEvent.TYPE_RESET, nil, SV1):run({sendEvent = function(self, ev) RESET_REPLY = ev end})
""")
assert s.eval("SV1.ad.stats.loads") == 0 and s.eval("RESET_REPLY.eventType") == 2
print("OK: statistics (distance, drive / wait time, deliveries, savegame, request / reply / reset event, text)")
