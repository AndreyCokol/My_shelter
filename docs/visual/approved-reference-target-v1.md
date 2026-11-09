# Approved Gameplay References — Visual Contract V1

**Status:** OWNER ART DIRECTION APPROVED / ENGINE IMPLEMENTATION IN PROGRESS (not pixel-parity approved)  
**Scope:** A5 owns visuals, Godot UX and integration; A2 owns procedural geometry and physics; A0 independently reviews final rendered evidence.  
**Tracking:** Issue #45 (visual/PC acceptance), Issue #44 (procedural uniqueness), PR #98 (actual older Godot captures).

## Source of truth (user-provided, 2026-11-08 / confirmed 2026-11-10)

The owner approved **four distinct 16:9 screenshots** in this ChatGPT project. They are *target concepts*, not evidence of implemented Godot pixels:

| Reference | Gameplay state and non-negotiable layout | Tone / surface cues |
|---|---|---|
| VIS-01 | Shelter: player at a workshop construction grid, NPC carrying supplies, homestead, tent, wheat/vegetable beds, chicken enclosure, well and storage. Building cost popup to the right of the placement preview | Bright warm sun, rich gold/earth/olive, flowers, functional wood/stone structures, inviting safe space |
| VIS-02 | Hospital exterior / street: melee hit against a zombie, second infected approaching, entrance centered upscreen, ambulance, broken car, medical loot pickup | Cold blue-green and grey, damp asphalt, puddle highlights, wear/overgrowth and restrained amber emergency lights |
| VIS-03 | Hospital interior: connected corridors, medical wards, reception, stairs, X-ray, pharmacy cache and an actual loot dialog | Cold hospital tiles and fixtures, readable departmental distinctions, red emergency accents, wear, selected warm lamps |
| VIS-04 | Apartment: several identifiable rooms (kitchen, lounge, bath, bedroom, storage), connecting hall and exit, zombie, individually highlighted salvage and backpack | Ruined cold residential atmosphere with old parquet, worn rugs, warm isolated lamps, broken windows and clutter |

**Critical:** source PNGs were provided in conversation and are not yet checked into GitHub as authorized, standalone asset source files. A screenshot is NOT a game-ready texture atlas; slicing it into a level image would break procedural recombination, gameplay physics/occlusion, lighting and pixel-art consistency. Do not claim pixel-identical output without source files and verified in-engine comparisons.

## Camera, viewport and platform — hard constraints

- Gameplay: **orthographic strict 90° from above**, no isometric projection, artificial tilt or visible vertical fronts that change the gameplay camera. Wall/roof illustrations are top-down representations. UI is a 2D desktop overlay.
- PC layout: **16:9**, tested at 1280×720 and 1920×1080. Internal logical canvas stays 640×360; upscale with nearest neighbor for pixel legibility. No mobile-first padding or giant touch targets.
- HUD regions at logical 640×360: upper-left player portrait, HP/stamina/survival stats; left quest and progress; top-center scene/day plaque; top-right real minimap; four quick slots at bottom-left; I/M/J/K menu buttons at bottom-right; bottom keyboard/mouse hints. Building grid and loot dialogs appear contextually, NOT permanently.
- **Control truth beats concept labels**: Left Ctrl currently toggles radial menu, G accesses shelter anywhere, Space dodges, E interacts; do NOT copy misleading Ctrl-run/Tab-radial labels verbatim from image concepts. The game contract is authoritative.
- Do not display arbitrary level, HP, weather, clock or currencies taken from screenshot examples. All visible runtime fields must come from live saved state or an explicit optional demo preset.

## Implementation matrix and acceptance

