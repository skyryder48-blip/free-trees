-----------------------------------------------------------
-- SERVER: CALLBACKS
-- All lib.callback.register() definitions.
-- Server-authoritative validation for every client action.
-----------------------------------------------------------

-----------------------------------------------------------
-- PLAYER DATA
-----------------------------------------------------------
lib.callback.register('forestry:player:getData', function(source)
    local citizenid = GetCitizenId(source)
    if not citizenid then return nil end

    local cache = PlayerCache[citizenid]
    if not cache then return nil end

    return {
        forestryXP = cache.forestryXP,
        forestryLevel = cache.forestryLevel,
        woodworkingXP = cache.woodworkingXP,
        woodworkingLevel = cache.woodworkingLevel,
        licenses = cache.licenses,
        nextForestryXP = ForestryUtils.XPForLevel(cache.forestryLevel + 1),
        nextWoodworkingXP = ForestryUtils.XPForLevel(cache.woodworkingLevel + 1),
    }
end)

-----------------------------------------------------------
-- PERMIT CHECK
-----------------------------------------------------------
lib.callback.register('forestry:permit:check', function(source)
    return HasValidPermit(source)
end)

-----------------------------------------------------------
-- PERMIT PURCHASE
-----------------------------------------------------------
lib.callback.register('forestry:permit:purchase', function(source)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    local price = Config.ForestryOffice.PermitPrice

    -- Check if already has valid permit
    local existing = MySQL.single.await(
        'SELECT id FROM forestry_permits WHERE citizenid = ? AND expires_at > NOW()',
        { citizenid }
    )
    if existing then
        return false, 'already_has_permit'
    end

    -- Check money
    local cash = player.Functions.GetMoney('cash')
    if cash < price then
        return false, 'insufficient_funds'
    end

    -- Deduct money
    player.Functions.RemoveMoney('cash', price, 'timber-permit')

    -- Insert permit with expiry
    MySQL.insert(
        [[INSERT INTO forestry_permits (citizenid, expires_at)
          VALUES (?, DATE_ADD(NOW(), INTERVAL ? DAY))
          ON DUPLICATE KEY UPDATE purchased_at = NOW(), expires_at = DATE_ADD(NOW(), INTERVAL ? DAY)]],
        { citizenid, Config.ForestryOffice.PermitDurationDays, Config.ForestryOffice.PermitDurationDays }
    )

    -- Grant permit item
    exports.ox_inventory:AddItem(source, 'timber_permit', 1)

    -- Update cache
    local cache = PlayerCache[citizenid]
    if cache then
        cache.licenses.timber_permit = true
    end

    return true, nil
end)

-----------------------------------------------------------
-- FELLING: VALIDATE
-- Called before client starts felling animation.
-----------------------------------------------------------
lib.callback.register('forestry:felling:validate', function(source, treeKey, modelHash, coords, toolName)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local cache = PlayerCache[citizenid]
    if not cache then return false, 'no_cache' end

    -- 1. Check player job is lumberjack and on duty
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    local job = player.PlayerData.job
    if job.name ~= FORESTRY_JOB then
        return false, 'wrong_job'
    end
    if not job.onduty then
        return false, 'off_duty'
    end

    -- 2. Check permit
    if not HasValidPermit(source) then
        return false, 'no_permit'
    end

    -- 3. Check cooldown
    if IsFellingOnCooldown(source) then
        return false, 'cooldown'
    end

    -- 4. Check tree not already felled
    if IsTreeFelled(treeKey) then
        return false, 'already_felled'
    end

    -- 5. Get species info
    local speciesKey, speciesData = ForestryUtils.GetSpeciesFromModel(modelHash)
    if not speciesKey then
        return false, 'unknown_species'
    end

    -- 6. Validate tool
    local toolInfo, toolErr
    if toolName then
        toolInfo, toolErr = FindSpecificTool(source, toolName)
    else
        toolInfo, toolErr = FindChoppingTool(source)
    end

    if not toolInfo then
        return false, 'tool_error:' .. (toolErr or 'unknown')
    end

    -- 7. Check tool can fell this tree size
    if not ForestryUtils.CanToolFellSize(toolInfo.name, speciesData.size) then
        return false, 'wrong_tool_size'
    end

    -- 8. Distance check (anti-teleport)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local dist = #(playerCoords - vec3(coords.x, coords.y, coords.z))
    if dist > 8.0 then
        return false, 'too_far'
    end

    -- Validation passed: return tool info and species data for client
    return true, nil, {
        tool = toolInfo.name,
        species = speciesKey,
        speciesLabel = speciesData.label,
        size = speciesData.size,
        hardness = speciesData.hardness,
        baseYield = speciesData.baseYield,
        fellingTime = toolInfo.toolData.fellingTime,
        skillCheck = ForestryUtils.GetFellingSkillCheck(speciesData.size),
    }
end)

