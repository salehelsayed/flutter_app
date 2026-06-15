# 1:1 Media Unavailable Fixes - Session Breakdown

Status: reusable
Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
Decomposition date: 2026-06-11

## Decomposition Artifact Updated

- Artifact path: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`
- Proposal or source doc path: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
- Downstream workflow rule: detailed planning happens one session at a time; later sessions must be refreshed against landed code before execution.
- Intended plan path rule: every session plan path is doc-scoped next to the source doc and uses `one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-<session-id>-plan.md`.

## Recommended Plan Count

Recommended plan count: 6

Use five implementation sessions for the source plan's actual code/test seams, plus one evidence-gated simulator acceptance and closure session. The source doc's "five TDD sessions" remains correct for implementation work; this breakdown adds the sixth session because final simulator proof, source-report disposition, and matrix/closure updates validate multiple prior slices and should not be hidden inside any one implementation plan.

## Overall Closure Bar

The work is closed only when direct 1:1 image/video media no longer becomes permanently unavailable across relay restart, multi-relay `not found`, local-WiFi temporary receipt, receiver commit/orphan cleanup, direct retry, duplicate replay, and thumbnail-generation failure cases. Each new regression must fail first, pass after its owning implementation, focused Go/Flutter suites must pass, named host gates `1to1`, `transport`, and `completeness-check` must pass where applicable, and a 1:1 simulator reliability run must prove at least one file/video media recovery path.

## Source Of Truth

- Product intent and proposed tests: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Root-cause evidence: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Regression policy: `Test-Flight-Improv/14-regression-test-strategy.md`.
- Named gate execution source of truth: `Test-Flight-Improv/test-gate-definitions.md`.
- Existing 1:1 closure reference: `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`.
- Existing stable matrix: `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`, especially DM-015, DM-016, DM-018, and DM-019.
- Likely production and direct-test paths are taken from the source doc and source report in this bounded pass; production code and test files were not edited or re-read for implementation.

## Run Mode Snapshot

- Active mode: `standard`.
- Degraded local continuation explicitly allowed: no.
- Source proposal/matrix/closure doc path: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`, with final evidence expected to update `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`, and `Test-Flight-Improv/test-gate-definitions.md` only if classifications change.
- Source row/status vocabulary: source plan sessions are `implementation-ready` or `evidence-gated`; stable 1:1 media matrix rows use DM identifiers with proof-column values such as `Required`, `Recommended`, and `N/A`, not Open/Closed row status.
- Overall closure bar: direct 1:1 image/video media must stop becoming permanently unavailable across relay restart, multi-relay `not found`, local-WiFi temporary receipt, receiver commit/orphan cleanup, direct retry, duplicate replay, and thumbnail-generation failure cases, with focused Go/Flutter regressions, named host gates where applicable, and 1:1 simulator evidence.
- Final verdict policy: `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open` per the controller skill; use `still_open` if any required session remains blocked, required closure evidence is missing, or the overall closure bar is not met.

## Controller Progress

