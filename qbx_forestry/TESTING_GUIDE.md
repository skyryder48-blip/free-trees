# QBX Forestry — Testing Guide

A step-by-step reference for verifying every system in `qbx_forestry` after install or after changes. Run tests roughly in the order listed; later stages depend on items and XP earned in earlier ones.

---

## Prerequisites

Before testing anything in-game, confirm the environment is clean.

**Dependencies must all be running:**
- `qbx_core`
- `ox_lib`
- `ox_target`
- `ox_inventory`
- `oxmysql`

**Server console — confirm resource starts cleanly:**
```
start qbx_forestry
```
Expected output:
```
[Forestry] Resource started. Player cache initialized.
```

No output expected for these two lines (confirm the bugs from this PR are gone):
- ~~`@qbx_forestry/server/inventory.lua:59: 'end' expected`~~
- ~~`No such export RegisterUsableItem in resource ox_inventory`~~

**Database — run the install script once:**
```sql
SOURCE qbx_forestry/sql/install.sql;
```
Confirm all 7 tables exist: `forestry_players`, `forestry_permits`, `forestry_felled_trees`, `forestry_contracts`, `forestry_market`, `forestry_export_multipliers`, `forestry_furniture_export`.

**Test character setup:**
- Character with job `lumberjack` set on duty
- A second character available for co-op tests (crosscut saw, crew)
- Admin access to give items via `/giveitem` or ox_inventory admin panel

---

## 1. Resource Start & Player Cache

| Step | Action | Expected result |
|------|--------|-----------------|
| 1.1 | Start resource while a player is already online | Server console prints player cache initialized; player data loaded from DB |
| 1.2 | `restart qbx_forestry` mid-session | Same message; no Lua errors; player state restored |
| 1.3 | Log in a character with job `lumberjack` | No errors in server console |
| 1.4 | Log out the character | `PlayerBeeSwarmActive` and `FellingCooldowns` entries cleared (confirm no lingering state errors) |

---

## 2. Usable Items (Bug Fix Verification)

These four items previously failed with `No such export RegisterUsableItem`. Confirm each triggers correctly now.

### 2.1 Smoke Canister
1. Give yourself a `smoke_canister`: `/giveitem [id] smoke_canister 1`
2. Use the item with no active bee swarm.
   - **Expected:** Notification "No bee swarm to disperse."
3. Trigger a bee swarm (fell a tree and wait for the 6.5% chance event, or temporarily lower the chance in config).
4. While the swarm is active, use `smoke_canister`.
   - **Expected:** Swarm ends immediately, `smoke_canister` removed from inventory, 1–3× `honeycomb` added, success notification.

### 2.2 Chainsaw Fuel
1. Give yourself a `chainsaw` with low fuel metadata and a `chainsaw_fuel`.
2. Use `chainsaw_fuel` with no chainsaw in inventory.
   - **Expected:** Notification "You need a chainsaw to refuel."
3. Give yourself a `chainsaw` item, then use `chainsaw_fuel`.
   - **Expected:** `chainsaw_fuel` consumed, chainsaw fuel metadata increases by `Config.Tools.FuelPerCanister`, capped at `Config.Tools.MaxFuel`, success notification showing new fuel level.

### 2.3 Sharpening Kit
1. Give yourself a `sharpening_kit`.
2. Use it.
   - **Expected:** Client event `forestry:client:sharpen:selectTool` fires, tool selection UI appears.

### 2.4 Tree Sapling
1. Give yourself a `tree_sapling`.
2. Use it away from a stump.
   - **Expected:** Client event `forestry:client:sapling:startPlant` fires, proximity check runs.
3. Use it at a felled tree stump.
   - **Expected:** Sapling planted, tree respawns immediately, +15 Forestry XP, `tree_sapling` consumed.

---

## 3. Permits

