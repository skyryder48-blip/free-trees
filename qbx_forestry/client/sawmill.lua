-----------------------------------------------------------
-- CLIENT: SAWMILL PROCESSING
-- Tier 1 portable sawmill + Tier 2 community sawmill.
-- 8 station types, multiplayer throughput bonus,
-- level-gated personal bonuses.
-----------------------------------------------------------

local isProcessingSawmill = false

--- Track active station users at each sawmill (for throughput bonus).
---@type table<string, table<string, number>> sawmillId -> { stationId -> source }
local activeSawmillStations = {}

--- Active sawmill audio handles.
---@type table<string, number>
local activeSawmillSounds = {}

-----------------------------------------------------------
-- STATION DEFINITIONS
-- Input requirements, outputs, durations, skill checks.
-----------------------------------------------------------
local StationDefs = {
    debarker = {
        label = 'Debarker',
        inputItem = { 'log_short', 'log_standard' },
        outputItems = function(species)
            return { { item = 'log_short', count = 1, metadata = { species = species, debarked = true } } }
        end,
        byproduct = { item = 'bark_raw', count = 1 },
        baseDuration = 6000,
        skillCheck = nil, -- Progress bar only
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        xp = 8,
    },
    headsaw = {
        label = 'Head Saw',
        inputItem = { 'log_short', 'log_standard' },
        requireDebarked = true,
        outputItems = function(species)
            return { { item = 'lumber_rough', count = 2, metadata = { species = species } } }
        end,
        byproduct = { item = 'sawdust', count = 2 },
        baseDuration = 10000,
        skillCheck = Config.SkillCheck.headsaw,
        anim = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle' },
        xp = 15,
        xpBonus = 5, -- On skill check success
    },
    edger = {
        label = 'Edger',
        inputItem = { 'lumber_rough' },
        outputItems = function(species)
            return { { item = 'lumber_edged', count = 1, metadata = { species = species } } }
        end,
        baseDuration = 5000,
        skillCheck = Config.SkillCheck.edger,
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        xp = 8,
    },
    planer = {
        label = 'Planer',
        inputItem = { 'lumber_edged' },
        outputItems = function(species)
            return { { item = 'lumber_finished', count = 1, metadata = { species = species } } }
        end,
        baseDuration = 6000,
        skillCheck = Config.SkillCheck.planer,
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        xp = 12,
        xpBonus = 5,
    },
    crosscut_station = {
        label = 'Crosscut Station',
        inputItem = { 'log_short', 'log_standard' },
        outputItems = function(species)
            return { { item = 'lumber_rough', count = 1, metadata = { species = species } } }
        end,
        byproduct = { item = 'wood_chips', count = 2 },
        baseDuration = 5000,
        skillCheck = Config.SkillCheck.crosscut_station,
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        xp = 8,
    },
    veneer = {
        label = 'Veneer Slicer',
        inputItem = { 'log_short', 'log_standard' },
        requireDebarked = true,
        validSpecies = { oak = true, cedar = true, redwood = true, maple = true },
        outputItems = function(species)
            return { { item = 'veneer_sheet', count = 2, metadata = { species = species } } }
        end,
        baseDuration = 12000,
        skillCheck = Config.SkillCheck.veneer,
        anim = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle' },
        xp = 25,
        xpBonus = 10,
    },
    plywood = {
        label = 'Plywood Press',
        inputItem = { 'veneer_sheet' },
        inputCount = 3,
        outputItems = function(species)
            return { { item = 'plywood_sheet', count = 1, metadata = { species = species } } }
        end,
        baseDuration = 15000,
        skillCheck = Config.SkillCheck.plywood,
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
        xp = 20,
    },
    specialty = {
        label = 'Specialty Saw',
        inputItem = { 'lumber_finished' },
        validSpecies = { oak = true, redwood = true, maple = true, cedar = true },
        outputItems = function(species)
            return { { item = 'specialty_cut', count = 1, metadata = { species = species } } }
        end,
        baseDuration = 10000,
        skillCheck = Config.SkillCheck.specialty,
        anim = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle' },
        xp = 30,
        xpBonus = 15,
    },
}

