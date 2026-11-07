EmptyHarvesterTask = ADInheritsFrom(AbstractTask)
EmptyHarvesterTask.debug = false

EmptyHarvesterTask.STATE_PATHPLANNING = {}
EmptyHarvesterTask.STATE_DRIVING = {}
EmptyHarvesterTask.STATE_UNLOADING = {}
EmptyHarvesterTask.STATE_REVERSING = {}
EmptyHarvesterTask.STATE_WAITING = {}
EmptyHarvesterTask.STATE_UNLOADING_FINISHED = {}

EmptyHarvesterTask.REVERSE_TIME = 30000
EmptyHarvesterTask.MAX_STUCK_TIME = 60000
EmptyHarvesterTask.WAITING_TIME = 7000
EmptyHarvesterTask.WAITING_FOR_PIPE = 1000
-- PropaineX edit: start following a combine that drives off after this long (ms; was 4000), in every stage of the
-- task; also how long it must have stood before that counts
EmptyHarvesterTask.FOLLOW_AFTER = 500

-- PropaineX edit: hand over to FollowCombineTask (active unloading), as AutoDrive did after 4 s
function EmptyHarvesterTask:switchToFollow()
    local mode = self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]
    mode.state = CombineUnloaderMode.STATE_ACTIVE_UNLOAD_COMBINE
    mode.breadCrumbs = Queue:new()
    mode.lastBreadCrumb = nil
    local followTask = FollowCombineTask:new(self.vehicle, self.combine)
    -- PropaineX edit (3.2.0.4): this unloader was called to a standing combine (see FollowCombineTask, standingCall)
    followTask.standingCall = true
    self.vehicle.ad.taskModule:addTask(followTask)
    self.vehicle.ad.taskModule:setCurrentTaskFinished(ADTaskModule.DONT_PROPAGATE)
end

-- PropaineX edit (3.2.0.4): arrived under the pipe of a standing combine. With Active unloading it goes straight
-- into chase mode (holding still while the combine stands), so there is no hand-over when the combine drives off.
-- Otherwise the old standing unload.
function EmptyHarvesterTask:startUnloading()
    if self:shouldStayWithCombine() then
        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask: arrived, active unloading -> chase mode")
        self:switchToFollow()
    else
        self.state = EmptyHarvesterTask.STATE_UNLOADING
    end
end

-- PropaineX edit: a combine (not a chopper) set to Active unloading, not turning or in a Courseplay pocket
function EmptyHarvesterTask:shouldStayWithCombine()
    local root = self.combine.getRootVehicle ~= nil and self.combine:getRootVehicle() or self.combine
    return self.combine.ad.isHarvester and AutoDrive.getSetting("activeUnloading", root) == true
        and not AutoDrive.combineIsTurning(self.combine) and not AutoDrive:getIsCPCombineInPocket(self.combine)
end

function EmptyHarvesterTask:new(vehicle, combine)
    local o = EmptyHarvesterTask:create()
    o.taskType = "EmptyHarvesterTask" -- PropaineX edit (3.6.1.4): ADUnloaderClear.isPlanning
    o.vehicle = vehicle
    o.combine = combine
    o.state = EmptyHarvesterTask.STATE_PATHPLANNING
    o.wayPoints = nil
    o.reverseStartLocation = nil
    o.stuckTimer = AutoDriveTON:new()
    o.reverseTimer = AutoDriveTON:new()
    o.waitTimer = AutoDriveTON:new()
    o.holdCPCombineTimer = AutoDriveTON:new()
    o.trailers = nil
    o.trailerCount = 0
    o.tractorTrainLength = 0
    EmptyHarvesterTask.setStateNames(o)
    return o
end

function EmptyHarvesterTask:setUp()
    EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:setUp")
    self.vehicle.ad.pathFinderModule:reset()
    self.vehicle.ad.pathFinderModule:startPathPlanningToPipe(self.combine, false)
    self.trailers, self.trailerCount = AutoDrive.getAllUnits(self.vehicle)
    self.tractorTrainLength = AutoDrive.getTractorTrainLength(self.vehicle, true, false)
    AutoDrive.setTrailerCoverOpen(self.vehicle, self.trailers, true)
end

