# MIG-009 Plan: Migrated-Out Runtime Network Gates

Status: closed (MIG-009 only; overall Move Account still open; MIG-010 through MIG-012 plus deferred-last MIG-006 remain open)

## Planning Progress

- 2026-06-07 20:08 CEST - Arbiter completed. Files inspected since last update: final validation script, gate/prohibition scan, progress count, reviewer-pass plan. Decision/blocker: execution-ready for MIG-009 only; no structural blockers; device/simulator evidence remains narrow and evidence-gated without MIG-006 group release evidence. Next action: hand this plan to the MIG-009 executor when requested.
- 2026-06-07 20:06 CEST - Arbiter started. Files inspected since last update: reviewer-pass plan and constraint-scan evidence. Decision/blocker: arbitration focuses on structural readiness, override compliance, and whether any missing evidence should block planning. Next action: final validation and status decision.
- 2026-06-07 20:05 CEST - Reviewer completed. Files inspected since last update: mandatory section scan, prohibited-command scan, listener discovery, final draft. Decision/blocker: reviewer pass after adding explicit main-started listener inspection/testing expectations; no structural blocker found. Next action: Arbiter decides whether the plan is execution-ready.
- 2026-06-07 20:02 CEST - Reviewer started. Files inspected since last update: completed planning draft, mandatory section list, gate/prohibition scan. Decision/blocker: no prohibited group simulator command appears in the executable gate list; host group gate remains scoped to direct group runtime changes. Next action: review for coverage gaps, dependency leaks, and closure overclaim.
- 2026-06-07 20:01 CEST - Planner completed. Files inspected since last update: planning draft sections, direct test list, gate list, scope guard, known-failure interpretation. Decision/blocker: draft is implementation-ready with a narrow non-group simulator evidence path and explicit MIG-006 exclusion. Next action: Reviewer checks whether runtime entry points and user hard constraints are all represented.

## Execution Progress

- 2026-06-07 20:09 CEST - Controller started MIG-009 execution from this reusable execution-ready plan. Pre-execution dirty worktree snapshot recorded for scope comparison; many modified/untracked files are inherited from earlier MIG sessions and must not be reverted unless the executor owns the delta:

```text
 M Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md
 M Test-Flight-Improv/codebase-test-inventory.md
 M Test-Flight-Improv/test-gate-definitions.md
 M android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt
 M go-mknoon/bin/testpeer
 M go-mknoon/bridge/bridge.go
 M go-mknoon/bridge/bridge_test.go
 M go-mknoon/node/inbox.go
 M go-mknoon/testdata/interop_vectors.json
 M go-relay-server/backend_redis_test.go
 M go-relay-server/inbox_test.go
 M info.plist
 M integration_test/group_multi_device_real_harness.dart
 M integration_test/group_multi_party_device_real_harness.dart
 M integration_test/group_recovery_e2e_test.dart
 M integration_test/scripts/group_multi_party_device_criteria.dart
 M ios/Runner/GoBridge.swift
 M lib/core/bridge/go_bridge_client.dart
 M lib/core/bridge/p2p_bridge_client.dart
 M lib/core/local_discovery/local_ws_server.dart
 M lib/features/groups/application/send_group_message_use_case.dart
 M lib/features/identity/application/startup_decision.dart
 M lib/features/identity/presentation/startup_router.dart
 M lib/features/push/infrastructure/push_token_store_impl.dart
 M lib/features/qr_code/application/handle_scanned_qr_use_case.dart
 M lib/features/qr_code/presentation/screens/qr_scanner_wired.dart
 M lib/main.dart
 M macos/Runner/MainFlutterWindow.swift
 M scripts/check_reliability_simulation_discovery.sh
 M scripts/run_test_gates.sh
 M test/core/bridge/go_bridge_client_test.dart
 M test/core/bridge/p2p_bridge_client_test.dart
 M test/core/local_discovery/local_ws_server_test.dart
 M test/features/groups/application/send_group_message_use_case_test.dart
 M test/features/identity/application/startup_decision_test.dart
 M test/features/identity/presentation/screens/startup_router_recovery_test.dart
 M test/features/qr_code/application/handle_scanned_qr_use_case_test.dart
 M test/features/qr_code/presentation/screens/qr_scanner_wired_test.dart
 M test/integration/group_multi_party_device_criteria_test.dart
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-001-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-002-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-003-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-004-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-005-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-006-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-007-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-009-plan.md
?? Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md
?? integration_test/migration_database_sqlcipher_capability_test.dart
?? lib/core/database/app_database_version.dart
?? lib/features/account_migration/
?? lib/features/qr_code/application/scanned_qr_classifier.dart
?? test/features/account_migration/
?? test/features/push/infrastructure/
```