-----------------------------------------------------------
-- PERSONAL BONUSES (Forestry level-gated)
-----------------------------------------------------------
local PersonalBonuses = {
    [8]  = { station = 'debarker', durationMod = 0.80 },              -- -20% duration
    [12] = { station = 'headsaw', skillCheckReduce = true },           -- -1 difficulty tier
    [16] = { station = 'headsaw', bonusLumberChance = 0.15 },         -- 15% bonus lumber
    [22] = { station = 'planer', durationMod = 0.75 },                -- -25% duration
    [26] = { station = 'veneer', skillCheckReduce = true, bonusYield = 1 }, -- -1 tier, +1 veneer
    [32] = { allStations = true, durationMod = 0.85 },                -- -15% all stations
    [38] = { station = 'headsaw', doubleSawdust = true },             -- Sawdust doubled
    [45] = { allStations = true, doubleOutputChance = 0.10 },         -- 10% double output
}

--- Calculate effective duration for a station.
---@param stationId string
---@param baseDuration number
---@param forestryLevel number
---@param sawmillId string
---@return number
local function getEffectiveDuration(stationId, baseDuration, forestryLevel, sawmillId)
    local duration = baseDuration

    -- Personal level bonuses
    for level, bonus in pairs(PersonalBonuses) do
        if forestryLevel >= level then
            if bonus.station == stationId and bonus.durationMod then
                duration = duration * bonus.durationMod
            end
            if bonus.allStations and bonus.durationMod then
                duration = duration * bonus.durationMod
            end
        end
    end

    -- Multiplayer throughput bonus
    if sawmillId and activeSawmillStations[sawmillId] then
        local activeCount = 0
        for _ in pairs(activeSawmillStations[sawmillId]) do
            activeCount = activeCount + 1
        end
        if activeCount > 1 then
            local sawmillConfig = nil
            for _, sm in ipairs(Config.Sawmills) do
                if sm.id == sawmillId then sawmillConfig = sm; break end
            end
            if sawmillConfig then
                local reduction = math.min(
                    (activeCount - 1) * sawmillConfig.throughputBonus,
                    sawmillConfig.throughputBonusCap
                )
                duration = duration * (1.0 - reduction)
            end
        end
    end

    return math.floor(duration)
end

--- Check if skill check should be reduced by 1 tier.
local function shouldReduceSkillCheck(stationId, forestryLevel)
    for level, bonus in pairs(PersonalBonuses) do
        if forestryLevel >= level and bonus.station == stationId and bonus.skillCheckReduce then
            return true
        end
    end
    return false
end

--- Reduce skill check difficulty by 1 tier.
local function reduceSkillCheck(checks)
    local reduced = {}
    local tierMap = { hard = 'medium', medium = 'easy', easy = 'easy' }
    for i, check in ipairs(checks) do
        reduced[i] = tierMap[check] or check
    end
    return reduced
end