| Step | Action | Expected result |
|------|--------|-----------------|
| 3.1 | Attempt to fell a tree with no `timber_permit` | Server rejects; notification "You need a timber permit." |
| 3.2 | Go to Forestry Office NPC → purchase permit ($500) | `timber_permit` added to inventory; DB row inserted into `forestry_permits` |
| 3.3 | Check DB: `SELECT * FROM forestry_permits WHERE citizenid = '...';` | Row exists with `expires_at` = 7 days from now |
| 3.4 | Manually expire the permit in DB: `UPDATE forestry_permits SET expires_at = NOW() - INTERVAL 1 MINUTE WHERE citizenid = '...';` | Next fell attempt rejected; notification "Your timber permit has expired." |
| 3.5 | Purchase a new permit | Previous expired row replaced or new row inserted; felling works again |

---

## 4. Tool Finding & FindChoppingTool (Syntax Fix Verification)

This function (`server/inventory.lua`) previously had a misplaced `::continue::` label that caused a parse error.

| Step | Action | Expected result |
|------|--------|-----------------|
| 4.1 | Attempt to fell a tree with no tool in inventory | Server rejects with error code `no_tool` |
| 4.2 | Give yourself a `hatchet` with 0 durability | Server finds the tool but rejects it; notification "Your [tool] is too worn to use." |
| 4.3 | Give yourself a `chainsaw` with 0 fuel | Server finds tool, rejects: "Your chainsaw is out of fuel." |
| 4.4 | Give yourself a valid `hatchet` (durability > 0) | Server finds it, returns tool data, proceeds to felling |
| 4.5 | Have both a broken hatchet and a valid felling axe | Server iterates past the broken hatchet and finds the axe (the `goto continue` logic being tested here) |

---

## 5. Felling

### 5.1 Tool & Size Restrictions
| Tool | Small tree | Medium tree | Large tree |
|------|-----------|-------------|------------|
| Hatchet | ✅ Works | ❌ Rejected | ❌ Rejected |
| Felling Axe | ✅ | ✅ | ❌ |
| Chainsaw (cert required) | ✅ | ✅ | ✅ |
| Crosscut Saw (cert + partner) | ✅ | ✅ | ✅ |

Confirm each cell: attempt the fell, verify the server callback accepts or rejects as shown.

### 5.2 Skill Checks
| Tree size | Pattern | On failure |
|-----------|---------|-----------|
| Small | easy, easy | −1 log from yield |
| Medium | easy, medium, easy | Logs marked `quality='damaged'` |
| Large | medium, medium, hard | Damaged logs + reduced yield |

1. Intentionally fail all checks on a large tree.
2. Collect the logs and check metadata: `quality` should be `'damaged'`.
3. Sell those logs — confirm 60% payout vs normal logs.

### 5.3 TIMBER! Warning
1. Have a second player stand within 12 m of the tree you fell.
2. Complete the fell.
   - **Expected:** Second player sees "⚠️ TIMBER!" on screen for 3 s and hears the warning audio.
3. Move second player beyond 12 m, repeat.
   - **Expected:** No warning received.

### 5.4 Crush Zone
1. Stand within 3 m of the fall line when the tree hits.
   - **Expected:** 65–90% HP damage + 2 s ragdoll.
2. Stand outside 3 m.
   - **Expected:** No damage.

### 5.5 Duplicate Fell Prevention
1. Fell a tree successfully.
2. Immediately attempt to target and fell the same stump again.
   - **Expected:** Server rejects; tree is in the felled cache.
3. Check DB: `SELECT * FROM forestry_felled_trees WHERE tree_key = '...';` — row exists.

### 5.6 Fall Direction
1. Stand north of a tree and fell it.
   - **Expected:** Tree falls south (away from player).
2. Verify the fall indicator arrow points in the expected direction before swinging.

### 5.7 Felling Cooldown
1. Fell a tree.
2. Immediately target a second adjacent tree and start felling.
   - **Expected:** Server rejects for 3 s (default `Config.Progression.FellingCooldownMs`).

---

## 6. Field Processing

### 6.1 Limbing
1. Fell a tree (leave the felled log prop in place).
2. Interact with the felled tree → Limb branches.
   - **Expected:** Progress bar completes, 2–4 `branch_bundle` items added.