function EmptyHarvesterTask:update(dt)
    if self.combine ~= nil and g_currentMission.nodeToObject[self.combine.components[1].node] == nil then
        self:finished()
        return
    end
    if self.lastState ~= self.state then
        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update %s -> %s", tostring(self:getStateName(self.lastState)), tostring(self:getStateName()))
        self.lastState = self.state
        self:resetAllTimers()
    end

    local checkForStuck = (self.vehicle.lastSpeedReal <= 0.0002) and (
        self.state == EmptyHarvesterTask.STATE_DRIVING
        or self.state == EmptyHarvesterTask.STATE_UNLOADING
    )

    self.stuckTimer:timer(checkForStuck, self.MAX_STUCK_TIME, dt)
    if self.stuckTimer:done()
        -- or AutoDrive.getDistanceBetween(self.vehicle, self.combine) < self.MIN_COMBINE_DISTANCE 
        then
        -- got stuck or to close to combine -> reverse
        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update - STATE_DRIVING stuck")
        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
        self.reverseStartLocation = {x = x, y = y, z = z}
        self.state = EmptyHarvesterTask.STATE_REVERSING
    end

    -- PropaineX edit: the standing combine drives off -> chase it right away, whatever stage we are in (planning,
    -- driving up, waiting for the pipe, unloading). Was only checked while unloading, after 4 s, standing still
    -- meanwhile, and it gave up when next to crop. Only once the combine has been seen standing in this task, as a
    -- moving combine that is nearly full is also sent here (it is about to stop).
    if self.combine.ad.noMovementTimer.elapsedTime > EmptyHarvesterTask.FOLLOW_AFTER then
        self.combineStood = true
    end
    if self.combineStood and self.combine.ad.driveForwardTimer.elapsedTime > EmptyHarvesterTask.FOLLOW_AFTER
        and (self.state == EmptyHarvesterTask.STATE_PATHPLANNING or self.state == EmptyHarvesterTask.STATE_DRIVING
            or self.state == EmptyHarvesterTask.STATE_UNLOADING) then
        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update combine drives off -> follow now (%s)", tostring(self:getStateName()))
        if self.state == EmptyHarvesterTask.STATE_PATHPLANNING then
            self.vehicle.ad.pathFinderModule:abort()
        end
        self:switchToFollow()
        return
    end

    -- PropaineX edit (3.6.0.4): no path to the pipe within PATH_TIMEOUT (searching plus the waits after a failed
    -- search) -> hand the job off or move aside and plan again (CombineUnloaderMode:onPathTimeout)
    if self.state == EmptyHarvesterTask.STATE_PATHPLANNING then
        self.pathWait = (self.pathWait or 0) + dt
        if self.pathWait > CombineUnloaderMode.PATH_TIMEOUT then
            self.pathWait = 0
            self.vehicle.ad.pathFinderModule:abort()
            self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:onPathTimeout()
            return
        end
    else
        self.pathWait = 0
    end

    if self.state == EmptyHarvesterTask.STATE_PATHPLANNING then
        if self.vehicle.ad.pathFinderModule:hasFinished() then
            self.wayPoints = self.vehicle.ad.pathFinderModule:getPath()
            self.vehicle.ad.drivePathModule:setWayPoints(self.wayPoints)
            if self.wayPoints == nil or #self.wayPoints == 0 then
                -- If the target/pipe location is blocked, we can issue a notification and stop the task - Otherwise we pause a moment and retry
                if self.vehicle.ad.pathFinderModule:isTargetBlocked() then
                    self:finished(ADTaskModule.DONT_PROPAGATE)
                    self.vehicle:stopAutoDrive()
                    AutoDriveMessageEvent.sendMessageOrNotification(self.vehicle, ADMessagesManager.messageTypes.WARN, "$l10n_AD_Driver_of; %s $l10n_AD_cannot_find_path; %s", 5000, self.vehicle.ad.stateModule:getName(), self.combine.ad.stateModule:getName())
                    return
                else
                    self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:notifyAboutFailedPathfinder()
                    -- Overdrive: no way around the crop (avoid fruit on): it stands still and plans again after the delay
                    self.noWayAroundCrop = self.vehicle.ad.pathFinderModule:isNoWayAroundCrop()
                    if self.noWayAroundCrop and not self.vehicle.ad.noWayAroundCropLogged then
                        self.vehicle.ad.noWayAroundCropLogged = true
                        local reasonText = g_i18n ~= nil and g_i18n:getText("AD_task_catch_no_way_around_crop") or "AD_task_catch_no_way_around_crop"
                        Logging.info("[AD] %s, unloading %s: %s (avoid fruit is on, not driving through the crop)", ADDiag.name(self.vehicle), ADDiag.name(self.combine), reasonText)
                    end
                    self.vehicle.ad.pathFinderModule:reset()
                    self.vehicle.ad.pathFinderModule:startPathPlanningToPipe(self.combine, false)
                    self.vehicle.ad.pathFinderModule:addDelayTimer(10000)
                end
            else
                self.noWayAroundCrop = false
                self.vehicle.ad.noWayAroundCropLogged = nil
                self.state = EmptyHarvesterTask.STATE_DRIVING
                return
            end
        else
            self.vehicle.ad.pathFinderModule:update(dt)
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
            return
        end
    elseif self.state == EmptyHarvesterTask.STATE_DRIVING then
        if self.vehicle.ad.drivePathModule:isTargetReached() then
            if AutoDrive:getIsCPActive(self.combine) then
                self.vehicle.ad.specialDrivingModule:stopVehicle()
                self.vehicle.ad.specialDrivingModule:update(dt)
                self.waitTimer:timer(self.combine:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF, EmptyHarvesterTask.WAITING_FOR_PIPE, dt)
                if self.waitTimer:done() then
                    self.waitTimer:timer(false)
                    self:startUnloading()
                end
            else
                self:startUnloading()
            end
            return
        else
            self.vehicle.ad.drivePathModule:update(dt)
        end
    elseif self.state == EmptyHarvesterTask.STATE_UNLOADING then
        self.vehicle.ad.specialDrivingModule.motorShouldNotBeStopped = true
        -- Stopping CP drivers for now
        AutoDrive:holdCPCombine(self.combine)
        -- (PropaineX edit: the check for the combine driving off is now at the top of update, for every stage)

        local combineFillLevel, _, _ = AutoDrive.getObjectFillLevels(self.combine)

        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update getDischargeState %s"
        , tostring(self.combine:getDischargeState())
        )
        if combineFillLevel > 0.1 and self.combine.getDischargeState ~= nil and self.combine:getDischargeState() ~= Dischargeable.DISCHARGE_STATE_OFF then
            EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update stopVehicle")
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
        else
            --Is the current trailer filled or is the combine empty?
            local _, _, filledToUnload = AutoDrive.getAllFillLevels(self.trailers)
            local distanceToCombine = AutoDrive.getDistanceBetween(self.vehicle, self.combine)

            -- PropaineX edit: combine emptied while standing, it unloads on the move (Active unloading) and we have
            -- room left: stay with it, so we are under the pipe when it fills again
            if combineFillLevel <= 0.1 and not filledToUnload and self:shouldStayWithCombine() then
                EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update combine empty, active unloading -> follow")
                self:switchToFollow()
                return
            end
            if combineFillLevel <= 0.1 or filledToUnload then
                EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update STATE_UNLOADING_FINISHED")
                self.state = EmptyHarvesterTask.STATE_UNLOADING_FINISHED
                return
            else
                -- Drive forward with collision checks active and only for a limited distance
                if distanceToCombine > 30 then
                    EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update distanceToCombine > 30")
                    self:finished()
                    return
                else
                    EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update driveForward")
                    self.vehicle.ad.specialDrivingModule:driveForward(dt)
                end
            end
        end
    elseif self.state == EmptyHarvesterTask.STATE_UNLOADING_FINISHED then
        EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:update - STATE_UNLOADING_FINISHED getIsCPCombineInPocket %s", tostring(AutoDrive:getIsCPCombineInPocket(self.combine)))
        if AutoDrive:getIsCPCombineInPocket(self.combine) or AutoDrive.combineIsTurning(self.combine) then
            -- reverse if CP unload in a pocket or pullback position
            -- reverse if combine is turning
            local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
            self.reverseStartLocation = {x = x, y = y, z = z}
            self.state = EmptyHarvesterTask.STATE_REVERSING
            return
        else
            self.state = EmptyHarvesterTask.STATE_WAITING
            return
        end
    elseif self.state == EmptyHarvesterTask.STATE_REVERSING then
        self.vehicle.ad.specialDrivingModule.motorShouldNotBeStopped = false
        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
        local distanceToReversStart = MathUtil.vector2Length(x - self.reverseStartLocation.x, z - self.reverseStartLocation.z)
        local overallLength
        if self.trailerCount <= 1 then
            overallLength = math.max(self.vehicle.size.length * 2, 15) -- 2x tractor length, min. 15m
        else
            overallLength = self.tractorTrainLength -- complete train length
        end
        if AutoDrive:getIsCPActive(self.combine) or self.combine:getIsAIActive() then
            -- if CP harvester
            overallLength = overallLength + AutoDrive.getFrontToolWidth(self.combine)
        end
        if self.combine.trailingVehicle ~= nil then
            -- if the harvester is trailed reverse 5m more
            -- overallLength = overallLength + 5
        end
        self.holdCPCombineTimer:timer(true, EmptyHarvesterTask.REVERSE_TIME, dt)
        if not self.holdCPCombineTimer:done() then
            -- Stopping CP drivers while reverse driving
            AutoDrive:holdCPCombine(self.combine)
        end
        self.reverseTimer:timer(true, EmptyHarvesterTask.REVERSE_TIME, dt)
        if (distanceToReversStart > overallLength) or self.reverseTimer:done() then
            self.state = EmptyHarvesterTask.STATE_WAITING
            return
        else
            self.vehicle.ad.specialDrivingModule:driveReverse(dt, 10, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
        end
    elseif self.state == EmptyHarvesterTask.STATE_WAITING then
        local waitTime = EmptyHarvesterTask.WAITING_TIME
        if AutoDrive:getIsCPActive(self.combine) or self.combine:getIsAIActive() then
            -- wait some more time to let CP combine move away
            waitTime = 3 * EmptyHarvesterTask.WAITING_TIME
        end
        self.waitTimer:timer(true, waitTime, dt)
        if self.waitTimer:done() or AutoDrive.isVehicleOrTrailerInCrop(self.vehicle, true) then
            self:finished()
            return
        else
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
            return
        end
    end
end

function EmptyHarvesterTask:abort()
end

function EmptyHarvesterTask:finished(propagate)
    EmptyHarvesterTask.debugMsg(self.vehicle, "EmptyHarvesterTask:finished()")
    self.vehicle.ad.specialDrivingModule.motorShouldNotBeStopped = false
    self.vehicle.ad.taskModule:setCurrentTaskFinished(propagate)
end

function EmptyHarvesterTask:getExcludedVehiclesForCollisionCheck()
    local excludedVehicles = {}
    if self.state == EmptyHarvesterTask.STATE_DRIVING then
        table.insert(excludedVehicles, self.combine:getRootVehicle())
    end
    return excludedVehicles
end

function EmptyHarvesterTask:setStateNames()
    if self.statesToNames == nil then
        self.statesToNames = {}
        for name, id in pairs(EmptyHarvesterTask) do
            if string.sub(name, 1, 6) == "STATE_" then
                self.statesToNames[id] = name
            end
        end
    end
end

function EmptyHarvesterTask:getStateName(state)
    local requestedState = state
    if requestedState == nil then
        requestedState = self.state
    end
    if requestedState == nil then
        Logging.error("[AD] EmptyHarvesterTask: Could not find name for state ->%s<- !", tostring(requestedState))
    end
    return self.statesToNames[requestedState] or ""
end

function EmptyHarvesterTask:resetAllTimers()
    -- self.stuckTimer:timer(false) -- stuckTimer reset by speed changes
    self.reverseTimer:timer(false)
    self.waitTimer:timer(false)
    self.holdCPCombineTimer:timer(false)
end

function EmptyHarvesterTask:getI18nInfo()
    local text = "$l10n_AD_task_unloading_combine;"
    local delayTime = self.vehicle.ad.pathFinderModule.delayTime or 0
    if self.state == EmptyHarvesterTask.STATE_PATHPLANNING and self.noWayAroundCrop and delayTime > 0 then
        -- Overdrive: waiting before planning again, no way around the crop
        text = text .. " - " .. "$l10n_AD_task_catch_no_way_around_crop;" .. string.format(" (%d s)", math.ceil(delayTime / 1000))
    elseif self.state == EmptyHarvesterTask.STATE_PATHPLANNING then
        local actualState, maxStates, steps, max_pathfinder_steps = self.vehicle.ad.pathFinderModule:getCurrentState()
        text = text .. " - " .. "$l10n_AD_task_pathfinding;" .. string.format(" %d / %d - %d / %d", actualState, maxStates, steps, max_pathfinder_steps)
    elseif self.state == EmptyHarvesterTask.STATE_DRIVING then
        text = text .. " - " .. "$l10n_AD_task_drive_to_combine_pipe;"
    elseif self.state == EmptyHarvesterTask.STATE_UNLOADING then
        text = text .. " - " .. "$l10n_AD_task_unloading_combine;"
    elseif self.state == EmptyHarvesterTask.STATE_REVERSING then
        text = text .. " - " .. "$l10n_AD_task_reversing_from_combine;"
    elseif self.state == EmptyHarvesterTask.STATE_WAITING then
        text = text .. " - " .. "$l10n_AD_task_waiting_for_room;"
    end
    return text 
end

function EmptyHarvesterTask.debugMsg(vehicle, debugText, ...)
    if EmptyHarvesterTask.debug == true then
        AutoDrive.debugMsg(vehicle, debugText, ...)
    else
        AutoDrive.debugPrint(vehicle, AutoDrive.DC_COMBINEINFO, debugText, ...)
    end
end
