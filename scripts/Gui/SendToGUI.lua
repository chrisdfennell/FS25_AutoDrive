-- fleet overview: choose a destination for the selected vehicle (AutoDriveSendToEvent)
-- waypoint panel: the other way round, choose a vehicle of the farm for a target (setTarget)
ADSendToGui = {}
ADSendToGui.debug = false

local ADSendToGui_mt = Class(ADSendToGui, DialogElement)

function ADSendToGui.new(target)
    local self = DialogElement.new(target, ADSendToGui_mt)
    self:include(ADGuiDebugMixin)
    self.targets = {}
    return self
end

-- all targets except debug markers, by folder and name; distance from the vehicle as the crow flies
function ADSendToGui.getTargets(vehicle)
    local x, z
    if vehicle ~= nil and vehicle.components ~= nil then
        x, _, z = getWorldTranslation(vehicle.components[1].node)
    end
    local targets = {}
    for markerIndex, marker in pairs(ADGraphManager:getMapMarkers()) do
        local wp = ADGraphManager:getWayPointById(marker.id)
        if wp ~= nil and not marker.isADDebug then
            local folder = ""
            if marker.group ~= nil and marker.group ~= "All" then
                folder = marker.group
            end
            local distance
            if x ~= nil then
                distance = MathUtil.vector2Length(wp.x - x, wp.z - z)
            end
            table.insert(targets, {markerIndex = markerIndex, name = marker.name, folder = folder, distance = distance})
        end
    end
    table.sort(targets, function(a, b)
        if a.folder ~= b.folder then
            return string.lower(a.folder) < string.lower(b.folder)
        end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return targets
end

function ADSendToGui.getRowText(target)
    local text = target.name
    if target.folder ~= "" then
        text = target.folder .. " > " .. text
    end
    if target.distance ~= nil then
        text = text .. string.format("  (%.1f km)", target.distance / 1000)
    end
    return text
end

-- the AutoDrive vehicles of the player's farm, nearest to the target first
function ADSendToGui.getVehicles(markerIndex)
    local marker = ADGraphManager:getMapMarkerById(markerIndex)
    local wp = marker ~= nil and ADGraphManager:getWayPointById(marker.id) or nil
    local vehicles = {}
    for _, vehicle in ipairs(ADFleetMap.getVehicles()) do
        local distance
        if wp ~= nil and vehicle.components ~= nil and vehicle.components[1] ~= nil then
            local x, _, z = getWorldTranslation(vehicle.components[1].node)
            distance = MathUtil.vector2Length(wp.x - x, wp.z - z)
        end
        table.insert(vehicles, {vehicle = vehicle, name = vehicle.ad.stateModule:getName() or "", distance = distance,
            busy = vehicle.ad.stateModule:isActive()})
    end
    table.sort(vehicles, function(a, b)
        if (a.distance ~= nil) ~= (b.distance ~= nil) then
            return a.distance ~= nil
        end
        if a.distance ~= nil and a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return vehicles
end

function ADSendToGui.getVehicleRowText(entry)
    local text = entry.name
    if entry.distance ~= nil then
        text = text .. string.format("  (%.1f km)", entry.distance / 1000)
    end
    if entry.busy then
        text = text .. "  - " .. g_i18n:getText("AD_sendTo_busy")
    end
    return text
end

-- choose a destination for this vehicle
function ADSendToGui:setVehicle(vehicle)
    self.vehicle = vehicle
    self.markerIndex = nil
end

-- choose a vehicle for this target
function ADSendToGui:setTarget(markerIndex)
    self.vehicle = nil
    self.markerIndex = markerIndex
end

function ADSendToGui:onOpen()
    ADSendToGui:superClass().onOpen(self)
    if self.markerIndex ~= nil then
        self.targets = ADSendToGui.getVehicles(self.markerIndex)
        local marker = ADGraphManager:getMapMarkerById(self.markerIndex)
        if self.titleText ~= nil and marker ~= nil then
            self.titleText:setText(string.format(g_i18n:getText("gui_ad_sendToTitleTarget"), marker.name))
        end
    else
        self.targets = ADSendToGui.getTargets(self.vehicle)
    end
    if self.markerIndex == nil and self.titleText ~= nil and self.vehicle ~= nil and self.vehicle.ad ~= nil then
        self.titleText:setText(string.format(g_i18n:getText("gui_ad_sendToTitleVehicle"), self.vehicle.ad.stateModule:getName()))
    end
    self.targetList:setDataSource(self)
    self.targetList:reloadData()
end

function ADSendToGui:getNumberOfItemsInSection(list, section)
    if list == self.targetList then
        return #self.targets
    end
    return 0
end

function ADSendToGui:populateCellForItemInSection(list, section, index, cell)
    if list == self.targetList then
        cell.attributes.listItemIcon:setImageSlice(nil, "ad_gui.info_icon")
        if self.markerIndex ~= nil then
            cell.attributes.listItemText:setText(ADSendToGui.getVehicleRowText(self.targets[index]))
        else
            cell.attributes.listItemText:setText(ADSendToGui.getRowText(self.targets[index]))
        end
        cell.target = self
    end
end

function ADSendToGui:send(index)
    local target = self.targets[index]
    if target ~= nil and self.markerIndex ~= nil then
        AutoDriveSendToEvent.sendEvent(target.vehicle, self.markerIndex)
        self:onClickBack()
    elseif target ~= nil and self.vehicle ~= nil then
        AutoDriveSendToEvent.sendEvent(self.vehicle, target.markerIndex)
        self:onClickBack()
    end
end

function ADSendToGui:onDoubleClick(list, section, index, cell)
    self:send(index)
end

function ADSendToGui:onClickSend()
    self:send(self.targetList:getSelectedIndexInSection())
end
