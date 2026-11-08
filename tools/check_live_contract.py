#!/usr/bin/env python3
"""P0-01: static invariants linking the living Godot project and G0 documents.

This is NOT a runtime game test, a schema migration test, or reviewer approval.
Deliberately fails if structural contracts drift, prompting a human review.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = [
    ("bootstrap schema1", "game/systems/core/core_session.gd", '"schema_version": 1'),
    ("bootstrap scope", "game/systems/core/core_session.gd", '"core-bootstrap"'),
    ("campaign base schema2", "game/state/campaign_model.gd", '"schema_version": 2'),
    ("legacy gameplay schema3", "game/state/gameplay_state.gd", "state.schema_version = 3"),
    ("procedural gameplay schema4", "game/state/campaign_model.gd", "state.schema_version = 4"),
    ("runtime layout manifest", "game/state/campaign_model.gd", "WorldLayout.manifest(rules.world_seed)"),
    ("runtime receipts", "game/systems/core/core_session.gd", "completed_actions[action_id]"),
    ("immutable snapshot view", "game/systems/core/core_session.gd", "return _state.duplicate(true)"),
    ("durable transition", "game/systems/scene_router/scene_router.gd", "actor_health: int = -1"),
    ("unconditional shelter interface", "game/app/game_app.gd", "func toggle_shelter()"),
    ("left-only radial input", "game/app/game_app.gd", "key.location == KEY_LOCATION_LEFT"),
    ("player melee LOS", "game/entities/player/player.gd", "enemy.has_clear_line_to(self)"),
    ("enemy melee LOS", "game/entities/enemies/enemy.gd", "< 28 and has_clear_line_to(target)"),
    ("shared combat ray", "game/entities/enemies/enemy.gd", "direct_space_state.intersect_ray(query)"),
    ("planted deadline compatibility", "game/state/gameplay_state.gd", "grow_minutes_at_planting"),
    ("one normative candidate", "docs/book-01/05-integration-contracts.md", "v1.5-PROPOSED"),
    ("real runtime schema in contract", "docs/book-01/05-integration-contracts.md", "schema_version = 4"),
    ("real implementation status in PRD", "docs/book-01/03-requirements.md", "INTEGRATION_BRANCH_IMPLEMENTED"),
    ("owner always-shelter decision", "docs/book-01/08-g0-decision-record.md", "OD-12"),
    ("runtime mapping", "docs/book-01/13-p0-01-live-contract-reconciliation.md", "schema_version=4"),
]
errors = []
for label, path, needle in checks:
    target = ROOT / path
    if not target.exists():
        errors.append(f"MISSING {label}: {path}")
        continue
    content = target.read_text(encoding="utf-8")
    if needle not in content:
        errors.append(f"DRIFT {label}: {path} lacks {needle!r}")
print(f"P0-01 STRUCTURE: {len(checks)} checks; errors={len(errors)}")
for error in errors:
    print("ERROR:", error)
sys.exit(bool(errors))
