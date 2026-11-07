-- PropaineX edit: drive a waiting unloader to a spot out of the harvesters' way (ADUnloaderClear), with the
-- pathfinder (field and fruit settings as usual). CombineUnloaderMode then waits for a call again.
MoveClearOfHarvesterTask = ADInheritsFrom(AbstractTask)

MoveClearOfHarvesterTask.STATE_PATHPLANNING = 1
MoveClearOfHarvesterTask.STATE_DRIVING = 2

MoveClearOfHarvesterTask.PLAN_TIME = 10000   -- ms at most for the pathfinder (3.6.0.4: was 30000)
MoveClearOfHarvesterTask.STATE_STRAIGHT = 3
-- PropaineX edit (3.6.0.4): moving aside after no path to a harvester (straightFallback): when there is no spot or no
-- path to it, drive STRAIGHT_DISTANCE straight ahead (reverse when it can't move forward)
MoveClearOfHarvesterTask.STRAIGHT_DISTANCE = 25 -- m
MoveClearOfHarvesterTask.STRAIGHT_TIME = 30000  -- ms at most
MoveClearOfHarvesterTask.STUCK_TIME = 3000      -- ms without moving forward before it reverses instead
MoveClearOfHarvesterTask.DRIVE_TIME = 120000 -- ms at most for the drive

function MoveClearOfHarvesterTask:new(vehicle, target, direction, straightFallback)
    local o = MoveClearOfHarvesterTask:create()
    o.vehicle = vehicle
    o.target = target
    o.direction = direction
    o.straightFallback = straightFallback
    return o
end

function MoveClearOfHarvesterTask:startStraight()
    self.state = MoveClearOfHarvesterTask.STATE_STRAIGHT
    self.elapsed = 0
    self.stillTime = 0
    self.reversing = false
    local x, _, z = getWorldTranslation(self.vehicle.components[1].node)
    self.straightStart = {x = x, z = z}
end

-- the path finder found nothing (in time): drive straight when allowed, else give up as before
function MoveClearOfHarvesterTask:onNoPath()
    if self.straightFallback then
        self:startStraight()
    else
        ADUnloaderClear.onMoveFailed(self.vehicle)
        self:finished()
    end
end

function MoveClearOfHarvesterTask:setUp()
    if self.target == nil then
        self:startStraight()
        return
    end
    self.state = MoveClearOfHarvesterTask.STATE_PATHPLANNING
    self.elapsed = 0
    local pfm = self.vehicle.ad.pathFinderModule
    pfm:reset()
    pfm:startPathPlanningTo({x = self.target.x, y = self.target.y, z = self.target.z}, {x = self.direction.x, z = self.direction.z})
    table.insert(pfm.appendWayPoints, {x = self.target.x, y = self.target.y, z = self.target.z})
end

function MoveClearOfHarvesterTask:update(dt)
    self.elapsed = self.elapsed + dt
    local pfm = self.vehicle.ad.pathFinderModule
    if self.state == MoveClearOfHarvesterTask.STATE_PATHPLANNING then
        if pfm:hasFinished() then
            local wayPoints = pfm:getPath()
            if wayPoints == nil or #wayPoints == 0 then
                self:onNoPath()
                return
            end
            self.vehicle.ad.drivePathModule:setWayPoints(wayPoints)
            self.state = MoveClearOfHarvesterTask.STATE_DRIVING
            self.elapsed = 0
        elseif self.elapsed > MoveClearOfHarvesterTask.PLAN_TIME then
            pfm:abort()
            self:onNoPath()
        else
            pfm:update(dt)
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            self.vehicle.ad.specialDrivingModule:update(dt)
        end
    elseif self.state == MoveClearOfHarvesterTask.STATE_STRAIGHT then
        local x, _, z = getWorldTranslation(self.vehicle.components[1].node)
        local distance = MathUtil.vector2Length(x - self.straightStart.x, z - self.straightStart.z)
        if distance >= MoveClearOfHarvesterTask.STRAIGHT_DISTANCE or self.elapsed > MoveClearOfHarvesterTask.STRAIGHT_TIME then
            self.vehicle.ad.specialDrivingModule:stopVehicle()
            ADUnloaderClear.onMoveDone(self.vehicle)
            self:finished()
            return
        end
        if (self.vehicle.lastSpeedReal or 0) < 0.0003 then
            self.stillTime = self.stillTime + dt
        else
            self.stillTime = 0
        end
        if not self.reversing and self.stillTime > MoveClearOfHarvesterTask.STUCK_TIME then
            self.reversing = true
            self.stillTime = 0
            self.straightStart = {x = x, z = z}
        end
        if self.reversing then
            self.vehicle.ad.specialDrivingModule:driveReverse(dt, 8, 1, self.vehicle.ad.trailerModule:canBeHandledInReverse())
        else
            self.vehicle.ad.specialDrivingModule:driveForward(dt)
        end
    else
        if self.vehicle.ad.drivePathModule:isTargetReached() then
            ADUnloaderClear.onMoveDone(self.vehicle)
            self:finished()
        elseif self.elapsed > MoveClearOfHarvesterTask.DRIVE_TIME then
            ADUnloaderClear.onMoveFailed(self.vehicle)
            self:finished()
        else
            self.vehicle.ad.drivePathModule:update(dt)
        end
    end
end

function MoveClearOfHarvesterTask:abort()
    if self.state == MoveClearOfHarvesterTask.STATE_PATHPLANNING and self.target ~= nil then
        self.vehicle.ad.pathFinderModule:abort()
    end
end

function MoveClearOfHarvesterTask:finished()
    self.vehicle.ad.taskModule:setCurrentTaskFinished()
end

function MoveClearOfHarvesterTask:getInfoText()
    return g_i18n:getText("AD_task_move_clear")
end

function MoveClearOfHarvesterTask:getI18nInfo()
    return "$l10n_AD_task_move_clear;"
end