- 2026-06-07 20:10 CEST - Controller completed bounded contract extraction before code browsing. Files inspected: this MIG-009 plan, scoped `graphify query "MIG-009 migrated-out runtime network gates account migration authority guard P2P resume push groups avatars retriers listeners" --budget 2500` result, the MIG-009 rows in `01-move-account-to-new-device-pr-session-breakdown.md`, the MIG-009 gaps in `01-move-account-to-new-device-pr.md`, and the named-gate definitions for `baseline`, `1to1`, `groups`, `transport`, optional `runtime-telemetry`, and `completeness-check`. Extracted contract: add a durable account-authority runtime network gate for migrated-out/non-active authority states while preserving missing legacy authority, active authority, and `migrationFailedActiveRestored`; cover P2P/startup-background, resume, push/open/background, watchdog/rendezvous recovery, inbox drain, local discovery/send/media send, group rejoin/drain/recovery, push/rendezvous re-registration, profile/contact-avatar/group-avatar downloads, and network-side-effect listeners/retriers. Required first/direct tests are the plan-listed account-migration runtime gate, P2P, resume, push, group, profile/avatar, and retrier/listener suites; required host gates are `./scripts/run_test_gates.sh baseline`, `1to1`, `groups`, `transport`, and `completeness-check`, with `runtime-telemetry` only if telemetry/flow-event acceptance changes. Known-failure interpretation: MIG-006 remains deferred-last/evidence-gated, not failed or closed; no prohibited MIG-006 group simulator/release commands may run. Decision/blocker: execution contract is concrete and safe to hand to a spawned Executor. Next action: spawn Executor with model request `gpt-5.5` and reasoning request `xhigh`.
- 2026-06-07 20:10 CEST - Controller spawned isolated Executor child `019ea348-43b7-73a2-b08f-befe071e8eb8` with explicit prompt request `model: gpt-5.5`, `reasoning_effort: xhigh`. Files handed off: this plan, current breakdown, source proposal, gate definitions/script, scoped graphify result summary, and the hard MIG-006 deferral override. Decision/blocker: Executor running; QA has not started and will not run in parallel. Next action: bounded wait for Executor code/test evidence or final handoff.
- 2026-06-07 20:12 CEST - Executor started. Files inspected: MIG-009 plan, MIG-009 breakdown row, source proposal MIG-009 gaps, `Test-Flight-Improv/test-gate-definitions.md`, and `scripts/run_test_gates.sh`; no product code inspected yet. Decision/blocker: execution contract is clear, MIG-006 remains deferred-last/evidence-gated, and prohibited MIG-006 group simulator/release commands remain out of scope. Next action: run an additional scoped `graphify query` for runtime gate wiring before raw code browsing.
- 2026-06-07 20:14 CEST - Executor inspected owner files after scoped graphify query `graphify query "MIG-009 runtime network gate wiring for account migration authority across P2P service start resume push notification open group rejoin drain avatar downloads listeners retriers main.dart" --budget 3500` completed with authority/startup/push/group nodes but incomplete runtime coverage. Files inspected: authority model/repository/impl, `start_node_use_case.dart`, `p2p_service.dart`, `p2p_service_impl.dart`, `handle_app_resumed.dart`, push registration/coordinator/foreground/open/route-target/background handlers, group rejoin/drain/avatar storage, profile update/download files, pending message/key-exchange/post retriers, local listener scan, and `main.dart` runtime wiring. Decision/blocker: no blocker; implement additive shared gate and wire it through side-effect boundaries. Next action: edit gate, product wiring, and focused tests; no prohibited MIG-006 commands will run.
- 2026-06-07 20:15 CEST - Parent controller stopped the first execution child after the second bounded wait because it had not produced a code/test delta, test result, QA handoff, or final execution verdict, and stdin was closed so an in-band progress request could not be delivered. Last useful heartbeat was the 20:14 owner-file inspection entry above. Blocker class: `spawn_or_tool_no_completion` for the first execution attempt only, not a product blocker. Next action: use the pipeline's implementation-code exception and spawn one fresh narrower MIG-009 execution child with the current plan, owner files/tests, and exact artifact/result expectation.
- 2026-06-07 20:16 CEST - Fresh narrower MIG-009 execution child started under `$implementation-execution-qa-orchestrator` after the first execution attempt produced heartbeats but no completion. Current phase: contract/evidence recovery before Executor materialization decision. Last completed command/result: first child inspected scoped graphify and owner files but landed no code/test delta. Current command/log: none. Decision/blocker state: `pending_executor_materialization`; MIG-006 remains deliberately deferred-last/evidence-gated, not failed or closed, and prohibited MIG-006 group simulator/release commands remain out of scope. Next action: extract the existing MIG-009 contract, check whether nested Executor/QA spawning is available with explicit `model: gpt-5.5` and `reasoning_effort: xhigh`, then use local sequential fallback only if nested spawning no-progresses.
- 2026-06-07 20:17 CEST - Contract extracted for this narrower child from this plan only, without replanning. Current phase: Executor spawn handoff. Scope: MIG-009 migrated-out runtime network gates backed by durable account authority; preserve missing legacy authority, `active`, and `migrationFailedActiveRestored`; block `migratedOut` and unsafe non-active migration states at runtime network side-effect entry points. Required direct tests: the plan-listed account migration gate, P2P, resume, push, groups, profile/avatar, pending message, key-exchange, and post retrier suites. Required host gates: `./scripts/run_test_gates.sh baseline`, `1to1`, `groups`, `transport`, and `completeness-check`; `runtime-telemetry` only if telemetry/flow-event acceptance changes. Decision/blocker state: `ready_to_spawn_executor`; MIG-006 remains deliberately deferred-last/evidence-gated and prohibited group simulator/release commands remain out of scope. Next action: spawn the Executor with explicit request `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-06-07 20:18 CEST - Spawned Executor agent `019ea34e-29fc-7911-919e-7c4ee86d26d2` with explicit request `model: gpt-5.5` and `reasoning_effort: xhigh`. Current phase: Executor running under bounded wait. Current command/log: waiting for child result; no local tests running. Decision/blocker state: `executor_running_pending_evidence`. Next action: perform one bounded wait, then inspect plan/worktree evidence before deciding whether an additional wait or local sequential fallback is justified. MIG-006 remains deliberately deferred-last/evidence-gated and prohibited group simulator/release commands remain out of scope.
- 2026-06-07 20:20 CEST - Parent controller stopped the narrower execution child after bounded no-progress and closed stdin prevented an in-band progress request. Last persisted state from that child was the 20:18 Executor-spawn heartbeat; no code/test delta, test result, QA handoff, local fallback marker, blocker, or final execution verdict landed after settle polling. Blocker class: `spawn_or_tool_no_completion` for execution delivery only, not a product blocker. Next action: use the single local execution fallback for MIG-009 in the parent controller, starting with a fresh scoped graphify query before raw code edits; MIG-006 remains deliberately deferred-last/evidence-gated and prohibited group simulator/release commands remain out of scope.
- 2026-06-07 20:27 CEST - Local execution fallback is active in the parent controller after the two isolated execution children failed to materialize a final handoff. Last completed command/result: scoped `graphify query "MIG-009 local fallback account migration runtime network gate P2PServiceImpl startNode handleAppResumed push registration group rejoin drain profile avatar retriers listeners" --budget 3000` completed, and local edits have started. Files touched in this fallback so far: `lib/features/account_migration/application/account_migration_runtime_network_gate.dart`, `lib/features/p2p/application/start_node_use_case.dart`, `lib/features/push/application/register_push_token_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, `lib/core/services/p2p_service_impl.dart`, `test/features/account_migration/application/account_migration_runtime_network_gate_test.dart`, `test/features/p2p/application/start_node_use_case_test.dart`, `test/features/push/application/register_push_token_use_case_test.dart`, and `test/core/lifecycle/app_lifecycle_recovery_test.dart`. Current command/file progress: inspecting `test/core/services/p2p_service_impl_test.dart` and runtime call-site wiring in `lib/main.dart` / startup and push coordinator files to finish the coherent gate seam before formatting and focused tests. Decision/blocker state: `local_executor_in_progress`; no product blocker yet. Next action: add the direct `P2PServiceImpl` gate test, wire the real runtime gate at app construction/call sites, run `dart format`, then run focused MIG-009 tests and permitted host gates only. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; prohibited MIG-006 group simulator/release evidence commands remain out of scope.
- 2026-06-07 20:32 CEST - Local fallback edit pass completed and `dart format` succeeded on the MIG-009 touched files. Files touched since the previous heartbeat now also include `lib/main.dart`, `lib/features/identity/presentation/startup_router.dart`, `lib/features/push/application/push_registration_coordinator.dart`, `test/features/push/application/push_registration_coordinator_test.dart`, and `test/core/services/p2p_service_impl_test.dart`. Landed seam summary: authority-backed runtime gate wired into `P2PServiceImpl`, startup P2P use case call, app resume, push registration, push coordinator quiet handling, and direct service tests including relay probe/health/recovery short-circuits. Current command starting: `flutter test test/features/account_migration/application/account_migration_runtime_network_gate_test.dart test/features/p2p/application/start_node_use_case_test.dart test/features/push/application/register_push_token_use_case_test.dart test/features/push/application/push_registration_coordinator_test.dart test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/services/p2p_service_impl_test.dart`. Decision/blocker state: `focused_tests_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; prohibited MIG-006 group simulator/release evidence commands remain out of scope.
- 2026-06-07 20:33 CEST - Focused MIG-009 test bundle passed: `flutter test test/features/account_migration/application/account_migration_runtime_network_gate_test.dart test/features/p2p/application/start_node_use_case_test.dart test/features/push/application/register_push_token_use_case_test.dart test/features/push/application/push_registration_coordinator_test.dart test/core/lifecycle/app_lifecycle_recovery_test.dart test/core/services/p2p_service_impl_test.dart` completed with `+106`, `All tests passed!`. Current command starting: inspect permitted host gate definitions and run the MIG-009 required host gates (`baseline`, `1to1`, `groups`, `transport`, `completeness-check`) as host gates only. Decision/blocker state: `host_gates_pending`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; this does not authorize `run_with_devices.sh group`, full group simulator, or deferred MIG-006 release evidence commands.
- 2026-06-07 20:34 CEST - Gate definition inspection completed. `scripts/run_test_gates.sh` keeps `groups` as the host-side Group Messaging Gate and uses the separate `reliability-sim` case for simulator reliability; the prohibited MIG-006 `run_with_devices.sh group` path is not being invoked. `git diff --check` passed. Current command starting: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`. Decision/blocker state: `baseline_gate_running`.
- 2026-06-07 20:37 CEST - Baseline gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` exited 0. The run included the named baseline host tests plus macOS integration slices and ended with `All tests passed!` for the integration slices. Current command starting: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1`. Decision/blocker state: `one_to_one_gate_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated, and no prohibited group simulator/release evidence commands have run.
- 2026-06-07 20:37 CEST - 1:1 gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh 1to1` exited 0 with `+74`, `All tests passed!`. Current command starting: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`. Decision/blocker state: `groups_host_gate_running`; no product blocker yet. This is the named host-side Group Messaging Gate from `scripts/run_test_gates.sh`, not MIG-006 deferred group simulator/release evidence.
- 2026-06-07 20:39 CEST - Group host gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` exited 0 with `+324`, `All tests passed!`. Current command starting: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`. Decision/blocker state: `transport_gate_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated and no `run_with_devices.sh group` or group simulator/release evidence command has run.
- 2026-06-07 20:41 CEST - Transport gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport` exited 0. The macOS run built the transport integration slices; `background_reconnect_test.dart` skipped under its own conditions, and the remaining transport/media stable-id slices ended with `All tests passed!`. Current command starting: `./scripts/run_test_gates.sh completeness-check`. Decision/blocker state: `completeness_check_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated and no prohibited group simulator/release evidence command has run.
- 2026-06-07 20:41 CEST - Completeness check passed: `./scripts/run_test_gates.sh completeness-check` reported `Completeness check: 801/801 test files classified.` and `Completeness check PASS.` Current phase: local QA review of the MIG-009 fallback diff before execution verdict. Current command/file progress: inspect scoped diff/stat for gate seam correctness and missing bypasses, then run `graphify update .` after code changes. Decision/blocker state: `local_qa_review_running`; no product blocker yet.
- 2026-06-07 20:44 CEST - Progress checkpoint under the local execution fallback. Local QA found the first pass protects P2P service methods, startup P2P, app resume, and push registration, with focused tests and permitted host gates already passing, but `lib/main.dart` still starts live listeners/retriers and passes direct retry callbacks that can invoke group/post/message bridge work outside `P2PServiceImpl`. Current command/file progress: editing `lib/main.dart` to add a shared runtime action helper, gate `startLiveServices()` before listener/retrier startup, and wrap `PendingMessageRetrier` network callbacks with operation-specific blocked values; then rerun formatting, `git diff --check`, a main compile/analyze check, and `graphify update .`. Decision/blocker state: `local_executor_recovery_in_progress`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; no `run_with_devices.sh group`, full group simulator, or MIG-006 release-evidence command will be run.
- 2026-06-07 20:47 CEST - Local recovery edit completed. `dart format lib/main.dart` succeeded, `git diff --check` passed, and `flutter analyze lib/main.dart` reported `No issues found!`. Current file progress: `lib/main.dart` now gates `startLiveServices()` before listener/retrier startup and wraps the direct `PendingMessageRetrier` retry/rejoin/drain callbacks with the runtime authority helper. Current command starting: `FLUTTER_DEVICE_ID=macos flutter test integration_test/loading_states_smoke_test.dart` as an app-entry compile smoke for the final `main.dart` delta. Decision/blocker state: `app_entry_compile_smoke_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated, not failed and not closed; prohibited MIG-006 group simulator/release evidence commands remain out of scope.
- 2026-06-07 20:48 CEST - The first app-entry smoke command did not run tests: `FLUTTER_DEVICE_ID=macos flutter test integration_test/loading_states_smoke_test.dart` exited 1 because raw `flutter test` reported multiple attached devices and requested `-d <deviceId>`. This is a harness invocation issue, not product evidence. Current command starting: `flutter test -d macos integration_test/loading_states_smoke_test.dart`. Decision/blocker state: `app_entry_compile_smoke_retry_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated and no prohibited group simulator/release evidence command has run.
- 2026-06-07 20:52 CEST - App-entry smoke retry passed: `flutter test -d macos integration_test/loading_states_smoke_test.dart` built the macOS app, logged existing macOS deployment/foreground warnings, and ended `+7`, `All tests passed!`. Local QA then found one more MIG-009 implementation-owned gap: delayed post media upload, post delivery, post follow-on, and key-exchange retriers could still execute after authority changes while the app is already running. Current file progress: added optional runtime authority gates to `PendingPostMediaUploadRetrier`, `PendingPostDeliveryRetrier`, `PendingPostFollowOnRetrier`, and `KeyExchangeRetrier`; wired the real gate through `lib/main.dart`; added blocked retrier tests in the corresponding test files. `dart format` succeeded on those nine touched files. Current command starting: focused retrier test bundle for the new delayed-work gates. Decision/blocker state: `focused_retrier_tests_running`; no product blocker yet. MIG-006 remains deliberately deferred-last/evidence-gated and no prohibited group simulator/release evidence command has run.
- 2026-06-07 21:00 CEST - Focused delayed-work retrier bundle passed: `flutter test test/features/contact_request/application/key_exchange_retrier_test.dart test/core/services/pending_post_delivery_retrier_test.dart test/core/services/pending_post_follow_on_retrier_test.dart test/core/services/pending_post_media_upload_retrier_test.dart` exited 0 with `+20`, `All tests passed!`. Local QA then fixed two gate-identity issues inside MIG-009 scope: target-peer bridge operations in `P2PServiceImpl` now evaluate the local account peer instead of the remote target peer, and push token registration now passes `p2pService.currentState.peerId` through the account-migration runtime gate. The focused MIG-009 bundle was rerun and passed with `+107`, `All tests passed!`. Decision/blocker state: `local_qa_recovery_passed`; MIG-006 remains deferred-last/evidence-gated and untouched.
- 2026-06-07 21:08 CEST - Local QA found app-shell bypasses outside the first gate pass and fixed them inside MIG-009 scope. `lib/main.dart` now wraps notification-open 1:1 inbox drains, foreground 1:1 drains, foreground group drains, and group dispatcher overflow recovery with the runtime authority helper. `prepareNotificationRouteTarget` now receives the runtime gate and gates group notification-open drains. Decision/blocker state: `app_shell_push_group_bypasses_fixed`; no MIG-006 group simulator or release evidence command has run.
- 2026-06-07 21:14 CEST - App-shell and push verification passed after the bypass fixes: `dart format lib/main.dart lib/features/push/application/prepare_notification_route_target_use_case.dart` succeeded; `flutter analyze lib/main.dart lib/features/push/application/prepare_notification_route_target_use_case.dart` reported `No issues found!`; affected push tests passed with `+45`; focused delayed-work retrier tests passed with `+20`; `flutter test -d macos integration_test/loading_states_smoke_test.dart` passed with `+7`; and `git diff --check` passed. Decision/blocker state: `final_push_app_shell_verification_passed`.
- 2026-06-07 21:24 CEST - Post-wrapper host baseline rerun passed after the final `main.dart` wrappers: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` exited 0 with the baseline host bundle passing at `+105`, macOS loading smoke passing at `+7`, and posts fake passing at `+1`. Earlier in this MIG-009 execution, the permitted host gates also passed: `1to1` with `+74`, host-side `groups` with `+324`, `transport` with its background reconnect self-skip plus transport/media slices passing, and `completeness-check` with `801/801`. The host-side `groups` gate is not the deferred MIG-006 group simulator/release evidence.
- 2026-06-07 21:31 CEST - Final background-push closure pass completed. `firebaseMessagingBackgroundHandler` now checks the account-migration runtime gate before local fallback display/recent-announcement surfacing, and `test/features/push/application/background_message_handler_test.dart` proves a blocked authority does not call the local-notification `show` method. Evidence: focused background handler test passed with `+13`; affected push bundle passed with `+46`; `flutter analyze lib/main.dart lib/features/push/application/background_message_handler.dart lib/features/push/application/prepare_notification_route_target_use_case.dart test/features/push/application/background_message_handler_test.dart` reported `No issues found!`; `git diff --check` passed; `./scripts/run_test_gates.sh completeness-check` passed with `801/801`; and `graphify update .` rebuilt the graph with 92605 nodes and 163155 edges. Decision/blocker state: `qa_accepted_mig_009_closed_for_session_scope_only`.

## Closure Progress

- Closed scope: MIG-009 added the durable account-authority runtime network gate and wired it into P2P service operations, startup P2P, app resume, push token registration/coordinator retry, foreground and notification-open drains, background push fallback display, live-service startup, pending-message callbacks, group dispatcher overflow recovery, and delayed key-exchange/post retriers. The gate allows missing legacy authority, `active`, and `migrationFailedActiveRestored`, and blocks `migratedOut`, fail-closed records, peer mismatches when a peer is supplied, and other non-active migration states.
- Closure evidence: direct account-migration/P2P/resume/push/P2P-service bundle passed with `+107`; affected push/background bundle passed with `+46`; delayed key-exchange/post retrier bundle passed with `+20`; app-entry smoke passed with `+7`; post-wrapper baseline gate passed with host `+105`, loading smoke `+7`, and posts fake `+1`; permitted MIG-009 host gates passed for `1to1`, host-side `groups`, `transport`, and `completeness-check`; analyzer, `git diff --check`, and `graphify update .` completed after the final code delta.
- Accepted differences: MIG-009 proves runtime quieting only. It does not implement pending-work ownership or queue migration, user-facing migrated-out screens and wake-lock journey, final physical-device acceptance, full bundle export/import, or MIG-006 group release evidence. Background push handling is limited to suppressing local migrated-out fallback display/surfacing; broader user education and migrated-out UX remain MIG-011.
- Residual/open scope: MIG-010 owns pending work ownership and queue migration; MIG-011 owns the user journey/progress/wake-lock/migrated-out UX; MIG-012 owns final device/release acceptance; MIG-006 remains deliberately deferred-last/evidence-gated with commands 29-123 and final group verification still required.

## Session Verdict

MIG-009 is closed for its own migrated-out runtime network gate scope only. The overall Move Account proposal remains open. MIG-006 is not failed, not closed, and not reinterpreted by this session; no prohibited MIG-006 group simulator or release-evidence command was run.

## real scope

MIG-009 owns migrated-out runtime network gates only. The session must make every normal runtime entry point that can create account network side effects consult the durable account-migration authority before it starts, resumes, drains, registers, rejoins, discovers, downloads, retries, or listens.

The implementation should preserve non-migrated behavior for missing legacy authority records, `active`, and `migrationFailedActiveRestored` accounts. It should block `migratedOut` and all non-active migration states that cannot safely create normal account network traffic, including import/staging, cutover-pending/paused, pairing/waiting, cleanup-required, and fail-closed states.

This document started as the execution-ready contract and now records the MIG-009 implementation and closure evidence.

## closure bar

MIG-009 closes only when migrated-out authority prevents account-network side effects through all runtime entry points named in the source and breakdown:

- startup/background P2P start and warmup
- app resume health/recovery paths
- watchdog/personal rendezvous recovery and relay reconnect side effects
- P2P start, inbox drain, local discovery, local sends, and local media sends
- push token registration, push foreground handling, notification-open drains, and background push display/fallback behavior where it can surface migrated-out activity
- group topic rejoin, group offline inbox drain, and group discovery/recovery loops
- rendezvous/push re-registration attempts after cutover primitives have unregistered old leases
- profile update listener downloads, contact avatar downloads, and group avatar downloads
- listeners/retriers that schedule or perform network sends, uploads, drains, retries, rejoin, or discovery

Direct tests must prove both blocked and allowed behavior. Host gates must pass where touched. Simulator evidence is limited by the explicit MIG-006 override: no group simulator or release-evidence commands belong to MIG-009.

## source of truth

Primary source:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`

