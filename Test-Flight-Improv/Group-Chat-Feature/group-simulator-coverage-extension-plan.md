# Plan: Extend simulator tests to cover the full group interaction surface

## Context

Current group simulator coverage runs 8 scenarios (G1–G8) via paired `group_smoke_alice_harness.dart` + `group_smoke_bob_harness.dart`, orchestrated by `integration_test/scripts/run_routing_smoke_e2e.dart`. They cover publish/receive, warm send, bidirectional, offline drain, full lifecycle, peer discovery, key rotation under traffic, and a 2-peer flood-publish proxy for multi-member.

What's NOT covered at simulator level (but is in the codebase and partially in unit tests):
- Member-side **leave** (system message + key-rotation aftermath), last-admin **leave-blocked** guard, admin **kick** + key-rotation aftermath, **dissolve**
- **Decline invite**, **expired-invite** acceptance, **revoke pending invite**, **offline invite delivery**
- **Late-joiner** welcome-key flow, **offline-during-rotation** repair (`group_pending_key_repair_service`)
- **Group media** bidirectional (image with EXIF strip), **media upload retry/resume**, **reaction** fan-out
- **Group metadata propagation** (rename / description / avatar sync)
- **History gap repair** on reconnect
- **Background-resume** during in-flight send, **push tap → open group**
- **3-peer fan-out** on real libp2p, **role change** (promote/demote)

We have the building blocks: `reset_simulators.sh` already provisions 3 sims (A/B/C); `smoke_test_friends.sh` already runs a 3-device shell scenario registry. We will reuse those and refactor the 2-device dart orchestrator into a scenario-registry shape so adding a scenario = adding one file + one registry entry.

User decisions guiding the plan:
1. **Per-scenario reset** (clean simulator state every scenario) — failure isolation > speed.
2. **Add carol harness for the ~5 scenarios that need it**; reuse `reset_simulators.sh` for device provisioning rather than reinventing simctl logic.
3. **Extract a scenario registry**, port G1–G8 into it, add new scenarios in the same shape.
4. **Scope: fill simulator gaps only** (~19 new scenarios, 27 total). Do not duplicate strong unit-test coverage (envelope encoding, archive, mute, drafts, etc.).

### Relationship to coverage matrix

