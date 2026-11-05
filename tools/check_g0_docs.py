#!/usr/bin/env python3
"""Read-only G0 Markdown integrity checks. No Godot runtime required."""
from __future__ import annotations

from pathlib import Path
from urllib.parse import unquote
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DOCS = [ROOT / "README.md", *sorted((ROOT / "docs" / "book-01").rglob("*.md"))]
LINK = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
EXPECTED = (
    "docs/book-01/03-requirements.md",
    "docs/book-01/04-five-agent-workplan.md",
    "docs/book-01/05-integration-contracts.md",
    "docs/book-01/06-application-architecture-proposal.md",
    "docs/book-01/08-g0-decision-record.md",
    "docs/book-01/09-sandbox-gameplay-design.md",
    "docs/book-01/10-qa-acceptance-matrix.md",
    "docs/book-01/11-technical-decisions-and-handoff.md",
    "docs/book-01/agents/A0.md",
    "docs/book-01/agents/A1.md",
    "docs/book-01/agents/A2.md",
    "docs/book-01/agents/A3.md",
    "docs/book-01/agents/A4.md",
    "docs/book-01/agents/A5.md",
    "docs/book-01/agents/prompts/COMMON.md",
)
errors: list[str] = []
checked_links = 0
checked_tables = 0

for name in EXPECTED:
    if not (ROOT / name).is_file():
        errors.append(f"MISSING: {name}")

if (ROOT / "docs/book-01/07-contract-spec-proposal.md").exists():
    errors.append("DUPLICATE CONTRACT: 07 must not coexist with normative 05")

for source in DOCS:
    if not source.exists():
        errors.append(f"MISSING DOC: {source}")
        continue

    fenced = False
    table_columns = None
    for row, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith(chr(96) * 3):
            fenced = not fenced
            table_columns = None
            continue
        if fenced:
            continue

        for found in LINK.finditer(line):
            href = unquote(found.group(1).split("#", 1)[0].strip())
            if not href or href.startswith(("http://", "https://", "mailto:")):
                continue
            checked_links += 1
            target = (source.parent / href).resolve()
            try:
                target.relative_to(ROOT)
            except ValueError:
                errors.append(f"{source.relative_to(ROOT)}:{row} OUTSIDE ROOT: {href}")
                continue
            if not target.exists():
                errors.append(f"{source.relative_to(ROOT)}:{row} BROKEN LINK: {href}")

        if line.startswith("|"):
            cols = line.count("|") - 1
            if table_columns is None:
                table_columns = cols
            elif cols != table_columns:
                errors.append(
                    f"{source.relative_to(ROOT)}:{row} TABLE COLUMNS: "
                    f"expected {table_columns}, got {cols}"
                )
            checked_tables += 1
        elif line.strip():
            table_columns = None

    if fenced:
        errors.append(f"{source.relative_to(ROOT)} UNCLOSED FENCED BLOCK")

checks = {
    "owner decisions": ("docs/book-01/08-g0-decision-record.md", "OD-11"),
    "independent A0": ("docs/book-01/agents/A0.md", "A5"),
    "A5 all UI": ("docs/book-01/agents/A5.md", "весь UI"),
    "one contract": ("docs/book-01/05-integration-contracts.md", "v1.0-CANDIDATE"),
    "sandbox continuation": ("docs/book-01/03-requirements.md", "FR-29"),
    "acceptance tests": ("docs/book-01/10-qa-acceptance-matrix.md", "CT-26"),
}
for label, (file, token) in checks.items():
    target = ROOT / file
    if target.exists() and token.casefold() not in target.read_text(encoding="utf-8").casefold():
        errors.append(f"CONTENT MISSING: {label} ({file})")

print(
    f"G0 DOCS: {len(DOCS)} files, {checked_links} local links, "
    f"{checked_tables} table lines, errors={len(errors)}"
)
for issue in errors:
    print("ERROR:", issue)
sys.exit(1 if errors else 0)
