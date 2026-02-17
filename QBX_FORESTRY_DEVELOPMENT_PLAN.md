# 🪓 QBX FORESTRY — DEVELOPMENT STATUS & COMPLETION PLAN
### Audit Date: February 17, 2026
### Compared Against: MASTER DESIGN REFERENCE (v1–v8 Consolidated)

---

## EXECUTIVE SUMMARY

The project has **11 of 22 required code files** written. The existing files are well-structured and follow the master reference closely, but they depend on **11 missing files** that contain critical functions referenced hundreds of times across the existing codebase. No file is runnable in its current state — the resource will error on startup because missing functions (`AddForestryXP`, `ForestryUtils.*`, `IsTreeFelled`, `GrantItem`, etc.) are called but never defined.

**Estimated completion:** ~3,500–4,000 additional lines of code across 11 files + 2 missing server callbacks.

| Category | Files Expected | Files Written | Status |
|---|---|---|---|
| Resource Manifest | 1 | 1 | ✅ Complete |
| SQL Schema | 1 | 1 | ✅ Complete |
| Configuration (3-layer) | 3 | 1 | ⚠️ 1 of 3 written (shared only) |
| Shared Utilities | 2 | 0 | ❌ Both missing |
| Server Scripts | 8 | 3 | ⚠️ 3 of 8 written |
| Client Scripts | 9 | 6 | ⚠️ 6 of 9 written |
| **TOTAL** | **24** | **12** | **50% file count / ~55% line count** |

---

## SECTION 1 — WHAT EXISTS (12 Files)

### ✅ Fully Functional Files
| File | Lines | Notes |
|---|---|---|
| `fxmanifest.lua` | 34 | Complete, correct dependencies |
| `install.sql` | 89 | All 7 tables + seed data |

### ⚠️ Complete Logic — But Missing Dependencies
These files are architecturally complete but **will not run** because they call functions defined in missing files.

| File | Lines | Role | Critical Missing Dependencies |
|---|---|---|---|
| `shared.lua` | 294 | Config: species, tools, skill checks, progression | Needs to move to `config/shared.lua` path |
| `main.lua` | 273 | Server: player lifecycle, usable items | `FlushPlayerXP()`, `ForestryUtils.LevelFromXP()`, `RemovePlayerFromCrew()`, `FORESTRY_JOB` constant |
| `callbacks.lua` | 523 | Server: all `lib.callback.register()` | `HasValidPermit()`, `IsTreeFelled()`, `FindChoppingTool()`, `FindSpecificTool()`, `DeductToolDurability()`, `DeductChainsawFuel()`, `RecordFelledTree()`, `AddForestryXP()`, `IncrementStat()`, `RollForEvent()`, `GrantItem()`, `GrantLogs()`, `ForestryUtils.*` (6+ functions), `FORESTRY_JOB` constant |
| `economy.lua` | 646 | Server: 7 sale channels, contracts, exports, market | `FORESTRY_JOB`, `GetCitizenId()` ✅ (in main), `IncrementStat()`, `AddForestryXP()`, `ForestryLog()` |
| `felling.lua` | 492 | Client: tree targeting, directional felling, skill checks, fall animation, crush zone, widow maker, bee swarm | `PlayerState.*`, `FelledTreeCache`, `ForestryUtils.*` (5+ functions), `IsWinded()`, `ConsumeSwing()`, `StartFellingAudio()`, `StopFellingAudio()`, `PlayTreeCreak()`, `PlayTreeFallSound()`, `SpawnChopParticle()`, `ApplyChainsawKickback()`, `RegisterProcessingTarget()` |
| `crew.lua` | 367 | Client: crew UI, invites, roles, radio | `PlayerState.*`, `CrewRole.*` enum, `CheckStamina()` |
| `immersion.lua` | 900 | Client: Old Timer NPC, camps, bulletin board, office, sell NPCs, contract board, export docks | `PlayerState.*`, `FormatNumber()` (self-contained ✅), `Config.ForestryOffice.*`, `Config.LumberBuyer.*`, `Config.FurnitureBuyer.*`, `Config.LumberExport.*`, `Config.FurnitureExport.*` |
| `sawmill.lua` | 653 | Client: Tier 1 + Tier 2 sawmill, 8 stations, personal bonuses | `PlayerState.*`, `ConsumeSwing()`, `StartStationAudio()` (self-contained ✅) |
| `transport.lua` | 521 | Client: log carry, vehicle loading, chutes | `PlayerState.*`, `CarryState` (global), `ConsumeSwing()`, `Config.LogTypes.*`, `Config.LogProps.*`, `RegisterLogPropTarget()` |
| `crafting.lua` | 278 | Client: furniture + secondary crafting | `PlayerState.*`, `Config.FurnitureRecipes`, `Config.WoodworkingBonuses` |

