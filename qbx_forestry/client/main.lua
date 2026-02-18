-----------------------------------------------------------
-- CLIENT: MAIN
-- Entry point, player state management, tree model targeting,
-- job clock-in/out, event handlers.
-- NOTE: PlayerState, FelledTreeCache, CarryState are
-- initialized in config/client.lua (loads first).
-----------------------------------------------------------

-----------------------------------------------------------
-- ON RESOURCE START
-----------------------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(1000)

    -- Request player data from server
    local data = lib.callback.await('forestry:player:getData', false)
    if data then
        PlayerState.forestryLevel = data.forestryLevel or 0
        PlayerState.woodworkingLevel = data.woodworkingLevel or 0
        PlayerState.loaded = true
    end

    -- Request felled tree cache
    TriggerServerEvent('forestry:server:requestFelledCache')

    -- Register tree models with ox_target
    RegisterTreeTargets()

    -- Register sawmill targets
    if RegisterSawmillTargets then
        RegisterSawmillTargets()
    end

    -- Check if already on duty
    local playerData = exports.qbx_core:GetPlayerData()
    if playerData and playerData.job and playerData.job.name == FORESTRY_JOB and playerData.job.onduty then
        PlayerState.onDuty = true
        if InitStamina then
            InitStamina(PlayerState.forestryLevel)
        end
    end
end)

-----------------------------------------------------------
-- REGISTER TREE TARGETS
-- Add ox_target to all tree model hashes for global
-- tree system (any GTA V tree is choppable).
-----------------------------------------------------------
function RegisterTreeTargets()
    for speciesKey, speciesData in pairs(Config.TreeSpecies) do
        for _, model in ipairs(speciesData.models) do
            exports.ox_target:addModel(model, {
                {
                    name = 'forestry_chop_' .. speciesKey .. '_' .. model,
                    icon = 'fa-solid fa-tree',
                    label = GetTreeTargetLabel(speciesKey, speciesData),
                    distance = Config.InteractionDistances.Tree,
                    canInteract = function(entity)
                        if not PlayerState.onDuty then return false end
                        local treeKey = ForestryUtils.TreeKey(GetEntityModel(entity), GetEntityCoords(entity))
                        if FelledTreeCache[treeKey] then return false end
                        return true
                    end,
                    onSelect = function(data)
                        if StartFelling then
                            StartFelling(data.entity)
                        end
                    end,
                },
            })
        end
    end
end

-----------------------------------------------------------
-- LEVEL-GATED TARGET LABEL
-- What the player sees depends on Forestry level:
-- 0-4: "Tree"
-- 5-9: Species name
-- 10-19: Species + size
-- 20-29: Species + size + yield
-- 30+: Species + size + yield + value
-----------------------------------------------------------
---@param speciesKey string
---@param speciesData table
---@return string
function GetTreeTargetLabel(speciesKey, speciesData)
    local level = PlayerState.forestryLevel

    if level < 5 then
        return 'Tree'
    elseif level < 10 then
        return speciesData.label .. ' Tree'
    elseif level < 20 then
        local sizeLabel = Config.TreeSizes[speciesData.size] and Config.TreeSizes[speciesData.size].label or speciesData.size
        return ('%s Tree (%s)'):format(speciesData.label, sizeLabel)
    elseif level < 30 then
        local sizeLabel = Config.TreeSizes[speciesData.size] and Config.TreeSizes[speciesData.size].label or speciesData.size
        return ('%s Tree (%s, ~%d logs)'):format(speciesData.label, sizeLabel, speciesData.baseYield)
    else
        local sizeLabel = Config.TreeSizes[speciesData.size] and Config.TreeSizes[speciesData.size].label or speciesData.size
        return ('%s Tree (%s, ~%d logs, $%d)'):format(speciesData.label, sizeLabel, speciesData.baseYield, speciesData.baseValue)
    end
end

-----------------------------------------------------------
-- JOB UPDATE HANDLER
-----------------------------------------------------------
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    if job.name == FORESTRY_JOB and job.onduty then
        PlayerState.onDuty = true
        if InitStamina then
            InitStamina(PlayerState.forestryLevel)
        end
        -- Apply clothing
        if Config.Clothing.AutoDress then
            ApplyForestryOutfit()
        end
    else
        if PlayerState.onDuty then
            PlayerState.onDuty = false
            -- Restore clothing
            if Config.Clothing.AutoDress then
                RestoreOutfit()
            end
            -- Cancel carry if active
            if CarryState and CancelCarry then
                CancelCarry(false)
            end
        end
    end