- 2026-06-11 18:11 - Session A intake started. Read pipeline and graphify skills, queried the existing graph, checked dirty worktree state, confirmed no reusable session plan files are present yet, and persisted the standard run-mode snapshot before planning.
- 2026-06-11 19:07 - Session A closure recorded. Spawned planner/execution/closure child attempts were made with `model: gpt-5.5` and `reasoning_effort: xhigh`; local fallback completed Session A after the spawned execution child produced no code/test evidence and the spawned closure child hung in an adjacent compile check. Verdict: `accepted_with_explicit_follow_up`; Session B may proceed.
- 2026-06-11 16:46 - Session B blocked before execution. The Session B planner child created a doc-scoped execution-ready plan draft, but the later Session B execution child failed immediately with a Codex CLI usage-limit lockout (`try again at Jul 11th, 2026 3:50 PM`). Because no fresh execution/QA child context is currently available and no isolated execution child materialized for the skill's local fallback, the current-doc pipeline is stopped at a real `spawn_or_tool_failure` block.
- 2026-06-11 18:58 - Session B closure audit recorded. Verified the Session B plan verdict, scoped owner-file diff, and regressions for canonical orphan adoption, not-found cleanup preservation, validation-failure preservation, and staged promotion after validation. Verdict: `accepted_with_explicit_follow_up`; Session C is the next ordered runnable session. No final source-report, matrix, or stable closure docs were updated because the breakdown keeps those Session F-owned.
- 2026-06-11 21:43 - Session C closure recorded via local closure fallback after the spawned closure child no-progressed. Verified the Session C plan verdict, scoped owner-file diff, RED/GREEN local-WiFi and voice regressions, `1to1`, explicit-device `transport`, `graphify update .`, and diff checks. Verdict: `accepted_with_explicit_follow_up`; Session D is the next ordered runnable session. No final source-report, matrix, or stable closure docs were updated because the breakdown keeps those Session F-owned.
- 2026-06-11 23:22 - Session D closure audit recorded. Verified the Session D plan verdict, scoped owner-file diff, and direct regressions for incoming unavailable retry wiring, targeted `DownloadMediaUseCase` retry with attachment-level dedupe, duplicate replay media repair, and stale initial-page merge preservation. Verdict: `accepted_with_explicit_follow_up`; Session E is the next ordered runnable session. No final source-report, matrix, or stable closure docs were updated because the breakdown keeps those Session F-owned.
- 2026-06-11 23:52 - Session E closure audit recorded. Verified the Session E plan verdict, scoped owner-file diff, RED/GREEN thumbnail fallback evidence, failed/pending/missing-file guard coverage, full media widget suites, media grid/feed/attachment preview compatibility, recommended `1to1`, format/diff checks, and `graphify update .` completion with HTML skipped due graph size. Verdict: `accepted_with_explicit_follow_up`; Session F is the next ordered runnable evidence-gated session. No final source-report, matrix, or stable closure docs were updated because the breakdown keeps those Session F-owned.
- 2026-06-12 11:46 - Session F Executor blocked before closure. Targeted media recovery proof passed and full `1to1` progressed through the media stable-ID proof plus the transport E2E media proof after a simulator-orchestrator-only fix in `integration_test/scripts/run_transport_e2e.dart`; however, the required full helper-managed `1to1` simulator scope failed at command #19 `./scripts/run_ios_notification_tap_ui_smoke.sh` on the second simulator `38FECA55-03C1-4907-BD9D-8E64BF8E3469`. Focused #19 rerun reproduced the second-simulator notification UI/XCTest harness failure and then timed out during retry warm readiness. Verdict: `still_open`; final source-report, matrix, closure-reference, and gate-definition updates remain deferred because required full simulator evidence is missing.

## Session Ledger