-----------------------------------------------------------
-- REGISTER SAWMILL TARGETS
-- Called from main.lua init. Level-gated ox_target options.
-----------------------------------------------------------
function RegisterSawmillTargets()
    for _, sawmill in ipairs(Config.Sawmills) do
        activeSawmillStations[sawmill.id] = {}

        for _, station in ipairs(sawmill.stations) do
            local stationId = station.id
            local levelReq = station.levelReq
            local stationDef = StationDefs[stationId]
            if not stationDef then goto nextStation end

            exports.ox_target:addSphereZone({
                coords = station.coords,
                radius = 1.5,
                debug = false,
                drawSprite = true,
                options = {
                    {
                        name = ('sawmill_%s_%s'):format(sawmill.id, stationId),
                        icon = 'fa-solid fa-gear',
                        label = stationDef.label,
                        distance = 2.5,
                        canInteract = function()
                            if not PlayerState.onDuty then return false end
                            if isProcessingSawmill then return false end
                            if PlayerState.forestryLevel < levelReq then return false end
                            return true
                        end,
                        onSelect = function()
                            UseSawmillStation(sawmill.id, stationId, station.coords)
                        end,
                    },
                },
            })

            ::nextStation::
        end

        -- Furniture workshop target
        if sawmill.furnitureWorkshop then
            exports.ox_target:addSphereZone({
                coords = sawmill.furnitureWorkshop,
                radius = 2.0,
                debug = false,
                drawSprite = true,
                options = {
                    {
                        name = ('workshop_%s'):format(sawmill.id),
                        icon = 'fa-solid fa-hammer',
                        label = 'Furniture Workshop',
                        distance = 2.5,
                        canInteract = function()
                            if not PlayerState.loaded then return false end
                            return true
                        end,
                        onSelect = function()
                            if OpenCraftingMenu then
                                OpenCraftingMenu()
                            end
                        end,
                    },
                },
            })
        end
    end
end

