# Lua fix tests: coverage (owner T4)

Entry: `luajit tests/lua/run.lua [filter]` (CI, ubuntu) or `python tests/lua/run_local.py [filter]` (local, lupa's LuaJIT).
Each case loads the REAL fix script from `mods/<mod>/gamedata/scripts/` into a fresh X-Ray-like environment (`harness.lua`).
Third-party modules are replaced by small stand-ins that copy the signatures and call shapes of the shipped code.

| Requirement | Test case(s) | File |
|---|---|---|
| FX-WSAMMO-001 | FX-WSAMMO-001 fewer full boxes than needed: partials and ALL full boxes consumed | test_wsammo.lua |
| FX-WSAMMO-002 | FX-WSAMMO-002 enough full boxes: complexCraft left to the original | test_wsammo.lua |
| FX-WSAMMO-003 | FX-WSAMMO-003 newItemSize < 1: partials released, no remainder created | test_wsammo.lua |
| FX-WSAMMO-004 | FX-WSAMMO-004 craft not allowed / empty complexCraft: wrapper does nothing | test_wsammo.lua |
| FX-WSAMMO-005 | FX-WSAMMO-005 wrappers installed once per class | test_wsammo.lua |
| FX-WSAMMO-006 | manual | |
| FX-TGEN-001 | FX-TGEN-001 wraps has_completed_task_prerequisites once and logs the marker; without the function: logged and skipped | test_tgen.lua |
| FX-TGEN-002 | FX-TGEN-002 generation calls answered from the memo for 5000 ms, per task_id | test_tgen.lua |
| FX-TGEN-003 | FX-TGEN-003 calls with an actor, an npc or no task id always reach the original | test_tgen.lua |
| FX-TGEN-004 | FX-TGEN-004 on_level_changing clears the memo and the bounty snapshot | test_tgen.lua |
| FX-TGEN-005 | FX-TGEN-005 swaps build_variants once and logs the marker; without the module, debug or a helper: logged and skipped | test_tgen.lua |
| FX-TGEN-006 | FX-TGEN-006 one scan per 5000 ms snapshot | test_tgen.lua |
| FX-TGEN-007 | FX-TGEN-007 picks the same candidates, in the same group order, as the original; stops at MAX_VARIANTS | test_tgen.lua |
| FX-TGEN-008 | FX-TGEN-008 every pick passes candidate_valid; refused ones are replaced | test_tgen.lua |
| FX-TGEN-009 | FX-TGEN-009 wraps on actor_on_first_update once; results and errors pass through | test_tgen.lua |
| FX-TGEN-010 | FX-TGEN-010 summary after 1 s idle: totals, nested time inside callers, top list; under 5 ms (nested time counted once): no summary, counters reset | test_tgen.lua |
| FX-TGEN-011 | manual (in game: host lag on a cold Taskboard refresh, taskprof summary) | — |
| FX-TGEN-012 | FX-TGEN-012 preconditions that read the dialog NPC are never answered from the memo; without mob_trade the memo works as before | test_tgen.lua |

### MOD-LOOTCLAIM (Combined GAMMA NPC Loot Claim, folder name read from pack.json) — test_lootclaim.lua

| Requirement | Test case(s) |
|---|---|
| MOD-LOOTCLAIM-001 | MCM page lists every DEFAULTS key with the same defaults; without MCM defaults apply, MCM enabled=false switches the mod off |
| MOD-LOOTCLAIM-002 | actor kill of a stalker; peer avatar and companion count as the player; no xrRazom; npc_loot_all + mutant victim |
| MOD-LOOTCLAIM-003 | free bodies (all six reasons); companion kill with companions_are_player=false |
| MOD-LOOTCLAIM-004 | NPC kill: claimed[victim] = killer |
| MOD-LOOTCLAIM-005 | Use blocked near a live killer; release rules (dead / not loaded / far); ignored keys and targets |
| MOD-LOOTCLAIM-006 | lock re-applied every 1000 ms |
| MOD-LOOTCLAIM-007 | own kill released after release_delay; scheduled once; release_after_loot=false |
| MOD-LOOTCLAIM-008 | enabled=false / npc_loot_all release every locked body |
| MOD-LOOTCLAIM-009 | NPC looting frees a claimed body; player kills untouched |
| MOD-LOOTCLAIM-010 | autolooter blocked / allowed / block_autolooter=false / module absent |
| MOD-LOOTCLAIM-011 | tip from a near killer, actor_menu text otherwise, show_messages=false |
| MOD-LOOTCLAIM-012 | save/load round trip, pending not saved |
| MOD-LOOTCLAIM-013 | level change clears all tables |
| MOD-LOOTCLAIM-014 | over 1000 entries the 100 oldest are dropped |
| MOD-LOOTCLAIM-015 | Semenov tissue counter |
| MOD-LOOTCLAIM-016 | manual (co-op on a real host) |

Mutation check (2026-10-14): disabling the Use block, inverting the distance check, removing the table cap, changing LOCK_VALUE
and disabling the release after NPC loot each made the matching cases fail.

### MOD-QCT (Quantity Craft and Transfer) — test_qct.lua

The workshop stand-in copies the call shape of the live chain: `UpdateItem` sees every live client object (released ones too,
until the deferred removal), `Craft` mirrors `zz_ui_workshop_keep_crafting_window_open.script` of Craft From Stashes (release,
discharge, one ammo box of `craft_item_r[2]`, `craft_item_r[2]` results, lead box refund of used - 1).

| Requirement | Test case(s) |
|---|---|
| MOD-QCT-001 | MOD-QCT-001 workshop patched once with the marker; no ui_inventory: logged and skipped |
| MOD-QCT-002 | MOD-QCT-002 hotkey needs the exact modifier set; key <= 0 disables it |
| MOD-QCT-003 | MOD-QCT-003 dialog max is the exact feasible N; the one-craft view is restored |
| MOD-QCT-004 | MOD-QCT-004 OK with N: one Craft() call, N results, N sets consumed, nothing released twice |
| MOD-QCT-005 | MOD-QCT-005 OK above what is left now is clamped by a fresh evaluation |
| MOD-QCT-006 | MOD-QCT-006 ammo result: N boxes of box size, dialog shows pieces |
| MOD-QCT-007 | MOD-QCT-007 *_lead_box result: no lead box refund beyond per-craft |
| MOD-QCT-008 | MOD-QCT-008 next batch refused while released objects linger; warning after the timeout |
| MOD-QCT-009 | MOD-QCT-009 multi-use material: fewest uses first, exact consumption |
| MOD-QCT-010 | MOD-QCT-010 move N: best first, re-validated at OK, packs counted in pieces |
| MOD-QCT-011 | MOD-QCT-011 give N: best still owned first, one SendGiveItem per id, stops when the player leaves |
| MOD-QCT-012 | MOD-QCT-012 no xrRazom or nobody within 5 m: no give entries |
| MOD-QCT-013 | MOD-QCT-013 peer: Craft runs inside the xrRazom peer-chain window |
| MOD-QCT-014 | manual (dialog layout on 4:3 / 16:9 / 21:9) |
| MOD-QCT-015 | manual (co-op: batch craft and give on a peer, counts match on host and peer) |

Mutation check (2026-10-26): no lead box skip, no busy block, no ammo split, give without the owner check, hotkey ignoring
modifiers, no peer-chain window, reversed multi-use order — each failed exactly its requirement's case.

## Expected failures

None at the moment.

## Notes on test seams

- `GFIX_TEST_ROOT=<dir>` points the loader at another `mods/` tree (a broken copy of a fix, or a tree with a mod that is not
  published yet).
- FX-TGEN: 7 mutations (memo TTL `<=`, no `candidate_valid`, `p[3]` ignored, logic calls memoized, nested profiler time
  counted twice, idle 500 ms, no clear on level change), each failed exactly its requirement's case.