---

## SECTION 2 — WHAT'S MISSING (11 Files + 2 Callbacks)

### 🔴 PRIORITY 1 — Shared Foundation (Blocks Everything)

These must be created first — every other file depends on them.

#### File 1: `shared/enums.lua`
**~40 lines** | All files reference these enums

```
Defines: TreeSize, LogQuality, LogLength, CrewRole + labels
Referenced by: callbacks.lua, felling.lua, economy.lua, crew.lua
```

#### File 2: `shared/utils.lua`
**~200 lines** | The most-referenced missing file in the entire project

```
Functions needed:
  ForestryUtils.TreeKey(modelHash, coords)          → "hash:x:y:z" composite key
  ForestryUtils.XPForLevel(level)                   → math.floor(100 * level^1.5)
  ForestryUtils.LevelFromXP(totalXP, maxLevel)      → current level from cumulative XP
  ForestryUtils.GetSpeciesFromModel(modelHash)       → speciesKey, speciesData
  ForestryUtils.CanToolFellSize(toolName, treeSize)  → boolean
  ForestryUtils.GetFellingSkillCheck(treeSize)       → skill check pattern table
  ForestryUtils.GetFallDirection(playerPos, treePos) → normalized direction vector
  ForestryUtils.DirectionToHeading(direction)        → GTA heading float
  ForestryUtils.DistanceToLineSegment(point, a, b)   → perpendicular distance

Referenced by: main.lua, callbacks.lua, felling.lua, economy.lua, immersion.lua
```

---

### 🔴 PRIORITY 2 — Server Core Systems (Blocks Gameplay)

These files contain functions called by `callbacks.lua` and `economy.lua`. Without them, no server callback completes successfully.

#### File 3: `server/progression.lua`
**~200 lines** | XP engine

```
Functions needed:
  AddForestryXP(source, amount)          → accumulate + check level-up
  AddWoodworkingXP(source, amount)       → accumulate + check level-up
  FlushPlayerXP(citizenid)               → write pending XP to DB
  IncrementStat(citizenid, key, amount?) → update statistics JSON
  GetCrewXPMultiplier(source)            → 1.0 + crew bonus

Threads:
  XP flush thread (60s interval) — batched writes per master reference §5.8

Referenced by: main.lua, callbacks.lua, economy.lua
```

#### File 4: `server/trees.lua`
**~150 lines** | Tree state management

```
Functions needed:
  IsTreeFelled(treeKey)                            → boolean from cache
  RecordFelledTree(treeKey, modelHash, treeSize)   → DB insert + cache update
  GetFelledTreeCache()                             → full set for client sync
  PlantSapling(source, treeKey)                    → set respawns_at = NOW()

Threads:
  Tree respawn tick (120s interval) — per master reference §4, Stage 1

Events:
  forestry:server:timberWarning        → broadcast to nearby players
  forestry:server:requestFelledCache   → send cache to joining client

Referenced by: callbacks.lua, felling.lua (via events)
```

#### File 5: `server/inventory.lua`
**~250 lines** | Item management

```
Functions needed:
  FindChoppingTool(source)                    → {name, slot, metadata, toolData} or nil, errorReason
  FindSpecificTool(source, toolName)          → same as above, specific tool
  DeductToolDurability(source, toolInfo, amt) → reduce durability, break at 0
  DeductChainsawFuel(source, toolInfo, amt)   → reduce fuel metadata
  HasValidPermit(source)                      → DB check expires_at > NOW()
  GrantItem(source, item, count, metadata?)   → ox_inventory:AddItem wrapper
  GrantLogs(source, logType, species, quality, count) → AddItem with metadata

Constants:
  FORESTRY_JOB = 'lumberjack'                → referenced in 4+ files

Referenced by: main.lua, callbacks.lua
```

