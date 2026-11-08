# ADR-0001 — Retention of command receipts without duplicate gameplay effects
**Status:** PROPOSED / NOT APPROVED, 2026-11-08. Issue [#35](https://github.com/AndreyCokol/My_shelter/issues/35) (A0-F05). Owners A1 core, A5 chief integration, A0 independent review.

## 1. Verified problem
The current `CoreSession.execute` stores each successful command as `completed_actions[action_id]={fingerprint,result}` inside the entire durable campaign JSON. This is crucial: retry of the same ID returns the original receipt without another effect even after load. `CampaignModel.validate` examines every receipt; full checkpoint rewrites and save size grow with campaign length.

`GameApp.next_action()` currently generates ID from wall-clock UNIX time, process tick microseconds and a local serial; **the ID has no persisted monotonic sequence**. Therefore arbitrary old IDs cannot be classified as "already executed" once their receipt has been removed.

`GameplayState.validate` additionally **dereferences** `completed_actions[resident.food_receipt_id].result.data` for joined residents, validates actual food allocations and active reservations. Blind pruning breaks the resident invariant and can make a legitimate slot unloadable. Some inventory instance IDs also embed source `action_id` (e.g. `grant:<action_id>` and `split:<action_id>`); keep IDs stable during any future migration.

The bounded 4096 recent-ID `EventBus` cache in PR #58 is **not** the durable receipt ledger and does not address F05.

Evidence from the real Linux CI F03 synthetic fixture ([run 42501725391](https://github.com/AndreyCokol/My_shelter/actions/runs/42501725391)): JSON-sized state 17,506 bytes at 100 receipts, 164,206 bytes at 1,000, 1,658,206 bytes at 10,000 (30-scenes fixture). These figures show growth in the fixture only, not a production save-space forecast.

## 2. Non-negotiable safety invariants
R1. No second grant, XP reward, crop harvest, purchase, NPC admission, time rest or other effect on retry, including after process restart.
R2. Same action ID + same semantic payload returns original receipt while its detailed receipt is retained; different payload returns ACTION_CONFLICT for retained IDs. No old unknown ID may silently become a fresh command.
R3. All `food_receipt_id` and any future explicit receipt foreign keys must resolve, or the domain must receive a formally reviewed migration to independent durable evidence.
R4. A failed write/load leaves the previous primary/backup accessible; never prune before atomic checkpoint.
R5. For schema v4 and other legacy IDs, **keep all prior receipts** unless a reviewed explicit migration or retained archive provides the same guarantees. Never trim the v4 dictionary by size alone.
R6. Do not claim both (a) indefinitely returning the exact original response for arbitrary unbounded IDs and (b) bounded persisted history with no auxiliary archive: these goals cannot hold simultaneously without changing the command contract.

## 3. Decision options
**Option A — P0 safest:** preserve full `completed_actions` under existing schema v4; add *read-only* size/latency diagnostics and private checkpoint warnings only. F03 fractional tick optimization PR #68 mitigates frame copy cost, but command save time/JSON disk size remain O(N). No behavior change, and no hazardous pruning. Recommended for the first closed prototype.

**Option B — future v5 compact retention:** require a *new explicit contract*, because old replay results cannot be retained forever in bounded space. Generate `action_id` under durable per-campaign/per-actor monotonically increasing sequence, not a wall-clock string. Persist `highest_committed_sequence`, `retention_floor`, a bounded recent full-receipt window, and independently retained `pinned_receipts` for domain foreign keys/unique grants. Every request with a sequence at or below the floor and without detailed retained receipt must return a new **REPLAY_EXPIRED/STALE_ACTION** error with **zero mutation**. This deliberately changes the exact-original-result guarantee for expired IDs, so needs A1/A5 review and decision on contract semantics. New action sequence must be greater than durable high-water; abandoned attempts may create gaps. On save/load, derive the next sequence from durable high-water; reject foreign campaign IDs. Pinned linked receipts may still grow if residents are unbounded, so "bounded global save" requires separately normalizing evidence into resident records and reviewing all foreign keys.

**Option C — historical archive:** move old receipts to an append-only sidecar and keep a bounded hot cache, retrieving archival receipts on replay. Preserves exact responses with no expired ID, but **total disk use still grows** and atomic two-file checkpoint/recovery is harder. No code change until transactional design and failure tests.

## 4. Proposed staged work (no silent schema changes)
1. **Now:** keep schema4 receipts intact. Add negative tests for deleting a joined resident's receipt and verify restore/replay behavior. Collect isolated core tick + checkpoint size measurements; distinguish CLI benchmark from actual Windows GUI and heap profiler.
2. **Technical review:** A1+A5 decide Option A for P0 and whether Option B's explicit error for expired historical IDs is acceptable for later schema v5. A0 reviews threat model for replay/reward duplication. No new owner product question if unchanged P0 policy.
3. **If Option B selected:** record G0/API ADR, exact schema v5, ID migration, pin sets, stable IDs, results/error code, crash matrix, backup rules and compatibility with schema3/schema4 **before** modifying `CoreSession`.
4. **Migration:** keep legacy v4 ledger on load/backup; explicit upgrade to v5 with new sequenced IDs for future commands. No forced rewrite of old slots and no deletion on a read-only load. Verify receipts referenced by residents before changing their representation.
5. **CI:** execute on Linux and Windows with 100/1000/10000/100000 actions, restart/replay inside/outside retention window, same ID changed payload, NPC/potato receipts, save failure before/after replace, mixed old and new schema, invalid foreign campaign ID and rejected old replay. Measure save size and CPU; do not choose an arbitrary acceptable threshold without profiling.

## 5. Gate and current outcome
**Decision:** Candidate Option A for P0; Options B/C reserved for independently reviewed later work. No runtime storage reduction is claimed. This ADR is evidence/plan, **not a migration implementation** and does not change #35 to DONE or G0 to APPROVED.