| Session id | Title | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- |
| A | Relay Media Durability And Failover | implementation-ready | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-A-plan.md` | None | accepted_with_explicit_follow_up |
| B | Receiver Commit And Orphan Adoption | implementation-ready | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-B-plan.md` | A for ordered rollout | accepted_with_explicit_follow_up |
| C | Local-WiFi Durable Fallback | implementation-ready | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-C-plan.md` | B for ordered rollout | accepted_with_explicit_follow_up |
| D | Retry And Duplicate Replay Repair | implementation-ready | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-D-plan.md` | C for ordered rollout | accepted_with_explicit_follow_up |
| E | Thumbnail Failure Is Not Media Unavailable | implementation-ready | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-E-plan.md` | D for ordered rollout | accepted_with_explicit_follow_up |
| F | Simulator Acceptance And Closure | evidence-gated | `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-F-plan.md` | A, B, C, D, E | blocked_external_device_ui_harness |

## Session Ledger Deltas

- 2026-06-11 19:07 - Session A accepted with explicit follow-up. Code/test files changed for this session: `go-relay-server/media.go`, `go-relay-server/media_test.go`, `go-mknoon/node/media.go`, `go-mknoon/node/media_test.go`, and `go-mknoon/integration/media_test.go` formatting/API adaptation. Gates/evidence: `cd go-relay-server && go test ./...` passed; `cd go-mknoon && go test -tags=integration ./integration` passed; `cd go-mknoon && go test ./node -run 'Test(Media|PL013|PL014|IdleTimeout)'` passed; `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed after the first no-device-selection run failed. Non-blocking follow-up: broad `cd go-mknoon && go test ./node` times out in `TestRefreshRelaySession_PreservesPubSubMaps`, and adjacent `go-mknoon/bridge`/`go-mknoon/cmd/testpeer` compile verification hung in the spawned closure child. Session B is unblocked because the direct media custody/failover closure bar is satisfied.
- 2026-06-11 16:46 - Session B blocked before code execution. Plan artifact: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-B-plan.md`. Status: `blocked`. Blocker class: `spawn_or_tool_failure`. Exact blocker: required fresh Session B execution/QA child context cannot be created because `codex exec` exits with the usage-limit lockout before doing work. No Session B production code was changed by this pipeline pass; C-F were not started because ordered rollout depends on B.
- 2026-06-11 18:58 - Session B accepted with explicit follow-up, superseding the earlier `blocked_spawn_or_tool_failure` state. Changed owner files: `lib/features/conversation/application/download_media_use_case.dart` and `test/features/conversation/application/download_media_use_case_test.dart`. Added/updated regressions: canonical orphan adoption, not-found cleanup preservation, validation-failure preservation, and staged promotion after validation. Evidence verified from the plan and scoped diff: RED plain-name failures before implementation, focused regressions green, full `flutter test test/features/conversation/application/download_media_use_case_test.dart` passed, `./scripts/run_test_gates.sh 1to1` passed, unqualified `baseline` was classified as device-selection failure, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed, `graphify update .` completed, and `git diff --check` passed. Residual follow-up: Session F still owns simulator acceptance and final source-report/matrix/closure updates; Session C may proceed next.
- 2026-06-11 21:43 - Session C accepted with explicit follow-up. Changed owner files: `lib/features/conversation/presentation/screens/conversation_wired.dart` and `test/features/conversation/presentation/screens/conversation_wired_test.dart`; `test/features/conversation/application/link_incoming_local_media_use_case_test.dart` was part of the direct evidence run. Added/updated regressions: local-peer GIF transfer now proves `sendLocalMedia` happens before relay `uploadMedia` with the same stable media ID; voice local transfer now proves `sendLocalMedia` happens before relay `sendVoiceMessageFn` with the same optimistic attachment ID. Evidence verified from the plan and scoped diff: RED plain-name failures before implementation, focused regressions green, `--plain-name "voice"` passed after fixture alignment, `flutter test test/features/conversation/application/link_incoming_local_media_use_case_test.dart` passed, full `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` passed, `./scripts/run_test_gates.sh 1to1` passed, `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed, `graphify update .` completed, and `git diff --check` passed. Residual follow-up: Session F still owns simulator acceptance and final source-report/matrix/closure updates; Session D may proceed next.
- 2026-06-11 23:22 - Session D accepted with explicit follow-up. Changed owner files verified for this session: `lib/features/conversation/presentation/screens/conversation_screen.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, `test/features/conversation/presentation/screens/conversation_screen_test.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, and `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`; `test/features/conversation/application/chat_message_listener_test.dart` was a direct-suite evidence file, but its visible local diff is adjacent/unrelated helper/test churn and is not claimed as a Session D regression addition. Added/updated regressions: incoming unavailable-media retry callback wiring, targeted direct unavailable retry through `DownloadMediaUseCase` with per-attachment in-flight dedupe, duplicate replay media repair without duplicate message insertion, and stale initial-page merge preservation. Evidence verified from the plan and scoped diff: RED plain-name failures before implementation, focused regressions green, full `conversation_screen_test.dart`, `conversation_wired_test.dart`, `chat_message_listener_test.dart`, and `handle_incoming_chat_message_use_case_test.dart` passed, `./scripts/run_test_gates.sh 1to1` passed, `dart format` reported no further changes across touched Dart files, and `git diff --check -- <touched Session D files>` passed. Resume recovery is accepted as not applicable for Session D because no existing incoming direct media download resume path was present to extend without adding new lifecycle infrastructure. Residual follow-up: rerun `graphify update .` later if a clean graph refresh is required; the attempted rerun completed AST extraction but did not return cleanly and is non-blocking. Session F still owns simulator acceptance and final source-report/matrix/closure updates; Session E may proceed next.
- 2026-06-11 23:52 - Session E accepted with explicit follow-up. Changed owner files verified for this session: `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `test/shared/widgets/media/media_grid_cell_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`, and `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-E-plan.md`. Pre-existing dirty edits in `lib/features/conversation/presentation/widgets/letter_card.dart`, `test/features/conversation/presentation/widgets/letter_card_test.dart`, and upload-pending portions of the shared media files are preserved and not claimed as Session E closure evidence. Added/updated regressions: existing-source video thumbnail-null fallback/play affordance, thumbnail-null missing-source error mapping, failed-video unavailable retry, missing-file done video unavailable guard, and pending-video loading guard. Evidence verified from the plan and scoped diff: RED evidence for the primary thumbnail-failure behavior after adding a deterministic resolver seam, missing-file and pending-video RED before implementation, failed-video retry already-green guard, all required plain-name checks green, full `media_grid_cell_test.dart` and `media_thumbnail_image_test.dart` green, conditional `media_grid_test.dart`, feed collapsed-card thumbnail plain-name suite, and `attachment_preview_strip_test.dart` green, recommended `./scripts/run_test_gates.sh 1to1` passed, `dart format` completed on touched Dart files, scoped `git diff --check` passed, and `graphify update .` completed while skipping HTML because the graph exceeded the 5000-node visualization limit. Residual follow-up: Session F still owns simulator acceptance, final combined source-report/matrix/closure-reference updates, and any final gate-definition classification; Session F may proceed next as the ordered evidence-gated session.
- 2026-06-12 11:46 - Session F blocked by required simulator UI smoke. Executor-owned code/test change: `integration_test/scripts/run_transport_e2e.dart` was adjusted only in simulator orchestration so E8 can accept a retained exact media-envelope proof when B8 drains the same inbox batch first; focused transport E2E passed after the change. Targeted command `run_with_devices.sh 1to1 --only 9` passed and proved missing local media re-download through `integration_test/scripts/run_media_stable_id_smoke.dart`. Full `run_with_devices.sh 1to1` rerun passed commands #1-#18, including #9 and #15 after the simulator-orchestrator fix, then failed at #19 iOS notification tap UI smoke. Focused #19 rerun passed first-simulator warm one-to-one and group notification tap scenarios, but second-simulator warm one-to-one failed at `ios/RunnerUITests/NotificationTapUITests.swift:99` (`Could not re-tap a Springboard notification...`) despite native/Flutter open markers, and retry timed out waiting for warm app node readiness. Final status: `blocked_external_device_ui_harness`; no final source-report/matrix/closure-reference docs were closed.

## Current Doc Verdict

- 2026-06-11 23:52 - Verdict: `still_open`. Sessions A, B, C, D, and E are accepted with explicit follow-up, and Session F is now the next ordered runnable evidence-gated session. Session F remains unresolved and still owns simulator acceptance plus final source-report, matrix, gate-definition classification if needed, and stable closure-reference updates, so the overall 1:1 media-unavailable source plan is not closed by Session E host/widget evidence alone.
- 2026-06-12 11:46 - Verdict: `still_open`. Sessions A-E remain accepted with explicit follow-up, but Session F is blocked by the required full `1to1` simulator scope at #19 iOS notification tap UI smoke on the second simulator. The source plan is not closed; final source-report, matrix, closure-reference, and any gate-definition updates remain pending until full simulator acceptance is rerun successfully or the notification UI smoke blocker is separately resolved and accepted by QA.

## Ordered Session Breakdown

### Session A: Relay Media Durability And Failover

- Session id: A
- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-A-plan.md`
- Exact scope: Persist relay media metadata beside blobs, rebuild relay media indexes after restart, protect same-ID replacement with staging/rename, align direct media count retention with direct inbox retention, preserve `not found` and `not authorized` error contracts, and make Go media download try later relays on media miss while keeping authorization failures terminal.
- Why it is its own session: This is the relay/Go transport seam. It has Go-only direct regressions and a different blast radius from Flutter receiver/UI work.
- Likely code-entry files: `go-relay-server/media.go`, `go-relay-server/main.go`, `go-relay-server/server_bootstrap.go`, `go-mknoon/node/media.go`.
- Likely direct tests/regressions: `go-relay-server/media_test.go`, `go-mknoon/node/media_test.go`, `go-mknoon/integration/media_test.go`; add restart durability, same-ID incomplete replacement, count-cap alignment, error-string contract, multi-relay `not found` failover, and corrupt sidecar tolerance if metadata format changes.
- Likely named gates: focused `go test ./go-relay-server`, `go test ./go-mknoon/node`, `go test -tags=integration ./go-mknoon/integration`; later `./scripts/run_test_gates.sh transport` and final 1:1 simulator evidence.
- Matrix/closure docs to update when done: Defer final matrix/closure edits to Session F unless this session adds or reclassifies a test file that requires `Test-Flight-Improv/test-gate-definitions.md` completeness classification.
- Dependency on earlier sessions: None.

