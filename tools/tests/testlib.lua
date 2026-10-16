-- helpers shared by the server and client runtimes

function snapshot()
    local parts = {}
    for i, wp in ipairs(ADGraphManager.wayPoints) do
        parts[#parts + 1] = string.format("%d=%d:%.17g,%.17g,%.17g,%d,f%s|%s|%s", i, wp.id, wp.x, wp.y, wp.z, wp.flags, tostring(wp.fieldID), table.concat(wp.out, ","), table.concat(wp.incoming, ","))
    end
    parts[#parts + 1] = "#wp=" .. #ADGraphManager.wayPoints .. " #pairs=" .. table.count(ADGraphManager.wayPoints)
    for i, m in ipairs(ADGraphManager.mapMarkers) do
        parts[#parts + 1] = string.format("M%d:%d,%s,%s,%d", i, m.id, m.name, m.group, m.markerIndex)
    end
    parts[#parts + 1] = "#m=" .. #ADGraphManager.mapMarkers .. " #mpairs=" .. table.count(ADGraphManager.mapMarkers)
    local names = {}
    for name, _ in pairs(ADGraphManager.groups) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local color = ADGraphManager.groupColors[name]
        local colorText = color and string.format("%.3f,%.3f,%.3f", color[1], color[2], color[3]) or "-"
        parts[#parts + 1] = string.format("G %s=%d %s", name, ADGraphManager.groups[name], colorText)
    end
    for name, _ in pairs(ADGraphManager.groupColors) do
        if ADGraphManager.groups[name] == nil then
            parts[#parts + 1] = "orphan color " .. name
        end
    end
    return table.concat(parts, "\n")
end

function serialize(v)
    local t = type(v)
    if t == "number" then
        if math.type and math.type(v) == "integer" then
            return tostring(v)
        end
        return string.format("%.17g", v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(x)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("can not serialize " .. t)
end

function setupNetwork(n, seed)
    math.randomseed(seed)
    ADGraphManager:load()
    ADGraphManager.groups = {All = 1, G1 = 2, G2 = 3}
    local wps = {}
    for i = 1, n do
        wps[i] = ADGraphManager:createNode(i, math.random(0, 1000) + 0.25, 10, math.random(0, 1000) + 0.5, {}, {}, math.random(0, 1), nil, (math.random() < 0.3) and math.random(1, 5) or nil)
    end
    for i = 1, n * 2 do
        local a, b = math.random(1, n), math.random(1, n)
        if a ~= b and not table.contains(wps[a].out, b) then
            table.insert(wps[a].out, b)
            if math.random() < 0.85 then
                -- otherwise a reverse connection
                table.insert(wps[b].incoming, a)
            end
        end
    end
    ADGraphManager.wayPoints = wps
    local markers = {}
    for i = 1, math.floor(n / 4) do
        markers[i] = {id = math.random(1, n), markerIndex = i, name = "M" .. i, group = (i % 2 == 0) and "G1" or "All"}
    end
    ADGraphManager.mapMarkers = markers
end