#### File 6: `server/crew.lua`
**~300 lines** | Crew state machine

```
Functions needed:
  CreateCrew(source)                            → generate crewId, init state
  InviteToCrew(source, targetSource)            → validate + trigger client invite
  SetCrewRole(source, targetSource, role)       → update role in state
  RemovePlayerFromCrew(source, reason)          → remove + transfer leadership
  GetCrewMembersNearPlayer(source, radius)      → count nearby crew members
  KickFromCrew(leaderSource, targetSource)      → leader-only removal
  GetCrewXPMultiplier(source)                   → 1.0 + 0.10 per active member (cap 0.40)

State:
  Crews = {}          → crewId → { leader, members[], stashId, createdAt }
  PlayerCrews = {}    → source → crewId

Events:
  forestry:server:crew:acceptInvite
  forestry:server:crew:leave
  forestry:server:crew:kick

Stash management:
  Register ox_inventory stash per crew (50 slots, 200kg)
  Cleanup 30 min after disband

Referenced by: main.lua, callbacks.lua, transport.lua (via crew load bonus)
```

#### File 7: `server/events.lua`
**~100 lines** | Random event roller

```
Functions needed:
  RollForEvent(source, treeSize)        → nil or {name, skillCheck, damage, ...}

Events:
  forestry:server:widowMaker:result     → award dodge XP or log damage
  forestry:server:beeSwarm:escaped      → clear bee state
  forestry:server:beeSwarm:ended        → clear bee state

Referenced by: callbacks.lua (felling:complete), felling.lua (event handlers)
```

#### File 8: `server/logging.lua`
**~50 lines** | Optional Discord webhooks

```
Functions needed:
  ForestryLog(eventType, title, description, color) → PerformHttpRequest to webhook

Referenced by: economy.lua (large sales, contracts, exports)
```

---

### 🟡 PRIORITY 3 — Client Support Systems (Blocks Full Experience)

#### File 9: `client/main.lua`
**~300 lines** | Client entry point — **THE** most critical client file

```
Must define:
  PlayerState = { loaded, onDuty, forestryLevel, woodworkingLevel, ... }
  FelledTreeCache = {}    → set of tree keys, synced from server
  CarryState = nil        → global carry tracking (used by transport.lua)

Must implement:
  - ox_target:addModel() for ALL tree models from Config.AllTreeModels
  - Job clock-in/clock-out (clothing swap, state toggle, blip creation)
  - onResourceStart init (request felled cache, setup blips)
  - QBCore:Client:OnJobUpdate handler
  - Level-gated ox_target label text (species ID per §4 Stage 1)
  - Felled tree cache sync event handler
  - Tree respawn event handler (re-show entity)

Referenced by: literally every client file via PlayerState.* and FelledTreeCache
```

#### File 10: `client/processing.lua`
**~200 lines** | Limbing & bucking

```
Functions needed:
  RegisterProcessingTarget(coords, species, quality, yield, size)
    → temporary ox_target at felled tree for limbing + bucking
  Limbing flow: progress bar → server callback → branch bundles
  Bucking flow: lib.inputDialog for cut length → server callback → logs granted
  Log prop spawning after bucking (ground props near stump)
  RegisterLogPropTarget(id, prop, logType, species)
    → ox_target on ground log prop for pickup → StartCarry()

Referenced by: felling.lua (PromptFieldProcessing calls RegisterProcessingTarget)
```

#### File 11: `client/stamina.lua`
**~120 lines** | Swing counter system

```
Functions needed:
  InitStamina(forestryLevel)      → calculate max swings
  ConsumeSwing()                  → return true/false, trigger winded if 0
  IsWinded()                      → boolean
  CheckStamina()                  → notify current swings remaining
  RefreshStamina(forestryLevel)   → recalc on level-up

Winded state:
  - Heavy breathing animation
  - Sprint block (Wait(0) loop, only while winded)
  - Recovery timer (200ms poll, 3-8s based on seated/standing/lying)
  - Warning at 3 swings remaining

Referenced by: felling.lua, transport.lua, sawmill.lua (via ConsumeSwing/IsWinded)
```

#### File 12: `client/effects.lua`  *(Optional but heavily referenced)*
**~200 lines** | Audio, particles, camera