### Session B: Receiver Commit And Orphan Adoption

- Session id: B
- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-B-plan.md`
- Exact scope: Make `DownloadMediaUseCase` adopt a valid existing canonical file before bridge download, preserve pre-existing canonical files on relay `not found` and validation failure, and promote staged downloads only after hash/size validation when feasible.
- Why it is its own session: This is the Flutter receiver persistence and cleanup seam. It can be verified with focused application tests without touching sender local-WiFi or UI retry wiring.
- Likely code-entry files: `lib/features/conversation/application/download_media_use_case.dart`.
- Likely direct tests/regressions: `test/features/conversation/application/download_media_use_case_test.dart`; add canonical orphan adoption, no deletion of pre-existing canonical file on `not found`, no deletion after validation failure, and staged-promotion coverage if staging is introduced.
- Likely named gates: focused Flutter application test above; `./scripts/run_test_gates.sh 1to1` in the session or final closure; `./scripts/run_test_gates.sh baseline` if Flutter production code changes and the planner requires baseline.
- Matrix/closure docs to update when done: Defer final 1:1 closure wording to Session F; no new matrix doc.
- Dependency on earlier sessions: A for ordered rollout; no hard code dependency unless the planner chooses to couple receiver cleanup with relay delete semantics.

### Session C: Local-WiFi Durable Fallback

- Session id: C
- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-C-plan.md`
- Exact scope: Ensure local-WiFi media transfer success is only a fast local optimization, not the only durable copy, unless a durable receiver ACK is implemented after receiver DB/local-path persistence. The default fix is to keep relay upload fallback after local transfer success.
- Why it is its own session: This is the sender/local-discovery handoff seam. It needs conversation wiring and local-media tests, and it has a transport/local-discovery gate contract distinct from Session B's receiver cleanup.
- Likely code-entry files: `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/conversation/application/link_incoming_local_media_use_case.dart`, `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_media_server.dart`.
- Likely direct tests/regressions: `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`; add local-WiFi success still uploads relay fallback without durable ACK, durable ACK skip only if implemented, and receiver persistence failure keeps or creates relay fallback.
- Likely named gates: focused Flutter tests above; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh transport` because local discovery, transport fallback, and media stable-id behavior may be affected.
- Matrix/closure docs to update when done: Defer final 1:1 media matrix/closure updates to Session F; update `Test-Flight-Improv/test-gate-definitions.md` only if new tests need classification.
- Dependency on earlier sessions: B for ordered rollout and to keep receiver persistence semantics settled before sender fallback assumptions.

### Session D: Retry And Duplicate Replay Repair

- Session id: D
- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-D-plan.md`
- Exact scope: Wire incoming direct unavailable-media retry through the direct conversation UI, implement targeted receiver retry using `DownloadMediaUseCase`, repair failed/pending media on duplicate envelope replay without inserting duplicates, prevent stale initial-page loads from overwriting newer repair state, and add resume recovery only if an existing app-resume media path is present.
- Why it is its own session: This is the receiver recovery/UI-state seam. It depends on the lower-level download and fallback behavior being stable, and it needs presentation plus listener/use-case regressions rather than relay or thumbnail tests.
- Likely code-entry files: `lib/features/conversation/presentation/screens/conversation_screen.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/conversation/application/chat_message_listener.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`.
- Likely direct tests/regressions: `test/features/conversation/presentation/screens/conversation_screen_test.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/conversation/application/chat_message_listener_test.dart`, `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`; add incoming retry callback, direct retry download/refresh, duplicate replay repair, stale initial page merge, and resume dedupe if applicable.
- Likely named gates: focused Flutter application/presentation tests above; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh completeness-check` if test inventory changes require classification.
- Matrix/closure docs to update when done: Defer final closure update to Session F; this session maps most directly to matrix DM-019 media retry without duplicates.
- Dependency on earlier sessions: C for ordered rollout so retry repairs recover against the durable media paths established earlier.

### Session E: Thumbnail Failure Is Not Media Unavailable

- Session id: E
- Session classification: implementation-ready
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-E-plan.md`
- Exact scope: Separate video thumbnail decode/generation failure from true media unavailability. Done video attachments with a valid local path should render a video fallback/play affordance; failed, pending, or missing-file attachments should still show unavailable/loading states and retry where appropriate.
- Why it is its own session: This is a display-policy seam. It has widget-focused regressions and should not be bundled with the deeper receiver retry implementation because it can be proven independently.
- Likely code-entry files: `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/media_thumbnail_image.dart`, `lib/core/media/video_thumbnail_cache.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart`.
- Likely direct tests/regressions: `test/shared/widgets/media/media_grid_cell_test.dart`, `test/shared/widgets/media/media_thumbnail_image_test.dart`, optional focused conversation widget test; add video thumbnail failure shows video fallback, and true failed media still shows unavailable retry.
- Likely named gates: focused media widget tests; `./scripts/run_test_gates.sh 1to1` in final combined validation because the visual false-unavailable state affects direct 1:1 media trust.
- Matrix/closure docs to update when done: Defer final matrix/closure updates to Session F; this session supports DM-016 video send/receive/playback and DM-019 media retry clarity.
- Dependency on earlier sessions: D for ordered rollout; no hard code dependency unless retry affordance rendering is refactored in D.

