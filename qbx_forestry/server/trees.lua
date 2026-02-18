-----------------------------------------------------------
-- SERVER: TREES
-- Felled tree tracking, respawn system, sapling planting.
-----------------------------------------------------------

--- In-memory cache of felled tree keys.
---@type table<string, boolean>
FelledTrees = {}

-----------------------------------------------------------
-- IS TREE FELLED
-----------------------------------------------------------
---@param treeKey string composite key from ForestryUtils.TreeKey
---@return boolean
function IsTreeFelled(treeKey)
    return FelledTrees[treeKey] == true
end

-----------------------------------------------------------
-- RECORD FELLED TREE
-- Insert into DB, add to cache, broadcast to clients.
-----------------------------------------------------------
---@param treeKey string
---@param modelHash number
---@param treeSize string 'small'|'medium'|'large'
---@return boolean success
function RecordFelledTree(treeKey, modelHash, treeSize)
    local sizeConfig = Config.TreeSizes[treeSize]
    if not sizeConfig then return false end

    local respawnMinutes = sizeConfig.respawnMinutes

    MySQL.insert.await(
        'INSERT INTO forestry_felled_trees (tree_key, model_hash, respawns_at) VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE)) ON DUPLICATE KEY UPDATE felled_at = NOW(), respawns_at = DATE_ADD(NOW(), INTERVAL ? MINUTE)',
        { treeKey, modelHash, respawnMinutes, respawnMinutes }
    )

    FelledTrees[treeKey] = true

    -- Broadcast to all clients
    TriggerClientEvent('forestry:client:treeFelled', -1, treeKey)

    return true
end

-----------------------------------------------------------
-- GET FELLED TREE CACHE
-----------------------------------------------------------
---@return table<string, boolean>
function GetFelledTreeCache()
    return FelledTrees
end

-----------------------------------------------------------
-- PLANT SAPLING (immediate respawn + XP reward)
-----------------------------------------------------------
---@param source number
---@param treeKey string
---@return boolean success
function PlantSapling(source, treeKey)
    if not FelledTrees[treeKey] then
        return false
    end

    -- Check for sapling item
    local count = exports.ox_inventory:Search(source, 'count', 'tree_sapling')
    if not count or count < 1 then
        TriggerClientEvent('ox_lib:notify', source, {
            description = 'You need a tree sapling.',
            type = 'error',
        })
        return false
    end

    -- Remove sapling
    exports.ox_inventory:RemoveItem(source, 'tree_sapling', 1)

    -- Set immediate respawn
    MySQL.update('UPDATE forestry_felled_trees SET respawns_at = NOW() WHERE tree_key = ?', { treeKey })

    -- Remove from cache and notify clients
    FelledTrees[treeKey] = nil
    TriggerClientEvent('forestry:client:treeRespawned', -1, { treeKey })

    -- Award XP
    if AddForestryXP then
        AddForestryXP(source, Config.Progression.ForestryXP.plant_sapling or 15)
    end

    TriggerClientEvent('ox_lib:notify', source, {
        description = 'Sapling planted! The tree will grow back soon.',
        type = 'success',
    })

    return true
end

-----------------------------------------------------------
-- LOAD FELLED TREES FROM DB (on resource start)
-----------------------------------------------------------
CreateThread(function()
    local rows = MySQL.query.await('SELECT tree_key FROM forestry_felled_trees WHERE respawns_at > NOW()')
    if rows then
        for _, row in ipairs(rows) do
            FelledTrees[row.tree_key] = true
        end
    end
    lib.print.info(('[Forestry] Loaded %d felled trees into cache'):format(rows and #rows or 0))
end)

-----------------------------------------------------------
-- RESPAWN TICK (every RespawnCheckInterval ms)
-----------------------------------------------------------
CreateThread(function()
    -- Initial delay before first check
    Wait(Config.RespawnCheckInterval or 120000)

    while true do
        local respawned = MySQL.query.await(
            'SELECT tree_key FROM forestry_felled_trees WHERE respawns_at <= NOW()'
        )

        if respawned and #respawned > 0 then
            local keys = {}
            for _, row in ipairs(respawned) do
                FelledTrees[row.tree_key] = nil
                keys[#keys + 1] = row.tree_key
            end

            MySQL.update('DELETE FROM forestry_felled_trees WHERE respawns_at <= NOW()')
            TriggerClientEvent('forestry:client:treeRespawned', -1, keys)

            lib.print.info(('[Forestry] Respawned %d trees'):format(#keys))
        end

        Wait(Config.RespawnCheckInterval or 120000)
    end
end)

-----------------------------------------------------------
-- CLIENT REQUEST: Sync felled cache on join
-----------------------------------------------------------
RegisterNetEvent('forestry:server:requestFelledCache', function()
    local src = source
    TriggerClientEvent('forestry:client:syncFelledCache', src, FelledTrees)
end)

-----------------------------------------------------------
-- TIMBER WARNING RELAY
-- Client triggers this; server broadcasts to all players.
-----------------------------------------------------------
RegisterNetEvent('forestry:server:timberWarning', function(treeCoords, fallDir)
    local src = source
    -- Broadcast to all players (client filters by distance)
    TriggerClientEvent('forestry:client:timberWarning', -1, treeCoords, fallDir)
end)
