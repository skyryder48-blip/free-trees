# ðŸª“ QBX FORESTRY â€” MASTER DESIGN REFERENCE
### Version: FINAL (Consolidated v1â€“v8)
### Framework: Qbox (qbx_core, ox_lib, ox_target, ox_inventory, oxmysql)
### Target: 150â€“200 Player RP Servers

---

# TABLE OF CONTENTS

1. [Overview & Vision](#1-overview--vision)
2. [Resource Structure & Manifest](#2-resource-structure--manifest)
3. [Database Schema](#3-database-schema)
4. [Production Chain (6 Stages)](#4-production-chain)
5. [Progression System](#5-progression-system)
6. [Crew System](#6-crew-system)
7. [Random Events](#7-random-events)
8. [Stamina System](#8-stamina-system)
9. [Immersion & RP Features](#9-immersion--rp-features)
10. [Old Timer NPC](#10-old-timer-npc)
11. [Item Registry](#11-item-registry)
12. [Economy & Sales](#12-economy--sales)
13. [Performance Architecture](#13-performance-architecture)
14. [Security Model](#14-security-model)
15. [Complete Configuration Reference](#15-complete-configuration-reference)

---

# 1. OVERVIEW & VISION

A multi-process forestry production script spanning forest to finished product. Six production stages, two independent XP tracks, ephemeral crew system, server-authoritative economy, and deep immersion layer.

**Core Loop:** Acquire permit â†’ Fell trees â†’ Process in field â†’ Transport â†’ Saw at mill â†’ Sell or craft furniture.

**Design Pillars:**
- Zero idle cost â€” nothing runs when nobody is doing forestry work.
- Server-authoritative â€” client never determines quantities, prices, or XP.
- Zone-free global trees â€” every GTA V tree model is choppable anywhere on the map via `ox_target:addModel()`.
- MySQL clock for all persistence â€” `NOW()` for timestamps, never `os.time()` (unavailable in FiveM server context).
- Session-relative timing via `GetGameTimer()` for ephemeral state (cooldowns, crew activity windows).
- Batched DB writes â€” XP accumulated in memory, flushed every 60 seconds + on disconnect.

**Removed Systems (for clarity):**
- âŒ Forestry Ranger job (entire enforcement system cut)
- âŒ Spotter mechanic during felling
- âŒ Weather/time-of-day effects on forestry work
- âŒ Zone-based forest areas (replaced by global tree system)
- âŒ Five of seven original random events (only Widow Maker and Bee Swarm remain)
- âŒ Full fatigue meter (replaced by swing-counter stamina)

---

# 2. RESOURCE STRUCTURE & MANIFEST

## 2.1 File Structure

```
qbx_forestry/
â”œâ”€â”€ fxmanifest.lua
â”œâ”€â”€ config/
â”‚   â”œâ”€â”€ shared.lua              -- Species, items, skill checks, progression tables
â”‚   â”œâ”€â”€ client.lua              -- Particles, carry, clothing, stamina, UI, draw distances
â”‚   â””â”€â”€ server.lua              -- Economy, XP, events, respawn timers, crew, NPC shops
â”œâ”€â”€ client/
â”‚   â”œâ”€â”€ main.lua                -- Entry point, player state init, job clock-in/out
â”‚   â”œâ”€â”€ felling.lua             -- Tree detection, directional felling, skill checks, fall sync
â”‚   â”œâ”€â”€ processing.lua          -- Limbing, bucking, cut length selection
â”‚   â”œâ”€â”€ transport.lua           -- Log carry, vehicle loading, chute interaction
â”‚   â”œâ”€â”€ sawmill.lua             -- Tier 1 portable + Tier 2 community sawmill stations
â”‚   â”œâ”€â”€ crafting.lua            -- Furniture workshop, secondary product crafting
â”‚   â”œâ”€â”€ crew.lua                -- Crew UI, invites, stash access, roster display
â”‚   â”œâ”€â”€ events.lua              -- Widow maker, bee swarm client handlers
â”‚   â”œâ”€â”€ stamina.lua             -- Swing counter, winded state, recovery
â”‚   â”œâ”€â”€ effects.lua             -- Audio, particles, camera shake, log props
â”‚   â””â”€â”€ immersion.lua           -- Clothing, camp spots, bulletin board, Old Timer NPC
â”œâ”€â”€ server/
â”‚   â”œâ”€â”€ main.lua                -- Entry point, usable item registration, player load/unload
â”‚   â”œâ”€â”€ economy.lua             -- NPC buy prices, export dock multipliers, contract generation
â”‚   â”œâ”€â”€ progression.lua         -- XP accumulation, level-up, batched writes, skill unlocks
â”‚   â”œâ”€â”€ trees.lua               -- Felled tree tracking, respawn tick, sapling planting
â”‚   â”œâ”€â”€ inventory.lua           -- Server-authoritative item grants, validations, metadata
â”‚   â”œâ”€â”€ crew.lua                -- Crew state, invites, kick, disband, XP multiplier
â”‚   â”œâ”€â”€ events.lua              -- Event roller, server-side event handlers
â”‚   â”œâ”€â”€ callbacks.lua           -- All lib.callback.register() definitions
â”‚   â””â”€â”€ logging.lua             -- Discord webhook integration (optional)
â”œâ”€â”€ shared/
â”‚   â”œâ”€â”€ enums.lua               -- Shared enumerations (tree sizes, log quality, etc.)
â”‚   â””â”€â”€ utils.lua               -- Shared utility functions (distance, table helpers)
â”œâ”€â”€ sql/
â”‚   â””â”€â”€ install.sql             -- All CREATE TABLE statements
â””â”€â”€ web/
    â””â”€â”€ images/                 -- Item PNG images (hatchet.png, chainsaw.png, etc.)
```

## 2.2 fxmanifest.lua

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbx_forestry'
description 'Forestry & Lumber Production for Qbox Framework'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
    'shared/*.lua',
}

client_scripts {
    'config/client.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/server.lua',
    'server/*.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
}
```

---

# 3. DATABASE SCHEMA

Seven tables. No ranger or zone tables.

```sql
-- Player progression and statistics
CREATE TABLE IF NOT EXISTS forestry_players (
    citizenid VARCHAR(50) PRIMARY KEY,
    forestry_xp INT NOT NULL DEFAULT 0,
    forestry_level INT NOT NULL DEFAULT 0,
    woodworking_xp INT NOT NULL DEFAULT 0,
    woodworking_level INT NOT NULL DEFAULT 0,
    licenses JSON NOT NULL DEFAULT '{}',
    statistics JSON NOT NULL DEFAULT '{}',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Timber permits with expiry
CREATE TABLE IF NOT EXISTS forestry_permits (
    id INT AUTO_INCREMENT PRIMARY KEY,
    citizenid VARCHAR(50) NOT NULL,
    purchased_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    UNIQUE KEY idx_citizen (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Felled tree tracking for respawn
CREATE TABLE IF NOT EXISTS forestry_felled_trees (
    tree_key VARCHAR(100) PRIMARY KEY,
    model_hash BIGINT NOT NULL,
    felled_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    respawns_at DATETIME NOT NULL,
    INDEX idx_respawn (respawns_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- NPC contracts
CREATE TABLE IF NOT EXISTS forestry_contracts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    item_name VARCHAR(50) NOT NULL,
    species VARCHAR(30) NULL,
    quantity INT NOT NULL,
    quantity_filled INT NOT NULL DEFAULT 0,
    price_per_unit INT NOT NULL,
    deadline DATETIME NOT NULL,
    fulfilled BOOLEAN NOT NULL DEFAULT FALSE,
    fulfilled_by VARCHAR(50) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_active (fulfilled, deadline),
    INDEX idx_item (item_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Dynamic market prices
CREATE TABLE IF NOT EXISTS forestry_market (
    item_name VARCHAR(50) PRIMARY KEY,
    base_price INT NOT NULL,
    current_price INT NOT NULL,
    supply INT NOT NULL DEFAULT 0,
    demand INT NOT NULL DEFAULT 100,
    last_updated DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Weekly lumber export species multipliers
CREATE TABLE IF NOT EXISTS forestry_export_multipliers (
    species VARCHAR(30) PRIMARY KEY,
    multiplier DECIMAL(3,1) NOT NULL DEFAULT 1.0,
    rotated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Weekly furniture export category multipliers
CREATE TABLE IF NOT EXISTS forestry_furniture_export (
    category VARCHAR(30) PRIMARY KEY,
    multiplier DECIMAL(3,1) NOT NULL DEFAULT 1.0,
    rotated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

**licenses JSON example:**
```json
{ "timber_permit": true, "chainsaw_cert": true, "crosscut_cert": false, "heavy_equipment": true }
```

**statistics JSON example:**
```json
{ "trees_felled": 342, "logs_processed": 891, "lumber_produced": 1204, "furniture_crafted": 67, "contracts_completed": 23, "total_earned": 245800 }
```

---

# 4. PRODUCTION CHAIN

## Stage 1 â€” Scouting & Permitting

### Species Identification (Level-Gated)

What a player sees when they ox_target a tree depends on Forestry level:

| Forestry Level | ox_target Shows |
|---|---|
| 0â€“4 | **"Tree"** â€” no species, no details |
| 5â€“9 | **"Pine Tree"** / **"Oak Tree"** â€” species name |
| 10â€“19 | Species + **Size Category** (Small / Medium / Large) |
| 20â€“29 | Species + Size + **Estimated Yield** |
| 30+ | Species + Size + Yield + **Wood Value Tier** |

Computed client-side from `Config.ModelToSpecies` hash lookup. Zero network traffic.

### Global Tree System

ALL GTA V trees are choppable anywhere on the map. No forest zones.

```lua
-- Client: register ox_target on all tree model hashes
for species, data in pairs(Config.TreeSpecies) do
    for _, model in ipairs(data.models) do
        ox_target:addModel(model, { ... })
    end
end
```

Tree models registered per species include `prop_tree_pine_*`, `prop_tree_oak_*`, `prop_tree_birch_*`, `prop_tree_cedar_*`, `prop_tree_maple_*`, `prop_tree_log_*`, and others. Species determined by model hash â†’ species lookup table (`Config.ModelToSpecies`).

Individual trees tracked by composite key: `modelHash:x:y:z` (coordinates rounded to 1 decimal). Felled trees stored in `forestry_felled_trees` DB table with `respawns_at` datetime. Client maintains `felledTreeCache` (set of tree keys) synced on join and via broadcast events. Felled trees hidden client-side via `SetEntityVisible(entity, false)`.

### Permits

One-time purchase from Forestry Office NPC. `timber_permit` item in ox_inventory. $500, expires after 7 days (enforced via `expires_at > NOW()` in MySQL). No ranger enforcement â€” purely RP/admin matter.

### Tree Respawn

| Tree Size | Respawn Time |
|---|---|
| Small | 60 minutes |
| Medium | 120 minutes |
| Large | 240 minutes |

Server checks every 2 minutes for trees where `respawns_at <= NOW()`, deletes DB rows, removes from `felledTreeCache`, broadcasts respawn to all clients. Planting a `tree_sapling` near a stump sets `respawns_at = NOW()` for immediate respawn and grants 15 Forestry XP.

---

## Stage 2 â€” Felling

### Directional Felling

Tree falls **directly away from the player's position** relative to the trunk. No radial menu â€” pure positioning.

### Ground Indicator (Tool-Gated)

Fall direction arrow renders on the ground only when all three conditions are met:
1. Player has a chopping tool in hand (hatchet, felling_axe, crosscut_saw, chainsaw).
2. Player is aiming at a valid tree model.
3. Player is within interaction range (4m).

Projected green arrow on ground from tree base extending ~8m in fall direction. Fades green â†’ yellow â†’ red if obstructions detected. Entirely client-side rendering.

### Tools

| Tool | Tree Sizes | Speed | Requirements |
|---|---|---|---|
| Hatchet | Small only | Slow (~12s) | None |
| Felling Axe | Small + Medium | Moderate (~18s) | Forestry Lv3 |
| Crosscut Saw | All sizes | Fast (~18s total, two players) | Forestry Lv14 + cert + partner |
| Chainsaw | All sizes | Fastest (~10s) | Forestry Lv7 + cert + fuel |

### Skill Checks

| Tree Size | Pattern | Failure |
|---|---|---|
| Small | `{'easy', 'easy'}` | -1 log yield |
| Medium | `{'easy', 'medium', 'easy'}` | Damaged logs |
| Large | `{'medium', 'medium', 'hard'}` | Damaged + fewer logs |

### TIMBER! Warning

When a tree begins to fall, all players within **12m** receive:
- On-screen text: **"âš ï¸ TIMBER!"** for 3 seconds.
- Loud crack/shout sound effect (positional 3D audio).
- **No directional indicator.** Players must physically look at the tree to judge fall direction. Forces spatial awareness.

---

## Stage 3 â€” Field Processing

### Limbing

Remove branches from felled tree. Produces 2â€“4 `branch_bundle` items per tree. 15% chance of `resin_raw` drop from pine/redwood. Costs 1 stamina swing per branch.

### Bucking

Cut felled tree into logs. Player selects length via `lib.inputDialog`:

| Length | Item | Weight | Hand-Carryable | Swing Cost |
|---|---|---|---|---|
| Short (4ft) | `log_short` | 2000g, stack 5 | Yes (shoulder carry) | 1 |
| Standard (8ft) | `log_standard` | 5000g, stack 3 | No (vehicle required) | 1 |
| Long (16ft) | `log_long` | 10000g, stack 1 | No (skidder/truck required) | 1 |

### Log Quality

Two states only:
- **Normal** â€” clean fell, full value. Metadata: `{ species = 'oak', quality = 'normal' }`
- **Damaged** â€” failed skill checks or bad fell direction. 60% value. Metadata: `{ species = 'oak', quality = 'damaged' }`

### Log Yield by Species

| Species | Size | Base Yield (standard-equivalent) | Base Value per Log |
|---|---|---|---|
| Pine | Large | 4 | $50 |
| Oak | Medium | 3 | $120 |
| Birch | Small | 2 | $40 |
| Redwood | Large | 6 | $200 |
| Cedar | Medium | 3 | $90 |
| Maple | Medium | 3 | $130 |

---

## Stage 4 â€” Transport

### Transport Methods

| Method | Capacity | License Required |
|---|---|---|
| Manual carry (shoulder) | 1 short log | None |
| Pickup truck bed | 6 short or 3 standard | None |
| ATV + Trailer | ~6 standard or ~12 short | None |
| Skidder (grapple) | Long logs | Heavy Equipment License |
| Logging Truck + Crane | 20+ standard | Heavy Equipment License |

### Physical Log Props

Logs exist as visible world props, not just inventory abstractions. After bucking, props spawn near the felled tree. Pickup via ox_target â†’ progress bar â†’ prop deleted, item added. While carrying, prop attaches to player model. Loading onto vehicles attaches props at calculated stacking positions.

| Log Type | Carry Animation | Speed Modifier |
|---|---|---|
| Short | One-shoulder carry (upper body, can walk/jog) | 0.85 (85% speed) |
| Standard | Two-hand carry (walk only, no sprint) | 0.65 (65% speed) |
| Long | Not hand-carryable | â€” |
| Branch bundle | Light carry | 0.90 |

### Log Chutes

Deployable via `log_chute_kit`. Send point (high elevation) and collection point (low elevation). Logs slide via timer. Blips visible only to clocked-in lumberjacks.

Access control: logs owned by placing player or their crew. Non-crew players don't see the collect option. Uncollected logs expire after 2 hours. Server-side ephemeral state (no DB).

---

## Stage 5 â€” Sawmill Processing

### Tier 1 â€” Portable Sawmill

Deployable item (`portable_sawmill`, $3,500). Any lumberjack can operate. **Any player can pick up any placed portable sawmill** (returns to their inventory â€” creates risk/reward). Produces `lumber_rough` + `sawdust` only.

### Tier 2 â€” Community Sawmill

Fixed facility on the map (1â€“3 configured locations). Eight processing stations:

| Station | Input â†’ Output | Level Req | Duration | Skill Check |
|---|---|---|---|---|
| Log Deck | Logs â†’ stash | 0 | Instant | None |
| Debarker | Log â†’ Debarked Log + `bark_raw` | 0 | 6s | None (progress bar only) |
| Head Saw | Debarked Log â†’ `lumber_rough` + `sawdust` | 5 | 10s | `{'medium'}` |
| Edger | `lumber_rough` â†’ `lumber_edged` | 5 | 5s | `{'easy'}` |
| Planer | `lumber_edged` â†’ `lumber_finished` | 10 | 6s | `{'easy'}` |
| Crosscut Station | Log â†’ sized pieces + `wood_chips` | 5 | 5s | `{'easy'}` |
| Veneer Slicer | Debarked Log (oak/cedar/redwood/maple) â†’ `veneer_sheet` | 20 | 12s | `{'hard'}` |
| Plywood Press | 3Ã— `veneer_sheet` â†’ `plywood_sheet` | 25 | 15s | `{'medium'}` |
| Specialty Saw | `lumber_finished` (premium species) â†’ `specialty_cut` | 30 | 10s | `{'hard'}` |

Players below the required level don't see the ox_target option â€” it simply doesn't exist for them.

### Multiplayer Throughput Bonus

Different players on different stations simultaneously: 15% duration reduction per additional active station, up to 60% with 4+ stations. Applies to all players at the mill, not just crew members.

### XP-Unlocked Personal Processing Bonuses

| Forestry Level | Bonus |
|---|---|
| 8 | Debarker duration -20% |
| 12 | Head Saw skill check -1 difficulty tier |
| 16 | 15% bonus lumber chance at Head Saw |
| 22 | Planer duration -25% |
| 26 | Veneer skill check -1 tier, +1 veneer per log |
| 32 | All station durations -15% (stacks) |
| 38 | Sawdust output doubled |
| 45 | 10% chance double output on any station |

These are personal to the player, not location-tied.

---

## Stage 6 â€” Sales & Distribution

Seven sale channels from low-tier buyback to premium export. Full details in [Section 12: Economy & Sales](#12-economy--sales).

**Summary:**
```
General Store     â†’ Byproducts (firewood, sawdust, mulch) at fixed low prices
Lumber Buyer NPC  â†’ All lumber types at base market price
Contract Board    â†’ Premium prices (1.3xâ€“2.0x) with deadlines
Lumber Export Dock â†’ Weekly species multipliers (0.7xâ€“2.5x), highest lumber payout
Furniture NPC     â†’ All furniture at base NPC price
Furniture Export   â†’ Weekly category multipliers (up to 3.0x), highest furniture payout
P2P Trading       â†’ Direct ox_inventory trades, no script mechanics needed
```

---

# 5. PROGRESSION SYSTEM

## 5.1 Dual XP Tracks

| Track | Governs | Cap |
|---|---|---|
| **Forestry** | Tree ID, felling, transport, sawmill, events | Level 50 |
| **Woodworking** | Furniture crafting recipes and bonuses | Level 30 |

Both stored in `forestry_players` table. Independent leveling.

## 5.2 Level Curve

```lua
local function xpForLevel(level)
    return math.floor(100 * (level ^ 1.5))
end
```

| Level | Cumulative XP | Time Estimate |
|---|---|---|
| 1 | 100 | ~30 min |
| 5 | 1,118 | ~3 hrs |
| 10 | 3,162 | ~8 hrs |
| 15 | 5,809 | ~15 hrs |
| 20 | 8,944 | ~25 hrs |
| 25 | 12,500 | ~38 hrs |
| 30 | 16,432 | ~52 hrs |
| 40 | 25,298 | ~88 hrs |
| 50 | 35,355 | ~135 hrs |

## 5.3 Forestry XP Sources

| Action | Base XP | Modifiers |
|---|---|---|
| Fell small tree | 10 | +5 if clean |
| Fell medium tree | 25 | +10 if clean |
| Fell large tree | 50 | +20 if clean |
| Limb a tree | 5 | â€” |
| Buck a log | 8 | Per cut |
| Carry log | 3 | Per log |
| Debarker | 8 | Per log |
| Head Saw | 15 | +5 on skill check success |
| Edger | 8 | Per piece |
| Planer | 12 | +5 on skill check success |
| Veneer Slicer | 25 | +10 on skill check success |
| Plywood Press | 20 | Per sheet |
| Specialty Saw | 30 | +15 on skill check success |
| Complete contract | 50 | Flat bonus |
| Complete export run | 75 | Flat bonus |
| Plant sapling | 15 | â€” |
| Dodge widow maker | 10 | Bonus |
| Crosscut saw (per player) | 15â€“25 | Based on performance |

**Crew XP bonus** applied on top: +10% per active crew member, cap +40% at 5 members.

**No XP for selling.** Only physical production work grants XP.

## 5.4 Forestry Level Unlocks

| Level | Unlock |
|---|---|
| 0 | Hatchet, small trees, Tier 1 sawmill, Debarker, Log Deck |
| 3 | Felling Axe |
| 5 | Head Saw, Edger, species ID on ox_target |
| 7 | Chainsaw Certification eligible |
| 8 | Efficient Debarking (duration -20%) |
| 10 | Planer, yield estimates on ox_target |
| 12 | Steady Cuts (Head Saw skill check -1 tier) |
| 14 | Crosscut Certification eligible |
| 16 | Reduced Waste (15% bonus lumber at Head Saw) |
| 18 | Heavy Equipment License eligible |
| 20 | Veneer Slicer, full tree info display |
| 22 | Precision Planing (Planer duration -25%) |
| 25 | Plywood Press |
| 26 | Veneer Mastery (skill check -1 tier, +1 veneer) |
| 30 | Specialty Saw, value tier on ox_target |
| 32 | Master Miller (all stations -15%) |
| 38 | Zero Waste (sawdust doubled) |
| 45 | Legendary Efficiency (10% double output) |
| 50 | Forestry Legend (cosmetic title) |

## 5.5 Licensing System

Reaching required level makes player **eligible**. They must complete an action to receive the license item.

| License | Eligibility | How to Obtain | Unlocks |
|---|---|---|---|
| Timber Permit | Level 0 | Purchase from Forestry Office ($500) | Clock in as lumberjack |
| Chainsaw Cert | Level 7 | Complete training task (single practice skill check) | Chainsaw use |
| Crosscut Cert | Level 14 | Complete co-op training (requires partner) | Crosscut saw use |
| Heavy Equip License | Level 18 | Pass driving test (short obstacle course) | Skidder, logging truck |

Licenses are ox_inventory items. Server-side validation on use attempt. Lost item = must re-obtain.

## 5.6 Woodworking XP Sources

| Action | Base XP |
|---|---|
| Craft Level 0 recipe | 15 |
| Craft Level 5 recipe | 30 |
| Craft Level 10 recipe | 50 |
| Craft Level 15 recipe | 75 |
| Craft Level 20 recipe | 100 |
| Craft Level 25 recipe | 140 |
| Failed craft | 25% of success XP |
| Furniture contract | 50 |
| Furniture export delivery | 40 |

## 5.7 Woodworking Level Unlocks

| Level | Unlock |
|---|---|
| 0 | Wooden Crate, Fence Panel Set |
| 5 | Pine Bookshelf, Basic Stool |
| 8 | Craft time -10% |
| 10 | Oak Chair, Cedar Chest, Birch Side Table |
| 14 | 5% material savings chance |
| 15 | Oak Dining Table, Pine Wardrobe, Maple Nightstand |
| 20 | Maple Desk, Birch Cabinet, Cedar Bench; +10% craft time reduction |
| 25 | Redwood Trophy Display, Oak Grandfather Clock |
| 26 | 10% material savings |
| 30 | Master label on crafted items (metadata) |

## 5.8 Batched XP Persistence

```lua
local pendingXP = {} -- pendingXP[citizenid] = { forestry = 0, woodworking = 0 }

-- Flush every 60 seconds
CreateThread(function()
    while true do
        Wait(60000)
        for citizenid, xp in pairs(pendingXP) do
            MySQL.update.await([[
                UPDATE forestry_players
                SET forestry_xp = forestry_xp + ?, woodworking_xp = woodworking_xp + ?,
                    forestry_level = ?, woodworking_level = ?
                WHERE citizenid = ?
            ]], { xp.forestry, xp.woodworking,
                  getCachedLevel(citizenid, 'forestry'),
                  getCachedLevel(citizenid, 'woodworking'),
                  citizenid })
        end
        pendingXP = {}
    end
end)

-- Also flush on disconnect
AddEventHandler('playerDropped', function()
    local citizenid = GetCitizenId(source)
    if citizenid and pendingXP[citizenid] then
        FlushPlayerXP(citizenid)
    end
    playerCache[citizenid] = nil
end)
```

---

# 6. CREW SYSTEM

## 6.1 Design

Crews are ephemeral session-based groups. No DB persistence â€” dissolve on server restart. Solo players lose nothing mechanically; crews gain efficiency bonuses and cooperative tool access.

## 6.2 Formation

Any clocked-in lumberjack can create a crew via `/crew` or radial menu. Leader invites nearby players (within 10m, must be clocked in, not in another crew) via `lib.registerContext`. Max 8 members.

## 6.3 Roles (Cosmetic Only)

| Role | Icon | Purpose |
|---|---|---|
| Leader | ðŸ‘‘ | Auto-assigned to creator. Manages crew. |
| Feller | ðŸª“ | Tree felling |
| Bucker | ðŸªš | Field processing |
| Driver | ðŸš› | Vehicle operation |
| Miller | âš™ï¸ | Sawmill stations |
| General | ðŸŒ² | Default |

Roles are voluntary labels. Any member can perform any action regardless of role.

## 6.4 XP Bonus

| Active Members | Bonus |
|---|---|
| 1 (solo) | 0% |
| 2 | +10% |
| 3 | +20% |
| 4 | +30% |
| 5+ | +40% (cap) |

"Active" = completed a forestry action within the last 5 minutes. Server-calculated via `GetCrewXPMultiplier()`.

## 6.5 Shared Stash

Each crew gets a temporary `ox_inventory` stash (50 slots, 200kg). Accessible by all members from anywhere. Items remain 30 minutes after crew disbands, then cleaned up.

## 6.6 Cooperative Mechanics

### Two-Person Crosscut Saw
- Both players need `crosscut_saw` item and certification.
- Alternating skill checks: `{'easy', 'medium'}` per player, 3 rounds each (6 total).
- Results: 0â€“1 failures = bonus yield +1 log +25 XP each; 2â€“3 = normal +15 XP; 4+ = damaged +10 XP.
- Total time ~18s (vs ~25s solo chainsaw on medium tree).
- Players don't need to be in the same crew â€” any two lumberjacks can cooperate. Crew just adds XP bonus.
- 60-second timeout if no partner joins.

### Relay Loading
Multiple crew members near same vehicle speeds loading:

| Members at Vehicle | Duration per Log |
|---|---|
| 1 (solo) | 4.0s |
| 2 | 2.5s |
| 3+ | 1.5s |

### Mill Shift Work
Multiple players on different Tier 2 stations: 15% faster per additional active station, up to 60%. Applies to everyone at the mill, not just crew.

## 6.7 Leaving & Disbanding

- Any member can leave via menu.
- Leader leaves â†’ auto-transfer to longest-active member. If only one remains, auto-disband.
- Leader can kick members.
- Disconnect or clock-out â†’ auto-removed from crew.

## 6.8 Radio Integration (Optional)

If pma-voice/saltychat/mumble-voip detected, crew members auto-join a shared radio frequency. Silently skipped if no radio resource present.

---

# 7. RANDOM EVENTS

Two events remain. Triggered by roll after successful tree fell. Server-authoritative.

```lua
Config.Events = {
    RollChanceBase = 1000,
    -- Combined: 16.5% chance per fell. 83.5% nothing.
    Events = {
        { name = 'widow_maker', chance = 100 },   -- 10.0%
        { name = 'bee_swarm',   chance = 65  },    -- 6.5%
    },
}
```

## 7.1 Widow Maker

**Trigger:** Tree felled successfully (medium/large trees only), 10% chance.

Dead branch breaks free during fall. 0.5â€“1.0s after fall animation starts, warning sound plays. Single `{'hard'}` skill check with short window.

- **Success:** Dodge. Notification: *"A dead branch snapped free â€” you dodged it!"* No damage. +10 Forestry XP.
- **Failure:** Hit. **40â€“65% max health damage.** 1.5s ragdoll. Notification: *"A widow maker caught you!"*

At 40â€“65% HP loss, a player below full health could go down. Incentivizes keeping health topped up and creates demand for medical items.

## 7.2 Bee Swarm

**Trigger:** Tree felled successfully (any size), 6.5% chance.

Felled tree contained a bee colony. 1s delay, buzzing audio begins. For next 20 seconds (or until dispelled):
- 2% HP damage every 3 seconds.
- Movement speed reduced 20% (`SetPedMoveRateOverride(0.8)`).
- Buzzing audio persists.

**Escape options:**
1. Run 30m from tree â†’ swarm dissipates.
2. Enter water â†’ immediate end.
3. Use `smoke_canister` item â†’ immediate end + 1â€“3Ã— `honeycomb` bonus drop.

## 7.3 Crush Zone (Not an "Event" â€” Always Active)

When a tree falls, server calculates a rectangular danger zone in the fall direction. Any player within 3m of the fall line on impact takes **65â€“90% max health damage** + 2s ragdoll.

This is not a random event â€” it happens every time someone stands in the fall zone. TIMBER! warning at 12m gives players ~2 seconds to react.

---

# 8. STAMINA SYSTEM

Replaced the full fatigue meter. Simple swing counter tied to Forestry XP level.

## 8.1 Mechanic

Every physical forestry action costs swings. When swings hit zero, player is **winded** and must recover.

### Swing Costs

| Action | Swings |
|---|---|
| Axe/hatchet chop (per skill check) | 1 |
| Chainsaw felling (per skill check) | 1 |
| Crosscut saw (per skill check) | 1 |
| Limbing (per branch) | 1 |
| Bucking (per cut) | 1 |
| Pick up short log | 1 |
| Pick up standard log | 2 |
| Load log onto vehicle | 1 |

**Does NOT cost swings:** Sawmill operation, crafting, selling, driving, walking, planting saplings.

### Max Swings by Level

```lua
local function GetMaxSwings(forestryLevel)
    return math.min(50, 12 + math.floor(forestryLevel * 0.6))
end
```

| Level | Max Swings | Practical Meaning |
|---|---|---|
| 0 | 12 | ~2 small trees before winded |
| 10 | 18 | ~3 medium trees with chainsaw |
| 20 | 24 | Full tree + process without rest |
| 30 | 30 | Extended work runs |
| 50 | 42 | Near cap, rarely winded |

## 8.2 Winded State

When swings reach 0:
1. All forestry actions blocked. Notification: *"You're winded. Catch your breath."*
2. Heavy breathing animation (hunched over, hands on knees).
3. Cannot sprint (control disabled).
4. Recovery timer starts based on player state:

| Player State | Recovery Time |
|---|---|
| Standing still | 8 seconds |
| Walking | No recovery (must stop) |
| **Seated** (vehicle, bench, chair) | ~3.2 seconds (2.5Ã— faster) |
| **Lying down** (ragdolled, bed) | ~2.3 seconds (3.5Ã— faster) |

On recovery: full swing counter restored. Notification: *"You've caught your breath."*

## 8.3 Level-Up Refresh

Gaining a Forestry level recalculates max swings and fully restores current swings.

## 8.4 UI

No HUD bar. Communicated via:
- Warning at 3 swings remaining: *"3 swings left before you need a break."*
- Winded notification when stamina hits 0.
- Recovery notification when restored.
- On-demand: radial menu â†’ "Check Stamina" â†’ *"You have 18/24 swings remaining."*

## 8.5 Performance

Zero cost when not winded. Recovery loop: 200ms poll, only during winded state (3â€“8 seconds). Sprint block: Wait(0) only during winded state. No persistent threads.

---

# 9. IMMERSION & RP FEATURES

## 9.1 Audio Design

All sounds use GTA V native `PlaySoundFromEntity` / `PlaySoundFromCoord`, positional 3D, distance-attenuated.

**Felling Audio:**

| Sound | Source | Distance | Notes |
|---|---|---|---|
| Axe chop impacts | Per-hit oneshot | 30m | Pitch varies Â±5% per hit |
| Chainsaw idle | Looped on entity | 40m | Starts on equip, stops on holster |
| Chainsaw cutting | Pitch-shifted loop | 50m | Pitch scales with species hardness |
| Tree creaking | Escalating groan | 25m | Final 3s of felling progress |
| Tree falling | Loud crack + whoosh | 60m | Loudest sound in script |
| Tree impact | Multi-layered crash | 50m | Camera shake for players â‰¤8m |
| Crosscut saw | Rhythmic rasp loop | 30m | Alternates stereo for push-pull |

**Processing Audio:** Limbing (crack + thud 15m), bucking (saw buzz 20m), log pickup (grunt 8m), log drop (thud 15m), vehicle loading (clang 20m).

**Sawmill Audio:** Each station produces ambient sound when operated. Multiple active stations create layered industrial soundscape. Head Saw is loudest (40m). Managed via `activeSawmillSounds` table with `StartStationAudio`/`StopStationAudio`.

## 9.2 Particle Effects

All particles use GTA V native `UseParticleFxAsset` / `StartParticleFxLoopedAtCoord` / `StartParticleFxNonLoopedAtCoord`. No custom assets.

| Effect | Particle | Type | Trigger |
|---|---|---|---|
| Axe chop | `core â†’ ent_brk_wood_lg` | Per-hit oneshot | Each chop impact |
| Chainsaw cutting | `core â†’ ent_dst_wood` | Looped during progress | Cutting duration |
| Tree ground impact | `core â†’ ent_dst_gen_dirt_lrg` | 2s oneshot | On tree hit ground |
| Stump dust | `core â†’ ent_dst_gen_dirt_sml` | 3s oneshot | After fell complete |
| Head Saw plume | `core â†’ ent_dst_wood` | Looped | Heavy sawdust, visible from distance |

**Performance limits:** Max 3 active looped + 10 active oneshot per client. 50m cull distance (skip spawning if camera too far). Looped particles always stopped when action ends.

## 9.3 Camera & Screen Effects

| Trigger | Effect | Intensity | Duration |
|---|---|---|---|
| Tree impact (â‰¤8m) | `ShakeGameplayCam 'SMALL_EXPLOSION_SHAKE'` | 0.03â€“0.08 (scales with distance) | 0.5s |
| Chainsaw kickback | `ShakeGameplayCam 'HAND_SHAKE'` + screen flash | 0.15 | 0.3s |
| Heavy log pickup | Blur pulse (`AnimpostfxPlay 'FocusOut'`) | â€” | 0.2s |
| Widow Maker hit | Camera shake + red flash | 0.2 | 0.8s |
| Bee Swarm active | Periodic screen pulse | 0.05 per tick | During swarm |
| Winded (stamina) | Heavy breathing camera bob | Subtle | During winded state |

## 9.4 Clothing System

Optional auto-dress when player clocks in as lumberjack. Configurable per server.

- On clock-in: client stores current outfit â†’ applies forestry outfit (flannel, work pants, boots, hard hat).
- On clock-out: restores previous outfit.
- Players can opt out via forestry menu toggle (preference stored as client KVP).
- Male and female outfit definitions in config with component/drawable/texture mappings.

## 9.5 Injury System

| Source | Damage | Effects | Trigger |
|---|---|---|---|
| Chainsaw kickback | 5â€“10% HP | 0.3s screen shake | Fail first skill check in chainsaw sequence |
| Widow Maker | 40â€“65% HP | 1.5s ragdoll | Event triggered, skill check failed |
| Bee Swarm DoT | 2% HP per 3s | 20% speed reduction, buzzing | Active swarm (up to 20s) |
| Crushed by tree | 65â€“90% HP | 2s ragdoll | Standing within 3m of fall line on impact |
| Dropped log | 5% HP | Brief stumble | Cancel carry while moving |

Crush zone detection: on tree impact, server calculates rectangular danger zone using `DistanceToLineSegment` from tree base to impact point, checks all nearby players.

## 9.6 Camp Spots

Scattered prop clusters in forested areas. Rest and social points.

Each camp: bench props + fire props, spawned client-side within 50m render distance. Sitting on bench triggers seated recovery multiplier for stamina. Blip on map (sprite 436, color 69, scale 0.5). No stash or special inventory â€” just places to stop and RP.

## 9.7 Bulletin Board

At each Forestry Office NPC location. Interactive via ox_target â†’ `lib.registerContext`.

Content server-refreshed every 30 minutes:
- **Market Update** â€” current export dock multipliers.
- **Safety Reminder** â€” static tips.
- **Community Stats** â€” total trees felled and lumber sold this week (from DB query).

---

# 10. OLD TIMER NPC

Character: **Earl** â€” retired from Old Growth Logging Co. Spawns at camp spots or Forestry Office locations. Idles with `WORLD_HUMAN_SMOKING` scenario. Interacted via ox_target â†’ `lib.registerContext` with five dialogue categories.

## 10.1 Dialogue Categories

### "Got any advice for me?" (Level-Aware)

Responses change based on player's Forestry level:

**Beginner (Lv 0â€“6):** Survival basics â€” widow makers, permits, stamina management, hatchet-first approach, clearing the fall zone.

**Intermediate (Lv 7â€“17):** Tool efficiency â€” cut length vs transport, chainsaw fuel management, crosscut saw benefits, bee swarm escape, crew XP bonus.

**Advanced (Lv 18â€“30):** Sawmill optimization â€” full processing chain value, veneer/plywood strategy, sapling replanting, multi-station throughput.

**Expert (Lv 31â€“50):** Market play â€” export dock weekly multiplier strategy, grandfather clock recipe economics, crew leadership value.

### "What's selling right now?" (Dynamic Market)

Pulls current export dock multipliers via server callback. Earl reports: hottest species and multiplier, coldest species to avoid, hot furniture category if applicable. Dialogue text is templated with real multiplier values.

### "How do I get better at this?" (Progression Nudges)

Identifies the player's next meaningful unlock (chainsaw cert at 7, heavy equipment at 18, veneer slicer at 20, etc.) and describes it in-character. Shows current level and next milestone.

### "Tell me about the trees around here." (Species Knowledge)

Random species per visit with practical info: Pine (bread and butter, everywhere), Oak (hardwood, wears tools, furniture premium), Birch (small/light/quick), Redwood (big prize, heavy gear needed), Cedar (aromatic, furniture moves fast), Maple (hardest wood, beautiful finish).

### "Any stories?" (Lore/Flavor)

Seven rotating anecdotes. No gameplay info â€” purely immersive. Cycle without immediate repeats.

---

# 11. ITEM REGISTRY

49 unique items. All registered in `ox_inventory/data/items.lua`.

**Format notes:**
- No `client = { image = '...' }` â€” ox_inventory auto-resolves from `web/images/{itemname}.png`.
- No `client.export` on tools â€” tool behavior handled by our script via ox_target + inventory search.
- Usable items registered via `exports.ox_inventory:RegisterUsableItem()` in our server/main.lua.

## 11.1 Tools & Equipment (10 items)

```lua
['hatchet']          = { label = 'Hatchet',          weight = 1500,  stack = false, close = true, description = 'A small axe for felling small trees and limbing.' },
['felling_axe']      = { label = 'Felling Axe',      weight = 3000,  stack = false, close = true, description = 'A heavy axe for felling small and medium trees.' },
['crosscut_saw']     = { label = 'Crosscut Saw',     weight = 4000,  stack = false, close = true, description = 'A two-person cooperative felling saw. Requires certification.' },
['chainsaw']         = { label = 'Chainsaw',         weight = 5000,  stack = false, close = true, description = 'A gas-powered chainsaw for all tree sizes. Requires fuel and certification.' },
['portable_sawmill'] = { label = 'Portable Sawmill',  weight = 15000, stack = false, close = true, description = 'A deployable Tier 1 sawmill for field lumber processing.' },
['log_chute_kit']    = { label = 'Log Chute Kit',    weight = 8000,  stack = false, close = true, description = 'A deployable chute for sliding logs downhill.' },
['chainsaw_fuel']    = { label = 'Chainsaw Fuel',    weight = 500,   close = true, description = 'Mixed fuel for chainsaws. Each unit powers roughly 5 trees.' },
['sharpening_kit']   = { label = 'Sharpening Kit',   weight = 300,   close = true, description = 'Restores 50 durability to bladed tools and saws.' },
['smoke_canister']   = { label = 'Smoke Canister',   weight = 150,   close = true, description = 'Disperses bee swarms. May yield honeycomb.' },
['tree_sapling']     = { label = 'Tree Sapling',     weight = 200,   close = true, description = 'A young tree ready for replanting at a stump site.' },
```

**Durability:** hatchet 50 uses, felling_axe 80, crosscut_saw 60 per team use, chainsaw 100 (sharpening kit restores 50).

## 11.2 Licenses & Certifications (4 items)

```lua
['timber_permit']      = { label = 'Timber Permit',           weight = 0, stack = false, close = true, description = 'Authorized permit for commercial tree felling.' },
['chainsaw_cert']      = { label = 'Chainsaw Certification',  weight = 0, stack = false, close = true, description = 'Proof of chainsaw safety training.' },
['crosscut_cert']      = { label = 'Crosscut Certification',  weight = 0, stack = false, close = true, description = 'Certification for crosscut saw operation.' },
['heavy_equip_license'] = { label = 'Heavy Equipment License', weight = 0, stack = false, close = true, description = 'Licensed to operate skidders and logging trucks.' },
```

## 11.3 Raw Logs (3 items, species via metadata)

```lua
['log_short']    = { label = 'Short Log (4ft)',    weight = 2000,  close = true, description = 'A 4-foot log section. Hand-carryable.' },
['log_standard'] = { label = 'Standard Log (8ft)', weight = 5000,  close = true, description = 'An 8-foot log. Requires vehicle transport.' },
['log_long']     = { label = 'Long Log (16ft)',    weight = 10000, close = true, description = 'A 16-foot log. Requires skidder or truck.' },
```

## 11.4 Processing Outputs (3 items)

```lua
['branch_bundle'] = { label = 'Branch Bundle', weight = 1000, close = true, description = 'Trimmed branches. Split for firewood.' },
['bark_raw']      = { label = 'Raw Bark',      weight = 500,  close = true, description = 'Tree bark. Shred for mulch.' },
['resin_raw']     = { label = 'Raw Resin',     weight = 150,  close = true, description = 'Sticky tree sap. Distill for turpentine.' },
```

## 11.5 Sawmill Products (8 items)

```lua
['lumber_rough']    = { label = 'Rough Lumber',    weight = 800,  close = true, description = 'Rough-cut lumber. Needs edging and planing.' },
['lumber_edged']    = { label = 'Edged Lumber',    weight = 750,  close = true, description = 'Trimmed edges. Ready for the planer.' },
['lumber_finished'] = { label = 'Finished Lumber', weight = 700,  close = true, description = 'Planed and sanded. Primary crafting/sale material.' },
['veneer_sheet']    = { label = 'Veneer Sheet',    weight = 400,  close = true, description = 'Thin decorative wood sheet.' },
['plywood_sheet']   = { label = 'Plywood Sheet',   weight = 1500, close = true, description = 'Laminated plywood panel.' },
['specialty_cut']   = { label = 'Specialty Cut',   weight = 600,  close = true, description = 'Precision-cut premium wood for high-end furniture.' },
['sawdust']         = { label = 'Sawdust',         weight = 200,  close = true, description = 'Fine wood particles. Compress into pellets or sell.' },
['wood_chips']      = { label = 'Wood Chips',      weight = 300,  close = true, description = 'Chipped wood from processing.' },
```

## 11.6 Crafted Goods (6 items)

```lua
['firewood_bundle'] = { label = 'Firewood Bundle', weight = 1200, close = true, description = 'Split and bundled firewood.' },
['wood_pellets']    = { label = 'Wood Pellets',    weight = 600,  close = true, description = 'Compressed wood pellet fuel.' },
['bark_mulch']      = { label = 'Bark Mulch',      weight = 400,  close = true, description = 'Landscaping mulch.' },
['turpentine']      = { label = 'Turpentine',      weight = 300,  close = true, description = 'Solvent distilled from resin. Crafting ingredient.' },
['wood_finish']     = { label = 'Wood Finish',     weight = 200,  close = true, description = 'Protective wood coating. Required for all furniture.' },
['honeycomb']       = { label = 'Honeycomb',       weight = 100,  close = true, description = 'Fresh honeycomb from a wild bee colony.' },
```

## 11.7 Specialty Supply (1 item)

```lua
['clock_mechanism'] = { label = 'Clock Mechanism', weight = 500, close = true, description = 'Precision clockwork for the grandfather clock recipe.' },
```

## 11.8 Furniture (15 items)

```lua
['furniture_crate']            = { label = 'Wooden Crate',           weight = 2000, close = true, description = 'A sturdy wooden storage crate.' },
['furniture_fence_panels']     = { label = 'Fence Panel Set',        weight = 3000, close = true, description = 'A set of wooden fence panels.' },
['furniture_stool']            = { label = 'Basic Stool',            weight = 1500, close = true, description = 'A simple handcrafted wooden stool.' },
['furniture_shelf_pine']       = { label = 'Pine Bookshelf',         weight = 3000, close = true, description = 'A pine bookshelf with clean lines.' },
['furniture_chair_oak']        = { label = 'Oak Chair',              weight = 2000, close = true, description = 'A solid oak dining chair.' },
['furniture_chest_cedar']      = { label = 'Cedar Chest',            weight = 3500, close = true, description = 'An aromatic cedar storage chest.' },
['furniture_sidetable_birch']  = { label = 'Birch Side Table',       weight = 2000, close = true, description = 'A light birch side table.' },
['furniture_table_oak']        = { label = 'Oak Dining Table',       weight = 5000, close = true, description = 'A grand oak dining table.' },
['furniture_wardrobe_pine']    = { label = 'Pine Wardrobe',          weight = 6000, close = true, description = 'A spacious pine wardrobe.' },
['furniture_nightstand_maple'] = { label = 'Maple Nightstand',       weight = 2000, close = true, description = 'A handsome maple nightstand.' },
['furniture_desk_maple']       = { label = 'Maple Desk',             weight = 5000, close = true, description = 'A professional maple writing desk.' },
['furniture_cabinet_birch']    = { label = 'Birch Cabinet',          weight = 4000, close = true, description = 'A clean birch display cabinet.' },
['furniture_bench_cedar']      = { label = 'Cedar Bench',            weight = 3500, close = true, description = 'A weather-resistant cedar bench.' },
['furniture_trophy_redwood']   = { label = 'Redwood Trophy Display', weight = 4000, close = true, description = 'A premium redwood trophy display case.' },
['furniture_clock_oak']        = { label = 'Oak Grandfather Clock',  weight = 7000, close = true, description = 'A magnificent oak grandfather clock.' },
```

## 11.9 Usable Item Registration (server/main.lua)

```lua
-- Smoke canister: disperse bee swarm
exports.ox_inventory:RegisterUsableItem('smoke_canister', function(source, item, data)
    if not playerBeeSwarmActive[source] then return end
    exports.ox_inventory:RemoveItem(source, 'smoke_canister', 1)
    playerBeeSwarmActive[source] = nil
    TriggerClientEvent('forestry:event:beeSwarm:disperse', source)
    local amount = math.random(Config.Events.BeeSwarm.bonusAmount[1], Config.Events.BeeSwarm.bonusAmount[2])
    exports.ox_inventory:AddItem(source, 'honeycomb', amount)
end)

-- Chainsaw fuel: refuel equipped chainsaw
exports.ox_inventory:RegisterUsableItem('chainsaw_fuel', function(source, item, data)
    local chainsaw = exports.ox_inventory:Search(source, 'slots', 'chainsaw')
    if not chainsaw or #chainsaw == 0 then return end
    exports.ox_inventory:RemoveItem(source, 'chainsaw_fuel', 1)
    local slot = chainsaw[1].slot
    local metadata = chainsaw[1].metadata or {}
    metadata.fuel = math.min((metadata.fuel or 0) + Config.Tools.FuelPerCanister, Config.Tools.MaxFuel)
    exports.ox_inventory:SetMetadata(source, slot, metadata)
end)

-- Sharpening kit: restore tool durability (triggers client tool selection)
exports.ox_inventory:RegisterUsableItem('sharpening_kit', function(source, item, data)
    TriggerClientEvent('forestry:sharpen:selectTool', source)
end)

-- Tree sapling: plant at stump (triggers client proximity check)
exports.ox_inventory:RegisterUsableItem('tree_sapling', function(source, item, data)
    TriggerClientEvent('forestry:sapling:startPlant', source)
end)
```

---

# 12. ECONOMY & SALES

## 12.1 Forestry Office NPC Shop

| Item | Price | Notes |
|---|---|---|
| Hatchet | $150 | â€” |
| Felling Axe | $400 | â€” |
| Crosscut Saw | $600 | Requires crosscut_cert |
| Chainsaw | $1,200 | Requires chainsaw_cert |
| Chainsaw Fuel | $50 | â€” |
| Sharpening Kit | $75 | â€” |
| Portable Sawmill | $3,500 | â€” |
| Tree Sapling | $25 | â€” |
| Smoke Canister | $30 | â€” |
| Log Chute Kit | $2,000 | â€” |
| Wood Finish | $100 | Also craftable from turpentine |
| Clock Mechanism | $500 | Specialty supply |
| Timber Permit | $500 | 7-day expiry |

## 12.2 General Store Buyback (Fixed Prices)

| Item | Price |
|---|---|
| Branch Bundle | $20 |
| Firewood Bundle | $40 |
| Sawdust | $5 |
| Wood Chips | $8 |
| Wood Pellets | $25 |
| Bark Mulch | $30 |
| Honeycomb | $45 |

## 12.3 Lumber Buyer NPC (Market-Modified)

Base prices modified by `forestry_market` supply/demand.

| Item | Base Price |
|---|---|
| Rough Lumber | $30 |
| Edged Lumber | $50 |
| Finished Lumber | $80 |
| Veneer Sheet | $60 |
| Plywood Sheet | $120 |
| Specialty Cut | $150 |
| Turpentine | $60 |

Market dynamics: selling increases supply â†’ price decreases. Supply decays 5 per hour. Price floor 50%, ceiling 150% of base.

## 12.4 Contract System

NPC-generated contracts rotate on a 30-minute generation timer. Max 8 active. Premium prices 1.3xâ€“2.0x with deadlines (24â€“72 hours). Partial delivery supported. Possible items: lumber_finished, plywood_sheet, veneer_sheet, specialty_cut, firewood_bundle.

## 12.5 Lumber Export Dock

Weekly rotating species multipliers (0.7xâ€“2.5x base price). Highest lumber payout in the game. Server rotates multipliers, stores in `forestry_export_multipliers` table.

## 12.6 Furniture Crafting

Public workshops at fixed map locations. No business ownership required.

### Recipes

| Recipe | WW Level | Ingredients | Species | NPC Price |
|---|---|---|---|---|
| Wooden Crate | 0 | 4Ã— lumber_rough | any | $150 |
| Fence Panel Set | 0 | 6Ã— lumber_finished | any | $400 |
| Basic Stool | 5 | 2Ã— lumber_finished + 1Ã— wood_finish | any | $250 |
| Pine Bookshelf | 5 | 4Ã— lumber_finished + 1Ã— wood_finish | pine | $600 |
| Oak Chair | 10 | 3Ã— lumber_finished + 1Ã— wood_finish | oak | $500 |
| Cedar Chest | 10 | 5Ã— lumber_finished + 2Ã— wood_finish | cedar | $900 |
| Birch Side Table | 10 | 2Ã— lumber_finished + 1Ã— wood_finish | birch | $450 |
| Oak Dining Table | 15 | 6Ã— lumber_finished + 2Ã— wood_finish | oak | $1,200 |
| Pine Wardrobe | 15 | 6Ã— lumber_finished + 2Ã— wood_finish | pine | $850 |
| Maple Nightstand | 15 | 3Ã— lumber_finished + 1Ã— wood_finish | maple | $700 |
| Maple Desk | 20 | 8Ã— lumber_finished + 3Ã— wood_finish | maple | $1,800 |
| Birch Cabinet | 20 | 5Ã— lumber_finished + 2Ã— veneer_sheet | birch | $1,100 |
| Cedar Bench | 20 | 4Ã— lumber_finished + 1Ã— wood_finish | cedar | $750 |
| Redwood Trophy | 25 | 4Ã— lumber_finished + 1Ã— specialty_cut | redwood | $2,500 |
| Grandfather Clock | 25 | 6Ã— lumber_finished + 2Ã— specialty_cut + 1Ã— clock_mechanism | oak | $3,500 |

### Secondary Crafting

| Product | Recipe | Sell Price |
|---|---|---|
| Firewood Bundle | 2Ã— branch_bundle | $40 |
| Wood Pellets | 5Ã— sawdust | $25 |
| Bark Mulch | 3Ã— bark_raw | $30 |
| Turpentine | 3Ã— resin_raw | $60 |
| Wood Finish | 1Ã— turpentine | $100 (or buy for $100) |

## 12.7 Furniture Export Dock

Separate from lumber export. Weekly category multipliers:

| Category | Items | Multiplier Range |
|---|---|---|
| Seating | Chair, Stool, Bench | 1.0xâ€“2.0x |
| Tables | Dining Table, Desk, Side Table, Nightstand | 1.0xâ€“2.2x |
| Storage | Chest, Cabinet, Wardrobe, Bookshelf | 0.8xâ€“1.8x |
| Specialty | Trophy Display, Grandfather Clock | 1.5xâ€“3.0x |
| Utility | Crate, Fence Panels | 0.8xâ€“1.5x |

## 12.8 Economy Safeguards

Sell cooldowns, daily NPC caps, export manifest expiry, server-side price validation, distance checks on every transaction, transaction logging.

---

# 13. PERFORMANCE ARCHITECTURE

## 13.1 Server Threads (Total: 4)

| Thread | Interval | Purpose |
|---|---|---|
| XP flush | 60s | Batch-write pending XP |
| Tree respawn tick | 120s | Check respawnable trees |
| Export rotation check | 3,600s | Weekly multiplier rotation |
| Contract generation | 1,800s | Generate new contracts |

## 13.2 Client Threads (Per-Player)

| Thread | When Active | Interval |
|---|---|---|
| Winded recovery | Only while winded (â‰¤8s) | 200ms |
| Winded sprint block | Only while winded (â‰¤8s) | 0ms |
| Bee swarm DoT | Only during swarm (â‰¤20s) | 3,000ms |

**At rest (not doing forestry work): zero client threads.**

## 13.3 Network Traffic

| Event | Direction | Frequency |
|---|---|---|
| Felling validation | Client â†’ Server (callback) | Per tree (~30s between) |
| Tree felled broadcast | Server â†’ All Clients | Per fell |
| Tree respawn broadcast | Server â†’ All Clients | Every 2min (batch) |
| TIMBER warning | Server â†’ Nearby (12m) | Per fell |
| Event trigger | Server â†’ Single Client | ~16.5% of fells |
| Crew roster | Server â†’ Crew Members | On changes |

No per-frame network traffic. Heaviest moment: tree-felled broadcast (~100 bytes).

## 13.4 Scaling (200 Players, 50 Active Loggers)

| Metric | Value |
|---|---|
| Trees felled/min | ~100 |
| Server callbacks/min | ~200 |
| DB writes/min | ~4 (batched XP) + ~100 (felled trees) |
| Memory: crew state | ~50KB |
| Memory: felled tree cache | ~200KB |
| Memory: pending XP | ~5KB |

---

# 14. SECURITY MODEL

Every client action passes through server validation.

**Felling validation chain:**
1. Player exists and loaded
2. Has lumberjack job, on duty
3. Has valid chopping tool (inventory search)
4. Has valid timber permit (DB query)
5. Tree not already felled (cache check)
6. Within interaction distance
7. Not on felling cooldown
8. Tool has sufficient durability
9. Tool has fuel (if chainsaw)

**Anti-exploit measures:**
- Client never specifies quantities, XP, or prices. Server calculates all.
- Distance checks on every spatial interaction.
- Per-player per-action cooldown tracking.
- Atomic tool/fuel deductions with item grants (no duplication window).
- Crew XP multiplier server-calculated from server-side state.

**Server Callbacks:**

| Callback | Purpose |
|---|---|
| `forestry:player:getData` | Return player level/XP/licenses |
| `forestry:felling:validate` | Authorize felling |
| `forestry:felling:complete` | Process fell results |
| `forestry:processing:validate` | Authorize limbing/bucking |
| `forestry:sawmill:validate` | Authorize station use |
| `forestry:transport:getLoadDuration` | Crew-adjusted load speed |
| `forestry:crafting:validate` | Authorize crafting |
| `forestry:economy:sell` | Process sale |
| `forestry:economy:getContracts` | Return active contracts |
| `forestry:economy:fulfillContract` | Complete contract |
| `forestry:permit:purchase` | Buy permit |
| `forestry:permit:check` | Validate permit |
| `forestry:crosscut:initiate` | Start/join crosscut session |
| `forestry:crew:create` | Create crew |
| `forestry:crew:invite` | Invite to crew |
| `forestry:crew:setRole` | Assign role |
| `forestry:oldtimer:getMarket` | Market snapshot for NPC |

---

# 15. COMPLETE CONFIGURATION REFERENCE

## 15.1 config/shared.lua

```lua
Config = {}

-- TREE SPECIES
Config.TreeSpecies = {
    pine     = { label = 'Pine',    models = { `prop_tree_pine_01`, `prop_tree_pine_02`, `prop_tree_cedar_01`, `prop_tree_cedar_02`, `prop_tree_cedar_03`, `prop_tree_cedar_04` }, size = 'large',  hardness = 0.4, baseYield = 4, baseValue = 50 },
    oak      = { label = 'Oak',     models = { `prop_tree_oak_01`, `prop_tree_eng_oak_01` }, size = 'medium', hardness = 0.8, baseYield = 3, baseValue = 120 },
    birch    = { label = 'Birch',   models = { `prop_tree_birch_01`, `prop_tree_birch_02`, `prop_tree_birch_03`, `prop_tree_birch_04` }, size = 'small', hardness = 0.3, baseYield = 2, baseValue = 40 },
    redwood  = { label = 'Redwood', models = { `prop_tree_log_01`, `prop_s_pine_dead_01` }, size = 'large',  hardness = 0.6, baseYield = 6, baseValue = 200 },
    cedar    = { label = 'Cedar',   models = { `prop_tree_cedar_s_01`, `prop_tree_cedar_s_04` }, size = 'medium', hardness = 0.5, baseYield = 3, baseValue = 90 },
    maple    = { label = 'Maple',   models = { `prop_tree_maple_02`, `prop_tree_maple_03` }, size = 'medium', hardness = 0.9, baseYield = 3, baseValue = 130 },
}

Config.ModelToSpecies = {} -- Built at load from above

-- SKILL CHECKS
Config.SkillCheck = {
    small  = { 'easy', 'easy' },
    medium = { 'easy', 'medium', 'easy' },
    large  = { 'medium', 'medium', 'hard' },
    crosscut = { 'easy', 'medium' },
    crosscutRounds = 3,
    headsaw = { 'medium' }, edger = { 'easy' }, planer = { 'easy' },
    veneer = { 'hard' }, plywood = { 'medium' }, specialty = { 'hard' },
    debarker = {}, crosscut_station = { 'easy' },
}

-- PROGRESSION
Config.Progression = {
    XPFormula = 1.5, XPPerLevel = 100,
    MaxForestryLevel = 50, MaxWoodworkingLevel = 30,
    ForestryXP = {
        fell_small = 8, fell_medium = 15, fell_large = 25,
        limb = 3, buck = 5, carry_log = 2, load_log = 2,
        sawmill_station = 10, plant_sapling = 15, contract_complete = 50,
    },
    WoodworkingXP = {
        craft_level0 = 10, craft_level5 = 15, craft_level10 = 25,
        craft_level15 = 35, craft_level20 = 50, craft_level25 = 75,
    },
}

-- TOOLS
Config.Tools = {
    hatchet     = { treeSizes = { 'small' },                   maxDurability = 50,  fellingTime = 12000 },
    felling_axe = { treeSizes = { 'small', 'medium' },         maxDurability = 80,  fellingTime = 18000 },
    crosscut_saw = { treeSizes = { 'small', 'medium', 'large' }, maxDurability = 60, fellingTime = 18000, requiresCert = 'crosscut_cert', requiresPartner = true },
    chainsaw    = { treeSizes = { 'small', 'medium', 'large' }, maxDurability = 100, fellingTime = 10000, requiresCert = 'chainsaw_cert', fuelPerUse = 1, maxFuel = 25 },
    FuelPerCanister = 5, MaxFuel = 25, SharpenAmount = 50,
}

-- TREE SIZES
Config.TreeSizes = {
    small  = { label = 'Small',  respawnMinutes = 60 },
    medium = { label = 'Medium', respawnMinutes = 120 },
    large  = { label = 'Large',  respawnMinutes = 240 },
}
```

## 15.2 config/client.lua

```lua
-- STAMINA
Config.Stamina = {
    BaseSwings = 12, SwingsPerLevel = 0.6, MaxSwings = 50,
    WindedDuration = 8000,
    SeatedRecoveryMultiplier = 2.5, LyingRecoveryMultiplier = 3.5,
    WarningThreshold = 3,
}

-- TIMBER WARNING
Config.TimberWarning = { Radius = 12.0, Duration = 3000, Sound = true, DirectionalIndicator = false }

-- INJURY
Config.Injury = {
    CrushZoneRadius = 3.0, CrushDamage = { min = 65, max = 90 }, CrushRagdoll = 2000,
    ChainsawKickback = { min = 5, max = 10 }, DroppedLog = 5,
}

-- CARRY & MOVEMENT
Config.CarrySpeedModifiers = { short_log = 0.85, standard_log = 0.65, branch_bundle = 0.90, hand_cart = 0.70 }

-- LOG PROPS
Config.LogProps = {
    short    = { model = `prop_logpile_04`, carryOffset = { bone = 57005, x = 0.1, y = 0.0, z = 0.0, rx = 90.0, ry = 0.0, rz = 0.0 } },
    standard = { model = `prop_log_01`,     carryOffset = { bone = 24818, x = 0.3, y = 0.1, z = 0.1, rx = 80.0, ry = 10.0, rz = 0.0 } },
    long     = { model = `prop_logpile_01`, carryOffset = nil },
}

-- VEHICLE LOG SLOTS
Config.VehicleLogSlots = {
    flatbed = { maxLogs = 20, positions = { --[[ vec3 offsets ]] } },
    pickup  = { maxLogs = 6,  positions = { --[[ vec3 offsets ]] } },
}

-- PARTICLES
Config.Particles = { MaxActiveLooped = 3, MaxActiveOneshot = 10, CullDistance = 50.0 }

-- CLOTHING
Config.Clothing = {
    AutoDress = true, AllowCustom = true,
    Outfits = {
        male   = { [3] = { drawable = 4, texture = 0 }, [4] = { drawable = 35, texture = 0 }, [6] = { drawable = 25, texture = 0 }, [8] = { drawable = 15, texture = 0 }, [0] = { drawable = 45, texture = 0, prop = true } },
        female = { [3] = { drawable = 7, texture = 0 }, [4] = { drawable = 30, texture = 0 }, [6] = { drawable = 25, texture = 0 }, [8] = { drawable = 3, texture = 0 },  [0] = { drawable = 45, texture = 0, prop = true } },
    },
}

-- CAMP SPOTS
Config.CampSpots = {
    { label = 'Logger Camp - Paleto', coords = vec3(-550.0, 5320.0, 70.0),
      props = { { model = `prop_bench_05`, offset = vec3(0,0,0), heading = 180.0 }, { model = `prop_bbq_3`, offset = vec3(2.0,0,0), heading = 90.0 } },
      blip = { sprite = 436, color = 69, scale = 0.5, label = 'Logger Camp' }, renderDistance = 50.0 },
}

-- OLD TIMER
Config.OldTimer = {
    Enabled = true,
    Locations = { { model = 's_m_y_construct_01', coords = vec4(-545.0, 5325.0, 70.0, 150.0), scenario = 'WORLD_HUMAN_SMOKING' } },
}
```

## 15.3 config/server.lua

```lua
-- EVENTS
Config.Events = {
    Enabled = true, RollChanceBase = 1000,
    Events = { { name = 'widow_maker', enabled = true, chance = 100 }, { name = 'bee_swarm', enabled = true, chance = 65 } },
}
Config.Events.WidowMaker = { enabled = true, chance = 100, treeSizes = { 'medium', 'large' }, skillCheck = { 'hard' }, damage = { min = 40, max = 65 }, bonusXP = 10, staggerDuration = 1500 }
Config.Events.BeeSwarm = { enabled = true, chance = 65, duration = 20000, tickDamage = 2, tickInterval = 3000, speedDebuff = 0.8, escapeDistance = 30.0, smokeItem = 'smoke_canister', bonusItem = 'honeycomb', bonusAmount = { 1, 3 } }

-- TREE RESPAWN
Config.RespawnCheckInterval = 120000

-- CREW
Config.Crew = {
    MaxMembers = 8, InviteDistance = 10.0,
    XPBonusPerMember = 0.10, XPBonusCap = 0.40, ActivityWindow = 300000,
    SharedStashSlots = 50, SharedStashWeight = 200000, StashCleanupDelay = 1800000,
    AutoRadio = true, RadioResource = 'pma-voice',
}

-- FORESTRY OFFICE
Config.ForestryOffice = {
    Locations = { { label = 'Paleto Forestry Office', coords = vec3(-530.0, 5400.0, 37.0),
        npc = { model = 's_m_y_ranger_01', coords = vec4(-530.0, 5400.0, 37.0, 180.0) },
        blip = { sprite = 480, color = 69, scale = 0.7, label = 'Forestry Office' } } },
    Shop = {
        { item = 'hatchet', price = 150 }, { item = 'felling_axe', price = 400 },
        { item = 'crosscut_saw', price = 600, requiresCert = 'crosscut_cert' },
        { item = 'chainsaw', price = 1200, requiresCert = 'chainsaw_cert' },
        { item = 'chainsaw_fuel', price = 50 }, { item = 'sharpening_kit', price = 75 },
        { item = 'portable_sawmill', price = 3500 }, { item = 'tree_sapling', price = 25 },
        { item = 'smoke_canister', price = 30 }, { item = 'log_chute_kit', price = 2000 },
        { item = 'wood_finish', price = 100 }, { item = 'clock_mechanism', price = 500 },
    },
    PermitPrice = 500, PermitDurationDays = 7,
}

-- GENERAL STORE
Config.GeneralStore = {
    Items = { branch_bundle = 20, firewood_bundle = 40, sawdust = 5, wood_chips = 8, wood_pellets = 25, bark_mulch = 30, honeycomb = 45 },
}

-- LUMBER BUYER
Config.LumberBuyer = {
    Locations = { { label = 'Paleto Lumber Buyer', coords = vec3(-540.0, 5415.0, 37.0),
        npc = { model = 's_m_y_construct_02', coords = vec4(-540.0, 5415.0, 37.0, 90.0) } } },
    BasePrices = { lumber_rough = 30, lumber_edged = 50, lumber_finished = 80, veneer_sheet = 60, plywood_sheet = 120, specialty_cut = 150, turpentine = 60 },
}

-- FURNITURE BUYER
Config.FurnitureBuyer = {
    Locations = { { label = 'Paleto Furniture Store', coords = vec3(-525.0, 5420.0, 37.0),
        npc = { model = 'a_f_y_business_02', coords = vec4(-525.0, 5420.0, 37.0, 270.0) } } },
}

-- CONTRACTS
Config.Contracts = {
    MaxActive = 8, GenerationInterval = 1800000,
    PremiumMultiplier = { min = 1.3, max = 2.0 }, DeadlineHours = { min = 24, max = 72 },
    PossibleItems = { 'lumber_finished', 'plywood_sheet', 'veneer_sheet', 'specialty_cut', 'firewood_bundle' },
    QuantityRange = { min = 5, max = 30 },
}

-- EXPORT DOCKS
Config.LumberExport = { Location = vec3(-200.0, 6200.0, 30.0), RotationIntervalHours = 168, MultiplierRange = { min = 0.7, max = 2.5 } }
Config.FurnitureExport = {
    Location = vec3(-210.0, 6205.0, 30.0), RotationIntervalHours = 168,
    Categories = {
        seating   = { items = {'furniture_chair_oak','furniture_stool','furniture_bench_cedar'}, multiplierRange = { min = 1.0, max = 2.0 } },
        tables    = { items = {'furniture_table_oak','furniture_desk_maple','furniture_sidetable_birch','furniture_nightstand_maple'}, multiplierRange = { min = 1.0, max = 2.2 } },
        storage   = { items = {'furniture_chest_cedar','furniture_cabinet_birch','furniture_wardrobe_pine','furniture_shelf_pine'}, multiplierRange = { min = 0.8, max = 1.8 } },
        specialty = { items = {'furniture_trophy_redwood','furniture_clock_oak'}, multiplierRange = { min = 1.5, max = 3.0 } },
        utility   = { items = {'furniture_crate','furniture_fence_panels'}, multiplierRange = { min = 0.8, max = 1.5 } },
    },
}

-- MARKET DYNAMICS
Config.Market = { SupplyDecayPerHour = 5, SupplyPerSale = 1, PriceFloor = 0.5, PriceCeiling = 1.5 }

-- SAWMILLS
Config.Sawmills = {
    { id = 'paleto_sawmill', label = 'Paleto Community Sawmill', tier = 2,
      blip = { sprite = 566, color = 47, scale = 0.8, label = 'Sawmill' },
      stations = {
          { id = 'debarker', label = 'Debarker', coords = vec3(-537.0, 5403.0, 37.0), levelReq = 0 },
          { id = 'headsaw', label = 'Head Saw', coords = vec3(-535.0, 5405.0, 37.0), levelReq = 5 },
          { id = 'edger', label = 'Edger', coords = vec3(-533.0, 5405.0, 37.0), levelReq = 5 },
          { id = 'planer', label = 'Planer', coords = vec3(-531.0, 5405.0, 37.0), levelReq = 10 },
          { id = 'crosscut_station', label = 'Crosscut', coords = vec3(-529.0, 5405.0, 37.0), levelReq = 5 },
          { id = 'veneer', label = 'Veneer Slicer', coords = vec3(-527.0, 5403.0, 37.0), levelReq = 20 },
          { id = 'plywood', label = 'Plywood Press', coords = vec3(-525.0, 5403.0, 37.0), levelReq = 25 },
          { id = 'specialty', label = 'Specialty Saw', coords = vec3(-523.0, 5403.0, 37.0), levelReq = 30 },
      },
      throughputBonus = 0.15, throughputBonusCap = 0.60,
      furnitureWorkshop = vec3(-521.0, 5401.0, 37.0),
    },
}

-- TRANSPORT
Config.Transport = { LoadDurationPerLog = 4000, LoadDurationCrew2 = 2500, LoadDurationCrew3 = 1500, CrewLoadProximity = 5.0 }

-- LOG CHUTES
Config.LogChutes = {
    { id = 'paleto_chute_north', label = 'North Ridge Chute',
      sendPoint = vec3(-800.0, 5500.0, 90.0), collectionPoint = vec3(-780.0, 5420.0, 38.0),
      slideTime = 8000, maxLogsPerSend = 3,
      blip = { send = { sprite = 479, color = 47, scale = 0.6, label = 'Log Chute (Send)' },
               collect = { sprite = 479, color = 25, scale = 0.6, label = 'Log Chute (Collect)' } } },
}

-- FURNITURE RECIPES
Config.FurnitureRecipes = {
    { item = 'furniture_crate',            level = 0,  ingredients = { lumber_rough = 4 }, price = 150 },
    { item = 'furniture_fence_panels',     level = 0,  ingredients = { lumber_finished = 6 }, price = 400 },
    { item = 'furniture_stool',            level = 5,  ingredients = { lumber_finished = 2, wood_finish = 1 }, price = 250 },
    { item = 'furniture_shelf_pine',       level = 5,  ingredients = { lumber_finished = 4, wood_finish = 1 }, species = 'pine', price = 600 },
    { item = 'furniture_chair_oak',        level = 10, ingredients = { lumber_finished = 3, wood_finish = 1 }, species = 'oak', price = 500 },
    { item = 'furniture_chest_cedar',      level = 10, ingredients = { lumber_finished = 5, wood_finish = 2 }, species = 'cedar', price = 900 },
    { item = 'furniture_sidetable_birch',  level = 10, ingredients = { lumber_finished = 2, wood_finish = 1 }, species = 'birch', price = 450 },
    { item = 'furniture_table_oak',        level = 15, ingredients = { lumber_finished = 6, wood_finish = 2 }, species = 'oak', price = 1200 },
    { item = 'furniture_wardrobe_pine',    level = 15, ingredients = { lumber_finished = 6, wood_finish = 2 }, species = 'pine', price = 850 },
    { item = 'furniture_nightstand_maple', level = 15, ingredients = { lumber_finished = 3, wood_finish = 1 }, species = 'maple', price = 700 },
    { item = 'furniture_desk_maple',       level = 20, ingredients = { lumber_finished = 8, wood_finish = 3 }, species = 'maple', price = 1800 },
    { item = 'furniture_cabinet_birch',    level = 20, ingredients = { lumber_finished = 5, veneer_sheet = 2 }, species = 'birch', price = 1100 },
    { item = 'furniture_bench_cedar',      level = 20, ingredients = { lumber_finished = 4, wood_finish = 1 }, species = 'cedar', price = 750 },
    { item = 'furniture_trophy_redwood',   level = 25, ingredients = { lumber_finished = 4, specialty_cut = 1 }, species = 'redwood', price = 2500 },
    { item = 'furniture_clock_oak',        level = 25, ingredients = { lumber_finished = 6, specialty_cut = 2, clock_mechanism = 1 }, species = 'oak', price = 3500 },
}

-- WOODWORKING BONUSES
Config.WoodworkingBonuses = {
    [8]  = { craftTimeReduction = 0.10 },
    [14] = { materialSaveChance = 0.05 },
    [20] = { craftTimeReduction = 0.10 },
    [26] = { materialSaveChance = 0.10 },
    [30] = { masterLabel = true },
}

-- BULLETIN BOARD
Config.BulletinBoard = { RefreshInterval = 1800000 }

-- LOGGING (optional Discord webhooks)
Config.Logging = {
    Enabled = false, WebhookURL = '',
    Events = { largeSale = true, contractComplete = true, exportSale = true, levelUp = true },
    LargeSaleThreshold = 5000,
}

-- FOOD ITEMS (recognized for stamina recovery context)
Config.FoodItems = { sandwich = true, burger = true, water = true, coffee = true, energy_bar = true }
```

---

# END OF MASTER REFERENCE

**Document Version:** FINAL (consolidated v1â€“v8)
**Total Items:** 49 unique ox_inventory items
**Total DB Tables:** 7
**Server Threads:** 4 (all â‰¥60s interval)
**Client Idle Threads:** 0

All systems fully specified. Ready for implementation.
