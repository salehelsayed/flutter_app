Status: accepted

# Doc 114 Session S3 Plan - Durable LAN Sender Ack Policy

## Planning Progress

- 2026-06-13T06:25:20Z - Arbiter completed. Files inspected since last update: reviewer-pass S3 plan, reviewer findings, accepted-difference section, and closure/gate contract. Decision/blocker: no structural blocker remains; the race-scoring note is an accepted difference, not an implementation blocker. Next action: S3 may proceed to execution under this plan only.
- 2026-06-13T06:23:45Z - Reviewer completed; Arbiter started. Files inspected since last update: S3 draft plan, `send_chat_message_use_case.dart` race-ranking section, mandatory section coverage, simulator gate coverage, and controller checklist mapping. Decision/blocker: plan is sufficient with one incremental clarification: S3 should not redesign race ranking if a non-durable local leg and acknowledged direct leg both finish; document that as an accepted difference unless implementation tests expose a concrete regression. Next action: arbiter classification and final execution-ready update.
- 2026-06-13T06:18:30Z - Planner completed; Reviewer started. Files inspected since last update: draft S3 plan content, S3 source evidence, direct sender tests, gate definitions, and current prerequisite evidence. Decision/blocker: draft contains all mandatory plan sections, S3 checklist mapping, focused tests, implementation steps, graph refresh rule, and scope guard. Next action: review sufficiency for missing simulator gate, stale assumptions, and scope drift.
- 2026-06-13T06:12:40Z - Planner started. Files inspected since last update: `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, S3 sender test anchors in `send_chat_message_use_case_test.dart`, current dirty status for S3-relevant files. Decision/blocker: S3 can be planned as implementation-ready, with host implementation closure plus explicit simulator/device evidence residual for final doc closure. Next action: draft plan.
- 2026-06-13T06:09:15Z - Evidence Collector completed. Files inspected since last update: doc 114 source and breakdown, S1/S2 plans, doc 115/116 breakdowns, `lan_ack.dart`, `local_ws_server.dart`, `local_p2p_service.dart`, `p2p_service.dart`, `p2p_service_impl.dart`, `send_chat_message_use_case.dart`, `send_chat_message_use_case_test.dart`, S3-relevant fakes, 115/116 current code/test symbols. Decision/blocker: S1/S2 are accepted/closed in the breakdown and current receiver code/tests; 115 P1 `inboxed` and 116 P1-P2 retry-fidelity prerequisites are present in repo evidence; no blocker. Next action: plan S3 only.

## Execution Progress

- 2026-06-13T06:30:23Z - Local fallback S3 execution accepted with simulator proof pending at the time. Phase: final execution verdict reconciliation. Last completed command/results: `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart --plain-name '3b. WIFI-INTERRUPTED-VOICE'` passed; `./scripts/run_test_gates.sh 1to1` passed with `+593`; `./scripts/run_test_gates.sh completeness-check` passed with `840/840`; targeted `dart analyze` exited 0 with two info-level style notes in `send_chat_message_use_case_test.dart`; scoped `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from repo root. A later final closure pass resolved the command `16` schema issue by updating the simulator harness to DB version 77 and truthful `inboxed` fallback statuses.
- 2026-06-13T15:07:40Z - Final batch re-audit resolved the S3 simulator residual: `./scripts/run_reliability_simulations.sh 1to1 --only 16` passed S1-S4 at 4/4. S3 remains accepted; physical-device proof is archived at doc level, not an S3 implementation item.
- 2026-06-13T06:23:25Z - Simulator/device smoke attempted with the plan's original filter. Phase: evidence residual classification. Command/result: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_relay_fallback_smoke_test.dart` resolved device IDs but no reliability simulation command matched the requested filter; the list pass subsequently identified the intended smoke as command `16`. Decision/blocker: reran the discovered command to avoid treating the stale filter as sufficient device evidence.
- 2026-06-13T06:23:05Z - Architecture graph refreshed after S3 code/test edits. Phase: graph maintenance. Command/result: `./graphify-arch/refresh_arch_graph.sh` passed from repo root, reapplied already-present graphify patches, rebuilt `graphify-arch/graphify-out/graph.json`, reclustered, regenerated aggregated `graph.html`, and refreshed `GRAPH_SELECTION.md` plus `comparison.json`. No `uv tool upgrade graphifyy` occurred.
- 2026-06-13T06:22:42Z - Targeted analyzer and diff hygiene passed. Phase: final host validation. Command/result: `dart analyze lib/core/services/p2p_service.dart lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/send_chat_message_use_case.dart test/core/local_discovery/fake_local_p2p_service.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/core/services/fake_p2p_service.dart test/shared/fakes/fake_p2p_service_integration.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_inbound_transport_test.dart` exited 0 with only `unnecessary_import` and `use_super_parameters` info-level notes in `send_chat_message_use_case_test.dart`; scoped `git diff --check` exited 0.
- 2026-06-13T06:22:18Z - Completeness gate passed. Phase: required gate verification. Command/result: `./scripts/run_test_gates.sh completeness-check` passed with `840/840 test files classified`.
- 2026-06-13T06:22:07Z - Full 1to1 named gate passed after focused expectation fix. Phase: required gate verification. Last completed command/result: `./scripts/run_test_gates.sh 1to1` passed with `+593`; log: `/tmp/doc114_s3_1to1_rerun.log`. Files touched since last entry: no additional files. Decision/blocker: no S3-owned 1to1 gate blocker remains. Next action: run `./scripts/run_test_gates.sh completeness-check`, simulator smoke availability/proof, and repo-root `./graphify-arch/refresh_arch_graph.sh`.
- 2026-06-13T06:21:16Z - Focused 1to1 integration slice passed after the S3 expectation update. Phase: local fallback gate verification. Last completed command/result: `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart --name "WIFI-INTERRUPTED-VOICE"` passed. Evidence: flow log emitted `CHAT_MSG_SEND_LAN_ACK` with `kind:"bool_legacy"`, unacked inbox handoff succeeded, and sender persisted `status:"inboxed"`/`via:"inbox"` before Bob received the message. Decision/blocker: no focused integration blocker remains. Next action: rerun full `./scripts/run_test_gates.sh 1to1`.
- 2026-06-13T06:20:45Z - S3-owned 1to1 gate expectation patched. Phase: local fallback gate fix. Files touched: `test/features/conversation/integration/send_then_lock_delivery_test.dart` only. Decision/blocker: source confirmed the failing `WIFI-INTERRUPTED-VOICE` row uses a bool-only/non-durable local sender and the S3 sender backstop may now persist `inboxed`; this is a stale test expectation, not a product-code blocker. Next action: run focused `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart --name "WIFI-INTERRUPTED-VOICE"` and then rerun `./scripts/run_test_gates.sh 1to1`.
- 2026-06-13T06:19:55Z - Parent controller local execution fallback heartbeat before further gate triage. Phase: S3 local fallback gate triage. Last completed command/results: focused S3 sender/P2P/local-discovery tests passed after the Dart promotion fix; retry-focused command still has the pre-existing doc-115 P3 failures recorded below; `./scripts/run_test_gates.sh 1to1` failed with one S3-owned integration expectation in `test/features/conversation/integration/send_then_lock_delivery_test.dart` where the gate expected `delivered` or `sent` but current S3 non-durable LAN backstop produced truthful `inboxed`. Current command/log being inspected: `/tmp/doc114_s3_1to1.log` and the `WIFI-INTERRUPTED-VOICE` assertion in `send_then_lock_delivery_test.dart`. Decision/blocker: pending_triage; likely update only the stale S3-owned gate expectation if source confirms the test uses non-durable/bool local LAN success. Next action: inspect the failing assertion, patch only the S3-caused expectation, rerun the focused slice, then rerun the 1to1 gate.
- 2026-06-13T06:48:30Z - Retry-focused command completed with pre-existing doc-115 P3 failures, not patched under S3. Phase: focused test triage. Last completed command/results: local-discovery slice passed on sequential rerun; retry command `flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/retry_unacked_messages_use_case_test.dart test/core/services/pending_message_retrier_test.dart` failed only in pre-existing modified `retry_unacked_messages_use_case_test.dart` tests under `115 P3 - retry-unacked truthfulness`: (1) expected `storeInInboxCallCount == 1` for a `sent` row with `transport == inbox`, actual `0`; (2) expected successful re-store status `inboxed`, actual `delivered`. Files inspected: `retry_unacked_messages_use_case.dart` and failing test lines. Decision/blocker: do not implement doc 115 P3 under doc 114 S3; classify as pre-existing prerequisite/future-doc failure because S3 did not touch `retry_unacked_messages_use_case.dart` or its tests and doc 114 S3 is barred from starting docs 115/116. Next action: run required named gates and record exact failures if they reproduce this pre-existing slice.
- 2026-06-13T06:45:30Z - Focused S3 test batch partially completed. Phase: focused test execution/triage. Last completed command/results: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` passed; `flutter test test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_inbound_transport_test.dart` passed; parallel `flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/local_discovery/local_ws_server_test.dart` failed before tests with native asset `install_name_tool` rename failure while another Flutter command held startup/native-assets work. Classification: environment/tooling-related pending sequential rerun, not yet a S3 behavioral failure. Next action: rerun the local-discovery slice sequentially, then run retry-focused S3 command.
- 2026-06-13T06:42:30Z - Local fallback structural validation passed. Phase: focused test execution starting. Last completed command/result: targeted `dart analyze` on S3 production/test files exited 0 with only non-blocking style infos (`unnecessary_import`, `use_super_parameters`); targeted `git diff --check` passed. Files touched since prior entry: `send_chat_message_use_case.dart` cast fix only. Decision/blocker: no structural compile blocker remains. Next action: run focused S3 Flutter test commands from the plan.
- 2026-06-13T06:39:10Z - Local execution fallback structural check started after stopping the stalled execution child. Phase: local fallback validation/fix. Last completed command/result: targeted `dart analyze` on S3 production/test files failed with one S3 compile error in `send_chat_message_use_case.dart` (`sendLocalMessageDurable` not promoted on `P2PService`) plus pre-existing style infos. Files touched: `lib/features/conversation/application/send_chat_message_use_case.dart` only. Decision/blocker: S3 compile issue is in-scope and narrowly repairable; fixed by binding the optional `DurableLanSender` interface before the call. Next action: rerun targeted analyzer and then focused S3 tests.
- 2026-06-13T06:36:00Z - Parent controller bounded-wait inspection found the spawned S3 execution controller stalled after real Executor progress but before a trustworthy execution verdict. Phase: execution child recovery. Files inspected: S3 plan progress, scoped S3 owner-file diff stat/name list, process list for `codex`, `flutter`, `dart`, graph refresh, and gate commands. Evidence found: Executor child `019ebf97-9c1f-72e1-b65d-33494bc58303` recorded a baseline and modified scoped S3 owner files, but no required test/gate result, graph refresh result, QA result, or `## Execution Verdict` was persisted. Decision/blocker: classify the spawned execution attempt as no-final-result after partial code/test progress; use the pipeline's single bounded local execution fallback instead of spawning another broad execution child. Next action: terminate the stalled spawned execution controller, inspect the scoped S3 diff, run required tests/gates locally, repair only S3 issues if needed, then write a final S3 execution verdict.
- 2026-06-13T06:08:14Z - Fresh S3 Executor baseline recorded before code edits. Phase: owner-file inspection/setup. Files inspected by this Executor so far: S3 plan, graphify skill, host/simulator gate skills, graphify-arch query output, and S3 owner dirty status. Files touched: S3 plan progress only. Current dirty status for S3 owner files: pre-existing modified `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_ws_server.dart`, `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/local_discovery/local_ws_server_test.dart`, `test/core/services/fake_p2p_service.dart`, `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/shared/fakes/fake_p2p_service_integration.dart`, and untracked `lib/core/local_discovery/lan_ack.dart`; `test/core/services/pending_message_retrier_test.dart` currently has no S3-owner status entry. Decision/blocker: no scope blocker; preserve pre-existing owner-file edits while applying only S3 behavior. Next action: inspect sender/local service/fake/test anchors, then add S3 focused tests and implementation.
- 2026-06-13T06:07:29Z - Spawned fresh S3 Executor child. Phase: Executor spawned/running. Files inspected/touched by controller: S3 plan progress only. Command currently running: child agent `019ebf97-9c1f-72e1-b65d-33494bc58303` with `model:gpt-5.5` and `reasoning_effort:xhigh`. Decision/blocker: spawned-agent isolation contract satisfied so far. Next action: bounded wait for Executor completion, then inspect assigned S3 files/evidence before QA.
- 2026-06-13T06:06:42Z - Fresh S3 execution controller extracted the contract before spawning any child agent. Phase: contract extraction. Files inspected: `implementation-execution-qa-orchestrator/SKILL.md`, S3 plan, S3 breakdown entry, source doc Phase 3 anchors, and `git status --short`. Current dirty status before this controller's Executor/code edits: broad pre-existing dirty worktree, including S3 owner files and many unrelated files; preserve unrelated changes. Required scope: `DurableLanSender`, detailed LAN send ack path, committed-only local delivery/sticky training, legacy/bool backstop, Go reuse truthful transport, focused tests/fakes only. Required evidence: focused S3 Flutter tests, targeted `dart analyze`, targeted `git diff --check`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh completeness-check`, simulator smoke if available or S4/S5 residual, and repo-root `./graphify-arch/refresh_arch_graph.sh` after code changes. Decision/blocker: contract is execution-safe; no scope blocker. Next action: spawn fresh Executor with `model:gpt-5.5` and `reasoning_effort:xhigh`.
- 2026-06-13T06:28:10Z - Controller pre-execution snapshot recorded before any S3 Executor/code edit. Phase: contract extraction and dirty-worktree baseline. Files inspected: S3 plan, S3 breakdown entry, `git status --short` for S3 owner files. Dirty state: broad pre-existing modified/untracked worktree remains; S3 owner files already dirty/untracked include `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/core/local_discovery/fake_local_p2p_service.dart`, `test/core/local_discovery/local_p2p_service_test.dart`, `test/core/services/fake_p2p_service.dart`, `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_inbound_transport_test.dart`, `test/core/services/p2p_service_transport_census_test.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, `test/shared/fakes/fake_p2p_service_integration.dart`, untracked `lib/core/local_discovery/lan_ack.dart`, and untracked doc 114 artifacts. Decision/blocker: no execution blocker; preserve unrelated dirty changes and keep S3 scope only. Next action: spawn fresh S3 execution agent with `model:gpt-5.5` and `reasoning_effort:xhigh`.

## Execution Verdict

Verdict: accepted.

Blocker class: none for S3 host implementation. The earlier simulator-schema residual is closed by the final command-16 pass; physical-device proof is archived at doc level.

Spawned-agent isolation used: attempted. Fresh S3 execution controller and Executor were spawned, but the child stalled after partial scoped code/test progress and did not persist a trustworthy verdict. The controller used the single bounded current-session local fallback to finish validation, apply the narrow integration expectation fix, and persist this verdict. No second broad execution child was spawned.

Files changed for S3:

- `lib/core/services/p2p_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `graphify-arch/graphify-out/*`, `graphify-arch/GRAPH_SELECTION.md`, and `graphify-arch/comparison.json` refreshed by `./graphify-arch/refresh_arch_graph.sh`

