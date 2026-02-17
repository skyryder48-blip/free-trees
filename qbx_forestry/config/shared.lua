Config = {}

-----------------------------------------------------------
-- TREE SPECIES
-- Models mapped to species. size/hardness/yield/value define behaviour.
-- Model hashes use backtick syntax (compiled at load by Lua 5.4).
-----------------------------------------------------------
Config.TreeSpecies = {
    pine = {
        label = 'Pine',
        models = {
            `prop_tree_pine_01`, `prop_tree_pine_02`,
            `prop_tree_cedar_01`, `prop_tree_cedar_02`,
            `prop_tree_cedar_03`, `prop_tree_cedar_04`,
        },
        size = 'large',
        hardness = 0.4,
        baseYield = 4,
        baseValue = 50,
    },
    oak = {
        label = 'Oak',
        models = {
            `prop_tree_oak_01`, `prop_tree_eng_oak_01`,
        },
        size = 'medium',
        hardness = 0.8,
        baseYield = 3,
        baseValue = 120,
    },
    birch = {
        label = 'Birch',
        models = {
            `prop_tree_birch_01`, `prop_tree_birch_02`,
            `prop_tree_birch_03`, `prop_tree_birch_04`,
        },
        size = 'small',
        hardness = 0.3,
        baseYield = 2,
        baseValue = 40,
    },
    redwood = {
        label = 'Redwood',
        models = {
            `prop_tree_log_01`, `prop_s_pine_dead_01`,
        },
        size = 'large',
        hardness = 0.6,
        baseYield = 6,
        baseValue = 200,
    },
    cedar = {
        label = 'Cedar',
        models = {
            `prop_tree_cedar_s_01`, `prop_tree_cedar_s_04`,
        },
        size = 'medium',
        hardness = 0.5,
        baseYield = 3,
        baseValue = 90,
    },
    maple = {
        label = 'Maple',
        models = {
            `prop_tree_maple_02`, `prop_tree_maple_03`,
        },
        size = 'medium',
        hardness = 0.9,
        baseYield = 3,
        baseValue = 130,
    },
}

-----------------------------------------------------------
-- MODEL â†’ SPECIES REVERSE LOOKUP
-- Built at load time from Config.TreeSpecies.
-----------------------------------------------------------
Config.ModelToSpecies = {}
for species, data in pairs(Config.TreeSpecies) do
    for _, model in ipairs(data.models) do
        Config.ModelToSpecies[model] = species
    end
end

-----------------------------------------------------------
-- TREE SIZES
-----------------------------------------------------------
Config.TreeSizes = {
    small  = { label = 'Small',  respawnMinutes = 60 },
    medium = { label = 'Medium', respawnMinutes = 120 },
    large  = { label = 'Large',  respawnMinutes = 240 },
}

-----------------------------------------------------------
-- TOOLS
-- treeSizes: which tree sizes this tool can fell.
-- fellingTime: base duration in ms for the felling progress.
-----------------------------------------------------------
Config.Tools = {
    hatchet = {
        treeSizes = { small = true },
        maxDurability = 50,
        fellingTime = 12000,
        levelReq = 0,
    },
    felling_axe = {
        treeSizes = { small = true, medium = true },
        maxDurability = 80,
        fellingTime = 18000,
        levelReq = 3,
    },
    crosscut_saw = {
        treeSizes = { small = true, medium = true, large = true },
        maxDurability = 60,
        fellingTime = 18000,
        levelReq = 14,
        requiresCert = 'crosscut_cert',
        requiresPartner = true,
    },
    chainsaw = {
        treeSizes = { small = true, medium = true, large = true },
        maxDurability = 100,
        fellingTime = 10000,
        levelReq = 7,
        requiresCert = 'chainsaw_cert',
        fuelPerUse = 1,
    },
    -- Global tool constants
    FuelPerCanister = 5,
    MaxFuel = 25,
    SharpenAmount = 50,
}

-- Quick lookup: is this item name a chopping tool?
Config.ChoppingTools = {
    hatchet = true,
    felling_axe = true,
    crosscut_saw = true,
    chainsaw = true,
}

