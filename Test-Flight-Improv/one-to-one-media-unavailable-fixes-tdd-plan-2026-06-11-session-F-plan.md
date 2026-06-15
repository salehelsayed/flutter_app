# Session F Plan: Simulator Acceptance And Closure

Status: execution-ready

Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
Breakdown artifact: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`
Current session: F, Simulator Acceptance And Closure

## Planning Progress

- 2026-06-12 09:04 CEST - Role: local plan fallback / Arbiter completed. Files inspected since last update: source plan, session breakdown, debug report, gate definitions, 1:1 reliability list output, `integration_test/media_message_journey_e2e_test.dart`, `integration_test/media_stable_id_smoke_test.dart`, reliability runner scripts, matrix rows DM-015/016/018/019, and 1:1 closure reference. Decision/blocker: spawned planner no-progressed after `planning-intake`; the breakdown entry is execution-safe, so this file is the bounded local fallback plan. Next action: execute targeted simulator proof, then full 1:1 reliability and host gates, then update closure docs.
- 2026-06-12 08:50 CEST - Role: Evidence Collector started by spawned planner. Files inspected since last update: `implementation-plan-orchestrator`, `graphify`, and `run-flutter-reliability-sims` skill contracts; plan path existence. Decision/blocker: no blocker yet; planning file established. Next action: graphify-arch first, then source docs and simulator inventory.
- 2026-06-12 08:49 CEST - Role: intake. Files inspected since last update: skill contracts and requested plan path existence only. Decision/blocker: plan file was missing, so this file became the live doc-scoped planning surface. Next action: start Evidence Collector.

## Execution Progress

- 2026-06-12 11:48 CEST - Phase: scoped diff check passed; graphify update started. Files inspected or touched: this plan. Command completed: `git diff --check -- integration_test/scripts/run_transport_e2e.dart Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-F-plan.md Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`, exit code 0. Command running next: `cd graphify-arch && graphify update .`. Decision/blocker: diff hygiene is clean for the tracked touched paths; final handoff remains blocked by #19 simulator UI smoke.
- 2026-06-12 11:47 CEST - Phase: scoped diff check started. Files inspected or touched: this plan. Command running next: `git diff --check -- integration_test/scripts/run_transport_e2e.dart Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-F-plan.md Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`. Decision/blocker: required final closure remains blocked by #19, but touched-file whitespace validation still needs to run before handoff.
- 2026-06-12 11:46 CEST - Phase: focused #19 triage completed; Session F blocked on simulator UI harness/device evidence. Files inspected or touched: this plan, `/tmp/session-f-ios-notification-triage-two-device-20260612-1132.log`, `build/ios-notification-tap-ui-smoke/20260612T093241Z/iPhone_17_Pro_warm_one_to_one_text.combined.log`, and `build/ios-notification-tap-ui-smoke/20260612T093241Z/iPhone_17_Pro_warm_one_to_one_text_retry_2.combined.log`. Command completed: `MKNOON_RELAY_ADDRESSES=... ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469'`, exit code 1. Classification state: `blocked_external_device_ui_harness`, not a Sessions A-E media-unavailable regression. Evidence: the focused rerun passed the first simulator warm one-to-one and group notification tap scenarios, then reproduced the second-simulator warm one-to-one failure; first attempt reached `ios_native_un_didReceive`, `ios_notification_open_forwarded_warm`, and `IOS_APNS_NOTIFICATION_OPENED` but failed at `ios/RunnerUITests/NotificationTapUITests.swift:99` with `Could not re-tap a Springboard notification titled New Message 412_27465`; retry prepare passed but then timed out waiting for warm app node readiness in the retry combined log. Decision/blocker: the required full helper-managed `1to1` gate remains failed at command #19, so Session F cannot honestly run final closure docs or mark the rollout closed. No production-code fix is authorized because the failure is outside the Session A-E media recovery scope and is isolated to the iOS notification tap UI smoke on simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`. Next action: update breakdown/final verdict as blocked, then run scoped diff check and `cd graphify-arch && graphify update .` for the files touched by this Executor.
- 2026-06-12 11:32 CEST - Phase: focused triage command corrected. Files inspected or touched: this plan and `/tmp/session-f-ios-notification-triage-20260612-1128.log`. Command completed: `MKNOON_RELAY_ADDRESSES=... ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '38FECA55-03C1-4907-BD9D-8E64BF8E3469'`, exit code 1. Result: invalid triage setup, not a product result; wrapper printed `Expected exactly two comma-separated simulator UDIDs in --devices.` Classification state remains pending_triage for the original #19 failure. Corrected focused triage command running next: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469'` with output redirected to `/tmp/session-f-ios-notification-triage-two-device-20260612-1132.log`.
- 2026-06-12 11:28 CEST - Phase: full simulator rerun exited failed; focused triage starting. Files inspected or touched: this plan, `/tmp/session-f-1to1-full-rerun-20260612-1026.log`, `build/ios-notification-tap-ui-smoke/20260612T091320Z/iPhone_17_Pro_warm_one_to_one_text.combined.log`, and `build/ios-notification-tap-ui-smoke/20260612T091320Z/iPhone_17_Pro_warm_one_to_one_text_retry_2.combined.log`. Command completed: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1` exited code 65 after command #19 failed. Evidence: retry attempt also reached native `ios_notification_open_forwarded_warm` and Flutter `IOS_APNS_NOTIFICATION_OPENED`, then XCTest continued polling notification/SpringBoard elements and did not satisfy foreground observation. Focused triage command running next: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '38FECA55-03C1-4907-BD9D-8E64BF8E3469'` with output redirected to `/tmp/session-f-ios-notification-triage-20260612-1128.log`. Current classification state: pending_triage. Decision/blocker: no fix until this focused rerun confirms whether the failure is persistent on the device/UI harness or clears under a fresh single-device invocation.
- 2026-06-12 11:25 CEST - Phase: full simulator rerun failed inside late UI smoke, classification pending_triage. Files inspected or touched: this plan and `/tmp/session-f-1to1-full-rerun-20260612-1026.log`. Failing command: helper-managed `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1`, currently in command #19 `MKNOON_RELAY_ADDRESSES=... ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469'`. Failing file/test: `ios/RunnerUITests/NotificationTapUITests.swift:104`, `NotificationTapUITests.testTapExistingNotification` on the second simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`. Log path: `build/ios-notification-tap-ui-smoke/20260612T091320Z/iPhone_17_Pro_warm_one_to_one_text.combined.log`, with wrapper log `/tmp/session-f-1to1-full-rerun-20260612-1026.log`. Focused triage command after the helper returns: `MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' ./scripts/run_ios_notification_tap_ui_smoke.sh --devices '38FECA55-03C1-4907-BD9D-8E64BF8E3469'`. Current classification state: pending_triage. Evidence so far: the app received SpringBoard notification taps twice, but XCTest did not observe `com.mknoon.app` become foreground within 60 seconds. Decision/blocker: no code edits are allowed for this failure until the helper exits and focused triage classifies whether this is a device/UI-runner blocker, unrelated notification surface, or a Session F-required regression.
- 2026-06-12 10:26 CEST - Phase: full simulator scope rerun started. Files inspected or touched: this plan. Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1` with output redirected to `/tmp/session-f-1to1-full-rerun-20260612-1026.log`. Decision/blocker: pending full simulator scope after simulator-orchestrator fix. Next action: inspect helper pass/fail summary and continue to named gates if green.
- 2026-06-12 10:26 CEST - Phase: focused transport E2E post-fix passed. Files inspected or touched: this plan and `integration_test/scripts/run_transport_e2e.dart`. Command completed: `dart run integration_test/scripts/run_transport_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` with output redirected to `/tmp/session-f-transport-e2e-postfix-20260612-1020.log`; exit code 0. Evidence: E8 orchestrator proof now reports `messageSeen=true attachmentReferenced=true downloaded size=69 blobInList=false retainedSources=inbox:b8`, and the final summary reports `Done. Flutter=0 Orch=0 Combined=0`. Decision/blocker: structural simulator race is fixed without production-code edits. Next action: rerun the required full helper-managed `1to1` scope.
- 2026-06-12 10:20 CEST - Phase: classification corrected and structural simulator fix applied. Files inspected or touched: this plan and `integration_test/scripts/run_transport_e2e.dart`. Command completed: `dart analyze integration_test/scripts/run_transport_e2e.dart` exited 0 with style/info diagnostics only. Corrected classification state: simulator-orchestrator structural failure, not a production media-loss regression. Evidence: B8 `inbox_retrieve` ran after E8's `inbox:store_timing success` and retrieved 2 messages before E8 verification started; this consumed the E8 media envelope into the script's retained proof buffer, so the later E8 `inbox_retrieve` saw 0 while `media_download` still succeeded. Fix: preserve parsed payload text/media in retained proofs and let E8 accept a retained proof only when it matches the exact E8 text and blob ID/mime/mediaType. Next action: rerun focused `dart run integration_test/scripts/run_transport_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`.
- 2026-06-12 10:19 CEST - Phase: full simulator failure classified. Files inspected or touched: this plan, `integration_test/scripts/run_transport_e2e.dart`, `integration_test/transport_e2e_test.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/domain/models/message_payload.dart`, `lib/features/conversation/domain/models/media_attachment.dart`, `lib/core/services/p2p_service_impl.dart`, `go-mknoon/cmd/testpeer/commands.go`, source plan, session breakdown, and logs `/tmp/session-f-1to1-full-20260612-0926.log` plus `/tmp/session-f-transport-e2e-triage-20260612-1014.log`. Focused triage command completed: `dart run integration_test/scripts/run_transport_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, failed with the same E8 orchestrator result. Classification state: Sessions A/C scoped regression; persistent real transport/media-envelope proof failure, not external/device. Evidence: Flutter E8 uploads media and sends `send=success attachments=1`, the receiver can `media_download` the 69-byte blob, but receiver-side `get_messages`/`inbox_retrieve` do not expose an E8 chat envelope carrying that attachment. Decision/blocker: a narrowly scoped fix is allowed because this is the media-blob-versus-envelope durability mismatch the rollout is closing. Next action: inspect and patch the smallest responsible real transport/testpeer/relay path, then rerun focused E8/transport evidence.
- 2026-06-12 10:14 CEST - Phase: full simulator failure triage started. Files inspected or touched: this plan, `integration_test/scripts/run_transport_e2e.dart`, `integration_test/transport_e2e_test.dart`, source rollout plan, session breakdown, and `/tmp/session-f-1to1-full-20260612-0926.log`. Focused triage command running next: `dart run integration_test/scripts/run_transport_e2e.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` with output redirected to `/tmp/session-f-transport-e2e-triage-20260612-1014.log`. Current classification state: pending_triage. Evidence so far: full helper passed #1-#14, failed #15 `integration_test/scripts/run_transport_e2e.dart`; E8 Flutter side uploaded media and logged `send=success attachments=1`, but orchestrator saw no E8 message/attachment envelope while `media_download` for the blob succeeded. Decision/blocker: rerun the failing command before deciding whether this is persistent Sessions A/C media-envelope regression, simulator orchestration fragility, or an external/device blocker.
- 2026-06-12 10:12 CEST - Phase: full simulator scope failed, classification pending_triage. Files inspected or touched: this plan. Failing command: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1` with output redirected to `/tmp/session-f-1to1-full-20260612-0926.log`. Failing file/test: unknown at first failure recording; helper exited code 1 after command #14 had passed. Focused triage command: `grep -E '^(PASS|FAIL):|\\[ERROR\\]|Exception|Error|^Running command #' /tmp/session-f-1to1-full-20260612-0926.log | tail -n 120` plus targeted tail around the first `FAIL:` marker. Decision/blocker: no production code edit is allowed until the failure is classified as a Sessions A-E scoped regression instead of external/device or unrelated simulator fragility. Next action: triage the redirected log and update this plan with classification before any fix.
- 2026-06-12 09:26 CEST - Phase: full simulator scope started. Files inspected or touched: this plan. Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1` with output redirected to `/tmp/session-f-1to1-full-20260612-0926.log`. Decision/blocker: pending full simulator scope; classification state not applicable until command exits. Next action: inspect log/exit status, then run host/named gates if green or record pending triage if red.
- 2026-06-12 09:26 CEST - Phase: targeted simulator proof passed. Files inspected or touched: this plan. Command completed: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only 9`. Result: pass; `integration_test/scripts/run_media_stable_id_smoke.dart` passed through `integration_test/media_stable_id_smoke_test.dart`, including `1:1 conversation open re-downloads missing media from stored attachment rows on simulator` with `MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED` and `MEDIA_DOWNLOAD_SUCCESS`. Decision/blocker: no simulator scenario extension or production-code fix is justified. Next action: run full helper-managed `1to1` reliability scope.
- 2026-06-12 09:22 CEST - Phase: targeted simulator proof started. Files inspected or touched: this plan. Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only 9`. Decision/blocker: pending targeted proof; classification state not applicable until command exits. Next action: on pass, run full `1to1`; on failure, write pending-triage details before focused rerun.
- 2026-06-12 09:22 CEST - Phase: required gate passed. Files inspected or touched: this plan. Command completed: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list`. Result: pass; helper resolved one-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, two-device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`, and a 20-command `1to1` plan. Decision/blocker: command 9 maps to `dart run integration_test/scripts/run_media_stable_id_smoke.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, so existing coverage satisfies the precondition for targeted proof. Next action: run `run_with_devices.sh 1to1 --only 9`.
- 2026-06-12 09:21 CEST - Phase: required gate started. Files inspected or touched: this plan. Command running: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list`. Decision/blocker: pending list pass; classification state not applicable until command exits. Next action: verify command 9 maps to `integration_test/scripts/run_media_stable_id_smoke.dart`.
- 2026-06-12 09:20 CEST - Phase: spawned Executor started. Files inspected or touched: this plan, session breakdown, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`, `scripts/run_test_gates.sh`, `scripts/run_reliability_simulations.sh`, `integration_test/scripts/run_media_stable_id_smoke.dart`, and `integration_test/media_stable_id_smoke_test.dart`. Command running: none. Decision/blocker: dirty worktree snapshot captured with many unrelated/prior-session modified and untracked files; Session F remains evidence-gated, and no production code will be edited unless a required gate failure is triaged to a Sessions A-E scoped regression. Next action: run the helper list pass and verify command 9 mapping.
- 2026-06-12 09:13 CEST - Phase: execution-controller intake before contract extraction. Files inspected or touched: orchestrator, reliability-sims, and graphify skill contracts; `graphify-arch` query for Session F evidence/gates; this plan and the session breakdown. Command running: none. Decision/blocker: execution contract extraction starting; spawned-agent availability still pending check. Next action: extract Session F scope/tests/gates from this plan, then attempt a fresh Executor spawn with `model=gpt-5.5` and `reasoning_effort=xhigh`.
- 2026-06-12 09:15 CEST - Phase: contract extracted. Files inspected or touched: this plan, session breakdown context, `Test-Flight-Improv/test-gate-definitions.md`, `Test-Flight-Improv/14-regression-test-strategy.md`, `scripts/run_test_gates.sh`, and `scripts/run_reliability_simulations.sh`. Command running: none. Decision/blocker: scope is evidence-gated Session F only; no production code edit is allowed unless a required gate failure is triaged to a Sessions A-E regression. Required gates are `run_with_devices.sh 1to1 --list`, `run_with_devices.sh 1to1 --only 9`, `run_with_devices.sh 1to1`, `./scripts/run_test_gates.sh 1to1`, explicit-device `transport`, `completeness-check`, scoped `git diff --check`, and `cd graphify-arch && graphify update .`; docs expected are the debug report, 1:1 closure reference, matrix rows DM-015/016/018/019, breakdown final ledger, and gate definitions only if classification changes. Next action: spawn the Executor in a fresh Codex process with the required model/effort.
- 2026-06-12 09:20 CEST - Phase: Executor spawned/running. Files inspected or touched: this plan. Command running: `codex exec -m gpt-5.5 -c model_reasoning_effort='"xhigh"' ...` for the Session F Executor. Decision/blocker: spawned-agent isolation is available; Executor child session `019ebab3-6386-7131-85f5-93bf0b6d610e` is running. Next action: wait for Executor final handoff, then spawn a separate QA Reviewer.

## Real Scope

Session F is the final evidence and documentation session for the 1:1 media-unavailable rollout. It must prove the landed Sessions A-E with simulator and named gate evidence, then update stable docs so future work knows which findings are fixed, refuted, residual-only, or still deferred.

In scope:

- Discover and use the current 1:1 reliability simulator command plan.
- Run at least one targeted 1:1 media recovery simulator proof before broad gates.
- Run the full 1:1 reliability simulator scope.
- Run named host gates required by the breakdown: `1to1`, `transport`, and `completeness-check`.
- Update `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Update `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Update `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`.
- Update `Test-Flight-Improv/test-gate-definitions.md` only if a new or reclassified integration/simulator test is added.

Out of scope:

- Reopening Sessions A-E implementation unless a required gate fails due to a landed regression.
- Group media, posts media, Move Account, notification product redesign, or broad transport rewrites.
- Adding a new simulator scenario if existing command-plan coverage already proves a 1:1 file-backed media recovery path.

## Closure Bar

Session F is acceptable only when all of these are true:

- The current 1:1 reliability list command passes and command numbers are recorded.
- A targeted simulator proof passes for a 1:1 media recovery path.
- The full 1:1 reliability simulator scope passes, or a real external/device blocker is recorded without overclaiming closure.
- `./scripts/run_test_gates.sh 1to1` passes.
- `./scripts/run_test_gates.sh transport` passes with an explicit device if the script requires one.
- `./scripts/run_test_gates.sh completeness-check` passes after doc/test classification.
- Closure docs record the fixed/refuted/deferred state of the original findings without treating host-only evidence as final simulator acceptance.
- The breakdown ledger records Session F and the final program verdict.

## Source Of Truth

- Current session contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`.
- Source plan: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Root-cause report to reconcile: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Named gates: `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; if they disagree, the script wins.
- Reliability simulator runner: `${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh`.
- Matrix rows: DM-015, DM-016, DM-018, and DM-019 in `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`.
- Maintenance closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Current code/tests beat stale prose if a doc conflicts with landed behavior.

## Session Classification

`evidence-gated`.

The session may finish with no production code change if existing simulator coverage passes. It must add or extend a simulator scenario only if the targeted inventory does not prove a file/video-backed 1:1 media recovery path or if the targeted proof fails because coverage is structurally insufficient.

## Exact Problem Statement

Sessions A-E landed the relay, receiver, local-WiFi fallback, retry/replay, and thumbnail-display fixes. Host tests prove their seams, but the source plan cannot close until the combined 1:1 media journey has simulator evidence and stable docs stop reading like open backlog. Session F must prove at least one 1:1 file/video recovery path in the reliability simulator suite, run the named gates, and reconcile the debug report/matrix/closure reference.

## Device/Relay Proof Profile

- Profile: `single-device` for targeted media recovery and full 1:1 simulator scope, with some full-scope commands using the helper-resolved two-device IDs.
- Live availability check already run through:
  - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list`
- Resolved one-device ID:
  - `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Resolved two-device IDs:
  - `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,38FECA55-03C1-4907-BD9D-8E64BF8E3469`
- Relay addresses:
  - `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
  - `/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g`
- Required closure evidence:
  - Targeted command `--only 9` because the current plan lists `integration_test/scripts/run_media_stable_id_smoke.dart`, and that file contains `1:1 conversation open re-downloads missing media from stored attachment rows on simulator`.
  - Full `1to1` scope through the helper so mixed one-device and two-device commands receive correct environment variables.
- `FLUTTER_DEVICE_ID` alone is not sufficient for the full reliability scope because commands 10, 12, 13, and 19 use two-device IDs; use the helper for full scope.

## Files And Repos To Inspect Next

- `integration_test/media_stable_id_smoke_test.dart`
- `integration_test/scripts/run_media_stable_id_smoke.dart`
- `integration_test/media_message_journey_e2e_test.dart`
- `integration_test/scripts/run_media_message_journey_e2e.dart`
- `scripts/run_reliability_simulations.sh`
- `scripts/check_reliability_simulation_discovery.sh`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## Existing Tests Covering This Area

- `integration_test/media_stable_id_smoke_test.dart` already contains `1:1 conversation open re-downloads missing media from stored attachment rows on simulator`, which proves an incoming 1:1 stored media row with a missing local file is recovered by `media:download`, ends with a done attachment, and avoids `Media unavailable`.
- `integration_test/media_stable_id_smoke_test.dart` also covers 1:1 stable media IDs, deleting the original file during upload, and voice optimistic attachment IDs.
- `integration_test/media_message_journey_e2e_test.dart` covers a real compose 1:1 image journey and GIF acceptance surfaces, but it is mainly happy-path delivery rather than recovery.
- `./scripts/run_test_gates.sh 1to1` covers the frozen host 1:1 reliability suite, including media attachment flow and media retry smoke.
- `./scripts/run_test_gates.sh transport` covers transport startup/local-discovery/media stable-id smoke surfaces.

## Regression/Proofs To Add First

No new simulator scenario is required before execution if targeted command `--only 9` passes and the full 1:1 scope still includes `integration_test/scripts/run_media_stable_id_smoke.dart`.

Add or extend a simulator proof only if execution discovers either of these:

- `--only 9` no longer targets `integration_test/scripts/run_media_stable_id_smoke.dart`.
- The existing stable-ID smoke no longer includes a 1:1 missing-media re-download scenario or no longer asserts recovered attachment state/no unavailable UI.

If an extension is required, add the smallest test to `integration_test/media_stable_id_smoke_test.dart` that proves direct 1:1 file-backed recovery using a failed/pending incoming attachment and a successful `media:download`, then re-run command `--only 9`.

## Step-By-Step Implementation Plan

1. Record a dirty worktree snapshot before execution.
2. Re-run the 1:1 reliability list pass and verify command 9 still maps to `integration_test/scripts/run_media_stable_id_smoke.dart`.
3. Run targeted simulator proof:
   - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only 9`
4. If targeted proof fails, triage first:
   - environment/device failure: record exact blocker, do not edit code.
   - structural missing scenario: add the minimal simulator proof described above.
   - product/test regression in Sessions A-E scope: fix only the failing owner seam and rerun targeted proof.
5. Run full simulator scope:
   - `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1`
6. Run host/named gates:
   - `./scripts/run_test_gates.sh 1to1`
   - `FLUTTER_DEVICE_ID=5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3 ./scripts/run_test_gates.sh transport`
   - `./scripts/run_test_gates.sh completeness-check`
7. Update the debug report with a rollout disposition section:
   - mark relay durability/failover, local-WiFi fallback, receiver orphan adoption, retry/replay repair, and thumbnail false-unavailable as fixed with session/test evidence.
   - keep direct encrypted media refutation as refuted unless new evidence changes it.
   - record any simulator/device limitations truthfully.
8. Update the stable 1:1 closure reference with direct-media recovery maintenance promises and reopen criteria.
9. Update matrix DM-015/DM-016/DM-018/DM-019 evidence notes without changing row vocabulary.
10. Update `test-gate-definitions.md` only if a new simulator test or classification was added.
11. Run `git diff --check` on touched Session F docs/tests.
12. Run `cd graphify-arch && graphify update .` after modifications; if that misses generated/native/platform docs touched by this session, use root graph fallback/update only for that gap.
13. Record final execution verdict in this plan and let closure update the breakdown ledger/final program verdict.

## Risks And Edge Cases

- The full 1:1 reliability scope has 20 commands and may fail on unrelated two-device notification/push smoke; failures must be classified before any fix.
- A single `FLUTTER_DEVICE_ID` can make paired commands invalid, so full scope must use the helper.
- `transport` may require explicit `FLUTTER_DEVICE_ID`; use the resolved one-device ID.
- Existing dirty worktree contains many unrelated changes; Session F must not revert or claim them.
- Host gates may surface unrelated modified-test failures from concurrent work. Classify them as unrelated only with focused evidence.
- Docs must not overclaim video-specific closure if the targeted simulator proof is image/file-backed recovery. Record video thumbnail and video playback support through Session E host/widget evidence and existing matrix wording.

## Exact Tests And Gates To Run

Required:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --only 9
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3 ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh completeness-check
git diff --check -- Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md Test-Flight-Improv/test-gate-definitions.md Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-F-plan.md Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md
cd graphify-arch && graphify update .
```

Conditional:

```bash
flutter test integration_test/media_stable_id_smoke_test.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3
dart run integration_test/scripts/run_media_stable_id_smoke.dart -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3
```

Use the conditional commands only for triage if `--only 9` fails and the helper output is not enough.

## Known-Failure Interpretation

- Device resolution failure is an environment blocker only if the helper reports missing required one-device or two-device IDs after a fresh list pass.
- Full 1:1 reliability failures outside media command 8/9 are blocking for final program closure unless triaged as pre-existing and unrelated with a narrower rerun or documented gate evidence.
- `baseline` is not required by this Session F plan because Session F is primarily evidence/doc closure unless it changes Flutter production code. If production code changes during a fix pass, add `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` or the current canonical baseline invocation required by `test-gate-definitions.md`.
- Root graph HTML export skips due graph size are non-blocking; `graphify update .` or `cd graphify-arch && graphify update .` JSON/report refresh is sufficient.

## Done Criteria

- The targeted simulator proof command passes or a truthful external blocker is recorded.
- The full 1:1 reliability simulator scope passes or a truthful external blocker prevents final closure.
- Required host gates pass.
- Source report, matrix, and closure reference are updated with concrete file/test/gate evidence.
- Any new simulator/test classification is reflected in `test-gate-definitions.md`, or the plan records that no classification change was needed.
- This plan records `Final execution verdict`.
- The breakdown marks Session F resolved and records a final program verdict.

## Scope Guard

Do not widen Session F into new transport architecture. Do not modify group media, posts media, account migration, or notification behavior unless a required full 1:1 reliability command fails in that exact surface and the fix is necessary to keep the required gate honest. Do not downgrade a required simulator failure into documentation-only acceptance.

## Accepted Differences / Intentionally Out Of Scope

- Existing targeted simulator recovery is file/image-backed rather than a full camera-video relay-restart test. This is acceptable only if docs explicitly preserve Session E's video-thumbnail proof and do not claim new video-playback simulator coverage beyond the existing matrix/gate evidence.
- Multi-relay and relay-restart behavior were proven in Go/direct host seams in Sessions A and transport gates; Session F's simulator target is the Flutter 1:1 media recovery journey, not live relay process orchestration.
- Full OS-suspended background retry remains outside the 1:1 closure reference unless a gate proves otherwise.

## Dependency Impact

Session F is the final dependency for the rollout. If it cannot run the required simulator or named gates, the overall doc verdict remains `still_open`. If it passes and docs are updated, the breakdown can move from `still_open` to `closed` or `accepted_with_explicit_follow_up` depending on any narrow residuals recorded by closure.

## Reviewer Findings

- Sufficiency: sufficient to execute.
- Missing files/tests/gates: none before execution; add or classify `integration_test/media_stable_id_smoke_test.dart` only if it is changed.
- Stale assumptions: the command number for media stable ID must be verified by a fresh list pass before `--only 9`.
- Overengineering risk: adding a new simulator when existing command 9 already proves file-backed recovery would add noise.
- Minimum needed: targeted command 9, full 1:1 reliability scope, required host gates, and stable doc reconciliation.

## Arbiter Decision

No structural blockers remain. The spawned planner no-progressed, but the breakdown entry was execution-safe and the local plan fallback now contains explicit scope, device profile, tests, gates, done criteria, known-failure handling, and scope guard.

## Final Execution Verdict

Blocked.

Session F did not meet the final closure bar because the required helper-managed full `1to1` simulator scope failed at command #19, the iOS notification tap UI smoke. The targeted media recovery proof passed, and the full rerun advanced through the media stable-ID proof plus the transport E2E media proof after a simulator-orchestrator-only fix in `integration_test/scripts/run_transport_e2e.dart`; however, the full helper exited code 65 on `./scripts/run_ios_notification_tap_ui_smoke.sh`, and a focused rerun of that same #19 command exited code 1 on the second simulator. Final source-report, matrix, closure-reference, and test-gate-definition updates were intentionally not applied because the required full simulator evidence is missing.