Evidence captured:

- `DurableLanSender` is an opt-in capability, `LocalP2PService.sendMessageDetailed` returns `LanSendAck`, and `P2PServiceImpl.sendLocalMessageDurable` delegates detailed LAN acks while preserving the side-effect gate.
- Sender policy maps only committed LAN acks to acknowledged local delivery; legacy/bool local acks use the existing inbox handoff or retryable sent-with-envelope path and do not train sticky `local`.
- Go-channel reuse now resolves from the actual Go transport rather than preserving `local` solely because the peer is LAN-visible.
- Focused sender/P2P/local-discovery/core tests passed after S3 fixes.
- Retry-focused trio failed only in pre-existing doc 115 P3 retry-unacked tests in `retry_unacked_messages_use_case_test.dart`; S3 did not touch those files and the full `1to1` gate passed afterward.
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart --plain-name '3b. WIFI-INTERRUPTED-VOICE'` passed after updating the stale expectation for non-durable/bool local acks to allow truthful `inboxed`.
- `./scripts/run_test_gates.sh 1to1` passed with `+593`.
- `./scripts/run_test_gates.sh completeness-check` passed with `840/840`.
- Targeted `dart analyze` exited 0 with only info-level style notes; scoped `git diff --check` passed.
- `./graphify-arch/refresh_arch_graph.sh` passed from repo root after final S3 edits. No `uv tool upgrade graphifyy` occurred.

Residuals deferred to S4/S5:

- The simulator wrapper's plan filter no-matched, but the list pass resolved the intended WiFi relay fallback smoke as command `16`; executing command `16` failed after three attempts before S3 LAN behavior with `SqfliteDatabaseException: table contacts has no column named ml_kem_key_updated_ts` in `integration_test/wifi_relay_fallback_smoke_test.dart` setup. Real loopback/device/mixed-version proof remains S4/S5 scope.
- The pre-existing doc 115 P3 retry-unacked focused failures remain outside S3 and must not be fixed under doc 114 S3.

Why S3 is safe to consider complete: the sender now treats committed LAN acks as the only durable local success, preserves custody/retry truth for legacy and bool local acks, keeps sticky local truthful, fixes the Go reuse transport label, and records host evidence plus explicit residuals without reopening receiver staging, docs 115/116, S4/S5, or final closure work.

## Planning Final verdict

S3 is execution-ready. No structural blockers remain.

## Final plan

This plan is scoped only to doc 114 S3. It does not execute code changes and does not plan, start, execute, or close S4/S5 or docs 115/116.

## structural blockers remaining

None.

## incremental details intentionally deferred

- Exact helper names inside S3 tests may vary, but tests must independently prove committed, legacy, bool-only, sticky, and reuse-label behavior.
- S4/S5 may later add or adjust real loopback/device evidence if S3 changes the sender API shape.

## accepted differences intentionally left unchanged

- The architecture graph is stale for newly added `LanSendAck`/`DurableLanSender` symbols; exact-symbol graph queries were used only for orientation, then current source/test files became authoritative.
- S3 host implementation closure is not final doc 114 closure. Real loopback, version-skew, device, notification, and final gate/doc closure remain S4/S5.

## exact docs/files used as evidence

- `Test-Flight-Improv/114-lan-ack-after-commit.md`
- `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md`
- `Test-Flight-Improv/114-lan-ack-after-commit-session-S1-plan.md`
- `Test-Flight-Improv/114-lan-ack-after-commit-session-S2-plan.md`
- `Test-Flight-Improv/115-relay-inbox-custody.md`
- `Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`
- `Test-Flight-Improv/116-edit-retry-fidelity.md`
- `Test-Flight-Improv/116-edit-retry-fidelity-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`
- `lib/core/local_discovery/lan_ack.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/local_discovery/local_ws_server_test.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart`
- `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart`

## why the plan is safe or unsafe to implement now

Safe to implement now because the S3 dependency surface is present, every controller requirement has a planned proof or accepted-difference entry, and the plan only changes sender-side ack classification, sticky training, and local-send detail propagation. It deliberately excludes receiver staging/replay work already closed by S2.

## real scope

S3 owns sender durable LAN ack policy and sticky transport truthfulness only:

- Add an opt-in `DurableLanSender` capability in the P2P sender seam.
- Add a detailed local send path from `P2PServiceImpl` through `LocalP2PService` to `LocalWsServer.sendMessageWithAck`.
- Map only `LanSendAck.committed` to acknowledged local success in `send_chat_message_use_case.dart`.
- Treat `LanSendAck.legacyAck`, bool-only `sendLocalMessage == true`, and non-capability local senders as non-durable: they must enter the existing unacked handoff and terminate as `inboxed` on relay custody or as truthful `sent` with `wireEnvelope`.
- Prevent legacy/bool LAN acks from training sticky `local`.
- Fix the Go-channel reuse mislabel in the sender seam by recording the actual Go transport rather than forcing `local` when a peer is LAN-visible.
- Update focused S3 sender tests and required fakes.

S3 must not:

- Change receiver staging/replay, `_commitInboundLanChatMessage`, `_replayDurablyStagedLanChat`, `inbox_staging` disposition behavior, or live LAN replay notification behavior already closed by S2.
- Add S4 loopback integration tests or version-skew fixture tests.
- Update S5 gate arrays, final closure logs, or stable closure references.
- Edit docs 115/116 or decompose/execute their sessions.
- Touch Go, relay, native, notification, or LAN media code.

## closure bar

S3 implementation closure requires host proof for every sender-seam requirement:

| Requirement | Planned proof |
|---|---|
| S1/S2 dependency is landed enough for sender work | Source and test evidence show `LanSendAck`, `LanInboundDecision`, `sendMessageWithAck`, `LocalP2PService.configureInboundChatCommitHandler`, `P2PServiceImpl._commitInboundLanChatMessage`, and S2 receiver tests/ledger exist. |
| 115 P1 `inboxed` foundation is present | Current code/tests show `persistInboxAccepted`, status `inboxed`, custody columns (`relayExpiresAt`, `custodyCheckedAt`), migration `077_message_relay_custody.dart`, `inboxed` send/delete tests, and receipt-driven `inboxed -> delivered` tests. |
| 116 P1-P2 retry-fidelity floor is present | Current code/tests show `deriveRetryAction`, row-derived edit retry, `edit_retry_round_trip_test.dart`, `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED`, `_retryInFlightMessageIds`, and single-flight tests. |
| Only committed LAN ack mints local delivered | New/updated `send_chat_message_use_case_test.dart` case with a durable local fake returning `LanSendAck.committed` expects `status == delivered`, `transport == local`, no inbox handoff, and sticky local recorded. |
| Legacy LAN ack is non-durable | New test with durable fake returning `LanSendAck.legacyAck` expects inbox handoff and `status == inboxed` / `transport == inbox` when relay custody succeeds. |
| Legacy LAN ack without relay custody remains retryable | New test with legacy ack and failed inbox handoff expects `status == sent`, `transport == local`, and non-null `wireEnvelope`. |
| Bool-only/non-capability local success is fail-safe | New test using a `P2PService` fake without `DurableLanSender` expects bool `sendLocalMessage == true` to behave as legacy/non-durable, not delivered/local. |
| Sticky local is trained only by committed ack | New test proves legacy ack never calls `recordSuccessfulTransport('local')`; committed ack does. |
| Sticky local short-circuit still uses backstop on non-durable ack | New test with `lastKnownGoodTransport == local` and legacy ack expects `inboxed`/`inbox`, not delivered/local. |
| Go-channel reuse label is truthful | New/updated reuse test with LAN-visible peer and Go `sendMessageWithReply.transport == direct` expects `message.transport == direct` and `recordSuccessfulTransport('direct')`, not local. |
| Old local happy-path tests are intentionally updated | Existing tests that asserted parse-time/bool LAN delivered behavior are updated to use committed-ack capability when they intentionally assert delivered/local; fallback and skip-local tests remain unchanged. |

Because S3 touches 1:1 transport behavior, host tests are not final user-visible/mobile closure. If devices are available, executors should run the narrow 1:1 simulator smoke listed in `exact tests and gates to run`; if unavailable or not specific enough for committed LAN ack, record it as residual evidence for S4/S5 and do not claim final doc 114 closure.

## source of truth

- Current source and tests beat stale prose.
- `Test-Flight-Improv/114-lan-ack-after-commit-session-breakdown.md` is the session ledger. It records S1 and S2 as accepted/closed and S3 as pending.
- `Test-Flight-Improv/114-lan-ack-after-commit.md` Phase 3 is the behavior contract for S3 unless current code/test evidence proves a narrower safe implementation.
- `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, and `scripts/run_host_test_gates.sh` are authoritative for named gates.
- Repo evidence verifies doc 115 P1 and doc 116 P1-P2 prerequisites; docs 115/116 are evidence only and must not be edited by S3.
- Worktree is dirty and includes many unrelated modified/untracked files. S3 implementers must preserve all non-S3 changes. Relevant dirty S3 files before planning include modified `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_ws_server.dart`, `lib/core/services/p2p_service.dart`, `lib/core/services/p2p_service_impl.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `test/features/conversation/application/send_chat_message_use_case_test.dart`, and untracked `lib/core/local_discovery/lan_ack.dart` plus doc 114/115/116 artifacts.
- Graph context source: exact-symbol `graphify-arch` queries only. Do not run `graphify update` or extraction from inside `graphify-arch`. After S3 code changes, executors must run `./graphify-arch/refresh_arch_graph.sh` from repo root. If `uv tool upgrade graphifyy` occurs, remove `graphify-out/cache/ast` before rebuild.

## session classification

`implementation-ready`

S3 is ready for implementation against current repo evidence. It is evidence-gated only for final doc 114 mobile/device closure, which remains S4/S5 scope.

## exact problem statement

Today the sender still treats a successful local bool send as acknowledged durable delivery. In `send_chat_message_use_case.dart`, `_tryLocalSend` calls `P2PService.sendLocalMessage`; when the bool is true, it returns `_RaceResult.succeeded(via: 'local', acknowledged: true)`. `_persistOutgoingSendResult` then writes `delivered/local` and drops the wire envelope. That is still unsafe for legacy parse-time LAN acks and for any fake/wiring that lacks detailed `LanSendAck` semantics.

The current code also still forces connection-reuse wins to `local` when the peer is LAN-visible by calling `_resolveGoSendTransport(..., preserveLocalPeerLabel: true)`. That can train the sticky sender toward local even when the actual Go channel was direct or relay.

S3 must make sender status truthful: only committed LAN acks count as local delivery; legacy/bool acks must use the durable handoff/retry path; sticky local must only be learned after committed LAN custody; and Go reuse must record actual transport.

## files and repos to inspect next

Production files:

- `lib/core/services/p2p_service.dart`
- `lib/core/local_discovery/local_p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/core/local_discovery/lan_ack.dart`
- `lib/core/local_discovery/local_ws_server.dart` only for signature/ack-type reference, not receiver changes.

Tests and fakes:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/core/local_discovery/fake_local_p2p_service.dart`
- `test/core/local_discovery/local_p2p_service_test.dart`
- `test/core/local_discovery/local_ws_server_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_transport_census_test.dart`
- `test/core/services/p2p_service_inbound_transport_test.dart`
- `test/core/services/fake_p2p_service.dart`
- `test/shared/fakes/fake_p2p_service_integration.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `test/core/services/pending_message_retrier_test.dart`

Gate/config files:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`

