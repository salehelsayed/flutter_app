Status: accepted

# Doc 114 Session S4 Plan - Host Loopback Integration And Version-Skew Pins

## Planning Progress

- 2026-06-13T07:13:00Z - Evidence Collector completed. Files inspected since last update: breakdown S3/S4 ledger, source doc Phase 4 and evidence bar, existing S4 plan closure/tests/done criteria, graphify-arch exact-symbol output, and parent device evidence. Decision/blocker: S4 can remain host implementation-ready, but required closure must be host-only because command `16` device proof is already schema-gated before LAN behavior. Next action: patch proof profile and dependency wording.
- 2026-06-13T07:10:00Z - Planning intake restarted for tightening only. Files inspected since last update: planning skill, graphify skill, S4 plan, S4 breakdown entry, source doc Phase 4 anchors, and exact-symbol graphify-arch query for `local_ws_durable_ack_integration_test.dart`, `wifi_relay_fallback_smoke_test.dart`, `ml_kem_key_updated_ts`, and `run_with_devices.sh`. Decision/blocker: no code/tests will run; required correction is a device/relay proof profile plus S3 dependency wording. Next action: complete Evidence Collector pass against the existing plan and named docs.
- 2026-06-13T06:29:20Z - Arbiter completed. Files inspected since last update: S4 draft plan, reviewer findings, doc 114 Phase 4 checklist, current S1-S3 closure ledger, and graph refresh rule. Decision/blocker: no structural blocker remains; S4 is host integration plus explicit device residual only. Next action: execute this plan only after S1-S3 remain accepted in the breakdown.
- 2026-06-13T06:28:50Z - Reviewer completed. Files inspected since last update: S4 draft sections, `local_ws_integration_i1_i2_test.dart`, `local_ws_server_test.dart`, staging DB helper tests, and doc 114 Phase 4. Decision/blocker: plan is sufficient with one adjustment: do not require the full message repository/listener stack for every row if a real `inbox_staging` DB plus replay callback proves the loss window; reserve production fixes for actual integration failures. Next action: arbiter classification.
- 2026-06-13T06:28:10Z - Planner completed. Files inspected since last update: S4 source phase, existing loopback integration test, local WS ack tests, staging DB helper tests, S1-S3 ledger entries. Decision/blocker: S4 should be implemented as one host-runnable integration test file plus narrow production fixes only if the composed path exposes a bug. Next action: reviewer pass.

## real scope

S4 adds host-runnable integration coverage that composes the already-landed S1-S3 seams over real loopback `LocalWsServer` sockets and a real `sqflite_common_ffi` `inbox_staging` database.

In scope:

- Add `test/core/local_discovery/local_ws_durable_ack_integration_test.dart`.
- Use real `LocalWsServer` instances over loopback, not mDNS or device discovery.
- Use real `inbox_staging_entries` schema/helper functions through `sqflite_common_ffi`.
- Prove the Phase 4 loss-window/version-skew rows that can be host-proven without OS/device fixtures.
- Patch only S1-S3 owner production code if a real composed loopback/staging bug is exposed.
- Record simulator/device-only evidence as S5 residual if the host suite cannot prove it.

Out of scope:

- No gate-array or test classification changes; S5 owns those.
- No final source-doc closure wording; S5 owns it.
- No docs 115/116 edits.
- No Go, relay, gomobile, native platform, notification, or mDNS changes.
- No sender policy redesign beyond fixing actual integration regressions in S1-S3 code.

## closure bar

S4 is accepted when host tests prove:

| Phase 4 requirement | Planned S4 proof |
|---|---|
| Receiver killed after committed ack does not lose the message | A real WS sender receives `LanSendAck.committed`; replay is held so the receiver is torn down with a `lan:<nonce>` row still in a real DB; a restarted staging repository/replay sweep over the same DB replays the row exactly once and deletes it. |
| Decrypt failure after committed ack quarantines instead of losing | A committed LAN row is replayed with a quarantined/decryption-failed outcome; the row remains `quarantined` with reason metadata and envelope intact. |
| Old sender matcher accepts committed ack within interactive budget | A raw old-client matcher (`ack == true && nonce == n`) connects to a new committing receiver and matches the committed frame within 1500ms. |
| New sender against old receiver classifies parse-time ack as legacy | Real `LocalWsServer.sendMessageWithAck` talks to an unconfigured/old-style receiver and returns `LanSendAck.legacyAck`. |
| Rejected commit nack resolves promptly and cannot mint delivered/local | New receiver rejects; `sendMessageWithAck` returns `LanSendAck.failed` promptly. If a composed send-use-case assertion is added, it must end `inboxed` or retryable `sent`, never `delivered/local`. |
| Old matcher skips nack and times out into fallback | Raw old-client matcher receives `ack:false` from a rejecting new receiver, does not match it, and times out within the old budget. |
| Media-bearing LAN replay after kill is not silent loss | Host-level proof may be reduced to a staged LAN chat envelope containing media metadata replaying exactly once and preserving the envelope/attachment metadata. Full relay-media fallback/device proof remains S5 residual unless an existing host fake can prove it without broad media stack work. |

