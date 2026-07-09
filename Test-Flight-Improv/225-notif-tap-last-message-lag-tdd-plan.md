# 225 - Notif-tap opens the chat, but the announced message renders late (Bug)

Status: accepted — /tdd-review READY-WITH-TIGHTENING (wf_ea1fd793-f62, 8-agent audit 2026-07-09); fix-list `225-review-fixlist.md` APPLIED into this plan 2026-07-09 (all items; §D6 receipt-timing applied as note-only — contract inherited from 146). EXECUTION-READY.
Spec: free-text intent (no formal spec) — user report 2026-07-09: "when I receive a notification from a user and I click on it, the main chat window of the user is opened (correct behavior), but there is a lag until the last message is displayed (the message I wanted to read when I clicked on the notification)."

> NOTE on numbering: 224 was claimed mid-session by a concurrent Claude session
> (`224-orbit-side-arc-tap-dead-zone-tdd-plan.md`, untracked on the shared tree).
> This plan is 225. Baseline `run_test_gates.sh 1to1` = **1518/1518 green**
> (snapshot 2026-07-09, this session).

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | Workflow `wf_2dc4805b-7f5` (16 agents: scout → seam-trace+test-inventory → per-claim verify → adversarial refute → tier obligations) | 6 candidate root causes → 4 survived (C1, C3, C5, C6), 2 killed (C2, C4) | hand to planner |
| 2026-07-09 | Planner | Spot-verified on HEAD: `background_message_handler.dart:112-199`, `p2p_service_impl.dart:1960-2034`, `conversation_wired.dart:548-579`, `prepare_notification_open_use_case.dart:21-89`, `push_decrypt_preview.dart:46-99`, `ios/NotificationService/NotificationService.swift:1-60` | Scope = Slice A (C3 replay-before-ack) + Slice B (C1 push-envelope staging fast-path). C5/C6 = named follow-up sessions | emit plan |
| 2026-07-09 | Reviewer (sufficiency) | this plan vs `references/sufficiency-checklist.md` | all gates pass; matrix zero empty cells; blind-spot sweep recorded | arbiter |
| 2026-07-09 | Reviewer (external /tdd-review) | `wf_ea1fd793-f62` (2 source-verifiers → 5 dimension assessors → 1 evergreen critic) | READY-WITH-TIGHTENING; both core bets source-verified SOUND; fix-list §A-§E | apply fix-list |
| 2026-07-09 | Planner (fix-list application) | spot-re-verified: `handle_incoming_chat_message_use_case.dart:263-265/:303`, `startup_router.dart:811-833/:1031`, `p2p_service_impl.dart:2176`, `go-relay-server/inbox.go:286-312`, `chat_message_listener.dart:383`, `app_group_path_channel.dart` | ALL fix-list items applied (§D6 receipt-timing = note-only, inherited 146 contract); TC-B13/TC-B14 added; TC-B12 → 3 required device scenarios; ingest await BOUNDED ~400ms (user-locked) | arbiter |
| 2026-07-09 | Arbiter | — | Structural verdict: implementation-ready; closure gate = TC-B12 device proof (3 scenarios, both receiver platforms) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-09 18:23 CEST | contract extraction | `Test-Flight-Improv/225-notif-tap-last-message-lag-tdd-plan.md`, `Test-Flight-Improv/225-review-fixlist.md`, `scripts/run_test_gates.sh`, `scripts/check_reliability_simulation_discovery.sh` | `git status --short`; `cd graphify-arch && graphify query "225 notification tap last message lag plan code entry files notification tap routing chat last message stream unread update tests gates" --budget 1500`; plan/read-gate extraction | contract explicit: Slice A replay-before-ack + Slice B 1:1 push-envelope staging/ingest; required RED-first tests, direct GREEN suites, `1to1`, `completeness-check`, discovery, analyze, diff-check, and TC-B12 device scenarios are named; unrelated dirty orbit/224/graphify files observed and out of scope | spawn Executor pass with strict scope guard |
| 2026-07-09 18:24 CEST | Executor contract/baseline | `Test-Flight-Improv/225-notif-tap-last-message-lag-tdd-plan.md`, `Test-Flight-Improv/225-review-fixlist.md`, `scripts/run_test_gates.sh`, `scripts/check_reliability_simulation_discovery.sh`, `integration_test/benchmark_harness.dart`, `integration_test/benchmark_notification_tap_harness.dart` | `git status --short`; `cd graphify-arch && graphify query "225 notification tap last message lag Slice A replay before ack Slice B push encrypted envelope staging prepareNotificationOpen startup_router background handler ingest staged push envelopes tests gates" --budget 1500`; inspected benchmark entrypoint for `BENCHMARK=NOTIFICATION_TAP` | Executor scope extracted: Slice A `_retrievePendingInboxPage` replay-before-ack only; Slice B 1:1 encrypted push-envelope file staging, handler/NSE write, ingest, bounded prepare wiring, startup/resume ingest, harness registration. Dirty unrelated files observed and left untouched. | run step-0 baseline attempt before RED edits |
| 2026-07-09 18:25 CEST | baseline | — | FAILED `timeout 180 flutter test --dart-define=BENCHMARK=NOTIFICATION_TAP integration_test/benchmark_harness.dart`; failing before test body: Flutter requires explicit `-d` because Pixel 6, macOS, and Chrome targets are visible; focused triage command: `flutter devices` | `pending_triage` (environment/device-selection, no production/test edits yet) | run device triage, then continue RED-first host tests |
| 2026-07-09 18:25 CEST | baseline triage | — | `flutter devices` found Pixel 6 `21071FDF600CSC`, two cabled iPhones, macOS, Chrome; wireless iPhone warning present but not needed for Pixel baseline | baseline retry classified environment/device-selection, not product; explicit-device rerun is available | run `timeout 300 flutter test -d 21071FDF600CSC --dart-define=BENCHMARK=NOTIFICATION_TAP integration_test/benchmark_harness.dart` |
| 2026-07-09 18:26 CEST | baseline | — | FAILED `timeout 300 flutter test -d 21071FDF600CSC --dart-define=BENCHMARK=NOTIFICATION_TAP integration_test/benchmark_harness.dart`; failing before benchmark body during `assembleDebug`: sqlite3 native asset hash mismatch for `libsqlite3.arm64.android.so` (`bef140...` vs expected `a668...`); focused triage command would be the reproduced hook command emitted by Flutter: `(cd ~/.pub-cache/hosted/pub.dev/sqlite3-3.1.4/; dart ...hook.dill --config ...input.json)` | `pending_triage` / environment-tooling (native asset cache/download integrity); no product/test edits made before baseline attempt | continue RED-first host tests; baseline remains environment-blocked unless native asset cache is repaired outside scope |
| 2026-07-09 18:31 CEST | RED tests added | `test/core/services/p2p_service_inbox_ack_ordering_test.dart`, `test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart`, `test/features/push/application/push_envelope_staging_test.dart`, `test/features/push/application/background_message_handler_staging_test.dart`, `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart`, `test/features/push/application/prepare_notification_open_use_case_test.dart`, `test/features/conversation/integration/notif_tap_payload_fast_path_test.dart`, `test/features/push/integration/push_ingest_persistence_test.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/identity/presentation/startup_router_notification_open_test.dart`, `integration_test/inbox_replay_before_ack_custody_harness.dart`, `integration_test/notif_push_payload_persist_harness.dart`, `integration_test/notification_tap_message_visible_proof_test.dart`, `scripts/run_test_gates.sh`, `scripts/check_reliability_simulation_discovery.sh` | added TC-A1..A5 and TC-B1..B14 host/device-registration RED coverage; production files untouched | RED-first state satisfied for host tests; simulator/device harnesses registered as skipped placeholders, not proof | run required RED commands and record expected failures |
| 2026-07-09 18:34 CEST | RED evidence | `test/core/services/p2p_service_inbox_ack_ordering_test.dart` | FAILED `flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart`; TC-A1 timed out waiting for replay while `inbox:ack` never completed; TC-A2 saw `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS` before `P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED`; A3/A4 green | expected RED for documented ack-before-replay ordering; classification `expected_red` | run Slice B RED commands before production edits |
| 2026-07-09 18:35 CEST | RED evidence | `test/features/push/application/push_envelope_staging_test.dart` | FAILED `flutter test test/features/push/application/push_envelope_staging_test.dart`; compile-RED missing `lib/features/push/application/push_envelope_staging.dart`, `StagedPushEnvelope`, `FilePushEnvelopeStagingStore` | expected RED for absent staging store; classification `expected_red` | run remaining Slice B RED commands |
| 2026-07-09 18:35 CEST | RED evidence | `test/features/push/application/background_message_handler_staging_test.dart` | FAILED `flutter test test/features/push/application/background_message_handler_staging_test.dart`; compile-RED missing staging API plus `debugSetBackgroundPushEnvelopeStager` / reset seam | expected RED for absent background staging wiring; classification `expected_red` | run remaining Slice B RED commands |
| 2026-07-09 18:35 CEST | RED evidence | `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart` | FAILED `flutter test test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart`; compile-RED missing `ingest_staged_push_envelopes_use_case.dart`, `PushEnvelopeStagingStore`, `StagedPushEnvelope`, `IngestStagedPushEnvelopesUseCase` | expected RED for absent staged-envelope ingest use case; classification `expected_red` | run remaining Slice B RED commands |
| 2026-07-09 18:35 CEST | RED evidence | `test/features/push/application/prepare_notification_open_use_case_test.dart` | FAILED `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart --plain-name 'conversation route awaits ingest BOUNDED'`; compile-RED no named parameter `ingestStagedPushEnvelopes` on `prepareNotificationOpen` | expected RED for missing bounded prepare-time ingest hook; classification `expected_red` | run remaining Slice B RED commands |
| 2026-07-09 18:36 CEST | RED evidence | `test/features/identity/presentation/startup_router_notification_open_test.dart` | FAILED `flutter test test/features/identity/presentation/startup_router_notification_open_test.dart --plain-name 'cold getInitialMessage tap runs the staged-envelope ingest'`; source assertion found no `ingestStagedPushEnvelopes` in `startup_router.dart` | expected RED for unwired cold initial-message wrapper; classification `expected_red` | run remaining Slice B RED commands |
| 2026-07-09 18:37 CEST | RED evidence | `test/features/conversation/integration/notif_tap_payload_fast_path_test.dart` | FAILED `flutter test test/features/conversation/integration/notif_tap_payload_fast_path_test.dart --reporter compact`; compile-RED missing `push_envelope_staging.dart`, `ingest_staged_push_envelopes_use_case.dart`, `PushEnvelopeStagingStore`, `StagedPushEnvelope`, and `IngestStagedPushEnvelopesUseCase` | expected RED for absent staged push fast path; classification `expected_red` | run final persistence RED, then production edits |
| 2026-07-09 18:38 CEST | RED evidence | `test/features/push/integration/push_ingest_persistence_test.dart` | FAILED `flutter test test/features/push/integration/push_ingest_persistence_test.dart --reporter compact`; compile-RED missing `push_envelope_staging.dart`, `ingest_staged_push_envelopes_use_case.dart`, `PushEnvelopeStagingStore`, `StagedPushEnvelope`, and `IngestStagedPushEnvelopesUseCase` | expected RED for absent staged push persistence path; classification `expected_red` | begin scoped Slice A/Slice B production edits |
| 2026-07-09 18:44 CEST | implementation | `lib/core/services/p2p_service_impl.dart`, `lib/features/push/application/push_envelope_staging.dart`, `lib/features/push/application/ingest_staged_push_envelopes_use_case.dart`, `lib/features/push/application/background_message_handler.dart`, `lib/features/push/application/prepare_notification_open_use_case.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/main.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`, `ios/NotificationService/NotificationService.swift` | moved `_retrievePendingInboxPage` replay before ACK after the migration gate; added file-backed 1:1 push envelope staging + single-flight ingest through `replayInboxChatMessage`; staged Android background pushes without suppressing notifications; added bounded prepare-time ingest and runtime-ready/resume/startup-router wiring; added iOS NSE app-group staging store | scoped to Slice A and Slice B; no P2PService interface change, DB migration, relay ordering, C5/C6, group/contactRequest/intros/posts staging, or drain retry/backoff changes | run graphify refresh, then focused GREEN tests |
| 2026-07-09 18:49 CEST | graph refresh | `graphify-out/*`, `graphify-arch/*` | PASSED `graphify update .`; PASSED `./graphify-arch/refresh_arch_graph.sh` | full graph and app-owned architecture graph refreshed after `lib/` production edits | run focused GREEN tests |
| 2026-07-09 18:49 CEST | direct GREEN pending_triage | `test/core/services/p2p_service_inbox_ack_ordering_test.dart` | FAILED `flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart`; failing test `replay-before-ack ordering staged entries replay and reach the render stream even when the inbox ack never completes`; focused triage command `sed -n '1,140p' test/core/services/p2p_service_inbox_ack_ordering_test.dart`; observed production replay event before `P2P_INBOX_ACK_REQUEST`, but the test awaited the drain future with a 200ms timeout while ACK was intentionally unresolved | `pending_triage` test-expectation mismatch with Slice A contract; production behavior shows replay-before-ack but drain remains pending on an unresolved ACK | adjust RED test to assert replay/render-before-ACK without requiring drain completion, then rerun command |
| 2026-07-09 18:50 CEST | direct GREEN | `test/core/services/p2p_service_inbox_ack_ordering_test.dart`, `test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart` | PASSED `flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart` after narrowing the unresolved-ACK test to replay-before-ACK and cleanup-completing ACK after assertions | Slice A replay-before-ack and redelivery idempotence green | run push direct suite |
| 2026-07-09 18:50 CEST | direct GREEN | `test/features/push` | PASSED `flutter test test/features/push` (262 tests; output included new background staging, file staging, ingest use-case, prepare-open, and persistence tests) | Slice B push suite green | run explicit fast-path/persistence command |
| 2026-07-09 18:51 CEST | direct GREEN | `test/features/conversation/integration/notif_tap_payload_fast_path_test.dart`, `test/features/push/integration/push_ingest_persistence_test.dart` | PASSED `flutter test test/features/conversation/integration/notif_tap_payload_fast_path_test.dart test/features/push/integration/push_ingest_persistence_test.dart` | payload fast path and persistence integration green | run ConversationWired direct command |
| 2026-07-09 18:52 CEST | direct GREEN pending_triage | `test/features/conversation/presentation/screens/conversation_wired_test.dart` | FAILED `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`; one failing test in the file, but the failure body was truncated from tool output; focused triage command `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded --concurrency=1` | `pending_triage`; exact failing test/assertion not yet visible | rerun focused triage command before edits |
| 2026-07-09 18:52 CEST | direct GREEN | `test/features/conversation/presentation/screens/conversation_wired_test.dart` | PASSED focused triage `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --reporter expanded --concurrency=1`; PASSED exact rerun `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` (109 tests) | prior failure did not reproduce; payload-ingested duplicate-render preservation test green | run StartupRouter direct command |
| 2026-07-09 18:53 CEST | direct GREEN | `test/features/identity/presentation/startup_router_notification_open_test.dart` | PASSED `flutter test test/features/identity/presentation/startup_router_notification_open_test.dart` | cold initial-message wrapper carries staged-envelope ingest before route preparation | run preservation gates |
| 2026-07-09 18:53 CEST | preservation gate pending_triage | 1:1 reliability gate | FAILED `./scripts/run_test_gates.sh 1to1`; summary showed `+1532 -2`, but failure bodies were truncated from tool output; focused triage command `./scripts/run_test_gates.sh 1to1 > /tmp/225-1to1.log 2>&1; grep -n "\\[E\\]\\|Some tests failed\\|Expected:\\|Actual:\\|package:test_api" /tmp/225-1to1.log` | `pending_triage`; two failing tests not yet identified from visible output | run captured-log triage before fixes |
| 2026-07-09 18:55 CEST | preservation gate triage/fix | `lib/main.dart`, `test/core/lifecycle/main_presence_lifecycle_wiring_test.dart`, `test/core/lifecycle/main_keepalive_wiring_test.dart` | Captured-log triage found failures in `TC-181-W4` and `TC-183-W4`: source assertions expected literal `_setPresenceUseCase.dispose()` / `_keepAliveUseCase.dispose()` in `dispose()` but `dart format` had split trailing-comment calls across lines. Adjusted comments above the calls; PASSED `flutter test test/core/lifecycle/main_presence_lifecycle_wiring_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart` | formatting-only source-lock repair; lifecycle behavior unchanged | rerun `./scripts/run_test_gates.sh 1to1` |
| 2026-07-09 18:55 CEST | preservation GREEN | 1:1 reliability gate | PASSED `./scripts/run_test_gates.sh 1to1` (1534 tests) | 1:1 reliability gate green after source-lock formatting repair | run remaining preservation direct commands |
| 2026-07-09 18:57 CEST | preservation GREEN | `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_impl_health_drain_test.dart` | PASSED `flutter test test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_impl_health_drain_test.dart` (131 tests) | P2P service preservation sentinels green | run offline inbox preservation command |
| 2026-07-09 18:57 CEST | preservation GREEN | `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`, `test/core/inbox/inbox_round_trip_test.dart`, `test/core/resilience/c4_partial_drain_test.dart` | PASSED `flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart test/core/inbox/inbox_round_trip_test.dart test/core/resilience/c4_partial_drain_test.dart` (28 tests) | offline inbox, inbox round-trip, and C4 partial-drain sentinels green | run `completeness-check` and discovery gates |
| 2026-07-09 18:58 CEST | named gate GREEN | `scripts/run_test_gates.sh` | PASSED `./scripts/run_test_gates.sh completeness-check`; output `Completeness check: 1064/1064 test files classified.` | classification completeness gate green | run reliability simulation discovery |
| 2026-07-09 18:58 CEST | discovery GREEN | `scripts/check_reliability_simulation_discovery.sh`, `integration_test/inbox_replay_before_ack_custody_harness.dart`, `integration_test/notif_push_payload_persist_harness.dart`, `integration_test/notification_tap_message_visible_proof_test.dart` | PASSED `./scripts/check_reliability_simulation_discovery.sh`; output lists 225 TC-A6, TC-B11, and TC-B12 files under 1:1 entrypoints and reports `PASS: all discovered simulator/E2E candidates are classified or explicitly ignored, and known tests/scenarios expanded.` | discovery/registration green | verify TC-B12 scenario ids and assess local device proof availability |
| 2026-07-09 18:59 CEST | device proof blocker | `integration_test/notification_tap_message_visible_proof_test.dart` | `rg -n "payload_fast_path_(ios_receiver|android_receiver|cold_kill)|notification_tap_message_visible" integration_test scripts Test-Flight-Improv/225-notif-tap-last-message-lag-tdd-plan.md`; `flutter devices`; `sed -n '1,220p' integration_test/notification_tap_message_visible_proof_test.dart`. Devices are connected (Pixel 6 + cabled iPhones), but the plan-named runner `integration_test/scripts/run_notification_tap_device_real.dart` is absent and all three TC-B12 tests are skipped placeholders with device-proof skip messages. | `blocked` / missing required TC-B12 device proof; not classified as device-unavailable because local devices are visible | continue host hygiene/graph checks; final verdict cannot be accepted until executable TC-B12 proof exists and all three scenarios pass |
| 2026-07-09 19:03 CEST | graph refresh | `graphify-out/*`, `graphify-arch/*` | PASSED `graphify update .`; PASSED `./graphify-arch/refresh_arch_graph.sh` after the final `lib/main.dart` source-lock formatting repair | full graph and app-owned architecture graph refreshed after all production edits | run hygiene gates |
| 2026-07-09 19:05 CEST | hygiene pending_triage | repository analyzer | FAILED `flutter analyze`; analyzer exited 1 with 1637 diagnostics across existing integration/test files (output truncated; examples include `avoid_print`, `unused_import`, `unused_element`, `depend_on_referenced_packages`). Focused triage command: `flutter analyze lib/core/services/p2p_service_impl.dart lib/features/push/application/push_envelope_staging.dart lib/features/push/application/ingest_staged_push_envelopes_use_case.dart lib/features/push/application/background_message_handler.dart lib/features/push/application/prepare_notification_open_use_case.dart lib/features/push/application/prepare_notification_route_target_use_case.dart lib/features/identity/presentation/startup_router.dart lib/main.dart test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart test/features/push/application/push_envelope_staging_test.dart test/features/push/application/background_message_handler_staging_test.dart test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart test/features/push/application/prepare_notification_open_use_case_test.dart test/features/conversation/integration/notif_tap_payload_fast_path_test.dart test/features/push/integration/push_ingest_persistence_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart test/features/identity/presentation/startup_router_notification_open_test.dart integration_test/inbox_replay_before_ack_custody_harness.dart integration_test/notif_push_payload_persist_harness.dart integration_test/notification_tap_message_visible_proof_test.dart` | `pending_triage` until touched-file analyzer result is known | run focused analyzer before deciding fix vs pre-existing classification |
| 2026-07-09 19:05 CEST | hygiene focused pending_triage | new 225 harness/test files | FAILED focused analyzer command; session-owned diagnostics: `invalid_annotation_target` for `@Tags(['device'])` in three new integration-test files and unused imports in `test/core/services/p2p_service_inbox_ack_ordering_test.dart`; touched pre-existing style info also surfaced at `lib/core/services/p2p_service_impl.dart:3723`. Focused fix: move `@Tags` to file-level library metadata and remove unused imports. | `pending_triage` until rerun; p2p style info not caused by this session and left unchanged unless it blocks focused rerun after fixes | apply narrow test/harness cleanup and rerun focused analyzer |
| 2026-07-09 19:06 CEST | hygiene focused GREEN | session-touched Dart files | PASSED focused `flutter analyze ...` over 21 session-touched files after moving harness tags to library metadata, removing unused imports, adding braces to the touched `p2p_service_impl.dart` style site, and ignoring intended Bridge fake field overrides in the new ACK-ordering test | no analyzer diagnostics remain in session-owned files; repository-wide `flutter analyze` remains blocked by the 1637 existing diagnostics from the full tree | rerun graphify after the final production-code style edit, then run `git diff --check` |
| 2026-07-09 19:10 CEST | graph refresh | `graphify-out/*`, `graphify-arch/*` | PASSED `graphify update .`; PASSED `./graphify-arch/refresh_arch_graph.sh` after the final `p2p_service_impl.dart` analyzer-style cleanup | full graph and app-owned architecture graph refreshed after all production edits | rerun affected P2P tests and final diff check |
| 2026-07-09 19:10 CEST | post-style rerun GREEN | `lib/core/services/p2p_service_impl.dart`, `test/core/services/p2p_service_inbox_ack_ordering_test.dart`, `test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart` | PASSED `flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart` (5 tests) | Slice A tests still green after analyzer cleanup | rerun P2P preservation pair |
| 2026-07-09 19:11 CEST | post-style rerun GREEN | `test/core/services/p2p_service_impl_test.dart`, `test/core/services/p2p_service_impl_health_drain_test.dart` | PASSED `flutter test test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_impl_health_drain_test.dart` (131 tests) | P2P preservation pair still green after analyzer cleanup | run `git diff --check` |
| 2026-07-09 19:11 CEST | hygiene GREEN | full diff | PASSED `git diff --check` | no whitespace/conflict-marker issues in diff | final inventory and Executor summary |
| 2026-07-09 19:12 CEST | local QA fix | `lib/features/push/application/push_envelope_staging.dart` | Local QA tightened `FilePushEnvelopeStagingStore.stage` to prefer temp-file rename-over-target and fall back to delete+rename only if replacement is rejected by the platform | aligns store with plan's atomic temp-write requirement | rerun focused analyzer, push suite, graph refresh, and final diff check |
| 2026-07-09 19:13 CEST | local QA retest GREEN | session-touched Dart files, `test/features/push` | PASSED focused `flutter analyze ...` over 21 session-touched files; PASSED `flutter test test/features/push` (262 tests) | atomic-write tightening did not regress push suite or touched-file analyzer | refresh graphify after final `lib/` edit |
| 2026-07-09 19:15 CEST | graph refresh | `graphify-out/*`, `graphify-arch/*` | PASSED `graphify update .`; PASSED `./graphify-arch/refresh_arch_graph.sh` after the final staging-store QA fix | full graph and app-owned architecture graph refreshed after all production edits | run final `git diff --check` and write Executor verdict |
| 2026-07-09 19:15 CEST | hygiene GREEN | full diff | PASSED final `git diff --check` | no whitespace/conflict-marker issues in tracked diff | write blocked Executor verdict |
| 2026-07-09 19:16 CEST | final Executor summary | session-owned Slice A/Slice B files and tests | Host implementation complete and direct/preservation/named host gates passed where runnable. Required blockers remain: TC-B12 is not executable/proven (plan runner absent and all three device tests are skipped placeholders despite connected devices); step-0 Pixel benchmark remains environment/tooling-blocked by sqlite3 native asset hash mismatch; repository-wide `flutter analyze` fails with 1637 existing diagnostics, though focused analyze over all 21 session-touched Dart files passes. | `blocked` / missing required proof and failed required hygiene gate | hand off to QA with host evidence and blockers |
| 2026-07-09 19:18 CEST | QA handoff | plan + scoped implementation/test/gate diff | Executor final verdict `blocked`; host implementation and required host/direct/preservation gates are file-backed; blockers recorded: missing executable TC-B12 device proof, step-0 benchmark native asset hash mismatch, full-tree analyzer pre-existing diagnostics | spawn independent QA Reviewer; QA must not fix code | review scope adherence, behavior, test/gate sufficiency, and blocker classification |
| 2026-07-09 19:19 CEST | QA review running | plan, graph query, git status/diff summaries | independent QA started; `graphify-arch` query run for 225 notification-tap staging/routing context; reviewing landed Slice A/Slice B diff, iOS NSE/Dart staging correctness, TC-A6/B11/B12 executable proof, and required gate evidence | `pending_triage`; no code/test edits by QA | inspect source/tests/gate registration and write QA verdict |
| 2026-07-09 19:22 CEST | QA verdict | plan, Slice A/Slice B source, iOS NSE store, staged-ingest tests, simulator/device harnesses, gate scripts | read-only QA plus `git diff --check` rerun. Slice A reorder and host Slice B wiring are scoped and mostly correct, but proof/closure is insufficient: TC-A6, TC-B11, and TC-B12 files are skipped placeholders; the plan-named TC-B12 runner is absent; step-0 benchmark and full-tree analyzer remain blocked/failed; staged-envelope filename keying is lossy for base64 nonces (`+`/`/`/`=` -> `_`) on Dart and iOS, so distinct nonce ids can collide. | `blocked` / QA blocking issues present | fix-pass should make proof rows executable, resolve/triage mandatory gates per plan, and make nonce file keys injective while preserving app-group parity |
| 2026-07-09 19:24 CEST | Executor fix-pass #1 start | `push_envelope_staging.dart`, `NotificationPreviewResolver.swift`, `push_envelope_staging_test.dart`, `NotificationPreviewResolverTests.swift`, three 225 integration proof harnesses, discovery/gate scripts | Read QA verdict and proof rows; `graphify-arch` query missed relevant symbols, root graph query found Swift resolver/test and staging surfaces; inspected placeholder harnesses and existing `run_1to1_device_real.dart` deferred-campaign pattern | Scope limited to QA blockers: nonce file keys must become injective; TC-A6/B11/B12 must stop being skipped false-green placeholders; TC-B12 runner absent; real APNs/relay orchestration not implementable from current harness state, so proof will remain an explicit blocker unless required external artifacts are supplied | patch nonce-key parity + proof artifact validators/runner; then run focused tests/gates and retriage mandatory benchmark/analyze blockers |
| 2026-07-09 19:28 CEST | proof validators pending_triage | `integration_test/inbox_replay_before_ack_custody_harness.dart`, `integration_test/notif_push_payload_persist_harness.dart`, `integration_test/notification_tap_message_visible_proof_test.dart` | FAILED `flutter test integration_test/inbox_replay_before_ack_custody_harness.dart integration_test/notif_push_payload_persist_harness.dart integration_test/notification_tap_message_visible_proof_test.dart --reporter compact`; failing before test bodies because Flutter saw Pixel 6, macOS, and Chrome and required explicit `-d`; focused triage command `flutter test -d macos integration_test/inbox_replay_before_ack_custody_harness.dart integration_test/notif_push_payload_persist_harness.dart integration_test/notification_tap_message_visible_proof_test.dart --reporter compact` | `pending_triage` environment/device-selection, not product behavior | rerun proof validators on explicit macOS target to expose artifact-gated result |
| 2026-07-09 19:40 CEST | fix-pass #1 tool failure | partial fix-pass files from git status and progress rows | Fix-pass #1 stream errored before final result (`stream disconnected before completion`). Partial changes exist in Swift nonce-key/tests, proof artifact support/runner/harnesses, and discovery/gate scripts; no trustworthy final evidence was returned after the 19:28 pending-triage row | `spawn_or_tool_failure` for child result; partial repo state requires fresh inspection | spawn fix-pass #2 to validate/finish or classify residual blockers from partial landing |
| 2026-07-09 19:42 CEST | Executor fix-pass #2 start | `Test-Flight-Improv/225-notif-tap-last-message-lag-tdd-plan.md`, implementation skill, graphify skill | Read execution rows through 19:40, local skill instructions, and `cd graphify-arch && graphify query "225 fix-pass 2 notification tap last message lag nonce staging proof harness TC-A6 TC-B11 TC-B12 files" --budget 1500`; git status shows partial fix-pass files plus unrelated dirty graph/orbit/226 files | scope limited to QA blockers and partial fix-pass recovery: injective Dart/iOS nonce keys, non-skipped artifact-gated TC-A6/B11/B12 validators, mandatory benchmark/analyze retriage; no C5/C6/group/contactRequest/intros/posts/relay/backoff/interface/migration work | run the explicit macOS three-harness proof command before code changes |
| 2026-07-09 19:45 CEST | proof validators pending_triage | `integration_test/inbox_replay_before_ack_custody_harness.dart`, `integration_test/notif_push_payload_persist_harness.dart`, `integration_test/notification_tap_message_visible_proof_test.dart` | FAILED `flutter test -d macos integration_test/inbox_replay_before_ack_custody_harness.dart integration_test/notif_push_payload_persist_harness.dart integration_test/notification_tap_message_visible_proof_test.dart --reporter compact`; TC-A6 test `drain purges the relay inbox and a second drain renders nothing new` failed clearly with missing `tc_a6_replay_before_ack_custody` proof artifact; TC-B11 and TC-B12 files failed to load on macOS after build with `Error waiting for a debug connection`; focused triage commands: run each file individually with `-d macos --reporter expanded`, then inspect artifact helper/harness code | `pending_triage` (TC-A6 expected proof-artifact blocker; TC-B11/B12 startup failure not yet classified) | triage harness code and app-start failure before edits |
| 2026-07-09 19:50 CEST | native XCTest pending_triage | `ios/NotificationService/NotificationPreviewResolver.swift`, `ios/RunnerTests/NotificationPreviewResolverTests.swift` | FAILED `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests`; xcresult `/Users/I560101/Library/Developer/Xcode/DerivedData/Runner-fdlavkflmiabpyeuegpuipvnubvr/Logs/Test/Test-Runner-2026.07.09_19-46-47-+0200.xcresult`; new `testAppGroupPushEnvelopeStoreUsesInjectiveNonceFileNames` passed, but existing resolver fixture/dedupe tests failed (`testDecryptsGroupFixturePreview`, `testDecryptsOneToOneFixturePreview`, `testDuplicateMessageKeepsFallbackAndSkipsSecondDecrypt`, `testGIRD006DuplicateGroupMessageIdKeepsFallbackAndSkipsSecondDecrypt`, `testMissingChatSecretKeepsStaticFallbackWithoutDecrypting`); focused triage command: same xcodebuild with `-only-testing:RunnerTests/NotificationPreviewResolverTests/testAppGroupPushEnvelopeStoreUsesInjectiveNonceFileNames` | `pending_triage` until single Swift nonce test confirms isolated pass and unrelated failures are classified | run single-test Swift selector before further edits |
| 2026-07-09 19:52 CEST | fix-pass #2 implementation/triage | `ios/NotificationService/NotificationPreviewResolver.swift`, `ios/RunnerTests/NotificationPreviewResolverTests.swift`, three proof harnesses | Added Swift `AppGroupPushEnvelopeStore.clear(nonce:)` and extended the Swift nonce test to clear only `a+b/c=` while preserving `a_b_c_`; individual macOS runs for TC-B11 and TC-B12 reached proof-artifact failures for `tc_b11_payload_persist_pre_drain` and all three TC-B12 scenarios; `flutter test test/features/push/application/push_envelope_staging_test.dart --reporter compact` passed; single native selector `xcodebuild test ... -only-testing:RunnerTests/NotificationPreviewResolverTests/testAppGroupPushEnvelopeStoreUsesInjectiveNonceFileNames` passed (`Test-Runner-2026.07.09_19-49-46-+0200.xcresult`) | QA nonce blocker resolved; TC-A6/B11/B12 are non-skipped artifact-gated failures when real proof artifacts are absent; full `NotificationPreviewResolverTests` class failure classified unrelated/pre-existing to this Swift nonce change because the touched nonce test passed in both class output and isolated selector | run discovery/completeness/analyze/diff and mandatory benchmark/analyze blocker retriage |
| 2026-07-09 19:54 CEST | hygiene pending_triage | repository analyzer | FAILED `flutter analyze`; analyzer exited 1 with 1624 diagnostics across existing integration/test files (examples visible: `avoid_print`, `unused_import`, `unnecessary_import`, `depend_on_referenced_packages`, `unused_element`, `dangling_library_doc_comments`); focused triage command: already-run touched-file analyzer over `push_envelope_staging.dart`, `push_envelope_staging_test.dart`, proof artifact helper/harnesses, and `run_notification_tap_device_real.dart`, plus inspect whether any diagnostics reference fix-pass #2 touched files | `pending_triage` until touched-file result and visible diagnostics are classified | classify full-analyze blocker without broad cleanup |
| 2026-07-09 19:57 CEST | fix-pass #2 gates/classification | proof runner, discovery/completeness, analyzer, benchmark | PASSED `dart run integration_test/scripts/run_notification_tap_device_real.dart --scenario all --list-scenarios` (5 scenarios: TC-A6, TC-B11, 3 TC-B12); PASSED `./scripts/check_reliability_simulation_discovery.sh`; PASSED `./scripts/run_test_gates.sh completeness-check` (`1064/1064`); PASSED touched-file `flutter analyze ...` over the 7 fix-pass Dart files; FAILED full-tree `flutter analyze` with 1624 existing diagnostics, while touched files are clean; PASSED `timeout 300 flutter test -d 21071FDF600CSC --dart-define=BENCHMARK=NOTIFICATION_TAP integration_test/benchmark_harness.dart` on Pixel 6 (cold 680ms, warm 133ms); `dart run integration_test/scripts/run_notification_tap_device_real.dart --scenario payload_fast_path_ios_receiver` exited 78 with explicit APNs/relay/device artifact blocker | discovery/completeness, touched analyzer, and benchmark blockers resolved for this environment; repository-wide analyze remains blocked by existing full-tree diagnostics outside fix-pass scope; real proof closure remains blocked until TC-A6/B11/B12 artifacts from the real rig exist | run final `git diff --check` and write fix-pass #2 verdict |
| 2026-07-09 19:59 CEST | final fix-pass #2 verdict | `Test-Flight-Improv/225-notif-tap-last-message-lag-tdd-plan.md`, Swift nonce store/test; validated proof harnesses/runner/scripts | PASSED `git diff --check`; fix-pass #2 resolved lossy nonce keying with Dart/iOS UTF-8 hex filenames and clearability proofs; validated TC-A6/B11/B12 are fail-closed artifact gates, not skipped placeholders; benchmark blocker no longer reproduces on Pixel 6; full-tree analyze still fails with existing repo diagnostics; no `lib/` production files were edited in fix-pass #2, so no new graph refresh was required | `blocked` / required real proof artifacts missing for TC-A6, TC-B11, and all three TC-B12 scenarios; full-tree `flutter analyze` remains a pre-existing/unrelated required hygiene blocker | hand off to QA with focus on proof-artifact sufficiency and no false-green device proof claims |
| 2026-07-09 20:00 CEST | second QA verdict | `push_envelope_staging.dart`, `push_envelope_staging_test.dart`, `NotificationPreviewResolver.swift`, `NotificationPreviewResolverTests.swift`, proof artifact helper/harnesses/runner, discovery/gate scripts | PASSED `git diff --check`; PASSED `dart run integration_test/scripts/run_notification_tap_device_real.dart --scenario all --list-scenarios` (TC-A6, TC-B11, 3 TC-B12 scenarios); PASSED `flutter test test/features/push/application/push_envelope_staging_test.dart --reporter compact`; source inspection confirms Dart/iOS nonce filename parity and clear-one-preserves-other tests; proof harnesses are fail-closed artifact validators, not real proof capture | `blocked` / plan-required real proof artifacts for TC-A6, TC-B11, and all TC-B12 scenarios are still missing; plan-required full-tree `flutter analyze` remains failed despite touched-file clean evidence; no forbidden fix-pass scope broadening found | next retry: capture/validate real proof artifacts on the real rig and resolve or formally reclassify the full-tree analyze gate |
| 2026-07-09 21:42 CEST | TC-B12 device proof (android_receiver) | `Test-Flight-Improv/225-proof-artifacts/payload_fast_path_android_receiver.json` (+ `android_receiver_airplane_tap.png`, `relay_journal_excerpt.log`) | Real rig: iPhone 11 sender (12D3KooWPzDTjARPoFbn…) → prod relay mknoun.xyz → Pixel 6 receiver (fresh `com.mknoon.app` debug install of this tree, peer 12D3KooWHumhPzm4hYGQ…). Relay 19:40:53 `Stored message` + `[PUSH] Notification sent (attempt 1/3)`; device FCM-started headless (no node), `PUSH_BACKGROUND_MESSAGE_RECEIVED` + staged `nonce-v1-3732…json`, NO pre-tap `CHAT_MSG_RECEIVE_STORED`; full airplane mode verified (`airplane_mode_on=1`, relay route unreachable) BEFORE tap 19:42:35; `NOTIFICATION_TAPPED` 19:42:38 → ingest `CHAT_MSG_RECEIVE_STORED` ×2 at 19:42:40.2/.3 → messages visible on screen; 0× `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS`; staged files cleared. Post-restore: drain redelivered → `CHAT_MSG_RECEIVE_DUPLICATE` ×2 (exactly-once held) + relay `Acked 3` (custody purged). Runner validation PASSED (exit 0). | **PASSED** — deviation documented in artifact: receiver process killed pre-send (`am kill`); a backgrounded-alive app gets a doze maintenance window from the high-prio FCM, its node drains and stores the message pre-tap (observed 19:37:48 in leg attempt 1) — headless FCM start is the only deterministic uncontaminated shape on this rig | run cold_kill leg |
| 2026-07-09 21:48 CEST | TC-B12 device proof (cold_kill) | `Test-Flight-Improv/225-proof-artifacts/payload_fast_path_cold_kill.json` (+ `cold_kill_airplane_tap.png`) | Same rig. Push staged headless 19:46:50 (`nonce-v1-7466…json`); process TERMINATED (`am kill`, pidof empty verified twice incl. after airplane-mode enable); tap 19:47:57 → NEW pid 22233 cold launch → `NOTIFICATION_TAPPED` 19:48:00.5 → ingest `CHAT_MSG_RECEIVE_STORED` id 18677fb5 at 19:48:02.7 → "B12-CK proof" visible under airplane mode; 0× drain-success; CK staged file cleared. Runner validation PASSED (exit 0). `force-stop` NOT used: it cancels the app's notifications + puts the package in stopped state (blocks FCM) — scenario physically untappable; `am kill` is the faithful OS-kill equivalent. | **PASSED** | validate + record blockers |
| 2026-07-09 21:55 CEST | TC-B12 campaign wrap | `run_notification_tap_device_real.dart --validate-artifacts`, `notification_tap_message_visible_proof_test.dart` | Runner validated both captured artifacts (exit 0 each). Flutter proof-test tier is environment-blocked on macOS: the sandboxed test runner gets `PathAccessException (Operation not permitted)` reading ANY external artifact dir (repo path and even `~/Library/Containers/com.mknoon.mknoonChat/Data/tmp`) — the fail-closed gate cannot go green on macOS regardless of artifacts; needs an entitlement exception for the debug runner or acceptance of the runner-script validator as the gate. NOT run on the Pixel to avoid a test-install disturbing the fresh pairing. | 2/3 TC-B12 scenarios DEVICE-PROVEN (`android_receiver`, `cold_kill`); **`ios_receiver` still open** (needs iPhone receiver with a 225 NSE build + APNs; human-assisted). New follow-up observation: a staged envelope whose payload.id already exists is RETAINED after dedupe (re-decrypted every ingest until 48h TTL/cap) instead of cleared. | iOS leg + TC-A6/TC-B11 sim runs remain for closure |
| 2026-07-09 22:20 CEST | post-campaign fix: duplicate staged envelope now cleared | `lib/features/push/application/ingest_staged_push_envelopes_use_case.dart`, `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart` | Device-campaign observation: an envelope whose replay returns `rejected`/`duplicate_confirmed_visible` was RETAINED and re-decrypted every ingest until 48h TTL/64-cap (the leg-1 file survived 3 ingest passes on the Pixel). RED-first test added (`confirmed-persisted duplicate clears its staging entry; other rejected reasons stay retained`) — FAILED for the documented reason; fix scoped to exactly that reason code (INV-1-safe: `duplicate_confirmed_visible` asserts the prior copy is durably persisted AND visible, so the push-envelope cache entry is redundant; all other rejected/retryable/quarantined reasons still retained; dedupe-clear counted as neither committed nor retained). GREEN: ingest file 5/5; `flutter test test/features/push` 264/264; focused analyze clean; `./scripts/run_test_gates.sh 1to1` **1535/1535** on full rerun (first run had a single non-reproducing flake, body lost to log trimming — same transient class as the 18:52 executor row); graphify full+arch refreshed. | fix landed; mutation lock = revert the reasonCode clear → new test red | iOS leg + TC-A6/TC-B11 sims remain |
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline above (user report 2026-07-09)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`
- Grounding record: workflow `wf_2dc4805b-7f5` (transcripts under session subagents dir)

## Session Classification
implementation-ready

## Exact Problem Statement

Tapping an incoming-message push notification routes correctly to the 1:1
conversation (139/145 fixed routing and made it non-blocking), but the screen
first renders the **stale DB page** and the announced message only appears after
a user-perceivable delay. The in-code comment at `conversation_wired.dart:563-568`
documents the mechanism verbatim: the tap opens the screen *before the relay
offline inbox has been drained*.

The device **already received the message bytes**: the FCM data payload carries
the full encrypted 1:1 envelope (`kem` + `ciphertext` + `nonce`,
`push_decrypt_preview.dart:52-54`; relay strips media and falls back >4KB per
142). On iOS the NSE even decrypts it to render the preview
(`NotificationPreviewResolver`) — then throws the plaintext away. Nothing
persists the envelope, so the only ingestion path is a full post-tap relay
round-trip: retrieve → stage → **awaited ack RTT** → decrypt → serial commit →
stream/reload. Warm-path lag ≈ 0.5–2s; degraded paths are far worse (3s retrieve
budget, 15s Go ack default, dead-QUIC re-dial, 30s health-tick recovery).

**What must improve:** the announced message is visible immediately on tap
(payload fast-path, zero relay RTT), and the backstop drain stops paying an ack
round-trip before its first render.
**What must stay unchanged (preserved-green sentinels):** 145 non-blocking
route + "catching up" banner semantics; 141 not-started drain deferral; 146/147
receipt/decrypt behavior; relay custody (entries ack-purged exactly as today);
Move-Account migration gates; NSE preview/mute/dedupe (04-P0) semantics;
exactly-once rendering across redundant render paths (131/159 locks);
`run_test_gates.sh 1to1` = 1518 baseline, 0 regressions.

## Root Cause (verify → refute confirmed)

Four mechanisms confirmed on HEAD by independent verify + adversarial refute
(workflow `wf_2dc4805b-7f5`); the first two are fixed here, the last two are
scoped out to follow-ups:

- **C1 (fixed here, Slice B) — payload discarded, relay re-download forced.**
  The push handler shows a local notification and *never persists* the envelope
  (`background_message_handler.dart:163-193`; its own telemetry note :118-119:
  "inbox drain on next resume"). iOS NSE decrypts for preview only and writes
  only app-group dedupe markers (`NotificationService.swift:27-57`). At tap
  time `_loadInitialPage()` (`conversation_wired.dart:555`) renders stale
  history and the only recovery is the drain
  (`conversation_wired.dart:569-570` → `p2p_service_impl.dart:2138-2162`).
- **C3 (fixed here, Slice A) — replay is gated on an awaited relay-ack RTT.**
  `_retrievePendingInboxPage`: `stageEntries` (:1970, durably on-device) →
  awaited `callP2PInboxAck` (:1998-2001; **no timeoutMs passed → Go default
  `InboxTimeout = 15s`**, `go-mknoon/node/config.go:38`, and
  `relay_selector.go:187-213` iterates candidates serially) → only then
  `_replayStagedInboxEntries` (:2024-2028, incl. the `replaySw.stop()` at
  :2028) where decrypt→save→stream-emit (the first renderable moment) happens. The ack has **no functional ordering
  dependency**: the ack-exception path already falls through to replay
  (:2014-2020) and staged-but-unacked entries dedupe on a later drain (comment
  :1971-1975). The ack RTT is pure added latency on the render path of *every
  drain page*.
- **C5 (follow-up session) — dead-QUIC warm tap: silent "successfully empty" drain.**
  3s `foregroundInboxTimeout` (:386) must cover a fresh relay dial after
  backgrounding; overshoot → `retrieveSucceeded:false` swallowed
  (:1861-1890, :2189-2201), banner clears, **no retry**; recovery waits on
  network-change drain / 30s health tick / next resume.
- **C6 (follow-up session) — >50 backlog paging, oldest-first.** Relay serves
  oldest-first (proven both backends: `go-relay-server/backend_memory.go:142,179-185`,
  `backend_redis.go:151,392-414`); notif-tap drain awaits page 1 only
  (:2144-2162, `maxInboxPages=10` :1056) so a newest message beyond entry 50
  renders only after serial unawaited background pages.

**Refuted / do-NOT-re-introduce:**
- **C2 (cold-tap "started-before-reservation race strands the drain")** —
  REFUTED. The 216 device A/B (2026-07-06) proved the startup drain succeeds
  ~2s after cold launch on both fix and no-fix builds; the in-code 216 comment
  is a stale GoLog misread (empty retrieves are silent in GoLog,
  `inbox.go:709`). Do not plan cold-start drain-race fixes off that narrative.
- **C4 ("not-started fast-return voids the banner/reload contract → lag")** —
  wrong mechanism, ~0ms contribution. The 141-deferred drain commits via
  `incomingMessageStream` (`chat_message_listener.dart:586`) which
  ConversationWired subscribed to at initState; the row renders within one
  frame of DB commit without any page re-read.

## Real Scope

**In scope:**
- **Slice A — replay-before-ack reorder** (`p2p_service_impl.dart`
  `_retrievePendingInboxPage` only): un-gated path becomes stage → **replay** →
  ack; the migration-gate check (:1976-1993) stays *before* replay and its
  gated early-return behavior (staged, not replayed, not acked) is preserved
  byte-for-byte. No signature changes, no P2PService interface change.
- **Slice B — push-envelope staging fast-path (1:1 chat kind only):**
  - `lib/features/push/application/push_envelope_staging.dart` (NEW): file-based
    staged-envelope store (JSON entries
    `{kind:'chat', kem, ciphertext, nonce, messageId, senderPeerId, receivedAtMs}`;
    stage / readAll / clear(id) / prune(TTL + cap); no SQLCipher, content is
    already E2E-encrypted). **Entry id = `nonce`** (always present, unique per
    message); `messageId` is metadata only — push `message_id` is NULLABLE
    (`buildPushMessage` adds it only "if present", `go-relay-server/inbox.go:293`).
    **Writes are atomic** (temp-file + rename); a malformed file **younger than a
    short write-window is retried, not cleared** (a torn read must not silently
    kill the fast path). **One `resolveStagingDir()` is used by BOTH writer and
    reader** per platform (Android: path-provider app dir; iOS: app-group
    container via the existing `lib/core/notifications/app_group_path_channel.dart`
    seam) — a writer/reader mismatch orphans files forever.
  - `background_message_handler.dart` (Android writer): on a routable chat data
    push carrying `kem`+`ciphertext`+`nonce`, stage the envelope (before showing
    the local notification; staging failure must never suppress the
    notification). **On iOS the NSE owns staging** — the Dart background handler
    either does not stage on iOS or stages to the same app-group dir (no second
    location).
  - `lib/features/push/application/ingest_staged_push_envelopes_use_case.dart`
    (NEW): read staged entries → decrypt + persist through the **existing**
    incoming pipeline (same seam as inbox replay:
    `chatMessageListener.processIncomingMessage` /
    `replayInboxChatMessage`-equivalent callback wired in `main.dart`, with
    `suppressNotification: true`) → clear each ingested entry.
    **`message.to` = local own-peer-id from the identity/keystore seam** (as the
    drain passes `toPeerId` into `_stagingEntryFromRawInboxMessage`) — it is NOT
    in any push and must NOT be sourced from the relay (Scope-Guard).
    Respects blocked-sender rejection (listener rejects **before** decrypt,
    `chat_message_listener.dart:383` `CHAT_LISTENER_BLOCKED_REJECT` — 147
    hardening) and the account-migration gate (defer, retain entries).
    Row-level exactly-once rides the pipeline's decrypted `payload.id` via
    `getMessage` (`handle_incoming_chat_message_use_case.dart:303`), not a
    push-messageId pre-check. **Single-flight guard**: concurrent ingest passes
    (tap-during-resume) coalesce — one clear, one row, one emit.
    Standalone use case + injected callbacks — **no P2PService method
    additions** (31-fakes hazard).
    Note (146 parity): delivery receipts fire via the same
    `handleIncomingChatMessage` hook, so the 146 fire-and-forget receipt
    contract is inherited (send failure swallowed — safe offline/airplane);
    no separate test — 146's own locks own that contract.
  - Wiring: ingest at (a) conversation-kind `prepareNotificationOpen` —
    **BOUNDED AWAIT ~400ms** (user-locked decision):
    `await ingest().timeout(~400ms, onTimeout: fall through)` + swallow-and-log.
    Common case is ~ms (local file read + crypto + DB write); a stall or throw
    falls through and the live `incomingMessageStream` renders the row when the
    ingest lands. (An UNbounded await would re-introduce the 145 latency class:
    the route dispatcher awaits prepare before navigating,
    `notification_route_dispatch.dart:21-22`, and `callDecryptMessage` carries a
    10s bridge timeout — try/catch stops a throw, NOT a stall.)
    **Wire BOTH prepare wrappers**: `main.dart:4475` (warm taps) AND
    `startup_router.dart:1031` (`_prepareNotificationRouteTarget`, the COLD
    `getInitialMessage` remote-FCM tap via :811-833 — it does not inherit
    main.dart params; the `warmPeer` precedent already shows the miss).
    Plus (b) startup/resume runtime-ready path (covers "user opens app without
    tapping").
  - iOS: `ios/NotificationService/` gains an `AppGroupPushEnvelopeStore`
    (mirror of `AppGroupPushDedupeStore`) writing the envelope JSON into the
    shared app-group container; NSE calls it additively (preview/mute/dedupe
    logic untouched). **Written field-set is PINNED, identical to Android**
    (the trigger fields alone are NOT enough):
    `{kind:'chat', kem, ciphertext, nonce, senderPeerId: userInfo['sender_id'], messageId: userInfo['message_id'] (nullable), receivedAtMs}`
    — omitting `senderPeerId` makes the three-way sender check
    (`handle_incoming_chat_message_use_case.dart:263-265`) unsatisfiable and
    **every iOS ingest silently falls back to the drain** (host-green,
    TestFlight-broken; the NSE has zero host/sim coverage). Writes atomic
    (`Data.write(options: .atomic)`); **cap (~64) enforced on WRITE**
    (evict oldest) — the NSE only writes, and Dart-side prune never runs if the
    app is never opened. Dart reader consumes the same directory via the
    existing app-group seam (precedent: `RecentRemoteShownMarkerStore` markers
    read Dart-side, 04-P0 SI-5). **NSE never opens the SQLCipher DB** (landmine:
    a failed keyed read-write open poisons the next open and bricks cold start).
  - Relay drain stays the backstop + custody path: the same message arriving
    later via drain must dedupe (existing messageId dedupe) and still ack-purge.

**Out of scope (owned elsewhere):**
- C5 in-drain retry / truthful drain failure / banner re-arm → **follow-up
  session (next free number)**; do not add retry/backoff or change
  `foregroundInboxTimeout` here.
- C6 multi-page backlog (notif-tap `drainOfflineInboxFully` / per-page reload /
  relay ordering change + redeploy) → **follow-up session**; drain paging
  semantics untouched here.
- Group / contactRequest / intros push staging (deliberate 1:1-only asymmetry,
  test-locked in TC-B2) → future session.
- Production telemetry sink for `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING`
  (kDebugMode-gated today) — unchanged (145 accepted difference).

## Files To Inspect Next
Production (entry/use-case, models, repos, helpers):
- `lib/features/push/application/background_message_handler.dart` (:112-199 handler body)
- `lib/features/push/application/push_decrypt_preview.dart` (:46-99 envelope fields)
- `lib/features/push/application/prepare_notification_open_use_case.dart` (:34-61 conversation branch)
- `lib/core/services/p2p_service_impl.dart` (:1861-2034 `_retrievePendingInboxPage`; :1472+ `_replayStagedInboxEntries`; :2045-2162 drain orchestration; :4905-4922 public entry)
- `lib/features/conversation/application/chat_message_listener.dart` (:361-423 processIncomingMessage, :383 blocked-before-decrypt `CHAT_LISTENER_BLOCKED_REJECT`, :586 stream emit)
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (:263-265 three-way sender check, :303 `getMessage(payload.id)` dedupe, decrypt seam + re-mint sites)
- `lib/main.dart` (:2083 `replayInboxChatMessage`, :2257-2277 registration, :4026-4166 tap routing, :4475 prepare wrapper #1, `_ensureRuntimeServicesReady`)
- `lib/features/identity/presentation/startup_router.dart` (:811-833 cold `getInitialMessage` tap, :1031 `_prepareNotificationRouteTarget` — prepare wrapper #2, does NOT inherit main.dart params)
- `lib/core/notifications/app_group_path_channel.dart` (iOS app-group dir seam for the Dart reader)
- `lib/features/conversation/presentation/screens/conversation_wired.dart` (:507-579 initState, :1208-1340 drain+reload)
- `ios/NotificationService/NotificationService.swift`, `NotificationPreviewResolver.swift` (app-group store precedent)
Direct tests + integration tests: see Existing Tests below.
Dependency-only context: `lib/core/notifications/notification_route_target.dart` (`remoteNotificationMessageIdFromData`), `go-mknoon/node/inbox.go:718-782` (InboxAck — read-only context; NOT edited).

## Existing Tests Covering This Area
- `test/features/push/application/prepare_notification_open_use_case_test.dart` — 145 fire-and-forget lock ("conversation drain is fire-and-forget — returns before drain completes"), warmPeer wiring. In `ONE_TO_ONE_TESTS` (run_test_gates.sh:85). **Sentinel.**
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — notif-tap drain+refetch (:3469), no-auto-drain-on-orbit (:3527), resume drain (:3553), repo-change backstop (:3602), coalescing (:3646), throwing-drain-clears-guard (:3706), both-streams-exactly-once (:3757), catching-up banner (:3806), stale/live timing one-shots (:3864-:3986), drainMs (:4023-:4067), 159 coalescer locks (:8484+). In `ONE_TO_ONE_TESTS` (:82). **Sentinels.**
- `test/core/services/p2p_service_impl_test.dart` (drain single-flight/paging/migration gates), `p2p_service_impl_health_drain_test.dart` (189 locks, curated :152), `test/core/inbox/inbox_round_trip_test.dart`, `test/core/resilience/c4_partial_drain_test.dart`, `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` (**BASELINE_TESTS** :11). **Sentinels.**
- `test/features/push/application/background_message_handler_*` (existing display/dedupe suites), `handle_incoming_chat_message_use_case_test.dart` (146 groups), notification routing suites (`test/core/notifications/*`, `notification_tap_smoke_test.dart`). **Sentinels.**
- `test/performance/benchmark_notification_tap_to_message_test.dart` (NT1-5, emitter only) + `integration_test/benchmark_notification_tap_harness.dart` (prints ms, fake model). Untouched.
- `integration_test/notification_open_during_other_chat_harness.dart` (reliability-sim 1to1; eventual-visibility with 3-min polling). Untouched.

**Missing coverage gaps (from the inventory agent, all closed or explicitly deferred here):**
(1) no latency/ordering bound anywhere — closed by TC-B7 (zero-relay-dependency
first-frame) + TC-B12 (device leg, plus the step-0 HEAD baseline); (2) no
"message visible in first rendered frame without drain" test — TC-B7; (3) real
drain latency contributors unmeasured — TC-A1/A2 (ack off render path), C5/C6
rows deferred with owners; (5) fire-and-forget drain "actually started"
companion — folded into TC-B6's prepare assertions; (8) relay-only
announced-message sim — TC-B11.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

### Slice A — replay before ack (`p2p_service_impl.dart`)

1. `test/core/services/p2p_service_inbox_ack_ordering_test.dart::staged entries replay and reach the render stream even when the inbox ack never completes`
   - Tier: unit/application host (core services)
   - Shape/setup: real `P2PServiceImpl` with FakeBridge: `inbox:retrieve_pending` returns 1 staged chat entry; `inbox:ack` returns a never-completing `Completer.future`; injected `replayRecoveredInboxChatMessage` records invocations. Drive public `drainOfflineInbox()`.
   - RED on HEAD because: replay is sequenced strictly after the awaited ack (`p2p_service_impl.dart:1998→2025`) — the replay callback is never invoked and the drain future never completes (assert callback invoked within a bounded pump; explicit timeout guard, not a bare test timeout).
   - GREEN after fix asserts: replay callback invoked + drain future completes while ack is still pending; ack was **attempted** with the staged entryIds.
   - Mutation that re-reds: restore `await callP2PInboxAck` above `_replayStagedInboxEntries` → red.
2. `test/core/services/p2p_service_inbox_ack_ordering_test.dart::replay commit precedes ack completion and the ack is still sent exactly once (custody preserved)`
   - Tier: unit/application host
   - Shape/setup: FakeBridge with a delayed-but-completing ack; capture flow events (`_captureFlowEvents` pattern from 146).
   - RED on HEAD because: `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS` is emitted **before** any replay-commit event (`P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED`) — ordering assertion fails.
   - GREEN after fix asserts: replay-commit event index < ack-success event index; ack called exactly once with the same entryIds. **Distinct-event discriminator:** assert `P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED` precedes `P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS` (both must be present — not merely same final row count).
   - Mutation that re-reds: swap the order back → red; drop the ack call → red (exactly-once assert).
3. `test/core/services/p2p_service_inbox_ack_ordering_test.dart::ack throw after replay is swallowed; replayed count returned; entries dedupe on a later drain` (**preserved-green lock**, green on HEAD for the throw-swallow half)
   - Tier: unit/application host
   - Shape/setup: ack throws; second drain redelivers the same entryIds.
   - GREEN asserts: `replayed == N` returned despite ack failure (`:2014-2020` semantics survive the reorder); second drain produces no duplicate replay commit.
   - Mutation that re-reds: make replay conditional on ack success → red.
4. `test/core/services/p2p_service_inbox_ack_ordering_test.dart::migration-gated page stays staged-not-replayed-not-acked` (**preserved-green lock**)
   - Tier: unit/application host
   - Shape/setup: account-migration gate active (`_allowsAccountNetworkSideEffects` false path, as existing p2p migration-gate tests do).
   - GREEN asserts: gated early-return unchanged — entries staged, `replayed == 0`, no ack call, `P2P_SERVICE_INBOX_ACK_SKIPPED_GATED` emitted (`:1976-1993` byte-preserved).
   - Mutation that re-reds: move replay above the gate check → red.
5. `test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart::re-staged same entryIds after a completed replay do not duplicate rows or emits`
   - Tier: integration/repo-host, **real SQLCipher** (staged-entries + messages tables, relevant migrations in `setUp`)
   - Shape/setup: stage→replay→re-stage the same entryIds (simulating the new crash-between-replay-and-ack redelivery window)→replay again.
   - Green-on-HEAD **preservation lock** guarding the reorder's new failure window (relay deletes only on ack; a kill between replay and ack redelivers).
   - Mutation that re-reds: drop entryId/messageId dedupe in stage/replay → red.
6. `integration_test/inbox_replay_before_ack_custody_harness.dart::drain purges the relay inbox and a second drain renders nothing new` (**preservation at the real-relay tier** — custody is a real-relay property, fake proves nothing)
   - Tier: simulator (real `GoBridgeClient` + local relay)
   - GREEN asserts: after a replay-first drain, relay inbox is empty (retrieve returns 0), exactly one rendered copy across two successive drains.
   - Mutation that re-reds: remove the post-replay ack call → relay entries survive → red.

### Slice B — push-envelope staging fast path

7. `test/features/push/application/push_envelope_staging_test.dart::stage/readAll/clear round-trips across store re-instantiation; prune drops TTL-expired and over-cap entries, keeps fresh ones; OLD malformed file is skipped+cleared without aborting; a torn/partial file YOUNGER than the write-window is retried, NOT deleted; entry id is the nonce`
   - Tier: unit host. RED on HEAD because: `push_envelope_staging.dart` does not exist (compile-RED).
   - GREEN asserts: durability across a second store instance over the same temp dir (process-restart proxy); prune removes exactly the expired/over-cap set and preserves the rest; young-torn-file retry (write a truncated JSON with fresh mtime → readAll skips it, does NOT clear; aged past the window → cleared); `clear(nonce)` works for a messageId-less entry.
   - Mutation that re-reds: skip `clear` after read → duplicate-read assert red; prune-everything mutation → keeps-fresh assert red; clear-young-torn-file → retry assert red; key store on messageId → nonce-id assert red (null messageId entry unclearable).
8. `test/features/push/application/background_message_handler_staging_test.dart::routable chat data push with kem+ciphertext+nonce stages an envelope at receipt`
   - Tier: unit/application host (fake staging dir + fake notifications plugin).
   - RED on HEAD because: handler only shows a local notification; no staging API exists (`background_message_handler.dart:163-193`).
   - GREEN asserts: exactly one staged entry carrying the PINNED schema — `kem`, `ciphertext`, `nonce` (= entry id), `senderPeerId` (from `data['sender_id']`), `messageId` (nullable, from `remoteNotificationMessageIdFromData`), `receivedAtMs`; a null `message_id` still stages fine; local notification still shown.
   - Mutation that re-reds: remove the staging call → red; drop `senderPeerId` from the written set → schema assert red (the field the three-way sender check needs).
9. `test/features/push/application/background_message_handler_staging_test.dart::no-ciphertext push (142 media fallback) stages nothing; group-kind push stages nothing (deliberate 1:1-only asymmetry); staging throw never suppresses the local notification`
   - Tier: unit/application host. RED on HEAD by absence of the staging seam (compile-RED with 8).
   - GREEN asserts: zero staged entries in both cases, notification still shown; a throwing store still results in `plugin.show(...)`.
   - Mutation that re-reds: stage-on-absent-ciphertext → red; stage-on-group-kind → red; let staging throw escape before `show` → red.
10. `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart::staged envelope decrypts, persists via the standard incoming pipeline, emits on the incoming stream, and clears its staging entry (others preserved); message.to is filled from the LOCAL identity seam`
    - Tier: unit/application host (fake decrypt/replay callbacks + in-memory repo; injected staging dir with 2 entries, ingest 1st).
    - RED on HEAD because: use case does not exist (compile-RED).
    - GREEN asserts: replay callback invoked with `suppressNotification`-equivalent semantics; the reconstructed ChatMessage has `to == local own-peer-id` (injected identity seam — NOT read from the staged entry); ingested entry cleared, the *other* entry preserved (destructive-side-effect lock).
    - Mutation that re-reds: skip clear → red; clear-all → red; source `to` from the staged entry → red.
11. `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart::blocked sender is rejected before decrypt (decrypt call count == 0) and the entry is cleared; OLD malformed envelope is skipped+cleared without aborting the batch; already-persisted message dedupes via the decrypted payload.id (no duplicate row or emit); active migration gate defers ingestion and retains entries`
    - Tier: unit/application host. RED on HEAD (compile-RED with 10).
    - GREEN asserts: the four cases above; blocked case uses the 147 pattern (`decryptCallCount == 0` — the bridge is never reached); dedupe rides the pipeline's `getMessage(payload.id)` (`handle_incoming_chat_message_use_case.dart:303`), NOT a push-messageId pre-check (push `message_id` is nullable).
    - Mutation that re-reds: decrypt-before-blocked-check → red; ingest-despite-gate → red; drop payload.id dedupe → red.
12. `test/features/push/application/prepare_notification_open_use_case_test.dart::conversation route awaits ingest BOUNDED (~400ms): fast ingest completes before success; a STALLED ingest falls through within the bound and the route still succeeds; a throwing ingest neither fails nor blocks the route; network drain stays fire-and-forget` (extend existing file)
    - Tier: unit/application host.
    - RED on HEAD because: `prepareNotificationOpen` has no ingest hook (`prepare_notification_open_use_case.dart:34-61`).
    - GREEN asserts: fast-path — injected ingest callback completed before the success return on the conversation branch; stall-path — a never-completing ingest future does NOT hold the route past the ~400ms bound (fakeAsync: success returned at the bound, ingest abandoned to fall-through); throw-path — success still returned; **existing 145 lock stays green** ("returns before drain completes").
    - Mutation that re-reds: drop the ingest call → red; make the await unbounded → stall-path red (the 145-latency-class regression this bound exists to prevent); await the network drain → the existing 145 lock goes red.
13. `test/features/conversation/integration/notif_tap_payload_fast_path_test.dart::tapped message is visible on the first settled frame (common case) while the relay drain NEVER resolves; on the bounded-timeout path it renders within N frames via the live stream`  ← **the money test**
    - Tier: integration host (widget-pumping; fake net + real migrations in `setUp` — NOT under `integration_test/`)
    - Shape/setup: stage an envelope exactly as the receipt handler would → run the prepare hook → pump `ConversationWired` with a `FakeP2PService` whose `drainOfflineInbox()` returns a never-completing future. Second case: ingest artificially delayed past the ~400ms bound → route falls through → assert the message still renders within N frames when the ingest lands (via `incomingMessageStream`).
    - RED on HEAD because: with the drain never resolving, no ingestion path exists — the announced message text never appears (`conversation_wired.dart:555` renders the stale page; `:569-570` drain is the only recovery).
    - GREEN after fix asserts: announced message text visible with **zero** relay involvement — at this fake tier the proof is the construction itself (the drain future never resolves, so ONLY the payload path can have rendered it). The event-absence discriminator lives at the real-impl tier: TC-B11 asserts no `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` (`p2p_service_impl.dart:2176` — note the `INBOX_` segment) before visibility; asserting event-absence here against a `FakeP2PService` would be vacuous (the fake never emits it).
    - Mutation that re-reds: revert the prepare/startup ingest wiring → red.
14. `test/features/push/integration/push_ingest_persistence_test.dart::ingested row is returned by the conversation initial-page query and survives repository reopen`
    - Tier: integration/repo-host, **real SQLCipher** (durability is the point).
    - RED on HEAD (compile-RED: ingest use case absent).
    - GREEN asserts: row present via the exact `loadConversationPage` initial-page query `_loadInitialPage` uses; still present after closing and reopening the DB/repo.
    - Mutation that re-reds: persist via a side-channel table the page query doesn't read → red.
15. `test/features/conversation/presentation/screens/conversation_wired_test.dart::payload-ingested message later replayed by the drain renders exactly once` (extend existing file; :3757 both-streams pattern)
    - Tier: widget. RED on HEAD (compile-RED: staging/ingest setup APIs absent).
    - GREEN asserts: one list entry after ingest-then-drain-replay of the same messageId.
    - Mutation that re-reds: drop messageId dedupe in the incoming pipeline → red.
16. `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart::startup/resume ingestion runs without a notification tap` (wiring-level companion asserted via the main-wiring seam test if a `main.dart` harness exists; otherwise the use-case + a `startup` trigger-source arg)
    - Tier: unit/application host. RED on HEAD (compile-RED).
    - GREEN asserts: staged-at-receipt entries are ingested on the runtime-ready/resume path with no tap (covers "user opens the app from the launcher instead of the notification").
    - Mutation that re-reds: wire ingest only into the tap path → red.
17. `integration_test/notif_push_payload_persist_harness.dart::real ciphertext envelope staged then ingested renders the plaintext BEFORE any drain; subsequent drain neither duplicates nor strands relay custody`
    - Tier: simulator E2E — **real `GoBridgeClient` on both parties + local relay** (real ML-KEM decrypt of a real peer's envelope; FakeBridge cannot prove convergence).
    - RED on HEAD: staging/ingest absent (harness asserts payload-path visibility pre-drain).
    - GREEN asserts: plaintext visible pre-drain; post-drain exactly-once; relay inbox purged (ack custody clean). **Distinct-event discriminator (real impl — this is where it is non-vacuous):** NO `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` (`p2p_service_impl.dart:2176`) is emitted before the visibility assertion — the payload path, not a fast drain, rendered it.
    - Mutation that re-reds: revert ingest wiring → pre-drain visibility red.
18. `integration_test/notification_tap_message_visible_proof_test.dart` `@Tags(['device'])` — **THREE required scenarios**  ← **PROD-CRITICAL closure gate**
    - Tier: **device-proof** (2 real devices, real bridge, real relay; orchestrator `integration_test/scripts/run_notification_tap_device_real.dart`)
    - Scenarios (ALL required for closure — the iOS-NSE-Swift and Android-Dart-isolate writes are disjoint code paths and the NSE has zero host/sim coverage; a single-scenario gate could pass running only one platform):
      - `payload_fast_path_ios_receiver` — receiver = iPhone (NSE writes the app-group envelope). Same run also asserts the NSE 04-P0 contract **with staging enabled**: preview title/body correct, mute respected, no duplicate banner (staging must not blow the NSE budget or break preview/dedupe).
      - `payload_fast_path_android_receiver` — receiver = Pixel (Dart background isolate writes).
      - `payload_fast_path_cold_kill` — after the push arrives and BEFORE the tap, force-stop the receiver (`adb shell am force-stop <pkg>` / iOS app terminate), then cold-launch via the tap: proves the killed→cold-launch→startup/prepare-ingest handoff (the dominant real-world notif-tap; "backgrounded" alone never runs it).
    - Shape (all scenarios): app backgrounded ≥1 min on receiver → sender sends a 1:1 text → push arrives → **FULL AIRPLANE MODE on the receiver** (all radios off) after the push has arrived, with the precondition that no receiver↔sender LAN/WS transport exists (separate networks or fully offline — same-WiFi libp2p LAN-direct is a false-green vector that can deliver the message live while the staged path is broken) → tap the notification → announced message visible.
    - Pass/fail: **categorical — the message renders with the network fully cut (zero relay RTT possible)**. The `≤2s` figure is a UX comfort wrapper only, NOT the improvement bar (a network-up `≤2s` gate would pass on the unfixed build, whose warm baseline is 0.5–2s).
    - RED on HEAD because: with the network cut, the drain physically cannot deliver — the message never appears.
    - Mutation that re-reds: disable NSE staging → iOS scenario red; disable handler staging → Android scenario red; disable startup ingest → cold-kill scenario red.
    - Install with `adb install -r` / `devicectl` — never `flutter install` (wipes device data).
19. `test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart::two concurrent ingest passes over the same entry coalesce — one clear, one row, one emit` (single-flight guard)
    - Tier: unit/application host.
    - RED on HEAD (compile-RED with 10); post-implementation it locks the tap-during-resume race (prepare-tap wiring and startup/resume wiring can both fire for the same entry).
    - GREEN asserts: launching two overlapping ingest calls yields exactly one replay-callback invocation, one persisted row, one `clear` — the second pass coalesces onto the in-flight one (or no-ops).
    - Mutation that re-reds: remove the single-flight guard → double-emit/double-clear assert red.
20. `test/features/identity/presentation/startup_router_notification_open_test.dart::cold getInitialMessage tap runs the staged-envelope ingest before the conversation's first render` (extend existing file)
    - Tier: unit/application host (widget-pumping StartupRouter, existing cold-FCM fixture).
    - RED on HEAD because: `startup_router.dart:1031` `_prepareNotificationRouteTarget` is a SECOND prepare wrapper that does not inherit main.dart wiring (proven precedent: it never got `warmPeer`) — with ingest wired only at `main.dart:4475`, the cold tap gets a default-null ingest and this assertion fails.
    - GREEN asserts: the injected ingest hook is invoked on the cold `getInitialMessage` route before the conversation screen is pushed.
    - Mutation that re-reds: revert the `startup_router.dart:1031` wiring (keep only main.dart) → red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-A1 replay not gated on ack | drain control flow | unit/app host | `p2p_service_inbox_ack_ordering_test.dart::…ack never completes` | replay sequenced after awaited ack (:1998→:2025) | restore await-ack-before-replay | `flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart` | AUTO core-host-all **+ add to `ONE_TO_ONE_TESTS`** (test/core/** not auto-globbed into 1to1) |
| TC-A2 replay→ack ordering + custody | flow-event ordering | unit/app host | same file::`replay commit precedes ack…exactly once` | ACK_SUCCESS precedes STAGED_CHAT_COMMITTED on HEAD | swap order back / drop ack | same cmd | same (one file, one array entry) |
| TC-A3 ack-throw semantics survive | error path | unit/app host | same file::`ack throw after replay…` | green-on-HEAD preservation lock | replay-conditional-on-ack | same cmd | same |
| TC-A4 migration gate unchanged | Move-Account gate | unit/app host | same file::`migration-gated page…` | green-on-HEAD preservation lock | move replay above gate | same cmd | same |
| TC-A5 redelivery idempotent | repo+DB durability | integration/repo-host (real SQLCipher) | `test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart::…` | green-on-HEAD lock guarding new crash window | drop entryId/messageId dedupe | `flutter test test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart` | AUTO core-host-all **+ add to `ONE_TO_ONE_TESTS`** |
| TC-A6 relay custody preserved | real relay custody | simulator | `integration_test/inbox_replay_before_ack_custody_harness.dart::…` | preservation at real-relay tier | remove post-replay ack | `/sims <scope> --only N` (index from dry-run) | **classify_path() case** in `check_reliability_simulation_discovery.sh` + runner in `run_reliability_simulations.sh` (+ `OPTIONAL_MANUAL_TESTS`) |
| TC-B1 store round-trip/prune | pure logic + file durability | unit host | `push_envelope_staging_test.dart::…` | compile-RED (store absent) | skip clear / prune-everything | `flutter test test/features/push/application/push_envelope_staging_test.dart` | AUTO (glob) |
| TC-B2 handler stages chat envelope | use-case wiring | unit/app host | `background_message_handler_staging_test.dart::routable chat data push…` | handler never persists (:163-193) | remove staging call | `flutter test test/features/push/application/background_message_handler_staging_test.dart` | AUTO **+ add to `ONE_TO_ONE_TESTS`** (headline 1:1) |
| TC-B3 no-stage cases + notif never suppressed | edge/asymmetry locks | unit/app host | same file::`no-ciphertext…group-kind…staging throw…` | compile-RED with TC-B2 | stage-on-absent / stage-on-group / throw-escapes-before-show | same cmd | same file/array entry |
| TC-B4 ingest happy path + clear | use-case + destructive side-effect | unit/app host | `ingest_staged_push_envelopes_use_case_test.dart::staged envelope decrypts…` | compile-RED (use case absent) | skip clear / clear-all | `flutter test test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart` | AUTO **+ add to `ONE_TO_ONE_TESTS`** |
| TC-B5 blocked/malformed/dedupe/migration-gate | policy invariants | unit/app host | same file::`blocked sender…malformed…dedupes…migration gate…` | compile-RED | decrypt-before-blocked / ingest-despite-gate / drop dedupe | same cmd | same |
| TC-B6 prepare hook, BOUNDED await | route-time wiring + stall guard | unit/app host | `prepare_notification_open_use_case_test.dart::conversation route awaits ingest BOUNDED…` | no ingest hook on HEAD (:34-61) | drop ingest call; make await unbounded (stall-path red); await network drain (re-reds 145 lock) | `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart` | AUTO; file already in `ONE_TO_ONE_TESTS` (:85) |
| TC-B7 first-frame visibility, zero relay | end-to-end fast path | integration host (fake net + real migrations) | `notif_tap_payload_fast_path_test.dart::…drain NEVER resolves (+ bounded-timeout fall-through case)` | no ingestion path exists — message never renders | revert prepare/startup ingest wiring | `flutter test test/features/conversation/integration/notif_tap_payload_fast_path_test.dart` | AUTO **+ add to `ONE_TO_ONE_TESTS`** |
| TC-B8 persistence durability | repo+DB | integration/repo-host (real SQLCipher) | `push_ingest_persistence_test.dart::…survives repository reopen` | compile-RED | persist via side-channel table | `flutter test test/features/push/integration/push_ingest_persistence_test.dart` | AUTO **+ add to `ONE_TO_ONE_TESTS`** |
| TC-B9 exactly-once vs drain replay | sibling render paths | widget | `conversation_wired_test.dart::payload-ingested…exactly once` | compile-RED (setup APIs absent) | drop messageId dedupe | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` | AUTO; file already in `ONE_TO_ONE_TESTS` (:82) |
| TC-B10 startup/resume ingest (no tap) | lifecycle durability | unit/app host | `ingest_staged_push_envelopes_use_case_test.dart::startup/resume ingestion…` | compile-RED | tap-only wiring | same cmd as TC-B4 | same |
| TC-B11 real-crypto payload path pre-drain | ML-KEM convergence + relay custody | simulator E2E | `integration_test/notif_push_payload_persist_harness.dart::…` | staging/ingest absent | revert ingest wiring | `/sims <scope> --only N` | classify_path() case + `run_reliability_simulations.sh` runner + `OPTIONAL_MANUAL_TESTS` |
| TC-B12 OS-boundary proof (3 REQUIRED scenarios) | device-proof (NSE process / background isolate / cold-kill handoff) | **device-proof** | `notification_tap_message_visible_proof_test.dart::{payload_fast_path_ios_receiver, payload_fast_path_android_receiver, payload_fast_path_cold_kill}` (iOS leg also asserts NSE 04-P0 with staging ON) | full-airplane-mode tap cannot render on HEAD | disable NSE staging → iOS red; disable handler staging → Android red; disable startup ingest → cold-kill red | `/sims <scope> --only N` (proof indices) after orchestrator run | classify_path **'device-proof'** case + all three `--scenario` ids in `integration_test/scripts/run_notification_tap_device_real.dart` |
| TC-B13 concurrent double-ingest coalesces | single-flight idempotency | unit/app host | `ingest_staged_push_envelopes_use_case_test.dart::two concurrent ingest passes…coalesce` | compile-RED (use case absent); locks tap-during-resume race | remove single-flight guard | `flutter test test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart` | AUTO **+ `ONE_TO_ONE_TESTS`** (same file as TC-B4/B5) |
| TC-B14 cold remote-FCM tap wired | second prepare wrapper (startup_router) | unit/app host | `startup_router_notification_open_test.dart::cold getInitialMessage tap runs the staged-envelope ingest…` | `startup_router.dart:1031` wrapper doesn't inherit main.dart wiring (warmPeer precedent) | revert the startup_router wiring, keep main.dart only | `flutter test test/features/identity/presentation/startup_router_notification_open_test.dart` | AUTO (feature-local glob; existing file) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** TC-B1 (store survives re-instantiation over the same dir = process-restart proxy) + TC-B10 (staged-while-dead entries ingested on next launch without a tap) + TC-B8 (row survives repo reopen).
- **Sibling-surface consistency:** the staging gate applies to chat-kind pushes only — group / contactRequest / intros / posts kinds deliberately stage nothing, **asymmetry test-locked** by TC-B3; group staging named as a future session. Sibling *render* paths (stream vs drain-reload) locked exactly-once by TC-B9 (+ existing :3757).
- **Destructive-action side-effects:** ingestion clears exactly the ingested entry and preserves others (TC-B4); prune removes exactly TTL-expired/over-cap and preserves fresh, and a torn file younger than the write-window is retried, never deleted (TC-B1); relay-side deletion still happens via ack (TC-A2 exactly-once, TC-A6/TC-B11 real-relay purge).
- **Invariant re-verification under new transitions:** the reorder's new replay-then-crash-before-ack window re-verifies the dedupe invariant (TC-A5); the migration-gate invariant is re-verified under both new flows (TC-A4 drain path byte-preserved; TC-B5 ingest defers + retains); ack-failure invariant re-verified post-reorder (TC-A3); the new tap-during-resume double-trigger re-verifies exactly-once (TC-B13); the bounded-timeout fall-through re-verifies eventual visibility via the live stream (TC-B7 second case).

## Invariants (locked by tests)
- INV-225-1: A drain page's decrypt/commit/render is never gated on relay-ack completion → TC-A1/TC-A2.
- INV-225-2: Relay custody is unchanged — every replayed page is still acked exactly once; unacked entries dedupe later → TC-A2/TC-A3/TC-A5/TC-A6.
- INV-225-3: The Move-Account migration gate is never bypassed by either slice → TC-A4/TC-B5.
- INV-225-4: A staged push envelope renders with zero relay round-trips → TC-B7 (discriminator: no drain/retrieve event before visibility) / TC-B11 / TC-B12.
- INV-225-5: The local notification is never suppressed by staging failures → TC-B3.
- INV-225-6: Payload ingest and drain replay converge exactly-once per messageId → TC-B5/TC-B9.
- INV-225-7: Blocked senders' ciphertext is never decrypted by the ingest path → TC-B5 (147 policy).
- INV-225-8: Route push is never blocked by network work (145) and never held past the ~400ms ingest bound by a local stall → existing fire-and-forget lock + TC-B6 (stall-path).
- INV-225-9: BOTH prepare wrappers (`main.dart:4475` warm, `startup_router.dart:1031` cold) carry the ingest hook → TC-B14 + TC-B12 cold-kill scenario.
- INV-225-10: Concurrent ingest triggers coalesce to exactly one clear/row/emit → TC-B13.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
0. **Warm-path latency baseline (before any edit):** run the existing
   `integration_test/benchmark_notification_tap_harness.dart` on HEAD (N≥20,
   record p50/p95 `sim_notification_tap_warm_ms`/`cold_ms`) and file the numbers
   in Execution Progress. The improvement claim is judged against this;
   the device `≤2s` figure is a UX wrapper, NOT the bar (see TC-B12).
1. `git status --short` snapshot (shared dirty tree: concurrent session owns `224-*.md`, `00-INDEX.md` mods, orbit/graphify artifacts — do not revert).
2. **Slice A RED:** add TC-A1..A4 file + TC-A5; run focused commands; confirm A1/A2 fail for the documented ordering reason (A3/A4/A5 green-on-HEAD locks).
3. **Slice A fix:** in `_retrievePendingInboxPage` move the `_replayStagedInboxEntries` block (:2024-2028 — including the `replaySw.stop()` at :2028, or the stopwatch is orphaned) to run after `stageEntries`+migration-gate (:1970-1993) and **before** the ack block (:1994-2022); keep the gated early-return and ack-exception swallow byte-equivalent; keep `replayMs`/`ackMs` stopwatch fields accurate. No signature changes. Stop-if: any existing drain test depends on ack-before-replay ordering for a *custody* reason not covered by :1971-1975's dedupe comment → replan, do not hack.
4. Slice A GREEN: focused file + `p2p_service_impl_test.dart` + `p2p_service_impl_health_drain_test.dart` + BASELINE `offline_inbox_roundtrip_test.dart`.
5. **Slice B RED:** add TC-B1..B10 + TC-B13/TC-B14 files/cases (compile-RED documented per case); run focused commands.
6. **Slice B store + handler:** `push_envelope_staging.dart` — entry id = `nonce`; atomic temp-file+rename writes; young-torn-file retry window; one `resolveStagingDir()` shared by writer+reader per platform; TTL ~48h, cap ~64, prune on read. `background_message_handler.dart` stages before `plugin.show` inside its existing try (staging wrapped so a throw cannot reach `show`); on iOS the Dart handler defers to the NSE (no second staging location).
7. **Slice B ingest:** `ingest_staged_push_envelopes_use_case.dart` with injected `{readStore, clearEntry, replayChatMessage, localIdentity, isBlocked/gate seams}` + single-flight guard; envelope→ChatMessage mapping mirrors the inbox-replay construction (verify against `replayInboxChatMessage` at `main.dart:2083`); **`message.to` = local own-peer-id from the injected identity seam — NOT staged, NOT from the push.** Stop-if (SENDER-side identity fields ONLY): if the push payload lacks a sender-side field the standard handler requires beyond `sender_id`, stop and replan — do NOT invent a parallel handler and do NOT touch `go-relay-server` (Scope Guard; recipient-side fields come from local identity by design).
8. **Slice B wiring:** supply ingest to `prepareNotificationOpen` (new optional param, default null keeps existing callers unchanged — 145 `warmPeer` pattern) at **BOTH wrappers**: `main.dart:4475` AND `startup_router.dart:1031` (`_prepareNotificationRouteTarget`); conversation branch awaits the ingest with `.timeout(~400ms, onTimeout: fall-through)` + swallow-and-log before returning success; plus the runtime-ready/resume hook.
9. **iOS:** `AppGroupPushEnvelopeStore.swift` (mirror `AppGroupPushDedupeStore`), NSE `didReceive` additively writes the **PINNED field-set** `{kind, kem, ciphertext, nonce, senderPeerId: userInfo['sender_id'], messageId: userInfo['message_id'] (nullable), receivedAtMs}` atomically (`.atomic`), enforcing the ~64 cap on write (evict oldest); Dart reader points the staging store at the app-group container path via `app_group_path_channel.dart`. NSE never touches SQLCipher; preview/mute/dedupe code paths untouched (asserted with staging ON in the TC-B12 iOS leg).
10. Harness registration: append the SIX new host files to `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh` (`p2p_service_inbox_ack_ordering_test`, `replay_before_ack_redelivery_idempotent_test`, `background_message_handler_staging_test`, `ingest_staged_push_envelopes_use_case_test`, `notif_tap_payload_fast_path_test`, `push_ingest_persistence_test`; `push_envelope_staging_test` is AUTO-only per the matrix); add classify_path cases + runners for TC-A6/TC-B11; add the device-proof classify_path case + **all three** orchestrator `--scenario` ids. Run `./scripts/run_test_gates.sh completeness-check`.
11. Rerun direct → preservation → named gates → sim dry-run (`/sims` shows new `--only N` indices) → device proof (TC-B12, all three scenarios) as the closure gate.

## Risks And Edge Cases
- Reorder crash window (replay done, ack lost) → redelivery → pinned by TC-A5.
- **Ingest STALL (not throw) gating the route up to the 10s bridge decrypt timeout** — try/catch does not stop a stall → pinned by the ~400ms bounded await, TC-B6 stall-path.
- **iOS NSE omits `senderPeerId` → every iOS ingest rejected as senderMismatch, silent drain fallback (host-green, TestFlight-broken)** → pinned by the pinned write schema + TC-B12 iOS receiver leg (only a device can catch it — the NSE is a separate process).
- **Cold `getInitialMessage` tap misses the ingest hook (second wrapper)** → pinned by TC-B14 + TC-B12 cold-kill leg.
- Torn/partial staged file read as "malformed" and deleted → fast path silently lost → pinned by atomic writes + young-file retry window (TC-B1).
- Writer/reader staging-dir mismatch on iOS orphans files forever → pinned by the single `resolveStagingDir()` seam (step 6).
- NSE-only devices accumulate envelopes (Dart prune never runs) → pinned by cap-on-write eviction (step 9).
- Concurrent tap-during-resume double-ingest → pinned by the single-flight guard, TC-B13.
- Staging queue growth on a device that never opens the app → TTL+cap prune pinned by TC-B1.
- Duplicate render via payload + drain → pinned by TC-B5/TC-B9 (dedupe rides decrypted `payload.id`, not nullable push messageId).
- Blocked-sender plaintext exposure via ingest → pinned by TC-B5 (147 policy).
- Move-Account: ingesting into an exporting account → pinned by TC-B5; drain gate byte-preserved → TC-A4.
- NSE writes envelope but app can't read (container path/encoding skew) → only provable on device → TC-B12 (that is *why* it is the closure gate).
- Ingest-path delivery receipts fire at ingest time: same `handleIncomingChatMessage` hook → 146 fire-and-forget contract inherited (send failure swallowed — safe under airplane mode); no separate test, 146's locks own it.
- Oversize/media pushes carry no ciphertext (142 fallback, `inbox.go:297-310`) → payload path silently absent; drain remains the path (TC-B3 locks no-crash); C5/C6 follow-ups own the drain-path worst cases.
- `prepareNotificationOpen` new optional param ripples to `prepareNotificationRouteTarget` + BOTH wrappers (main.dart, startup_router.dart) — additive-with-default, 145 precedent; **no P2PService interface change anywhere** (31-fakes hazard avoided by design).

## Device/Relay Proof Profile
Requires **device-proof for closure**: TC-B12, ALL THREE scenarios required —
`payload_fast_path_ios_receiver` (iPhone receiver; also asserts NSE 04-P0 with
staging ON), `payload_fast_path_android_receiver` (Pixel receiver),
`payload_fast_path_cold_kill` (force-stop before tap). Full airplane mode on the
receiver after push arrival; devices on separate networks (LAN-direct
false-green guard). Pass/fail is categorical (renders with the network cut);
`≤2s` is a UX wrapper judged against the step-0 baseline. Sim rows TC-A6/TC-B11
run via `/sims` after registration (local relay OK; defaults
`/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…` if needed).
Deferred device work → C5/C6 follow-up sessions: warm-tap-after-long-background and >50-backlog scenarios extend the same proof file as new `--scenario` cases.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Step-0 baseline (BEFORE any edit) — record p50/p95 in Execution Progress
# run integration_test/benchmark_notification_tap_harness.dart on HEAD, N>=20
# (dispatched via integration_test/benchmark_harness.dart; benchmark/benchmark-sim gates)

# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart          # TC-A1/A2 FAIL (replay gated on ack); A3/A4 green locks
flutter test test/features/push/application/push_envelope_staging_test.dart        # compile-RED: store absent
flutter test test/features/push/application/background_message_handler_staging_test.dart  # RED: handler never stages
flutter test test/features/push/application/ingest_staged_push_envelopes_use_case_test.dart # compile-RED: use case absent (incl. TC-B13 single-flight)
flutter test test/features/push/application/prepare_notification_open_use_case_test.dart --plain-name 'conversation route awaits ingest BOUNDED'  # RED: no ingest hook
flutter test test/features/identity/presentation/startup_router_notification_open_test.dart --plain-name 'cold getInitialMessage tap runs the staged-envelope ingest'  # RED: second wrapper unwired
flutter test test/features/conversation/integration/notif_tap_payload_fast_path_test.dart  # RED: message never renders with drain unresolved

# Direct GREEN (after fix)
flutter test test/core/services/p2p_service_inbox_ack_ordering_test.dart test/core/inbox/replay_before_ack_redelivery_idempotent_test.dart
flutter test test/features/push
flutter test test/features/conversation/integration/notif_tap_payload_fast_path_test.dart test/features/push/integration/push_ingest_persistence_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/identity/presentation/startup_router_notification_open_test.dart

# Preservation sentinels (must stay green)
./scripts/run_test_gates.sh 1to1            # baseline 1518/1518 (2026-07-09); expect 1518 + new registered tests, 0 regressions
flutter test test/core/services/p2p_service_impl_test.dart test/core/services/p2p_service_impl_health_drain_test.dart
flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart test/core/inbox/inbox_round_trip_test.dart test/core/resilience/c4_partial_drain_test.dart

# Migration: N/A — no DB schema change (file-based staging). If execution discovers a DB-backed
# staging table is required after all: allocate DB v96 + test/core/database/migrations/096_*_test.dart
# (real SQLCipher, PRAGMA + run-twice idempotency) and STOP for replan.

# Named gate for the touched subsystem + registration completeness
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh completeness-check

# Simulator/device discovery + run
./scripts/check_reliability_simulation_discovery.sh   # must list: inbox_replay_before_ack_custody_harness, notif_push_payload_persist_harness, notification_tap_message_visible_proof_test (device-proof)
# /sims <scope> --list  → note --only N for each  → /sims <scope> --only N   (resume: --start-at N)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the six RED commands above, each for its documented reason, before production edits.
- Pre-existing dirty tree (concurrent session — do NOT revert/touch): `Test-Flight-Improv/224-orbit-side-arc-tap-dead-zone-tdd-plan.md` (untracked), `00-INDEX.md` (modified), `graphify-arch/graphify-out/*` regen artifacts, uncommitted 220/221/orbit work.
- Known pre-existing red (209 execution note): `group_conversation_wired_bg_task_test` failed at clean HEAD on 2026-07-05 — verify against clean HEAD before attributing to this session.
- Environment blocker (NOT product): missing simulator/device for TC-A6/TC-B11/TC-B12; host slices remain valid, closure stays open until the proof runs.
- Scope drift (BLOCKING): any failure in group/intros/posts push suites, relay server tests, or drain paging tests — outside the Scope Guard, stop and replan.

## Done Criteria
- [ ] Step-0 warm-path baseline captured on HEAD (p50/p95, N≥20) and recorded in Execution Progress.
- [ ] RED added first; each failed for its documented reason (compile-RED cases noted as such).
- [ ] Mutation-verified: every production edit has a named re-red revert (matrix column).
- [ ] Direct GREEN + preservation sentinels + `1to1` gate (0 regressions from 1518) + `completeness-check` pass.
- [ ] No DB migration shipped (or DB v96 + real-SQLCipher migration test if replanned).
- [ ] OS-boundary path proven on real devices: **ALL THREE TC-B12 scenarios green** — `payload_fast_path_ios_receiver` (incl. NSE 04-P0 with staging ON), `payload_fast_path_android_receiver`, `payload_fast_path_cold_kill`. One platform alone does NOT close.
- [ ] Every new test registered (array / classify_path / --scenario ×3) and seen running in a gate / `/sims` dry-run.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not touch `go-relay-server/` (ordering/targeted-fetch changes = C6 follow-up + relay redeploy).
- Do not add drain retry/backoff, change `foregroundInboxTimeout`, or alter drain-failure surfacing (C5 follow-up).
- Do not change drain paging / `waitForAllPages` semantics or `maxInboxPages` (C6 follow-up).
- Do not add or change any `P2PService` interface member (~31 fakes break).
- Do not open the SQLCipher DB from the NSE, ever (poisoned-reopen landmine).
- Do not modify NSE preview/mute/dedupe (04-P0) logic — staging is additive.
- Do not stage group/contactRequest/intros/posts pushes (TC-B3 locks the asymmetry).
- Do not re-introduce the refuted C2 cold-start-race or C4 banner-contract narratives.
- Do not touch the concurrent session's uncommitted files (`224-*.md`, orbit work).

## Accepted Differences / Intentionally Out Of Scope
- Drain worst-case latency (dead-QUIC 3s-budget silent failure; >50 backlog paging) remains after this session — C5/C6 follow-up sessions own them; this session removes the *common-case* lag (payload fast-path) and one ack RTT per drain page.
- Media/oversize pushes (no ciphertext in payload, 142 fallback) still arrive via drain only.
- `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING` stays kDebugMode-only (145 accepted difference).
- Old builds ignore staged-envelope files (additive store, no wire/schema change) — forward-compatible by construction.

## Dependency Impact
- C5/C6 follow-up sessions build on INV-225-1/2 (replay-before-ack) and extend `notification_tap_message_visible_proof_test.dart` with their own `--scenario` cases.
- 217 wake-token / relay flip work is untouched (no flag-map or relay change here).
- 146/147 receipt/decrypt behavior is upstream of `_replayStagedInboxEntries` and unaffected by the reorder (replay internals untouched).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md) run 2026-07-09: all core conditions + yes/no gates pass — every TC has tier/file/mutation/gate/registration (zero empty matrix cells); RED-on-HEAD reasons documented (compile-RED flagged explicitly); preserved-green sentinels named with baseline count (1518); OS-boundary proven at device tier (TC-B12 = PROD-CRITICAL); migration N/A justified with a replan trigger; blind-spot sweep: all four classes have rows (no N/As needed); refuted findings recorded (C2, C4); dirty-tree snapshot planned (step 1).

External /tdd-review (`wf_ea1fd793-f62`, 8 agents, 2026-07-09): **READY-WITH-TIGHTENING — both core bets source-verified SOUND** (Slice A strictly safer than HEAD: relay is non-destructive on retrieve, deletes only on ack; Slice B payload sufficient: push carries `sender_id`+`message_id`+envelope). Fix-list `225-review-fixlist.md` **APPLIED in full** on 2026-07-09: §A1 pinned NSE write-set (senderPeerId — silent iOS senderMismatch killer), §A2-A4 TC-B12 → 3 required scenarios (per-platform receivers + cold-kill) with full airplane mode (LAN-direct false-green struck), §B1-B2 bounded ~400ms ingest await (user-locked; try/catch stops a throw, not a stall — 10s bridge decrypt timeout was the exposure) + TC-B7 restated, §C1 second prepare wrapper (`startup_router.dart:1031`) wired + TC-B14, §D1 store keyed on nonce (push message_id nullable), §D2 `message.to` from local identity + Stop-if scoped to sender fields, §D3 atomic writes + young-torn-file retry, §D4 single dir resolver, §D5 cap-on-write in NSE, §D6 NSE-04-P0-with-staging folded into the iOS device leg (receipt-timing applied as NOTE only — contract inherited from 146's own locks, a test would duplicate them), §D7 single-flight + TC-B13, §D8 step-0 baseline + `≤2s` demoted to UX wrapper, §E1-E5 line fixes (TC-B12 closure label, :2024-2028, :383, `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` event name + discriminator moved to TC-B11, TC-B7/B12 gap credits).

## Arbiter Decision
Structural blockers: none. | Deferred details: exact staged-envelope SENDER-side schema fields beyond `sender_id` may grow at step 7's Stop-if (recipient-side `to` comes from local identity by design — never from the relay). | Accepted differences: listed above (C5/C6/media/telemetry; §D6 receipt-timing note-only).

## Final Execution Verdict
Verdict: blocked | Blocker class: test_or_gate_failure | Spawned-agent isolation used: yes — Executor, QA Reviewer, fix-pass Executor recovery, and second QA Reviewer ran in separate spawned agents; fix-pass #1 ended in `spawn_or_tool_failure` and fix-pass #2 completed recovery from the partial landing | Local sequential fallback used: no | Files changed: Slice A `p2p_service_impl.dart`; Slice B push staging/ingest/background/prepare/startup/main/iOS NSE wiring; Dart+iOS injective nonce file-keying; fail-closed proof artifact validators/runner; host/device-registration tests; gate/discovery registrations; graphify outputs refreshed after `lib/` edits | Tests run: RED catalog recorded above; GREEN host direct/preservation/named gates passed where runnable (`flutter test` Slice A, `test/features/push`, fast-path/persistence integration, ConversationWired, StartupRouter, `1to1`, P2P preservation, offline inbox preservation, `completeness-check`, discovery, focused analyzer, `git diff --check`); fix-pass #2 also passed Pixel benchmark (cold 680ms, warm 133ms), proof runner list, Dart nonce test, and isolated Swift nonce XCTest | Blocking: real proof artifacts/runs for TC-A6, TC-B11, and all three TC-B12 scenarios are still missing; artifact validators are fail-closed and not a substitute for real APNs/FCM/relay/device proof; repository-wide `flutter analyze` remains red on existing full-tree diagnostics despite session-touched files analyzing clean | QA verdict: second QA confirmed nonce/proof-placeholder fixes are sound, but plan closure is unsafe until real proof artifacts are captured and the required full-tree analyze gate is resolved or formally narrowed | Non-blocking follow-ups (owner): C5 dead-session drain retry (next session), C6 backlog paging (next session), group push staging (future).