3. If the species is **Pine** or **Redwood**, check for `resin_raw` (15% chance — test several times).

### 6.2 Bucking
1. Interact with a limbed log → Buck into lengths.
2. Select **Short (4 ft)**.
   - **Expected:** `log_short` added (weight 2 kg), hand-carryable.
3. Select **Standard (8 ft)**.
   - **Expected:** `log_standard` added (weight 5 kg).
4. Select **Long (16 ft)**.
   - **Expected:** `log_long` added (weight 10 kg).
5. Confirm each log has metadata: `{species='...', quality='normal'}`.

---

## 7. Stamina

| Step | Action | Expected result |
|------|--------|-----------------|
| 7.1 | At level 0 (max 12 swings), perform 12 chopping actions | Winded state triggers: heavy breathing, sprint locked, all forestry actions blocked |
| 7.2 | Stand still while winded | Recovery completes in ~8 s; "You've caught your breath." notification |
| 7.3 | Sit on a camp bench while winded | Recovery completes in ~3.2 s (2.5× multiplier) |
| 7.4 | While winded, check stamina via radial menu → "Check Stamina" | Shows "0/12 swings remaining" |
| 7.5 | Gain a Forestry level | Max swings recalculated upward; current swings fully restored |
| 7.6 | At 3 swings remaining, perform another action | Warning notification "3 swings left before you need a break." |

---

## 8. Random Events

Both events fire after a successful fell. Temporarily set probabilities to 100% in `config/server.lua` to test reliably, then restore.

### 8.1 Widow Maker (normally 10%, medium/large trees only)
1. Set `Config.Events.WidowMaker.chance = 1.0` temporarily.
2. Fell a medium or large tree.
   - **Expected:** 0.5–1.0 s after fall animation, warning sound plays and a single `hard` skill check appears.
3. **Pass the check:** No damage, +10 Forestry XP, notification "A dead branch snapped free — you dodged it!"
4. **Fail the check:** 40–65% HP damage, 1.5 s ragdoll, notification "A widow maker caught you!"
5. Confirm event does **not** fire on small trees.

### 8.2 Bee Swarm (normally 6.5%, any size)
1. Set `Config.Events.BeeSwarm.chance = 1.0` temporarily.
2. Fell any tree.
   - **Expected:** ~1 s delay, buzzing audio starts, movement reduced to 80%.
3. **Escape by distance:** Run 30+ m from the stump. Swarm should dissipate.
4. **Escape by water:** Jump into a body of water. Swarm should end immediately.
5. **Escape with smoke canister:** Use `smoke_canister`. Swarm ends, 1–3× `honeycomb` granted.
6. **Let it expire:** Stay within 30 m for 20 s without a canister or water. Swarm ends on its own. Verify 2% HP damage was applied every 3 s during the event.

---

## 9. Transport

### 9.1 Manual Carry
1. Carry a `log_short` (shoulder-carry).
   - **Expected:** Movement speed at 85%, carry animation active, prop visible on character.
2. Drop the log while moving.
   - **Expected:** 5% HP damage, brief stumble animation.

### 9.2 Vehicle Loading
1. Back a pickup truck near logs.
2. Load a `log_standard`.
   - **Expected:** 4.0 s load animation (solo), log moves to vehicle inventory or designated slot.
3. Repeat with 2 crew members near the vehicle.
   - **Expected:** Duration drops to ~2.5 s per log.
4. Repeat with 3+ crew members.
   - **Expected:** Duration drops to ~1.5 s per log.

### 9.3 Log Chute
1. Deploy a `log_chute_kit` at an elevated point.
2. Place a log at the send point.
   - **Expected:** ~8 s slide time, log appears at collection point.
3. Verify only the deployer/crew can collect at the bottom.
4. Leave logs uncollected for 2 hours (or adjust config to test expiry).
   - **Expected:** Logs disappear from collection point.

---

## 10. Sawmill

### 10.1 Tier 1 Portable Sawmill
1. Give yourself a `portable_sawmill` and deploy it.
2. Feed in debarked logs.
   - **Expected:** Produces `lumber_rough` + `sawdust` only.
