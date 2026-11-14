FollowCombineTask = ADInheritsFrom(AbstractTask)
FollowCombineTask.debug = false

FollowCombineTask.STATE_CHASING = {}
FollowCombineTask.STATE_WAIT_FOR_TURN = {}
FollowCombineTask.STATE_REVERSING = {}
FollowCombineTask.STATE_REVERSING_FROM_CHOPPER = {}
FollowCombineTask.STATE_WAIT_FOR_PASS_BY = {}
FollowCombineTask.STATE_FINISHED = {}
FollowCombineTask.STATE_WAIT_BEFORE_FINISH = {}
FollowCombineTask.STATE_WAIT_FOR_COMBINE_TO_PASS_BY = {}
FollowCombineTask.STATE_GENERATE_UTURN_PATH = {}
FollowCombineTask.STATE_DRIVE_UTURN_PATH = {}
-- PropaineX edit (3.8.0.4): pull forward out of the combine's tail swing at a turn
FollowCombineTask.STATE_CLEAR_FORWARD = {}
FollowCombineTask.NO_FLOW_TIME = 2000 -- ms, PropaineX edit (3.8.2.4): nothing going in at a standing combine -> reposition
FollowCombineTask.TAIL_CLEARANCE = 3       -- m, PropaineX edit (3.8.3.4, 3 m in 3.8.4.4): combine's rear corner this close -> pull forward
FollowCombineTask.CLEAR_EXTRA = 6           -- m beyond the combine's length to pull forward
FollowCombineTask.CLEAR_MAX_TIME = 15000    -- ms
FollowCombineTask.CLEAR_BLOCKED_TIME = 3000 -- ms not moving while pulling forward -> back out instead
FollowCombineTask.GO_AROUND_TIME = 10000    -- ms, PropaineX edit (od.55): stuck at a standing harvester -> drive round it

FollowCombineTask.MAX_REVERSE_DISTANCE = 20
FollowCombineTask.MIN_COMBINE_DISTANCE = 25
FollowCombineTask.MAX_REVERSE_TIME = 30000
FollowCombineTask.MAX_TURN_TIME = 60000
FollowCombineTask.MAX_STUCK_TIME = 60000
FollowCombineTask.WAIT_BEFORE_FINISH_TIME = 8000

function FollowCombineTask:new(vehicle, combine)
    local o = FollowCombineTask:create()
    o.vehicle = vehicle
    o.combine = combine
    o.state = FollowCombineTask.STATE_CHASING
    o.reverseStartLocation = nil
    o.angleWrongTimer = AutoDriveTON:new()
    o.waitForTurnTimer = AutoDriveTON:new()
    o.stuckTimer = AutoDriveTON:new()
    o.dischargeTimer = AutoDriveTON:new()
    o.fillingTimer = AutoDriveTON:new()
    o.lastChaseSide = -10
    o.waitForPassByTimer = AutoDriveTON:new()
    o.chaseTimer = AutoDriveTON:new()
    o.startedChasing = false
    o.reverseTimer = AutoDriveTON:new()
    o.waitTimer = AutoDriveTON:new()
    o.chasePos, o.chaseSide = vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getPipeChasePosition()
    o.angleToCombineHeading = vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getAngleToCombineHeading()
    o.angleToCombine = vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getAngleToCombine()
    o.trailers = nil
    o.combineRootVehicle = o.combine:getRootVehicle()
    o.activeUnloading = AutoDrive.getSetting("activeUnloading", o.combineRootVehicle)
    FollowCombineTask.setStateNames(o)
    return o
end

function FollowCombineTask:setUp()
    FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask setUp")
    self.lastChaseSide = self.chaseSide
    self.pushedOutSide = nil -- PropaineX edit (od.59)
    self.trailers, _ = AutoDrive.getAllUnits(self.vehicle)
    self.activeUnloading = AutoDrive.getSetting("activeUnloading", self.combineRootVehicle)
    AutoDrive.setTrailerCoverOpen(self.vehicle, self.trailers, true)
end

