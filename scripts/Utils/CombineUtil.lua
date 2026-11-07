
-- harvester types
function AutoDrive.setCombineType(vehicle)
    if vehicle == nil then
        return false
    end
    if vehicle.ad == nil then
        vehicle.ad = {}
    end
    local rootVehicle = vehicle:getRootVehicle()
    local rootVehicleName = rootVehicle and rootVehicle:getName() or "no rootVehicle!!!"
    vehicle.ad.hasCombine = false -- vehicle is any combine or has attached one
    vehicle.ad.isAutoAimingChopper = false -- chopper with flexible self targeting pipe
    vehicle.ad.isFixedPipeChopper = false -- chopper with fixed pipe
    vehicle.ad.isChopper = false -- chopper, without bunker
    vehicle.ad.isHarvester = false -- harvester with bunker

    if (vehicle.spec_combine ~= nil and vehicle.spec_pipe ~= nil and vehicle.spec_combine.isBufferCombine == true and vehicle.spec_pipe.numAutoAimingStates > 0) then
        vehicle.ad.isAutoAimingChopper = true
    end
    if (vehicle.spec_combine ~= nil and vehicle.spec_pipe ~= nil and vehicle.spec_combine.isBufferCombine == true and vehicle.spec_pipe.numAutoAimingStates == 0) then
        vehicle.ad.isFixedPipeChopper = true
    end
    if (vehicle.spec_combine ~= nil and vehicle.spec_pipe ~= nil and vehicle.spec_combine.isBufferCombine == true) then
        vehicle.ad.isChopper = true
    end
    if (vehicle.spec_combine ~= nil and vehicle.spec_pipe ~= nil and not vehicle.spec_combine.isBufferCombine) then
        vehicle.ad.isHarvester = true
    end

    rootVehicle.ad.hasCombine = vehicle.ad.isAutoAimingChopper or vehicle.ad.isFixedPipeChopper or vehicle.ad.isChopper or vehicle.ad.isHarvester
    return rootVehicle.ad.hasCombine
end

-- PropaineX edit (3.10.0.0): NEXAT. The Nexat's harvester module (nexco) sits on the carrier (widespanVehicle) turned
-- 90 deg: the module faces the way it harvests, the carrier drives crab-wise. AutoDrive only knew "same way" or
-- "reversed" (> 100 deg) trailed harvesters, so everything read from the carrier (its heading, size, sensors) was
-- 90 deg off. A harvester module mounted 45-135 deg to its carrier counts as sideways; for it the module's own frame
-- is the travel frame, and the carrier's length is the rig's width.
function AutoDrive.isSidewaysHarvester(combine)
    if combine == nil or not combine.isTrailedHarvester or combine.trailingVehicle == nil
        or combine.components == nil or (combine.ad ~= nil and combine.ad.isReverseAttached) then
        return false
    end
    if combine.adSideways == nil then
        local carrier = combine.trailingVehicle
        if carrier.components == nil then
            return false
        end
        local vx, _, vz = localDirectionToWorld(carrier.components[1].node, 0, 0, 1)
        local cx, _, cz = localDirectionToWorld(combine.components[1].node, 0, 0, 1)
        combine.adSideways = math.abs(vx * cx + vz * cz) < 0.7071 -- cos 45 deg
        if combine.adSideways then
            Logging.info("[AD] %s: harvester module mounted sideways on %s (Nexat), using the module's heading",
                tostring(combine.getName ~= nil and combine:getName() or "?"), tostring(carrier.getName ~= nil and carrier:getName() or "?"))
        end
    end
    return combine.adSideways
end

-- the sideways harvester module of a harvester or its carrier, nil when it isn't one
function AutoDrive.getSidewaysHarvester(vehicle)
    if vehicle == nil then
        return nil
    end
    if AutoDrive.isSidewaysHarvester(vehicle) then
        return vehicle
    end
    local module = vehicle.ad ~= nil and vehicle.ad.attachableCombine or nil
    if module ~= nil and module ~= vehicle and AutoDrive.isSidewaysHarvester(module) then
        return module
    end
    return nil
end

-- the vehicle whose own frame (z = forward) is the harvester's direction of travel: the module on a Nexat, else as given
function AutoDrive.getHarvesterFrameVehicle(vehicle)
    return AutoDrive.getSidewaysHarvester(vehicle) or vehicle
end

-- half width, half length of the whole harvester in its travel frame (Nexat: carrier and module together)
function AutoDrive.getHarvesterHalfSize(combine)
    local w = combine.size ~= nil and combine.size.width or 3
    local l = combine.size ~= nil and combine.size.length or 10
    local module = AutoDrive.getSidewaysHarvester(combine)
    if module ~= nil then
        local carrier = module.trailingVehicle
        w = math.max(module.size.width or 0, carrier.size ~= nil and carrier.size.length or 0)
        l = math.max(module.size.length or 0, carrier.size ~= nil and carrier.size.width or 0)
    end
    return w / 2, l / 2