end)

-----------------------------------------------------------
-- FELLED TREE CACHE SYNC
-----------------------------------------------------------
RegisterNetEvent('forestry:client:syncFelledCache', function(cacheData)
    FelledTreeCache = cacheData or {}
end)

RegisterNetEvent('forestry:client:treeFelled', function(treeKey)
    FelledTreeCache[treeKey] = true
end)

RegisterNetEvent('forestry:client:treeRespawned', function(keys)
    if type(keys) == 'table' then
        for _, key in ipairs(keys) do
            FelledTreeCache[key] = nil
        end
    end
end)

-----------------------------------------------------------
-- XP GAIN NOTIFICATION
-----------------------------------------------------------
RegisterNetEvent('forestry:client:xpGain', function(track, amount, total, level)
    if track == 'forestry' then
        PlayerState.forestryLevel = level
    elseif track == 'woodworking' then
        PlayerState.woodworkingLevel = level
    end

    local trackLabel = track == 'forestry' and 'Forestry' or 'Woodworking'
    lib.notify({
        description = ('+%d %s XP'):format(amount, trackLabel),
        type = 'inform',
        duration = 2000,
    })
end)

-----------------------------------------------------------
-- LEVEL UP NOTIFICATION
-----------------------------------------------------------
RegisterNetEvent('forestry:client:levelUp', function(track, newLevel)
    if track == 'forestry' then
        PlayerState.forestryLevel = newLevel
        if RefreshStamina then
            RefreshStamina(newLevel)
        end
    elseif track == 'woodworking' then
        PlayerState.woodworkingLevel = newLevel
    end

    -- Check for new unlocks at this level
    local unlockMsg = ''
    if track == 'forestry' and Config.ForestryUnlocks then
        local unlock = Config.ForestryUnlocks[newLevel]
        if unlock then
            unlockMsg = '\nUnlocked: ' .. unlock
        end
    end

    lib.notify({
        title = track == 'forestry' and 'Forestry Level Up!' or 'Woodworking Level Up!',
        description = ('You reached level %d!%s'):format(newLevel, unlockMsg),
        type = 'success',
        duration = 6000,
    })

    PlaySoundFrontend(-1, 'RANK_UP', 'HUD_AWARDS', true)
end)

-----------------------------------------------------------
-- CLOTHING HELPERS
-----------------------------------------------------------
local savedOutfit = nil

function ApplyForestryOutfit()
    if not Config.Clothing.AutoDress then return end

    local ped = cache.ped
    local isMale = IsPedMale(ped)
    local outfit = Config.Clothing.Outfits[isMale and 'male' or 'female']
    if not outfit then return end

    -- Save current outfit for restoration
    savedOutfit = {}
    for componentId in pairs(outfit) do
        if outfit[componentId].prop then
            savedOutfit[componentId] = {
                drawable = GetPedPropIndex(ped, componentId),
                texture = GetPedPropTextureIndex(ped, componentId),
                prop = true,
            }
        else
            savedOutfit[componentId] = {
                drawable = GetPedDrawableVariation(ped, componentId),
                texture = GetPedTextureVariation(ped, componentId),
            }
        end
    end

    -- Apply forestry outfit
    for componentId, data in pairs(outfit) do
        if data.prop then
            SetPedPropIndex(ped, componentId, data.drawable, data.texture, true)
        else
            SetPedComponentVariation(ped, componentId, data.drawable, data.texture, 0)
        end
    end
end

function RestoreOutfit()
    if not savedOutfit then return end

    local ped = cache.ped
    for componentId, data in pairs(savedOutfit) do
        if data.prop then
            if data.drawable >= 0 then
                SetPedPropIndex(ped, componentId, data.drawable, data.texture, true)
            else
                ClearPedProp(ped, componentId)
            end
        else
            SetPedComponentVariation(ped, componentId, data.drawable, data.texture, 0)
        end
    end

    savedOutfit = nil
end

-----------------------------------------------------------
-- RESOURCE CLEANUP
-----------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Restore outfit
    if savedOutfit then
        RestoreOutfit()
    end
end)
