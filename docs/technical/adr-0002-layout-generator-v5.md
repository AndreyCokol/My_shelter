# ADR-0002 — generator v5: physical uniqueness of hospital floors

**Status:** IMPLEMENTED IN DRAFT PR #73 / G0 REVIEW PENDING · 2026-11-08  
**Tracking:** Issue #44; A2 world-layout owner, A5 chief integrator and all UI, A0 independent code checker.

## Problem verified against v4
The existing world graph generated 4 hospitals × 4 floors, with 16 distinct IDs, but a strict fingerprint of room rectangles, door locations and collision walls showed only 11–14 genuinely distinct layouts across eight seeds (0, 1, 54, 127, 128, 1023, 65535, 2147483647). The old tests examined segment IDs and patterns; visually indistinguishable structural fallback plans could pass.

## Version and compatible behavior
- **Campaign `schema_version` remains 4.** `world_states.layout.generator_version` is a different persisted field.
- `WorldLayout.VERSION=5` applies to **newly created** worlds; `WorldLayout.valid_manifest` accepts historic generator versions 1, 2, 3, 4, and 5.
- When loading an old v4 manifest, `WorldLayout.from_manifest` calls `build(seed, 4)` and uses the historic 3-argument `Plans.get_plan(kind,floor,pattern)` behavior. No v5 architectural variation is requested. Thus world topology, door/stair positions and v4 collision walls remain anchored to the stored generator version.
- `WorldLayout.build(seed, 5)` adds deterministic architectural variation only in hospital floors. The variation index is `district*4+floor_index`, stable for the same seed/catalog.
- Do not silently alter v4 save manifests; any opt-in `session.upgrade_world` uses existing explicit migration and backup contracts. Do not confuse generator_version with save schema_version, ruleset_version or asset catalog_version.

## New physical geometry (not ID-only or purely decorative)
Each of the sixteen hospital floor slots creates an L-shaped internal alcove in an upper room. The configuration combines 2 room positions × 2 wall depths × 4 segment lengths. The walls are included in `plan.walls`, therefore in both rendered wall geometry and the game's physical collision obstacles. They are placed away from north-west furniture, walkable room anchors, entrance doors, stairs and other required objectives. The plans are checked with `Plans.valid`; gameplay route checks cover physical navigation.

**Scope limit:** This is a concrete collision-geometry distinction, not a claim that all sixteen floor plans have completely different functional graphs, furniture sets, narratives, art tiles or hospital department identities. Additional designed floor archetypes and authored segment art may still be desirable for richer visual variety, and must not be misrepresented as implemented.

## Acceptance evidence and required steps
- `run_layout_fingerprint_tests.gd`: 128 sequential seeds plus 4 edge seeds; seeded determinism, manifest roundtrip, 30-scene graph, paired stairs/entrances, 16 distinct hospital wall+room+door fingerprints, 8 house-floor fingerprints, 4 street fingerprints.
- `run_layout_fingerprint_tests.gd`: old generator-v4 manifest still reconstructs original geometry; documented historical uniqueness counts serve as frozen regression points for eight seeds.
- `run_world_tests.gd`: write and load a v4 checkpoint under v5-capable game code; check no automatic v5 wall geometry appears and user inventory/mission state survives.
- Existing `expanded_routes` path checks, 128-seed graph tests, native Windows export and Linux render checks must remain green.
- CI SUCCESS on exact HEAD SHA is required; **visual walkthrough on native Windows, actual gameplay FPS, and independent A2/A5/A0 approval remain separate**.
- If an out-of-bounds alcove or furnished collision occurs: fail explicit validation and correct the template. Never weaken fingerprint uniqueness or blindly change already-saved v4 worlds.