### Session F: Simulator Acceptance And Closure

- Session id: F
- Session classification: evidence-gated
- Intended plan file: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-F-plan.md`
- Exact scope: Discover available 1:1 simulator scenarios, add or extend a 1:1 media journey scenario if no discovered scenario covers file/video media retry or recovery, run targeted simulator proof first, run the full 1:1 reliability simulator gate, run required named host gates, and update the source report plus stable matrix/closure docs with fixed/refuted/deferred status.
- Why it is its own session: This validates multiple prior slices and owns final documentation. It cannot be planned safely until Sessions A-E have landed and the current simulator inventory is known.
- Likely code-entry files: simulator discovery or scenario files only if the evidence pass proves a new/extended scenario is required; otherwise none.
- Likely direct tests/regressions: `integration_test/media_message_journey_e2e_test.dart` or an existing/discovered 1:1 reliability simulator scenario; acceptance scenario must cover relay restart before receiver download, first-relay miss with second-relay success, local-WiFi plus relay fallback retry, or canonical orphan adoption.
- Likely named gates: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list`, targeted simulator scenario, `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1`, `./scripts/run_test_gates.sh 1to1`, `./scripts/run_test_gates.sh transport`, and `./scripts/run_test_gates.sh completeness-check`.
- Matrix/closure docs to update when done: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md` for fixed/refuted/deferred findings; `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` if the corrected direct-media recovery behavior changes closure wording; `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md` for DM-015/DM-016/DM-018/DM-019 evidence or coverage notes if needed; `Test-Flight-Improv/test-gate-definitions.md` if any new test/scenario requires classification.
- Dependency on earlier sessions: A, B, C, D, and E.

## Why This Is Not Fewer Sessions

Fewer than six sessions would either combine Go relay durability with Flutter receiver recovery, combine sender local-WiFi behavior with receiver retry/UI state, or hide simulator acceptance and closure documentation inside an implementation slice. Those combinations would mix different gates, different direct test families, and different rollback surfaces. The acceptance/closure pass is intentionally separate because unit/widget tests cannot prove the recorded 1:1 file/video journey or restart/failover behavior by themselves.

## Why This Is Not More Sessions

More sessions would mostly split individual tests from the same seam. Relay restart, same-ID replacement, direct media cap alignment, error-contract pinning, and node failover all belong to the same relay/media custody contract. Receiver orphan adoption and cleanup are one `DownloadMediaUseCase` contract. Retry wiring, duplicate replay repair, and stale page merge all repair the same direct incoming failed-media state. Splitting those further would add bookkeeping without leaving independently meaningful verified states.

## Regression And Gate Contract

`Test-Flight-Improv/14-regression-test-strategy.md` requires every production bug to add a permanent regression first, run the direct suite for changed files, and run the relevant subsystem gate for shared messaging changes. `Test-Flight-Improv/test-gate-definitions.md` is the execution source of truth for named gates.

Across this session set:

- Each implementation session must add the owning failing regression before implementation.
- Shared 1:1 send, retry, upload, listener, or inbox changes require `./scripts/run_test_gates.sh 1to1`.
- Bridge, resume, reconnect, transport fallback, local discovery, or app-bootstrap changes require `./scripts/run_test_gates.sh transport`.
- New or reclassified test files require `./scripts/run_test_gates.sh completeness-check` and, if needed, `Test-Flight-Improv/test-gate-definitions.md` updates.
- Device-backed simulator acceptance remains final closure evidence; host tests alone cannot close the source plan.

## Matrix Update Contract

Do not create a new matrix doc. Reuse the existing stable docs:

- `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md` for direct 1:1 media rows DM-015 image, DM-016 video, DM-018 offline media, and DM-019 media retry without duplicates.
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` for the maintained 1:1 reliability closure bar.
- `Test-Flight-Improv/test-gate-definitions.md` only if the session adds or reclassifies tests/scenarios.

