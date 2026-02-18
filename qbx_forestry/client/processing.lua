-----------------------------------------------------------
-- CLIENT: PROCESSING
-- Field processing after felling: limbing + bucking.
-- Ground log prop spawning and pickup targets.
-----------------------------------------------------------

-----------------------------------------------------------
-- REGISTER PROCESSING TARGET
-- Creates temporary ox_target at felled tree for
-- limbing and bucking operations.
-----------------------------------------------------------
---@param coords vector3 felled tree location
---@param speciesKey string
---@param quality string
---@param yield number expected log count
---@param treeSize string
function RegisterProcessingTarget(coords, speciesKey, quality, yield, treeSize)
    local targetId = exports.ox_target:addSphereZone({
        coords = coords,
        radius = 3.0,
        debug = false,
        options = {
            {
                name = 'forestry_limb_' .. math.random(100000, 999999),
                icon = 'fa-solid fa-scissors',
                label = 'Limb Tree',
                distance = 2.5,
                canInteract = function()
                    return PlayerState.onDuty and not IsWinded()
                end,
                onSelect = function()
                    PerformLimbing(coords, speciesKey)
                end,
            },
            {
                name = 'forestry_buck_' .. math.random(100000, 999999),
                icon = 'fa-solid fa-ruler',
                label = 'Buck into Logs',
                distance = 2.5,
                canInteract = function()
                    return PlayerState.onDuty and not IsWinded()
                end,
                onSelect = function()
                    PerformBucking(coords, speciesKey, quality, yield)
                end,
            },
        },
    })
end

