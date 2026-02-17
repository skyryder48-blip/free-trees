-----------------------------------------------------------
-- CLIENT: FELLING
-- Tree targeting, server-validated felling, skill checks,
-- directional fall, TIMBER! warning, crush zone.
-----------------------------------------------------------

--- Is the player currently felling a tree?
local isFelling = false

-----------------------------------------------------------
-- START FELLING (called from ox_target onSelect)
-----------------------------------------------------------
---@param entity number tree entity handle
function StartFelling(entity)
    if isFelling then
        lib.notify({ description = 'Already felling a tree.', type = 'error' })
        return
    end

    if not PlayerState.onDuty then
        lib.notify({ description = 'You must be clocked in as a lumberjack.', type = 'error' })
        return
    end

    -- Check stamina
    if IsWinded and IsWinded() then
        lib.notify({ description = 'You\'re too winded to chop. Catch your breath.', type = 'error' })
        return
    end

    local model = GetEntityModel(entity)
    local entityCoords = GetEntityCoords(entity)
    local treeKey = ForestryUtils.TreeKey(model, entityCoords)

    -- Quick client-side pre-check
    if FelledTreeCache[treeKey] then
        lib.notify({ description = 'This tree has already been felled.', type = 'error' })
        return
    end

    -- Find equipped tool client-side (for UI feedback; server re-validates)
    local toolName = GetEquippedChoppingTool()

    -- Server validation
    local success, err, fellData = lib.callback.await('forestry:felling:validate', false,
        treeKey, model, entityCoords, toolName
    )

    if not success then
        local messages = {
            wrong_job = 'You need to be a lumberjack.',
            off_duty = 'You must be on duty.',
            no_permit = 'You need a valid timber permit.',
            cooldown = 'You\'re still recovering from the last tree.',
            already_felled = 'This tree has already been felled.',
            unknown_species = 'This tree can\'t be chopped.',
            no_tool = 'You need a chopping tool.',
            wrong_tool_size = 'Your tool can\'t fell a tree this size.',
            too_far = 'You\'re too far from the tree.',
            ['tool_error:no_tool'] = 'You need a chopping tool in your inventory.',
            ['tool_error:level_too_low'] = 'You\'re not experienced enough for this tool.',
            ['tool_error:missing_cert'] = 'You\'re missing a required certification.',
            ['tool_error:broken'] = 'Your tool is broken. Use a sharpening kit.',
            ['tool_error:no_fuel'] = 'Your chainsaw is out of fuel.',
        }
        lib.notify({ description = messages[err] or 'Cannot fell this tree.', type = 'error' })
        return
    end

    -- Begin felling sequence
    isFelling = true
    local playerCoords = GetEntityCoords(cache.ped)

    -- Calculate fall direction (away from player)
    local fallDir = ForestryUtils.GetFallDirection(playerCoords, entityCoords)
    local fallHeading = ForestryUtils.DirectionToHeading(fallDir)

    -- Face the tree
    TaskTurnPedToFaceCoord(cache.ped, entityCoords.x, entityCoords.y, entityCoords.z, 1000)
    Wait(1000)

    -- Play chopping animation
    local animDict, animName = GetChoppingAnim(fellData.tool)
    lib.requestAnimDict(animDict)

    -- Start audio
    if StartFellingAudio then
        StartFellingAudio(fellData.tool, entity)
    end

    -- Skill check sequence
    local skillCheckPattern = fellData.skillCheck
    local allPassed = true

    if #skillCheckPattern > 0 then
        -- Play chopping progress with skill checks
        local totalTime = fellData.fellingTime
        local checkInterval = totalTime / (#skillCheckPattern + 1)

        for i, difficulty in ipairs(skillCheckPattern) do
            -- Consume a stamina swing per check
            if ConsumeSwing then
                local canSwing = ConsumeSwing()
                if not canSwing then
                    -- Ran out of stamina mid-fell
                    ClearPedTasks(cache.ped)
                    isFelling = false
                    if StopFellingAudio then StopFellingAudio() end
                    lib.notify({ description = 'You\'re too exhausted to continue.', type = 'error' })
                    return
                end
            end

            -- Play chop animation segment
            TaskPlayAnim(cache.ped, animDict, animName, 8.0, -8.0, math.floor(checkInterval), 1, 0, false, false, false)

            -- Spawn chop particle
            if SpawnChopParticle then
                SpawnChopParticle(entityCoords)
            end

            -- Wait for animation segment then trigger skill check
            Wait(math.floor(checkInterval * 0.8))

            local passed = lib.skillCheck(difficulty, Config.SkillCheck.inputs)

            if not passed then
                allPassed = false

                -- Chainsaw kickback on first fail
                if fellData.tool == 'chainsaw' and i == 1 then
                    if ApplyChainsawKickback then
                        ApplyChainsawKickback()
                    end
                end
            end
        end
    else
        -- No skill check - just progress bar
        TaskPlayAnim(cache.ped, animDict, animName, 8.0, -8.0, fellData.fellingTime, 1, 0, false, false, false)

        local completed = lib.progressCircle({
            duration = fellData.fellingTime,
            label = 'Chopping...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
        })

        if not completed then
            ClearPedTasks(cache.ped)
            isFelling = false
            if StopFellingAudio then StopFellingAudio() end
            return
        end
    end

    -- Stop chopping animation
    ClearPedTasks(cache.ped)
    if StopFellingAudio then StopFellingAudio() end

    -- Tree creaking sound (last 2s before fall)
    if PlayTreeCreak then
        PlayTreeCreak(entityCoords)
    end
    Wait(500)

    -- Server: complete felling (grants XP, rolls events, etc)
    local completeSuccess, result = lib.callback.await('forestry:felling:complete', false,
        treeKey, model, entityCoords, fellData.tool, allPassed
    )

    if not completeSuccess then
        isFelling = false
        return
    end

    -- TIMBER! warning to nearby players
    TriggerServerEvent('forestry:server:timberWarning', entityCoords, fallDir)

    -- Animate tree fall
    AnimateTreeFall(entity, entityCoords, fallDir, fallHeading)

    -- Handle crush zone
    CheckCrushZone(entityCoords, fallDir)

    -- Handle random event
    if result.event then
        HandleFellingEvent(result.event, entityCoords)
    end

    -- Start field processing prompt
    Wait(2000)

    if result.yield and result.yield > 0 then
        PromptFieldProcessing(entityCoords, result.species, result.quality, result.yield, result.size)
    end

    isFelling = false
end

-----------------------------------------------------------
-- ANIMATE TREE FALL
-----------------------------------------------------------
function AnimateTreeFall(entity, treeCoords, fallDir, fallHeading)
    -- Hide the original tree entity
    SetEntityVisible(entity, false, false)
    FreezeEntityPosition(entity, true)

    -- The tree is now "felled" - we rely on FelledTreeCache to keep it hidden.
    -- A falling prop could be created here for visual effect,
    -- but for performance we use audio + particles + camera shake.

    -- Tree fall sound
    if PlayTreeFallSound then
        PlayTreeFallSound(treeCoords)
    end

    -- Impact effects after ~1.5s fall time
    Wait(1500)

    -- Ground impact
    local impactPoint = treeCoords + fallDir * 6.0
    impactPoint = vec3(impactPoint.x, impactPoint.y, treeCoords.z)

    if PlayTreeImpact then
        PlayTreeImpact(impactPoint)
    end

    -- Camera shake for nearby players
    local playerCoords = GetEntityCoords(cache.ped)
    local distToImpact = #(playerCoords - impactPoint)
    if distToImpact <= Config.CameraEffects.TreeImpactShakeRadius then
        local intensity = Config.CameraEffects.TreeImpactShakeMax -
            (distToImpact / Config.CameraEffects.TreeImpactShakeRadius) *
            (Config.CameraEffects.TreeImpactShakeMax - Config.CameraEffects.TreeImpactShakeMin)
        ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', intensity)
    end
end

-----------------------------------------------------------
-- TIMBER! WARNING (server broadcasts to nearby)
-----------------------------------------------------------
RegisterNetEvent('forestry:client:timberWarning', function(treeCoords, fallDir)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - treeCoords)

    if dist > Config.TimberWarning.Radius then return end

    -- On-screen warning text
    lib.notify({
        title = 'âš ï¸ TIMBER!',
        description = 'A tree is falling nearby!',
        type = 'warning',
        duration = Config.TimberWarning.Duration,
    })

    -- Warning sound
    if Config.TimberWarning.Sound then
        PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    end
end)