-----------------------------------------------------------
-- SKILL CHECKS
-- Arrays of difficulty strings passed to lib.skillCheck().
-- An empty table {} means no skill check (progress bar only).
-----------------------------------------------------------
Config.SkillCheck = {
    -- Felling by tree size
    small  = { 'easy', 'easy' },
    medium = { 'easy', 'medium', 'easy' },
    large  = { 'medium', 'medium', 'hard' },

    -- Crosscut saw (per round, 3 rounds per player)
    crosscut = { 'easy', 'medium' },
    crosscutRounds = 3,

    -- Sawmill stations
    debarker = {},
    headsaw = { 'medium' },
    edger = { 'easy' },
    planer = { 'easy' },
    crosscut_station = { 'easy' },
    veneer = { 'hard' },
    plywood = { 'medium' },
    specialty = { 'hard' },

    -- Skill check input keys
    inputs = { 'w', 'a', 's', 'd' },
}

-----------------------------------------------------------
-- PROGRESSION
-----------------------------------------------------------
Config.Progression = {
    XPFormula = 1.5,       -- exponent in: 100 * level^1.5
    XPPerLevel = 100,      -- base multiplier
    MaxForestryLevel = 50,
    MaxWoodworkingLevel = 30,
    FlushInterval = 60000, -- ms between batched XP writes

    ForestryXP = {
        fell_small = 10,   fell_small_clean = 5,
        fell_medium = 25,  fell_medium_clean = 10,
        fell_large = 50,   fell_large_clean = 20,
        limb = 5,
        buck = 8,
        carry_log = 3,
        load_log = 3,
        debarker = 8,
        headsaw = 15,      headsaw_bonus = 5,
        edger = 8,
        planer = 12,       planer_bonus = 5,
        veneer = 25,       veneer_bonus = 10,
        plywood = 20,
        specialty = 30,    specialty_bonus = 15,
        contract_complete = 50,
        export_complete = 75,
        plant_sapling = 15,
        dodge_widow_maker = 10,
    },

    WoodworkingXP = {
        craft_level0 = 15,
        craft_level5 = 30,
        craft_level10 = 50,
        craft_level15 = 75,
        craft_level20 = 100,
        craft_level25 = 140,
        failed_craft_pct = 0.25,
        furniture_contract = 50,
        furniture_export = 40,
    },
}

-----------------------------------------------------------
-- FORESTRY LEVEL UNLOCKS
-- Key = level, value = table of unlock flags.
-----------------------------------------------------------
Config.ForestryUnlocks = {
    [0]  = { 'hatchet', 'debarker', 'log_deck' },
    [3]  = { 'felling_axe' },
    [5]  = { 'headsaw', 'edger', 'species_id' },
    [7]  = { 'chainsaw_cert_eligible' },
    [8]  = { 'efficient_debarking' },
    [10] = { 'planer', 'yield_estimate' },
    [12] = { 'steady_cuts' },
    [14] = { 'crosscut_cert_eligible' },
    [16] = { 'reduced_waste' },
    [18] = { 'heavy_equip_eligible' },
    [20] = { 'veneer', 'full_tree_info' },
    [22] = { 'precision_planing' },
    [25] = { 'plywood' },
    [26] = { 'veneer_mastery' },
    [30] = { 'specialty', 'value_tier' },
    [32] = { 'master_miller' },
    [38] = { 'zero_waste' },
    [45] = { 'legendary_efficiency' },
    [50] = { 'forestry_legend' },
}

-----------------------------------------------------------
-- SAWMILL STATION LEVEL REQUIREMENTS
-----------------------------------------------------------
Config.SawmillStationLevels = {
    debarker = 0,
    headsaw = 5,
    edger = 5,
    planer = 10,
    crosscut_station = 5,
    veneer = 20,
    plywood = 25,
    specialty = 30,
}

-----------------------------------------------------------
-- LOG TYPES
-----------------------------------------------------------
Config.LogTypes = {
    short = {
        item = 'log_short',
        label = 'Short (4ft)',
        weight = 2000,
        carryable = true,
        swingCost = 1,
    },
    standard = {
        item = 'log_standard',
        label = 'Standard (8ft)',
        weight = 5000,
        carryable = false,
        swingCost = 1,
    },
    long = {
        item = 'log_long',
        label = 'Long (16ft)',
        weight = 10000,
        carryable = false,
        swingCost = 1,
    },
}

-----------------------------------------------------------
-- DAMAGED LOG MODIFIER
-----------------------------------------------------------
Config.DamagedValueMultiplier = 0.60

-----------------------------------------------------------
-- TIMBER WARNING (shared so server can check radius for broadcast)
-----------------------------------------------------------
Config.TimberWarning = {
    Radius = 12.0,
    Duration = 3000,
}