Session F owns final matrix/closure/source-report updates after all implementation evidence is available.

## Downstream Execution Path

Each session should be processed independently and in order:

| Session id | Next downstream path |
| --- | --- |
| A | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| B | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| C | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| D | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| E | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |
| F | `$implementation-plan-orchestrator` -> `$implementation-execution-qa-orchestrator` -> `$implementation-closure-audit-orchestrator` |

Later sessions must refresh their plan against landed code before execution. Session F must refresh against final simulator discovery and all landed A-E changes.

## Reviewer Questions

- Recommended session count sufficiency: 6 is sufficient; 5 would drop final acceptance/closure ownership, and more would fragment same-seam regressions.
- Sessions to merge: None.
- Sessions that must split: None.
- Missing tests or named gates: No structural missing gate; final simulator evidence is prerequisite-blocked until Session F lists scenarios and either finds or creates coverage.
- Meaningful verified state: Each implementation session ends with focused failing-then-passing regressions; Session F ends with simulator and doc closure evidence.
- Matrix-update responsibility: Session F owns final source-report, matrix, closure, and gate-definition updates.
- Minimum safe session set: Six sessions.

## Structural Blockers Remaining

None for decomposition. Session F is prerequisite-blocked by design until Sessions A-E land and simulator discovery runs.