-----------------------------------------------------------
-- USE SAWMILL STATION
-----------------------------------------------------------
---@param sawmillId string
---@param stationId string
---@param stationCoords vector3
function UseSawmillStation(sawmillId, stationId, stationCoords)
    if isProcessingSawmill then return end

    -- Server validation
    local valid, err, data = lib.callback.await('forestry:sawmill:validate', false, stationId)
    if not valid then
        local messages = {
            not_loaded = 'Player data not loaded.',
            no_cache = 'Data error.',
            level_too_low = 'You need a higher Forestry level for this station.',
            not_on_duty = 'You must be on duty.',
        }
        lib.notify({ description = messages[err] or 'Cannot use station.', type = 'error' })
        return
    end

    local stationDef = StationDefs[stationId]
    if not stationDef then return end

    isProcessingSawmill = true

    -- Mark station active for throughput tracking
    activeSawmillStations[sawmillId] = activeSawmillStations[sawmillId] or {}
    activeSawmillStations[sawmillId][stationId] = cache.serverId

    -- Check for input material
    local hasInput = false
    local inputSlot = nil
    local inputMeta = nil
    local inputItem = nil
    local inputCount = stationDef.inputCount or 1

    for _, item in ipairs(stationDef.inputItem) do
        local count = exports.ox_inventory:Search('count', item)
        if count and count >= inputCount then
            hasInput = true
            inputItem = item

            local slots = exports.ox_inventory:Search('slots', item)
            if slots and #slots > 0 then
                inputSlot = slots[1]
                inputMeta = slots[1].metadata or {}
            end
            break
        end
    end

    if not hasInput then
        lib.notify({
            description = ('Need %s for the %s.'):format(
                table.concat(stationDef.inputItem, ' or '),
                stationDef.label
            ),
            type = 'error',
        })
        isProcessingSawmill = false
        activeSawmillStations[sawmillId][stationId] = nil
        return
    end

    -- Check debarked requirement
    if stationDef.requireDebarked and not (inputMeta and inputMeta.debarked) then
        lib.notify({ description = 'This log needs to be debarked first.', type = 'error' })
        isProcessingSawmill = false
        activeSawmillStations[sawmillId][stationId] = nil
        return
    end

    -- Check species requirement
    local species = inputMeta and inputMeta.species or 'pine'
    if stationDef.validSpecies and not stationDef.validSpecies[species] then
        lib.notify({
            description = ('The %s only accepts certain wood species.'):format(stationDef.label),
            type = 'error',
        })
        isProcessingSawmill = false
        activeSawmillStations[sawmillId][stationId] = nil
        return
    end

    -- Face the station
    TaskTurnPedToFaceCoord(cache.ped, stationCoords.x, stationCoords.y, stationCoords.z, 1000)
    Wait(1000)

    -- Calculate effective duration
    local forestryLevel = data.forestryLevel or PlayerState.forestryLevel
    local effectiveDuration = getEffectiveDuration(stationId, stationDef.baseDuration, forestryLevel, sawmillId)

    -- Start animation
    if stationDef.anim then
        lib.requestAnimDict(stationDef.anim.dict)
        TaskPlayAnim(cache.ped, stationDef.anim.dict, stationDef.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    -- Start station audio
    StartStationAudio(stationId, stationCoords)

    -- Skill check or progress bar
    local skillPassed = true
    if stationDef.skillCheck and #stationDef.skillCheck > 0 then
        -- Run halfway progress, then skill check, then finish
        local halfDuration = math.floor(effectiveDuration * 0.5)

        local prog1 = lib.progressCircle({
            duration = halfDuration,
            label = ('Operating %s...'):format(stationDef.label),
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
        })

        if not prog1 then
            ClearPedTasks(cache.ped)
            StopStationAudio(stationId)
            isProcessingSawmill = false
            activeSawmillStations[sawmillId][stationId] = nil
            return
        end

        -- Skill check
        local checks = stationDef.skillCheck
        if shouldReduceSkillCheck(stationId, forestryLevel) then
            checks = reduceSkillCheck(checks)
        end

        skillPassed = lib.skillCheck(checks, Config.SkillCheck.inputs)

        -- Finish remaining duration
        local prog2 = lib.progressCircle({
            duration = halfDuration,
            label = 'Finishing...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
        })

        if not prog2 then
            ClearPedTasks(cache.ped)
            StopStationAudio(stationId)
            isProcessingSawmill = false
            activeSawmillStations[sawmillId][stationId] = nil
            return
        end
    else
        -- Simple progress bar
        local completed = lib.progressCircle({
            duration = effectiveDuration,
            label = ('Operating %s...'):format(stationDef.label),
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
        })

        if not completed then
            ClearPedTasks(cache.ped)
            StopStationAudio(stationId)
            isProcessingSawmill = false
            activeSawmillStations[sawmillId][stationId] = nil
            return
        end
    end

    ClearPedTasks(cache.ped)
    StopStationAudio(stationId)

    -- Server processes the station use
    local success, result = lib.callback.await('forestry:sawmill:complete', false,
        stationId, inputItem, species, skillPassed, inputCount
    )

    if success then
        local xpAmount = stationDef.xp
        if skillPassed and stationDef.xpBonus then
            xpAmount = xpAmount + stationDef.xpBonus
        end

        lib.notify({
            description = ('Processed at %s. +%d XP'):format(stationDef.label, xpAmount),
            type = 'success',
        })
    else
        lib.notify({ description = 'Processing failed.', type = 'error' })
    end

    activeSawmillStations[sawmillId][stationId] = nil
    isProcessingSawmill = false
end

-----------------------------------------------------------
-- PORTABLE SAWMILL (Tier 1)
-----------------------------------------------------------
function DeployPortableSawmill()
    if isProcessingSawmill then return end

    local count = exports.ox_inventory:Search('count', 'portable_sawmill')
    if not count or count < 1 then
        lib.notify({ description = 'You need a portable sawmill.', type = 'error' })
        return
    end

    local ped = cache.ped
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local deployCoords = coords + forward * 2.0

    -- Deploying animation
    local completed = lib.progressCircle({
        duration = 5000,
        label = 'Setting up portable sawmill...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' },
    })

    if not completed then return end

    -- Spawn prop (using a workbench-like prop)
    local propModel = `prop_toolchest_05`
    lib.requestModel(propModel)

    local found, groundZ = GetGroundZFor_3dCoord(deployCoords.x, deployCoords.y, deployCoords.z + 2.0, false)
    if found then deployCoords = vec3(deployCoords.x, deployCoords.y, groundZ) end

    local prop = CreateObject(propModel, deployCoords.x, deployCoords.y, deployCoords.z, false, false, false)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetModelAsNoLongerNeeded(propModel)

    -- Register interaction target
    exports.ox_target:addLocalEntity(prop, {
        {
            name = 'portable_sawmill_use',
            icon = 'fa-solid fa-saw',
            label = 'Use Portable Sawmill',
            distance = 2.5,
            canInteract = function()
                if not PlayerState.onDuty then return false end
                if isProcessingSawmill then return false end
                return true
            end,
            onSelect = function()
                UsePortableSawmill(prop, deployCoords)
            end,
        },
        {
            name = 'portable_sawmill_pickup',
            icon = 'fa-solid fa-hand',
            label = 'Pick Up Sawmill',
            distance = 2.5,
            onSelect = function()
                PickupPortableSawmill(prop)
            end,
        },
    })

    -- Remove from inventory (server validates)
    TriggerServerEvent('forestry:server:deploySawmill', deployCoords)

    lib.notify({ description = 'Portable sawmill deployed!', type = 'success' })
