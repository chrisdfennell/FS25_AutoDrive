-- fleet overview: choose a destination for the selected vehicle (AutoDriveSendToEvent)
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

function ADSendToGui:setVehicle(vehicle)
    self.vehicle = vehicle
end

function ADSendToGui:onOpen()
    ADSendToGui:superClass().onOpen(self)
    self.targets = ADSendToGui.getTargets(self.vehicle)
    if self.titleText ~= nil and self.vehicle ~= nil and self.vehicle.ad ~= nil then
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
        cell.attributes.listItemText:setText(ADSendToGui.getRowText(self.targets[index]))
        cell.target = self
    end
end

function ADSendToGui:send(index)
    local target = self.targets[index]
    if target ~= nil and self.vehicle ~= nil then
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
