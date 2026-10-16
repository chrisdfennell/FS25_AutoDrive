-- fleet overview: every AutoDrive vehicle of the player's farm with mode, destination, load, fuel and state
ADFleetGui = {}
ADFleetGui.debug = false
ADFleetGui.REFRESH_INTERVAL = 1000
-- a multiplayer client asks the server for the driver statistics this often while the list shows them
ADFleetGui.STATS_REQUEST_INTERVAL = 2000

local ADFleetGui_mt = Class(ADFleetGui, DialogElement)

function ADFleetGui.new(target)
    local self = DialogElement.new(target, ADFleetGui_mt)
    self:include(ADGuiDebugMixin)
    self.rows = {}
    self.refreshTimer = 0
    self.statsRequestTimer = 0
    self.showStatistics = false
    return self
end

-- fill level of all trailers / units in percent, nil without capacity
function ADFleetGui.getLoadPercent(vehicle)
    local units = AutoDrive.getAllUnits(vehicle)
    if units == nil or #units == 0 then
        return nil
    end
    local fillLevel, fillCapacity = AutoDrive.getAllFillLevels(units)
    if fillCapacity == nil or fillCapacity <= 0 then
        return nil
    end
    return 100 * fillLevel / fillCapacity
end

-- lowest level of the vehicle's own consumables (fuel, electric charge, methane, DEF) in percent
function ADFleetGui.getFuelPercent(vehicle)
    local spec = vehicle.spec_motorized
    if spec == nil or spec.consumersByFillTypeName == nil or vehicle.getFillUnitFillLevelPercentage == nil then
        return nil
    end
    local lowest
    for _, consumer in pairs(spec.consumersByFillTypeName) do
        if consumer.fillUnitIndex ~= nil then
            local percent = 100 * vehicle:getFillUnitFillLevelPercentage(consumer.fillUnitIndex)
            if lowest == nil or percent < lowest then
                lowest = percent
            end
        end
    end
    return lowest
end

function ADFleetGui.getDestinationText(vehicle)
    local stateModule = vehicle.ad.stateModule
    local first = stateModule:getFirstMarkerName() or ""
    local mode = stateModule:getMode()
    if mode == AutoDrive.MODE_PICKUPANDDELIVER or mode == AutoDrive.MODE_DELIVERTO then
        local second = stateModule:getSecondMarkerName() or ""
        if mode == AutoDrive.MODE_DELIVERTO then
            return second
        end
        return first .. " > " .. second
    end
    return first
end

-- newest warning or error of the notification history for the vehicle
function ADFleetGui.getLastProblem(vehicle)
    for _, item in ipairs(ADMessagesManager:getHistory() or {}) do
        if item.vehicle == vehicle and item.messageType ~= nil and item.messageType ~= ADMessagesManager.messageTypes.INFO then
            return item
        end
    end
    return nil
end

function ADFleetGui.getRow(vehicle)
    local stateModule = vehicle.ad.stateModule
    local row = {vehicle = vehicle, name = stateModule:getName() or "", active = stateModule:isActive()}
    local parts = {row.name, AutoDrive.Hud:getModeName(vehicle), ADFleetGui.getDestinationText(vehicle)}

    local load = ADFleetGui.getLoadPercent(vehicle)
    if load ~= nil then
        table.insert(parts, string.format(g_i18n:getText("AD_fleet_load"), string.format("%d%%", math.floor(load + 0.5))))
    end
    local fuel = ADFleetGui.getFuelPercent(vehicle)
    if fuel ~= nil then
        table.insert(parts, string.format(g_i18n:getText("AD_fleet_fuel"), string.format("%d%%", math.floor(fuel + 0.5))))
    end

    local state
    row.icon = "ad_gui.info_icon"
    if row.active then
        state = stateModule:getCurrentLocalizedTaskInfo()
        if state == nil or state == "" then
            state = g_i18n:getText("AD_fleet_driving")
        end
    else
        state = g_i18n:getText("AD_fleet_stopped")
        local problem = ADFleetGui.getLastProblem(vehicle)
        if problem ~= nil then
            state = state .. ": " .. tostring(problem.text)
            row.icon = ADNotificationsHistoryGui.ICON_SLICES[problem.messageType] or "ad_gui.warn_icon"
        end
    end
    local schedule = ADWorkSchedule.getText(vehicle)
    if schedule ~= nil then
        table.insert(parts, schedule)
    end
    table.insert(parts, state)
    row.text = table.concat(parts, "  |  ")
    row.statsText = row.name .. "  |  " .. ADStatistics.getText(vehicle.ad.stats)
    return row