-- Server-side relay for TIMBER warning
RegisterNetEvent('forestry:server:timberWarning', function(treeCoords, fallDir)
    -- This is actually handled server-side to broadcast
end)

-- Server event handler in server scope - added via server events
-- We trigger it from client and the server relays to nearby players

-----------------------------------------------------------
-- CRUSH ZONE CHECK
-----------------------------------------------------------
function CheckCrushZone(treeCoords, fallDir)
    local playerCoords = GetEntityCoords(cache.ped)
    local impactEnd = treeCoords + fallDir * 8.0
    impactEnd = vec3(impactEnd.x, impactEnd.y, treeCoords.z)

    local dist = ForestryUtils.DistanceToLineSegment(
        vec3(playerCoords.x, playerCoords.y, 0),
        vec3(treeCoords.x, treeCoords.y, 0),
        vec3(impactEnd.x, impactEnd.y, 0)
    )

    if dist <= Config.Injury.CrushZoneRadius then
        -- Player is in the crush zone!
        local damage = math.random(Config.Injury.CrushDamage.min, Config.Injury.CrushDamage.max)
        local ped = cache.ped
        local maxHealth = GetEntityMaxHealth(ped)
        local healthLoss = math.floor(maxHealth * damage / 100)

        SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - healthLoss))
        SetPedToRagdoll(ped, Config.Injury.CrushRagdoll, Config.Injury.CrushRagdoll, 0, false, false, false)

        ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 0.3)
        AnimpostfxPlay('Rampage', 0, true)
        Wait(500)
        AnimpostfxStop('Rampage')

        lib.notify({
            description = 'You were crushed by the falling tree!',
            type = 'error',
            duration = 5000,
        })
    end
