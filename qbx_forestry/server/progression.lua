-----------------------------------------------------------
-- SERVER: PROGRESSION
-- XP accumulation, level-up detection, batched DB writes,
-- stat tracking for both Forestry and Woodworking tracks.
-----------------------------------------------------------

--- Pending XP to flush to DB.
---@type table<string, {forestry: number, woodworking: number}>
local PendingXP = {}

-----------------------------------------------------------
-- ADD FORESTRY XP
-----------------------------------------------------------
---@param source number player server id
---@param amount number base XP to award
function AddForestryXP(source, amount)
    local citizenid = GetCitizenId(source)
    if not citizenid then return end

    local cache = PlayerCache[citizenid]
    if not cache then return end

    -- Apply crew XP multiplier
    local multiplier = 1.0
    if GetCrewXPMultiplier then
        multiplier = GetCrewXPMultiplier(source)
    end
    amount = math.floor(amount * multiplier)

    if amount <= 0 then return end

    -- Update crew activity
    if UpdateCrewActivity then
        UpdateCrewActivity(source)
    end

    -- Accumulate in pending
    if not PendingXP[citizenid] then
        PendingXP[citizenid] = { forestry = 0, woodworking = 0 }
    end
    PendingXP[citizenid].forestry = PendingXP[citizenid].forestry + amount

    -- Update in-memory cache
    local oldLevel = cache.forestryLevel
    cache.forestryXP = (cache.forestryXP or 0) + amount
    cache.forestryLevel = ForestryUtils.LevelFromXP(cache.forestryXP, Config.Progression.MaxForestryLevel)

    -- Notify client of XP gain
    TriggerClientEvent('forestry:client:xpGain', source, 'forestry', amount, cache.forestryXP, cache.forestryLevel)

    -- Check for level-up
    if cache.forestryLevel > oldLevel then
        TriggerClientEvent('forestry:client:levelUp', source, 'forestry', cache.forestryLevel)

        if ForestryLog then
            ForestryLog('levelUp', 'Forestry Level Up',
                ('**%s** reached Forestry Level **%d**'):format(cache.name or citizenid, cache.forestryLevel),
                3066993
            )
        end
    end
end

-----------------------------------------------------------
-- ADD WOODWORKING XP
-----------------------------------------------------------
---@param source number
---@param amount number
function AddWoodworkingXP(source, amount)
    local citizenid = GetCitizenId(source)
    if not citizenid then return end

    local cache = PlayerCache[citizenid]
    if not cache then return end

    if amount <= 0 then return end

    -- Accumulate in pending
    if not PendingXP[citizenid] then
        PendingXP[citizenid] = { forestry = 0, woodworking = 0 }
    end
    PendingXP[citizenid].woodworking = PendingXP[citizenid].woodworking + amount

    -- Update in-memory cache
    local oldLevel = cache.woodworkingLevel
    cache.woodworkingXP = (cache.woodworkingXP or 0) + amount
    cache.woodworkingLevel = ForestryUtils.LevelFromXP(cache.woodworkingXP, Config.Progression.MaxWoodworkingLevel)

    -- Notify client
    TriggerClientEvent('forestry:client:xpGain', source, 'woodworking', amount, cache.woodworkingXP, cache.woodworkingLevel)

    -- Check for level-up
    if cache.woodworkingLevel > oldLevel then
        TriggerClientEvent('forestry:client:levelUp', source, 'woodworking', cache.woodworkingLevel)

        if ForestryLog then
            ForestryLog('levelUp', 'Woodworking Level Up',
                ('**%s** reached Woodworking Level **%d**'):format(cache.name or citizenid, cache.woodworkingLevel),
                15105570
            )
        end
    end
end

-----------------------------------------------------------
-- FLUSH PLAYER XP
-- Write pending XP to database for a specific player.
-- Called directly (player disconnect) or from periodic thread.
-----------------------------------------------------------
---@param citizenid string
function FlushPlayerXP(citizenid)
    -- Collect from PendingXP (may have new entries since swap)
    local xp = PendingXP[citizenid]
    if not xp then return end
    if xp.forestry == 0 and xp.woodworking == 0 then
        PendingXP[citizenid] = nil
        return
    end

    local cache = PlayerCache[citizenid]
    if not cache then
        PendingXP[citizenid] = nil
        return
    end

    -- Snapshot and clear before async DB call
    local fXP = xp.forestry
    local wXP = xp.woodworking
    PendingXP[citizenid] = nil

    local affected = MySQL.update.await([[
        UPDATE forestry_players
        SET forestry_xp = forestry_xp + ?,
            woodworking_xp = woodworking_xp + ?,
            forestry_level = ?,
            woodworking_level = ?,
            statistics = ?
        WHERE citizenid = ?
    ]], {
        fXP,
        wXP,
        cache.forestryLevel,
        cache.woodworkingLevel,
        json.encode(cache.statistics or {}),
        citizenid,
    })

    if not affected or affected == 0 then
        lib.print.error(('[Forestry] XP flush failed for %s (F:%d W:%d)'):format(citizenid, fXP, wXP))
        -- Re-add to pending so it can be retried
        if not PendingXP[citizenid] then
            PendingXP[citizenid] = { forestry = 0, woodworking = 0 }
        end
        PendingXP[citizenid].forestry = PendingXP[citizenid].forestry + fXP
        PendingXP[citizenid].woodworking = PendingXP[citizenid].woodworking + wXP
    end
end

-----------------------------------------------------------
-- INCREMENT STAT
-- Update a player's statistics counter in memory cache.
-- Persisted with XP flush.
-----------------------------------------------------------
---@param citizenid string
---@param key string stat key (e.g., 'trees_felled')
---@param amount? number (default 1)
function IncrementStat(citizenid, key, amount)
    local cache = PlayerCache[citizenid]
    if not cache then return end

    if not cache.statistics then
        cache.statistics = {}
    end

    cache.statistics[key] = (cache.statistics[key] or 0) + (amount or 1)
end

-----------------------------------------------------------
-- FLUSH ALL PENDING XP (periodic thread)
-- Runs every FlushInterval (default 60s).
-- Snapshots pending citizens, then flushes each.
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.Progression.FlushInterval or 60000)

        -- Snapshot citizen IDs that need flushing
        local citizens = {}
        for citizenid in pairs(PendingXP) do
            citizens[#citizens + 1] = citizenid
        end

        for _, citizenid in ipairs(citizens) do
            FlushPlayerXP(citizenid)
        end
    end
end)