## Accepted Differences Intentionally Left Unchanged

- The source doc says five TDD sessions; this breakdown treats those as implementation sessions and adds a sixth acceptance/closure session for downstream orchestration safety.
- The default Session C fix remains relay fallback after local-WiFi success unless a durable receiver ACK is intentionally implemented in that session.
- Legacy relay blobs without metadata after restart remain an accepted rollout difference unless a later implementation plan chooses a safe migration path.
- TTL and byte-cap eviction remain explicit storage-policy residuals; only the direct count cap must not undercut direct inbox retention.
- Group media, public post media, encryption protocol changes, and broad local-discovery rewrites remain out of scope.

## Exact Docs/Files Used As Evidence

Docs read or queried in this decomposition:

- `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
- `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`

Likely code/test entry files named by those docs:

- `go-relay-server/media.go`
- `go-relay-server/main.go`
- `go-relay-server/server_bootstrap.go`
- `go-mknoon/node/media.go`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/link_incoming_local_media_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `go-relay-server/media_test.go`
- `go-mknoon/node/media_test.go`
- `go-mknoon/integration/media_test.go`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/shared/widgets/media/media_thumbnail_image_test.dart`
- `integration_test/media_message_journey_e2e_test.dart`

## Why The Decomposition Is Safe To Send Into Downstream Planning/Execution

The split follows the actual seams named by the source plan and existing closure/gate docs: relay/Go media custody, Flutter receiver file commit, local-WiFi sender fallback, direct retry/replay recovery, thumbnail display policy, and final simulator/doc closure. Each session has a doc-scoped plan path, a narrow direct regression family, an explicit gate contract, and a clear dependency point. No implementation pipeline work, production code, or tests were edited during decomposition.