Do not inspect/plan unrelated docs 115/116 beyond prerequisite evidence already named here unless S3 implementation hits a compile dependency that directly references their current code.

## existing tests covering this area

- `test/core/local_discovery/local_ws_server_test.dart` covers S1 ack classification, including committed, legacy, and nack frames.
- `test/core/local_discovery/local_p2p_service_test.dart` covers the local P2P facade and S2 commit handler passthrough. It does not yet cover a S3 `sendMessageDetailed` passthrough.
- `test/core/services/p2p_service_impl_test.dart` covers S2 receiver-side LAN staging/replay and direct service local-send behavior. It does not yet prove `P2PServiceImpl implements DurableLanSender`.
- `test/features/conversation/application/send_chat_message_use_case_test.dart` already covers local send, fallback, sticky learned transport, connection reuse, inbox handoff, 115 `inboxed`, and 116 downgrade/single-flight behavior. Some existing tests intentionally pin the old parse-time/bool-local delivered semantics and must be rewritten under S3.
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`, `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`, and `test/core/services/pending_message_retrier_test.dart` cover retry visibility and must stay green after legacy/bool LAN acks persist `sent` plus `wireEnvelope` or `inboxed`.
- 115 prerequisite tests currently cover `inboxed` custody and receipt-origin discrimination, including `direct:` and `lan:` staged entry skips.
- 116 prerequisite tests currently cover edit retry action fidelity, no-downgrade writer gate, and retry single-flight.

## regression/tests to add first

Add or rewrite tests before production changes:

1. In `test/features/conversation/application/send_chat_message_use_case_test.dart`, add a durable local fake path. Prefer `class DurableLanFakeP2PService extends FakeP2PService implements DurableLanSender` with a `LanSendAck localSendAck` knob so the base fake can remain a bool-only/non-capability sender for fail-safe tests.
2. Add `LAN committed ack persists delivered with transport local`: durable fake returns `LanSendAck.committed`; expect success, `delivered/local`, `storeInInboxCallCount == 0`, and sticky local recorded.
3. Add `LAN legacy ack is non-durable: inbox handoff takes custody and status is inboxed`: durable fake returns `LanSendAck.legacyAck`, `storeInInboxResult == true`; expect `inboxed/inbox`, envelope retained, one inbox call, and no sticky local record.
4. Add `LAN legacy ack with failed inbox handoff keeps truthful sent with wireEnvelope`: durable fake returns `legacyAck`, `storeInInboxResult == false`; expect `sent`, `transport == local`, non-null `wireEnvelope`, and no sticky local record.
5. Add `P2PService without DurableLanSender capability treats a bool LAN ack as non-durable`: base fake has local bool success and inbox success; expect `inboxed/inbox`, not delivered/local.
6. Add `legacy LAN ack never trains sticky learned transport; committed ack does`: assert `recordSuccessfulTransport` only records `local` for committed.
7. Add `sticky local short-circuit honors a non-durable legacy ack with the inbox backstop`: seed `lastKnownGoodTransportResult = 'local'`, return legacy ack, and expect `inboxed/inbox`.
8. Add or adjust `connection-reuse win over the Go channel records the actual transport, not local`: connected and LAN-visible peer, Go result transport `direct`; expect `direct` and sticky `direct`.
9. Rewrite old local happy-path tests such as `sends locally when peer is on local WiFi`, `passes interactive local budget to the WiFi transport`, NET-REL U1 local grace, U2 sticky local, and any local-wire-envelope pins so delivered/local assertions use the durable committed fake. Keep local failure, non-local skip, and direct fallback assertions unchanged unless they compile-break.
10. In `test/core/local_discovery/local_p2p_service_test.dart`, add a passthrough test for `sendMessageDetailed` returning the underlying `LanSendAck`.
11. In `test/core/services/p2p_service_impl_test.dart`, add a narrow test that `sendLocalMessageDurable` returns committed/legacy/failed from `LocalP2PService.sendMessageDetailed`, while `sendLocalMessage` returns true only for committed.

## step-by-step implementation plan

1. Add red tests first as listed above. Stop and refresh this plan if a test requires receiver staging/replay changes, DB schema changes, docs 115/116 edits, or S4 loopback fixtures.
2. In `lib/core/services/p2p_service.dart`, import `lan_ack.dart` and add an opt-in `abstract interface class DurableLanSender` beside `ReadinessProofRecorder`/`P2PFullInboxDrain`:

```dart
abstract interface class DurableLanSender {
  Future<LanSendAck> sendLocalMessageDurable(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  });
}
```

Do not add this method to `P2PService`; keep existing fakes compile-safe unless they opt into the capability.

3. In `lib/core/local_discovery/local_p2p_service.dart`, add `sendMessageDetailed(...)` that resolves the local peer and delegates to `_wsServer.sendMessageWithAck(...)`, returning `LanSendAck.failed` when the peer is absent. Keep `sendMessage(...)` as a bool wrapper that returns true only when detailed ack is `LanSendAck.committed`.
4. Update `test/core/local_discovery/fake_local_p2p_service.dart` with a `LanSendAck sendAck` or callback knob and a `sendMessageDetailed(...)` override. Keep `sendMessage(...)` true only for committed if the fake implements the concrete `LocalP2PService` method.
5. In `lib/core/services/p2p_service_impl.dart`, implement `DurableLanSender`. Add `sendLocalMessageDurable(...)` near `sendLocalMessage`, preserving the existing account-network-side-effects gate. It should return `LanSendAck.failed` if the gate blocks or `_localP2P` is null, otherwise delegate to `_localP2P.sendMessageDetailed(...)`. Change `sendLocalMessage(...)` to return `await sendLocalMessageDurable(...) == LanSendAck.committed`.
6. In `lib/features/conversation/application/send_chat_message_use_case.dart`, import `lan_ack.dart` if needed and update `_tryLocalSend`:
   - If `p2pService is DurableLanSender`, call `sendLocalMessageDurable`.
   - Map `LanSendAck.committed` to `_RaceResult.succeeded(via: 'local', acknowledged: true)`.
   - Map `LanSendAck.legacyAck` to `_RaceResult.succeeded(via: 'local', acknowledged: false)`.
   - Map `LanSendAck.failed` to `_RaceResult.failed('local_send_failed')`.
   - If the service lacks the capability, call the existing bool `sendLocalMessage`; map `true` to legacy/non-durable success (`acknowledged:false`) and `false` to failed.
   - Emit a compact `CHAT_MSG_SEND_LAN_ACK` flow event with `kind: committed|legacy|failed|bool_legacy|bool_failed` and no message body.
7. In `send_chat_message_use_case.dart`, remove the Go reuse mislabel by changing the reuse call at the current `preserveLocalPeerLabel: true` site to use the actual Go result. Prefer removing the parameter entirely if no other caller needs it; otherwise stop passing true. The reuse path must record `direct` or `relay` when `SendMessageResult.transport` says so.
8. Leave `_persistOutgoingSendResult` mostly unchanged. Its existing unacked path already writes `inboxed` on successful handoff and `sent` plus `wireEnvelope` on failed handoff; S3 should feed the correct `acknowledged` value into it rather than fork the persistence policy.
9. Update S3 tests and any compile-facing fakes. Do not mass-update all P2P fakes. Only opt in fakes that need detailed LAN behavior; bool-only fakes should remain valuable negative controls.
10. Run focused tests after each behavior batch, then the exact gates below.
11. After S3 code changes and tests, run `./graphify-arch/refresh_arch_graph.sh` from repo root. Do not run `graphify update` or extraction inside `graphify-arch`. If `uv tool upgrade graphifyy` occurs during the rebuild, remove `graphify-out/cache/ast` before rebuilding.

## risks and edge cases

- Bool-only fakes can accidentally become durable if the base test fake implements `DurableLanSender`; keep an explicit non-capability negative control.
- Legacy LAN ack still means the receiver may have processed a RAM-only copy. The sender must backstop with relay custody or preserve a retryable `sent` envelope, accepting duplicate delivery as receiver-idempotent.
- Sticky local short-circuit is the highest-risk path because it bypasses the parallel direct leg. Its legacy/non-durable behavior must run the same handoff path as cold local legacy acks.
- Connection reuse may be both connected and LAN-visible. The Go result must win for transport truthfulness; LAN visibility alone must not rewrite it to `local`.
- Existing local happy-path tests may currently assert old semantics. Rewrites must distinguish deliberate committed-ack delivered tests from legacy/bool fail-safe tests.
- Account migration gating remains receiver-side for S2 and local-send side-effect gate remains in `P2PServiceImpl`; S3 must not weaken either.
- Broad dirty worktree increases attribution risk. Executors must use `git diff -- <S3 files>` and avoid reverting unrelated changes.

## exact tests and gates to run

Focused red/green S3 suites:

```bash
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/core/local_discovery/local_p2p_service_test.dart test/core/local_discovery/local_ws_server_test.dart
flutter test test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_inbound_transport_test.dart
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/retry_unacked_messages_use_case_test.dart test/core/services/pending_message_retrier_test.dart
```

Analysis and diff hygiene:

```bash
dart analyze lib/core/services/p2p_service.dart lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/send_chat_message_use_case.dart test/core/local_discovery/fake_local_p2p_service.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/core/services/fake_p2p_service.dart test/shared/fakes/fake_p2p_service_integration.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_inbound_transport_test.dart
git diff --check -- lib/core/services/p2p_service.dart lib/core/local_discovery/local_p2p_service.dart lib/core/services/p2p_service_impl.dart lib/features/conversation/application/send_chat_message_use_case.dart test/core/local_discovery/fake_local_p2p_service.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/core/local_discovery/local_p2p_service_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_transport_census_test.dart test/core/services/p2p_service_inbound_transport_test.dart
```

Named host gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh completeness-check
```

