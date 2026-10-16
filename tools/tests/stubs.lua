-- minimal FS / AutoDrive environment for running GraphManager + UndoManager outside the game
unpack = unpack or table.unpack

function table.contains(t, v)
    for _, x in pairs(t) do
        if x == v then
            return true
        end
    end
    return false
end
function table.indexOf(t, v)
    for i, x in ipairs(t) do
        if x == v then
            return i
        end
    end
    return nil
end
function table.removeValue(t, v)
    local i = table.indexOf(t, v)
    if i then
        table.remove(t, i)
        return true
    end
    return false
end
function table.count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

Logging = {
    warning = function(fmt, ...)
        error("Logging.warning: " .. string.format(fmt, ...))
    end,
    error = function(fmt, ...)
        error("Logging.error: " .. string.format(fmt, ...))
    end
}

AutoDrive = {
    Hud = {lastUIScale = 0},
    FLAG_NONE = 0,
    FLAG_SUBPRIO = 1,
    notifyDestinationListeners = function() end,
    getAllVehicles = function() return {} end,
    getSetting = function() return false end,
    resetMouseSelections = function() end,
    getControlledVehicle = function() return nil end,
    isInExtendedEditorMode = function() return false end,
    playSample = function() end
}

BROADCASTS = {}
AutoDriveUndoRedoEvent = {
    newApply = function(instructions) return {instructions = instructions} end,
    newFeedback = function() return {} end
}
FEEDBACK = {}

bit32 = {band = function(a, b) return a & b end}

-- network stream stubs: values are queued in STREAM
STREAM = {}
STREAM_POS = 1
local function w(_, v) STREAM[#STREAM + 1] = v end
local function r() local v = STREAM[STREAM_POS]; STREAM_POS = STREAM_POS + 1; return v end
streamWriteUInt8, streamWriteUInt16, streamWriteInt32, streamWriteFloat32, streamWriteBool = w, w, w, w, w
streamReadUInt8, streamReadUInt16, streamReadInt32, streamReadFloat32, streamReadBool = r, r, r, r, r
AutoDrive.streamWriteStringOrEmpty = function(_, s) w(nil, s or "") end
AutoDrive.streamReadStringOrEmpty = function() return r() end
Event = {new = function(mt) return setmetatable({}, mt) end}
function Class(t, base) return {__index = t} end
function InitEventClass() end

g_time = 0

-- additions for player owners, previews, notices, folders and routes import
streamWriteBool = function(_, v) STREAM[#STREAM + 1] = v; return v end
NetworkNode = {LOCAL_STREAM_ID = 0}
MathUtil = {vector2Length = function(x, z) return math.sqrt(x * x + z * z) end}
AutoDrive.getDebugChannelIsSet = function() return false end
AutoDrive.DC_ROADNETWORKINFO = 1
AutoDrive.angleBetween = function() return 0 end
AutoDrive.isEditorModeEnabled = function() return true end
AutoDrive.drawDistance = 50
g_currentMission = {userManager = {
    getUserByConnection = function(self, connection) return connection and connection.user end,
    getUserByUserId = function() return nil end
}}
MESSAGES = {}
ADMessagesManager = {messageTypes = {INFO = 1, WARN = 2, ERROR = 3}, addMessage = function(self, vehicle, messageType, text) table.insert(MESSAGES, text) end}

function deepCopy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = deepCopy(x) end
    return c
end
AutoDriveSync = {
    streamWriteGraph = function(streamId, w, m, g, c) STREAM[#STREAM + 1] = deepCopy({w = w, m = m, g = g, c = c}) end,
    streamReadGraph = function(streamId)
        local v = deepCopy(STREAM[STREAM_POS]); STREAM_POS = STREAM_POS + 1
        return v.w, v.m, v.g, v.c
    end
}

LOGS = {}
Logging.info = function(fmt, ...) table.insert(LOGS, string.format(fmt, ...)) end

-- Lua 5.1 (the game) has math.atan2, Lua 5.3+ only math.atan(y, x)
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