-----------------------------------------------------------
-- FELLING: COMPLETE
-- Called after client finishes felling animation + skill checks.
-----------------------------------------------------------
lib.callback.register('forestry:felling:complete', function(source, treeKey, modelHash, coords, toolName, skillCheckPassed)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false end

    local cache = PlayerCache[citizenid]
    if not cache then return false end

    -- Re-validate (prevent replay)
    if IsTreeFelled(treeKey) then return false end

    local speciesKey, speciesData = ForestryUtils.GetSpeciesFromModel(modelHash)
    if not speciesKey then return false end

    -- Find and deduct from tool
    local toolInfo = FindSpecificTool(source, toolName)
    if not toolInfo then return false end

    -- Deduct tool durability
    DeductToolDurability(source, toolInfo, 1)

    -- Deduct chainsaw fuel if applicable
    if toolName == 'chainsaw' then
        DeductChainsawFuel(source, toolInfo, 1)
    end

    -- Record felled tree
    local recorded = RecordFelledTree(treeKey, modelHash, speciesData.size)
    if not recorded then return false end

    -- Set cooldown
    SetFellingCooldown(source)

    -- Determine quality
    local quality = skillCheckPassed and LogQuality.NORMAL or LogQuality.DAMAGED

    -- Calculate yield
    local baseYield = speciesData.baseYield
    local yield = baseYield
    if not skillCheckPassed then
        yield = math.max(1, yield - 1) -- Lose 1 log on fail
    end

    -- XP
    local xpKey = 'fell_' .. speciesData.size
    local baseXP = Config.Progression.ForestryXP[xpKey] or 10
    if skillCheckPassed then
        local cleanKey = xpKey .. '_clean'
        baseXP = baseXP + (Config.Progression.ForestryXP[cleanKey] or 0)
    end
    AddForestryXP(source, baseXP)

    -- Statistics
    IncrementStat(citizenid, 'trees_felled')

    -- Roll for random events
    local eventResult = nil
    if Config.Events.Enabled then
        eventResult = RollForEvent(source, speciesData.size)
    end

    return true, {
        species = speciesKey,
        speciesLabel = speciesData.label,
        size = speciesData.size,
        quality = quality,
        yield = yield,
        xpGained = baseXP,
        event = eventResult,
    }
end)

-----------------------------------------------------------
-- PROCESSING: VALIDATE (limbing/bucking)
-----------------------------------------------------------
lib.callback.register('forestry:processing:validate', function(source, action, treeKey)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    local job = player.PlayerData.job
    if job.name ~= FORESTRY_JOB or not job.onduty then
        return false, 'not_on_duty'
    end

    -- Check player has a tool (any chopping tool works for limbing/bucking)
    local toolInfo = FindChoppingTool(source)
    if not toolInfo then
        return false, 'no_tool'
    end

    return true, nil, {
        tool = toolInfo.name,
    }
end)

-----------------------------------------------------------
-- PROCESSING: COMPLETE LIMBING
-----------------------------------------------------------
lib.callback.register('forestry:processing:completeLimb', function(source, speciesKey)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false end

    -- Grant branch bundles (2-4)
    local branchCount = math.random(2, 4)
    GrantItem(source, 'branch_bundle', branchCount)

    -- 15% resin chance for pine/redwood
    if speciesKey == 'pine' or speciesKey == 'redwood' then
        if math.random(100) <= 15 then
            GrantItem(source, 'resin_raw', 1)
            lib.notify(source, { description = 'You collected some raw resin!', type = 'success' })
        end
    end

    -- XP
    AddForestryXP(source, Config.Progression.ForestryXP.limb)

    return true, { branches = branchCount }
end)

