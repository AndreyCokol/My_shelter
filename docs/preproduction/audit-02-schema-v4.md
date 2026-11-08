# Audit-02 — schema v4 data contract and backward compatibility
Status: **STATIC_CODE_REVIEW / candidate / runtime NOT_RUN**, 2026-11-08.
Exact source ref: `feature/shelter-always-20261108`; pending Issue #34 and #36.

## Code-verified schema construction
- `game/state/campaign_model.gd` `new_state` starts with `scope=campaign-core`, schema2; `Gameplay.seed` promotes it to schema3; if `rules.world_seed` exists it promotes to **schema4** and sets `world_states.layout=WorldLayout.manifest(seed)`, `world_states.locations={}`.
- `WorldLayout.manifest(seed)` contains `seed`, `generator_version` (currently 4), `catalog_version` (currently 1); `valid_manifest` permits generator versions 1/2/3/4 under its validator. This is **generator_version**, not campaign `schema_version`.
- Campaign state required top-level keys: `schema_version, scope, ruleset_version, save_id, state_revision, game_time_minutes, clock_remainder, resource_revisions, scene, player, wallet, shelter, inventory, crops, residents, quests, story_flags, world_states, completed_actions, claimed_reward_ids`.
- Scene includes `current_scene_id, return_scene_id, entry_point_id, positions, last_outside_position`; `player.position` persists; runtime scene Nodes are excluded from save.
- Gameplay seeding: two initial crops `plot_1,plot_2`, two residents `resident_1,resident_2`, quests Q01..Q07; the list of fields in nested world_states is expanded by later schema4 gameplay systems. Do not invent full JSON fixture from this summary; use an actual serialized checkpoint and schema4 validator to establish the normative fixture.
- `game/data/game_rules.gd` uses candidate `version=prototype-v1`, `minutes_per_real_second=1.0`, `crop.grow_minutes=180`, `crop.spoil_minutes=120`, `food.units_per_resident=2`. These are **prototype balancing choices**, NOT canonical book intervals and NOT an owner-approved two-potato rule. Old book example 72/12 hours is reference-only.
- `campaign_model.validate` explicitly allows schema3 as `legacy` when current rules produce schema4, but only if all validation succeeds. Thus stating “v3 universally rejected” would be inaccurate. Exact migration behavior and persistence of upgraded state must be tested.
- `game/state/gameplay_state.gd` validates crop/resident/quest and world-state invariants, and treats schema4 separately.

## Potential compatibility traps (tests required)
1. **Legacy schema3 under current v4 rules:** validate/load and upgrade_world (if required) vs backup/rollback; never overwrite original file on failed conversion. Record actual returned error codes for incompatible world state and test save/load.
2. **Ruleset mismatch:** ruleset_version must equal current rules.version. Different `world_seed`, balance definitions and stored deadlines can invalidate saves; existing Issue #34 tracks this, not yet resolved by static reading.
3. **Map persistence:** check `generator_version` and `catalog_version` separately from `schema_version` on load; scene portal and location references should remain valid across layout versions.
4. **Post-update idempotency:** `completed_actions` receipt ledger, reservations and `claimed_reward_ids` must survive schema changes without duplicate rewards.
5. **Saved-return HP:** `SceneRouter` captures departure_position, `campaign_commands.gd` supports health in context on transition/save, but runtime owner must be checked for actually populating the field. PR #39 CI evidence is separate from this static assertion.

## Required reproducible test fixtures
SCHEMA-01 new schema4 checkpoint serializes and reloads with exact world seed and valid portal graph.
SCHEMA-02 schema3 legacy slot loads or fails with explicit non-destructive error, documented expected migration.
SCHEMA-03 ruleset mismatch fails without overwriting primary or backup.
SCHEMA-04 corrupted/truncated primary: verified backup recovery without unintended reset.
SCHEMA-05 committed action replay post-load returns ALREADY_APPLIED and does not duplicate reward, items or residents.
SCHEMA-06 generator_version old/new compatibility and map stability.
All tests currently **NOT_RUN in this audit**.

## Handoff
A1 — schema/SaveManager/transaction; A3 — balance/crop deadlines; A2 — scene/portal validator; A5 — chief integration, UI failure/recovery; A0 independent review. Do not declare Issue #36 resolved until exact implementation version and SHA are reviewed.