```
Functions needed:
  StartFellingAudio(toolName, entity)
  StopFellingAudio()
  PlayTreeCreak(coords)
  PlayTreeFallSound(coords)
  PlayTreeImpactSound(coords)
  SpawnChopParticle(coords)
  ApplyChainsawKickback()

All use GTA V native PlaySound*/UseParticleFxAsset. 
If omitted, gameplay works but is silent/visually flat.
The existing felling.lua wraps all calls in `if StartFellingAudio then` guards,
so this file is not strictly required for startup, but the experience suffers.

Referenced by: felling.lua, sawmill.lua
```

---

### 🟡 PRIORITY 4 — Missing Config Files

#### File 13: `config/client.lua`
**~180 lines** | Already designed in master reference §15.2

Contains: Stamina tuning, timber warning, injury values, carry speed modifiers, log props, vehicle slots, particles, camera effects, audio distances, clothing, fall indicator, camp spots, Old Timer NPC locations, interaction distances.

**Note:** Much of this config is referenced by existing client files but currently undefined. The `Config.Stamina.*`, `Config.Injury.*`, `Config.LogProps.*`, `Config.CarrySpeedModifiers.*`, `Config.Clothing.*`, `Config.CampSpots.*`, `Config.OldTimer.*` tables are all read by immersion.lua, transport.lua, felling.lua, etc.

#### File 14: `config/server.lua`
**~250 lines** | Already designed in master reference §15.3

Contains: Events config, crew config, forestry office (shop + permit), general store, lumber buyer, furniture buyer, contracts, export docks, sawmill locations, transport, log chutes, furniture recipes, woodworking bonuses, market dynamics, bulletin board, logging, sell cooldowns.

**Note:** `Config.ForestryOffice.*`, `Config.Events.*`, `Config.Crew.*`, `Config.Contracts.*`, etc. are all referenced by existing files but undefined.

---

### 🟠 Missing Server Callbacks (in existing `callbacks.lua`)

Two callbacks are called from client files but never registered:

| Callback | Called By | Purpose |
|---|---|---|
| `forestry:sawmill:complete` | sawmill.lua line 449 | Process station output, grant items, award XP |
| `forestry:crafting:complete` | crafting.lua line 204 | Validate ingredients, remove inputs, grant furniture, award WW XP |
| `forestry:crafting:completeSecondary` | crafting.lua line 263 | Validate + process secondary recipes |

These should be added to `callbacks.lua` once `server/inventory.lua` and `server/progression.lua` exist.

---

## SECTION 3 — DEPENDENCY GRAPH

```
shared/enums.lua ──────────────────┐
shared/utils.lua ──────────────────┤
                                   ▼
                        ┌──────────────────────┐
                        │  config/shared.lua    │ (exists as shared.lua)
                        │  config/client.lua    │ ❌ MISSING
                        │  config/server.lua    │ ❌ MISSING
                        └──────────┬───────────┘
                                   │
               ┌───────────────────┼───────────────────┐
               ▼                   ▼                   ▼
    ┌─────────────────┐ ┌──────────────────┐ ┌─────────────────┐
    │ SERVER LAYER    │ │ CLIENT LAYER     │ │ DATABASE        │
    │                 │ │                  │ │                 │
    │ main.lua     ✅ │ │ main.lua      ❌ │ │ install.sql  ✅ │
    │ inventory.lua ❌ │ │ felling.lua   ✅ │ └─────────────────┘
    │ progression.lua❌│ │ processing.lua ❌│
    │ trees.lua    ❌ │ │ transport.lua ✅ │
    │ crew.lua     ❌ │ │ sawmill.lua   ✅ │
    │ events.lua   ❌ │ │ crafting.lua  ✅ │
    │ economy.lua  ✅ │ │ crew.lua      ✅ │
    │ callbacks.lua ✅ │ │ stamina.lua   ❌ │
    │ logging.lua  ❌ │ │ effects.lua   ❌ │
    └─────────────────┘ │ immersion.lua ✅ │
                        └──────────────────┘
```

**Legend:** ✅ Written  ❌ Missing

---

## SECTION 4 — RECOMMENDED BUILD ORDER