3. Walk away without picking up the sawmill.
4. Have a different player walk up and "pick up" the unclaimed sawmill.
   - **Expected:** Sawmill returned to that player's inventory (any player can claim unclaimed).

### 10.2 Tier 2 Community Sawmill — Station Progression
Test each station in order (requires appropriate Forestry level):

| Station | Minimum level | Input | Expected output |
|---------|--------------|-------|-----------------|
| Log Deck | 0 | Any log | Stored in stash |
| Debarker | 0 | Log | Debarked log + `bark_raw` |
| Head Saw | 5 | Debarked log | `lumber_rough` + `sawdust` |
| Edger | 5 | `lumber_rough` | `lumber_edged` |
| Planer | 10 | `lumber_edged` | `lumber_finished` |
| Crosscut Saw | 5 | Log | Sized pieces + `wood_chips` |
| Veneer Slicer | 20 | Debarked log (premium species) | `veneer_sheet` |
| Plywood Press | 25 | 3× `veneer_sheet` | `plywood_sheet` |
| Specialty Saw | 30 | `lumber_finished` (premium species) | `specialty_cut` |

For each station:
- Verify access is blocked below the minimum level.
- Verify the correct skill check difficulty appears.
- Confirm output quantities and item metadata.

### 10.3 Throughput Bonus (Multi-Player)
1. Have 2+ players operate different stations simultaneously.
   - **Expected:** Each active station beyond the first reduces processing time by 15%, up to 60% at 4+ stations.

### 10.4 Personal Bonuses (Level-Based)
Verify each unlock triggers at the correct level:

| Level | Bonus to verify |
|-------|----------------|
| 8 | Debarker duration visibly shorter (−20%) |
| 12 | Head Saw skill check drops one difficulty tier |
| 16 | +15% chance of bonus `lumber_rough` at Head Saw |
| 22 | Planer duration visibly shorter (−25%) |
| 26 | Veneer: −1 difficulty tier, +1 `veneer_sheet` per run |
| 32 | All stations −15% duration |
| 38 | `sawdust` output doubled |
| 45 | 10% chance of double output on any station (test ~20 times to observe) |

---

## 11. Crafting

### 11.1 Furniture Recipes
Test one recipe per woodworking tier unlock:

| Level | Item to craft | Key ingredients |
|-------|--------------|-----------------|
| 0 | Wooden crate | `lumber_rough` |
| 5 | Pine bookshelf | `lumber_finished` (pine) |
| 10 | Oak chair | `lumber_finished` (oak) |
| 15 | Oak table | `lumber_finished` (oak) |
| 20 | Maple desk | `lumber_finished` (maple) |
| 25 | Oak grandfather clock | `lumber_finished` (oak) + `clock_mechanism` |

For each:
- Confirm access is blocked below the required level.
- Verify ingredients are consumed.
- Verify output item is granted with correct metadata.
- At **level 30**, verify crafted item carries `{crafter='PlayerName'}` metadata.

### 11.2 Secondary Crafting
| Recipe | Input | Output |
|--------|-------|--------|
| Firewood bundle | 2× `branch_bundle` | `firewood_bundle` |
| Wood pellets | 5× `sawdust` | `wood_pellets` |
| Bark mulch | 3× `bark_raw` | `bark_mulch` |
| Turpentine | 3× `resin_raw` | `turpentine` |
| Wood finish | 1× `turpentine` | `wood_finish` |

### 11.3 Material Save Chance
At **Woodworking level 14** (5% save) and **level 26** (10% save), craft several items and verify that occasionally one fewer input material is consumed. Run 20+ crafts to observe the chance reliably.

### 11.4 Craft Time Reduction
Craft the same item before and after reaching levels 5, 8, 15, and 20. Time each with a stopwatch to confirm the stated reductions apply.

---

## 12. Economy

### 12.1 General Store (Fixed Prices)
Sell each byproduct and verify the payout exactly:

| Item | Expected price |
|------|---------------|
| `branch_bundle` | $20 |
| `firewood_bundle` | $40 |
| `sawdust` | $5 |
| `wood_chips` | $8 |
| `wood_pellets` | $25 |
| `bark_mulch` | $30 |
| `honeycomb` | $45 |

### 12.2 Lumber Buyer NPC (Market-Modified)
1. Sell a batch of `lumber_finished`.
2. Note the price per unit.
3. Sell another large batch immediately.
   - **Expected:** Price decreases (supply rises); verify the formula clamps at 50% of base.
4. Wait for supply to decay (5 units/hour) and re-check price.
5. Sell **damaged** logs.
   - **Expected:** 60% of the current market price.

### 12.3 Contracts
1. Open the contract board.
   - **Expected:** Up to 8 active contracts listed; each shows item, quantity, deadline, and premium price.
2. Accept a contract and deliver partial quantity.
   - **Expected:** `quantity_filled` increments in DB; partial payout at premium rate.
3. Deliver the remainder before the deadline.
   - **Expected:** Contract marked `fulfilled = true`; full payout received; +50 Forestry XP.
4. Let a contract expire past its deadline.
   - **Expected:** Contract removed from the board on next generation cycle.

### 12.4 Lumber Export Dock
1. Check current species multipliers (via Bulletin Board or Earl NPC).
2. Bring the highest-multiplier species' lumber to the Export Dock.
3. Sell it.
   - **Expected:** Payout = base price × multiplier; +75 Forestry XP on completion.
4. Verify multipliers rotate weekly: check DB `forestry_export_multipliers` after 7 days or manually update and re-test.

### 12.5 Furniture Export Dock
1. Craft a specialty furniture item (e.g., grandfather clock — specialty category).
2. Sell at the Furniture Export Dock during a high specialty multiplier week.
   - **Expected:** Payout reflects category multiplier (specialty max 3.0×); +75 Forestry XP.

---

## 13. Progression & XP

### 13.1 XP Batching
1. Perform several actions (fell, limb, buck, process).
2. Check DB `forestry_players.forestry_xp` immediately — value should be unchanged (batch pending).
3. Wait 60 seconds (flush interval).
4. Check DB again — XP now updated.
5. Disconnect mid-batch.
   - **Expected:** XP flushed immediately on disconnect; no loss.

### 13.2 Level-Up
1. Get close to a level threshold (use DB to set XP manually if needed).
2. Perform one more action to push over.
   - **Expected:** Level-up notification on screen; new unlock announced; max swings recalculated.

### 13.3 Forestry Level Gating
Verify felling access changes at key levels:

| Level | Newly accessible |
|-------|-----------------|
| 3 | Felling Axe usable |
| 5 | Species name visible on target |
| 7 | Eligible for Chainsaw Cert |
| 10 | Yield estimate visible on target |
| 14 | Eligible for Crosscut Cert |
| 18 | Eligible for Heavy Equipment License |
| 20 | Full species + value info on target |
| 30 | Value tier display on target |

### 13.4 Woodworking Level Gating
Attempt to craft items above and below the current Woodworking level. Confirm access is enforced server-side (not just hidden client-side).

---

## 14. Crew System

| Step | Action | Expected result |
|------|--------|-----------------|
| 14.1 | Player A runs `/crew` or uses radial menu to create a crew | Crew created; Player A is leader |
| 14.2 | Player A invites Player B (within 10 m, both clocked in) | Player B receives invite notification |
| 14.3 | Player B accepts | B appears in crew roster; shared stash accessible to both |
| 14.4 | Player A assigns a role to Player B | Role shows in roster (cosmetic only) |
| 14.5 | Both players perform forestry actions within 5 min of each other | Both receive +10% XP (2-member bonus) |
| 14.6 | Add 3, 4, 5+ members and verify XP multipliers: +20%, +30%, +40% (cap) | |
| 14.7 | Player A (leader) leaves the crew | Leadership transfers to longest-active member |
| 14.8 | Only 1 member remains | Crew auto-disbands; stash accessible for 30 min, then cleaned |
| 14.9 | A member disconnects | Removed from crew automatically; remaining members unaffected |
| 14.10 | `restart qbx_forestry` with a crew active | Crews are ephemeral — all dissolved; no DB residue |