end

-- AutoDrive vehicles of the local player's farm, by name. The order must not depend on the state:
-- the list refreshes every second and the selected row has to stay on the same vehicle
function ADFleetGui.getRows()
    local farmId
    if g_localPlayer ~= nil and g_localPlayer.getFarmId ~= nil then
        farmId = g_localPlayer:getFarmId()
    end
    local rows = {}
    for _, vehicle in pairs(AutoDrive.getAllVehicles() or {}) do
        if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil and (farmId == nil or vehicle.getOwnerFarmId == nil or vehicle:getOwnerFarmId() == farmId) then
            table.insert(rows, ADFleetGui.getRow(vehicle))
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return (a.vehicle.rootNode or 0) < (b.vehicle.rootNode or 0)
    end)
    return rows
end

function ADFleetGui:onOpen()
    ADFleetGui:superClass().onOpen(self)
    self.vehicleList:setDataSource(self)
    self:updateButtons()
    if self.showStatistics then
        AutoDriveStatisticsEvent.request()
    end
    self:refreshItems()
end

-- the list shows either the current state or the driver statistics
function ADFleetGui:updateButtons()
    if self.viewButton ~= nil then
        if self.showStatistics then
            self.viewButton:setText(g_i18n:getText("button_ad_status"))
        else
            self.viewButton:setText(g_i18n:getText("button_ad_statistics"))
        end
    end
    if self.actionButton ~= nil then
        if self.showStatistics then
            self.actionButton:setText(g_i18n:getText("button_ad_resetStatistics"))
        else
            self.actionButton:setText(g_i18n:getText("button_ad_startStop"))
        end
    end
end

function ADFleetGui:onClickView()
    self.showStatistics = not self.showStatistics
    self:updateButtons()
    if self.showStatistics then
        AutoDriveStatisticsEvent.request()
        self.statsRequestTimer = 0
    end
    self:refreshItems()
end

function ADFleetGui:refreshItems()
    self.rows = ADFleetGui.getRows()
    self.refreshTimer = 0
    self.vehicleList:reloadData()
end

function ADFleetGui:update(dt)
    ADFleetGui:superClass().update(self, dt)
    self.refreshTimer = self.refreshTimer + dt
    if self.refreshTimer > ADFleetGui.REFRESH_INTERVAL then
        self:refreshItems()
    end
    if self.showStatistics then
        self.statsRequestTimer = self.statsRequestTimer + dt
        if self.statsRequestTimer > ADFleetGui.STATS_REQUEST_INTERVAL then
            self.statsRequestTimer = 0
            AutoDriveStatisticsEvent.request()
        end
    end
end

function ADFleetGui:getNumberOfItemsInSection(list, section)
    if list == self.vehicleList then
        return #self.rows
    end
    return 0
end

function ADFleetGui:populateCellForItemInSection(list, section, index, cell)
    if list == self.vehicleList then
        local row = self.rows[index]
        cell.attributes.listItemIcon:setImageSlice(nil, row.icon)
        if self.showStatistics then
            cell.attributes.listItemText:setText(row.statsText)
        else
            cell.attributes.listItemText:setText(row.text)
        end
        cell.target = self
    end
end

function ADFleetGui:getSelectedVehicle()
    local row = self.rows[self.vehicleList:getSelectedIndexInSection()]
    if row ~= nil and row.vehicle ~= nil and row.vehicle.ad ~= nil then
        return row.vehicle
    end
    return nil
end

function ADFleetGui:enterVehicle(vehicle)
    if vehicle ~= nil then
        self:onClickBack()
        AutoDrive.requestToEnterVehicle(vehicle)
    end
end

function ADFleetGui:onDoubleClick(list, section, index, cell)
    local row = self.rows[index]
    if row ~= nil then
        self:enterVehicle(row.vehicle)
    end
end

function ADFleetGui:onClickEnter()
    self:enterVehicle(self:getSelectedVehicle())
end

function ADFleetGui:onClickStartStop()
    local vehicle = self:getSelectedVehicle()
    if vehicle ~= nil and self.showStatistics then
        -- in the statistics view this button resets the selected vehicle's numbers
        AutoDriveStatisticsEvent.requestReset(vehicle)
        self:refreshItems()
    elseif vehicle ~= nil then
        local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        ADInputManager:onInputCall(vehicle, "input_start_stop", farmId)
    end
end
