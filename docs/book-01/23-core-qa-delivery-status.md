# CORE/QA/DELIVERY — Windows GUI & performance evidence protocol (2026-11-09)

**Owner:** CORE/QA/DELIVERY, working under A5. Independent A0 and owner G0/G4 approvals are **not** implied by this document.
**Repository:** `AndreyCokol/My_shelter`
**Shared baseline:** PR #130, `a1ae8c0b68017ea4f4067a677a2d94029e1cac1d`.
**Combined technical candidate:** [PR #145](https://github.com/AndreyCokol/My_shelter/pull/145), `23ce02ca1b8605173b0514c2592334336b9a9d9d`.
**Related CORE-only patches:** [PR #134](https://github.com/AndreyCokol/My_shelter/pull/134) (HUD snapshot); [PR #141](https://github.com/AndreyCokol/My_shelter/pull/141) (backup atomicity).
**Related VISUAL branch:** [PR #135](https://github.com/AndreyCokol/My_shelter/pull/135) (HUD implementation and UI tests), exact content integrated in PR #144/#145.

## Status — not a signoff

| ID | Status | Evidence or blocker |
| --- | --- | --- |
| CORE-01 / NX-01 | IN_PR | Exact six-file union in PR #145. Count its CI only after all Linux, Windows and docs runs finish successfully on this SHA. |
| CORE-02 / NX-04 | NOT_RUN | No physical or remote interactive Windows desktop available to this agent. Headless CI is not a human walkthrough. |
| CORE-03 / NX-05 | NOT_RUN | No 30-minute continuously rendered Windows session; average/P95/P99 frametime, FPS, RAM/VRAM and save latency not measured. |
| CORE-04 / NX-06 | CI_PASS | PR #141: 27 new save-failure checks + 38 prior crash checks; Linux, Windows headless and docs pass. Real power-off and physical ENOSPC NOT_RUN. |
| CORE-05 / NX-17/18 | TODO | 3/7/14-day real action-chain campaign scenarios and optional NPC/quest progression require dedicated end-to-end work. |
| CORE-06 / NX-20/21 | BLOCKED | A0 independent review, original R1–R4 owner reference approval, licensed private delivery asset inventory, 15–35min GUI, 30min native FPS and owner G0/G4 acceptance remain outstanding. |

## CORE-02: interactive Windows x64 walkthrough — exact protocol

**Gate:** test a single pinned commit. Tester supplies executable SHA256 and its source commit; the CI-verified export alone is insufficient. Test on Windows 10/11 x64 in an **isolated Windows account or disposable VM**, never against the player's existing `user://saves`. Run Godot 4.7.2 build. Record OS build, CPU, GPU, RAM, graphics driver, game commit and EXE SHA256.

**Setup:** video/screen capture with clock, raw input trace/notes, action/expected/observed/pass/bug-ID log, and original save fixture hash. Begin with 1280×720 window; repeat UI/input stress at 1920×1080. Note actual frame content and whether G/E/Ctrl hit the right targets. Do not change saved state or graphics fixtures outside this test profile.

| Minute range (planning only) | Operator action | Required observation |
| --- | --- | --- |
| 00–03 | Launch fresh EXE, read Q01/Q02 and move via WASD/arrow keys; use E, Esc, left Ctrl | No focus traps, no fake UI stats, no stuck pause or overlapped radial menu |
| 03–07 | Enter a procedural hospital through street door, use stairs, look for exit and loot, fight using LMB and Space | Real collision, LOS and enemy pursuit, input works without clicking through UI |
| 07–10 | **Before the first victory**, press G from hospital; in shelter press G again | Shelter works before victory, returns to the **same scene and actual saved position**; no scene/HP/aggro reset |
| 10–14 | Defeat first zombie, check one set of XP/loot/reward, return by G, inspect inventory and storage | Single reward/action receipt; no duplicate items or negative inventory |
| 14–20 | Plant, inspect grow/rest preview, harvest if eligible; inspect food, warehouse and volunteer resident consent/work | Time, food and resident state tied to actual campaign; decline NPC and still free-roam |
| 20–26 | Save using UI, exit `MyShelter.exe` completely, restart, load same save, retry previously completed action | Same scene/position/HP/crops/stock/quest and single victory reward; no silent reset |
| 26–35 (optional) | Repeat 1280×720/1920×1080, windowed/fullscreen, Alt+Tab, all modals and left Ctrl wheel | No clipped panels, lost key-up, transparent click-through or inability to close a modal |

**Required artifacts per test:** original uncut video (or direct screen recording), log line for every step with wall clock, PC configuration, EXE SHA256, before/after isolated save SHA256, 720p and 1080p screenshots, and severity-ranked issue links. Mark `GUI_PASS` **only** after witnessed execution, including E/G/Space/Ctrl and save/restart/load.

## CORE-03: actual 30-minute rendered Windows frame/memory soak

**Status: NOT_RUN / measured values: NOT_MEASURED.** Synthetic `108000 tick` CI is excluded from this measurement. Use exactly the same pinned EXE SHA as CORE-02; Windows desktop must be rendering frames continuously for at least 1800 real seconds.

1. Start frame-time capture via an installed ETW/PresentMon-compatible recorder; record its **exact version**, monitor, graphics adapter, display refresh rate and raw CSV. Capture actual presented-frame time, not campaign tick or CPU simulation time.
2. Start process memory/CPU sampling at **1 sample/sec** with an external tool. Record WorkingSet64, PrivateMemorySize64, handles, process CPU time and system physical RAM. If vendor/OS GPU memory API is available, record dedicated VRAM; otherwise mark VRAM `NOT_MEASURED` (never infer from textures).
3. Timeline: 0–5min outdoor street/hospital traversal; 5–10min real combat/AI; 10–15min open/close UI panels at least 10 times; 15–20min shelter/plant/harvest/volunteer NPC; 20–25min transition by G and doors; 25–30min growing receipt journal + one explicit save/reload. Capture action timestamps to join frame and memory peaks with game transitions.
4. Each save/load has a stopwatch interval and before/after file size+SHA256. Keep the profile isolated. Record Windows OS build, CPU, GPU, driver, RAM, 1280×720 and 1920×1080 runs separately. To compare resolutions fairly, each needs its own full 30 minutes.
5. Analysis: report frame-time **mean, median, P95, P99** in milliseconds over non-empty valid presented frames, FPS mean (total frames divided by measured elapsed seconds), and 1% low FPS with explicitly documented formula; count frame gaps/stalls, process RSS/working-set peak, private-bytes peak, VRAM peak if available and measured save/load latency. Retain **raw logs** and analyze by same SHA.
6. Acceptance: never stamp a numeric 60 FPS PASS without measured samples; do not disguise software OpenGL headless screenshots, 108000 virtual ticks or a ten-second exported EXE smoke as live Windows gameplay.

Example Windows memory sampling in an **isolated test account** (run from PowerShell, stop after the 30-minute session):
```powershell
$log = Join-Path $PWD "myshelter-process-memory.csv"
for ($i = 0; $i -lt 1800; $i++) {
    $p = Get-Process -Name MyShelter -ErrorAction Stop | Select-Object -First 1
    [pscustomobject]@{
        TimestampUtc = [DateTime]::UtcNow.ToString("o")
        WorkingSetBytes = $p.WorkingSet64
        PrivateBytes = $p.PrivateMemorySize64
        Handles = $p.HandleCount
        CpuSeconds = $p.CPU
    } | Export-Csv -Path $log -NoTypeInformation -Append
    Start-Sleep -Seconds 1
}
```
This records **memory only**; it is not an FPS logger. Use raw frame-time capture alongside it. Note sample timing jitter and partial sessions.

## CORE-04: additional negative / migration boundary

- PR #141 isolated failure suite directly tests saved primary and prior `.bak` byte equality when primary rename fails, partial `.bak.tmp` copy, staging refusal, commit-before-backup promotion and single receipt/reward after reload.
- Failure of backup promotion **after** committed primary may leave an older but valid backup. It is not an uncommitted action; the next successful save repairs the backup. This two-file ordering is crash-tolerant but not a fully atomic transaction of two file names.
- Existing v4-layout compatibility fixtures/38 crash checks must remain in combined CI. Add later dedicated real migrated archive-slot and physical disk-full/deny-rename trials in a disposable VM. A real hard power-off is **never** a regular CI action.

## CORE-06: FR → test → observed GUI → SHA → reviewer

| FR or requirement | Automated test | Real GUI observed | SHA or PR | Independent reviewer |
| --- | --- | --- | --- | --- |
| G shelter before first victory, return exact place | gameplay + router tests | NOT_RUN | PR #145 | A0 PENDING |
| One-time victory reward after failure/load | crash checks 38 + save failure checks 27 | NOT_RUN | PR #141 / unified PR #145 | A0 PENDING |
| HUD/rest read-only without durable journal copy | `run_ui_content_tests.gd` + `game_app.gd` | NOT_RUN | PR #144 / unified PR #145 | A0 PENDING |
| Windows PC 720p/1080p input and overlays | runtime/UI automated tests | NOT_RUN | PR #145 | A0 PENDING |
| Native 30-minute FPS/RAM | 108k accelerated ticks **not equivalent** | NOT_RUN | GUI build SHA pending | A0 PENDING |
| R1–R4 exact pixel reference and original copyright | Visual-only contract | NOT_RUN | VISUAL-owner evidence pending | A0 PENDING |
| Portable Windows offline ZIP, exact SHA, credits/licenses | Windows offline headless smoke only | NOT_RUN | delivery SHA pending | A0 PENDING |
| Owner G0/G4 | no substitute | NOT_RUN | final unified SHA pending | OWNER PENDING |

## Release / delivery controls

- PR #131 is a temporary private executable upload workflow and must **never** be merged into `main`. No rights to redistribute proprietary book/PNG assets are inferred from CI success.
- Deliver an owner-only ZIP **only when** it is built from the final unified code SHA, contains a README with version, exact SHA and license/source manifest, has a recorded ZIP SHA256 and passes extract/Windows offline smoke and archive-integrity checks.
- `CI_PASS` does not imply `GUI_PASS`, `REVIEWED` or `OWNER_ACCEPTED`. A0 independent review cannot be signed by CORE. Only owner may approve G0/G4 or authorize merge.