Session breakdown:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`

Already-closed prerequisite:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-008-plan.md`

Code authority model:

- `lib/features/account_migration/domain/models/account_migration_authority_state.dart`
- `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart`
- `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`

Gate map:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## session classification

Implementation-ready, evidence-gated only for device/simulator evidence that cannot be run without crossing the MIG-006 hard override.

MIG-009 depends on MIG-001 authority persistence/startup blocking and MIG-008 cutover primitives. It does not depend on MIG-006 group simulator release evidence, and MIG-006 must remain open/deferred-last rather than failed or closed.

## exact problem statement

MIG-001 blocks migrated-out accounts at startup, and MIG-008 adds cutover primitives that unregister old leases/tokens and commit active authority. Existing runtime code still has many ways to restart network activity after startup: resume handlers, push callbacks, P2P warmup/recovery, retriers/listeners, group rejoin/drain, local discovery, and avatar/profile downloads. A migrated-out old device must not be able to recreate normal account activity through any of those runtime paths after cutover.

The executor must add a single durable account-authority network-side-effect guard and wire it through each runtime path that can produce old-device account network traffic. The guard must fail closed for migrated or in-progress migration states, but remain backward-compatible for non-migrated accounts.

## files and repos to inspect next

Account authority and startup:

- `lib/features/account_migration/domain/models/account_migration_authority_state.dart`
- `lib/features/account_migration/domain/repositories/account_migration_authority_repository.dart`
- `lib/features/account_migration/application/account_migration_authority_repository_impl.dart`
- `lib/features/identity/application/startup_decision.dart`
- `lib/features/identity/presentation/startup_router.dart`