-----------------------------------------------------------
-- PROCESSING: COMPLETE BUCKING
-----------------------------------------------------------
lib.callback.register('forestry:processing:completeBuck', function(source, speciesKey, quality, logType, count)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false end

    -- Validate log type
    local logConfig = Config.LogTypes[logType]
    if not logConfig then return false end

    -- Server determines actual count (don't trust client)
    local actualCount = math.min(count or 1, 6) -- Sanity cap

    -- Grant logs
    local success = GrantLogs(source, logType, speciesKey, quality, actualCount)
    if not success then return false end

    -- XP per cut
    AddForestryXP(source, Config.Progression.ForestryXP.buck * actualCount)

    return true, { granted = actualCount }
end)

-----------------------------------------------------------
-- SAWMILL: VALIDATE STATION USE
-----------------------------------------------------------
lib.callback.register('forestry:sawmill:validate', function(source, stationId)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local cache = PlayerCache[citizenid]
    if not cache then return false, 'no_cache' end

    -- Check level requirement
    local reqLevel = Config.SawmillStationLevels[stationId]
    if reqLevel and cache.forestryLevel < reqLevel then
        return false, 'level_too_low'
    end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    local job = player.PlayerData.job
    if job.name ~= FORESTRY_JOB or not job.onduty then
        return false, 'not_on_duty'
    end

    return true, nil, {
        forestryLevel = cache.forestryLevel,
    }
end)

-----------------------------------------------------------
-- ECONOMY: SELL ITEMS
-----------------------------------------------------------
lib.callback.register('forestry:economy:sell', function(source, channel, items)
    -- Forward to economy module when loaded
    if ProcessSale then
        return ProcessSale(source, channel, items)
    end
    return false, 'economy_not_loaded'
end)

-----------------------------------------------------------
-- ECONOMY: GET CONTRACTS
-----------------------------------------------------------
lib.callback.register('forestry:economy:getContracts', function(source)
    local contracts = MySQL.query.await(
        'SELECT * FROM forestry_contracts WHERE fulfilled = FALSE AND deadline > NOW() ORDER BY deadline ASC'
    )
    return contracts or {}
end)

-----------------------------------------------------------
-- TRANSPORT: GET LOAD DURATION
-----------------------------------------------------------
lib.callback.register('forestry:transport:getLoadDuration', function(source)
    -- Check crew members near vehicle for relay loading bonus
    local crewNearby = 1
    if GetCrewMembersNearPlayer then
        crewNearby = GetCrewMembersNearPlayer(source, Config.Transport.CrewLoadProximity)
    end

    local duration
    if crewNearby >= 3 then
        duration = Config.Transport.LoadDurationCrew3
    elseif crewNearby >= 2 then
        duration = Config.Transport.LoadDurationCrew2
    else
        duration = Config.Transport.LoadDurationPerLog
    end

    return duration
end)

-----------------------------------------------------------
-- CREW: CREATE
-----------------------------------------------------------
lib.callback.register('forestry:crew:create', function(source)
    if CreateCrew then
        return CreateCrew(source)
    end
    return false, 'crew_not_loaded'
end)

-----------------------------------------------------------
-- CREW: INVITE
-----------------------------------------------------------
lib.callback.register('forestry:crew:invite', function(source, targetSource)
    if InviteToCrew then
        return InviteToCrew(source, targetSource)
    end
    return false, 'crew_not_loaded'
end)

-----------------------------------------------------------
-- CREW: SET ROLE
-----------------------------------------------------------
lib.callback.register('forestry:crew:setRole', function(source, targetSource, role)
    if SetCrewRole then
        return SetCrewRole(source, targetSource, role)
    end
    return false, 'crew_not_loaded'
end)

-----------------------------------------------------------
-- OLD TIMER: GET MARKET DATA
-----------------------------------------------------------
lib.callback.register('forestry:oldtimer:getMarket', function(source)
    local multipliers = MySQL.query.await(
        'SELECT species, multiplier FROM forestry_export_multipliers'
    )

    local furnitureMultipliers = MySQL.query.await(
        'SELECT category, multiplier FROM forestry_furniture_export'
    )

    -- Find hottest/coldest
    local hotSpecies, coldSpecies = nil, nil
    local hotMult, coldMult = 0, 999

    if multipliers then
        for _, row in ipairs(multipliers) do
            local mult = tonumber(row.multiplier) or 1.0
            if mult > hotMult then
                hotMult = mult
                hotSpecies = row.species
            end
            if mult < coldMult then
                coldMult = mult
                coldSpecies = row.species
            end
        end
    end

    local hotCategory = nil
    local hotCatMult = 0
    if furnitureMultipliers then
        for _, row in ipairs(furnitureMultipliers) do
            local mult = tonumber(row.multiplier) or 1.0
            if mult > hotCatMult then
                hotCatMult = mult
                hotCategory = row.category
            end
        end
    end

    return {
        hotSpecies = hotSpecies,
        hotMult = hotMult,
        coldSpecies = coldSpecies,
        coldMult = coldMult,
        hotCategory = hotCategory,
        hotCatMult = hotCatMult,
        allSpecies = multipliers,
        allCategories = furnitureMultipliers,
    }
end)

-----------------------------------------------------------
-- FORESTRY OFFICE: SHOP PURCHASE
-----------------------------------------------------------
lib.callback.register('forestry:shop:purchase', function(source, itemName, qty)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    qty = math.max(1, math.min(qty or 1, 10)) -- Clamp 1-10

    -- Find item in shop config
    local shopItem = nil
    for _, entry in ipairs(Config.ForestryOffice.Shop) do
        if entry.item == itemName then
            shopItem = entry
            break
        end
    end

    if not shopItem then return false, 'item_not_in_shop' end

    -- Check cert requirement
    if shopItem.requiresCert then
        local certCount = exports.ox_inventory:Search(source, 'count', shopItem.requiresCert)
        if not certCount or certCount < 1 then
            return false, 'missing_cert'
        end
    end

    -- Check money
    local totalPrice = shopItem.price * qty
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    local cash = player.Functions.GetMoney('cash')
    if cash < totalPrice then
        return false, 'insufficient_funds'
    end

    -- Check inventory space
    local canCarry = exports.ox_inventory:CanCarryItem(source, itemName, qty)
    if not canCarry then
        return false, 'inventory_full'
    end

    -- Process purchase
    player.Functions.RemoveMoney('cash', totalPrice, 'forestry-shop-' .. itemName)
    exports.ox_inventory:AddItem(source, itemName, qty)

    return true, nil
end)
