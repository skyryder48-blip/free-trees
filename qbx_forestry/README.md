# QBX Forestry — Current Build Package

## Status: Phase 1a Complete (12 code files + SQL)

This package contains all completed code files, organized in the directory structure
expected by `fxmanifest.lua`. See `QBX_FORESTRY_MASTER_REFERENCE.md` for the full
design specification.

## Completed Files

```
qbx_forestry/
├── fxmanifest.lua                    ✅ Resource manifest
├── sql/
│   └── install.sql                   ✅ 7 tables + seed data (89 lines)
├── config/
│   └── shared.lua                    ✅ Species, tools, skill checks, progression (294 lines)
│   ├── client.lua                    ❌ TODO — stamina, particles, clothing, carry config
│   └── server.lua                    ❌ TODO — events, crew, economy, sawmill, NPC config
├── shared/
│   ├── enums.lua                     ❌ TODO — TreeSize, LogQuality, CrewRole enums
│   └── utils.lua                     ❌ TODO — ForestryUtils (XP calc, tree keys, distance)
├── server/
│   ├── main.lua                      ✅ Player lifecycle, usable items (273 lines)
│   ├── callbacks.lua                 ✅ All lib.callback.register defs (523 lines)
│   ├── economy.lua                   ✅ 7 sale channels, contracts, exports (646 lines)
│   ├── progression.lua               ❌ TODO — XP engine, batched writes, level-up
│   ├── trees.lua                     ❌ TODO — Felled tree tracking, respawn tick
│   ├── inventory.lua                 ❌ TODO — Tool finding, durability, permits, item grants
│   ├── crew.lua                      ❌ TODO — Crew state machine, stash management
│   ├── events.lua                    ❌ TODO — Random event roller
│   └── logging.lua                   ❌ TODO — Discord webhook integration
├── client/
│   ├── main.lua                      ❌ TODO — PlayerState, tree targeting, clock-in/out
│   ├── felling.lua                   ✅ Directional felling, skill checks, crush zone (492 lines)
│   ├── processing.lua                ❌ TODO — Limbing, bucking, log prop spawning
│   ├── transport.lua                 ✅ Log carry, vehicle loading, chutes (521 lines)
│   ├── sawmill.lua                   ✅ Tier 1 + Tier 2, 8 stations, bonuses (653 lines)
│   ├── crafting.lua                  ✅ Furniture + secondary crafting (278 lines)
│   ├── crew.lua                      ✅ Crew UI, invites, roles, radio (367 lines)
│   ├── stamina.lua                   ❌ TODO — Swing counter, winded state, recovery
│   ├── effects.lua                   ❌ TODO — Audio, particles, camera effects
│   └── immersion.lua                 ✅ Old Timer NPC, camps, bulletin, shops (900 lines)
└── web/
    └── images/                       ❌ TODO — 49 item PNG icons for ox_inventory
```

## Line Count Summary

| Layer          | Complete Lines | Files |
|----------------|---------------|-------|
| Config         | 294           | 1/3   |
| SQL            | 89            | 1/1   |
| Server         | 1,442         | 3/8   |
| Client         | 3,211         | 6/9   |
| Shared         | 0             | 0/2   |
| Manifest       | 34            | 1/1   |
| **Total**      | **5,070**     | **12/24** |

## Dependencies (must be running on server)

- qbx_core
- ox_lib
- ox_target
- ox_inventory
- oxmysql

## ⚠️  This build will NOT start on a server

The completed files reference functions in the 11 missing files. The resource will
error on startup until the remaining files are created. See the Development Plan
document for the phased build order.
