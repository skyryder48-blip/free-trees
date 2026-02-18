-----------------------------------------------------------
-- CONFIG: CLIENT
-- Client-side configuration values.
-- Loaded before client/*.lua via fxmanifest.
-----------------------------------------------------------

-----------------------------------------------------------
-- GLOBAL STATE (must initialize here, before client/*.lua)
-- client/transport.lua accesses PlayerState.loaded at load
-- time in a CreateThread, before client/main.lua loads.
-----------------------------------------------------------
PlayerState = {
    loaded = false,
    onDuty = false,
    forestryLevel = 0,
    woodworkingLevel = 0,
    citizenid = nil,
}

FelledTreeCache = {}
CarryState = nil

-----------------------------------------------------------
-- STAMINA
-----------------------------------------------------------
Config.Stamina = {
    BaseSwings = 12,
    SwingsPerLevel = 0.6,
    MaxSwings = 50,
    WindedDuration = 8000,
    SeatedRecoveryMultiplier = 2.5,
    LyingRecoveryMultiplier = 3.5,
    WarningThreshold = 3,
}

-----------------------------------------------------------
-- TIMBER WARNING (extensions to shared config)
-----------------------------------------------------------
Config.TimberWarning.Sound = true
Config.TimberWarning.DirectionalIndicator = false

-----------------------------------------------------------
-- CAMERA EFFECTS
-----------------------------------------------------------
Config.CameraEffects = {
    TreeImpactShakeRadius = 8.0,
    TreeImpactShakeMin = 0.03,
    TreeImpactShakeMax = 0.08,
}

-----------------------------------------------------------
-- INJURY
-----------------------------------------------------------
Config.Injury = {
    CrushZoneRadius = 3.0,
    CrushDamage = { min = 65, max = 90 },
    CrushRagdoll = 2000,
    ChainsawKickback = { min = 5, max = 10 },
    DroppedLog = 5,
}

-----------------------------------------------------------
-- CARRY & MOVEMENT
-----------------------------------------------------------
Config.CarrySpeedModifiers = {
    short_log = 0.85,
    standard_log = 0.65,
    branch_bundle = 0.90,
    hand_cart = 0.70,
}

-----------------------------------------------------------
-- LOG PROPS (models and carry bone offsets)
-----------------------------------------------------------
Config.LogProps = {
    short = {
        model = `prop_logpile_04`,
        carryOffset = {
            bone = 57005, -- SKEL_R_Hand
            x = 0.1, y = 0.0, z = 0.0,
            rx = 90.0, ry = 0.0, rz = 0.0,
        },
    },
    standard = {
        model = `prop_log_01`,
        carryOffset = {
            bone = 24818, -- SKEL_Spine3
            x = 0.3, y = 0.1, z = 0.1,
            rx = 80.0, ry = 10.0, rz = 0.0,
        },
    },
    long = {
        model = `prop_logpile_01`,
        carryOffset = nil, -- Not hand-carryable
    },
}

-----------------------------------------------------------
-- VEHICLE LOG SLOTS
-----------------------------------------------------------
Config.VehicleLogSlots = {
    flatbed = { maxLogs = 20 },
    pickup  = { maxLogs = 6 },
}

-----------------------------------------------------------
-- PARTICLES
-----------------------------------------------------------
Config.Particles = {
    MaxActiveLooped = 3,
    MaxActiveOneshot = 10,
    CullDistance = 50.0,
}

-----------------------------------------------------------
-- CLOTHING (on-duty outfit)
-----------------------------------------------------------
Config.Clothing = {
    AutoDress = true,
    AllowCustom = true,
    Outfits = {
        male = {
            [3] = { drawable = 4, texture = 0 },   -- Torso
            [4] = { drawable = 35, texture = 0 },   -- Legs
            [6] = { drawable = 25, texture = 0 },   -- Shoes
            [8] = { drawable = 15, texture = 0 },   -- Undershirt
            [0] = { drawable = 45, texture = 0, prop = true }, -- Hat
        },
        female = {
            [3] = { drawable = 7, texture = 0 },
            [4] = { drawable = 30, texture = 0 },
            [6] = { drawable = 25, texture = 0 },
            [8] = { drawable = 3, texture = 0 },
            [0] = { drawable = 45, texture = 0, prop = true },
        },
    },
}

-----------------------------------------------------------
-- CAMP SPOTS
-----------------------------------------------------------
Config.CampSpots = {
    {
        label = 'Logger Camp - Paleto',
        coords = vec3(-550.0, 5320.0, 70.0),
        props = {
            { model = `prop_bench_05`, offset = vec3(0, 0, 0), heading = 180.0 },
            { model = `prop_bbq_3`, offset = vec3(2.0, 0, 0), heading = 90.0 },
        },
        blip = { sprite = 436, color = 69, scale = 0.5, label = 'Logger Camp' },
        renderDistance = 50.0,
    },
}

-----------------------------------------------------------
-- OLD TIMER NPC
-----------------------------------------------------------
Config.OldTimer = {
    Enabled = true,
    Locations = {
        {
            model = 's_m_y_construct_01',
            coords = vec4(-545.0, 5325.0, 70.0, 150.0),
            scenario = 'WORLD_HUMAN_SMOKING',
        },
    },
}

-----------------------------------------------------------
-- FORESTRY OFFICE (client-side: locations for NPC spawning)
-----------------------------------------------------------
Config.ForestryOffice = Config.ForestryOffice or {}
Config.ForestryOffice.Locations = {
    {
        label = 'Paleto Forestry Office',
        coords = vec3(-530.0, 5400.0, 37.0),
        npc = {
            model = 's_m_y_ranger_01',
            coords = vec4(-530.0, 5400.0, 37.0, 180.0),
        },
        blip = { sprite = 480, color = 69, scale = 0.7, label = 'Forestry Office' },
    },
}

-----------------------------------------------------------
-- LUMBER BUYER (client-side: NPC locations)
-----------------------------------------------------------
Config.LumberBuyer = Config.LumberBuyer or {}
Config.LumberBuyer.Locations = {
    {
        label = 'Paleto Lumber Buyer',
        coords = vec3(-540.0, 5415.0, 37.0),
        npc = {
            model = 's_m_y_construct_02',
            coords = vec4(-540.0, 5415.0, 37.0, 90.0),
        },
    },
}

-----------------------------------------------------------
-- FURNITURE BUYER (client-side: NPC locations)
-----------------------------------------------------------
Config.FurnitureBuyer = Config.FurnitureBuyer or {}
Config.FurnitureBuyer.Locations = {
    {
        label = 'Paleto Furniture Store',
        coords = vec3(-525.0, 5420.0, 37.0),
        npc = {
            model = 'a_f_y_business_02',
            coords = vec4(-525.0, 5420.0, 37.0, 270.0),
        },
    },
}

-----------------------------------------------------------
-- EXPORT DOCKS (client-side: zone coords)
-----------------------------------------------------------
Config.LumberExport = Config.LumberExport or {}
Config.LumberExport.Location = vec3(-200.0, 6200.0, 30.0)

Config.FurnitureExport = Config.FurnitureExport or {}
Config.FurnitureExport.Location = vec3(-210.0, 6205.0, 30.0)

-----------------------------------------------------------
-- SAWMILLS
-----------------------------------------------------------
Config.Sawmills = {
    {
        id = 'paleto_sawmill',
        label = 'Paleto Community Sawmill',
        tier = 2,
        blip = { sprite = 566, color = 47, scale = 0.8, label = 'Sawmill' },
        stations = {
            { id = 'debarker',         label = 'Debarker',       coords = vec3(-537.0, 5403.0, 37.0), levelReq = 0 },
            { id = 'headsaw',          label = 'Head Saw',       coords = vec3(-535.0, 5405.0, 37.0), levelReq = 5 },
            { id = 'edger',            label = 'Edger',          coords = vec3(-533.0, 5405.0, 37.0), levelReq = 5 },
            { id = 'planer',           label = 'Planer',         coords = vec3(-531.0, 5405.0, 37.0), levelReq = 10 },
            { id = 'crosscut_station', label = 'Crosscut',       coords = vec3(-529.0, 5405.0, 37.0), levelReq = 5 },
            { id = 'veneer',           label = 'Veneer Slicer',  coords = vec3(-527.0, 5403.0, 37.0), levelReq = 20 },
            { id = 'plywood',          label = 'Plywood Press',  coords = vec3(-525.0, 5403.0, 37.0), levelReq = 25 },
            { id = 'specialty',        label = 'Specialty Saw',  coords = vec3(-523.0, 5403.0, 37.0), levelReq = 30 },
        },
        throughputBonus = 0.15,
        throughputBonusCap = 0.60,
        furnitureWorkshop = vec3(-521.0, 5401.0, 37.0),
    },
}

-----------------------------------------------------------
-- LOG CHUTES
-----------------------------------------------------------
Config.LogChutes = {
    {
        id = 'paleto_chute_north',
        label = 'North Ridge Chute',
        sendPoint = vec3(-800.0, 5500.0, 90.0),
        collectionPoint = vec3(-780.0, 5420.0, 38.0),
        slideTime = 8000,
        maxLogsPerSend = 3,
        blip = {
            send    = { sprite = 479, color = 47, scale = 0.6, label = 'Log Chute (Send)' },
            collect = { sprite = 479, color = 25, scale = 0.6, label = 'Log Chute (Collect)' },
        },
    },
}

-----------------------------------------------------------
-- CREW (client-side keys)
-----------------------------------------------------------
Config.Crew = Config.Crew or {}
Config.Crew.AutoRadio = true
Config.Crew.RadioResource = 'pma-voice'
Config.Crew.InviteDistance = 10.0

-----------------------------------------------------------
-- FALL INDICATOR
-----------------------------------------------------------
Config.FallIndicator = {
    Enabled = true,
    Length = 8.0,
    Width = 1.0,
}

-----------------------------------------------------------
-- INTERACTION DISTANCES
-----------------------------------------------------------
Config.InteractionDistances = {
    Tree = 4.0,
    Station = 2.5,
    NPC = 3.0,
}