These scenarios complement `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, which tracks 49 P0 requirement rows. All matrix rows are already marked `Covered` via unit / host / fake-network / raw-Go evidence; many rows explicitly note paired-device/simulator proof is *"supporting only"* or *"was not run"*. The matrix's `evidence rows rule` accepts simulator as a valid evidence form alongside Go, raw-protocol, relay, device-lab, packet-capture, and privacy proof.

Each scenario below is annotated with the matrix row(s) it provides paired-iOS-simulator evidence for. Annotation legend:
- `matrix: <ROW>` — direct evidence for that row; passing run lets the matrix upgrade "supporting only / not run" to "simulator-proven".
- `matrix: <ROW> (partial)` — overlaps with the row but doesn't fully discharge its evidence requirement.
- `matrix: —` — no matrix row; scenario is genuinely additive UX-level coverage outside the P0 security/correctness scope.

13 of 19 new scenarios map to matrix rows; 6 (L02, M02, M03, B01, B02, S01) have no matrix row.

## Architecture

### Scenario registry (Dart)
New directory: `integration_test/group_smoke_scenarios/`

- `_types.dart` — `ScenarioStep` typedef + `GroupScenario` value type (id, description, peerCount, `matrixRows: List<String>` (empty list = no matrix coverage), optional alice/bob/carol step). No inheritance, no superfluous abstractions; consistent with project convention of top-level functions.
- `_signals.dart` — extract `_writeSignal/_waitForSignal/_writeJson/_waitForJson` from `group_smoke_alice_harness.dart` lines 41–80 into shared helpers. Keep `gsmoke_${runId}_<name>` naming; namespace per scenario as `<scenarioId>_<runId>_<name>` to prevent cross-run collision.
- `_registry.dart` — `const Map<String, GroupScenario> scenarioById` aggregating every scenario file's exported value.
- One file per scenario (`g01_publish_receive.dart`, …, `l03_kick_with_rotation.dart`, etc.). Each file exports a single `final GroupScenario <name>` constant.

### Harness dispatchers (thin)
- `integration_test/group_smoke_alice_harness.dart` — refactored to ~80 lines: boots real-DI context (reusing setup in `group_multi_device_real_harness.dart`), reads `SCENARIO_ID` dart-define, looks up registry, runs `scenario.alice` step.
- `integration_test/group_smoke_bob_harness.dart` — same shape, runs `scenario.bob`.
- `integration_test/group_smoke_carol_harness.dart` — **new**, same shape, runs `scenario.carol`. For 2-device scenarios (`peerCount == 2`), the orchestrator does not spawn this harness at all; if launched anyway by accident it returns early when `scenario.carol == null`.

### Orchestrator extension (`integration_test/scripts/run_routing_smoke_e2e.dart`)
- Add `--devices alice,bob[,carol]` flag (parser + validation).
- Add `--scenario <id>` for single-scenario runs and `--no-reset-between` for fast local iteration.
- Per-scenario reset: shell out to `reset_simulators.sh` between scenarios via `Process.run`, fail-fast on non-zero. (User confirmed `reset_simulators.sh` already handles 3 sims — reuse, don't reinvent.)
- Read `peerCount` from registry per scenario; only spawn harness processes for the peers that scenario uses.
- Pass `--dart-define=SCENARIO_ID=<id>` plus existing `E2E_SHARED_DIR`, `SMOKE_RUN_ID`, `E2E_DB_NAME`, `SMOKE_ROLE`.
- Aggregate results to `$E2E_SHARED_DIR/group_results.json` (`[{id, status, durationMs, retryCount, matrixRows, stderrTail}, ...]`); print a final pass/fail table including the matrix-row column; non-zero exit on any failure.
- One retry per scenario; record `retryCount`. Two consecutive fails = hard fail (avoid hiding regressions).

### Dart vs shell decision: keep Dart, invoke `reset_simulators.sh` between scenarios
Rationale: Dart owns scenario sequencing + signal IPC + result aggregation (where it's strong); shell owns sim provisioning (where it's strong, already 1300 lines of proven simctl logic in `smoke_test_friends.sh`/`reset_simulators.sh`). One source of scenario truth, no parallel orchestrator drift.

A thin `integration_test/scripts/run_group_e2e.sh` wrapper sets `E2E_SHARED_DIR` + `SMOKE_RUN_ID` then `dart run integration_test/scripts/run_routing_smoke_e2e.dart --suite=group --devices=alice,bob,carol`.

## Scenarios to add (19)

Each maps to a use-case file (top-level function per project convention).

**Lifecycle / membership**
- **L01** member voluntarily leaves group; remaining members observe `voluntary_leave` system message AND survivors rotate key (decrypt new messages, leaver cannot) — **3 peers** — `leave_group_use_case.dart` + `broadcast_voluntary_leave_use_case.dart` + `rotate_and_distribute_group_key_use_case.dart` (forward-secrecy on departure, mirrors L03 for the leave path) — `matrix: RP-014`
- **L02** last admin's leave is blocked — 2 peers — `leave_group_use_case.dart` (guard branch) — `matrix: —`
- **L03** admin kicks member; remaining peer rotates key and decrypts new messages; kicked peer cannot decrypt — **3 peers** — `remove_group_member_use_case.dart` + `rotate_and_distribute_group_key_use_case.dart` — `matrix: RP-017`
- **L04** admin dissolves group; both members observe `group_dissolved` system message — 2 peers — `dissolve_group_use_case.dart` + `delete_group_and_messages_use_case.dart` — `matrix: EC-006 (partial)`

**Crypto / membership-coupled**
- **C01** late joiner receives current welcome key and decrypts post-add messages — **3 peers** — `accept_pending_group_invite_use_case.dart` + welcome-key fields in invite payload — `matrix: EK-011, IJ-014`
- **C02** member offline during rotation; comes back online; `group_pending_key_repair_service` restores decryption — 2 peers — `rotate_and_distribute_group_key_use_case.dart` + `group_pending_key_repair_service.dart` — `matrix: EK-005, PREREQ-FUTURE-EPOCH-KEY-REPAIR`

**Messaging / media**
- **M01** group image bidirectional, EXIF stripped, thumbnail decrypts — 2 peers — `send_group_message_use_case.dart` (media branch) + `ImageProcessor` — `matrix: AB-006 (partial)`
- **M02** reaction add/remove fan-out; both members observe — **3 peers** — `send_group_reaction_use_case.dart` + `handle_incoming_group_reaction_use_case.dart` — `matrix: —`
- **M03** in-flight image upload interrupted (kill app mid-upload) resumes on next launch and is decrypted by peer — 2 peers — `retry_incomplete_group_uploads_use_case.dart` — `matrix: —`

**Background / push**
- **B01** in-flight `send_group_message` survives app backgrounding (lifecycle event), completes on resume — 2 peers — `recover_stuck_sending_group_messages_use_case.dart` — `matrix: —`
- **B02** push notification tap navigates directly into the correct group thread — 2 peers — push handler + group nav route. Use local `xcrun simctl push` fixture (no real APNs). — `matrix: —`

**3-peer fan-out**
- **F01** single send delivered to two peers via libp2p without relay fallback — **3 peers** — `send_group_message_use_case.dart` + GossipSub flood-publish path — `matrix: LP-002, LP-013`

**Negative paths / invitation lifecycle**
- **N01** decline invite leaves both sides clean (no group, no pending) — 2 peers — `decline_pending_group_invite_use_case.dart` — `matrix: EC-001`
- **N02** accepting an expired invite returns `expired` and creates no group — 2 peers — `accept_pending_group_invite_use_case.dart` (TTL branch) — `matrix: EC-001, EC-003`
- **N03** admin revokes pending invite before recipient accepts; recipient's pending state clears; subsequent accept fails cleanly — 2 peers — `revoke_pending_group_invite_use_case.dart` — `matrix: IJ-003`
- **N04** invite sent while recipient offline is drained from inbox on reconnect and renders as pending — 2 peers — `send_group_invite_use_case.dart` + `handle_incoming_group_invite_use_case.dart` + `group_invite_listener.dart` — `matrix: IJ-014 (partial)`

**Roles**
- **R01** promote member to admin; new admin can then kick — **3 peers** — `update_group_member_role_use_case.dart` — `matrix: RP-006`

**Settings / metadata propagation**
- **S01** admin renames group + changes description + updates avatar; member observes title/description update, system message, and new avatar bytes/hash — 2 peers — `update_group_metadata_use_case.dart` + `group_avatar_storage.dart` — `matrix: —`

**History / convergence**
- **H01** intentional message drop (kill connection mid-publish) is detected by peer on reconnect; gap is repaired and final history converges — 2 peers — `group_history_gap_repair_repository.dart` + repair protocol — `matrix: OS-006, PREREQ-HISTORY-GAP-REPAIR`

(Original gap list had `L05` / `L06` collapsed into `N01` / `N02`, same surface. Voluntary-leave key-rotation aftermath is folded into L01 as a 3-peer scenario rather than split into a separate L05.)

## Migration of G1–G8

Each inline block in `group_smoke_alice_harness.dart` lines 98–396 and `group_smoke_bob_harness.dart` becomes one scenario file under `group_smoke_scenarios/g0X_*.dart`:

- Move each block's body verbatim into a `ScenarioStep` closure (alice + bob halves).
- Signal names and dart-define reads stay identical (`gsmoke_${runId}_<name>`), so behavior is unchanged.
- Replace the in-harness if/else ladder (~300 lines) with the ~10-line dispatcher.
- **Sequencing:** ship G1–G8 ports first under the new dispatcher with no other changes; verify all 8 still pass; *then* add L/C/M/B/F/N/R. This catches port regressions before new-scenario noise.

## Files to modify / create

**Modify**
- `integration_test/group_smoke_alice_harness.dart` — reduce to dispatcher
- `integration_test/group_smoke_bob_harness.dart` — reduce to dispatcher
- `integration_test/scripts/run_routing_smoke_e2e.dart` — add 3-device support, per-scenario reset hook, registry-driven launch, `group_results.json` aggregation

**Create**
- `integration_test/group_smoke_carol_harness.dart` — new dispatcher
- `integration_test/group_smoke_scenarios/_types.dart`, `_signals.dart`, `_registry.dart`
- `integration_test/group_smoke_scenarios/g01_publish_receive.dart` … `g08_*.dart` (8 ports)
- `integration_test/group_smoke_scenarios/l01_member_leave.dart` … `h01_history_gap_repair.dart` (19 new: L01–L04, C01–C02, M01–M03, B01–B02, F01, N01–N04, R01, S01, H01)
- `integration_test/scripts/run_group_e2e.sh` — thin wrapper

**Reuse as-is (do not modify)**
- `reset_simulators.sh`
- `integration_test/group_multi_device_real_harness.dart` (shared real-DI base)
- `smoke_test_friends.sh` (referenced for pattern only)

## Verification

- **Full suite locally:** `./integration_test/scripts/run_group_e2e.sh` — provisions 3 sims, runs all 27 scenarios (G1–G8 + 19 new), writes `group_results.json`. Expected wall time ~35–45 min (per-scenario reset is the dominant cost).
- **Port verification (intermediate):** `./integration_test/scripts/run_group_e2e.sh --scenario G1 ... G8` — confirms no behavioral regression from the registry refactor before any new scenarios are added.
- **Single scenario (fast iteration):** `./integration_test/scripts/run_group_e2e.sh --scenario L03 --no-reset-between` — skips reset, runs once.
- **CI:** invokes the same wrapper; uploads `group_results.json` as an artifact; a follow-up step parses it and emits two GitHub Actions summary tables — (1) scenario pass/fail/duration/retry, (2) matrix-row → simulator status (which P0 rows are now simulator-proven). Existing dart-defines (`E2E_SHARED_DIR`, `SMOKE_RUN_ID`, `E2E_DB_NAME`, `SMOKE_ROLE`) are preserved; `SCENARIO_ID` is the only addition.
- **Unit tests stay green:** registry refactor must not require any change to `test/features/groups/**`.

## Risks / tradeoffs

- **Reset overhead:** ~25–30 s × 27 scenarios ≈ 11–14 min on top of scenario time. Mitigated by `--no-reset-between` for local dev; CI eats the cost (correctness > speed). Possible future optimization: skip reset only when next scenario's `peerCount` matches previous (deferred — not in this plan).
- **Carol maintenance surface:** keep the carol harness logic-free (dispatcher only); 6 scenarios use carol (L01, L03, C01, M02, F01, R01); resist scope creep beyond those.
- **libp2p / relay flakiness:** retry budget = 1/scenario, recorded as `retryCount` in `group_results.json`. Two consecutive failures = hard fail.
- **Out of scope (do not include):**
  - True OS-level backgrounding (only in-app `AppLifecycleState` transitions are simulated)
  - Multi-device same-user (already covered in unit tests at `test/features/groups/integration/group_multi_device_convergence_test.dart`)
  - Android simulators (separate concern)
  - Real APNs delivery for B02 (use `xcrun simctl push` fixture)
  - Surfaces already strongly unit-tested: envelope encoding, archive/unarchive, mute, draft persistence, last-admin guard logic detail, freshness-proof TTL math

## Implementation order

1. Create `_types.dart`, `_signals.dart`, empty `_registry.dart`. Add carol harness file (still empty dispatcher).
2. Refactor alice/bob harness to dispatcher; port G1 only into the registry; verify G1 passes.
3. Port G2–G8; verify all 8 pass.
4. Extend orchestrator: `--devices`, `--scenario`, `--no-reset-between`, per-scenario reset, `group_results.json` aggregation.
5. Add new scenarios in this order (most-blocking-coverage-first):
   - **Tier 1 — security/correctness critical:** L01, L04, L02, L03, C01, C02
   - **Tier 2 — invitation lifecycle (zero current simulator coverage):** N01, N02, N03, N04
   - **Tier 3 — metadata + media + UX:** S01, M01, M03, M02, B01, B02
   - **Tier 4 — convergence + multi-peer:** F01, H01, R01
6. Wire `run_group_e2e.sh` and update CI workflow to run it.