| Layer | Live game now | Reference parity still missing |
|---|---|---|
| 90° top-down 2D and segmented Godot world | Existing world/hero/physics | More elaborate handcrafted tile geometry and roof, wall occlusion and coherent light |
| Cold/warm palette + floor 128px textures | Existing world_art textures; initial V1 deterministic grime, puddles, flowers overlay | Proper authored layered atlases: floors, wall ends, doors, roof, furniture, props; material consistency |
| Procedural hospitals/apartments/roads | v5 collision-unique geometry, v4 save compatibility, route tests | Authored variants of reception, ward, pharmacy, x-ray, kitchen, lounge, baths, exterior facades, vehicles and crop plots |
| HUD | Existing image-backed bronze HUD + V1 top-center live scene/day banner | Portrait/style exact sizing, three status bars, multi-step quest checklist, styled pickup/cache dialog and illustrated ability cues |
| Actors | Current simplified actor/entity sprites | True 64×64 production sprite sheets at strict 90° for 4 directions, idle/move/attack/dodge/hit/death with matching animations |
| Lighting | Static surface tints and local accents | Consistent real Godot 2D lights/shadows/reflection highlights, time/weather variations, performance constraints |
| QA | Real Linux rendered captures at 720p/1080p, Windows headless checks | Actual Windows GUI and input, independent A0, visual comparison of four pinned reference PNGs, 30min FPS/heap profiling |

### Pixel-parity gate — mandatory before saying 1:1

1. Commit approved screenshot references as access-rights-cleared **reference-only** assets under `docs/visual/references/` and give them immutable SHA-256 entries in the manifest. They are never used as tiled map backgrounds.
2. Capture the **real Godot process** in the same four controlled game states at both resolutions with deterministic seed, camera scale, HUD values, UI layout, scene variant and light preset. Save the exact build SHA and seed in the image manifest.
3. Compare side by side first on composition/camera, then UI region, then world detail. Record per-region measurements for approximate positioning, icon/label readability, dominant palette, anatomy, material continuity and area occupancy. Numeric pixel error is meaningful only after alignment; exclude explicitly dynamic pixels (floating damage, animation, clock) rather than claiming identical pixels from unlike frames.
4. Gate each area separately: HUD; shelter; street/hospital facade; hospital interior; apartments; actor and motion. Explicit FAIL/NOT_RUN stays open until fixed. One passed element cannot imply full-project parity.
5. A5 PR, CI Linux+Windows, screenshot inspection, **independent A0** sign-off and owner visual acceptance required. No G0 freeze or claim that generated concept image equals live runtime.

## First in-engine change (this branch)

- `WorldArt.atmosphere` adds deterministic nonblocking warm/cold decals (surface cracks, worn hospital/apartment floor traces, street water damage, small shelter flowers). Existing room geometry, procedural seeds, portals and saves remain unchanged.
- `ExplorationHUD` adds live top-center bronze location/day plaque. The day is computed from saved `game_time_minutes`, not copied from concept image. Text is bounded to prevent overlap at 640×360.
- The real software-rendered visual test checks that the HUD receives current saved time and scene; existing 3-seed render and route tests remain active. Performance/visual parity must be verified on exact SHA.

### Highest-priority remaining art deliverables for 1:1

1. **Tileset pipeline:** 128×128 seamless ground (each environment ×4), transition/wall/corner atlases, 16 different hospital floors, 8 house floors, varied street, warm modular shelter; correct atlas permissions, naming and nearest filtering.
2. **Actors + props:** hero, infected and resident 64×64 top-down sprites and state animations; medical equipment, beds, shelves, cars, farm machinery, loot, interactive doors, map and UI icons separately with alpha channels.
3. **Scene construction:** spawn/use reusable modular fragments using the authored tiles; physical colliders exactly match doors/walls/furniture, proper layering and occlusion. No full screenshot flattened under interactive gameplay.
4. **Polish:** real light sources, damp reflections, grime, footprints/particle hits, item highlights and readable Russian typography with controlled contrast.
5. **Accept:** four comparable real screenshots and short in-engine gameplay capture, then A5/A0 + owner review. Until that, **visual fidelity is PARTIAL, not 1:1**.