-----------------------------------------------------------
-- PERFORM LIMBING
-- Remove branches from felled tree.
-----------------------------------------------------------
---@param coords vector3
---@param speciesKey string
function PerformLimbing(coords, speciesKey)
    -- Server validation
    local valid, err = lib.callback.await('forestry:processing:validate', false, 'limb', nil)
    if not valid then
        lib.notify({ description = err or 'Cannot limb this tree.', type = 'error' })
        return
    end

    -- Consume stamina
    if not ConsumeSwing() then
        lib.notify({ description = 'Too tired to limb.', type = 'error' })
        return
    end

    -- Face the tree
    TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, 1000)
    Wait(1000)

    -- Chopping animation
    lib.requestAnimDict('melee@hatchet@streamed_core')
    TaskPlayAnim(cache.ped, 'melee@hatchet@streamed_core', 'ground_attack_on_spot', 8.0, -8.0, -1, 1, 0, false, false, false)

    -- Progress bar
    local completed = lib.progressCircle({
        duration = 5000,
        label = 'Limbing tree...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(cache.ped)

    if not completed then return end

    -- Server grants items
    local success, result = lib.callback.await('forestry:processing:completeLimb', false, speciesKey)

    if success then
        lib.notify({
            description = ('Removed branches. Got %d branch bundles.'):format(result and result.branches or 0),
            type = 'success',
        })
    else
        lib.notify({ description = 'Limbing failed.', type = 'error' })
    end
end

-----------------------------------------------------------
-- PERFORM BUCKING
-- Cut felled tree into logs. Player selects length.
-----------------------------------------------------------
---@param coords vector3
---@param speciesKey string
---@param quality string
---@param yield number
function PerformBucking(coords, speciesKey, quality, yield)
    -- Input dialog for cut length
    local input = lib.inputDialog('Buck Logs', {
        {
            type = 'select',
            label = 'Cut Length',
            required = true,
            options = {
                { value = 'short',    label = 'Short (4ft) - Hand carryable' },
                { value = 'standard', label = 'Standard (8ft) - Vehicle required' },
                { value = 'long',     label = 'Long (16ft) - Truck/skidder required' },
            },
        },
    })

    if not input then return end
    local logType = input[1]

    -- Server validation
    local valid, err = lib.callback.await('forestry:processing:validate', false, 'buck', nil)
    if not valid then
        lib.notify({ description = err or 'Cannot buck.', type = 'error' })
        return
    end

    -- Consume stamina per cut
    local consumed = 0
    for i = 1, yield do
        if ConsumeSwing() then
            consumed = consumed + 1
        else
            break
        end
    end

    if consumed == 0 then
        lib.notify({ description = 'Too tired to buck.', type = 'error' })
        return
    end

    -- Face the tree
    TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, 1000)
    Wait(1000)

    -- Bucking animation
    lib.requestAnimDict('anim@heists@fleeca_bank@drilling')
    TaskPlayAnim(cache.ped, 'anim@heists@fleeca_bank@drilling', 'drill_straight_idle', 8.0, -8.0, -1, 1, 0, false, false, false)

    local completed = lib.progressCircle({
        duration = 3000 * consumed,
        label = ('Bucking into %s logs...'):format(logType),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(cache.ped)

    if not completed then return end

    -- Server grants logs
    local success, result = lib.callback.await('forestry:processing:completeBuck', false,
        speciesKey, quality, logType, consumed
    )

    if success then
        lib.notify({
            description = ('Cut %d %s logs.'):format(result and result.granted or consumed, logType),
            type = 'success',
        })

        -- Spawn log props on ground
        SpawnLogProps(coords, logType, speciesKey, result and result.granted or consumed)
    else
        lib.notify({ description = 'Bucking failed.', type = 'error' })
    end
end

-----------------------------------------------------------
-- SPAWN LOG PROPS
-- Create ground prop objects at felled tree location.
-----------------------------------------------------------
---@param baseCoords vector3
---@param logType string
---@param species string
---@param count number
function SpawnLogProps(baseCoords, logType, species, count)
    local propConfig = Config.LogProps[logType]
    if not propConfig then return end

    for i = 1, count do
        lib.requestModel(propConfig.model)
        local offset = vec3(
            math.random(-20, 20) / 10.0,
            math.random(-20, 20) / 10.0,
            0.0
        )
        local spawnPos = baseCoords + offset

        local prop = CreateObject(propConfig.model, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
        if prop and prop ~= 0 then
            PlaceObjectOnGroundProperly(prop)
            FreezeEntityPosition(prop, true)
            RegisterLogPropTarget(math.random(100000, 999999), prop, logType, species)
        end
        SetModelAsNoLongerNeeded(propConfig.model)
    end
end

-----------------------------------------------------------
-- REGISTER LOG PROP TARGET
-- ox_target on ground log for pickup.
-----------------------------------------------------------
---@param id number unique identifier
---@param prop number entity handle
---@param logType string
---@param species string
function RegisterLogPropTarget(id, prop, logType, species)
    local logConfig = Config.LogTypes[logType]
    local label = logConfig and logConfig.label or logType

    exports.ox_target:addLocalEntity(prop, {
        {
            name = 'pickup_log_' .. id,
            icon = 'fa-solid fa-hand',
            label = 'Pick Up ' .. label,
            distance = 2.5,
            canInteract = function()
                if not PlayerState.onDuty then return false end
                if CarryState then return false end
                if not logConfig or not logConfig.carryable then return false end
                return true
            end,
            onSelect = function()
                exports.ox_target:removeLocalEntity(prop)
                DeleteEntity(prop)
                if StartCarry then
                    StartCarry(logType, species, LogQuality.NORMAL)
                end
            end,
        },
    })
end

-----------------------------------------------------------
-- DROP OVERFLOW
-- Server sends this when inventory is full. Spawns ground
-- props near the player that can be picked up later.
-----------------------------------------------------------
RegisterNetEvent('forestry:client:dropOverflow', function(itemName, count, metadata)
    local ped = cache.ped
    local coords = GetEntityCoords(ped)

    -- Determine which prop model to use based on item name
    local propModel
    local logType

    -- Check if this is a log item
    for lt, logConfig in pairs(Config.LogTypes) do
        if logConfig.item == itemName then
            logType = lt
            local propConfig = Config.LogProps[lt]
            if propConfig then
                propModel = propConfig.model
            end
            break
        end
    end

    -- Fallback to generic crate prop for non-log items
    propModel = propModel or `prop_box_wood05a`

    for i = 1, count do
        lib.requestModel(propModel)
        local offset = vec3(
            math.random(-20, 20) / 10.0,
            math.random(-20, 20) / 10.0,
            0.0
        )
        local spawnPos = coords + offset

        local prop = CreateObject(propModel, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
        if prop and prop ~= 0 then
            PlaceObjectOnGroundProperly(prop)
            FreezeEntityPosition(prop, true)

            if logType then
                local species = metadata and metadata.species or 'unknown'
                RegisterLogPropTarget(math.random(100000, 999999), prop, logType, species)
            else
                -- Generic item pickup target
                local id = math.random(100000, 999999)
                exports.ox_target:addLocalEntity(prop, {
                    {
                        name = 'pickup_overflow_' .. id,
                        icon = 'fa-solid fa-hand',
                        label = 'Pick Up ' .. itemName:gsub('_', ' '),
                        distance = 2.5,
                        onSelect = function()
                            exports.ox_target:removeLocalEntity(prop)
                            DeleteEntity(prop)
                            TriggerServerEvent('forestry:server:claimOverflow', itemName, 1, metadata)
                        end,
                    },
                })
            end
        end
        SetModelAsNoLongerNeeded(propModel)
    end
end)
