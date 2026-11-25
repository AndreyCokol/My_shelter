# SDD — LD-01: Local-first Windows delivery (2026-11-25)

**Owner requirement; applies to A0–A5.** Local playable Windows installation is the primary owner acceptance target; GitHub is the versioned source, review and evidence system. Both must be current for every accepted integrated candidate. This requirement is not permission to publish unlicensed binaries publicly.

## Delivery design and responsibilities
1. A1–A5 commit tested changes to their own branches/PRs with exact SHA and handoff. A5 integrates; A1 owns build infrastructure; A0 reviews and tracks delivery. Only the agreed integrated candidate is activated, never an arbitrary agent branch.
2. Build Windows x64 from exact accepted source SHA, run regression tests and executable startup smoke, verify SHA256 and size. Deliver privately to the owner or build locally. GitHub publication of source/approved artifacts respects existing review, rights and G0/G4 gates. PR #188 is the existing delivery implementation, not proof of installation.
3. Stage immutable versions, verify before switching active state atomically; retain last-good and rollback. Never erase saves, overwrite local uncommitted work, force-reset a checkout or force-close a running game. Defer switch safely when needed.
4. Automatic delivery after integration acceptance and retry when PC/network becomes available; no repeated manual archive downloads. Stable launcher must work offline with the installed version. Failed delivery retains last-good and reports discrepancy.
5. **Mandatory owner-selected checkout path:** `%USERPROFILE%\AgentProjects\My_shelter`. The owner confirmed AgentProjects is empty; clone there initially, then A1/A5 must synchronize this exact checkout to every accepted integration SHA. Export and safely promote the verified executable at the stable owner-facing path `%USERPROFILE%\AgentProjects\My_shelter\build\windows\MyShelter.exe`; preserve last-good on failure. Do not use an alternative checkout as the owner delivery target. The separate versioned installer below may remain a rollback/launcher mechanism. The default branch currently contains documentation, so cloning alone does not constitute a playable delivery. Installation convention from PR #188: `%LOCALAPPDATA%\MyShelter\MyShelter.cmd` (stable launcher), `versions\<active_sha>\MyShelter.exe` (actual EXE relative to install root), `state.json`, `UpdateMyShelter.cmd`, `RollbackMyShelter.cmd`. Paths are conventions, not evidence that installation exists.
6. A0 records GitHub PR/commit, exact source SHA, local EXE path, SHA256, install timestamp, smoke result and active SHA from local state. A local confirmation is necessary to claim delivery complete. If local access is unavailable, report LOCAL DELIVERY PENDING rather than Done; retain the latest verified installed build. Source and binary should not silently diverge.

## Acceptance checks
- Accepted integrated GitHub SHA matches local active SHA and the EXE manifest; launch works offline.
- Next accepted candidate reaches the same launcher automatically; owner need not download each update.
- Network failure, corrupted package, running game, local dirty checkout and rollback are handled without losing saves or working build.
- Separate public release approval is still required; no bypass via public Actions artifacts.
- Status values: LOCAL VERIFIED / LOCAL DELIVERY PENDING / FAILED (last-good retained). No claim of LOCAL VERIFIED without actual owner-PC evidence.