end

-----------------------------------------------------------
-- USE PORTABLE SAWMILL (only rough lumber + sawdust)
-----------------------------------------------------------
function UsePortableSawmill(prop, coords)
    if isProcessingSawmill then return end
    isProcessingSawmill = true

    -- Check for logs
    local hasLog = false
    local inputItem = nil
    for _, item in ipairs({ 'log_short', 'log_standard' }) do
        local count = exports.ox_inventory:Search('count', item)
        if count and count > 0 then
            hasLog = true
            inputItem = item
            break
        end
    end

    if not hasLog then
        lib.notify({ description = 'You need logs to process.', type = 'error' })
        isProcessingSawmill = false
        return
    end

    local slots = exports.ox_inventory:Search('slots', inputItem)
    local species = (slots and #slots > 0 and slots[1].metadata and slots[1].metadata.species) or 'pine'

    TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, 1000)
    Wait(1000)

    lib.requestAnimDict('anim@heists@fleeca_bank@drilling')
    TaskPlayAnim(cache.ped, 'anim@heists@fleeca_bank@drilling', 'drill_straight_idle', 8.0, -8.0, -1, 1, 0, false, false, false)

    local completed = lib.progressCircle({
        duration = 12000,
        label = 'Cutting lumber...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    ClearPedTasks(cache.ped)

    if not completed then
        isProcessingSawmill = false
        return
    end

    -- Server processes
    local success = lib.callback.await('forestry:sawmill:complete', false,
        'portable', inputItem, species, true, 1
    )

    if success then
        lib.notify({ description = 'Lumber cut! Got rough lumber and sawdust.', type = 'success' })
    end

    isProcessingSawmill = false
end

-----------------------------------------------------------
-- PICK UP PORTABLE SAWMILL
-----------------------------------------------------------
function PickupPortableSawmill(prop)
    if not DoesEntityExist(prop) then return end

    local completed = lib.progressCircle({
        duration = 3000,
        label = 'Picking up sawmill...',
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    if not completed then return end

    exports.ox_target:removeLocalEntity(prop)
    DeleteEntity(prop)

    -- Add to player inventory (any player can pick up any sawmill)
    TriggerServerEvent('forestry:server:pickupSawmill')
end

-----------------------------------------------------------
-- STATION AUDIO
-----------------------------------------------------------
function StartStationAudio(stationId, coords)
    local soundId = GetSoundId()
    if stationId == 'headsaw' or stationId == 'specialty' then
        PlaySoundFromCoord(soundId, 'Drill', coords.x, coords.y, coords.z, 'DLC_HEIST_FLEECA_SOUNDSET', true, 40.0, false)
    else
        PlaySoundFromCoord(soundId, 'INTRUDER', coords.x, coords.y, coords.z, 'INTRUDER_WARNING_SOUNDS', true, 20.0, false)
    end
    activeSawmillSounds[stationId] = soundId
end

function StopStationAudio(stationId)
    local soundId = activeSawmillSounds[stationId]
    if soundId then
        StopSound(soundId)
        ReleaseSoundId(soundId)
        activeSawmillSounds[stationId] = nil
    end
end