end

-----------------------------------------------------------
-- HANDLE FELLING EVENT (widow maker / bee swarm)
-----------------------------------------------------------
function HandleFellingEvent(eventData, treeCoords)
    if eventData.name == 'widow_maker' then
        HandleWidowMaker(eventData, treeCoords)
    elseif eventData.name == 'bee_swarm' then
        HandleBeeSwarm(eventData, treeCoords)
    end
end

-----------------------------------------------------------
-- WIDOW MAKER
-----------------------------------------------------------
function HandleWidowMaker(eventData, treeCoords)
    -- Short delay (branch breaking free)
    Wait(math.random(500, 1000))

    -- Warning sound
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)

    -- Skill check
    local passed = lib.skillCheck(eventData.skillCheck, Config.SkillCheck.inputs)

    if passed then
        -- Dodged
        TriggerServerEvent('forestry:server:widowMaker:result', true)
    else
        -- Hit
        local ped = cache.ped
        local maxHealth = GetEntityMaxHealth(ped)
        local damage = math.random(eventData.damage.min, eventData.damage.max)
        local healthLoss = math.floor(maxHealth * damage / 100)

        SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - healthLoss))
        SetPedToRagdoll(ped, eventData.staggerDuration, eventData.staggerDuration, 0, false, false, false)

        ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', 0.2)
        AnimpostfxPlay('FocusOut', 0, false)
        Wait(800)
        AnimpostfxStop('FocusOut')

        TriggerServerEvent('forestry:server:widowMaker:result', false)
    end
end