Runtime/P2P/resume:

- `lib/main.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/features/p2p/application/start_node_use_case.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/services/p2p_service_impl.dart`

Push and notification open:

- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/features/push/application/push_registration_coordinator.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`

Groups, profile, avatars, retriers, listeners:

- `lib/features/groups/application/rejoin_group_topics_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/settings/application/profile_update_listener.dart`
- `lib/features/settings/application/download_profile_picture_use_case.dart`
- `lib/core/services/incoming_message_router.dart`
- `lib/core/services/contact_request_listener.dart`
- `lib/core/services/chat_message_listener.dart`
- `lib/features/contact_request/application/contact_request_listener.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_invite_listener.dart`
- `lib/features/groups/application/group_key_update_listener.dart`
- `lib/features/groups/application/group_membership_update_listener.dart`
- post listener files under `lib/features/posts/application/`
- `lib/core/services/pending_message_retrier.dart`
- `lib/features/contact_request/application/key_exchange_retrier.dart`
- `lib/features/posts/application/pending_post_media_upload_retrier.dart`
- `lib/features/posts/application/pending_post_delivery_retrier.dart`
- `lib/features/posts/application/pending_post_follow_on_retrier.dart`
- local discovery services reached from `P2PServiceImpl`

## existing tests covering this area

Startup and authority:

- `test/features/identity/application/startup_decision_test.dart`
- startup-router tests under `test/features/identity/presentation/`
- authority model/repository tests under `test/features/account_migration/`

P2P/runtime/resume:

- `test/features/p2p/application/start_node_use_case_test.dart`
- `test/core/services/p2p_service_impl_test.dart`
- `test/core/services/p2p_service_fault_injection_test.dart`
- `test/core/services/p2p_service_lan_availability_test.dart`
- `test/core/services/p2p_service_stop_race_test.dart`
- resume/lifecycle tests under `test/core/lifecycle/`

Push/groups/profile/retriers:

- `test/features/push/application/register_push_token_use_case_test.dart`
- `test/features/push/application/push_registration_coordinator_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/prepare_notification_open_use_case_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_avatar_storage_test.dart`
- `test/features/settings/application/profile_update_listener_test.dart`
- `test/features/settings/application/download_profile_picture_use_case_test.dart`
- incoming-message-router and listener tests under `test/core/services/`, `test/features/contact_request/application/`, `test/features/conversation/application/`, `test/features/groups/application/`, `test/features/introduction/application/`, and `test/features/posts/`
- `test/core/services/pending_message_retrier_test.dart`
- `test/features/contact_request/application/key_exchange_retrier_test.dart`
- post retrier tests under `test/features/posts/application/`

## regression/tests to add first

Add or update direct tests before implementation where practical:

- New `test/features/account_migration/application/account_migration_runtime_network_gate_test.dart`: missing legacy record, `active`, and `migrationFailedActiveRestored` allow normal side effects; `migratedOut`, import/staging, cutover-pending/paused, pairing/waiting, cleanup-required, fail-closed, and mismatched authority peer block.
- Update `test/features/p2p/application/start_node_use_case_test.dart`: blocked authority returns an explicit blocked result and never calls `P2PService.startNode`; allowed authority preserves existing results.
- Add or update `test/core/services/p2p_service_account_migration_gate_test.dart`: blocked authority prevents `node:start`, warm background health/recovery, personal rendezvous/relay reconnect, inbox retrieve, push token registration, local discovery/restart, local peer discovery, local send, and local media send; allowed authority preserves existing behavior.
- Add `test/core/lifecycle/handle_app_resumed_migration_gate_test.dart`: blocked authority prevents bridge health/reinitialize, P2P health/drain, push-registration retry, group rejoin/drain/recovery, pending message/post/key-exchange retry callbacks, nearby refresh, and upload retries.
- Update push tests to prove blocked authority prevents token fetch/register/persist, coordinator retries, foreground drains, notification-open drains, route-target drains, and background migrated-out local notification/preview display.
- Update group tests to prove blocked authority returns a skipped/no-op result for topic rejoin and group inbox drain, with no `group:join` or `group:inboxRetrieveCursor`.
- Update profile/avatar tests to prove blocked authority prevents `profile:download` and `media:download` for contact/group avatar downloads.
- Inspect main-started message, contact, intro, group, and post listeners. Add direct tests or no-network justifications for any listener `start` or envelope-processing path that can acknowledge, download, upload, send, retry, or otherwise create network side effects.
- Update retrier/listener tests to prove blocked authority prevents subscriptions/timers from performing network retry work and cancels or no-ops if authority becomes blocked before a scheduled retry fires.
- Add one wiring-level test, source-inspection test, or narrow constructor test proving `main.dart` passes the same runtime gate into P2P, resume, push, group, profile/avatar, and retrier/listener entry points.

## step-by-step implementation plan

1. Introduce a narrow account-migration runtime network gate in `lib/features/account_migration/application/`, backed by `AccountMigrationAuthorityRepository` and, where useful, the local identity peer id. It should expose a simple async decision such as `allowsAccountNetworkSideEffects({String? peerId, String? reason})` and optional `isBlocked` helpers for tests. Missing authority records remain allowed for legacy installs; non-active migration states block.
2. Add small, explicit result shapes where current APIs need assertions instead of silent ambiguity. `startP2PNode` should be able to report account-migration blocked without pretending there is no identity. Group drain/rejoin and push/open paths may return skipped/no-op results when blocked.
3. Wire the guard into startup-router background P2P entry points and `startP2PNode`. Startup blocking already exists; MIG-009 adds protection for direct/background P2P start calls that occur after startup decisions.
4. Wire the guard into `P2PServiceImpl` before any public method or private delayed callback that can create account network side effects: node start/warmup, health checks, relay reconnect/personal rendezvous recovery, inbox drains, push-token registration or re-registration, local discovery/restart, local peer discovery, local send, and local media send. Stop/dispose paths stay allowed.
5. Wire the guard into `handleAppResumed` and its `main.dart` call site so a migrated-out account skips bridge/P2P health, drains, rejoin, retries, push-registration retry, local discovery/nearby refresh, and upload retry callbacks. Keep purely local cleanup outside this session unless it schedules network work.
6. Wire push registration and notification handling: `PushRegistrationCoordinator.isEnabled`, `register_push_token_use_case`, foreground remote message handling, notification-open preparation, route-target preparation, and background handler display/fallback logic must no-op when blocked. Background handling should not become a MIG-011 UI project; it only suppresses migrated-out push activity.
7. Wire group runtime paths: `rejoin_group_topics_use_case`, `drain_group_offline_inbox_use_case`, and group discovery/recovery loops reached from resume/retriers must consult the gate before bridge calls.
8. Wire profile/avatar paths: `ProfileUpdateListener`, contact profile-picture download, and group avatar download should no-op before bridge media/profile download calls when blocked. Existing local disk/avatar resolvers remain unchanged unless they initiate network downloads.
9. Inspect message, contact, intro, group, post, and profile listeners started from `main.dart`. For listener paths that only process already-local envelopes, record a no-network justification in tests or closure notes. For listener paths that acknowledge, download, upload, send, retry, or trigger bridge/P2P calls, wire the runtime gate before those side effects.
10. Wire retriers/listeners that can generate network side effects: pending message, pending post media upload, pending post delivery, pending post follow-on, key exchange, group retry/upload/recovery callbacks reached through `PendingMessageRetrier`, and profile update listener retry timers. They should avoid starting subscriptions/timers when already blocked and re-check before executing delayed work.
11. Update fakes/test helpers with lightweight gate stubs and call counters only where tests need explicit assertions. Avoid broad test-helper refactors.
12. Run the direct tests first, fix regressions within MIG-009 scope, then run the host gates and the narrow non-group simulator path listed below. Record any device/simulator unavailability as evidence-gated rather than green.

## risks and edge cases

- A guard only at startup is insufficient because resume, push, timers, listeners, and delayed P2P warmup can run after the startup decision.
- A guard only in `P2PServiceImpl` is insufficient because group bridge calls, push callbacks, and avatar/profile downloads can bypass P2P service methods.
- Missing authority records must remain compatible with pre-migration installs; do not strand existing users by treating missing as migrated-out.
- Peer mismatch should fail closed for account side effects when the persisted authority belongs to another peer, but tests must make the intended legacy/missing-record behavior explicit.
- Stop/shutdown/dispose/unregister cleanup paths should remain allowed; the guard blocks normal activity, not safe teardown.
- Timers and listeners may be scheduled while active and fire after authority flips to migrated-out. Re-check immediately before side effects.
- Background push handler changes can accidentally become a UI/session-routing change. Keep it to suppressing migrated-out push activity and no-op side effects.
- Group host tests are valid for direct group runtime code changes; group simulator/release evidence remains outside this session by hard override.

## exact tests and gates to run

Direct focused tests after implementation:

```sh
flutter test \
  test/features/account_migration/application/account_migration_runtime_network_gate_test.dart \
  test/features/p2p/application/start_node_use_case_test.dart \
  test/core/services/p2p_service_account_migration_gate_test.dart \
  test/core/lifecycle/handle_app_resumed_migration_gate_test.dart \
  test/features/push/application/register_push_token_use_case_test.dart \
  test/features/push/application/push_registration_coordinator_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
  test/features/push/application/prepare_notification_open_use_case_test.dart \
  test/features/push/application/background_message_handler_test.dart \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/application/group_avatar_storage_test.dart \
  test/features/settings/application/profile_update_listener_test.dart \
  test/features/settings/application/download_profile_picture_use_case_test.dart \
  test/core/services/pending_message_retrier_test.dart \
  test/features/contact_request/application/key_exchange_retrier_test.dart \
  test/features/posts/application/pending_post_media_upload_retrier_test.dart \
  test/features/posts/application/pending_post_delivery_retrier_test.dart \
  test/features/posts/application/pending_post_follow_on_retrier_test.dart
