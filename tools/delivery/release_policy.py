#!/usr/bin/env python3
"""Fail-closed PUBLIC preview promotion gate.

Approval environment variables must be configured in the protected GitHub
environment 'preview-release' AFTER review of the exact game source SHA.
These markers are human attestations, not cryptographic signatures, license
inventories, or a substitute for the environment's Required Reviewers.
"""
from __future__ import annotations

import os
import re
import sys

APPROVAL_VARIABLES = (
    "MYSHELTER_OWNER_APPROVED_SHA",
    "MYSHELTER_ASSET_RIGHTS_APPROVED_SHA",
    "MYSHELTER_A0_REVIEWED_SHA",
    "MYSHELTER_G0_G4_APPROVED_SHA",
)


class ReleaseGateError(ValueError):
    pass


def check_public_preview_approvals(source_sha: str, environment: dict[str, str]) -> None:
    """Raise unless ALL independently set approval markers match exact source."""
    if not isinstance(source_sha, str) or re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise ReleaseGateError("Source must be an exact lowercase 40-character SHA")
    for key in APPROVAL_VARIABLES:
        value = environment.get(key)
        if not isinstance(value, str) or value != source_sha:
            raise ReleaseGateError(
                f"Public preview BLOCKED: missing/mismatched {key} for exact source SHA"
            )


def main() -> int:
    try:
        check_public_preview_approvals(os.environ.get("SOURCE_SHA", ""), os.environ)
    except ReleaseGateError as error:
        print(error, file=sys.stderr)
        return 1
    print("PUBLIC PREVIEW PROMOTION GATE: PASS (all four SHA-scoped attestations)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