Host closure is not final doc 114 closure. Real mDNS/device, mixed-version binaries, notification, and media fallback device proof remain S5 residuals unless S4 can run an existing simulator scenario that directly covers them.

## source of truth

- Current code and tests beat stale prose.
- `Test-Flight-Improv/114-lan-ack-after-commit.md` Phase 4 defines the S4 checklist.
- `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md` is the ledger and currently records S1-S3 as accepted/closed.
- `test/core/local_discovery/local_ws_integration_i1_i2_test.dart` is the host loopback style model.
- `test/core/database/helpers/inbox_staging_db_helpers_test.dart` is the real SQLite staging helper style model.
- `test/core/local_discovery/local_ws_server_test.dart` is the ack-frame and raw-WS behavior reference.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are gate sources; S5 owns any classification/gate-array edits.
- Graph usage: exact-symbol `graphify-arch` queries are orientation only. After S4 code/test changes, run `./graphify-arch/refresh_arch_graph.sh` from repo root. Never run `graphify update` or extraction inside `graphify-arch`.

## session classification

`implementation-ready`

S4 is implementation-ready as a host integration session, with device-only proof explicitly residual for S5.

## exact problem statement

S1-S3 now implement the protocol, receiver staging, and sender truthfulness seams independently. Missing S4 proof is the composed real-socket host behavior: committed ack over actual WebSocket loopback must imply durable `lan:<nonce>` custody, the staged row must survive receiver teardown and replay on restart, replay failure must quarantine instead of disappearing, and old/new ack compatibility must be pinned over real frames rather than only unit fakes.

## files and repos to inspect next

Production files, only if integration exposes a bug:

- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`

New and existing tests:

- `test/core/local_discovery/local_ws_durable_ack_integration_test.dart`
- `test/core/local_discovery/local_ws_integration_i1_i2_test.dart`
- `test/core/local_discovery/local_ws_server_test.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/database/helpers/inbox_staging_db_helpers_test.dart`

Gate/config files:

- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` for inspection only; do not edit in S4 unless the plan is refreshed because S5 is no longer the owner.

## existing tests covering this area

- `local_ws_server_test.dart` already proves handler withholding, committed ack shape, explicit nack, timeout nack, legacy ack shape, and `sendMessageWithAck` classification.
- `local_ws_integration_i1_i2_test.dart` already proves real loopback legacy text/media transport and stale host/port behavior.
- `p2p_service_impl_test.dart` already proves S2 LAN staging/replay dispositions at service-unit level.
- `send_chat_message_use_case_test.dart` already proves S3 sender truthfulness and legacy/bool backstop at application level.
- No current host test composes real WS ack frames with real `inbox_staging` DB custody or raw old-matcher behavior.

## regression/tests to add first

Add tests in `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` before any production changes:

1. `receiver killed after committed ack does not lose the message: staged row replays on restart`
2. `decrypt failure after committed ack quarantines the staged row instead of losing the message`
3. `old sender matcher accepts committed ack within the interactive budget`
4. `new sender against old receiver classifies parse-time ack as legacy and non-durable`
5. `rejected commit nack resolves the sender promptly with no delivered state possible`
6. `old sender matcher skips a nack frame mid-wait and times out into fallback`
7. `media-bearing LAN message replay after receiver kill preserves text and media metadata without silent loss`

If a full message repository/listener stack makes the first/media tests too broad, keep S4 host-scoped by using a real DB-backed staging repository plus deterministic replay callbacks that count/dequeue rows and inspect stored envelopes. Escalate full UI/media/device proof to S5 residual rather than widening S4 into a media subsystem rewrite.

## step-by-step implementation plan