end

-- the combine's sensors (left/right/front... of the way it harvests). Nexat: the carrier's sensors face 90 deg off, so
-- the module gets its own set, the side ones moved out past the carrier's wheel units.
function AutoDrive.getCombineSensors(combine, rootVehicle)
    local module = AutoDrive.getSidewaysHarvester(combine)
    if module == nil then
        return combine.ad.sensors or rootVehicle.ad.sensors
    end
    if module.adNexatSensors == nil then
        local shared = module.ad -- the carrier's ad table (shared with the module)
        local saved = shared.sensors
        shared.sensors = nil
        ADSensor:addSensorsToVehicle(module)
        module.adNexatSensors = shared.sensors
        shared.sensors = saved
        local halfW = AutoDrive.getHarvesterHalfSize(module)
        for name, sign in pairs({leftSensor = 1, leftSensorFruit = 1, leftSensorField = 1, rightSensor = -1, rightSensorFruit = -1, rightSensorField = -1}) do
            local sensor = module.adNexatSensors[name]
            if sensor ~= nil and sensor.location ~= nil then
                sensor.location.x = sign * (halfW + 1 + sensor.width / 2)
            end
        end
    end
    return module.adNexatSensors
end


function AutoDrive.getDischargeNode(combine)
    local dischargeNode = nil
    if combine.spec_dischargeable ~= nil then
        for _, dischargeNodeIter in pairs(combine.spec_dischargeable.dischargeNodes) do
            dischargeNode = dischargeNodeIter
        end
        if combine.getPipeDischargeNodeIndex ~= nil then
            dischargeNode = combine.spec_dischargeable.dischargeNodes[combine:getPipeDischargeNodeIndex()]
        end
        return dischargeNode.node
    else
        return nil
    end
end

function AutoDrive.validateCachedPipeData(combine)
    -- check if the harvester has been reconfigured, invalidate cache
    if combine.ad ~= nil and combine.ad.pipeRoot ~= nil and not entityExists(combine.ad.pipeRoot) then
        combine.ad.pipeRoot = nil
        combine.ad.storedPipeSide = nil
        combine.ad.storedPipeLength = nil
    end
end

function AutoDrive.getPipeRoot(combine)
    if combine.ad ~= nil and combine.ad.pipeRoot ~= nil then
        return combine.ad.pipeRoot
    end
    local dischargeNode = AutoDrive.getDischargeNode(combine)
    local pipeRoot = nil

    if dischargeNode then
        for _, component in ipairs(combine.components) do

            local node = dischargeNode
            local count = 0
            repeat
                node = getParent(node)
                count = count + 1
            until ((node == component.node) or (node == 0) or (node == nil) or count >= 100)

            if node and node ~= 0 then
                -- found
                pipeRoot = node
                break
            end
        end
    end
    if pipeRoot == nil or pipeRoot == 0 then
        -- fallback
        pipeRoot = combine.components[1].node
    end

    if combine.ad ~= nil then
        combine.ad.pipeRoot = pipeRoot
    end
    return pipeRoot
end

-- ret: -1 right, 1 left, 0 behind
-- not for sugarcane harvesters, choppers!!!
function AutoDrive.getPipeSide(combine)
    if combine.ad ~= nil and combine.ad.storedPipeSide ~= nil then
        return combine.ad.storedPipeSide
    end
    local combineNode = AutoDrive.getPipeRoot(combine)
    local dischargeNode = AutoDrive.getDischargeNode(combine)
    local dischargeX, dichargeY, dischargeZ = getWorldTranslation(dischargeNode)
    local diffX, _, _ = AutoDrive.worldToLocal(combine, dischargeX, dichargeY, dischargeZ, combineNode)
    if combine.ad ~= nil and (combine.ad.isFixedPipeChopper or combine.ad.isHarvester) and AutoDrive.isPipeOut(combine) then
        combine.ad.storedPipeSide = AutoDrive.sign(diffX)
    end
    return AutoDrive.sign(diffX)
end

