-----------------------------------------------------------
-- SERVER: MAIN ENTRY POINT
-- Player lifecycle, usable item registration, core state.
-----------------------------------------------------------

--- Player data cache: citizenid -> { forestryLevel, woodworkingLevel, licenses, ... }
---@type table<string, table>
PlayerCache = {}

--- Map server source -> citizenid for fast lookups.
---@type table<number, string>
SourceToCitizen = {}

--- Players currently affected by bee swarm.
---@type table<number, vector3> source -> tree coords
PlayerBeeSwarmActive = {}

--- Per-player felling cooldown (GetGameTimer timestamps).
---@type table<number, integer>
FellingCooldowns = {}

--- Felling cooldown duration in ms.
local FELLING_COOLDOWN = 3000

-----------------------------------------------------------
-- HELPER: Get citizenid from source
-----------------------------------------------------------
---@param source number
---@return string?
function GetCitizenId(source)
    return SourceToCitizen[source]
end

-----------------------------------------------------------
-- HELPER: Get cached player data
-----------------------------------------------------------
---@param citizenid string
---@return table?
function GetPlayerCache(citizenid)
    return PlayerCache[citizenid]
end

-----------------------------------------------------------
-- HELPER: Get cached data by source
-----------------------------------------------------------
---@param source number
---@return table?
function GetPlayerCacheBySource(source)
    local cid = SourceToCitizen[source]
    if not cid then return nil end
    return PlayerCache[cid]
end

-----------------------------------------------------------
-- PLAYER LOAD: Fetch or create DB row, populate cache
-----------------------------------------------------------
local function OnPlayerLoaded(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    SourceToCitizen[source] = citizenid

    -- Fetch or create forestry_players row
    local row = MySQL.single.await(
        'SELECT * FROM forestry_players WHERE citizenid = ?',
        { citizenid }
    )

    if not row then
        MySQL.insert.await(
            'INSERT INTO forestry_players (citizenid) VALUES (?)',
            { citizenid }
        )
        row = {
            forestry_xp = 0,
            forestry_level = 0,
            woodworking_xp = 0,
            woodworking_level = 0,
            licenses = '{}',
            statistics = '{"trees_felled":0,"logs_processed":0,"lumber_produced":0,"furniture_crafted":0,"contracts_completed":0,"total_earned":0}',
        }
    end

    -- Parse JSON fields
    local licenses = {}
    local statistics = {}
    if type(row.licenses) == 'string' then
        licenses = json.decode(row.licenses) or {}
    elseif type(row.licenses) == 'table' then
        licenses = row.licenses
    end
    if type(row.statistics) == 'string' then
        statistics = json.decode(row.statistics) or {}
    elseif type(row.statistics) == 'table' then
        statistics = row.statistics
    end

    -- Recalculate levels from XP (source of truth)
    local forestryLevel = ForestryUtils.LevelFromXP(row.forestry_xp, Config.Progression.MaxForestryLevel)
    local woodworkingLevel = ForestryUtils.LevelFromXP(row.woodworking_xp, Config.Progression.MaxWoodworkingLevel)

    -- Build display name from character info
    local charinfo = player.PlayerData.charinfo
    local name = charinfo and (charinfo.firstname .. ' ' .. charinfo.lastname) or citizenid

    PlayerCache[citizenid] = {
        source = source,
        citizenid = citizenid,
        name = name,
        forestryXP = row.forestry_xp,
        forestryLevel = forestryLevel,
        woodworkingXP = row.woodworking_xp,
        woodworkingLevel = woodworkingLevel,
        licenses = licenses,
        statistics = statistics,
    }

    lib.print.info(('[Forestry] Player loaded: %s (Forestry Lv%d, WW Lv%d)'):format(
        citizenid, forestryLevel, woodworkingLevel
    ))
end

-----------------------------------------------------------
-- PLAYER UNLOAD: Flush XP, clean up cache
-----------------------------------------------------------
local function OnPlayerUnloaded(source)
    local citizenid = SourceToCitizen[source]

    if citizenid then
        -- Flush any pending XP before removal
        FlushPlayerXP(citizenid)

        -- Save licenses and statistics
        local cache = PlayerCache[citizenid]
        if cache then
            MySQL.update.await(
                'UPDATE forestry_players SET licenses = ?, statistics = ? WHERE citizenid = ?',
                { json.encode(cache.licenses), json.encode(cache.statistics), citizenid }
            )
        end

        PlayerCache[citizenid] = nil
    end

    SourceToCitizen[source] = nil
    PlayerBeeSwarmActive[source] = nil
    FellingCooldowns[source] = nil

    -- Remove from crew if applicable
    if RemovePlayerFromCrew then
        RemovePlayerFromCrew(source, 'disconnected')
    end
end

-----------------------------------------------------------
-- FRAMEWORK EVENTS: Player lifecycle
-----------------------------------------------------------
-- QBX fires this when a player's character is fully loaded
RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    OnPlayerLoaded(source)
end)