function FollowCombineTask:update(dt)
    if self.combine == nil or g_currentMission.nodeToObject[self.combine.components[1].node] == nil then
        self:finished()
        return
    end

    self:updateStates(dt)

    -- PropaineX edit (od.58): END OF ROW. Before everything else (pipe lock included): header up or off = end of the
    -- row, stand where we are until it is down and on again.
    if self:updateEndOfRowWait(dt) then
        return
    end

    -- PropaineX edit (3.9.0.4): PIPE LOCK. Active unloading on a combine (not a forage harvester): under the pipe, at
    -- the pipe's speed, all the time. None of the turn / pass-by / reverse / pull-forward / wrong-side handling below.
    if self:isPipeLock() then
        self:updatePipeLock(dt)
        return
    end

    if self.lastState ~= self.state then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update %s -> %s", tostring(self:getStateName(self.lastState)), tostring(self:getStateName()))
        self.lastState = self.state
        self:resetAllTimers()
    end

    local checkForStuck = (self.vehicle.lastSpeedReal <= 0.0002) and (
        self.state == FollowCombineTask.STATE_CHASING
        or self.state == FollowCombineTask.STATE_WAIT_FOR_TURN
        or self.state == FollowCombineTask.STATE_WAIT_FOR_COMBINE_TO_PASS_BY
        or self.state == FollowCombineTask.STATE_GENERATE_UTURN_PATH
        or self.state == FollowCombineTask.STATE_DRIVE_UTURN_PATH
    )

    self.stuckTimer:timer(checkForStuck, self.MAX_STUCK_TIME, dt)
    if self.stuckTimer:done()
        -- or AutoDrive.getDistanceBetween(self.vehicle, self.combine) < self.MIN_COMBINE_DISTANCE 
        then
        -- got stuck or to close to combine -> reverse
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update - STATE_DRIVING stuck")
        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
        self.reverseStartLocation = {x = x, y = y, z = z}
        if self.combine.ad.isChopper then
            self.state = FollowCombineTask.STATE_REVERSING_FROM_CHOPPER
        else
            self.state = FollowCombineTask.STATE_REVERSING -- reverse to get room from harvester
        end
    end

    self:sampleCombineHeading(dt) -- PropaineX edit (3.8.5.4)
    -- PropaineX edit (3.8.4.4): tail check also while waiting for the turn (at a corner it was already waiting and got
    -- pinned). 3.8.5.4: ONLY in a real turn (WAIT_FOR_TURN is entered past TURN_ANGLE, 47 deg), never while chasing:
    -- it fired on lane changes and veered the truck off
    if self.state == FollowCombineTask.STATE_WAIT_FOR_TURN or self.state == FollowCombineTask.STATE_WAIT_FOR_COMBINE_TO_PASS_BY then
        local gap = self:tailSwingsAtUs()
        if gap ~= nil and self:isOutsideOfTurn() and self.chaseSide ~= AutoDrive.CHASEPOS_REAR then
            self:startClearForward(string.format("combine's tail %.1f m away", gap))
            return
        end
    end

    if self.state == FollowCombineTask.STATE_CHASING then
        self.chaseTimer:timer(true, 4000, dt)
        self.clearedThisTurn = nil -- PropaineX edit (3.8.4.4)

        if self.combine.ad.isChopper then
            if self.filled and self.chaseSide ~= nil and self.chaseSide ~= AutoDrive.CHASEPOS_REAR then
                --skip reversing
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - filled chopper")
                self.state = FollowCombineTask.STATE_FINISHED -- finish immediate
                return
            elseif self.filled and self.chaseSide ~= nil and self.chaseSide == AutoDrive.CHASEPOS_REAR then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING CHASEPOS_REAR - filled chopper")
                local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
                self.reverseStartLocation = {x = x, y = y, z = z}
                self.state = FollowCombineTask.STATE_REVERSING -- reverse to get room from harvester
                return
            end
        elseif self.filled or (self.combine.ad.isHarvester and self.combineFillPercent <= 0.1 and (not self.activeUnloading)) then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - filled harvester")
            self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH -- unload after some time to let harvester drive away
            return
        end

        -- PropaineX edit (3.2.0.4): called to a standing combine: while it stands, chase it at its speed (zero), i.e.
        -- hold still under the pipe; no stuck/angle timers meanwhile. The moment it rolls, the normal chase below runs.
        -- (3.2.1.4: for every Active unloading combine that stands, once we are at the pipe: within 3 m of the chase
        -- point, or arrived there by a standing call)
        -- PropaineX edit (3.7.0.4): a standing call only counts until the combine first rolls; after that only the 3 m
        -- check does (it stuck for the whole task, so a truck left far behind held still at a combine that stopped again)
        if self.combine.lastSpeedReal > 0.0004 then
            self.standingCall = false
            self.creepAnchor = nil -- PropaineX edit (3.8.2.4)
        end
        -- PropaineX edit (3.8.2.4): after creeping along the trailer we are at the pipe, however far from the chase point
        local nearPipe = self.standingCall or self.creepAnchor
        if not nearPipe and self.chasePos ~= nil then
            local vx, _, vz = getWorldTranslation(self.vehicle.components[1].node)
            nearPipe = MathUtil.vector2Length(vx - self.chasePos.x, vz - self.chasePos.z) < 3
        end
        -- PropaineX edit (3.8.2.4): hold still only while grain goes in (or there is nothing to take / no room). Grain
        -- in the combine, room in the trailer, but nothing going in for NO_FLOW_TIME (the part under the pipe is heaped
        -- full) -> creep to the chase point, which follows the next free part of the trailer; flow again -> hold.
        local flowing = self.combine.getDischargeState ~= nil and self.combine:getDischargeState() == Dischargeable.DISCHARGE_STATE_OBJECT
        if flowing then
            self.noFlowTime = 0
            self.creepForward = nil
            self.creepTurned = nil
        else
            self.noFlowTime = (self.noFlowTime or 0) + dt
        end
        local reposition = (self.combineFillPercent or 0) > 0.1 and not self.filled and self.noFlowTime > FollowCombineTask.NO_FLOW_TIME
        if self.activeUnloading and self.combine.ad.isHarvester and nearPipe and reposition and self.combine.lastSpeedReal <= 0.0004 then
            self.stuckTimer:timer(false)
            self.angleWrongTimer:timer(false)
            self:creepUnderPipe(dt)
            return
        end
        if self.activeUnloading and self.combine.ad.isHarvester and nearPipe and self.combine.lastSpeedReal <= 0.0004 then
            self.stuckTimer:timer(false)
            self.angleWrongTimer:timer(false)
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
            return
        end

        local wrongChopperHeading = self.combine.ad.isChopper and (self.angleToCombineHeading > 90 and self.distanceToCombine < 30)

        if (self.angleWrongTimer.elapsedTime > 15000) or wrongChopperHeading then
            -- if stuck with harvester - try reverse
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - stuck -> stuckTimer:%s angleWrongTimer:%s"
            , tostring(self.stuckTimer:done()), tostring(self.angleWrongTimer.elapsedTime > 15000))
            local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
            self.reverseStartLocation = {x = x, y = y, z = z}
            if self.combine.ad.isChopper then
                self.state = FollowCombineTask.STATE_REVERSING_FROM_CHOPPER
                return
            else
                self.state = FollowCombineTask.STATE_REVERSING -- reverse to get room from harvester
                return
            end
        end

        -- PropaineX edit (3.7.1.4): combine moving (Active unloading): on the wrong side it keeps driving round to its
        -- side instead of quitting (catch-up now hands straight back to chase, that would loop standing still); only
        -- ahead of the combine it quits as before (the turn task that follows drives round to get behind it)
        local activeMoving = CatchCombinePipeTask.isActiveMoving(self.combine)
        if activeMoving and CatchCombinePipeTask.isInFront(self.vehicle) then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - ahead of the moving combine -> finished")
            self:finished()
            return
        end
        if not activeMoving and not self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:isUnloaderOnCorrectSide() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - not UnloaderOnCorrectSide -> finished")
            self:finished()
            return
        end

        -- PropaineX edit (3.2.1.4): not the "over 90 % and closer than 25 m -> reverse" part with Active unloading on
        -- (3.2.0.4 only skipped it for a standing call; a moving combine over 90 % still made it back away)
        -- PropaineX edit (3.7.0.4): a turn only counts past TURN_ANGLE (see isRealTurn); was any CP manoeuvre / turn flag
        local realTurn = self:isRealTurn(AutoDrive.combineIsTurning(self.combine))
        if self.combine.ad.isHarvester and ((not self.activeUnloading and self.combineFillPercent > 90 and AutoDrive.getDistanceBetween(self.vehicle, self.combine) < self.MIN_COMBINE_DISTANCE) -- if to close -> reverse
            or (realTurn and AutoDrive:getIsCPTurning(self.combine)))
            then
            -- Stop chasing and wait for a normal unload call while standing
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - to close to harvester -> reverse")
            local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
            self.reverseStartLocation = {x = x, y = y, z = z}
            self.state = FollowCombineTask.STATE_REVERSING -- reverse to get room from harvester
            return
        end

        if not activeMoving and (not self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:isUnloaderOnCorrectSide(self.chaseSide)) and (not realTurn) then
            if self.lastChaseSide ~= CombineUnloaderMode.CHASEPOS_REAR then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - switching chase side from side to elsewhere - let's wait for passby next")
                self.state = FollowCombineTask.STATE_WAIT_FOR_PASS_BY
                return
            end
        end

        local movingDirection = self.combine.movingDirection
        if self.combine.ad.isReverseAttached then
            movingDirection = -self.combine.movingDirection
        end
        if realTurn then
            -- harvester turns
            --print("Waiting for turn now - 1- t:" ..  tostring(AutoDrive.combineIsTurning(self.combine)) .. " anglewrongtimer: " .. tostring(self.angleWrongTimer.elapsedTime > 10000))      
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CHASING - combineIsTurning")
            self.state = FollowCombineTask.STATE_WAIT_FOR_TURN
            return
        elseif ((self.combine.lastSpeedReal *  movingDirection) <= -0.00005) then
            self.vehicle.ad.specialDrivingModule:driveReverse(dt, self.combine.lastSpeedReal * 3600 * 1.3, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
        else
            self:followChasePoint(dt)
        end
    elseif self.state == FollowCombineTask.STATE_WAIT_FOR_TURN then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN")
        self.waitForTurnTimer:timer(true, self.MAX_TURN_TIME, dt)
        if self.waitForTurnTimer:done() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combine turn took to long - set finished now")
            self.state = FollowCombineTask.STATE_FINISHED
            return
        end

        if AutoDrive.combineIsTurning(self.combine) then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combineIsTurning")
            if self.combine.ad.isHarvester and (self.distanceToCombine < ((self.vehicle.size.length + self.combine.size.length) / 2 + 10)) then
                -- harvester
                -- if combine drive reverse to turn -> reverse to keep distance
                -- PropaineX edit (3.8.4.4): beside it, pull forward (once per turn) instead of backing a semi up
                local leftRight, _ = self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getUnloaderOnSide()
                -- 3.8.5.4: only on the outside of the turn and when we chased from the side; on the inside the combine
                -- comes round across our front: stand and let it turn away
                if leftRight ~= AutoDrive.CHASEPOS_UNKNOWN and not self.clearedThisTurn and self:isOutsideOfTurn()
                    and self.chaseSide ~= AutoDrive.CHASEPOS_REAR then
                    self:startClearForward(string.format("close beside the turning combine (%.0f m)", self.distanceToCombine))
                    return
                end
                if self:isOutsideOfTurn() or self.chaseSide == AutoDrive.CHASEPOS_REAR then
                    self:reverse(dt)
                else
                    self.vehicle.ad.specialDrivingModule:stopVehicle() -- 3.8.5.4: inside of the turn: stand
                    self.vehicle.ad.specialDrivingModule:update(dt)
                end
            elseif self.combine.ad.isChopper and AutoDrive:getIsCPActive(self.combine) then
                -- CP chopper turn
                if self.combine.ad.isAutoAimingChopper then
                    local movingDirection = self.combine.movingDirection
                    if self.combine.ad.isReverseAttached then
                        movingDirection = -self.combine.movingDirection
                    end
                    local isdrivingReverse = ((self.combine.lastSpeedReal * movingDirection) <= -0.00051) 
                    local combineIsDriving = (self.combine.lastSpeedReal > 0.001) 

                    if isdrivingReverse then
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN -> self:reverse")
                        self:reverse(dt)
                    elseif (not combineIsDriving and (self:getAngleToCobine() > 45)) then
                        -- if stuck with harvester - try reverse
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - stuck / getAngleToCobine() > 45 -> STATE_REVERSING_FROM_CHOPPER combineIsDriving %s", tostring(combineIsDriving))
                        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
                        self.reverseStartLocation = {x = x, y = y, z = z}
                        self.state = FollowCombineTask.STATE_REVERSING_FROM_CHOPPER -- reverse to get room from harvester
                        return
                    elseif combineIsDriving then
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combineIsDriving -> stopVehicle")
                        self.vehicle.ad.specialDrivingModule:stopVehicle()
                        self.vehicle.ad.specialDrivingModule:update(dt)
                    else
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN -> followChasePoint self.chaseSide %s", tostring(self.chaseSide))
                        self:followChasePoint(dt)
                    end
                else
                    -- isFixedPipeChopper
                    FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - noMovementTimer %d", self.combine.ad.noMovementTimer.elapsedTime)
                    local dischargeState = self.combine:getDischargeState()
                    self.fillingTimer:timer(not self.combine.spec_combine.isFilling, 100, dt)
                    if self.fillingTimer:done() and self.combine.ad.noMovementTimer.elapsedTime < 5000 then
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - fillingTimer:done")
                        -- harvested to end of row
                        AutoDrive:holdCPCombine(self.combine)
                        self.vehicle.ad.specialDrivingModule:stopVehicle()
                        self.vehicle.ad.specialDrivingModule:update(dt)
                    else
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN -> followChasePoint no AutoAimingChopper")
                        self:followChasePoint(dt)
                    end
                    self.dischargeTimer:timer(dischargeState ~= Dischargeable.DISCHARGE_STATE_OBJECT , 500, dt)
                    if self.dischargeTimer:done() and self.fillingTimer:done() and self.combine.ad.noMovementTimer.elapsedTime < 5000 then
                        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - dischargeTimer:done")
                        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
                        self.reverseStartLocation = {x = x, y = y, z = z}
                        self.state = FollowCombineTask.STATE_REVERSING_FROM_CHOPPER -- reverse to get room from harvester
                        return
                    end
                end
            else
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN -> stopVehicle")
                -- stop while combine is turning
                self.vehicle.ad.specialDrivingModule:stopVehicle()
                self.vehicle.ad.specialDrivingModule:update(dt)
            end
        end

        -- check if we could continue
        local combineSensors = AutoDrive.getCombineSensors(self.combine, self.combineRootVehicle) -- PropaineX edit (3.10.0.0): Nexat
        if not AutoDrive.combineIsTurning(self.combine) and 
            (
                (
                    combineSensors.frontSensorFruit:pollInfo() and 
                    (
                        self.combine.ad.isChopper -- chopper
                        or self.combine.ad.driveForwardTimer.elapsedTime > 8000 -- Harvester moves
                    ) 
                ) 
                or self.waitForTurnTimer.elapsedTime > 15000 -- turn longer than 15 sec
            ) then
            if (self.angleToCombineHeading + self.angleToCombine) < 180 and self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:isUnloaderOnCorrectSide(self.chaseSide) then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combine turn finished - Heading looks good - start chasing again")
                self.state = FollowCombineTask.STATE_CHASING
                return
            elseif self.angleToCombineHeading > 150 and self.angleToCombineHeading < 210 and self.distanceToCombine < 80 and self.combine.ad.isHarvester then
                -- Instead of directly trying a long way around to get behind the harvester, let's wait for him to pass us by and then U-turn
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combine turn finished - Heading inverted - wait for passby, then U-turn")
                self.state = FollowCombineTask.STATE_WAIT_FOR_COMBINE_TO_PASS_BY
                return
            else
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_TURN - combine turn finished - Heading looks bad - stop to be able to start pathfinder")
                self.stayOnField = true
                self.state = FollowCombineTask.STATE_FINISHED
                return
            end
        end
    elseif self.state == FollowCombineTask.STATE_WAIT_FOR_PASS_BY then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_PASS_BY")
        self.waitForPassByTimer:timer(true, 2200, dt)
        self.vehicle.ad.specialDrivingModule:stopVehicle()
        self.vehicle.ad.specialDrivingModule:update(dt)
        if self.waitForPassByTimer:done() then
            if (self.angleToCombineHeading + self.angleToCombine) < 180 and self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:isUnloaderOnCorrectSide() then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_PASS_BY - passby timer elapsed - heading looks good - chasing again")
                self.state = FollowCombineTask.STATE_CHASING
                return
            else
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_PASS_BY - passby timer elapsed - heading looks bad - set finished now")
                self.stayOnField = true
                self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
                return
            end
        end
    elseif self.state == FollowCombineTask.STATE_REVERSING then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING")
        local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
        local distanceToReverseStart = MathUtil.vector2Length(x - self.reverseStartLocation.x, z - self.reverseStartLocation.z)
        self.reverseTimer:timer(true, self.MAX_REVERSE_TIME, dt)
        local doneReversing = distanceToReverseStart > self.MAX_REVERSE_DISTANCE or (not self.startedChasing)
        if doneReversing or self.reverseTimer:done() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING - done reversing - set finished")
            self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
            return
        else
            self:reverse(dt)
        end
    elseif self.state == FollowCombineTask.STATE_REVERSING_FROM_CHOPPER then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING_FROM_CHOPPER")
        local cx, _, cz = getWorldTranslation(self.combine.components[1].node)
        local vx, _, vz = getWorldTranslation(self.vehicle.components[1].node)
        local distanceToReverseStart = MathUtil.vector2Length(vx - self.reverseStartLocation.x, vz - self.reverseStartLocation.z)
        local distanceToCombine = MathUtil.vector2Length(cx - vx, cz - vz)
        self.reverseTimer:timer(true, self.MAX_REVERSE_TIME, dt)
        local doneReversing = distanceToReverseStart > self.MAX_REVERSE_DISTANCE or distanceToCombine > self.MAX_REVERSE_DISTANCE
        if doneReversing or self.reverseTimer:done() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING_FROM_CHOPPER - done reversing - set finished")
            if self.combine.ad.isFixedPipeChopper and AutoDrive:getIsCPActive(self.combine) then
                -- wait for CP to finish a turn maneuver before invoke pathfinder
                self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
                return
            else
                self.state = FollowCombineTask.STATE_FINISHED
                return
            end
        else
            if self.combine.ad.isFixedPipeChopper then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING_FROM_CHOPPER - not AutoAimingChopper -> holdCPCombine")
                AutoDrive:holdCPCombine(self.combine)
            else
                if self:getAngleToCobine() > 30 then
                    FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_REVERSING_FROM_CHOPPER - AngleToCobine > 30 -> holdCPCombine")
                    AutoDrive:holdCPCombine(self.combine)
                end
            end
            self:reverse(dt)
        end
    elseif self.state == FollowCombineTask.STATE_WAIT_BEFORE_FINISH then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_BEFORE_FINISH")
        -- wait for CP to finish a turn maneuver before invoke pathfinder
        -- TODO: check if following is useful!
        local combineIsDriving = self.combine.ad.isFixedPipeChopper and AutoDrive:getIsCPActive(self.combine) and (self.combine.lastSpeedReal > 0.001)
        self.waitTimer:timer(not combineIsDriving, self.WAIT_BEFORE_FINISH_TIME, dt)
        if self.waitTimer:done() then
            self.state = FollowCombineTask.STATE_FINISHED
            return
        else
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
        end
    elseif self.state == FollowCombineTask.STATE_WAIT_FOR_COMBINE_TO_PASS_BY then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_COMBINE_TO_PASS_BY")
        self.waitForPassByTimer:timer(true, 15000, dt)
        self.vehicle.ad.specialDrivingModule:stopVehicle()
        self.vehicle.ad.specialDrivingModule:update(dt)
        if self.waitForPassByTimer:done() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_COMBINE_TO_PASS_BY - passby timer elapsed - heading looks bad - set finished now")
            self.stayOnField = true
            self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
            return
        else
            local cx, cy, cz = getWorldTranslation(self.combine.components[1].node)
            local _, _, offsetZ = AutoDrive.worldToLocal(self.vehicle, cx, cy, cz)
            if offsetZ <= -10 then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_WAIT_FOR_COMBINE_TO_PASS_BY - combine passed us. Calculate U-turn now")
                local cx, cy, cz = getWorldTranslation(self.combine.components[1].node)
                local offsetX, _, _ = AutoDrive.worldToLocal(self.vehicle, cx, cy, cz)
                self.vehicle:generateUTurn(offsetX > 0)
                self.state = FollowCombineTask.STATE_GENERATE_UTURN_PATH
                return
            end
        end
    elseif self.state == FollowCombineTask.STATE_GENERATE_UTURN_PATH then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_GENERATE_UTURN_PATH")
        if self.vehicle.ad.uTurn ~= nil and self.vehicle.ad.uTurn.inProgress then
            self.vehicle:generateUTurn(true)
        elseif self.vehicle.ad.uTurn ~= nil and not self.vehicle.ad.uTurn.inProgress then
            if self.vehicle.ad.uTurn.colliFound or self.vehicle.ad.uTurn.points == nil or #self.vehicle.ad.uTurn.points < 5 then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_GENERATE_UTURN_PATH - U-Turn generation failed due to collision - set finished now")
                self.stayOnField = true
                self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
                return
            else
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_GENERATE_UTURN_PATH - U-Turn generation finished - passing points to drivePathModule now")
                self.vehicle.ad.drivePathModule:setWayPoints(self.vehicle.ad.uTurn.points)
                self.state = FollowCombineTask.STATE_DRIVE_UTURN_PATH
                return
            end
        end
    elseif self.state == FollowCombineTask.STATE_DRIVE_UTURN_PATH then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_DRIVE_UTURN_PATH")
        if self.vehicle.ad.drivePathModule:isTargetReached() then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_DRIVE_UTURN_PATH - U-Turn finished")
            if (self.angleToCombineHeading + self.angleToCombine) < 180 and self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:isUnloaderOnCorrectSide() then
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_DRIVE_UTURN_PATH - passby timer elapsed - heading looks good - chasing again")
                self.state = FollowCombineTask.STATE_CHASING
                return
            else
                FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_DRIVE_UTURN_PATH - passby timer elapsed - heading looks bad - set finished now")
                self.stayOnField = true
                self.state = FollowCombineTask.STATE_WAIT_BEFORE_FINISH
                return
            end
        else
            self.vehicle.ad.drivePathModule:update(dt)
        end
    elseif self.state == FollowCombineTask.STATE_CLEAR_FORWARD then
        -- PropaineX edit (3.8.0.4): drive ahead and a little away from the combine until past the length of the
        -- combine, then wait for the turn as before; can't move -> back out as before
        local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
        local moved = MathUtil.vector2Length(vx - self.clearStartLocation.x, vz - self.clearStartLocation.z)
        self.clearTime = self.clearTime + dt
        if self.vehicle.lastSpeedReal * 3600 < 1 then
            self.clearStoppedTime = self.clearStoppedTime + dt
        else
            self.clearStoppedTime = 0
        end
        local clearDistance = (self.combine.size and self.combine.size.length or 10) + FollowCombineTask.CLEAR_EXTRA
        if moved >= clearDistance or self.clearTime > FollowCombineTask.CLEAR_MAX_TIME then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CLEAR_FORWARD - clear (%.0f m) -> wait for turn", moved)
            self.state = FollowCombineTask.STATE_WAIT_FOR_TURN
            return
        end
        if self.clearStoppedTime > FollowCombineTask.CLEAR_BLOCKED_TIME and self.clearTime > FollowCombineTask.CLEAR_BLOCKED_TIME then
            FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_CLEAR_FORWARD - blocked -> reverse")
            Logging.info("[AD] %s: can't pull forward away from %s (something in front), backing up instead", ADDiag.name(self.vehicle), ADDiag.name(self.combine))
            self.reverseStartLocation = {x = vx, y = vy, z = vz}
            self.state = FollowCombineTask.STATE_REVERSING
            return
        end
        local fx, _, fz = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
        local cx, _, cz = getWorldTranslation(self.combine.components[1].node)
        local ax, az = vx - cx, vz - cz
        local al = MathUtil.vector2Length(ax, az)
        if al > 0.01 then
            ax, az = ax / al, az / al
        end
        -- PropaineX edit (3.8.5.4): straight ahead along its own heading (it steered 4 m away from the combine: a veer)
        local point = {x = vx + fx * 25, y = vy, z = vz + fz * 25}
        self.vehicle.ad.specialDrivingModule:driveToPoint(dt, point, 12, true, 1, 15, false)
    elseif self.state == FollowCombineTask.STATE_FINISHED then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:update STATE_FINISHED")
        self:finished()
        return
    end
end

function FollowCombineTask:startPathPlanningForCircling()
    local sideOffset = 0
    if self.chaseSide ~= nil and self.chaseSide == AutoDrive.CHASEPOS_LEFT then
        sideOffset = 8
    elseif self.chaseSide ~= nil and self.chaseSide == AutoDrive.CHASEPOS_RIGHT then
        sideOffset = -8
    end

    local targetPos = AutoDrive.createWayPointRelativeToVehicle(self.vehicle, sideOffset, 0)
    local directionX, directionY, directionZ = AutoDrive.localToWorld(self.vehicle, 0, 0, 0, self.vehicle.ad.ADRootNode)
    local direction = {x = directionX - targetPos.x, z = directionZ - targetPos.z}
    self.vehicle.ad.pathFinderModule:reset()
    self.vehicle.ad.pathFinderModule:startPathPlanningTo(targetPos, direction)
end

function FollowCombineTask:updateStates(dt)
    local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
    local cx, cy, cz = getWorldTranslation(self.combine.components[1].node)

    self.chasePos, self.chaseSide = self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getPipeChasePosition()

    self.angleToCombineHeading = self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getAngleToCombineHeading()
    self.angleToCombine = self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD]:getAngleToCombine()

    self.lastChaseSide = self.chaseSide
    self.pushedOutSide = nil -- PropaineX edit (od.59)

    self.distanceToCombine = MathUtil.vector2Length(x - cx, z - cz)

    if (g_updateLoopIndex  % AutoDrive.PERF_FRAMES == 0) or self.updateStatesFirst ~= true then
        self.updateStatesFirst = true

        local cmaxCapacity = 0
        local cfillLevel = 0
        cfillLevel, cmaxCapacity, _ = AutoDrive.getObjectFillLevels(self.combine)
        self.combineFillPercent = cmaxCapacity > 0 and (cfillLevel / cmaxCapacity) * 100 or 0

        local fillFreeCapacity = 0
        _, _, self.filledToUnload, fillFreeCapacity = AutoDrive.getAllFillLevels(self.trailers)
        self.filled = fillFreeCapacity <= 0.1
        
        self.activeUnloading = AutoDrive.getSetting("activeUnloading", self.combineRootVehicle)
    end
    self:shouldWaitForChasePos(dt)
