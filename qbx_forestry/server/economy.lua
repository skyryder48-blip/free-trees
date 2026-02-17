-----------------------------------------------------------
-- SERVER: ECONOMY & SALES
-- Seven sale channels, contract generation, market dynamics,
-- weekly export dock rotations, NPC shop interactions.
-----------------------------------------------------------

-----------------------------------------------------------
-- MARKET DYNAMICS
-- Supply/demand affects Lumber Buyer prices.
-- Supply decays 5/hour. Each sale increases supply by 1.
-- Price floor 50%, ceiling 150% of base.
-----------------------------------------------------------

--- Calculate current market price for an item.
---@param itemName string
---@return integer price
local function GetMarketPrice(itemName)
    local row = MySQL.single.await(
        'SELECT base_price, current_price, supply, demand FROM forestry_market WHERE item_name = ?',
        { itemName }
    )

    if not row then
        local basePrices = Config.LumberBuyer.BasePrices
        return basePrices[itemName] or 0
    end

    return row.current_price
end

--- Update market after a sale (increase supply, recalc price).
---@param itemName string
---@param quantity integer
local function UpdateMarketAfterSale(itemName, quantity)
    MySQL.update([[
        UPDATE forestry_market
        SET supply = supply + ?,
            current_price = GREATEST(
                FLOOR(base_price * ?),
                LEAST(
                    FLOOR(base_price * ?),
                    FLOOR(base_price * (1.0 - (supply + ?) / (demand + supply + ? + 100) * 0.5))
                )
            ),
            last_updated = NOW()
        WHERE item_name = ?
    ]], {
        quantity * Config.Market.SupplyPerSale,
        Config.Market.PriceFloor,
        Config.Market.PriceCeiling,
        quantity,
        quantity,
        itemName,
    })
end

--- Supply decay thread (every hour).
CreateThread(function()
    Wait(10000)
    while true do
        Wait(3600000) -- 1 hour

        MySQL.update([[
            UPDATE forestry_market
            SET supply = GREATEST(0, supply - ?),
                current_price = GREATEST(
                    FLOOR(base_price * ?),
                    LEAST(
                        FLOOR(base_price * ?),
                        FLOOR(base_price * (1.0 - GREATEST(0, supply - ?) / (demand + GREATEST(0, supply - ?) + 100) * 0.5))
                    )
                ),
                last_updated = NOW()
        ]], {
            Config.Market.SupplyDecayPerHour,
            Config.Market.PriceFloor,
            Config.Market.PriceCeiling,
            Config.Market.SupplyDecayPerHour,
            Config.Market.SupplyDecayPerHour,
        })
    end
end)

-----------------------------------------------------------
-- PROCESS SALE (universal handler)
-----------------------------------------------------------
---@param source number
---@param channel string 'general_store'|'lumber_buyer'|'furniture_buyer'|'lumber_export'|'furniture_export'|'contract'
---@param items table { itemName: string, quantity: integer }[] or single item data
---@return boolean success
---@return string|integer? error_or_total
function ProcessSale(source, channel, items)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then return false, 'no_player' end

    -- Validate job/duty for most channels
    local job = player.PlayerData.job
    if job.name ~= FORESTRY_JOB or not job.onduty then
        return false, 'not_on_duty'
    end

    local totalEarned = 0

    if channel == 'general_store' then
        totalEarned = ProcessGeneralStoreSale(source, items)
    elseif channel == 'lumber_buyer' then
        totalEarned = ProcessLumberBuyerSale(source, items)
    elseif channel == 'furniture_buyer' then
        totalEarned = ProcessFurnitureBuyerSale(source, items)
    elseif channel == 'lumber_export' then
        totalEarned = ProcessLumberExportSale(source, items)
    elseif channel == 'furniture_export' then
        totalEarned = ProcessFurnitureExportSale(source, items)
    elseif channel == 'contract' then
        return ProcessContractFulfillment(source, items)
    else
        return false, 'invalid_channel'
    end

    if totalEarned <= 0 then
        return false, 'nothing_sold'
    end

    -- Pay the player
    player.Functions.AddMoney('cash', totalEarned, 'forestry-sale-' .. channel)

    -- Track statistics
    IncrementStat(citizenid, 'total_earned', totalEarned)

    -- Log large sales
    if Config.Logging.Enabled and totalEarned >= (Config.Logging.LargeSaleThreshold or 5000) then
        ForestryLog('largeSale', 'Large Sale',
            ('**Player:** %s\n**Channel:** %s\n**Total:** $%d'):format(citizenid, channel, totalEarned),
            15844367
        )
    end

    return true, totalEarned