Simulator/device smoke because S3 touches 1:1 transport behavior:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only integration_test/wifi_relay_fallback_smoke_test.dart
```

If the simulator/device command cannot run in the executor environment, or if it does not specifically exercise committed LAN ack semantics, record that as a S4/S5 evidence residual. Do not mark final doc 114 closed from S3 host evidence alone.

Graph refresh after S3 code changes:

```bash
./graphify-arch/refresh_arch_graph.sh
```

If `uv tool upgrade graphifyy` occurs before that rebuild:

```bash
rm -rf graphify-out/cache/ast
./graphify-arch/refresh_arch_graph.sh
```

## known-failure interpretation

- Failures in tests outside the exact focused S3 suites and named gates should be treated as pre-existing unless they reproduce with only the S3 diff applied or directly involve the S3 files.
- Existing tests that assert old parse-time/bool LAN delivered semantics are expected to go red after the first S3 red-test pass; they must be rewritten into committed-ack delivered tests or legacy/bool non-durable tests, not papered over.
- Simulator/device unavailability is not an S3 implementation blocker, but it is a final doc 114 closure blocker/residual for S4/S5.
- `graphify-arch` missing new symbols is a stale-graph condition, not a code blocker. Refresh the graph only after code changes using the repo-root script.

## done criteria

S3 is done when all of the following are true:

- `DurableLanSender` exists as an opt-in capability and does not force every `P2PService` fake to implement a new method.
- `LocalP2PService.sendMessageDetailed` returns `LanSendAck` from `LocalWsServer.sendMessageWithAck`; its bool `sendMessage` wrapper returns true only for committed.
- `P2PServiceImpl` implements durable local sending and keeps existing side-effect gating.
- `send_chat_message_use_case.dart` maps committed LAN ack to acknowledged local success, legacy/bool local ack to unacked success/backstop, and failed ack to failed local leg.
- Legacy/bool local acks never persist `delivered/local`, never drop `wireEnvelope` without relay custody, and never train sticky `local`.
- Committed LAN ack still persists `delivered/local` and trains sticky `local`.
- Go connection reuse records the actual Go transport, not `local` just because the peer is LAN-visible.
- Existing intentional local delivered tests are updated to use committed ack; local failure and direct/relay fallback semantics stay unchanged.
- The focused tests, analysis command, `git diff --check`, `./scripts/run_test_gates.sh 1to1`, and `./scripts/run_test_gates.sh completeness-check` pass or have precise pre-existing failure notes.
- The simulator/device smoke is run if available; otherwise the residual is recorded for S4/S5.
- `./graphify-arch/refresh_arch_graph.sh` is run from repo root after code changes, with `graphify-out/cache/ast` removed first only if `uv tool upgrade graphifyy` occurred.
- No docs 115/116, S4/S5 plan files, receiver staging/replay code, Go/relay/native code, or final gate arrays are edited for S3.

## scope guard

S3 must stop and return to planning if implementation appears to require:

- Editing `_commitInboundLanChatMessage`, `_replayDurablyStagedLanChat`, `_applyRecoveredInboxOutcome`, staging DB helpers, or replay callback contracts.
- Adding `local_ws_durable_ack_integration_test.dart` or any S4 host loopback/version-skew fixture.
- Updating doc 114 closure logs, test-gate file lists, or `scripts/run_test_gates.sh` arrays for final classification.
- Editing docs 115/116 or their session breakdowns/plans.
- Changing relay, Go, gomobile bridge, native platform files, notification routing, or LAN media behavior.
- Replacing the existing unacked handoff policy instead of feeding it correct durable/non-durable ack truth.

## accepted differences / intentionally out of scope

- S3 accepts duplicate-delivery possibility for legacy LAN acks because the backstop copy is required for durability and receiver idempotency is the existing safety mechanism.
- S3 does not prove real-socket timing, old/new binary skew, post-ack receiver kill, decrypt quarantine, or media-bearing LAN replay. Those remain S4.
- S3 does not update final source-doc closure, stable closure references, or coordinated gate arrays. Those remain S5.
- S3 does not try to make legacy/bool LAN acks "failed"; it treats them as non-durable success so the existing handoff can preserve UX and retryability.
- S3 does not redesign transport race scoring. If a legacy/non-durable local leg and an acknowledged direct leg both finish within the current grace logic, S3's required invariant is that the selected terminal is truthful (`inboxed` or retryable `sent`, not `delivered/local`). Preferring acknowledged direct over non-durable local would be a separate race-policy change and must be re-planned if product requires it.

## dependency impact

- S4 depends on S3's final `DurableLanSender` and `sendMessageDetailed` API shape for real loopback/version-skew tests.
- S5 depends on S3's final test names and behavior for gate classification and doc closure.
- Doc 115 Phase 3 custody sweep and doc 116 Phase 3 work must not be reopened by S3; S3 consumes their current foundations only.
- If S3 changes the meaning of `sendLocalMessage` in a way that breaks broad fakes or local media assumptions, stop and re-plan. The intended change is local text ack truthfulness only.

## reviewer findings

Reviewer verdict: sufficient with an incremental adjustment already recorded.

- Missing files/tests/gates: none structural. The plan names production files, compile-facing fakes, focused sender/local/core tests, `1to1`, `completeness-check`, graph refresh, and a simulator smoke/residual rule.
- Stale assumptions: graphify-arch is stale for new LAN ack symbols, but the plan treats graph output as orientation and uses current source/tests as truth.
- Scope drift: no S4/S5 planning, no docs 115/116 edits, no receiver staging/replay changes, and no Go/relay/native work are included.
- Overengineering: the opt-in `DurableLanSender` capability is narrow and avoids forcing all `P2PService` fakes to grow a method.
- Minimum needed adjustment: explicitly document the accepted difference that S3 does not redesign transport race scoring for local legacy vs direct acked ties; that clarification is now in `accepted differences / intentionally out of scope`.
- Checklist coverage: every user-listed S3 requirement has a planned proof or accepted-difference entry.

## arbiter decision

Arbiter verdict: execution-ready.

- Structural blockers: none.
- Incremental details: helper names and exact fake shape can vary during implementation as long as the tests preserve committed, legacy, bool-only, sticky, and reuse-label proof.
- Accepted differences: S3 does not redesign race scoring, does not claim final mobile/device closure, does not edit docs 115/116, and does not reopen S2 receiver staging/replay.
- Stop rule result: no structural blocker remained after reviewer pass, so planning stops here.
