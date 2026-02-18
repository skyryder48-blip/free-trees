-----------------------------------------------------------
-- SERVER: EVENTS
-- Random event rolling and server-side event handlers.
-- Two events: Widow Maker and Bee Swarm.
-----------------------------------------------------------

-----------------------------------------------------------
-- ROLL FOR EVENT
-- Called after successful tree fell. Returns event data
-- or nil if no event triggers.
-----------------------------------------------------------
---@param source number player server id
---@param treeSize string 'small'|'medium'|'large'
---@return table? eventData
function RollForEvent(source, treeSize)
    if not Config.Events.Enabled then return nil end

    local roll = math.random(1, Config.Events.RollChanceBase)
    local cumulative = 0

    for _, event in ipairs(Config.Events.Events) do
        if not event.enabled then goto continue end
        cumulative = cumulative + event.chance

        if roll <= cumulative then
            if event.name == 'widow_maker' then
                return RollWidowMaker(source, treeSize)
            elseif event.name == 'bee_swarm' then
                return RollBeeSwarm(source)
            end
        end

        ::continue::
    end

    return nil
end

-----------------------------------------------------------
-- WIDOW MAKER ROLL
-- Only triggers on medium/large trees.
-----------------------------------------------------------
---@param source number
---@param treeSize string
---@return table? eventData
local function RollWidowMakerInternal(source, treeSize)
    local wm = Config.Events.WidowMaker

    -- Size restriction
    local validSize = false
    for _, size in ipairs(wm.treeSizes) do
        if size == treeSize then
            validSize = true
            break
        end
    end
    if not validSize then return nil end

    return {
        name = 'widow_maker',
        skillCheck = wm.skillCheck,
        damage = wm.damage,
        staggerDuration = wm.staggerDuration,
        bonusXP = wm.bonusXP,
    }
end

-- Expose as global
function RollWidowMaker(source, treeSize)
    return RollWidowMakerInternal(source, treeSize)
end

-----------------------------------------------------------
-- BEE SWARM ROLL
-----------------------------------------------------------
---@param source number
---@return table eventData
function RollBeeSwarm(source)
    local bs = Config.Events.BeeSwarm

    -- Track active swarm server-side
    PlayerBeeSwarmActive[source] = true

    return {
        name = 'bee_swarm',
        duration = bs.duration,
        tickDamage = bs.tickDamage,
        tickInterval = bs.tickInterval,
        speedDebuff = bs.speedDebuff,
        escapeDistance = bs.escapeDistance,
    }
end

-----------------------------------------------------------
-- WIDOW MAKER: Result handler
-- Client reports dodge or hit.
-----------------------------------------------------------
RegisterNetEvent('forestry:server:widowMaker:result', function(dodged)
    local src = source

    if dodged then
        -- Award bonus XP for dodging
        if AddForestryXP then
            AddForestryXP(src, Config.Events.WidowMaker.bonusXP or 10)
        end
        if IncrementStat then
            local citizenid = GetCitizenId(src)
            if citizenid then
                IncrementStat(citizenid, 'widow_makers_dodged')
            end
        end
    end
end)

-----------------------------------------------------------
-- BEE SWARM: Escaped by distance or water
-----------------------------------------------------------
RegisterNetEvent('forestry:server:beeSwarm:escaped', function()
    local src = source
    PlayerBeeSwarmActive[src] = nil
end)

-----------------------------------------------------------
-- BEE SWARM: Duration expired
-----------------------------------------------------------
RegisterNetEvent('forestry:server:beeSwarm:ended', function()
    local src = source
    PlayerBeeSwarmActive[src] = nil
end)

-----------------------------------------------------------
-- SMOKE CANISTER: Disperse bee swarm + bonus loot
-----------------------------------------------------------
-- Registered in server/main.lua via RegisterUsableItem.
-- When used, if player has active swarm:
function HandleSmokeCanisters(source)
    if not PlayerBeeSwarmActive[source] then return false end

    PlayerBeeSwarmActive[source] = nil

    -- Disperse on client
    TriggerClientEvent('forestry:client:beeSwarm:disperse', source)

    -- Bonus honeycomb drop
    local bs = Config.Events.BeeSwarm
    local bonusQty = math.random(bs.bonusAmount[1], bs.bonusAmount[2])
    if GrantItem then
        GrantItem(source, bs.bonusItem, bonusQty)
    end

    return true
end
