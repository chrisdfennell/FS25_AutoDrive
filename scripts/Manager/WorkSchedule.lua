-- Work schedule: vehicles start their AutoDrive job at a set hour and stop at another one.
-- Pickup & deliver finishes the round it is on and then parks, other modes stop right away.
-- The hours are the vehicle settings scheduleStart / scheduleStop. Runs on the server.

ADWorkSchedule = {}

ADWorkSchedule.CHECK_INTERVAL = 1000
ADWorkSchedule.START = 1
ADWorkSchedule.STOP = 2

function ADWorkSchedule:load()
    self.lastHour = nil
    self.timer = 0
end

-- in-game hour 0..23, nil before the mission is ready
function ADWorkSchedule.getHour()
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment == nil or environment.dayTime == nil then
        return nil
    end
    return math.floor(environment.dayTime / 3600000) % 24
end

-- hour setting of the vehicle, nil if not set
function ADWorkSchedule.getHourSetting(name, vehicle)
    local hour = AutoDrive.getSetting(name, vehicle)
    if hour == nil or hour < 0 then
        return nil
    end
    return hour
end

-- the time went from lastHour to hour (can be several hours, e.g. after sleeping):
-- START or STOP if a schedule hour was passed (the later one if both), nil otherwise
function ADWorkSchedule.getAction(startHour, stopHour, lastHour, hour)
    if lastHour == nil or hour == nil or lastHour == hour then
        return nil
    end
    -- hours passed after lastHour, up to and including hour
    local function passedAt(h)
        if h == nil then
            return nil
        end
        local steps = (h - lastHour) % 24
        local total = (hour - lastHour) % 24
        if steps > 0 and steps <= total then
            return steps
        end
        return nil
    end
    local startAt, stopAt = passedAt(startHour), passedAt(stopHour)
    if startAt ~= nil and (stopAt == nil or startAt > stopAt) then
        return ADWorkSchedule.START
    elseif stopAt ~= nil then
        return ADWorkSchedule.STOP
    end
    return nil
end

function ADWorkSchedule.isStopRequested(vehicle)
    return vehicle ~= nil and vehicle.ad ~= nil and vehicle.ad.scheduleStopRequested == true
end

function ADWorkSchedule:update(dt)
    if g_server == nil then
        return
    end
    self.timer = (self.timer or 0) + dt
    if self.timer < ADWorkSchedule.CHECK_INTERVAL then
        return
    end
    self.timer = 0

    local hour = ADWorkSchedule.getHour()
    if hour == nil then
        return
    end
    local lastHour = self.lastHour
    self.lastHour = hour

    for _, vehicle in pairs(AutoDrive.getAllVehicles() or {}) do
        if vehicle.ad ~= nil and vehicle.ad.stateModule ~= nil then
            local active = vehicle.ad.stateModule:isActive()
            if not active then
                vehicle.ad.scheduleStopRequested = nil
            end
            local action = ADWorkSchedule.getAction(ADWorkSchedule.getHourSetting("scheduleStart", vehicle), ADWorkSchedule.getHourSetting("scheduleStop", vehicle), lastHour, hour)
            if action == ADWorkSchedule.START and not active then
                self:start(vehicle)
            elseif action == ADWorkSchedule.STOP and active then
                self:stop(vehicle)
            end
        end
    end
end

function ADWorkSchedule:start(vehicle)
    if ADGraphManager:getWayPointById(1) == nil or vehicle.ad.stateModule:getFirstMarker() == nil then
        return
    end
    vehicle.ad.scheduleStopRequested = nil
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
    ADInputManager:input_start_stop(vehicle, farmId)
    AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_schedule_started;", 5000, vehicle.ad.stateModule:getName())
end

function ADWorkSchedule:stop(vehicle)
    if vehicle.ad.stateModule:getMode() == AutoDrive.MODE_PICKUPANDDELIVER then
        -- finish the round, then park (PickupAndDeliverMode / ParkTask check isStopRequested)
        vehicle.ad.scheduleStopRequested = true
        AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_schedule_finishing;", 5000, vehicle.ad.stateModule:getName())
    else
        local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or nil
        ADInputManager:input_start_stop(vehicle, farmId)
        AutoDriveMessageEvent.sendMessageOrNotification(vehicle, ADMessagesManager.messageTypes.INFO, "$l10n_AD_Driver_of; %s $l10n_AD_schedule_stopped;", 5000, vehicle.ad.stateModule:getName())
    end
end

-- e.g. "06:00 - 20:00" for the fleet overview, nil without a schedule
function ADWorkSchedule.getText(vehicle)
    local startHour = ADWorkSchedule.getHourSetting("scheduleStart", vehicle)
    local stopHour = ADWorkSchedule.getHourSetting("scheduleStop", vehicle)
    if startHour == nil and stopHour == nil then
        return nil
    end
    local function hourText(h)
        if h == nil then
            return "--:--"
        end
        return string.format("%02d:00", h)
    end
    return hourText(startHour) .. " - " .. hourText(stopHour)
end
