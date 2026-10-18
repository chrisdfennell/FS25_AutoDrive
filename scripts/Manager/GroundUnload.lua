-- Tipping on the ground (bunker silo / heap areas): AutoDrive drives slowly through the area while tipping, to
-- spread the load (upstream). Vehicle setting groundUnload "stand still": the vehicle stops at the first place it
-- can tip and stays there. When nothing comes out any more for a while (the heap is as high as it gets), it moves
-- on slowly until the load runs again, and stops again. Reversing into a silo is left as it is.
ADGroundUnload = {}

ADGroundUnload.DRIVE_THROUGH = 1
ADGroundUnload.STAND_STILL = 2
-- no litres tipped for this long (ms): move on to the next free place
ADGroundUnload.STALL_TIME = 4000
-- less than this (litres) is "nothing tipped"
ADGroundUnload.MIN_FLOW = 1

function ADGroundUnload.isStandStill(vehicle)
    if vehicle == nil or vehicle.ad == nil or AutoDrive.getSetting("groundUnload", vehicle) ~= ADGroundUnload.STAND_STILL then
        return false
    end
    local drivePathModule = vehicle.ad.drivePathModule
    return not (drivePathModule ~= nil and drivePathModule:getIsReversing())
end

-- while tipping on the ground: true = stand still, false = drive on (spread, or move on from a full heap)
function ADGroundUnload.shouldStop(vehicle, fillLevel, dt)
    if not ADGroundUnload.isStandStill(vehicle) then
        return false
    end
    local state = vehicle.ad.groundUnloadState
    if state == nil or fillLevel > state.fillLevel + ADGroundUnload.MIN_FLOW then
        -- a new load
        state = {fillLevel = fillLevel, stalled = 0}
        vehicle.ad.groundUnloadState = state
    end
    if fillLevel < state.fillLevel - ADGroundUnload.MIN_FLOW then
        -- the load runs: stay here
        state.fillLevel = fillLevel
        state.stalled = 0
        return true
    end
    state.stalled = state.stalled + (dt or 0)
    return state.stalled < ADGroundUnload.STALL_TIME
end

function ADGroundUnload.reset(vehicle)
    if vehicle ~= nil and vehicle.ad ~= nil then
        vehicle.ad.groundUnloadState = nil
    end
end

-- the unload task: stand still or keep following the route
function ADGroundUnload.drive(task, dt)
    local vehicle = task.vehicle
    if ADGroundUnload.shouldStop(vehicle, AutoDrive.getAllFillLevels(task.trailers), dt) then
        vehicle.ad.specialDrivingModule.motorShouldNotBeStopped = true
        vehicle.ad.specialDrivingModule:stopVehicle()
        vehicle.ad.specialDrivingModule:update(dt)
    else
        vehicle.ad.drivePathModule:update(dt)
    end
end
