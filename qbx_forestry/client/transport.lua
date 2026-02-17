-----------------------------------------------------------
-- CLIENT: TRANSPORT
-- Log carry mode, vehicle loading, log chutes.
-- Physical props attached to player/vehicles.
-----------------------------------------------------------

--- Active carry state.
---@class CarryData
---@field logType string
---@field species string
---@field quality string
---@field prop number entity handle
---@field speedMod number

--- Is player loading a vehicle?
local isLoading = false

-----------------------------------------------------------
-- START CARRY MODE
-- Attaches log prop to player, applies speed modifier.
-----------------------------------------------------------
---@param logType string 'short' or 'standard'
---@param species string
---@param quality string
function StartCarry(logType, species, quality)
    if CarryState then
        lib.notify({ description = 'Already carrying something.', type = 'error' })
        return
    end

    local propConfig = Config.LogProps[logType]
    if not propConfig or not propConfig.carryOffset then
        lib.notify({ description = 'This log requires vehicle transport.', type = 'error' })
        return
    end

    local logConfig = Config.LogTypes[logType]
    if not logConfig or not logConfig.carryable then
        lib.notify({ description = 'This log is too heavy to carry by hand.', type = 'error' })
        return
    end

    -- Check stamina
    local swingCost = logType == 'standard' and 2 or 1
    for i = 1, swingCost do
        if ConsumeSwing then
            if not ConsumeSwing() then
                lib.notify({ description = 'Too tired to pick this up.', type = 'error' })
                return
            end
        end
    end

    -- Pickup progress
    local completed = lib.progressCircle({
        duration = 2000,
        label = 'Picking up log...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    if not completed then return end

    -- Blur pulse on heavy pickup
    AnimpostfxPlay('FocusOut', 0, false)
    Wait(200)
    AnimpostfxStop('FocusOut')

    -- Create and attach prop
    local modelHash = propConfig.model
    lib.requestModel(modelHash)

    local ped = cache.ped
    local prop = CreateObject(modelHash, 0.0, 0.0, 0.0, false, false, false)

    if not prop or prop == 0 then
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    local offset = propConfig.carryOffset
    AttachEntityToEntity(
        prop, ped,
        GetPedBoneIndex(ped, offset.bone),
        offset.x, offset.y, offset.z,
        offset.rx, offset.ry, offset.rz,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(modelHash)

    -- Apply speed modifier
    local speedMod = Config.CarrySpeedModifiers[logType .. '_log'] or 0.85
    SetPedMoveRateOverride(ped, speedMod)

    -- Play carry animation
    local animDict = logType == 'short'
        and 'anim@heists@box_carry@'
        or 'missfinale_c2mcs_1'
    local animName = logType == 'short'
        and 'idle'
        or 'fin_c2_mcs_1_camman'

    lib.requestAnimDict(animDict)
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0, false, false, false)

    CarryState = {
        logType = logType,
        species = species,
        quality = quality,
        prop = prop,
        speedMod = speedMod,
    }

    -- Block sprint while carrying standard logs
    if logType == 'standard' then
        CreateThread(function()
            while CarryState and CarryState.logType == 'standard' do
                DisableControlAction(0, 21, true) -- Sprint
                Wait(0)
            end
        end)
    end

    lib.notify({ description = 'Carrying log. Find a vehicle or drop point.', type = 'inform' })
end

-----------------------------------------------------------
-- DROP / CANCEL CARRY
-----------------------------------------------------------
function CancelCarry(intentional)
    if not CarryState then return end

    local ped = cache.ped

    -- Detach and delete prop
    if CarryState.prop and DoesEntityExist(CarryState.prop) then
        DetachEntity(CarryState.prop, true, true)

        if intentional then
            -- Place prop on ground
            local coords = GetEntityCoords(ped)
            local forward = GetEntityForwardVector(ped)
            local dropPos = coords + forward * 1.0
            local found, groundZ = GetGroundZFor_3dCoord(dropPos.x, dropPos.y, dropPos.z + 2.0, false)
            if found then
                SetEntityCoords(CarryState.prop, dropPos.x, dropPos.y, groundZ, false, false, false, false)
            else
                SetEntityCoords(CarryState.prop, dropPos.x, dropPos.y, dropPos.z, false, false, false, false)
            end
            PlaceObjectOnGroundProperly(CarryState.prop)
            FreezeEntityPosition(CarryState.prop, true)

            -- Register pickup target on dropped prop
            if RegisterLogPropTarget then
                local propId = math.random(100000, 999999)
                RegisterLogPropTarget(propId, CarryState.prop, CarryState.logType, CarryState.species)
            end
        else
            DeleteEntity(CarryState.prop)
        end
    end

    -- Restore movement
    SetPedMoveRateOverride(ped, 1.0)
    ClearPedTasks(ped)

    -- Drop damage if moving and not intentional
    if not intentional then
        local speed = GetEntitySpeed(ped)
        if speed > 1.0 then
            local maxHealth = GetEntityMaxHealth(ped)
            local healthLoss = math.floor(maxHealth * Config.Injury.DroppedLog / 100)
            SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - healthLoss))
            lib.notify({ description = 'You dropped the log on yourself!', type = 'error' })
        end
    end

    CarryState = nil