1. Create `local_ws_durable_ack_integration_test.dart` with the same host-runnable header style as `local_ws_integration_i1_i2_test.dart`.
2. Build small helpers for:
   - real `LocalWsServer` sender/receiver lifecycle;
   - in-memory `sqflite_common_ffi` DB with `runInboxStagingEntriesMigration`;
   - staging a LAN envelope through a commit handler that writes `lan:<nonce>` rows before returning committed;
   - replaying recoverable rows from the same DB with committed/retry/quarantine outcomes;
   - raw old-sender WebSocket matcher for `ack == true && nonce == expectedNonce`.
3. Add the loss-window tests first and prove they fail only if custody/replay glue is absent.
4. Add version-skew tests using raw WS clients and real `sendMessageWithAck`.
5. Add the media-metadata preservation host test. Keep it envelope/row/replay focused unless existing fake media helpers make relay fallback proof cheap.
6. Patch production only if the new host tests expose a real composed bug in S1-S3 seams.
7. Run focused host tests, then named gates and graph refresh.
8. Record device/simulator proof as residual if the existing simulator command cannot match or does not exercise committed LAN ack behavior.

## risks and edge cases

- Real socket timing can be flaky if tests use long ack timeouts; keep explicit small test budgets where possible.
- A real DB-backed staging helper may require small test-only adapter code; do not create production-only abstractions for tests.
- Holding replay to simulate receiver kill must not leak async work or open sockets.
- Old matcher should skip nack frames, not treat them as success or test failure.
- Media-bearing proof can easily become too broad; preserve text/envelope metadata in S4 and leave full relay-media/device proof to S5 if needed.
- New file classification may make completeness fail. S4 should record it; S5 owns classification/gate-array edits unless S4 is explicitly re-scoped.

## exact tests and gates to run

Focused S4 tests:

```bash
flutter test test/core/local_discovery/local_ws_durable_ack_integration_test.dart
flutter test test/core/local_discovery
```

Regression checks for touched production files if any production code changes:

```bash
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
```

Named gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh completeness-check
```

Simulator/device residual attempt if an existing scenario matches:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_relay_fallback_smoke_test.dart
```

Graph refresh after code/test changes:

```bash
./graphify-arch/refresh_arch_graph.sh
```

If `uv tool upgrade graphifyy` occurs before graph rebuild:

```bash
rm -rf graphify-out/cache/ast
./graphify-arch/refresh_arch_graph.sh
```

## known-failure interpretation

- `completeness-check` may fail solely because `local_ws_durable_ack_integration_test.dart` is a new unclassified file. Record exact output and leave classification for S5 unless S4 is re-scoped.
- Device/simulator unavailability or no matching `--only` scenario is a S5 residual, not an S4 host blocker.
- Retry-unacked doc 115 P3 failures recorded during S3 remain outside S4 unless the new S4 diff touches those files.
- Failures in broad dirty worktree files outside S4 owner files should be classified as pre-existing unless reproduced by the focused S4 diff.

## done criteria

S4 is done when:

- `local_ws_durable_ack_integration_test.dart` exists and is host-runnable with real loopback WebSockets and real SQLite staging.
- Host tests prove committed ack after staging, restart replay deletion, quarantine disposition, committed old-matcher compatibility, legacy ack classification, rejected nack prompt failure, old-matcher nack timeout, and media metadata preservation or an explicit media residual.
- Any production fixes are limited to S1-S3 owner code and are justified by failing S4 tests.
- Focused S4 tests pass.
- `flutter test test/core/local_discovery` passes, or failures are precisely classified.
- `./scripts/run_test_gates.sh 1to1` passes, or failures are precisely classified.
- `./scripts/run_test_gates.sh completeness-check` passes or records the new-file classification residual for S5.
- Simulator/device smoke is run if a matching existing scenario exists, otherwise S5 residual is recorded.
- `./graphify-arch/refresh_arch_graph.sh` passes from repo root after S4 edits.

## scope guard

Do not in S4:

- edit docs 115/116 or their session artifacts;
- edit `scripts/run_test_gates.sh` or `test-gate-definitions.md` unless the plan is explicitly refreshed because S5 ownership changed;
- add device-only mDNS or notification fixtures;
- change relay, Go, gomobile, native platform code, or media transport product behavior;
- rewrite sender race policy or receiver replay architecture;
- add broad DB migrations.

Overengineering signals:

- building a new staging repository abstraction solely for tests;
- pulling full UI notification behavior into host loopback tests;
- making media fallback assertions depend on device-only transport when row/envelope metadata is enough for S4;
- treating a classification-only completeness failure as an implementation bug.

## accepted differences / intentionally out of scope