end

-----------------------------------------------------------
-- GENERAL STORE (fixed prices, byproducts only)
-----------------------------------------------------------
function ProcessGeneralStoreSale(source, items)
    local total = 0
    local storeItems = Config.GeneralStore.Items

    for _, entry in ipairs(items) do
        local price = storeItems[entry.item]
        if not price then goto continue end

        local count = exports.ox_inventory:Search(source, 'count', entry.item)
        local sellQty = math.min(entry.quantity or 1, count or 0)
        if sellQty <= 0 then goto continue end

        exports.ox_inventory:RemoveItem(source, entry.item, sellQty)
        total = total + (price * sellQty)

        ::continue::
    end

    return total
end

-----------------------------------------------------------
-- LUMBER BUYER NPC (market-modified prices)
-----------------------------------------------------------
function ProcessLumberBuyerSale(source, items)
    local total = 0

    for _, entry in ipairs(items) do
        if not Config.LumberBuyer.BasePrices[entry.item] then goto continue end

        local count = exports.ox_inventory:Search(source, 'count', entry.item)
        local sellQty = math.min(entry.quantity or 1, count or 0)
        if sellQty <= 0 then goto continue end

        local price = GetMarketPrice(entry.item)

        -- Check metadata for damaged quality
        local slots = exports.ox_inventory:Search(source, 'slots', entry.item)
        local damageCount = 0
        local normalCount = 0
        local removed = 0

        for _, slot in ipairs(slots or {}) do
            if removed >= sellQty then break end
            local qty = math.min(slot.count, sellQty - removed)
            local meta = slot.metadata or {}
            if meta.quality == LogQuality.DAMAGED then
                damageCount = damageCount + qty
            else
                normalCount = normalCount + qty
            end
            removed = removed + qty
        end

        exports.ox_inventory:RemoveItem(source, entry.item, sellQty)

        local normalValue = normalCount * price
        local damagedValue = math.floor(damageCount * price * Config.DamagedValueMultiplier)
        total = total + normalValue + damagedValue

        -- Update market
        UpdateMarketAfterSale(entry.item, sellQty)

        local citizenid = GetCitizenId(source)
        if citizenid then
            IncrementStat(citizenid, 'lumber_produced', sellQty)
        end

        ::continue::
    end

    return total
end

-----------------------------------------------------------
-- FURNITURE BUYER NPC (base prices from recipe config)
-----------------------------------------------------------
function ProcessFurnitureBuyerSale(source, items)
    local total = 0

    -- Build price lookup from recipes
    local prices = {}
    for _, recipe in ipairs(Config.FurnitureRecipes) do
        prices[recipe.item] = recipe.price
    end

    for _, entry in ipairs(items) do
        local price = prices[entry.item]
        if not price then goto continue end

        local count = exports.ox_inventory:Search(source, 'count', entry.item)
        local sellQty = math.min(entry.quantity or 1, count or 0)
        if sellQty <= 0 then goto continue end

        exports.ox_inventory:RemoveItem(source, entry.item, sellQty)
        total = total + (price * sellQty)

        local citizenid = GetCitizenId(source)
        if citizenid then
            IncrementStat(citizenid, 'furniture_crafted', sellQty)
        end

        ::continue::
    end

    return total
end

