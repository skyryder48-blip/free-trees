-----------------------------------------------------------
-- CONFIG: SERVER
-- Server-side configuration values.
-- Loaded before server/*.lua via fxmanifest.
-----------------------------------------------------------

-----------------------------------------------------------
-- RANDOM EVENTS
-----------------------------------------------------------
Config.Events = {
    Enabled = true,
    RollChanceBase = 1000,
    Events = {
        { name = 'widow_maker', enabled = true, chance = 100 }, -- 10%
        { name = 'bee_swarm',   enabled = true, chance = 65 },  -- 6.5%
    },
}

Config.Events.WidowMaker = {
    enabled = true,
    chance = 100,
    treeSizes = { 'medium', 'large' },
    skillCheck = { 'hard' },
    damage = { min = 40, max = 65 },
    bonusXP = 10,
    staggerDuration = 1500,
}

Config.Events.BeeSwarm = {
    enabled = true,
    chance = 65,
    duration = 20000,
    tickDamage = 2,
    tickInterval = 3000,
    speedDebuff = 0.8,
    escapeDistance = 30.0,
    smokeItem = 'smoke_canister',
    bonusItem = 'honeycomb',
    bonusAmount = { 1, 3 },
}

-----------------------------------------------------------
-- TREE RESPAWN
-----------------------------------------------------------
Config.RespawnCheckInterval = 120000

-----------------------------------------------------------
-- CREW (server-side keys)
-----------------------------------------------------------
Config.Crew = Config.Crew or {}
Config.Crew.MaxMembers = 8
Config.Crew.XPBonusPerMember = 0.10
Config.Crew.XPBonusCap = 0.40
Config.Crew.ActivityWindow = 300000
Config.Crew.SharedStashSlots = 50
Config.Crew.SharedStashWeight = 200000
Config.Crew.StashCleanupDelay = 1800000

-----------------------------------------------------------
-- FORESTRY OFFICE (server-side: shop, permit pricing)
-----------------------------------------------------------
Config.ForestryOffice = Config.ForestryOffice or {}
Config.ForestryOffice.PermitPrice = 500
Config.ForestryOffice.PermitDurationDays = 7
Config.ForestryOffice.Shop = {
    { item = 'hatchet',          price = 150 },
    { item = 'felling_axe',     price = 400 },
    { item = 'crosscut_saw',    price = 600,  requiresCert = 'crosscut_cert' },
    { item = 'chainsaw',        price = 1200, requiresCert = 'chainsaw_cert' },
    { item = 'chainsaw_fuel',   price = 50 },
    { item = 'sharpening_kit',  price = 75 },
    { item = 'portable_sawmill', price = 3500 },
    { item = 'tree_sapling',    price = 25 },
    { item = 'smoke_canister',  price = 30 },
    { item = 'log_chute_kit',   price = 2000 },
    { item = 'wood_finish',     price = 100 },
    { item = 'clock_mechanism', price = 500 },
}

-----------------------------------------------------------
-- GENERAL STORE (byproduct sale prices)
-----------------------------------------------------------
Config.GeneralStore = {
    Items = {
        branch_bundle  = 20,
        firewood_bundle = 40,
        sawdust        = 5,
        wood_chips     = 8,
        wood_pellets   = 25,
        bark_mulch     = 30,
        honeycomb      = 45,
    },
}

-----------------------------------------------------------
-- LUMBER BUYER
-----------------------------------------------------------
Config.LumberBuyer = Config.LumberBuyer or {}
Config.LumberBuyer.BasePrices = {
    lumber_rough    = 30,
    lumber_edged    = 50,
    lumber_finished = 80,
    veneer_sheet    = 60,
    plywood_sheet   = 120,
    specialty_cut   = 150,
    turpentine      = 60,
}

-----------------------------------------------------------
-- FURNITURE BUYER
-----------------------------------------------------------
Config.FurnitureBuyer = Config.FurnitureBuyer or {}

-----------------------------------------------------------
-- CONTRACTS
-----------------------------------------------------------
Config.Contracts = {
    MaxActive = 8,
    GenerationInterval = 1800000,
    PremiumMultiplier = { min = 1.3, max = 2.0 },
    DeadlineHours = { min = 24, max = 72 },
    PossibleItems = {
        'lumber_finished',
        'plywood_sheet',
        'veneer_sheet',
        'specialty_cut',
        'firewood_bundle',
    },
    QuantityRange = { min = 5, max = 30 },
}

-----------------------------------------------------------
-- EXPORT DOCKS
-----------------------------------------------------------
Config.LumberExport = Config.LumberExport or {}
Config.LumberExport.RotationIntervalHours = 168
Config.LumberExport.MultiplierRange = { min = 0.7, max = 2.5 }

Config.FurnitureExport = Config.FurnitureExport or {}
Config.FurnitureExport.RotationIntervalHours = 168
Config.FurnitureExport.Categories = {
    seating = {
        items = { 'furniture_chair_oak', 'furniture_stool', 'furniture_bench_cedar' },
        multiplierRange = { min = 1.0, max = 2.0 },
    },
    tables = {
        items = { 'furniture_table_oak', 'furniture_desk_maple', 'furniture_sidetable_birch', 'furniture_nightstand_maple' },
        multiplierRange = { min = 1.0, max = 2.2 },
    },
    storage = {
        items = { 'furniture_chest_cedar', 'furniture_cabinet_birch', 'furniture_wardrobe_pine', 'furniture_shelf_pine' },
        multiplierRange = { min = 0.8, max = 1.8 },
    },
    specialty = {
        items = { 'furniture_trophy_redwood', 'furniture_clock_oak' },
        multiplierRange = { min = 1.5, max = 3.0 },
    },
    utility = {
        items = { 'furniture_crate', 'furniture_fence_panels' },
        multiplierRange = { min = 0.8, max = 1.5 },
    },
}

-----------------------------------------------------------
-- MARKET DYNAMICS
-----------------------------------------------------------
Config.Market = {
    SupplyDecayPerHour = 5,
    SupplyPerSale = 1,
    PriceFloor = 0.5,
    PriceCeiling = 1.5,
}

-----------------------------------------------------------
-- SAWMILLS (server-side: station definitions for validation)
-----------------------------------------------------------
Config.Sawmills = {
    {
        id = 'paleto_sawmill',
        label = 'Paleto Community Sawmill',
        tier = 2,
        stations = {
            { id = 'debarker',         levelReq = 0 },
            { id = 'headsaw',          levelReq = 5 },
            { id = 'edger',            levelReq = 5 },
            { id = 'planer',           levelReq = 10 },
            { id = 'crosscut_station', levelReq = 5 },
            { id = 'veneer',           levelReq = 20 },
            { id = 'plywood',          levelReq = 25 },
            { id = 'specialty',        levelReq = 30 },
        },
        throughputBonus = 0.15,
        throughputBonusCap = 0.60,
    },
}

-----------------------------------------------------------
-- TRANSPORT
-----------------------------------------------------------
Config.Transport = {
    LoadDurationPerLog = 4000,
    LoadDurationCrew2 = 2500,
    LoadDurationCrew3 = 1500,
    CrewLoadProximity = 5.0,
}

-----------------------------------------------------------
-- LOG CHUTES (server-side)
-----------------------------------------------------------
Config.LogChutes = {
    {
        id = 'paleto_chute_north',
        sendPoint = vec3(-800.0, 5500.0, 90.0),
        collectionPoint = vec3(-780.0, 5420.0, 38.0),
        slideTime = 8000,
        maxLogsPerSend = 3,
    },
}

-----------------------------------------------------------
-- FURNITURE RECIPES
-----------------------------------------------------------
Config.FurnitureRecipes = {
    { item = 'furniture_crate',            level = 0,  ingredients = { lumber_rough = 4 },                                     price = 150 },
    { item = 'furniture_fence_panels',     level = 0,  ingredients = { lumber_finished = 6 },                                  price = 400 },
    { item = 'furniture_stool',            level = 5,  ingredients = { lumber_finished = 2, wood_finish = 1 },                 price = 250 },
    { item = 'furniture_shelf_pine',       level = 5,  ingredients = { lumber_finished = 4, wood_finish = 1 },                 species = 'pine',    price = 600 },
    { item = 'furniture_chair_oak',        level = 10, ingredients = { lumber_finished = 3, wood_finish = 1 },                 species = 'oak',     price = 500 },
    { item = 'furniture_chest_cedar',      level = 10, ingredients = { lumber_finished = 5, wood_finish = 2 },                 species = 'cedar',   price = 900 },
    { item = 'furniture_sidetable_birch',  level = 10, ingredients = { lumber_finished = 2, wood_finish = 1 },                 species = 'birch',   price = 450 },
    { item = 'furniture_table_oak',        level = 15, ingredients = { lumber_finished = 6, wood_finish = 2 },                 species = 'oak',     price = 1200 },
    { item = 'furniture_wardrobe_pine',    level = 15, ingredients = { lumber_finished = 6, wood_finish = 2 },                 species = 'pine',    price = 850 },
    { item = 'furniture_nightstand_maple', level = 15, ingredients = { lumber_finished = 3, wood_finish = 1 },                 species = 'maple',   price = 700 },
    { item = 'furniture_desk_maple',       level = 20, ingredients = { lumber_finished = 8, wood_finish = 3 },                 species = 'maple',   price = 1800 },
    { item = 'furniture_cabinet_birch',    level = 20, ingredients = { lumber_finished = 5, veneer_sheet = 2 },                species = 'birch',   price = 1100 },
    { item = 'furniture_bench_cedar',      level = 20, ingredients = { lumber_finished = 4, wood_finish = 1 },                 species = 'cedar',   price = 750 },
    { item = 'furniture_trophy_redwood',   level = 25, ingredients = { lumber_finished = 4, specialty_cut = 1 },               species = 'redwood', price = 2500 },
    { item = 'furniture_clock_oak',        level = 25, ingredients = { lumber_finished = 6, specialty_cut = 2, clock_mechanism = 1 }, species = 'oak', price = 3500 },
}

-----------------------------------------------------------
-- WOODWORKING BONUSES (level-gated)
-----------------------------------------------------------
Config.WoodworkingBonuses = {
    [8]  = { craftTimeReduction = 0.10 },
    [14] = { materialSaveChance = 0.05 },
    [20] = { craftTimeReduction = 0.10 },
    [26] = { materialSaveChance = 0.10 },
    [30] = { masterLabel = true },
}

-----------------------------------------------------------
-- BULLETIN BOARD
-----------------------------------------------------------
Config.BulletinBoard = {
    RefreshInterval = 1800000,
}

-----------------------------------------------------------
-- LOGGING (optional Discord webhooks)
-----------------------------------------------------------
Config.Logging = {
    Enabled = false,
    WebhookURL = '',
    Events = {
        largeSale = true,
        contractComplete = true,
        exportSale = true,
        levelUp = true,
    },
    LargeSaleThreshold = 5000,
}

-----------------------------------------------------------
-- FOOD ITEMS (recognized for stamina recovery context)
-----------------------------------------------------------
Config.FoodItems = {
    sandwich = true,
    burger = true,
    water = true,
    coffee = true,
    energy_bar = true,
}