### Phase A — Foundation (Must Be First)
| Step | File | Est. Lines | Why First |
|---|---|---|---|
| A1 | `shared/enums.lua` | 40 | Enums referenced everywhere |
| A2 | `shared/utils.lua` | 200 | `ForestryUtils.*` called in 6+ files |
| A3 | `config/client.lua` | 180 | Client files read Config.Stamina, Config.Injury, etc. |
| A4 | `config/server.lua` | 250 | Server files read Config.Events, Config.Crew, Config.ForestryOffice, etc. |

### Phase B — Server Core (Unblocks Callbacks)
| Step | File | Est. Lines | Unblocks |
|---|---|---|---|
| B1 | `server/inventory.lua` | 250 | Every felling/processing callback |
| B2 | `server/progression.lua` | 200 | XP grants in all callbacks + economy |
| B3 | `server/trees.lua` | 150 | Felling validation + respawn system |
| B4 | `server/events.lua` | 100 | Post-fell random events |
| B5 | `server/crew.lua` | 300 | Crew formation + XP bonus |
| B6 | `server/logging.lua` | 50 | Economy Discord logging |
| B7 | Add 3 missing callbacks to `callbacks.lua` | 80 | Sawmill + crafting completion |

### Phase C — Client Core (Unblocks Gameplay)
| Step | File | Est. Lines | Unblocks |
|---|---|---|---|
| C1 | `client/main.lua` | 300 | ALL client functionality (PlayerState, tree targeting, clock-in) |
| C2 | `client/stamina.lua` | 120 | Felling, transport, sawmill swing costs |
| C3 | `client/processing.lua` | 200 | Limbing + bucking after felling |
| C4 | `client/effects.lua` | 200 | Audio + particles (optional but immersive) |

### Phase D — Integration & Polish
| Step | Task | Notes |
|---|---|---|
| D1 | Move `shared.lua` → `config/shared.lua` | Path alignment with fxmanifest |
| D2 | ox_inventory items registration | 49 items in `ox_inventory/data/items.lua` |
| D3 | Job registration | `lumberjack` job in `qbx_core` shared config |
| D4 | Coordinate validation | Verify all NPC/station/camp coords in-world |
| D5 | End-to-end testing | Full loop: permit → fell → limb → buck → transport → mill → sell |

---

## SECTION 5 — ESTIMATED EFFORT

| Phase | Files | Lines | Estimated Time |
|---|---|---|---|
| Phase A | 4 files | ~670 | 1 session |
| Phase B | 6 files + edits | ~1,130 | 2 sessions |
| Phase C | 4 files | ~820 | 1–2 sessions |
| Phase D | Edits + testing | ~200 | 1 session |
| **TOTAL** | **14 deliverables** | **~2,820 lines** | **5–6 sessions** |

---

## SECTION 6 — RISK NOTES

1. **File paths:** Current files sit at project root, but `fxmanifest.lua` expects `client/*.lua`, `server/*.lua`, `shared/*.lua`, `config/*.lua` directory structure. Files must be placed in correct subdirectories.

2. **Config split:** The existing `shared.lua` at root serves as `config/shared.lua`, but there is no `config/client.lua` or `config/server.lua`. All `Config.*` values referenced by client/server files (stamina, injury, events, crew, economy, sawmills, etc.) are undefined until those config files are created.

3. **Global function scope:** Server files use Lua globals (`function ProcessSale(...)`) to share functions across files loaded by `server/*.lua` glob. This is fine for FiveM but means load order matters — `server/inventory.lua` and `server/progression.lua` must define their functions before `callbacks.lua` tries to call them. FiveM loads alphabetically, so `callbacks.lua` loads before `inventory.lua` — the existing guard pattern (`if ProcessSale then`) handles this correctly.

4. **The `FORESTRY_JOB` constant** is referenced in 4+ files but never defined. Should be placed in `shared/enums.lua` or `config/shared.lua` as `FORESTRY_JOB = 'lumberjack'`.

5. **ox_inventory items** (49 total) need to be added to the server's `ox_inventory/data/items.lua`. This is external to the resource but required for functionality.

---

**Conclusion:** The existing 12 files represent solid architectural work — callbacks, UI flows, economy logic, and game mechanics are well-designed. The missing 11 files are primarily *infrastructure* (utility functions, state management, item operations) that the existing files already assume exist. Once the foundation files in Phase A and B are built, the existing code should come to life with minimal modification.