-----------------------------------------------------------
-- LUMBER EXPORT DOCK (weekly species multipliers)
-----------------------------------------------------------
function ProcessLumberExportSale(source, items)
    local total = 0

    -- Get current multipliers
    local multipliers = {}
    local rows = MySQL.query.await(
        'SELECT species, multiplier FROM forestry_export_multipliers'
    )
    if rows then
        for _, row in ipairs(rows) do
            multipliers[row.species] = tonumber(row.multiplier) or 1.0
        end
    end

    for _, entry in ipairs(items) do
        if not Config.LumberBuyer.BasePrices[entry.item] then goto continue end

        local slots = exports.ox_inventory:Search(source, 'slots', entry.item)
        if not slots or #slots == 0 then goto continue end

        local sellQty = math.min(entry.quantity or 1, 0)
        -- Count available
        for _, slot in ipairs(slots) do
            sellQty = sellQty + slot.count
        end
        sellQty = math.min(entry.quantity or sellQty, sellQty)
        if sellQty <= 0 then goto continue end

        local basePrice = GetMarketPrice(entry.item)
        local removed = 0

        for _, slot in ipairs(slots) do
            if removed >= sellQty then break end
            local qty = math.min(slot.count, sellQty - removed)
            local meta = slot.metadata or {}
            local species = meta.species or 'pine'
            local mult = multipliers[species] or 1.0
            local quality = meta.quality or LogQuality.NORMAL
            local qualityMult = quality == LogQuality.DAMAGED and Config.DamagedValueMultiplier or 1.0

            total = total + math.floor(basePrice * mult * qualityMult * qty)
            removed = removed + qty
        end

        exports.ox_inventory:RemoveItem(source, entry.item, sellQty)
        UpdateMarketAfterSale(entry.item, sellQty)

        ::continue::
    end

    -- Bonus XP for export run
    if total > 0 then
        AddForestryXP(source, Config.Progression.ForestryXP.export_complete or 75)
    end

    return total
end

-----------------------------------------------------------
-- FURNITURE EXPORT DOCK (weekly category multipliers)
-----------------------------------------------------------
function ProcessFurnitureExportSale(source, items)
    local total = 0

    -- Get category multipliers
    local catMultipliers = {}
    local rows = MySQL.query.await(
        'SELECT category, multiplier FROM forestry_furniture_export'
    )
    if rows then
        for _, row in ipairs(rows) do
            catMultipliers[row.category] = tonumber(row.multiplier) or 1.0
        end
    end

    -- Build reverse lookup: item -> category
    local itemCategory = {}
    for catName, catData in pairs(Config.FurnitureExport.Categories) do
        for _, itemName in ipairs(catData.items) do
            itemCategory[itemName] = catName
        end
    end

    -- Build price lookup
    local prices = {}
    for _, recipe in ipairs(Config.FurnitureRecipes) do
        prices[recipe.item] = recipe.price
    end

    for _, entry in ipairs(items) do
        local basePrice = prices[entry.item]
        if not basePrice then goto continue end

        local category = itemCategory[entry.item]
        local mult = category and catMultipliers[category] or 1.0

        local count = exports.ox_inventory:Search(source, 'count', entry.item)
        local sellQty = math.min(entry.quantity or 1, count or 0)
        if sellQty <= 0 then goto continue end

        exports.ox_inventory:RemoveItem(source, entry.item, sellQty)
        total = total + math.floor(basePrice * mult * sellQty)

        ::continue::
    end

    -- Bonus XP for furniture export
    if total > 0 then
        AddForestryXP(source, Config.Progression.ForestryXP.export_complete or 75)
    end

    return total
end