- Full device mDNS, previous-build/new-build binary skew, and notification evidence remain S5 residuals unless an existing simulator scenario covers them directly.
- The media-bearing LAN replay test may prove host text/envelope/metadata preservation only; full relay-media fallback on device is S5 residual if no cheap host fake exists.
- S4 does not claim final doc 114 closure and does not update source doc closure logs.
- Classification/gate-array edits for the new test file remain S5 by decomposition design.

## dependency impact

- S5 depends on S4's new test name, pass/fail evidence, completeness classification status, and residual list.
- If S4 discovers a production bug in S1-S3 seams, S5 must cite the final fixed behavior and tests rather than earlier unit-only evidence.
- If S4 cannot add the integration file without broad fixture work, S5 must mark doc 114 `still_open` or `accepted_with_explicit_follow_up` rather than overclaim closure.

## reviewer findings

Reviewer verdict: sufficient with one adjustment, already reflected.

- Missing files/tests/gates: none structural; the plan names the new host file, local discovery suite, `1to1`, completeness, simulator residual attempt, and graph refresh.
- Stale assumptions: Phase 4 prose asks for full message repo/media fallback in places; current S2/S3 host seams make a row/envelope/replay proof sufficient for S4 host closure, with device/media fallback residual in S5.
- Overengineering: avoid building a new full app stack in a local-discovery integration test.
- Decomposition: narrow enough; S4 composes S1-S3 and leaves docs/gate closure to S5.

## arbiter decision

Arbiter verdict: execution-ready.

Structural blockers: none.

Accepted differences:

- S4 host closure may be row/envelope/replay focused for media metadata and does not need full device relay-media fallback.
- S4 may leave new-test gate classification to S5 and record completeness residual if needed.
- S4 does not claim final doc 114 closure.

Why safe to implement now: S1-S3 are accepted in the breakdown, the existing repo has clear loopback and staging helper patterns, and every Phase 4 host-runnable checklist item has a concrete proof or an explicit S5 residual.

## Execution Progress

- 2026-06-13T06:30:10Z - Implemented `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` as a host-runnable real loopback suite over `LocalWsServer` plus a real `sqflite_common_ffi` `inbox_staging` database. No production code changes were needed in S4.
- 2026-06-13T06:31:00Z - Fixed test-only compile and lint issues: moved shared peer ids to top-level scope, removed an unused import, and replaced `catchError` cleanup with `_deleteDbPath`.
- 2026-06-13T06:31:30Z - Focused verification passed: `dart analyze test/core/local_discovery/local_ws_durable_ack_integration_test.dart` reported no issues, and `flutter test test/core/local_discovery/local_ws_durable_ack_integration_test.dart` passed. Log: `/tmp/doc114_s4_focused_after_cleanup.log`.
- 2026-06-13T06:32:20Z - Local-discovery sweep passed: `flutter test test/core/local_discovery` completed at `+118`. Log: `/tmp/doc114_s4_local_discovery_final.log`.
- 2026-06-13T06:34:00Z - Named 1:1 gate passed: `./scripts/run_test_gates.sh 1to1` completed at `+593`. Log: `/tmp/doc114_s4_1to1.log`.
- 2026-06-13T06:34:10Z - Completeness check passed with the new file already classified: `841/841 test files classified`. Log: `/tmp/doc114_s4_completeness.log`.
- 2026-06-13T06:34:25Z - Simulator wrapper evidence attempted: `run_with_devices.sh 1to1 --only integration_test/wifi_relay_fallback_smoke_test.dart` resolved simulator ids but reported no runnable reliability simulation command matched the requested resume filter. Log: `/tmp/doc114_s4_sim_smoke.log`. This remains S5 device/simulator residual evidence, not an S4 host blocker.
- 2026-06-13T06:35:30Z - Hygiene and graph maintenance passed: `git diff --check` exited cleanly, and `./graphify-arch/refresh_arch_graph.sh` rebuilt the architecture graph and regenerated `GRAPH_SELECTION.md` plus `comparison.json`. Log: `/tmp/doc114_s4_graph_refresh.log`.

## Execution Verdict

Verdict: accepted.

S4 is accepted for host integration and version-skew coverage. The new loopback suite proves committed ack after durable staging, restart replay deletion, quarantine disposition, old committed-ack compatibility, legacy ack classification, rejecting nack behavior, old matcher nack timeout behavior, and media envelope metadata preservation using real WebSocket frames and a real staging DB.

Accepted residual for S5: device-only/mDNS/mixed-version and `wifi_relay_fallback_smoke_test.dart` simulator proof remain closure-profile work because the available reliability-sim wrapper resolved devices but found no runnable command for the requested `--only` selector.