-----------------------------------------------------------
-- BEE SWARM
-----------------------------------------------------------
function HandleBeeSwarm(eventData, treeCoords)
    Wait(1000) -- Delay before swarm starts

    lib.notify({
        title = 'ðŸ Bee Swarm!',
        description = 'You disturbed a bee colony! Get away or use a smoke canister!',
        type = 'warning',
        duration = 5000,
    })

    local startTime = GetGameTimer()
    local duration = eventData.duration
    local tickInterval = eventData.tickInterval
    local lastTick = startTime
    local escaped = false

    -- Speed debuff
    SetPedMoveRateOverride(cache.ped, eventData.speedDebuff)

    CreateThread(function()
        while true do
            Wait(200)

            -- Check if dispelled (smoke canister used)
            -- Server will clear PlayerBeeSwarmActive and trigger disperse event

            local now = GetGameTimer()
            local elapsed = now - startTime

            -- Duration expired
            if elapsed >= duration then
                break
            end

            -- Check escape distance
            local playerCoords = GetEntityCoords(cache.ped)
            local dist = #(playerCoords - treeCoords)
            if dist >= eventData.escapeDistance then
                escaped = true
                TriggerServerEvent('forestry:server:beeSwarm:escaped')
                break
            end

            -- Check if in water
            if IsEntityInWater(cache.ped) then
                escaped = true
                TriggerServerEvent('forestry:server:beeSwarm:escaped')
                break
            end

            -- Damage tick
            if (now - lastTick) >= tickInterval then
                lastTick = now
                local ped = cache.ped
                local maxHealth = GetEntityMaxHealth(ped)
                local healthLoss = math.floor(maxHealth * eventData.tickDamage / 100)
                SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - healthLoss))

                -- Screen pulse
                AnimpostfxPlay('FocusOut', 0, false)
                Wait(200)
                AnimpostfxStop('FocusOut')
            end
        end

        -- Restore movement speed
        SetPedMoveRateOverride(cache.ped, 1.0)

        if not escaped then
            TriggerServerEvent('forestry:server:beeSwarm:ended')
            lib.notify({ description = 'The bees have lost interest.', type = 'inform' })
        else
            lib.notify({ description = 'You escaped the bee swarm!', type = 'success' })
        end
    end)
end

-- Disperse handler (from smoke canister)
RegisterNetEvent('forestry:client:beeSwarm:disperse', function()
    SetPedMoveRateOverride(cache.ped, 1.0)
    lib.notify({ description = 'The smoke dispersed the bees!', type = 'success' })
end)

-----------------------------------------------------------
-- HELPER: Get equipped chopping tool name
-----------------------------------------------------------
function GetEquippedChoppingTool()
    for toolName in pairs(Config.ChoppingTools) do
        local count = exports.ox_inventory:Search('count', toolName)
        if count and count > 0 then
            return toolName
        end
    end
    return nil
end

-----------------------------------------------------------
-- HELPER: Get chopping animation dict/name
-----------------------------------------------------------
function GetChoppingAnim(toolName)
    if toolName == 'chainsaw' then
        return 'anim@heists@fleeca_bank@drilling', 'drill_straight_idle'
    else
        return 'melee@hatchet@streamed_core', 'ground_attack_on_spot'
    end
end

-----------------------------------------------------------
-- PROMPT FIELD PROCESSING
-- After felling, prompt player to limb and buck.
-----------------------------------------------------------
function PromptFieldProcessing(treeCoords, speciesKey, quality, yield, treeSize)
    -- This will be expanded in processing.lua
    -- For now, show a context menu for next steps

    lib.notify({
        title = 'Tree Felled!',
        description = ('Ready to process: %d logs available. Use the tree to limb and buck.'):format(yield),
        type = 'success',
        duration = 5000,
    })

    -- Register a temporary ox_target at the felled tree location for processing
    if RegisterProcessingTarget then
        RegisterProcessingTarget(treeCoords, speciesKey, quality, yield, treeSize)
    end
end

-----------------------------------------------------------
-- TIMBER WARNING SERVER RELAY
-----------------------------------------------------------
-- Server-side event to broadcast TIMBER warning to nearby players
-- (This is registered on server side; client triggers it)