-----------------------------------------------------------
-- CONTRACT FULFILLMENT
-----------------------------------------------------------
function ProcessContractFulfillment(source, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return false, 'not_loaded' end

    local contractId = data.contractId
    if not contractId then return false, 'no_contract_id' end

    local contract = MySQL.single.await(
        'SELECT * FROM forestry_contracts WHERE id = ? AND fulfilled = FALSE AND deadline > NOW()',
        { contractId }
    )

    if not contract then return false, 'contract_not_found' end

    -- Check player has the items
    local remaining = contract.quantity - contract.quantity_filled
    local count = exports.ox_inventory:Search(source, 'count', contract.item_name)
    local deliverQty = math.min(remaining, count or 0)

    if deliverQty <= 0 then return false, 'no_items' end

    -- Species match check if contract requires it
    if contract.species then
        local slots = exports.ox_inventory:Search(source, 'slots', contract.item_name)
        local matchCount = 0
        for _, slot in ipairs(slots or {}) do
            local meta = slot.metadata or {}
            if meta.species == contract.species then
                matchCount = matchCount + slot.count
            end
        end
        deliverQty = math.min(deliverQty, matchCount)
        if deliverQty <= 0 then return false, 'wrong_species' end
    end

    -- Remove items
    exports.ox_inventory:RemoveItem(source, contract.item_name, deliverQty)

    -- Update contract
    local newFilled = contract.quantity_filled + deliverQty
    local fulfilled = newFilled >= contract.quantity

    MySQL.update(
        'UPDATE forestry_contracts SET quantity_filled = ?, fulfilled = ?, fulfilled_by = ? WHERE id = ?',
        { newFilled, fulfilled, fulfilled and citizenid or nil, contractId }
    )

    -- Pay
    local totalPay = deliverQty * contract.price_per_unit
    local player = exports.qbx_core:GetPlayer(source)
    if player then
        player.Functions.AddMoney('cash', totalPay, 'forestry-contract-' .. contractId)
    end

    IncrementStat(citizenid, 'total_earned', totalPay)

    if fulfilled then
        IncrementStat(citizenid, 'contracts_completed')
        AddForestryXP(source, Config.Progression.ForestryXP.contract_complete or 50)

        if Config.Logging.Enabled then
            ForestryLog('contractComplete', 'Contract Completed',
                ('**Player:** %s\n**Item:** %s x%d\n**Payout:** $%d'):format(
                    citizenid, contract.item_name, contract.quantity, totalPay
                )
            )
        end
    end

    return true, totalPay
end

-----------------------------------------------------------
-- CONTRACT GENERATION THREAD (every 30 minutes)
-----------------------------------------------------------
CreateThread(function()
    Wait(15000)
    while true do
        GenerateContracts()
        Wait(Config.Contracts.GenerationInterval)
    end
end)

function GenerateContracts()
    -- Count active unfulfilled contracts
    local active = MySQL.scalar.await(
        'SELECT COUNT(*) FROM forestry_contracts WHERE fulfilled = FALSE AND deadline > NOW()'
    ) or 0

    local toGenerate = Config.Contracts.MaxActive - active
    if toGenerate <= 0 then return end

    -- Generate 1-3 at a time
    toGenerate = math.min(toGenerate, math.random(1, 3))

    for _ = 1, toGenerate do
        local itemIndex = math.random(1, #Config.Contracts.PossibleItems)
        local itemName = Config.Contracts.PossibleItems[itemIndex]
        local quantity = math.random(Config.Contracts.QuantityRange.min, Config.Contracts.QuantityRange.max)
        local deadlineHours = math.random(Config.Contracts.DeadlineHours.min, Config.Contracts.DeadlineHours.max)

        -- Base price from lumber buyer or furniture recipes
        local basePrice = Config.LumberBuyer.BasePrices[itemName]
        if not basePrice then
            for _, recipe in ipairs(Config.FurnitureRecipes) do
                if recipe.item == itemName then
                    basePrice = recipe.price
                    break
                end
            end
        end
        basePrice = basePrice or 50

        local multiplier = Config.Contracts.PremiumMultiplier.min +
            math.random() * (Config.Contracts.PremiumMultiplier.max - Config.Contracts.PremiumMultiplier.min)
        local pricePerUnit = math.floor(basePrice * multiplier)

        -- Random species requirement (30% chance)
        local species = nil
        if math.random(100) <= 30 then
            local speciesList = {}
            for key in pairs(Config.TreeSpecies) do
                speciesList[#speciesList + 1] = key
            end
            species = speciesList[math.random(#speciesList)]
        end

        MySQL.insert(
            [[INSERT INTO forestry_contracts (item_name, species, quantity, price_per_unit, deadline)
              VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR))]],
            { itemName, species, quantity, pricePerUnit, deadlineHours }
        )
    end
end

-----------------------------------------------------------
-- EXPORT DOCK ROTATION (weekly)
-----------------------------------------------------------
CreateThread(function()
    Wait(20000)
    while true do
        CheckExportRotation()
        Wait(3600000) -- Check every hour
    end
end)

function CheckExportRotation()
    -- Lumber species rotation
    local oldest = MySQL.scalar.await(
        'SELECT MIN(rotated_at) FROM forestry_export_multipliers'
    )

    if oldest then
        local hoursAge = MySQL.scalar.await(
            'SELECT TIMESTAMPDIFF(HOUR, ?, NOW())',
            { oldest }
        )

        if hoursAge and hoursAge >= Config.LumberExport.RotationIntervalHours then
            RotateLumberExport()
        end
    end

    -- Furniture category rotation
    local fOldest = MySQL.scalar.await(
        'SELECT MIN(rotated_at) FROM forestry_furniture_export'
    )

    if fOldest then
        local fHoursAge = MySQL.scalar.await(
            'SELECT TIMESTAMPDIFF(HOUR, ?, NOW())',
            { fOldest }
        )

        if fHoursAge and fHoursAge >= Config.FurnitureExport.RotationIntervalHours then
            RotateFurnitureExport()
        end
    end
end

function RotateLumberExport()
    local minMult = Config.LumberExport.MultiplierRange.min
    local maxMult = Config.LumberExport.MultiplierRange.max

    for speciesKey in pairs(Config.TreeSpecies) do
        local mult = minMult + math.random() * (maxMult - minMult)
        mult = math.floor(mult * 10) / 10 -- Round to 1 decimal

        MySQL.update(
            'UPDATE forestry_export_multipliers SET multiplier = ?, rotated_at = NOW() WHERE species = ?',
            { mult, speciesKey }
        )
    end

    lib.print.info('[Forestry] Lumber export multipliers rotated')
end

function RotateFurnitureExport()
    for catName, catData in pairs(Config.FurnitureExport.Categories) do
        local minMult = catData.multiplierRange.min
        local maxMult = catData.multiplierRange.max
        local mult = minMult + math.random() * (maxMult - minMult)
        mult = math.floor(mult * 10) / 10

        MySQL.update(
            'UPDATE forestry_furniture_export SET multiplier = ?, rotated_at = NOW() WHERE category = ?',
            { mult, catName }
        )
    end

    lib.print.info('[Forestry] Furniture export multipliers rotated')
end

-----------------------------------------------------------
-- GET SELL OPTIONS (for client UI)
-----------------------------------------------------------
lib.callback.register('forestry:economy:getSellOptions', function(source, channel)
    if channel == 'general_store' then
        return Config.GeneralStore.Items
    elseif channel == 'lumber_buyer' then
        local prices = {}
        for item, base in pairs(Config.LumberBuyer.BasePrices) do
            prices[item] = GetMarketPrice(item)
        end
        return prices
    elseif channel == 'lumber_export' then
        local multipliers = {}
        local rows = MySQL.query.await('SELECT species, multiplier FROM forestry_export_multipliers')
        if rows then
            for _, row in ipairs(rows) do
                multipliers[row.species] = tonumber(row.multiplier) or 1.0
            end
        end
        return { basePrices = Config.LumberBuyer.BasePrices, multipliers = multipliers }
    elseif channel == 'furniture_export' then
        local catMults = {}
        local rows = MySQL.query.await('SELECT category, multiplier FROM forestry_furniture_export')
        if rows then
            for _, row in ipairs(rows) do
                catMults[row.category] = tonumber(row.multiplier) or 1.0
            end
        end
        return catMults
    end
    return nil
end)

-----------------------------------------------------------
-- BULLETIN BOARD DATA
-----------------------------------------------------------
lib.callback.register('forestry:bulletin:getData', function(source)
    -- Export multipliers
    local lumberMults = MySQL.query.await('SELECT species, multiplier FROM forestry_export_multipliers')
    local furnitureMults = MySQL.query.await('SELECT category, multiplier FROM forestry_furniture_export')

    -- Community stats (this week)
    local stats = MySQL.single.await([[
        SELECT
            COALESCE(SUM(JSON_EXTRACT(statistics, '$.trees_felled')), 0) AS total_felled,
            COALESCE(SUM(JSON_EXTRACT(statistics, '$.total_earned')), 0) AS total_earned
        FROM forestry_players
        WHERE updated_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]])

    return {
        lumberMultipliers = lumberMults or {},
        furnitureMultipliers = furnitureMults or {},
        treesThisWeek = stats and tonumber(stats.total_felled) or 0,
        earnedThisWeek = stats and tonumber(stats.total_earned) or 0,
    }
end)