```

Host gates:

```sh
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
```

Run this only if runtime telemetry or push flow-event acceptance changes:

```sh
./scripts/run_test_gates.sh runtime-telemetry
```

Narrow non-MIG-006 simulator evidence, only when devices are available and after host gates pass:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

Never include the MIG-006 deferred-last group simulator or group release-evidence commands in this session.

## known-failure interpretation

- MIG-006 deferred-last group simulator/release evidence is not a MIG-009 failure and must not be marked closed by this session.
- If device or simulator availability blocks the narrow 1:1 simulator path, record that as evidence-gated and do not overclaim device acceptance.
- Host group gate failures caused by MIG-009 group runtime guard changes are in scope. Failures that require the prohibited group simulator/release evidence remain outside this session.
- Existing unrelated gate failures are not MIG-009 acceptance unless a direct MIG-009 test or touched gate regresses.
- `runtime-telemetry` is required only if MIG-009 changes telemetry names, flow-event acceptance, or push decrypt telemetry behavior.

## done criteria

- All MIG-009 named runtime entry points have a durable account-authority network-side-effect guard or an explicit no-network justification in code/tests.
- Migrated-out and non-active migration states no-op or return explicit blocked/skipped results without bridge/P2P/network calls.
- Missing legacy authority, active authority, and migration-failed-active-restored authority preserve existing runtime behavior.
- Direct blocked/allowed tests cover P2P, resume, push, notification-open, groups, profile/avatar downloads, and retriers/listeners.
- Required host gates pass or have clear unrelated known-failure evidence.
- Narrow non-group simulator evidence is run when available, or recorded as evidence-gated without using prohibited MIG-006 commands.
- The MIG-009 plan/closure docs state that MIG-006 remains deferred-last/evidence-gated and not a dependency.

## scope guard

Do not implement MIG-006 group simulator/release evidence, do not run prohibited group simulator commands, and do not close MIG-006.

Do not implement MIG-010 pending-work ownership semantics beyond preventing runtime network side effects from migrated-out accounts.

Do not implement MIG-011 migrated-out UI beyond no-op/block results needed to suppress runtime network or push activity.

Do not implement MIG-012 final device acceptance, final program verdict, or overall source-doc closure.

Do not change server-side cutover primitives unless direct MIG-009 evidence shows a client runtime gate cannot otherwise prevent old-device reactivation.

## accepted differences / intentionally out of scope

- Group runtime host coverage is planned because MIG-009 changes direct group rejoin/drain paths. Full group simulator/release evidence remains intentionally excluded by the user override.
- Background push handling is limited to preventing migrated-out push activity/display fallback; full migrated-out navigation or user education belongs to MIG-011.
- Pending-work ownership and cross-device queue transfer belong to MIG-010. MIG-009 may stop migrated-out retry work but must not decide new-device ownership of old queues.
- Runtime graph updates were required after implementation and completed with `graphify update .`.

## dependency impact

MIG-009 consumes MIG-001 authority persistence/startup semantics and MIG-008 cutover primitives. It should leave MIG-010, MIG-011, and MIG-012 with clearer boundaries: old-device runtime network side effects are blocked, while pending-work transfer, user-facing blocked surfaces, and final multi-device/release evidence remain their own sessions.

MIG-006 remains deliberately deferred-last/evidence-gated by hard user override. MIG-009 must not wait on it, close it, or reinterpret its missing release evidence as a failure.
