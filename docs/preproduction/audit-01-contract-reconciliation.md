# Audit-01 — reconciliation v1.0/v1.5 and schema v4 (2026-11-08)
**Status: STATIC REVIEW WITH FINDINGS; NOT APPROVED / runtime NOT_RUN.**
**Scope:** Issue #36; source refs `docs/book01-g0-consolidated-20261105`, `integration/procedural-world-20261107`, `feature/shelter-always-20261108`. Reviewer: ChatGPT technical review, **not impersonating A0 or A1–A5**.

## Evidence and exact reviewed paths
1. Baseline `docs/book-01/05-integration-contracts.md` on G0 candidate: blob `69ec611b19f507cd1407e87608c41cea6f2e9569`, v1.0-CANDIDATE.
2. Same file on procedural branch is 36,081 characters vs 18,712 on baseline; shared base plus proposed additions §§11–15 (replay, commit/recovery, load, pause, deadlines, scenes, EventBus, gameplay). On shelter branch §§16 adds OD-12. Header remains v1.5-PROPOSED and G0 review required.
3. `game/systems/inventory/campaign_commands.gd` on shelter branch, lines 58–87: unconditional enter/return, while System purchase/parcel gated on first victory; lines 160–188: schema4 Layout linkage and shelter warp exemption. These are static code facts, not runtime pass.
4. `game/systems/scene_router/scene_router.gd` on procedural branch: staged scene instantiation, committed scene install; correct return coordinate is **runtime acceptance pending**.
5. `game/systems/gameplay/gameplay_commands.gd` lines 489–498: Q01 first enemy, Q02 shelter visited **and** first enemy; Q06 consent, despite missing Q06 in original narrative `02-story.md`.
6. `game/systems/world/world_layout.gd` begins with VERSION=4, DISTRICTS=4 and FLOORS=4; current generation is **not absent**. Its topology and geometry must be reviewed/tested under Issue #44, not replaced with a second generator.
7. Source owner decisions: Issue #4 OD-01…OD-12; chief A5/UI; A1 core; A0 independent support; no additional owner questionnaire.

## Delta v1.0 → v1.5 (actual file comparison)
- Explicit successful replay `ok=true, code=ALREADY_APPLIED`, original receipt data/revision; replay has no extra commit/event.
- `GameSession.set_pause(bool)` replaced for UI with pause tokens `acquire_pause(reason)/release_pause(token)`.
- `scene_changed` payload now `entry_point_id,return_scene_id` instead of ambiguous `return_point_id`.
- New proposed requirements for atomic checkpoint/rollback/recovery, loading, deterministic calendar deadlines and EventBus weak subscriptions.
- New sections document runtime scene transition, core schema2, gameplay schema3 and subsequently schema4, procedural world and unconditional shelter. Historic schema examples in §§5/12/15 MUST NOT be interpreted as current runtime save format.

## Findings and remaining actions
**F01 HIGH — Normative version ambiguity:** PR #7 declares v1.0 as unique candidate, but implementation branch has v1.5-PROPOSED. Select exact HEAD SHA and one reviewed contract; don't merge stale copy over new code. Owner: A1+A5; tracking #36.
**F02 HIGH — Save-format documentation gap:** schema v4 must have a field-by-field normative serialized fixture, validator and explicit compatibility matrix v2/v3/v4. Confirm actual save code, migration, backup and game rules before claim. Owner: A1+A3, #34/#36.
**F03 MEDIUM — Quest narrative mismatch:** original `02-story.md` skips Q06, but gameplay code implements Q06 consent. Preserve existing implemented quest ID; reconcile canonical quest design and tests. Owner: A4+A5, #43.
**F04 MEDIUM — Event consumption compatibility:** update consumer test fixtures for `scene_changed.entry_point_id` and `return_scene_id`, and successful replay semantics. Owner: A1+A5, #36.
**F05 MEDIUM — Shelter retreat acceptance:** static code is consistent with OD-12 in the inspected paths; still verify before-first-enemy, combat HP, collision-safe destination, save/load, duplicate rewards, modal pause, native GUI. Owner: A1+A2+A5, #37 / PR #39.
**F06 MEDIUM — Existing procedural layout:** verify collision-flood-fill and bidirectional portals on multiple seeds + schema4 save/reload, without claiming 16 visually unique floors solely because constants are 4×4. Owner: A2+A5, #44.

## Acceptance steps (not yet performed)
- Freeze candidate code branch and hash; compare implementation schema with exact persisted JSON and corrupted/old version paths.
- Run contract tests for idempotency, conflict, stale entity revisions, atomic save/load, pause tokens, tick/rest equivalence; record actual command/output.
- Re-run native Windows CI and independent manual GUI smoke for OD-12. Mark NOT_RUN where appropriate.
- A1, A2, A3, A4, A5 add independent review evidence; A0 reviews A5 without changing role. Owner approves final SHA of G0 in Issue #4.
**Outcome:** discrepancy classified and documented; no claim of resolved #36, no approved G0, no code merge into main.