function AutoDrive.getPipeLength(combine)
    if combine.ad ~= nil and combine.ad.storedPipeLength ~= nil then
        return combine.ad.storedPipeLength
    end

    local pipeRootX, _ , pipeRootZ = getWorldTranslation(AutoDrive.getPipeRoot(combine))
    local dischargeX, dischargeY, dischargeZ = getWorldTranslation(AutoDrive.getDischargeNode(combine))
    local length = MathUtil.vector3Length(pipeRootX - dischargeX,
                                        0, 
                                        pipeRootZ - dischargeZ)
    --AutoDrive.debugPrint(combine, AutoDrive.DC_COMBINEINFO, "AutoDrive.getPipeLength - " .. length)
    if (combine.ad.isFixedPipeChopper or combine.ad.isHarvester) and AutoDrive.isPipeOut(combine) then
        local combineNode = AutoDrive.getPipeRoot(combine)
        local dischargeX, dichargeY, dischargeZ = getWorldTranslation(AutoDrive.getDischargeNode(combine))
        local diffX, _, _ = AutoDrive.worldToLocal(combine, dischargeX, dichargeY, dischargeZ, combineNode)
        length = math.abs(diffX)

        -- Store pipe length for 'normal' harvesters
        if combine.ad ~= nil then
            combine.ad.storedPipeLength = length
        end
    end

    return length
end

function AutoDrive.isPipeOut(combine)

    local function isPipeOut(combine)
        if (combine.spec_combine ~= nil and combine.spec_pipe ~= nil and combine.spec_dischargeable ~= nil) then
            if combine.getIsDischargeNodeActive ~= nil and combine.getPipeDischargeNodeIndex ~= nil then
                local pipeDischargeNodeIndex = combine:getPipeDischargeNodeIndex()
                if pipeDischargeNodeIndex and pipeDischargeNodeIndex > 0 then
                    local spec_dischargeable = combine.spec_dischargeable
                    if spec_dischargeable and spec_dischargeable.dischargeNodes and #spec_dischargeable.dischargeNodes > 0 then
                        local dischargeNode = spec_dischargeable.dischargeNodes[pipeDischargeNodeIndex]
                        if dischargeNode and combine:getIsDischargeNodeActive(dischargeNode) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    if combine.spec_combine ~= nil then
        return isPipeOut(combine)
    else        
        for _, implement in pairs(AutoDrive.getAllImplements(combine)) do
            if implement and isPipeOut(implement) then
                return true
            end
        end
    end
    return false
end

function AutoDrive.getAIMarkerWidth(object)
    local retWidth = 0
    if object ~= nil and object.getAIMarkers ~= nil then
        local aiLeftMarker, aiRightMarker = object:getAIMarkers()
        if aiLeftMarker ~= nil and aiRightMarker ~= nil then
            local left, _, _ = localToLocal(aiLeftMarker, object.rootNode, 0, 0, 0)
            local right, _, _ = localToLocal(aiRightMarker, object.rootNode, 0, 0, 0)
            if left < right then
                left, right = right, left
            end
            retWidth = left - right
        end
    end
    return retWidth
end

function AutoDrive.getAISizeMarkerWidth(object)
    local retWidth = 0
    if object ~= nil and object.getAISizeMarkers ~= nil then
        local aiLeftMarker, aiRightMarker = object:getAISizeMarkers()
        if aiLeftMarker ~= nil and aiRightMarker ~= nil then
            local left, _, _ = localToLocal(aiLeftMarker, object.rootNode, 0, 0, 0)
            local right, _, _ = localToLocal(aiRightMarker, object.rootNode, 0, 0, 0)
            if left < right then
                left, right = right, left
            end
            retWidth = left - right
        end
    end
    return retWidth
end

function AutoDrive.getFrontToolWidth(vehicle, forced)
    if vehicle.ad ~= nil and vehicle.ad.frontToolWidth ~= nil and not (forced == true) then
        return vehicle.ad.frontToolWidth
    end
    local widthOfFrontTool = 0

    -- check for AIMarkers
    local implements = AutoDrive.getAllImplements(vehicle, false)
    for _, implement in pairs(implements) do
        --Check if tool is in front of vehicle
        local toolX, toolY, toolZ = getWorldTranslation(implement.components[1].node)
        local _, _, offsetZ =  AutoDrive.worldToLocal(vehicle, toolX, toolY, toolZ)
        if offsetZ > 0 then
            widthOfFrontTool = math.max(widthOfFrontTool, AutoDrive.getAIMarkerWidth(implement))
        end
    end

    if widthOfFrontTool == 0 then
        -- check for AISizeMarkers
        for _, implement in pairs(implements) do
            --Check if tool is in front of vehicle
            local toolX, toolY, toolZ = getWorldTranslation(implement.components[1].node)
            local _, _, offsetZ =  AutoDrive.worldToLocal(vehicle, toolX, toolY, toolZ)
            if offsetZ > 0 then
                widthOfFrontTool = math.max(widthOfFrontTool, AutoDrive.getAISizeMarkerWidth(implement))
            end
        end
    end

    if widthOfFrontTool == 0 then
        -- if AIMarkers not available or returned 0, get tool size as defined in vehicle XML - the worst case, see rsmDS900.xml
        for _, implement in pairs(implements) do
            if implement.size.width ~= nil then
                --Check if tool is in front of vehicle
                local toolX, toolY, toolZ = getWorldTranslation(implement.components[1].node)
                local _, _, offsetZ =  AutoDrive.worldToLocal(vehicle, toolX, toolY, toolZ)
                if offsetZ > 0 then
                    widthOfFrontTool = math.abs(implement.size.width)
                end
            end
        end
    end

    if vehicle.ad ~= nil then
        vehicle.ad.frontToolWidth = widthOfFrontTool
    end

    return widthOfFrontTool