-- Handle player disconnect
AddEventHandler('playerDropped', function()
    OnPlayerUnloaded(source)
end)

-- Handle character logout (without disconnect)
RegisterNetEvent('qbx_core:server:playerLoggedOut', function()
    OnPlayerUnloaded(source)
end)

-- Job update: auto-remove from crew if job changes away from lumberjack
RegisterNetEvent('QBCore:Server:OnJobUpdate', function(source, job)
    if job.name ~= FORESTRY_JOB then
        if RemovePlayerFromCrew then
            RemovePlayerFromCrew(source, 'job_changed')
        end
    end
end)

-----------------------------------------------------------
-- ON RESOURCE START: Load already-connected players
-----------------------------------------------------------
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Load any players already online (hot reload support)
    local players = exports.qbx_core:GetQBPlayers()
    if players then
        for src, _ in pairs(players) do
            OnPlayerLoaded(src)
        end
    end

    lib.print.info('[Forestry] Resource started. Player cache initialized.')
end)

-----------------------------------------------------------
-- USABLE ITEM REGISTRATIONS
-----------------------------------------------------------

-- Smoke canister: disperse active bee swarm
exports.ox_inventory:RegisterUsableItem('smoke_canister', function(source, item, data)
    if not PlayerBeeSwarmActive[source] then
        lib.notify(source, { description = 'No bee swarm to disperse.', type = 'error' })
        return
    end

    exports.ox_inventory:RemoveItem(source, 'smoke_canister', 1)
    PlayerBeeSwarmActive[source] = nil
    TriggerClientEvent('forestry:client:beeSwarm:disperse', source)

    -- Bonus honeycomb drop
    local amount = math.random(
        Config.Events.BeeSwarm.bonusAmount[1],
        Config.Events.BeeSwarm.bonusAmount[2]
    )
    exports.ox_inventory:AddItem(source, 'honeycomb', amount)
    lib.notify(source, {
        description = ('You dispersed the swarm and found %dx honeycomb!'):format(amount),
        type = 'success',
    })
end)

-- Chainsaw fuel: refuel equipped chainsaw
exports.ox_inventory:RegisterUsableItem('chainsaw_fuel', function(source, item, data)
    local chainsaw = exports.ox_inventory:Search(source, 'slots', 'chainsaw')
    if not chainsaw or #chainsaw == 0 then
        lib.notify(source, { description = 'You need a chainsaw to refuel.', type = 'error' })
        return
    end

    exports.ox_inventory:RemoveItem(source, 'chainsaw_fuel', 1)

    local slot = chainsaw[1].slot
    local metadata = chainsaw[1].metadata or {}
    metadata.fuel = math.min(
        (metadata.fuel or 0) + Config.Tools.FuelPerCanister,
        Config.Tools.MaxFuel
    )
    exports.ox_inventory:SetMetadata(source, slot, metadata)
    lib.notify(source, {
        description = ('Chainsaw refueled. Fuel: %d/%d'):format(metadata.fuel, Config.Tools.MaxFuel),
        type = 'success',
    })
end)

-- Sharpening kit: triggers client-side tool selection
exports.ox_inventory:RegisterUsableItem('sharpening_kit', function(source, item, data)
    TriggerClientEvent('forestry:client:sharpen:selectTool', source)
end)

-- Tree sapling: triggers client-side planting proximity check
exports.ox_inventory:RegisterUsableItem('tree_sapling', function(source, item, data)
    TriggerClientEvent('forestry:client:sapling:startPlant', source)
end)

-----------------------------------------------------------
-- FELLING COOLDOWN HELPERS
-----------------------------------------------------------

--- Check if player is on felling cooldown.
---@param source number
---@return boolean
function IsFellingOnCooldown(source)
    local last = FellingCooldowns[source]
    if not last then return false end
    return (GetGameTimer() - last) < FELLING_COOLDOWN
end

--- Set felling cooldown for player.
---@param source number
function SetFellingCooldown(source)
    FellingCooldowns[source] = GetGameTimer()
end