### 14.11 Two-Person Crosscut Saw
1. Both players have `crosscut_saw` + `crosscut_cert`.
2. Player A initiates crosscut on a tree; system waits for partner (60 s timeout).
3. Player B joins within 60 s.
   - **Expected:** Alternating skill checks (easy/medium, 3 rounds each).
4. Pass all 6 checks.
   - **Expected:** +1 bonus log, +25 Forestry XP each.
5. Fail 2–3 checks.
   - **Expected:** Normal yield, +15 XP each.
6. Fail 4+ checks.
   - **Expected:** Damaged logs, +10 XP each.
7. Have Player A initiate but Player B not join within 60 s.
   - **Expected:** Timeout, fell cancelled, no items consumed.

---

## 15. Licensing

| License | How to obtain | What it unlocks |
|---------|--------------|-----------------|
| Timber Permit | Purchase ($500) from Forestry Office NPC | Required to fell any tree |
| Chainsaw Cert | Practice skill check at Lv 7+ | Chainsaw use |
| Crosscut Cert | Co-op training with a partner at Lv 14+ | Crosscut saw use |
| Heavy Equipment License | Driving test at Lv 18+ | Skidder, logging truck |

For each:
- Attempt to use the associated tool without the license — confirm server rejection.
- Complete the acquisition flow, verify the license item appears in inventory.
- Use the tool — confirm it now works.
- Verify license is stored in `forestry_players.licenses` JSON column.

---

## 16. Tree Respawn

| Step | Action | Expected result |
|------|--------|-----------------|
| 16.1 | Fell a small tree | `forestry_felled_trees` row inserted; `respawns_at` = now + 60 min |
| 16.2 | Fell a medium tree | `respawns_at` = now + 120 min |
| 16.3 | Fell a large tree | `respawns_at` = now + 240 min |
| 16.4 | Manually set `respawns_at` to past for a row in DB, then wait for the 120 s respawn tick | Tree removed from felled cache; `forestry:client:treeRespawned` broadcast sent; tree becomes targetable again |
| 16.5 | Plant a `tree_sapling` at a felled stump | Tree immediately respawned (no DB wait), row deleted, +15 XP granted |

---

## 17. Immersion Systems

### 17.1 Old Timer NPC (Earl)
Test each dialogue branch:

| Dialogue | Verify |
|----------|--------|
| "Got any advice for me?" | Response matches current level tier (beginner 0–6, intermediate 7–17, advanced 18–30, expert 31–50) |
| "What's selling right now?" | Returns actual live export dock multipliers from DB |
| "How do I get better at this?" | Shows current level and next meaningful unlock |
| "Tell me about the trees around here." | Returns species-specific lore text; changes across visits |
| "Any stories?" | Returns one of 7 rotating anecdotes; does not immediately repeat |

### 17.2 Bulletin Board
1. Interact with the board at the Forestry Office.
   - **Expected:** Shows current export dock multipliers, a safety tip, and community stats (trees felled + lumber sold this week from DB).
2. Wait 30+ minutes and check again.
   - **Expected:** Content refreshed.

### 17.3 Camp Spots
1. Travel to a configured camp spot.
   - **Expected:** Bench and fire props spawn within 50 m; camp blip visible on map.
2. Sit on a bench while winded.
   - **Expected:** Stamina recovery is 2.5× faster than standing.

### 17.4 Clothing System
1. Enable auto-dress in settings (if configured).
2. Clock in.
   - **Expected:** Forestry outfit applied (flannel, work pants, boots, hard hat).
3. Clock out.
   - **Expected:** Original outfit restored.
4. Toggle clothing preference via forestry menu.
   - **Expected:** Preference persists after relog (stored as client KVP).

---

## 18. Server Threads

Verify each background thread runs on schedule:

| Thread | Interval | How to verify |
|--------|----------|---------------|
| XP Flush | 60 s | DB `forestry_xp` updates ~60 s after earning XP |
| Tree Respawn Tick | 120 s | Manually expire a row in DB; tree is re-enabled within 120 s |
| Export Rotation Check | 3,600 s | Change system time or DB `last_rotation` manually; multipliers rotate |
| Contract Generation | 1,800 s | Delete all contracts from DB; new ones appear within 30 min |

---

## 19. Security & Anti-Exploit

The following should **never** work regardless of what a modified client sends.

| Exploit attempt | Expected server behaviour |
|----------------|--------------------------|
| Trigger fell callback from >8 m away | Rejected: distance check fails |
| Claim zero-durability tool is valid | Rejected: server reads inventory directly |
| Submit XP amount from client | Irrelevant: server calculates all XP |
| Submit custom quantity for logs | Ignored: server calculates yield from species/size/skill |
| Fell the same tree twice in quick succession | Second attempt rejected: felled cache hit |
| Use smoke canister without active bee swarm | Rejected: `PlayerBeeSwarmActive[source]` is nil; canister not consumed |
| Call `forestry:economy:sell` with an inflated price | Price ignored: server looks up current market price independently |
| Join a crew via direct event without invite | Rejected: no pending invite in server state |

---

## 20. Regression Checklist

After any code change, run these checks before deploying:

- [ ] Resource starts without Lua errors in server console
- [ ] `FindChoppingTool` iterates past broken/empty tools and finds a valid one
- [ ] All four usable items trigger their callbacks (`smoke_canister`, `chainsaw_fuel`, `sharpening_kit`, `tree_sapling`)
- [ ] Felling validation rejects: no permit, wrong tool for size, tree already felled, player too far, on cooldown
- [ ] XP batches to DB within 60 s and flushes immediately on disconnect
- [ ] Crew disbands cleanly on restart; no stash leak
- [ ] Contract generation fires; contracts appear on board
- [ ] Export dock multipliers readable from DB and displayed by Earl NPC and Bulletin Board

---

## Appendix: Useful DB Queries

```sql
-- Check a player's current state
SELECT citizenid, forestry_level, forestry_xp, woodworking_level, woodworking_xp, licenses, statistics
FROM forestry_players WHERE citizenid = 'ABC123';

-- Force a level for testing (requires XP flush to propagate client-side)
UPDATE forestry_players SET forestry_xp = 8944, forestry_level = 20 WHERE citizenid = 'ABC123';

-- Expire a permit for testing
UPDATE forestry_permits SET expires_at = NOW() - INTERVAL 1 MINUTE WHERE citizenid = 'ABC123';

-- Force a tree respawn (by expiring the row)
UPDATE forestry_felled_trees SET respawns_at = NOW() - INTERVAL 1 MINUTE WHERE tree_key = '...';

-- Check active contracts
SELECT * FROM forestry_contracts WHERE fulfilled = 0 ORDER BY deadline;

-- Check current market prices
SELECT item_name, base_price, current_price, supply, demand FROM forestry_market;

-- Check export multipliers
SELECT * FROM forestry_export_multipliers;
SELECT * FROM forestry_furniture_export;

-- Wipe felled tree cache for clean testing
DELETE FROM forestry_felled_trees;
```

## Appendix: Temporary Config Overrides for Testing

In `config/server.lua`, temporarily set these values to make events and timers testable without waiting:

```lua
-- Fire events on every fell
Config.Events.WidowMaker.chance = 1.0
Config.Events.BeeSwarm.chance = 1.0

-- Speed up tree respawn for testing (seconds)
Config.Respawn.SmallTree  = 60     -- default 3600
Config.Respawn.MediumTree = 120    -- default 7200
Config.Respawn.LargeTree  = 240    -- default 14400

-- Speed up contract generation
Config.Economy.ContractGenerationInterval = 30  -- default 1800

-- Speed up XP flush
-- (Edit the Wait() in server/progression.lua thread: change 60000 to 5000)
```

Restore all values before production deployment.