end

-- Drop command
RegisterCommand('droplog', function()
    if CarryState then
        CancelCarry(true)
        lib.notify({ description = 'Log dropped.', type = 'inform' })
    end
end, false)

-----------------------------------------------------------
-- VEHICLE LOADING
-- Load carried or ground logs onto nearby vehicle.
-----------------------------------------------------------

--- Tracked vehicle loads: vehicleNetId -> { logs = { {logType, species, quality} } }
---@type table<number, table>
local vehicleLoads = {}

---@param vehicle number entity handle
function LoadLogOntoVehicle(vehicle, logType, species, quality)
    if isLoading then return end
    isLoading = true

    -- Get load duration from server (accounts for crew relay bonus)
    local duration = lib.callback.await('forestry:transport:getLoadDuration', false)

    -- Consume stamina
    if ConsumeSwing then
        if not ConsumeSwing() then
            lib.notify({ description = 'Too tired to load.', type = 'error' })
            isLoading = false
            return
        end
    end

    -- Loading progress
    local completed = lib.progressCircle({
        duration = duration,
        label = 'Loading log...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'anim@heists@box_carry@',
            clip = 'idle',
        },
    })

    if not completed then
        isLoading = false
        return
    end

    -- Track vehicle load
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not vehicleLoads[netId] then
        vehicleLoads[netId] = { logs = {} }
    end

    local loadData = vehicleLoads[netId]
    loadData.logs[#loadData.logs + 1] = {
        logType = logType,
        species = species,
        quality = quality,
    }

    -- Attach visual prop to vehicle
    AttachLogPropToVehicle(vehicle, loadData, logType)

    -- If carrying, remove carry state
    if CarryState then
        if CarryState.prop and DoesEntityExist(CarryState.prop) then
            DeleteEntity(CarryState.prop)
        end
        SetPedMoveRateOverride(cache.ped, 1.0)
        ClearPedTasks(cache.ped)
        CarryState = nil
    end

    -- Clang sound
    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)

    lib.notify({
        description = ('Log loaded. Vehicle has %d logs.'):format(#loadData.logs),
        type = 'success',
    })

    isLoading = false
end

-----------------------------------------------------------
-- ATTACH LOG PROP TO VEHICLE
-----------------------------------------------------------
function AttachLogPropToVehicle(vehicle, loadData, logType)
    local propConfig = Config.LogProps[logType]
    if not propConfig then return end

    local modelHash = propConfig.model
    lib.requestModel(modelHash)

    local logIndex = #loadData.logs
    -- Simple stacking: offset upward per log
    local baseOffset = vec3(0.0, -1.0, 0.8)
    local stackOffset = vec3(0.0, 0.0, 0.3 * (logIndex - 1))
    local offset = baseOffset + stackOffset

    local prop = CreateObject(modelHash, 0.0, 0.0, 0.0, false, false, false)
    if prop and prop ~= 0 then
        AttachEntityToEntity(
            prop, vehicle, 0,
            offset.x, offset.y, offset.z,
            0.0, 0.0, 90.0,
            true, true, false, false, 2, true
        )
        loadData.logs[logIndex].prop = prop
    end

    SetModelAsNoLongerNeeded(modelHash)
end

-----------------------------------------------------------
-- UNLOAD VEHICLE
-- Remove all logs from vehicle, add to player inventory.
-----------------------------------------------------------
function UnloadVehicle(vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local loadData = vehicleLoads[netId]
    if not loadData or #loadData.logs == 0 then
        lib.notify({ description = 'No logs on this vehicle.', type = 'inform' })
        return
    end

    local unloaded = 0
    for _, logEntry in ipairs(loadData.logs) do
        -- Server grants the item
        local success = lib.callback.await('forestry:processing:completeBuck', false,
            logEntry.species, logEntry.quality, logEntry.logType, 1
        )

        if success then
            unloaded = unloaded + 1
        end

        -- Remove prop
        if logEntry.prop and DoesEntityExist(logEntry.prop) then
            DeleteEntity(logEntry.prop)
        end
    end

    vehicleLoads[netId] = nil

    lib.notify({
        description = ('Unloaded %d logs from vehicle.'):format(unloaded),
        type = 'success',
    })
end

-----------------------------------------------------------
-- VEHICLE INTERACTION TARGETS
-- Register ox_target options on vehicles for loading/unloading.
-----------------------------------------------------------
CreateThread(function()
    -- Wait for main init
    while not PlayerState.loaded do Wait(1000) end

    -- Add vehicle bone target for load/unload
    exports.ox_target:addGlobalVehicle({
        {
            name = 'forestry_load_vehicle',
            icon = 'fa-solid fa-truck-loading',
            label = 'Load Log',
            bones = { 'boot', 'chassis', 'chassis_dummy' },
            distance = 3.0,
            canInteract = function(entity)
                if not PlayerState.onDuty then return false end
                if isLoading then return false end
                -- Must be carrying a log OR have logs in inventory
                if CarryState then return true end
                local shortCount = exports.ox_inventory:Search('count', 'log_short')
                local stdCount = exports.ox_inventory:Search('count', 'log_standard')
                return (shortCount and shortCount > 0) or (stdCount and stdCount > 0)
            end,
            onSelect = function(data)
                if not data.entity then return end
                if CarryState then
                    LoadLogOntoVehicle(data.entity, CarryState.logType, CarryState.species, CarryState.quality)
                else
                    -- Select from inventory
                    SelectLogToLoad(data.entity)
                end
            end,
        },
        {
            name = 'forestry_unload_vehicle',
            icon = 'fa-solid fa-truck-ramp-box',
            label = 'Unload Logs',
            bones = { 'boot', 'chassis', 'chassis_dummy' },
            distance = 3.0,
            canInteract = function(entity)
                if not PlayerState.onDuty then return false end
                local netId = NetworkGetNetworkIdFromEntity(entity)
                local loadData = vehicleLoads[netId]
                return loadData and #loadData.logs > 0
            end,
            onSelect = function(data)
                if not data.entity then return end
                UnloadVehicle(data.entity)
            end,
        },
    })
end)

-----------------------------------------------------------
-- SELECT LOG TO LOAD (from inventory)
-----------------------------------------------------------
function SelectLogToLoad(vehicle)
    local options = {}

    local shortLogs = exports.ox_inventory:Search('slots', 'log_short')
    if shortLogs and #shortLogs > 0 then
        local meta = shortLogs[1].metadata or {}
        options[#options + 1] = {
            value = 'short',
            label = ('Short Log (%s, %s)'):format(meta.species or '?', meta.quality or 'normal'),
            species = meta.species or 'pine',
            quality = meta.quality or 'normal',
        }
    end

    local stdLogs = exports.ox_inventory:Search('slots', 'log_standard')
    if stdLogs and #stdLogs > 0 then
        local meta = stdLogs[1].metadata or {}
        options[#options + 1] = {
            value = 'standard',
            label = ('Standard Log (%s, %s)'):format(meta.species or '?', meta.quality or 'normal'),
            species = meta.species or 'pine',
            quality = meta.quality or 'normal',
        }
    end

    if #options == 0 then
        lib.notify({ description = 'No logs in inventory.', type = 'error' })
        return
    end

    local input = lib.inputDialog('Select Log to Load', {
        {
            type = 'select',
            label = 'Log',
            options = options,
            required = true,
        },
    })

    if not input then return end

    local selected = input[1]
    local logData
    for _, opt in ipairs(options) do
        if opt.value == selected then
            logData = opt
            break
        end
    end

    if not logData then return end

    -- Remove from inventory first
    local itemName = Config.LogTypes[selected].item
    local removed = exports.ox_inventory:Search('count', itemName)
    if not removed or removed < 1 then return end

    -- The server will handle removal via callback; for now load directly
    LoadLogOntoVehicle(vehicle, selected, logData.species, logData.quality)
end

-----------------------------------------------------------
-- LOG CHUTES
-----------------------------------------------------------

--- Active log chutes
---@type table<string, { ownerId: number, crewId: string?, logs: table[] }>
local logChuteState = {}

--- Deploy a log chute from kit
function DeployLogChute()
    -- Find nearest configured chute point
    local playerCoords = GetEntityCoords(cache.ped)
    local nearestChute = nil
    local nearestDist = math.huge

    for _, chute in ipairs(Config.LogChutes) do
        local dist = #(playerCoords - chute.sendPoint)
        if dist < nearestDist then
            nearestDist = dist
            nearestChute = chute
        end
    end

    if not nearestChute or nearestDist > 15.0 then
        lib.notify({ description = 'No chute send point nearby. Move to a ridge.', type = 'error' })
        return
    end

    lib.notify({
        description = ('Log chute deployed at %s! Send up to %d logs per batch.'):format(
            nearestChute.label, nearestChute.maxLogsPerSend
        ),
        type = 'success',
    })
end

-----------------------------------------------------------
-- CLEANUP ON RESOURCE STOP
-----------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Clean up carry state
    if CarryState then
        if CarryState.prop and DoesEntityExist(CarryState.prop) then
            DeleteEntity(CarryState.prop)
        end
        SetPedMoveRateOverride(cache.ped, 1.0)
        CarryState = nil
    end

    -- Clean up vehicle props
    for netId, loadData in pairs(vehicleLoads) do
        for _, logEntry in ipairs(loadData.logs) do
            if logEntry.prop and DoesEntityExist(logEntry.prop) then
                DeleteEntity(logEntry.prop)
            end
        end
    end
    vehicleLoads = {}
end)
