-----------------------------------------------------------
-- CLIENT: EFFECTS
-- Audio, particles, camera effects for felling/processing.
-- All functions are optional guards (called with `if Fn then Fn()`)
-----------------------------------------------------------

--- Active felling audio handle.
local fellingAudioId = nil

-----------------------------------------------------------
-- FELLING AUDIO (looping)
-----------------------------------------------------------
---@param toolName string
---@param entity number tree entity handle
function StartFellingAudio(toolName, entity)
    StopFellingAudio() -- Clear any existing

    fellingAudioId = GetSoundId()

    if toolName == 'chainsaw' then
        PlaySoundFromEntity(fellingAudioId, 'Drill', entity, 'DLC_HEIST_FLEECA_SOUNDSET', true, 50.0)
    else
        local coords = GetEntityCoords(entity)
        PlaySoundFromCoord(fellingAudioId, 'INTRUDER', coords.x, coords.y, coords.z, 'INTRUDER_WARNING_SOUNDS', true, 30.0, false)
    end
end

-----------------------------------------------------------
-- STOP FELLING AUDIO
-----------------------------------------------------------
function StopFellingAudio()
    if fellingAudioId then
        StopSound(fellingAudioId)
        ReleaseSoundId(fellingAudioId)
        fellingAudioId = nil
    end
end

-----------------------------------------------------------
-- TREE CREAK (one-shot, ~2s before fall)
-----------------------------------------------------------
---@param coords vector3
function PlayTreeCreak(coords)
    local soundId = GetSoundId()
    PlaySoundFromCoord(soundId, 'Pin_Good', coords.x, coords.y, coords.z, 'GTAO_FM_Events_Soundset', false, 25.0, false)
    SetTimeout(2000, function()
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end)
end

-----------------------------------------------------------
-- TREE FALL SOUND (during fall animation)
-----------------------------------------------------------
---@param coords vector3
function PlayTreeFallSound(coords)
    local soundId = GetSoundId()
    PlaySoundFromCoord(soundId, 'INTRUDER', coords.x, coords.y, coords.z, 'INTRUDER_WARNING_SOUNDS', false, 60.0, false)
    SetTimeout(3000, function()
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end)
end

-----------------------------------------------------------
-- TREE IMPACT (ground hit + dust particles)
-----------------------------------------------------------
---@param coords vector3
function PlayTreeImpact(coords)
    -- Ground impact sound
    local soundId = GetSoundId()
    PlaySoundFromCoord(soundId, 'TIMER_STOP', coords.x, coords.y, coords.z, 'HUD_MINI_GAME_SOUNDSET', false, 50.0, false)
    SetTimeout(1000, function()
        StopSound(soundId)
        ReleaseSoundId(soundId)
    end)

    -- Dust particle
    UseParticleFxAsset('core')
    StartParticleFxNonLoopedAtCoord(
        'ent_dst_gen_dirt_lrg',
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        2.0, false, false, false
    )
end

-----------------------------------------------------------
-- CHOP PARTICLE (wood chips on each swing)
-----------------------------------------------------------
---@param coords vector3
function SpawnChopParticle(coords)
    UseParticleFxAsset('core')
    StartParticleFxNonLoopedAtCoord(
        'ent_brk_wood_lg',
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        1.0, false, false, false
    )
end

-----------------------------------------------------------
-- CHAINSAW KICKBACK (camera shake + minor damage)
-----------------------------------------------------------
function ApplyChainsawKickback()
    ShakeGameplayCam('HAND_SHAKE', 0.15)
    AnimpostfxPlay('FocusOut', 0, false)
    Wait(300)
    AnimpostfxStop('FocusOut')

    -- Apply kickback damage
    local ped = cache.ped
    local maxHealth = GetEntityMaxHealth(ped)
    local damage = math.random(Config.Injury.ChainsawKickback.min, Config.Injury.ChainsawKickback.max)
    local healthLoss = math.floor(maxHealth * damage / 100)
    SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - healthLoss))

    lib.notify({ description = 'Chainsaw kicked back!', type = 'error' })
end