end

function FollowCombineTask:reverse(dt)
    self.vehicle.ad.specialDrivingModule:driveReverse(dt, 15, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
end

-- PropaineX edit (3.8.5.4): while the combine is flagged as turning (lane change or corner, can't tell yet) and we
-- chase from the side, aim TURN_HOLD_BACK m behind its tail on our side instead of under the pipe: its rear-wheel steering
-- swings the tail out, and from behind the tail it can't reach us. Back under the pipe when the flag clears.
FollowCombineTask.TURN_HOLD_BACK = 3 -- m between the combine's tail and our front

function FollowCombineTask:getTurnHoldBackPos()
    if not AutoDrive.combineIsTurning(self.combine) or self.combine.ad.isChopper or not self.combine.ad.isHarvester
        or self.chaseSide == nil or self.chaseSide == AutoDrive.CHASEPOS_REAR or self.chasePos == nil then
        return nil
    end
    local cx, cy, cz = getWorldTranslation(self.combine.components[1].node)
    local sideX, _, _ = AutoDrive.worldToLocal(self.combine, self.chasePos.x, self.chasePos.y, self.chasePos.z, self.combine.ad.ADRootNode)
    local back = -(self.combine.size.length / 2) - FollowCombineTask.TURN_HOLD_BACK - (self.vehicle.size.length or 0) / 2
    local x, y, z = AutoDrive.localToWorld(self.combine, sideX, 0, back, self.combine.ad.ADRootNode)
    return {x = x, y = cy, z = z}
end

-- PropaineX edit (od.58): END OF ROW WAIT. A harvester (not a forage harvester) raises its header or switches it off
-- at the end of a row; a rounded headland corner is harvested with the header down, so that is chased as before.
-- Header up or off (after we have seen it working): the runner stops where it is (no following, no pulling forward,
-- no reversing) until every header is lowered and switched on again, then the chase starts over.
-- Not while the harvester is calling for an unload (it stands still then) and at most MAX_TURN_TIME.
function FollowCombineTask:isHeaderWorking()
    local root = self.combineRootVehicle
    if root == nil then
        return nil
    end
    local found, working = false, true
    local function check(v)
        if v ~= nil and v.spec_cutter ~= nil then
            found = true
            local lowered = true
            if v.getIsLowered ~= nil and (v.getAllowsLowering == nil or v:getAllowsLowering()) then
                lowered = v:getIsLowered(true)
            end
            local on = v.getIsTurnedOn == nil or v:getIsTurnedOn()
            if not (lowered and on) then
                working = false
            end
        end
    end
    local children = root.getChildVehicles ~= nil and root:getChildVehicles() or nil
    if children ~= nil then
        for _, v in pairs(children) do
            check(v)
        end
    else
        check(root)
    end
    if not found then
        return nil -- no header found: feature off for this harvester
    end
    return working
end

function FollowCombineTask:updateEndOfRowWait(dt)
    if not self.combine.ad.isHarvester or self.combine.ad.isChopper then
        return false
    end
    local working = self:isHeaderWorking()
    if working == nil then
        self.endOfRowWait = nil
        return false
    end
    if working then
        self.headerSeenWorking = true
        if self.endOfRowWait then
            self.endOfRowWait = nil
            Logging.info("[AD] %s: end of row: %s header down and on again, chasing again", ADDiag.name(self.vehicle), ADDiag.name(self.combine))
            if self.state ~= FollowCombineTask.STATE_FINISHED then
                self.state = FollowCombineTask.STATE_CHASING
            end
        end
        return false
    end
    local calling = AutoDrive:getIsCPWaitingForUnload(self.combine) or (self.combineFillPercent or 0) >= 99
    if not self.endOfRowWait then
        if not self.headerSeenWorking or calling or self.state == FollowCombineTask.STATE_FINISHED then
            return false
        end
        self.endOfRowWait = true
        self.endOfRowWaitTime = 0
        Logging.info("[AD] %s: end of row: %s header up, standing here until it is harvesting again", ADDiag.name(self.vehicle), ADDiag.name(self.combine))
    end
    self.endOfRowWaitTime = self.endOfRowWaitTime + dt
    if calling or self.endOfRowWaitTime > FollowCombineTask.MAX_TURN_TIME then
        Logging.info("[AD] %s: end of row: stop waiting for %s (%s)", ADDiag.name(self.vehicle), ADDiag.name(self.combine), calling and "it calls for an unload" or "waited too long")
        self.endOfRowWait = nil
        self.headerSeenWorking = nil -- wait again only after it has harvested again
        return false
    end
    self.vehicle.ad.specialDrivingModule:stopVehicle()
    self.vehicle.ad.specialDrivingModule:update(dt)
    return true
end

function FollowCombineTask:followChasePoint(dt)
    -- PropaineX edit (3.8.6.4): no dropping back in turns any more (getTurnHoldBackPos unused): it keeps chasing under
    -- the pipe; dropping back steered it at a spot behind it and veered it off
    if self:shouldWaitForChasePos(dt) then
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:followChasePoint getAngleToChasePos %.0f -> stopVehicle", self:getAngleToChasePos())
        self.vehicle.ad.specialDrivingModule:stopVehicle()
        self.vehicle.ad.specialDrivingModule:update(dt)
    else
        self.startedChasing = true
        local combineSpeed = self.combine.lastSpeedReal * 3600
        local acc = 1
        local totalSpeedLimit = 40
        -- Let's start driving a little slower when we are switching sides
        if not self.chaseTimer:done() or not self:isCaughtCurrentChaseSide() then
            acc = 1
            totalSpeedLimit = math.max(combineSpeed + 20, 10)
        end
        -- PropaineX edit: stronger catch-up to stay under the pipe (chaseCatchUp)
        -- PropaineX edit (od.56): never steer into the harvester (keep-out gap)
        local steer = self.combine.ad.isHarvester and not self.combine.ad.isChopper and self:keepOffHarvester(self.chasePos, true) or nil
        self.vehicle.ad.specialDrivingModule:driveToPoint(dt, self.chasePos, combineSpeed, false, acc, totalSpeedLimit, true, steer)
    end
end

-- PropaineX edit (3.7.0.4): a "turn" (CP manoeuvre, AI turn or near the field edge) only counts once the combine has
-- swung more than TURN_ANGLE from where it pointed when the turn flag came on; a small veer is chased through.
FollowCombineTask.TURN_ANGLE = 47

function FollowCombineTask:getCombineHeading()
    local rx, _, rz = AutoDrive.localDirectionToWorld(self.combine, 0, 0, 1, self.combine.ad.ADRootNode)
    return {x = rx, z = rz}
end

function FollowCombineTask:isRealTurn(turnFlag)
    if not turnFlag then
        self.turnStartHeading = nil
        return false
    end
    if self.turnStartHeading == nil then
        self.turnStartHeading = self:getCombineHeading()
        return false
    end
    local swung = math.abs(AutoDrive.angleBetween(self.turnStartHeading, self:getCombineHeading()))
    return swung > FollowCombineTask.TURN_ANGLE
end

-- PropaineX edit (3.8.2.4): the part of the trailer under the pipe is full but the rest isn't: move the trailer under
-- the pipe toward its emptier end, at walking pace. The heap forms where the pipe drops, so the longer stretch of the
-- trailer from the pipe is the emptier one: pipe ahead of the trailer's middle -> drive forward (the pipe moves back
-- along the trailer), behind it -> reverse. Stops at that end (CREEP_END_MARGIN); the hold takes over once grain flows.
FollowCombineTask.CREEP_SPEED = 3       -- km/h
FollowCombineTask.CREEP_END_MARGIN = 1  -- m from the trailer's end

function FollowCombineTask:getCreepTrailer()
    local best, bestLength = nil, 0
    for _, trailer in pairs(self.trailers or {}) do
        if trailer ~= self.vehicle and trailer.size ~= nil and (trailer.size.length or 0) > bestLength then
            best, bestLength = trailer, trailer.size.length
        end
    end
    return best or self.vehicle
end

function FollowCombineTask:creepUnderPipe(dt)
    local trailer = self:getCreepTrailer()
    local dischargeNode = AutoDrive.getDischargeNode(self.combine)
    if trailer == nil or dischargeNode == nil then
        self.vehicle.ad.specialDrivingModule:stopVehicle()
        self.vehicle.ad.specialDrivingModule:update(dt)
        return
    end
    local px, py, pz = getWorldTranslation(dischargeNode)
    local _, _, pipeZ = worldToLocal(trailer.components[1].node, px, py, pz)
    local half = (trailer.size.length or 0) / 2 - FollowCombineTask.CREEP_END_MARGIN
    self.creepAnchor = true
    if self.creepForward == nil then
        self.creepForward = pipeZ > 0
        FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:creepUnderPipe - nothing going in, creeping %s", self.creepForward and "forward" or "back")
    end
    if (self.creepForward and pipeZ < -half) or (not self.creepForward and pipeZ > half) then
        -- reached that end of the trailer: try the other way once, then stand
        if not self.creepTurned then
            self.creepTurned = true
            self.creepForward = not self.creepForward
        else
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
            return
        end
    end
    if self.creepForward then
        local x, y, z = AutoDrive.localToWorld(self.vehicle, 0, 0, 20)
        self.vehicle.ad.specialDrivingModule:driveToPoint(dt, {x = x, y = y, z = z}, FollowCombineTask.CREEP_SPEED, false, 0.5,
            FollowCombineTask.CREEP_SPEED, false)
    else
        self.vehicle.ad.specialDrivingModule:driveReverse(dt, FollowCombineTask.CREEP_SPEED, 0.5, self.vehicle.ad.trailerModule:canBeHandledInReverse())
    end
end

function FollowCombineTask:tailSwingsAtUs()
    -- PropaineX edit (3.8.3.4): no angle any more (15 deg also fired on lane changes): only when the combine's rear
    -- corner on our side actually comes within TAIL_CLEARANCE of the truck or a trailer
    if self.combine.ad.isChopper or not self.combine.ad.isHarvester or self.combine.size == nil then
        return nil
    end
    local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
    local sideX, _, _ = AutoDrive.worldToLocal(self.combine, vx, vy, vz, self.combine.ad.ADRootNode)
    local side = sideX >= 0 and 1 or -1
    local halfW, halfL = AutoDrive.getHarvesterHalfSize(self.combine) -- PropaineX edit (3.10.0.0): Nexat: carrier's wheel units
    local px, py, pz = AutoDrive.localToWorld(self.combine, side * halfW, 0, -halfL, self.combine.ad.ADRootNode)
    local units = {self.vehicle}
    for _, trailer in pairs(self.trailers or {}) do
        if trailer ~= self.vehicle then
            table.insert(units, trailer)
        end
    end
    local margin = FollowCombineTask.TAIL_CLEARANCE
    for _, unit in pairs(units) do
        if unit.components ~= nil and unit.components[1] ~= nil and unit.size ~= nil then
            local lx, _, lz = worldToLocal(unit.components[1].node, px, py, pz)
            local gx = math.abs(lx) - (unit.size.width or 0) / 2
            local gz = math.abs(lz) - (unit.size.length or 0) / 2
            if gx < margin and gz < margin then
                return math.max(gx, gz, 0) -- PropaineX edit (3.8.4.4): the gap, nil when clear
            end
        end
    end
    return nil
end

-- PropaineX edit (3.9.1.4): gap between the truck and the combine, front to back along the line between them
function FollowCombineTask:getGapToCombine()
    local d = AutoDrive.getDistanceBetween(self.vehicle, self.combine)
    local _, halfL = AutoDrive.getHarvesterHalfSize(self.combine) -- PropaineX edit (3.10.0.0): Nexat
    return d - halfL - (self.vehicle.size.length or 0) / 2
end

FollowCombineTask.BACK_OFF_GAP = 30      -- m: back up until this gap, then forward at once
FollowCombineTask.BACK_OFF_START_GAP = 15 -- m: only this close (or closer) is backing off needed
FollowCombineTask.SEMI_RADIUS = 12        -- m: a combine turning tighter than this can't be followed on the inside
FollowCombineTask.BACK_OFF_SPEED = 12     -- km/h
FollowCombineTask.BACK_OFF_BLOCKED = 3000 -- ms not moving while backing off -> stop backing off (blocked)

function FollowCombineTask:updateBackOff(dt)
    local c = self.combine
    local sdm = self.vehicle.ad.specialDrivingModule
    local gap = self:getGapToCombine()
    if self.backingOff then
        if gap >= FollowCombineTask.BACK_OFF_GAP then
            Logging.info("[AD] %s: %.0f m from %s, forward again", ADDiag.name(self.vehicle), gap, ADDiag.name(c))
            self.backingOff = nil
            return false
        end
        if sdm.frontHold and math.abs(self.combineTurnRate or 0) < FollowCombineTask.TURN_DEADBAND then
            -- PropaineX edit (od.56): held at the harvester's front and its turn is over: it has passed, chase again
            Logging.info("[AD] %s: %s has come round, forward again", ADDiag.name(self.vehicle), ADDiag.name(c))
            self.backingOff = nil
            sdm.frontHold = false
            return false
        end
        if sdm.frontHold then
            self.backOffStopped = 0 -- PropaineX edit (od.56): held so it doesn't back into the harvester's front: not blocked
        elseif self.vehicle.lastSpeedReal * 3600 < 1 then
            self.backOffStopped = (self.backOffStopped or 0) + dt
        else
            self.backOffStopped = 0
        end
        if self.backOffStopped > FollowCombineTask.BACK_OFF_BLOCKED and self.backOffTime > FollowCombineTask.BACK_OFF_BLOCKED then
            Logging.info("[AD] %s: can't back up any further (%.0f m from %s), forward again", ADDiag.name(self.vehicle), gap, ADDiag.name(c))
            self.backingOff = nil
            return false
        end
        self.backOffTime = self.backOffTime + dt
        sdm:driveReverse(dt, FollowCombineTask.BACK_OFF_SPEED, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
        return true
    end
    -- start: a real corner (the combine has turned more than TURN_ANGLE in one go: never a lane change), toward our
    -- side, tighter than a semi can follow, and we are close beside it
    local w = self.combineTurnRate or 0
    if math.abs(w) >= FollowCombineTask.TURN_DEADBAND and (self.turnSwing == nil or self.turnSwing * w >= 0) then
        self.turnSwing = (self.turnSwing or 0) + w * dt / 1000
        self.turnQuiet = 0
    else
        self.turnQuiet = (self.turnQuiet or 0) + dt
        if self.turnQuiet > 1000 or (self.turnSwing ~= nil and self.turnSwing * w < 0) then
            self.turnSwing = nil
        end
    end
    if math.deg(math.abs(self.turnSwing or 0)) < FollowCombineTask.TURN_ANGLE then
        return false
    end
    local v = c.lastSpeedReal * 1000
    if math.abs(w) < FollowCombineTask.TURN_DEADBAND or v < 0.1 or gap > FollowCombineTask.BACK_OFF_START_GAP then
        return false
    end
    local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
    local tx, _, tz = AutoDrive.worldToLocal(c, vx, vy, vz, c.ad.ADRootNode)
    local _, cHalfL = AutoDrive.getHarvesterHalfSize(c) -- PropaineX edit (3.10.0.0): Nexat
    if tx * w <= 0 or tz < -cHalfL then
        return false -- outside of the turn, or already behind its tail
    end
    -- PropaineX edit (od.56): OUR radius on the inside is the harvester's minus how far in we are beside it (a 13 m
    -- turn with the truck 8 m to the inside is a 5 m turn for the semi: it folded its trailer)
    if v / math.abs(w) - math.abs(tx) >= FollowCombineTask.SEMI_RADIUS then
        return false
    end
    Logging.info("[AD] %s: inside of %s's turn (radius %.0f m, %.0f m for us), backing up to %d m", ADDiag.name(self.vehicle),
        ADDiag.name(c), v / math.abs(w), v / math.abs(w) - math.abs(tx), FollowCombineTask.BACK_OFF_GAP)
    self.backingOff = true
    self.backOffTime = 0
    self.backOffStopped = 0
    sdm:driveReverse(dt, FollowCombineTask.BACK_OFF_SPEED, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
    return true
end

-- PropaineX edit (3.9.0.4): pipe lock (see update)
-- PropaineX edit (od.55): truck clearly beside the harvester (outside its width) on its pipe side, its front level
-- with the harvester's tail or further forward
function FollowCombineTask:isBesidePipeSide()
    local c = self.combine
    local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
    local lx, _, lz = AutoDrive.worldToLocal(c, vx, vy, vz, c.ad.ADRootNode)
    local halfW, halfL = AutoDrive.getHarvesterHalfSize(c)
    local frontZ = lz + (self.vehicle.size ~= nil and self.vehicle.size.length or 0) / 2
    return math.abs(lx) > halfW and AutoDrive.sign(lx) == AutoDrive.getPipeSide(c) and frontZ >= -halfL
end

function FollowCombineTask:isPipeLock()
    return self.activeUnloading == true and self.combine.ad.isHarvester and not self.combine.ad.isChopper
end

function FollowCombineTask:updatePipeLock(dt)
    if self.state ~= FollowCombineTask.STATE_CHASING then
        self.state = FollowCombineTask.STATE_CHASING
        self.lastState = self.state
    end
    self.stuckTimer:timer(false)
    self.angleWrongTimer:timer(false)
    local sdm = self.vehicle.ad.specialDrivingModule
    if self.filled then
        -- trailer full: off to unload (the mode picks the next task)
        Logging.info("[AD] %s: trailer full, leaving %s to unload", ADDiag.name(self.vehicle), ADDiag.name(self.combine))
        self:finished()
        return
    end
    local standing = self.combine.lastSpeedReal <= 0.0004
    if standing then
        -- combine stands: hold still under the pipe while grain goes in; nothing going in -> creep along the trailer
        local flowing = self.combine.getDischargeState ~= nil and self.combine:getDischargeState() == Dischargeable.DISCHARGE_STATE_OBJECT
        if flowing then
            self.noFlowTime = 0
            self.creepForward = nil
            self.creepTurned = nil
        else
            self.noFlowTime = (self.noFlowTime or 0) + dt
        end
        -- PropaineX edit (od.55): the spot behind a standing harvester is no pipe: nothing falls in there (it held
        -- still behind it for good). Only beside it on its pipe side counts. Standing still, grain in it, nothing falling
        -- in and not beside the pipe for GO_AROUND_TIME: drive round it and start the approach over
        local beside = self:isBesidePipeSide()
        local behind = self.chaseSide == AutoDrive.CHASEPOS_REAR and not beside
        if not flowing and not beside and (self.combineFillPercent or 0) > 0.1
            and (self.vehicle.lastSpeedReal or 0) <= 0.0004 then
            self.goAroundTime = (self.goAroundTime or 0) + dt
        else
            self.goAroundTime = 0
        end
        if self.goAroundTime > FollowCombineTask.GO_AROUND_TIME then
            self.goAroundTime = 0
            Logging.info("[AD] %s: nothing falling in for %d s at standing %s (not beside its pipe), driving round it to %d m behind and starting over",
                ADDiag.name(self.vehicle), FollowCombineTask.GO_AROUND_TIME / 1000, ADDiag.name(self.combine), ADUnloaderClear.GO_AROUND_BEHIND)
            ADUnloaderClear.goAround(self.vehicle.ad.modes[AutoDrive.MODE_UNLOAD], self.combine)
            return
        end
        if behind then
            -- hold still (no chasing a spot behind it) until the timer above sends it round
            self.creepAnchor = nil
            sdm:stopVehicle()
            sdm:update(dt)
            sdm.isBlocked = false
            if sdm.stoppedTimer ~= nil then
                sdm.stoppedTimer:timer(false)
            end
            return
        end
        local nearPipe = self.creepAnchor
        if not nearPipe and self.chasePos ~= nil then
            local vx, _, vz = getWorldTranslation(self.vehicle.components[1].node)
            nearPipe = MathUtil.vector2Length(vx - self.chasePos.x, vz - self.chasePos.z) < 3
        end
        if nearPipe then
            if (self.combineFillPercent or 0) > 0.1 and self.noFlowTime > FollowCombineTask.NO_FLOW_TIME then
                self:creepUnderPipe(dt)
            else
                sdm:stopVehicle()
                sdm:update(dt)
            end
            sdm.isBlocked = false
            if sdm.stoppedTimer ~= nil then
                sdm.stoppedTimer:timer(false)
            end
            return
        end
    else
        self.creepAnchor = nil
        self.creepForward = nil
        self.creepTurned = nil
        self.noFlowTime = 0
        self.goAroundTime = 0 -- PropaineX edit (od.55)
    end
    -- drive to the spot under the pipe at the combine's speed (catch up when behind, drop back when past it), aimed at
    -- where the pipe will be in LEAD_TIME (the combine's speed and turn rate), so it doesn't lag behind every swing
    self.startedChasing = true
    local combineSpeed = self.combine.lastSpeedReal * 3600
    -- PropaineX edit (3.9.0.4): farther than PIPE_LOCK_RANGE from the combine: no pipe maths, just drive to it (field
    -- speed limit setting); the prediction starts fresh once inside the range
    if AutoDrive.getDistanceBetween(self.vehicle, self.combine) > FollowCombineTask.PIPE_LOCK_RANGE then
        self.lastCombineFwd = nil
        self.combineTurnRate = nil
        sdm:driveToPoint(dt, self.chasePos, combineSpeed, false, 1, FollowCombineTask.FLAT_OUT, true)
        return
    end
    -- inside the range too: only the field speed limit setting caps it; near the pipe the catch-up maths slows it
    -- speed from the spot under the pipe; steering at a point LOOK_AHEAD m further along the combine's line (a spot right
    -- beside the truck can't be steered onto by a semi, it stayed metres off after every lane change)
    -- PropaineX edit (3.9.1.4): INSIDE of a turn tighter than a semi can follow (combine turning toward our side): back
    -- straight up until the gap to the combine is BACK_OFF_GAP, then forward at once (user: the only chase reverse)
    self:updateTurnRate(dt) -- PropaineX edit (od.56)
    if self:updateBackOff(dt) then
        return
    end
    -- on the wrong side of the combine: never straight across it. Drop back behind its tail on our current side, then
    -- come round to our side from behind (the combine drives on, so dropping back is quick)
    local c = self.combine
    local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
    local tx, _, tz = AutoDrive.worldToLocal(c, vx, vy, vz, c.ad.ADRootNode)
    local cxl = AutoDrive.worldToLocal(c, self.chasePos.x, self.chasePos.y, self.chasePos.z, c.ad.ADRootNode)
    local halfW, halfL = AutoDrive.getHarvesterHalfSize(c) -- PropaineX edit (3.10.0.0): Nexat: whole rig, not just the module
    -- 3.9.1.4: only when actually BESIDE it on the other side; from behind its tail it just comes up the pipe side
    local clearlyWrong = tx * cxl < 0 and math.abs(tx) > halfW and tz > -halfL and math.abs(self.combineTurnRate or 0) < 0.05
    self.wrongSideTime = clearlyWrong and (self.wrongSideTime or 0) + dt or 0
    -- PropaineX edit (od.59): already pushed out once on this (no-pipe) side: no second try up the same line, stop at
    -- once and let it pass, then the lane approach brings it up the pipe side. Forgotten once under the pipe.
    if self.pushedOutSide ~= nil and tx * cxl > 0 and math.abs(tx - cxl) <= FollowCombineTask.LANE_TOLERANCE then
        self.pushedOutSide = nil
    end
    if clearlyWrong and self.pushedOutSide ~= nil and tx * self.pushedOutSide > 0 then
        self.wrongSideTime = math.max(self.wrongSideTime, 1001)
    end
    -- PropaineX edit (od.56): beside it on the wrong side: STOP and let it drive past (was: drive to a spot behind it,
    -- which swung the semi round in an arc into the harvester). Once our front is behind its tail, the lane approach
    -- below brings it up the pipe side. (A standing harvester: the go-around above takes over after GO_AROUND_TIME.)
    local frontZ, rearZ = self:getCabSpanZ()
    if self.wrongSideTime > 1000 or (self.comingRound and tx * cxl < 0 and frontZ > -halfL - FollowCombineTask.LANE_BEHIND) then
        self.comingRound = true
        if not self.wrongSideLogged then
            self.wrongSideLogged = true
            Logging.info("[AD] %s: on the wrong side of %s, stopping to let it pass, then coming up its pipe side", ADDiag.name(self.vehicle), ADDiag.name(c))
        end
        sdm:stopVehicle()
        sdm:update(dt)
        return
    end
    self.comingRound = nil
    self.wrongSideLogged = nil
    -- PropaineX edit (od.56): facing AGAINST the harvester (it came round at the end of the row) and not yet behind it:
    -- turning a semi round here crosses its path. Stop and let it pass; once our front is behind its tail, the chase
    -- turns round behind it.
    local hx, _, hz = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
    local cfx, _, cfz = AutoDrive.localDirectionToWorld(c, 0, 0, 1, c.ad.ADRootNode)
    local facingAgainst = hx * cfx + hz * cfz < FollowCombineTask.AGAINST_COS
    -- also: the whole cab ahead of its front (e.g. after pulling ahead out of a tail swing): no turning round toward
    -- a spot behind us, that crosses its path; stand and let it come past
    local cabAhead = rearZ > halfL
    if (cabAhead or (facingAgainst and frontZ > -halfL - FollowCombineTask.LANE_BEHIND)) and combineSpeed > 0.5 then
        if not self.againstLogged then
            self.againstLogged = true
            Logging.info("[AD] %s: ahead of / facing %s, stopping to let it pass", ADDiag.name(self.vehicle), ADDiag.name(c))
        end
        sdm:stopVehicle()
        sdm:update(dt)
        return
    end
    self.againstLogged = nil
    -- PropaineX edit (od.56): behind its tail and not yet in the pipe-side lane: line up in the lane BEHIND the tail
    -- first, then straight up it (no lazy arc that cuts round the tail onto the other side)
    local laneSteer = self:getLaneApproach(tx, tz, cxl, halfW, halfL)
    if laneSteer ~= nil then
        if self:cabHeadsIntoHarvester() then
            if not self.headInLogged then
                self.headInLogged = true
                Logging.info("[AD] %s: pointing into %s, stopping", ADDiag.name(self.vehicle), ADDiag.name(c))
            end
            sdm:stopVehicle()
            sdm:update(dt)
            return
        end
        self.headInLogged = nil
        local laneMax = FollowCombineTask.FLAT_OUT
        if self:getGapToCombine() < FollowCombineTask.CLOSE_GAP then
            laneMax = combineSpeed + FollowCombineTask.CLOSE_EXTRA
        end
        sdm:driveToPoint(dt, laneSteer.target, math.min(combineSpeed, laneMax), false, 1, laneMax, true, laneSteer.steer)
        return
    end
    self.laneLogged = nil
    local target = self:predictChasePos(dt)
    -- straight line: the combine's heading smoothed over LINE_SMOOTH ms; its small wobbles don't reach our wheels
    local fx, _, fz = AutoDrive.localDirectionToWorld(self.combine, 0, 0, 1, self.combine.ad.ADRootNode)
    local k = math.min(1, dt / FollowCombineTask.LINE_SMOOTH)
    if self.lineDir == nil then
        self.lineDir = {x = fx, z = fz}
    else
        local lx, lz = self.lineDir.x + (fx - self.lineDir.x) * k, self.lineDir.z + (fz - self.lineDir.z) * k
        local l = math.sqrt(lx * lx + lz * lz)
        self.lineDir = {x = lx / l, z = lz / l}
    end
    -- a real turn (beyond the dead band): follow the combine's actual heading at once
    if math.abs(self.combineTurnRate or 0) >= FollowCombineTask.TURN_DEADBAND then
        self.lineDir = {x = fx, z = fz}
    end
    local look = math.max(FollowCombineTask.LOOK_AHEAD, combineSpeed / 3.6 * 3)
    local steer = {x = target.x + self.lineDir.x * look, y = target.y, z = target.z + self.lineDir.z * look}
    -- 3.9.1.4: ahead of the pipe spot and facing the combine's way: ease off (half its speed) and let it come up to us,
    -- not drive on and turn round through its path
    local maxSpeed = FollowCombineTask.FLAT_OUT
    local _, _, aheadZ = AutoDrive.worldToLocal(self.vehicle, target.x, target.y, target.z)
    local hx, _, hz = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
    if aheadZ < -1 and hx * self.lineDir.x + hz * self.lineDir.z > 0 then
        maxSpeed = combineSpeed * 0.5
    end
    -- PropaineX edit (od.56): never steer into the harvester (keep-out gap)
    target, steer = self:keepOffHarvester(target), self:keepOffHarvester(steer, true)
    -- a TRAILER corner too close (it cuts in behind the cab, or the harvester's tail swings out in a turn): steering
    -- the cab out doesn't move it in time, so drop back (half the harvester's speed) until it is clear again
    local followSpeed = combineSpeed
    local side = tx >= 0 and 1 or -1
    local inside, byTrailer = self:getKeepOutIntrusion(side)
    local w = self.combineTurnRate or 0
    local swingAway = w * tx < 0 and math.abs(w) >= FollowCombineTask.TURN_DEADBAND and inside ~= nil
        and inside > -FollowCombineTask.SWING_WATCH and self:isParallel()
    if swingAway then
        -- it turns AWAY from us while we are beside it: its tail swings out at us faster than it drives on, so pull
        -- ahead out of the swing at once, wheels straight along our heading (catch-up maths works from followSpeed)
        followSpeed = combineSpeed + FollowCombineTask.SWING_ESCAPE
        local hx, _, hz = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
        steer = {x = vx + hx * 25, y = vy, z = vz + hz * 25}
        target = steer
        maxSpeed = FollowCombineTask.FLAT_OUT
        if not self.swingLogged then
            self.swingLogged = true
            Logging.info("[AD] %s: %s turns away, its tail swings at us: pulling ahead", ADDiag.name(self.vehicle), ADDiag.name(c))
        end
    else
        self.swingLogged = nil
        -- a TRAILER corner too close (it cuts in behind the cab): steering the cab out doesn't move it in time, so
        -- drop back (half the harvester's speed) until it is clear again
        if byTrailer and inside ~= nil and inside > -FollowCombineTask.DRIFT_IN then
            followSpeed = combineSpeed * 0.5
            maxSpeed = math.min(maxSpeed, followSpeed)
            if not self.trailerInLogged then
                self.trailerInLogged = true
                Logging.info("[AD] %s: trailer close to %s, dropping back", ADDiag.name(self.vehicle), ADDiag.name(c))
            end
        elseif inside == nil or inside < -FollowCombineTask.DRIFT_IN - 0.5 then
            self.trailerInLogged = nil
        end
    end
    -- PropaineX edit (od.56): close to the harvester and not straight with it (coming in at an angle): no catch-up
    -- sprint, at most CLOSE_EXTRA over its speed (35 km/h at an angle beside it could not stop in time)
    if not self:isParallel(FollowCombineTask.CLOSE_ANGLE) and self:getGapToCombine() < FollowCombineTask.CLOSE_GAP then
        followSpeed = math.min(followSpeed, combineSpeed + FollowCombineTask.CLOSE_EXTRA)
        maxSpeed = math.min(maxSpeed, combineSpeed + FollowCombineTask.CLOSE_EXTRA)
    end
    -- PropaineX edit (od.56): the cab's own path (where it rolls if the wheels go straight, e.g. the jackknife guard
    -- straightening a folded trailer, which ignores the steering) runs into the harvester within HEAD_IN_PROBE m: stop
    if self:cabHeadsIntoHarvester() then
        if not self.headInLogged then
            self.headInLogged = true
            Logging.info("[AD] %s: pointing into %s, stopping", ADDiag.name(self.vehicle), ADDiag.name(c))
        end
        sdm:stopVehicle()
        sdm:update(dt)
        return
    end
    self.headInLogged = nil
    sdm:driveToPoint(dt, target, followSpeed, false, 1, maxSpeed, true, steer)
end

FollowCombineTask.HEAD_IN_PROBE = 5 -- m ahead of the cab's front checked for the harvester (more at speed)
FollowCombineTask.HEAD_IN_DECEL = 3 -- m/s2 a loaded semi is counted on to brake with
FollowCombineTask.CLOSE_GAP = 15     -- m: this close to the harvester and not straight with it...
FollowCombineTask.CLOSE_ANGLE = 10   -- deg: "straight with it" for that speed cap
FollowCombineTask.CLOSE_EXTRA = 8    -- km/h: ...at most this much faster than the harvester

function FollowCombineTask:cabHeadsIntoHarvester()
    local c = self.combine
    local halfW, halfL = AutoDrive.getHarvesterHalfSize(c)
    local hl = (self.vehicle.size ~= nil and self.vehicle.size.length or 0) / 2
    local hw = self:getOwnHalfWidth()
    -- at least HEAD_IN_PROBE, more at speed: braking distance (v^2 / 2a, HEAD_IN_DECEL) + 2 m
    local v = (self.vehicle.lastSpeedReal or 0) * 1000
    local probe = math.max(FollowCombineTask.HEAD_IN_PROBE, v * v / (2 * FollowCombineTask.HEAD_IN_DECEL) + 2)
    for d = 1, probe do
        for _, sx in ipairs({-hw, 0, hw}) do
            local wx, wy, wz = AutoDrive.localToWorld(self.vehicle, sx, 0, hl + d)
            local lx, _, lz = AutoDrive.worldToLocal(c, wx, wy, wz, c.ad.ADRootNode)
            if math.abs(lx) < halfW + FollowCombineTask.KEEP_OUT_GAP and math.abs(lz) < halfL + FollowCombineTask.KEEP_OUT_GAP then
                return true
            end
        end
    end
    return false
end

-- PropaineX edit (od.56): KEEP-OUT GAP. Our "lane" beside the harvester is the harvester's half width + our half width +
-- KEEP_OUT_GAP out from its centre line, never further out than the spot under the pipe (so the trailer stays under
-- it). No point the truck drives or steers at may lie closer in than that lane, within the harvester's length
-- (+ KEEP_OUT_LENGTH): such a point is moved straight out sideways, to the side the truck is on. A truck or trailer
-- already more than DRIFT_IN m inside its lane beside the harvester: the steer point goes STEER_AWAY m further out, so it
-- steers away. Result: the steering can never close in on the harvester, whatever the chase maths says.
FollowCombineTask.KEEP_OUT_GAP = 1.0    -- m between the truck's side and the harvester's side
FollowCombineTask.KEEP_OUT_MIN = 0.4    -- m: the lane is never closer than this, even for a short pipe
-- PropaineX edit (od.59): on the PIPE side the strip is thin, so a truck gets in under the pipe instead of turning away
FollowCombineTask.KEEP_OUT_PIPE_GAP = 0.5 -- m between the truck's side and the harvester's side, pipe side only
FollowCombineTask.PIPE_GAP_TURN = 0.03  -- rad/s (~2 deg/s): turning toward the pipe side faster than this = full gap
FollowCombineTask.KEEP_OUT_LENGTH = 2   -- m before its front and behind its tail that count too
FollowCombineTask.AGAINST_COS = math.cos(math.rad(110)) -- facing more than 110 deg off the harvester's heading
FollowCombineTask.PARALLEL_ANGLE = 30   -- deg: pulling ahead out of a tail swing only when this close to its heading
FollowCombineTask.SWING_WATCH = 6       -- m: beside it within this of the keep-out strip counts for the tail swing
FollowCombineTask.SWING_ESCAPE = 8      -- km/h over the harvester's speed when pulling out of its tail swing
FollowCombineTask.DRIFT_IN = 0.5        -- m inside the lane before it steers away
FollowCombineTask.STEER_AWAY = 2        -- m extra out for the steer point when steering away
FollowCombineTask.LANE_BEHIND = 4       -- m: lane approach lines up this far behind the tail (front of the truck)
FollowCombineTask.LANE_TOLERANCE = 1.5  -- m sideways off the pipe lane that still counts as in it
FollowCombineTask.LANE_MIN_AHEAD = 6    -- m: the lane steer point is never closer ahead than this (full lock swings it in)

-- the cab's front and rear (m, along the harvester's heading, in its frame): the larger and the smaller of the two,
-- whichever way the cab faces
function FollowCombineTask:getCabSpanZ()
    local c = self.combine
    local hl = (self.vehicle.size ~= nil and self.vehicle.size.length or 0) / 2
    local fx, fy, fz = AutoDrive.localToWorld(self.vehicle, 0, 0, hl)
    local rx, ry, rz = AutoDrive.localToWorld(self.vehicle, 0, 0, -hl)
    local _, _, a = AutoDrive.worldToLocal(c, fx, fy, fz, c.ad.ADRootNode)
    local _, _, b = AutoDrive.worldToLocal(c, rx, ry, rz, c.ad.ADRootNode)
    return math.max(a, b), math.min(a, b)
end

-- true when the cab points within PARALLEL_ANGLE of the harvester's heading
function FollowCombineTask:isParallel(maxAngle)
    local hx, _, hz = AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
    local cfx, _, cfz = AutoDrive.localDirectionToWorld(self.combine, 0, 0, 1, self.combine.ad.ADRootNode)
    return hx * cfx + hz * cfz > math.cos(math.rad(maxAngle or FollowCombineTask.PARALLEL_ANGLE))
end

function FollowCombineTask:getOwnHalfWidth()
    local w = self.vehicle.size ~= nil and self.vehicle.size.width or 3
    for _, trailer in pairs(self.trailers or {}) do
        if trailer.size ~= nil and (trailer.size.width or 0) > w then
            w = trailer.size.width
        end
    end
    return w / 2
end

-- PropaineX edit (od.59): the harvester's pipe side (1 / -1, from the spot under the pipe), nil when unknown or behind
function FollowCombineTask:getPipeSide()
    if self.chasePos == nil or self.chaseSide == AutoDrive.CHASEPOS_REAR then
        return nil
    end
    local c = self.combine
    local cxl = AutoDrive.worldToLocal(c, self.chasePos.x, self.chasePos.y, self.chasePos.z, c.ad.ADRootNode)
    return cxl >= 0 and 1 or -1
end

-- PropaineX edit (od.59): keep-out gap on the given side: thin on the pipe side, wide everywhere else
function FollowCombineTask:getKeepOutGap(side)
    local w = self.combineTurnRate or 0
    local turningToward = w * (side or 0) > 0 and math.abs(w) >= FollowCombineTask.PIPE_GAP_TURN
    -- turning in toward the pipe side: it closes in on us, so the full gap there too while it turns
    if side ~= nil and side == self:getPipeSide() and not turningToward then
        return FollowCombineTask.KEEP_OUT_PIPE_GAP
    end
    return FollowCombineTask.KEEP_OUT_GAP
end

-- lane distance from the harvester's centre line
function FollowCombineTask:getKeepOutLane(side)
    local c = self.combine
    local halfW = AutoDrive.getHarvesterHalfSize(c)
    local lane = halfW + self:getOwnHalfWidth() + self:getKeepOutGap(side) -- PropaineX edit (od.59)
    if self.chasePos ~= nil and self.chaseSide ~= AutoDrive.CHASEPOS_REAR then
        local cxl = AutoDrive.worldToLocal(c, self.chasePos.x, self.chasePos.y, self.chasePos.z, c.ad.ADRootNode)
        lane = math.min(lane, math.abs(cxl))
    end
    -- whatever the pipe spot says: never closer than touching distance + KEEP_OUT_MIN
    return math.max(lane, halfW + self:getOwnHalfWidth() + FollowCombineTask.KEEP_OUT_MIN)
end

-- how far (m) the closest corner of the truck or a trailer is inside the keep-out strip (harvester's side +
-- KEEP_OUT_GAP) on the given side, among corners level with the harvester (front to back, + KEEP_OUT_LENGTH); <= 0 is
-- clear, nil when no corner is level with it. Corners, not centres: a trailer at an angle (or the harvester's tail
-- swinging in a turn) touches with a corner first.
function FollowCombineTask:getKeepOutIntrusion(side)
    local c = self.combine
    local halfW, halfL = AutoDrive.getHarvesterHalfSize(c)
    local reach = halfL + FollowCombineTask.KEEP_OUT_LENGTH
    local edge = halfW + self:getKeepOutGap(side) -- PropaineX edit (od.59)
    local worst, worstIsTrailer = nil, false
    local units = {self.vehicle}
    for _, trailer in pairs(self.trailers or {}) do
        if trailer ~= self.vehicle then
            table.insert(units, trailer)
        end
    end
    for _, unit in pairs(units) do
        if unit.components ~= nil and unit.components[1] ~= nil and unit.size ~= nil then
            local node = unit.components[1].node
            local hw, hl = (unit.size.width or 0) / 2, (unit.size.length or 0) / 2
            for _, k in ipairs({{-1, -1}, {1, -1}, {-1, 1}, {1, 1}, {-1, 0}, {1, 0}}) do
                local wx, wy, wz = localToWorld(node, k[1] * hw, 0, k[2] * hl)
                local lx, _, lz = AutoDrive.worldToLocal(c, wx, wy, wz, c.ad.ADRootNode)
                if math.abs(lz) <= reach and lx * side > 0 then
                    local inside = edge - lx * side
                    if worst == nil or inside > worst then
                        worst, worstIsTrailer = inside, unit ~= self.vehicle
                    end
                end
            end
        end
    end
    return worst, worstIsTrailer
end

function FollowCombineTask:keepOffHarvester(point, isSteer)
    if point == nil then
        return point
    end
    local c = self.combine
    local _, halfL = AutoDrive.getHarvesterHalfSize(c)
    local px, _, pz = AutoDrive.worldToLocal(c, point.x, point.y or 0, point.z, c.ad.ADRootNode)
    local vx, vy, vz = getWorldTranslation(self.vehicle.components[1].node)
    local tx = AutoDrive.worldToLocal(c, vx, vy, vz, c.ad.ADRootNode)
    local side = tx >= 0 and 1 or -1
    local lane = self:getKeepOutLane(side) -- PropaineX edit (od.59)
    local pipeSide = self:getPipeSide()
    -- PropaineX edit (od.59): on the pipe side only steer away once actually in the thin strip
    local driftIn = side == pipeSide and 0 or FollowCombineTask.DRIFT_IN
    local minX = lane
    local reach = halfL + FollowCombineTask.KEEP_OUT_LENGTH
    if isSteer then
        local inside = self:getKeepOutIntrusion(side)
        if inside ~= nil and inside > -driftIn then
            -- a corner closer than KEEP_OUT_GAP + DRIFT_IN to its side: steer out, further the deeper it is
            minX = math.max(minX, math.abs(px)) + FollowCombineTask.STEER_AWAY + math.max(inside, 0) * 2
            if not self.keepOutLogged then
                self.keepOutLogged = true
                Logging.info("[AD] %s: %.1f m from %s's side, steering away", ADDiag.name(self.vehicle),
                    math.max(self:getKeepOutGap(side) - inside, 0), ADDiag.name(c))
            end
            -- PropaineX edit (od.59): pushed out on the side WITHOUT the pipe: remember it, so the next try drops
            -- behind the tail and comes up the pipe side instead of the same line again
            if pipeSide ~= nil and side ~= pipeSide and self.pushedOutSide ~= side then
                self.pushedOutSide = side
                Logging.info("[AD] %s: pushed out on the side of %s without the pipe, next try comes up its pipe side",
                    ADDiag.name(self.vehicle), ADDiag.name(c))
            end
        elseif inside == nil or inside < -driftIn - 0.5 then
            self.keepOutLogged = nil
        end
        -- the steer point lies ahead but decides the steering beside the harvester: it counts at any distance
        -- while we are beside or behind it
        reach = math.max(reach, math.abs(pz) + 1)
    end
    if math.abs(pz) > reach or (px * side >= minX and not (isSteer and self.keepOutLogged)) then
        return point
    end
    local wx, _, wz = AutoDrive.localToWorld(c, side * minX, 0, pz, c.ad.ADRootNode)
    return {x = wx, y = point.y, z = wz}
end

-- behind the tail and off the pipe lane: {target, steer} that line it up in the lane behind the tail; nil otherwise
function FollowCombineTask:getLaneApproach(tx, tz, cxl, halfW, halfL)
    if self.chaseSide == AutoDrive.CHASEPOS_REAR then
        return nil
    end
    local frontZ = self:getCabSpanZ()
    if frontZ > -halfL or math.abs(tx - cxl) <= FollowCombineTask.LANE_TOLERANCE then
        return nil
    end
    -- drive toward the pipe spot (speed), steer at a point in the pipe lane LOOK_AHEAD m ahead of us but never level
    -- with the harvester (it stays behind its tail until we are lined up): it lines up in the lane while it rolls on
    -- (a lane point to stop at left it standing just off the lane)
    local c = self.combine
    local _, y, _ = getWorldTranslation(self.vehicle.components[1].node)
    local steerZ = math.max(tz + FollowCombineTask.LANE_MIN_AHEAD, math.min(tz + FollowCombineTask.LOOK_AHEAD, -halfL - FollowCombineTask.LANE_BEHIND))
    local sx, _, sz = AutoDrive.localToWorld(c, cxl, 0, steerZ, c.ad.ADRootNode)
    if not self.laneLogged then
        self.laneLogged = true
        Logging.info("[AD] %s: behind %s, lining up on its pipe side before coming up", ADDiag.name(self.vehicle), ADDiag.name(c))
    end
    return {target = self.chasePos, steer = {x = sx, y = y, z = sz}}
end

FollowCombineTask.LOOK_AHEAD = 12 -- m: steering aims this far along the combine's line (longer = straighter, calmer)
FollowCombineTask.TURN_DEADBAND = 0.07 -- rad/s (4 deg/s): less than this counts as straight (combine wobble)
FollowCombineTask.LINE_SMOOTH = 3000 -- ms: the straight line follows the combine's heading this slowly

FollowCombineTask.FLAT_OUT = 200 -- km/h: no cap of our own (AutoDrive's chase had an unexplained 40); the field speed limit setting caps it

FollowCombineTask.PIPE_LOCK_RANGE = 50 -- m
FollowCombineTask.LEAD_TIME = 1.5 -- s

-- the combine's turn rate (rad/s, + = toward local +x), smoothed: last frame's heading seen from the current frame
function FollowCombineTask:updateTurnRate(dt)
    local c = self.combine
    local cx, cy, cz = getWorldTranslation(c.components[1].node)
    local fx, _, fz = AutoDrive.localDirectionToWorld(c, 0, 0, 1, c.ad.ADRootNode)
    local rate = 0
    if self.lastCombineFwd ~= nil and dt > 0 then
        local px, _, pz = AutoDrive.worldToLocal(c, cx + self.lastCombineFwd.x, cy, cz + self.lastCombineFwd.z, c.ad.ADRootNode)
        rate = -math.atan2(px, pz) / (dt / 1000)
    end
    self.lastCombineFwd = {x = fx, z = fz}
    self.combineTurnRate = 0.9 * (self.combineTurnRate or rate) + 0.1 * rate -- smoothed
end

-- the chase point, moved with the combine as if it kept its speed and turn rate for LEAD_TIME
function FollowCombineTask:predictChasePos(dt)
    local c = self.combine
    local cx, cy, cz = getWorldTranslation(c.components[1].node)
    local fx, _, fz = AutoDrive.localDirectionToWorld(c, 0, 0, 1, c.ad.ADRootNode)
    -- PropaineX edit (od.56): turn rate now kept up to date every frame by updateTurnRate (it went stale while backing
    -- off, so the back-off never saw the turn end)
    local w = self.combineTurnRate or 0
    -- straight line: below TURN_DEADBAND the combine counts as driving straight (no chasing its wobble)
    if math.abs(w) < FollowCombineTask.TURN_DEADBAND then
        w = 0
    end
    local v = c.lastSpeedReal * 1000 -- m/s
    local T = FollowCombineTask.LEAD_TIME
    if v < 0.1 or self.chasePos == nil then
        return self.chasePos
    end
    -- chase point in combine coordinates
    local ox, _, oz = AutoDrive.worldToLocal(c, self.chasePos.x, self.chasePos.y, self.chasePos.z, c.ad.ADRootNode)
    local a = w * T
    local mx, mz
    if math.abs(w) < 0.0001 then
        mx, mz = 0, v * T
    else
        mx, mz = v / w * (1 - math.cos(a)), v / w * math.sin(a)
    end
    local px = mx + ox * math.cos(a) + oz * math.sin(a)
    local pz = mz - ox * math.sin(a) + oz * math.cos(a)
    -- keep only what the TURN adds: minus the straight-ahead travel v*T (that would put it ahead of the pipe)
    pz = pz - v * T
    local wx, wy, wz = AutoDrive.localToWorld(c, px, 0, pz, c.ad.ADRootNode)
    return {x = wx, y = self.chasePos.y, z = wz}
end

-- PropaineX edit (3.8.5.4): which way the combine is turning, from its heading HEADING_SAMPLE ms ago: true when its
-- nose swings away from us (we are on the outside, its tail swings toward us). Convention-free (dot product).
FollowCombineTask.HEADING_SAMPLE = 1000
FollowCombineTask.SWING_MIN = 4 -- deg per sample

function FollowCombineTask:sampleCombineHeading(dt)
    self.headingSampleAge = (self.headingSampleAge or FollowCombineTask.HEADING_SAMPLE) + dt
    if self.headingSampleAge >= FollowCombineTask.HEADING_SAMPLE then
        self.prevHeading = self.curHeadingSample
        self.curHeadingSample = self:getCombineHeading()
        self.headingSampleAge = 0
    end
end

function FollowCombineTask:isOutsideOfTurn()
    if self.prevHeading == nil then
        return false
    end
    local heading = self:getCombineHeading()
    -- still swinging (more than SWING_MIN deg in the last sample): a combine driving straight again is no reason to
    -- pull forward (after the turn it drives across our front)
    if math.abs(AutoDrive.angleBetween(self.prevHeading, heading)) < FollowCombineTask.SWING_MIN then
        return false
    end
    local vx, _, vz = getWorldTranslation(self.vehicle.components[1].node)
    local cx, _, cz = getWorldTranslation(self.combine.components[1].node)
    return (heading.x - self.prevHeading.x) * (vx - cx) + (heading.z - self.prevHeading.z) * (vz - cz) < 0
end

-- PropaineX edit (3.8.4.4): pull forward out of the combine's way (STATE_CLEAR_FORWARD), logged
function FollowCombineTask:startClearForward(why)
    Logging.info("[AD] %s: %s, pulling forward out of the way", ADDiag.name(self.vehicle), why)
    local x, y, z = getWorldTranslation(self.vehicle.components[1].node)
    self.clearStartLocation = {x = x, y = y, z = z}
    self.clearTime = 0
    self.clearStoppedTime = 0
    self.clearedThisTurn = true
    self.state = FollowCombineTask.STATE_CLEAR_FORWARD
end

function FollowCombineTask:shouldWaitForChasePos(dt)
    -- PropaineX edit (3.7.0.4): the combine moves -> we move, however far off and whichever way the chase point lies
    -- (driveToPoint turns round to a point behind). Only a block stops it (collision check, stuck timer). The angle
    -- timer is held at zero too, so it doesn't back away after 15 s. Forage harvesters: unchanged.
    -- Also for a standing Active unloading harvester we are not yet at: drive up to it (at the pipe the hold in
    -- update() keeps it still).
    if not self.combine.ad.isChopper and (self.combine.lastSpeedReal > 0.0004
        or (self.activeUnloading and self.combine.ad.isHarvester)) then
        self.angleWrongTimer:timer(false)
        return false
    end
    local angle = self:getAngleToChasePos()
    self.angleWrongTimer:timer(angle > 50, 3000, dt)
    local _, _, diffZ = AutoDrive.worldToLocal(self.vehicle, self.chasePos.x, self.chasePos.y, self.chasePos.z)
    return self.angleWrongTimer:done() or  diffZ <= -1 --or (not self.combine.ad.sensors.frontSensorFruit:pollInfo())
end

function FollowCombineTask:isCaughtCurrentChaseSide()
    local caught = false
    local angle = self:getAngleToChasePos()
    local vehicleX, vehicleY, vehicleZ = getWorldTranslation(self.vehicle.components[1].node)
    local _, _, diffZ = AutoDrive.worldToLocal(self.vehicle, self.chasePos.x, self.chasePos.y, self.chasePos.z)

    local diffX, _, _ = AutoDrive.worldToLocal(self.combine, vehicleX, vehicleY, vehicleZ, self.combine.ad.ADRootNode)
    if ((angle < 15 and diffZ >= 0) or (angle > 165 and diffZ < 0)) and (self.angleToCombineHeading < 15) and (AutoDrive.sign(diffX) == self.chaseSide or self.chaseSide == AutoDrive.CHASEPOS_REAR) then
        caught = true
    end
    return caught
end


function FollowCombineTask:getAngleToCombineHeading()
    if self.vehicle == nil or self.combine == nil then
        return math.huge
    end

    local combineRx, _, combineRz = AutoDrive.localDirectionToWorld(self.combine, 0, 0, 1, self.combine.ad.ADRootNode)
    local rx, _, rz =  AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)

    return math.abs(AutoDrive.angleBetween({x = rx, z = rz}, {x = combineRx, z = combineRz}))
end

function FollowCombineTask:getAngleToChasePos()
    local worldX, _, worldZ = getWorldTranslation(self.vehicle.components[1].node)
    local rx, _, rz =  AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
    local angle = math.abs(AutoDrive.angleBetween({x = rx, z = rz}, {x = self.chasePos.x - worldX, z = self.chasePos.z - worldZ}))
    return angle
end

function FollowCombineTask:getAngleToCobine()
    local worldX, _, worldZ = getWorldTranslation(self.vehicle.components[1].node)
    local rx, _, rz =  AutoDrive.localDirectionToWorld(self.vehicle, 0, 0, 1)
    local referenceAxis = self.combine.components[1].node
    if self.combine.components[2] ~= nil and self.combine.components[2].node ~= nil then
        referenceAxis = self.combine.components[2].node
    end

    local combineX, _, combineZ = getWorldTranslation(referenceAxis)
    local angle = math.abs(AutoDrive.angleBetween({x = rx, z = rz}, {x = combineX - worldX, z = combineZ - worldZ}))
    return angle
end

function FollowCombineTask:abort()
end

function FollowCombineTask:finished()
    FollowCombineTask.debugMsg(self.vehicle, "FollowCombineTask:finished()")
    self.vehicle.ad.taskModule:setCurrentTaskFinished()
end

function FollowCombineTask:getExcludedVehiclesForCollisionCheck()
    local excludedVehicles = {}
    if self.state == FollowCombineTask.STATE_CHASING or self.state == FollowCombineTask.STATE_WAIT_FOR_TURN then
        -- PropaineX edit (3.8.4.4): not while pulling forward: the combine in front counts as blocked (-> back up)
        table.insert(excludedVehicles, self.combine:getRootVehicle())
    end
    return excludedVehicles
end

function FollowCombineTask:setStateNames()
    if self.statesToNames == nil then
        self.statesToNames = {}
        for name, id in pairs(FollowCombineTask) do
            if string.sub(name, 1, 6) == "STATE_" then
                self.statesToNames[id] = name
            end
        end
    end
end

function FollowCombineTask:getStateName(state)
    local requestedState = state
    if requestedState == nil then
        requestedState = self.state
    end
    if requestedState == nil then
        Logging.error("[AD] FollowCombineTask: Could not find name for state ->%s<- !", tostring(requestedState))
    end
    return self.statesToNames[requestedState] or ""
end

function FollowCombineTask:resetAllTimers()
    -- self.stuckTimer:timer(false) -- stuckTimer reset by speed changes
    self.angleWrongTimer:timer(false)
    self.waitForTurnTimer:timer(false)
    self.dischargeTimer:timer(false)
    self.fillingTimer:timer(false)
    self.waitForPassByTimer:timer(false)
    self.chaseTimer:timer(false)
    self.reverseTimer:timer(false)
    self.waitTimer:timer(false)
    self.turnStartHeading = nil -- PropaineX edit (3.7.0.4)
end


function FollowCombineTask:getI18nInfo()
    local text = "$l10n_AD_task_chasing_combine;"
    if self.state == FollowCombineTask.STATE_CHASING then
        if not self:isCaughtCurrentChaseSide() then
            text = text .. " - " .. "$l10n_AD_task_catching_chase_side;" .. ": "
        else
            text = text .. " - " .. "$l10n_AD_task_chase_side;" .. ": "
        end
        if self.chaseSide == AutoDrive.CHASEPOS_LEFT then
            text = text .. " - " .. "$l10n_AD_task_chase_side_left;"
        elseif self.chaseSide == AutoDrive.CHASEPOS_REAR then
            text = text .. " - " .. "$l10n_AD_task_chase_side_rear;"
        elseif self.chaseSide == AutoDrive.CHASEPOS_RIGHT then
            text = text .. " - " .. "$l10n_AD_task_chase_side_right;"
        end
    elseif self.state == FollowCombineTask.STATE_REVERSING_FROM_CHOPPER or self.state == FollowCombineTask.STATE_WAIT_FOR_TURN then
        text = text .. " - " .. "$l10n_AD_task_wait_for_combine_turn;"
    elseif self.state == FollowCombineTask.STATE_REVERSING then
        text = text .. " - " .. "$l10n_AD_task_reversing_from_combine;"
    elseif self.state == FollowCombineTask.STATE_WAIT_FOR_PASS_BY then
        text = text .. " - " .. "$l10n_AD_task_wait_for_combine_pass_by;"
    elseif self.state == FollowCombineTask.STATE_WAIT_BEFORE_FINISH then
        text = text .. " - " .. "$l10n_AD_task_waiting_for_room;"
    end
    return text
end

function FollowCombineTask.debugMsg(vehicle, debugText, ...)
    if FollowCombineTask.debug == true then
        AutoDrive.debugMsg(vehicle, debugText, ...)
    else
        AutoDrive.debugPrint(vehicle, AutoDrive.DC_COMBINEINFO, debugText, ...)
    end
end