end

function AutoDrive.getFrontToolLength(vehicle)
    if vehicle.ad ~= nil and vehicle.ad.frontToolLength ~= nil then
        return vehicle.ad.frontToolLength
    end
    local lengthOfFrontTool = 0

    local implements = AutoDrive.getAllImplements(vehicle, false)
    for _, implement in pairs(implements) do
        if implement.size.width ~= nil then
            --Check if tool is in front of vehicle
            local toolX, toolY, toolZ = getWorldTranslation(implement.components[1].node)
            local _, _, offsetZ =  AutoDrive.worldToLocal(vehicle, toolX, toolY, toolZ)
            if offsetZ > 0 then
                lengthOfFrontTool = math.abs(implement.size.length)
            end
        end
    end

    if vehicle.ad ~= nil then
        vehicle.ad.frontToolLength = lengthOfFrontTool
    end

    return lengthOfFrontTool
end

function AutoDrive.getLengthOfFieldInFront(vehicle, onlyWithFruit, maxRange, stepLength)
    local maxSearchRange = maxRange or 50
    stepLength = stepLength or 5
    local length = 10
    local foundField = true
    local foundFruit = false
    local foundCutFruit = false

    local function findCutFruit(corners, fruitTypeIndex)
        -- try to find a cut fruit
        local fillType = DensityMapHeightUtil.getFillTypeAtArea(corners[1].x, corners[1].z, corners[2].x, corners[2].z, corners[3].x, corners[3].z)
        if fillType ~= nil and AutoDrive.windrowCutFillTypes[fruitTypeIndex] == fillType then
            local fillLevel, _, _ = DensityMapHeightUtil.getFillLevelAtArea(fillType, corners[1].x, corners[1].z, corners[2].x, corners[2].z, corners[3].x, corners[3].z)
            if (fillLevel and fillLevel > 0.1) then
                local value = DensityMapHeightUtil.getValueAtArea(corners[1].x, corners[1].z, corners[2].x, corners[2].z, corners[3].x, corners[3].z, true)
                if (value and value > 0.1) then
                    -- cut fruit found
                    return true
                end
            end
        end
        return false
    end


    while foundField do
        local worldPosX, _, worldPosZ = AutoDrive.localToWorld(vehicle, 0, 0, length + stepLength)
        foundField = AutoDrive.checkIsOnField(worldPosX, 0, worldPosZ)

        if onlyWithFruit and foundField then
            local fruitTypeIndex, growthState = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(worldPosX, worldPosZ)
            if fruitTypeIndex and fruitTypeIndex ~= FruitType.MEADOW and growthState then
                -- field has fruit
                local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
                if fruit then
                    -- check for ground fruit
                    foundField = true
                    foundFruit = not fruit:getIsCut(growthState)
                    foundField = foundField and foundFruit
                    if fruit:getIsCut(growthState) and AutoDrive.windrowCutFillTypes[fruitTypeIndex] then
                        -- fruit could be cut, try to find the cutted fruit
                        foundField = true
                        local corners = AutoDrive.getCornersForAreaRelativeToVehicle(vehicle, 0, length, 3, stepLength)
                        foundCutFruit = findCutFruit(corners, fruitTypeIndex)
                        foundField = foundField and foundCutFruit
                    end
                end
            end
        end

        length = length + stepLength
        if math.abs(length) >= maxSearchRange then
            foundField = false
        end
    end
    return length
end

-- 3
-- |
-- |
-- 1 ---- 2
--
--
--    v
function AutoDrive.getCornersForAreaRelativeToVehicle(vehicle, xOffset, zOffset, width, length)
    local corners = {}
    local worldPosX, _, worldPosZ = AutoDrive.localToWorld(vehicle, xOffset - width/2, 0, zOffset)
    corners[1] = { x = worldPosX, z = worldPosZ}
    worldPosX, _, worldPosZ = AutoDrive.localToWorld(vehicle, xOffset + width/2, 0, zOffset)
    corners[2] = { x = worldPosX, z = worldPosZ}
    worldPosX, _, worldPosZ = AutoDrive.localToWorld(vehicle, xOffset - width/2, 0, zOffset + length)
    corners[3] = { x = worldPosX, z = worldPosZ}

    return corners
end
