Status: reusable-breakdown

# 102 - Group Image Retry Duplicate Delivery Notifications Media UX Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- Decomposition date:
  `2026-05-31`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution
  - no session may broaden beyond the source spec's group image retry, duplicate delivery, notification, and media unavailable acceptance gaps
  - every source-spec acceptance gap must end as `closed`, `residual-only` with explicit follow-up, or `blocked` with evidence

## recommended plan count

- `7`
- The smallest safe split is:
  - `1` implementation session for sender in-doubt reliable-send classification and same-id sender reconciliation
  - `1` implementation session for sender retry ownership across failed-card retry, restored composer send, upload-pending media retry, app resume, and already-open UI refresh
  - `1` implementation session for Flutter recipient logical-dedupe and attachment row stability
  - `1` implementation session for relay/native group inbox idempotency and durable push fanout boundaries
  - `1` implementation session for media unavailable/loading display semantics
  - `1` implementation session for Android/iOS repo-level notification display, suppression, dedupe, mute, active-group, and tap-routing behavior
  - `1` acceptance/closure session for incident reproduction, simulator/device evidence, final gates, and matrix/docs classification

## decomposition progress

Latest role progress entries retained for controller handoff:

| Phase | Docs/files inspected so far | Current next action |
|---|---|---|
| Evidence Collector | Source spec; `14-regression-test-strategy.md`; `test-gate-definitions.md`; group closure docs; notification and group matrices; group send/retry/listener/UI code; relay group inbox code; media display widgets; push/NSE notification code; direct test inventory by `rg` | Map acceptance gaps into session-owned closure targets without broadening beyond the spec. |
| Closure Mapper | Source acceptance gaps, current group reliability closure reference, notification journey matrix, group test inventory, current code/test seams | Convert gaps into closure bars and identify where existing coverage is partial versus missing. |
| Session Splitter | Code/test ownership boundaries across Flutter sender, Flutter recipient, Go relay/native, media widgets, push/NSE, simulator/device acceptance | Split by independently verifiable seam and named gate family. |
| Reviewer | Proposed seven-session set, source acceptance bullets, named gates, matrix-doc update responsibility | Seven sessions are sufficient; no merge is safe across sender, relay, media, notification, and final acceptance seams. |
| Arbiter | Reviewer findings and session ledger | No structural blockers remain; accepted differences are documented below. |

## overall closure bar

This rollout is closed only when all of the following are true at the same time:

- one user-intended group image send remains one visible image message for every eligible recipient across reliable-send timeout, weak peer evidence, failed-card retry, app resume, close/reopen, restored composer continuation, live pubsub delivery, and group inbox replay
- the sender is not left with a permanent misleading failed state after delivery evidence, same-id own replay, durable custody, or retry success proves the logical send resolved
- failed-card retry, incomplete-upload retry, failed-message retry, and restored composer send cannot race into multiple recipient-visible copies for the same logical group image
- recipient timelines dedupe same-message-id live/inbox replays and any source-spec-supported same-logical-send duplicate path without collapsing clearly intentional separate successful sends of the same image
- relay group inbox storage and push fanout do not materialize repeated durable store attempts for one logical group message as duplicate recipient-visible rows or duplicate notifications
- retryable media loading, failed-download recovery, and done-but-not-yet-verifiably-displayable group media do not show terminal `Media unavailable`, while truly unsafe or terminal media still does
- Android foreground/background, active-group, muted-group, duplicate, display-failure, and notification-tap behavior maps one logical group image send to one eligible visible notification path
- iOS repo-level APNs payload, NSE preview/fallback, duplicate same-id versus re-minted-id behavior, and notification-open routing are proven; the narrow real APNs background/terminated device-context path is either closed with evidence or classified residual-only/blocked with exact evidence
- final acceptance includes focused unit/integration proof, the three-user incident regression, simulator evidence for group image retry and notification behavior, the required host and reliability gates from the source spec, and truthful updates to stable matrix/closure docs

## Run Mode Snapshot

- Last refreshed: `2026-05-31 17:39 CEST`
- Active mode: `implementation-committed gap-closure`
- GIRD-005 local continuation:
  `completed after user instructed to stop after finishing GIRD-005; do not infer local continuation permission for later sessions`
- Source proposal, matrix, or closure doc path:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- Source row/status vocabulary:
  - unresolved source gaps are the acceptance gap families above plus the
    source doc's `Missing acceptance evidence` bullets
  - accepted source statuses for this run are `Closed`/`Covered` only when
    concrete file-and-test evidence is recorded
  - final gap classifications allowed by the source doc are `closed`,
    `residual-only with explicit follow-up`, or `blocked with evidence`
- Overall closure bar:
  all source acceptance gaps must be closed by row-owned session evidence, or
  explicitly classified as residual-only/blocking evidence during `GIRD-007`;
  row-owned implementation sessions may not finish accepted while their owned
  gap remains open or partially evidenced.
- Final verdict policy:
  use the pipeline verdict vocabulary `closed`,
  `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; in this
  implementation-committed run, `closed` requires every row-owned source gap to
  be updated to closed/covered with concrete evidence, and unresolved row-owned
  gaps force `still_open`.

## source of truth

Primary governing docs:

- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`

Current repo facts that govern the split:

- `lib/core/bridge/bridge_group_helpers.dart` gives `group:sendReliable` a Dart-side 10 second timeout and returns an `ok: false`, `BRIDGE_TIMEOUT` map on timeout.
- `go-mknoon/node/config.go` has longer native group inbox and pubsub timeouts, and `go-mknoon/node/pubsub.go` waits on native pubsub/inbox work for reliable sends. This creates an in-doubt sender state that is not equivalent to proven non-delivery.
- After accepted `GIRD-001` execution, `lib/features/groups/application/send_group_message_use_case.dart` pre-persists `sending`, then classifies reliable `BRIDGE_TIMEOUT` and reliable `publishSucceeded && zero topic peers && !inboxStored` as in-doubt non-failed `pending` sender state under the original message id.
- After accepted `GIRD-002` execution, `lib/features/groups/presentation/screens/group_conversation_wired.dart` still creates a fresh UUID and timestamp for normal composer sends, but restored failed group media continuations track group, original message id/timestamp, draft, quote, and attachment fingerprint. An unchanged continuation reuses the original row id/timestamp; if the row has already settled non-failed, the screen refreshes row/media and clears the restored composer instead of publishing.
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` retries failed rows with the original message id when attachments are `done`, and still treats `upload_pending` media as owned by incomplete-upload recovery. After accepted `GIRD-002` execution, the failed-card UI path intercepts selected `upload_pending` rows, shows localized pending-upload feedback, refreshes row/media, and does not publish or call the failed-message retry owner.
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, `lib/core/lifecycle/handle_app_resumed.dart`, and `lib/core/services/pending_message_retrier.dart` can run incomplete-upload and failed-message retry flows during recovery. `GIRD-002` evidence preserves incomplete-upload-before-failed-message ordering and late final-send abort when another owner has already settled the row.
- After accepted `GIRD-001` execution, `lib/features/groups/application/handle_incoming_group_message_use_case.dart` dedupes stable incoming messages by `messageId`, preserves distinct stable ids with the same content/timestamp, and reconciles own-message replay for `sending`/`pending` outgoing rows plus failed outgoing rows that carry retry recovery evidence.
- After accepted `GIRD-002` execution, an already-open `GroupConversationWired` reloads current messages/media on app resume and after group recovery gate completion, so same-id sender retry status/media changes can surface without closing and reopening the group screen.
- After accepted `GIRD-003` execution, `lib/features/groups/application/handle_incoming_group_message_use_case.dart` applies recipient-side logical media retry dedupe before duplicate attachment save: an exact envelope match plus strict media identity enriches the canonical row and returns `null`. Intentional separate image sends with distinct media identity still persist. `lib/features/groups/application/group_message_listener.dart` required no production change; focused listener evidence covers the re-minted group image retry emitting and notifying once without claiming final notification behavior.
- `lib/features/groups/application/group_message_listener.dart` emits the incoming group message before fire-and-forget media auto-download, then re-emits after download so UI can refresh.
- `lib/shared/widgets/media/media_grid_cell.dart` renders unavailable when group media is failed, integrity failed, upload failed/cancelled, invalid, or missing required verified metadata; pending/downloading uses loading UI.
- `go-relay-server/backend_memory.go` and `go-relay-server/backend_redis.go` append group inbox store requests with new sequence ids; existing 1:1 inbox dedupe does not prove group inbox same-logical-message idempotency.
- After accepted `GIRD-004` blocker-resolution execution, `go-relay-server/backend_memory.go`, `go-relay-server/backend_redis.go`, `go-relay-server/group_inbox_store.go`, and `go-relay-server/inbox.go` make exact keyed duplicate group inbox stores idempotent, reject conflicting same-id sender/body rows, merge recipient ACLs for exact duplicates, and suppress duplicate push fanout. Native `go-mknoon` preservation evidence is green after narrow stale-test/native validation fixes in `go-mknoon/node/group_inbox_test.go`, `go-mknoon/node/multi_relay_test.go`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/pubsub_test.go`.
- After accepted `GIRD-005` local continuation, `lib/core/media/group_media_integrity_policy.dart` separates required verification metadata from displayable local-path availability, so verified `done` group media without a local path is resolving rather than terminal unavailable. `GroupConversationWired` stages valid visible failed/pending recovery as `downloading` before awaiting download, normalizes verified done/no-path media to recoverable pending, and keeps unsafe, unverifiable, quarantined, upload-failed/cancelled, invalid, or oversized media terminal. Focused GIRD-005 policy/widget/wired tests, direct preservation suites, `./scripts/run_test_gates.sh groups`, and `git diff --check` passed. Go relay/native deltas are not claimed as GIRD-005 evidence; they are governed by accepted `GIRD-004`.
- After accepted `GIRD-006` execution, `lib/features/push/application/background_message_handler.dart` still marks recent remote announcements immediately for visible FCM notification pushes, but data-only group fallback marks the recent remote gate only after local fallback display succeeds. A failed local fallback display no longer suppresses later in-app local replay.
- After accepted `GIRD-006` execution, Flutter focused tests cover canonical group route payloads, background fallback duplicate coalescing, display-failure replay preservation, foreground group push drain, local replay exact-id suppression, and notification tap route preparation.
- After accepted `GIRD-006` execution, `go-relay-server/inbox_test.go` proves group image push messages use canonical data-only identity, and `ios/RunnerTests/NotificationPreviewResolverTests.swift` proves same-id duplicate group image pushes skip repeated preview decrypt while re-minted ids remain independent. Real APNs background/terminated device-context proof remains assigned to `GIRD-007`.
- During `GIRD-007`, final host coverage closed: `feature-host-all` discovered `484` commands and passed as an ordered fail-fast/resume sweep through `#484` after isolated host test repairs; `./scripts/run_test_gates.sh groups` passed with `313` tests; `./scripts/run_test_gates.sh completeness-check` passed with `767/767` classified test files after direct-suite classification updates.
- During `GIRD-007`, final Go preservation closed: `cd go-relay-server && go test ./...` passed, and `cd go-mknoon && go test ./node ./bridge ./internal` passed.
- During `GIRD-007`, the group reliability simulator gate closed. The dry-run/list pass confirmed command `#49` maps to `integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_never_member_publish_rejected`. The former `#49` Dana online-readiness blocker was classified as an environment/harness preflight fixture issue from stale repo-owned transport census/testpeer processes, not Dana role/device, scenario/member logic, group-image behavior, or product transport. After cleanup and preflight hardening, `group --only 49` passed with artifact `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_K8Q6OU`, run id `1780323563475`, and role logs `alice.log`, `bob.log`, `charlie.log`, `dana.log`; the later full sweep re-ran `#49` and passed with artifact `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_never_member_publish_rejected_YwrP1Q`, run id `1780357563278`.
- During `GIRD-007`, subsequent group reliability failures were classified and fixed at the correct layer without weakening assertions: `#68 private_max_group_size_churn` was a stale membership harness fixture fixed in `integration_test/group_multi_party_device_real_harness.dart`; `#72 private_same_user_multi_device_readd` was a harness JSON read/write race fixed in `integration_test/scripts/run_group_multi_party_device_real.dart` and `integration_test/group_multi_device_real_harness.dart`; `#43` and `#86` were environment/storage disk-full interruptions that passed after cleanup and targeted rerun. The final `group` reliability fail-fast/resume sweep completed all `122` commands; final tail artifacts include `#121` iOS notification tap UI smoke logs under `build/ios-notification-tap-ui-smoke/20260602T052947Z`, and `#122` push-decrypt simulator smoke passed.
- During `GIRD-007`, the narrow real APNs background/terminated device-context proof is classified `residual-only with explicit follow-up`: real iOS hardware is visible, but no repo-local non-interactive provider APNs sender harness exists to prove production/TestFlight APNs delivery, NSE preview/fallback, OS coalescing, tap route, and catch-up for canonical same-id and re-minted group image pushes.
- Existing tests cover many adjacent pieces, including reliable-send success, legacy publish-timeout plus inbox success, same-message-id dedupe, failed-card retry targeting, pending-media refresh, active-group notification suppression, notification open routing, foreground group push drain, group media fanout, and group recovery. They do not close this exact incident chain.

## acceptance gap ownership

| Source acceptance gap family | Owning sessions | Required final classification |
|---|---:|---|
| Reliable-send timeout, weak peer evidence, durable custody, and false failed state | `GIRD-001`, `GIRD-007` | closed, residual-only, or blocked |
| Same-id own replay/receipt repair and already-open sender status refresh | `GIRD-001`, `GIRD-002`, `GIRD-007` | closed, residual-only, or blocked |
| Failed-card retry, restored composer continuation, upload-pending retry feedback, resume overlap, and close/reopen continuation | `GIRD-002`, `GIRD-007` | closed, residual-only, or blocked |
| Recipient live/inbox replay, re-minted-id duplicate image rows, attachment ownership, and intentional separate sends | `GIRD-003`, `GIRD-004`, `GIRD-007` | closed, residual-only, or blocked |
| Relay group inbox repeated durable store attempts and push fanout duplication | `GIRD-004`, `GIRD-006`, `GIRD-007` | closed, residual-only, or blocked |
| Recoverable media unavailable flash and terminal unsafe media preservation | `GIRD-005`, `GIRD-007` | closed, residual-only, or blocked |
| Android active, muted, foreground, background, duplicate, display-failure, and tap notification paths | `GIRD-006`, `GIRD-007` | closed, residual-only, or blocked |
| iOS APNs payload, NSE preview/fallback, duplicate same-id/re-minted-id behavior, and notification-open routing | `GIRD-006`, `GIRD-007` | closed, residual-only, or blocked |
| Three-user reported incident, simulator evidence, narrow iOS device-context evidence, final host/reliability gates, and docs/matrix closure | `GIRD-007` | closed, residual-only, or blocked |

## session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Initial status |
|---|---|---|---|---|---|
| `GIRD-001` | `Sender in-doubt send classification and reconciliation` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md` | none | `pending` |
| `GIRD-002` | `Sender retry ownership across composer, failed-card, upload, and resume` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md` | `GIRD-001` | `prerequisite-blocked` |
| `GIRD-003` | `Recipient logical dedupe and attachment row stability` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md` | `GIRD-001`, `GIRD-002` | `prerequisite-blocked` |
| `GIRD-004` | `Relay and native group inbox idempotency` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-004-plan.md` | `GIRD-001`, `GIRD-003` | `prerequisite-blocked` |
| `GIRD-005` | `Group media retryable loading versus terminal unavailable UI` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-005-plan.md` | `GIRD-003` | `prerequisite-blocked` |
| `GIRD-006` | `Group image notification identity, suppression, fallback, and tap routing` | `implementation-ready` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-006-plan.md` | `GIRD-003`, `GIRD-004` | `prerequisite-blocked` |
| `GIRD-007` | `Incident acceptance, simulator/device evidence, gates, and closure docs` | `acceptance-only` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-007-plan.md` | `GIRD-001`, `GIRD-002`, `GIRD-003`, `GIRD-004`, `GIRD-005`, `GIRD-006` | `prerequisite-blocked` |

## Session Closure Ledger

| Session ID | Current status | Plan file | Execution verdict | Closure docs touched | Evidence summary | Follow-ups/blockers |
|---|---|---|---|---|---|---|
| `GIRD-001` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md` | `accepted` after isolated Executor and separate QA Reviewer, both recorded with `model: gpt-5.5` and `reasoning_effort: xhigh` | Updated this breakdown only. Inspected the GIRD-001 plan and source doc; stable source/matrix closure reconciliation remains assigned to `GIRD-007`. | RED evidence recorded in the plan: application tests failed for reliable timeout, reliable zero-peer/no-custody in-doubt state, and same-id failed-row self replay; bridge timeout guard was already green. GREEN evidence recorded in the plan: direct `GIRD-001` suites, preservation suites, `./scripts/run_test_gates.sh groups`, and `git diff --check` passed. `transport` was skipped because no bridge production/startup/resume/transport wiring changed; repository/helper suites were skipped because no repository/helper path changed. | None for `GIRD-001`. No blocking issues and no non-blocking follow-ups were accepted by QA. `GIRD-002+` scope remains open and must refresh against this accepted sender-state contract before execution. |
| `GIRD-002` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md` | `accepted` after a spawned Executor with `model: gpt-5.5` and `reasoning_effort: xhigh` made code/doc progress, then bounded local fallback completed Executor verification plus QA after the spawned agent no-progress condition was closed | Updated this breakdown only. Inspected the GIRD-002 plan, source doc, dirty-tree snapshot, and GIRD-002 production/test/l10n diffs; stable source/matrix closure reconciliation remains assigned to `GIRD-007`. | RED evidence recorded in the plan: restored composer retry minted two rows/two ids, upload-pending failed-card retry gave generic failure feedback, and already-open screen state stayed stale after resume. GREEN evidence recorded in the plan: focused `GIRD-002` suites for `group_conversation_wired_test.dart`, `retry_incomplete_group_uploads_use_case_test.dart`, and `pending_message_retrier_upload_ordering_test.dart` passed; plan-listed preservation commands passed; `./scripts/run_test_gates.sh groups`, `flutter gen-l10n`, and `git diff --check` passed. Conditional `transport`, lifecycle `GIRD-002`, and `group_conversation_screen_test.dart` commands were skipped with file-change-based rationale. | None for `GIRD-002`. No blocking issues and no non-blocking follow-ups were accepted by QA. `GIRD-003+` implementation scope remains open; final simulator/device acceptance and stable source/matrix classification remain assigned to `GIRD-007`. |
| `GIRD-003` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md` | `accepted` after host-only GIRD-003 execution and QA evidence, with Completion Auditor classification `closed` for `GIRD-003` only | Updated this breakdown only. Used the Completion Auditor handoff for GIRD-003; stable source/matrix closure reconciliation remains assigned to `GIRD-007`. | Handler/listener RED then GREEN evidence recorded for recipient logical media retry dedupe before duplicate attachment save. Focused tests added/verified: `GIRD-003 distinct-id group image retry with same media identity keeps one recipient row`, `GIRD-003 intentional separate image sends with distinct media identity both persist`, and `GIRD-003 reminted group image retry emits and notifies once`. Preservation tests, GIRD-001/GIRD-002 sender-contract refreshes, `./scripts/run_test_gates.sh groups`, and `git diff --check` passed. Conditional repository/db/media-helper and foreground-push integration suites were skipped with file-change rationale. | None for `GIRD-003`. No residual-only items, blockers, or still-open items remain within `GIRD-003`. Later ledger state: `GIRD-004`, `GIRD-005`, and `GIRD-006` are accepted; `GIRD-007` closed final group reliability and has an explicit APNs provider residual. |
| `GIRD-004` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-004-plan.md` | `accepted` after relay idempotency implementation, native preservation blocker resolution, required relay/native gates, and QA review | Updated this breakdown and the GIRD-004 plan only. Stable source/matrix closure reconciliation remains assigned to `GIRD-007`; no stable closure docs were touched. | GIRD-004 RED tests were added before production changes. GREEN evidence now covers memory/Redis exact keyed duplicate idempotency, sender/body conflict rejection, expanded recipient ACL merge, duplicate push fanout suppression, and native stable retry identity. Native blocker-resolution evidence fixed stale/brittle test expectations and one narrow validation classification path, then passed required focused selectors and module gates. Required commands passed: relay `GIRD004`, relay `GroupInbox|InboxStoreDedup|RedisGroupInbox|GroupStore`, relay full `go test ./...`, native `GIRD004|GISTR001`, native `GroupInboxStore|GroupInboxRetrieve|RelaySelector`, native `go test ./node ./bridge ./internal`, and `git diff --check`. | None for `GIRD-004`. GIRD-006 is accepted for relay-origin duplicate notification proof; GIRD-007 final host/Go preservation and group reliability are green, with only the APNs provider residual remaining. |
| `GIRD-005` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-005-plan.md` | `accepted` after local GIRD-005 continuation completed focused GREEN, direct preservation, group gate, and hygiene evidence; earlier spawned executor scope violation remains recorded but no longer blocks this row | Updated this breakdown and the GIRD-005 plan only. Stable source/matrix closure reconciliation remains assigned to `GIRD-007`; simulator/device incident proof is not claimed here. | RED evidence recorded in the plan: policy `done`/no-path unavailable classification, widget loading versus unavailable UI, failed-recovery visible downloading state, and done/no-path recovery failed before production edits. GREEN evidence recorded in the plan: focused `--plain-name GIRD-005` policy/widget/wired tests passed; the six direct/preservation Flutter suites passed with `327` tests; `./scripts/run_test_gates.sh groups` passed with `313` tests; `git diff --check` passed. | None for `GIRD-005`. Go relay/native deltas are out of GIRD-005 scope and governed by accepted `GIRD-004`. GIRD-006 is accepted; GIRD-007 final group reliability is accepted with only the APNs provider residual remaining. |
| `GIRD-006` | `accepted` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-006-plan.md` | `accepted` after RED-first notification display-failure proof, minimal background fallback gate fix, focused Flutter/Go/iOS proof, direct preservation, named gates, and hygiene evidence | Updated this breakdown and the GIRD-006 plan only. Stable source/matrix closure reconciliation remains assigned to `GIRD-007`; real APNs device-context proof is not claimed here. | RED evidence recorded in the plan: background group fallback display failure incorrectly marked the recent remote gate before fallback display succeeded. GREEN evidence recorded in the plan: focused GIRD-006 Flutter tests passed for background fallback failure/success/dedupe, canonical payloads, foreground drain, listener local replay suppression, and tap routing; Go relay payload selector passed; iOS `NotificationPreviewResolverTests` passed; direct Flutter preservation passed with `301` tests; `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh runtime-telemetry`, `dart format --set-exit-if-changed`, and `git diff --check` passed. | None for `GIRD-006`. Real APNs background/terminated delivery, OS coalescing, and device-context notification open are now classified as residual-only with explicit provider-harness follow-up in `GIRD-007`; the final group reliability gate is green. |
| `GIRD-007` | `accepted with residual-only APNs follow-up` | `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-007-plan.md` | `accepted with explicit follow-up` after final host, completeness, Go preservation, and full group reliability simulator scope passed with fix-as-you-go classification | Updated the source spec, this breakdown, the group reliability closure reference, the notification journey matrix, the group test inventory, and `test-gate-definitions.md`. | Host evidence: `feature-host-all --list` found `484` commands; ordered fail-fast/resume sweep passed through `#484`; `groups` passed with `313`; `completeness-check` passed with `767/767` after adding direct-suite classifications. Go evidence: relay `go test ./...` and native `go test ./node ./bridge ./internal` passed. Reliability sim evidence: `group --list` found `122`; `#49 private_never_member_publish_rejected` was classified as environment/harness preflight after stale transport/testpeer process cleanup and passed twice (`K8Q6OU`, `YwrP1Q` artifacts with all role logs); `#68` stale membership fixture and `#72` JSON race were harness fixes; `#43` and `#86` were disk-full environment interruptions; final tail `#87` through `#122` passed and the wrapper reported `PASS: reliability simulations completed for scope: group`. | No active blocker. Residual-only follow-up: add/run a provider-backed physical-device/TestFlight APNs background/terminated harness for same-id and re-minted group image pushes. |

## Controller Progress

| Time | Session | Phase | Docs/files inspected or updated | Tentative verdict | Next action |
|---|---|---|---|---|---|
| `2026-05-31 18:46 CEST` | `GIRD-003` | ledger sanity / planning intake | Verified `GIRD-001` and `GIRD-002` closure ledger rows are `accepted`; no existing `GIRD-003` plan file. Dirty snapshot includes accepted GIRD-001/GIRD-002 production/test/doc changes plus unrelated modified `scripts/check_reliability_simulation_discovery.sh`. | `GIRD-003` dependency satisfied and runnable | Spawn fresh `implementation-plan-orchestrator` agent for the intended `GIRD-003` plan path, refreshing against accepted sender-state and sender-retry contracts. |
| `2026-05-31 18:53 CEST` | `GIRD-003` | planning verified / pre-execution dirty snapshot | Verified `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md` is `Status: execution-ready` with no structural blockers; plan classifies execution closure as host-only and defers simulator/device incident proof to `GIRD-007`. Dirty snapshot includes accepted GIRD-001/GIRD-002 production/test/doc changes, the new GIRD-003 plan, and unrelated modified `scripts/check_reliability_simulation_discovery.sh`. | Planning accepted, no blocker | Spawn fresh `implementation-execution-qa-orchestrator` agent for `GIRD-003` only. |
| `2026-05-31 19:02 CEST` | `GIRD-003` | execution accepted / closure intake | Verified `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md` is `Status: accepted` with RED/GREEN GIRD-003 evidence, preservation and sender-contract refresh evidence, `./scripts/run_test_gates.sh groups`, and `git diff --check`. | Execution accepted, no blocker | Spawn fresh `implementation-closure-audit-orchestrator` agent for `GIRD-003` to reconcile the session ledger only. |
| `2026-05-31 19:10 CEST` | `GIRD-004` | ledger sanity / planning intake | Verified `GIRD-001`, `GIRD-002`, and `GIRD-003` closure ledger rows are `accepted`; `GIRD-004` depends on accepted `GIRD-001` and `GIRD-003`; no existing `GIRD-004` plan file. Dirty snapshot includes accepted prior-session production/test/doc changes plus unrelated modified `scripts/check_reliability_simulation_discovery.sh`. | `GIRD-004` dependency satisfied and runnable | Spawn fresh `implementation-plan-orchestrator` agent for the intended `GIRD-004` plan path, scoped to relay/native group inbox idempotency. |
| `2026-05-31 19:16 CEST` | `GIRD-004` | planning verified / pre-execution dirty snapshot | Verified `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-004-plan.md` is `Status: execution-ready`; planning used one fresh child that no-progressed after intake, then the allowed artifact-only local plan fallback. Dirty snapshot includes accepted prior-session Flutter/test/doc changes plus unrelated modified `scripts/check_reliability_simulation_discovery.sh`; no Go production/test files are dirty yet. | Planning accepted, no blocker | Spawn fresh `implementation-execution-qa-orchestrator` agent for `GIRD-004` only. |
| `2026-05-31 19:29 CEST` | `GIRD-004` | historical temporary block / ledger update | At that time, verified the GIRD-004 plan `## Final execution verdict` was `blocked`; inspected local RED command output and Go test-only deltas. This temporary state was superseded by the later accepted GIRD-004 blocker-resolution pass recorded below. | Historical temporary block; later superseded by accepted GIRD-004 evidence | Continue the pipeline with `GIRD-005`, which depends only on accepted `GIRD-003`; do not claim relay/native or notification closure until GIRD-004 is later accepted. |
| `2026-05-31 19:30 CEST` | `GIRD-005` | ledger sanity / planning intake | Verified `GIRD-003` closure ledger row is `accepted`; `GIRD-005` depends only on accepted `GIRD-003`; no existing `GIRD-005` plan file. Dirty snapshot at that time included accepted GIRD-001/GIRD-002/GIRD-003 Flutter/test/doc changes, GIRD-004 RED-only Go test deltas, and unrelated modified `scripts/check_reliability_simulation_discovery.sh`. | `GIRD-005` dependency satisfied and runnable | Spawn fresh `implementation-plan-orchestrator` agent for the intended `GIRD-005` plan path, scoped to media retryable loading versus terminal unavailable UI. |
| `2026-05-31 19:38 CEST` | `GIRD-005` | planning verified / pre-execution dirty snapshot | Verified `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-005-plan.md` is `Status: execution-ready`; planning records host-only Flutter media UI closure with simulator/device incident proof deferred to `GIRD-007`. Dirty snapshot at that time included accepted GIRD-001/GIRD-002/GIRD-003 Flutter/test/doc changes, GIRD-004 RED-only Go test deltas, the new GIRD-005 plan, and unrelated modified `scripts/check_reliability_simulation_discovery.sh`. | Planning accepted, no blocker | Spawn fresh `implementation-execution-qa-orchestrator` agent for `GIRD-005` only. |
| `2026-05-31 20:00 CEST` | `GIRD-005` | historical execution block / ledger update | Stopped the active GIRD-005 execution chain after it ran out-of-scope Go work and left current-doc artifacts stale. At that point GIRD-005 Flutter partial deltas lacked GREEN/QA evidence and Go relay work was outside GIRD-005 scope. | Historical GIRD-005 block later superseded; at that time GIRD-006/GIRD-007 were not runnable | User later requested stopping after finishing GIRD-005, so GIRD-005 was locally completed without advancing to GIRD-006. |
| `2026-05-31 20:06 CEST` | `GIRD-005` | local continuation accepted / stop point | Focused on the existing GIRD-005 Flutter partial deltas only; did not edit or verify Go work as GIRD-005 evidence. Updated the GIRD-005 plan and this breakdown after focused GREEN, direct preservation, `./scripts/run_test_gates.sh groups`, and `git diff --check` passed. | `GIRD-005` accepted; stop before `GIRD-006` per user instruction | Persisted the then-current rollout verdict as still open because later sessions were not closed. This was superseded for GIRD-004 by the accepted blocker-resolution pass below. |
| `2026-05-31 21:18 CEST` | `GIRD-004` | blocker-resolution accepted / ledger update | Reopened only the remaining native evidence blocker recorded in the GIRD-004 plan. Relay idempotency implementation was preserved. Updated this breakdown and the GIRD-004 plan after native failure reproduction/classification, narrow native fixes, required relay/native GREEN gates, and `git diff --check`. | `GIRD-004` accepted; `GIRD-006` now dependency-ready; `GIRD-007` still blocked until GIRD-006 and final acceptance run | Stop after GIRD-004 blocker-resolution per current user scope. Do not advance into GIRD-006 or GIRD-007 in this pass. |
| `2026-05-31 21:57 CEST` | `GIRD-006` | local continuation accepted / ledger update | Completed GIRD-006 after user resumed the rollout beyond GIRD-004. Updated the GIRD-006 plan and this breakdown after RED-first display-failure proof, minimal background fallback gate fix, focused Flutter/Go/iOS evidence, direct Flutter preservation, `groups`, `runtime-telemetry`, formatting, and `git diff --check` passed. | `GIRD-006` accepted; `GIRD-007` now dependency-ready | Continue to `GIRD-007` for incident acceptance, source-required host/reliability gates, narrow iOS device-context classification, and stable docs/matrix closure. |
| `2026-06-01 02:05 CEST` | `GIRD-007` | final acceptance blocked / ledger update | Updated the GIRD-007 plan and final rollout docs after host/completeness/Go gates passed, group reliability commands `#1` through `#48` passed, and `#49` repeatedly failed on Dana online readiness. | `GIRD-007` blocked with evidence; source rollout blocked | Stop at the documented blocker. Do not broaden beyond Report 102; resume with `group --only 49`, then `group --start-at 50`, only after the Dana readiness issue is fixed or conclusively classified by the group reliability owner. |
| `2026-06-02 07:40 CEST` | `GIRD-007` | blocker resolved / final acceptance ledger update | Updated the GIRD-007 plan and this breakdown after `#49` was classified as environment/harness preflight, `group --only 49` passed, `group --start-at 50` and the full group reliability scope completed through `#122`, and the required artifacts/role logs were recorded. | `GIRD-007` accepted with residual-only APNs follow-up; source rollout no longer blocked by group reliability | Preserve the provider-backed physical-device/TestFlight APNs background/terminated follow-up as residual-only; do not reopen group reliability unless a new regression appears. |

## Closure Progress

| Time | Session | Phase | Docs inspected or updated | Tentative verdict | Next action |
|---|---|---|---|---|---|
| `2026-05-31 17:59 CEST` | `GIRD-001` | closure audit started | Inspected `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`; `git status --short`. No closure writes yet. | `accepted` for GIRD-001 only, pending ledger reconciliation | Audit accepted execution/QA evidence, then update GIRD-001 ledger without touching GIRD-002+ scope. |
| `2026-05-31 18:00 CEST` | `GIRD-001` | closure writer completed | Updated current repo facts for the accepted GIRD-001 sender-state changes; added `Session Closure Ledger` row for `GIRD-001`; preserved source-doc and stable matrix closure deferral to `GIRD-007`. | `accepted` for GIRD-001 only | Review the doc update for overclaiming, stale wording, and pipeline readiness for `GIRD-002`. |
| `2026-05-31 18:01 CEST` | `GIRD-001` | closure reviewer completed | Reviewed the updated breakdown against the accepted plan evidence, current production/test diffs, source-doc deferral rules, and dirty-tree snapshot. | `accepted` for GIRD-001 only; no follow-ups/blockers | Hand control back to the pipeline; next session may refresh and plan `GIRD-002` against the accepted sender-state contract. |
| `2026-05-31 18:43 CEST` | `GIRD-002` | closure audit started | Inspected `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`; `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`; `git status --short`; GIRD-002 production/test/l10n diff excerpts. No closure writes yet. | `accepted` for GIRD-002 only, pending ledger reconciliation | Run Completion Auditor against accepted execution evidence, then update only the GIRD-002 closure ledger/current-doc facts. |
| `2026-05-31 18:43 CEST` | `GIRD-002` | closure writer completed | Updated current repo facts for accepted GIRD-002 sender retry ownership, added the GIRD-002 `Session Closure Ledger` row, and added the GIRD-002 ordered-session closure result. Stable source-doc and matrix closure reconciliation remains assigned to `GIRD-007`. | `accepted` for GIRD-002 only | Review the doc update for evidence consistency, overclaiming, stale wording, and pipeline readiness for `GIRD-003`. |
| `2026-05-31 18:45 CEST` | `GIRD-002` | closure reviewer completed | Reviewed the updated breakdown against the accepted plan evidence, GIRD-002 production/test/l10n diffs, source-doc deferral rules, and dirty-tree snapshot; tightened one over-broad closure-result phrase to name the untouched files exactly. | `accepted` for GIRD-002 only; no follow-ups/blockers | Hand control back to the pipeline; next session may refresh and plan `GIRD-003` against accepted GIRD-001/GIRD-002 sender contracts. |
| `2026-05-31 19:05 CEST` | `GIRD-003` | closure audit completed | Used the Completion Auditor handoff for GIRD-003 and inspected this breakdown. No source doc, stable matrix, code, test, or script files were edited. | `accepted` for GIRD-003 only; no residual-only items or blockers | Update only this breakdown with the GIRD-003 ledger row, current repo fact, and ordered-session closure result. |
| `2026-05-31 19:05 CEST` | `GIRD-003` | closure writer completed | Updated current repo facts for accepted GIRD-003 recipient logical dedupe, added the GIRD-003 `Session Closure Ledger` row, and added the GIRD-003 ordered-session closure result. Stable source-doc and matrix closure reconciliation remains assigned to `GIRD-007`. | `accepted` for GIRD-003 only | Review the doc update for evidence consistency, overclaiming, stale wording, and pipeline readiness for `GIRD-004`. |
| `2026-05-31 19:09 CEST` | `GIRD-003` | closure reviewer completed | Reviewed the updated breakdown against the accepted GIRD-003 plan evidence, landed focused test names, source-doc deferral rules, and dirty-tree constraints. | `accepted` for GIRD-003 only; no corrections, residual-only items, or blockers | Hand control back to the pipeline; `GIRD-004` may refresh and plan against the accepted GIRD-003 recipient dedupe contract. |

## ordered session breakdown

### Session GIRD-001

- Title:
  `Sender in-doubt send classification and reconciliation`
- Session id:
  `GIRD-001`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-001-plan.md`
- Exact scope:
  - classify reliable `group:sendReliable` Dart timeout as an in-doubt send state, not proven non-delivery, when native custody or live delivery may still resolve later
  - classify reliable publish success with weak or zero local peer evidence and failed inbox custody without overclaiming receiver non-delivery
  - define and persist the sender-side proof needed to settle an in-doubt group image send truthfully
  - allow same-id own-message replay, durable custody evidence, or delivered/read receipt evidence to repair a falsely failed outgoing row where repo architecture supports it
  - ensure repaired outgoing rows do not retain failed-card affordances that invite duplicate retries
  - preserve existing reliable-send happy paths, legacy publish-timeout plus inbox success behavior, and sender-trust status semantics
- Why it is its own session:
  - this is the core application contract for in-doubt delivery and status truth
  - later retry, recipient, and notification work need a stable definition of the logical send and its settlement state
- Likely code-entry files:
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/domain/models/group_message_receipt.dart`
  - `lib/features/groups/domain/repositories/group_message_repository.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  - `lib/core/database/helpers/group_messages_db_helpers.dart`
  - `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/send_group_message_use_case_test.dart`
  - `test/core/bridge/bridge_group_helpers_test.dart`
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  - `test/core/database/helpers/group_messages_db_helpers_reliability_test.dart`
  - `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart` if receipt settlement is used
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` if bridge timeout, native callback, resume, or startup/transport behavior changes
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure result:
  - `accepted` after isolated execution and separate QA review
  - reliable `BRIDGE_TIMEOUT` and reliable zero-peer/no-custody publish success now persist non-failed in-doubt `pending` sender rows under the original message id and return `SendGroupMessageResult.success`
  - same-id own-message replay can repair the affected failed outgoing row when group, sender, transport identity, text, and retry evidence match
  - no repository/helper, bridge production, startup/resume, transport, simulator/device, media, notification, relay, or retry-ownership work was claimed here
  - stable source-doc and matrix closure classification remains with `GIRD-007`

### Session GIRD-002

- Title:
  `Sender retry ownership across composer, failed-card, upload, and resume`
- Session id:
  `GIRD-002`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-002-plan.md`
- Exact scope:
  - make failed-card retry, restored composer continuation, app resume recovery, pending-message retrier recovery, and incomplete-upload retry converge on one logical group image send
  - prevent restored composer send from minting a fresh recipient-visible message id for the same failed/in-doubt user-intended image send
  - handle retry while media is still `upload_pending` with truthful feedback and no silent no-op that encourages a duplicate composer send
  - prevent incomplete-upload retry and failed-message retry from both sending the same logical image during the same recovery sweep
  - ensure already-open group conversation screens observe background/resume retry status and media changes without requiring close/reopen
  - preserve dedicated failed-card retry targeting only the selected failed media row
- Why it is its own session:
  - this is the user-facing retry and lifecycle surface, separate from the send-result classifier
  - it spans presentation, lifecycle, and retry orchestration tests that should not be bundled into `GIRD-001`
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/services/pending_message_retrier.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  - `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/lifecycle/handle_app_resumed_group_stuck_sending_test.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh transport` if lifecycle/startup/reconnect behavior changes
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - `GIRD-001`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure result:
  - `accepted` after a spawned Executor made code/doc progress, local sequential fallback completed Executor verification plus QA, and the plan recorded no blocking issues
  - restored failed group media composer continuations now reuse the original message id/timestamp when draft, quote, group, and attachment fingerprint still match
  - if the restored row settles non-failed before the user presses Send, the already-open screen refreshes row/media and clears the composer instead of publishing a new row
  - upload-pending failed-card retry now gives localized pending-upload feedback, refreshes row/media, and does not publish or call the failed-message retry owner
  - already-open group conversation screens reload messages/media on app resume and after group recovery gate completion
  - incomplete-upload and pending retrier ordering remained green; no broad queue, durable schema, recipient dedupe, relay/native, notification, `group_conversation_screen.dart`, `handle_app_resumed.dart`, transport, simulator, or device-backed work was claimed here
  - stable source-doc and matrix closure classification remains with `GIRD-007`

### Session GIRD-003

- Title:
  `Recipient logical dedupe and attachment row stability`
- Session id:
  `GIRD-003`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-003-plan.md`
- Exact scope:
  - keep same-message-id live pubsub plus group inbox replay as one recipient row and one local notification path
  - close the source-spec duplicate gap for one logical group image send that may arrive through retry paths with distinct stable ids, without collapsing intentional separate successful sends
  - ensure media attachments remain attached to the correct visible group row and do not appear to move between duplicate rows
  - preserve existing behavior that truly distinct stable message ids with the same content/timestamp can persist when they are intentional separate sends
  - cover missing/unstable message id fallbacks without using broad unsafe content dedupe
- Why it is its own session:
  - recipient visible row idempotency is a separate closure bar from sender retry ownership and relay storage
  - it is the place to decide whether Flutter needs a logical send key, attachment/blob identity check, or another existing architecture-compatible proof
- Likely code-entry files:
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/domain/models/group_message_payload.dart`
  - `lib/features/groups/domain/models/group_message.dart`
  - `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
  - `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
  - `lib/core/database/helpers/group_messages_db_helpers.dart`
  - `lib/core/database/helpers/media_attachments_db_helpers.dart`
- Likely direct tests/regressions:
  - `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
  - `test/core/database/helpers/group_messages_db_helpers_test.dart`
  - `test/core/database/helpers/media_attachments_db_helpers_test.dart`
  - `test/features/groups/integration/group_resume_recovery_test.dart`
  - `integration_test/foreground_group_push_drain_test.dart` if foreground push drain behavior is changed or extended
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - reliability simulator group scope in final `GIRD-007`
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - `GIRD-001`
  - `GIRD-002`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure result:
  - `accepted` for `GIRD-003` only after host-side execution/QA and Completion Auditor classification recorded no residual items
  - `handle_incoming_group_message_use_case.dart` now performs recipient logical media retry dedupe before duplicate attachment save: exact envelope match plus strict media identity enriches the canonical row and returns `null`
  - focused tests cover distinct-id group image retry with same media identity keeping one recipient row, intentional separate image sends with distinct media identity both persisting, and re-minted group image retry emitting and notifying once
  - no listener production change, repository/db/media-helper change, foreground-push integration change, relay/native idempotency, simulator/device incident acceptance, final notification behavior, or source/matrix reconciliation was claimed here
  - later ledger state: `GIRD-004`, `GIRD-005`, and `GIRD-006` are accepted; `GIRD-007` remains open as documented below
  - stable source-doc and matrix closure classification remains with `GIRD-007`

### Session GIRD-004

- Title:
  `Relay and native group inbox idempotency`
- Session id:
  `GIRD-004`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-004-plan.md`
- Exact scope:
  - make repeated durable store attempts for the same logical group message idempotent at the relay/native boundary where the current backend appends every group store request
  - ensure duplicate group inbox storage does not produce duplicate recipient-visible catch-up rows or duplicate push fanout
  - preserve group inbox authorization, cursor, history-gap, retention, and distinct-message storage semantics
  - keep malformed or unkeyed messages classified honestly rather than silently collapsing unsafe data
- Why it is its own session:
  - this crosses Go relay/native storage and has different test commands from Flutter recipient behavior
  - storage/push idempotency can be validated independently once `GIRD-001` and `GIRD-003` define the app-visible logical-send identity
- Likely code-entry files:
  - `go-relay-server/backend_memory.go`
  - `go-relay-server/backend_redis.go`
  - `go-relay-server/inbox.go`
  - `go-relay-server/group_inbox_store.go`
  - `go-mknoon/node/group_inbox.go`
  - `go-mknoon/node/pubsub.go`
  - `go-mknoon/node/group_inbox_test.go`
- Likely direct tests/regressions:
  - `go-relay-server/group_inbox_test.go`
  - `go-relay-server/inbox_dedup_test.go`
  - new Go tests for memory and Redis group inbox same-logical-message duplicate store behavior
  - `go-mknoon/node/group_inbox_test.go`
  - `go-mknoon/node/pubsub_test.go` or adjacent reliable-send tests if native publish/inbox behavior changes
- Likely named gates:
  - `cd go-relay-server && go test ./...`
  - `cd go-mknoon && go test ./node ./bridge ./internal`
  - `./scripts/run_test_gates.sh groups` only if Flutter behavior changes in the same session
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - `GIRD-001`
  - `GIRD-003`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Execution result:
  - `accepted` after GIRD-004 RED tests, relay idempotency implementation, native preservation blocker-resolution, required relay/native GREEN gates, and QA review
  - relay memory/Redis group inbox stores are exact-key idempotent, reject conflicting same-id sender/body rows, merge duplicate recipient ACLs, and propagate duplicate store results so push fanout is not repeated
  - native `go-mknoon` preservation evidence is trustworthy after narrow stale-test/native validation fixes for inclusive retrieve timestamps, fake-relay selector-shape tests, valid reliable-send fixture peer IDs, duplicate transport peer classification, forced corrupt-state validation coverage, and empty peer-id admission rejection
  - required commands passed: `cd go-relay-server && go test ./... -run "GIRD004"`, `cd go-relay-server && go test ./... -run "GroupInbox|InboxStoreDedup|RedisGroupInbox|GroupStore"`, `cd go-relay-server && go test ./...`, `cd go-mknoon && go test ./node -run "GIRD004|GISTR001"`, `cd go-mknoon && go test ./node -run "GroupInboxStore|GroupInboxRetrieve|RelaySelector"`, `cd go-mknoon && go test ./node ./bridge ./internal`, and `git diff --check`
  - `GIRD-006` is now accepted for relay-origin duplicate notification proof; `GIRD-005` remains accepted independently because it depends only on `GIRD-003`

### Session GIRD-005

- Title:
  `Group media retryable loading versus terminal unavailable UI`
- Session id:
  `GIRD-005`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-005-plan.md`
- Exact scope:
  - distinguish retryable download failures and still-resolving verification states from terminal unavailable media in group image rows
  - prevent a recoverable failed-download retry or done-but-not-yet-verifiably-displayable state from briefly rendering `Media unavailable` before the image loads
  - preserve terminal unavailable/error rendering for unsafe, unverifiable, quarantined, unsupported, oversized, or permanently failed media
  - ensure visible rows refresh to the loaded image while the group screen is already open
  - preserve existing group media integrity policy, required content hash behavior, and retry controls for genuinely unavailable media
- Why it is its own session:
  - this is a narrow media state and widget/presentation contract with a different regression family from message idempotency
  - it must avoid weakening verification safety while changing user-visible loading copy/state
- Likely code-entry files:
  - `lib/core/media/group_media_integrity_policy.dart`
  - `lib/shared/widgets/media/media_grid_cell.dart`
  - `lib/shared/widgets/media/media_thumbnail_image.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/conversation/application/download_media_use_case.dart`
- Likely direct tests/regressions:
  - `test/core/media/group_media_integrity_policy_test.dart`
  - `test/shared/widgets/media/media_grid_cell_test.dart`
  - `test/shared/widgets/media/media_thumbnail_image_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - broader feature host scope through `$run-flutter-host-gates` in final `GIRD-007` if shared media behavior changes
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - `GIRD-003`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Execution result:
  - `accepted` after local GIRD-005 continuation completed the planned host-only proof and the user requested stopping after this session
  - RED evidence exists for policy, widget, and wired GIRD-005 gaps, and the focused `--plain-name GIRD-005` policy/widget/wired tests now pass
  - direct preservation suites passed with `327` tests: `group_media_integrity_policy_test.dart`, `media_grid_cell_test.dart`, `media_thumbnail_image_test.dart`, `group_conversation_screen_test.dart`, `group_conversation_wired_test.dart`, and `group_message_listener_test.dart`
  - `./scripts/run_test_gates.sh groups` passed with `313` tests, and `git diff --check` passed
  - no Go, relay, notification, membership, duplicate-delivery, or unrelated script evidence is claimed for GIRD-005; Go relay/native deltas remain out of GIRD-005 scope and are governed by accepted `GIRD-004`

### Session GIRD-006

- Title:
  `Group image notification identity, suppression, fallback, and tap routing`
- Session id:
  `GIRD-006`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-006-plan.md`
- Exact scope:
  - make one logical group image send map to at most one eligible visible notification path across local listener replay, foreground push drain, background fallback, and duplicate delivery
  - keep active-group suppression and muted-group suppression consistent across foreground, background, fallback, and replay paths
  - avoid consuming a recent remote announcement as if a notification was visible when local fallback display cannot happen because permission, channel, display, or platform behavior prevented it
  - keep Android foreground/background notification identity consistent for duplicate logical group image sends
  - cover iOS repo-level APNs payload shape, NSE preview/fallback behavior, duplicate same-id versus re-minted-id behavior, and notification tap routing without claiming real APNs device delivery
  - preserve existing notification-open routing for group messages and existing notification route contract tests
- Why it is its own session:
  - notification identity and suppression are a separate subsystem with push, local notification, remote gate, active/mute, and iOS NSE seams
  - it should depend on recipient/relay idempotency so notification dedupe keys align with the final logical-message contract
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/push/application/show_notification_use_case.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/features/push/application/background_push_notification_fallback.dart`
  - `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
  - `lib/features/push/application/resolve_group_notification_route_target_use_case.dart`
  - `lib/core/notifications/recent_remote_notification_gate.dart`
  - `lib/core/notifications/recent_background_notification_gate.dart`
  - `lib/core/notifications/flutter_notification_service.dart`
  - `lib/core/notifications/notification_route_target.dart`
  - `go-relay-server/inbox.go`
  - `ios/NotificationService/NotificationPreviewResolver.swift`
  - `ios/NotificationService/NotificationService.swift`
- Likely direct tests/regressions:
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/push/application/show_notification_use_case_test.dart`
  - `test/features/push/application/background_message_handler_test.dart`
  - `test/features/push/application/background_push_notification_fallback_test.dart`
  - `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/features/push/application/resolve_group_notification_route_target_use_case_test.dart`
  - `test/core/notifications/notification_route_target_test.dart`
  - `test/core/notifications/notification_route_contract_matrix_test.dart`
  - `test/integration/group_notification_dedupe_integration_test.dart`
  - `integration_test/foreground_group_push_drain_test.dart`
  - `ios/RunnerTests/NotificationPreviewResolverTests.swift`
  - Go push payload tests adjacent to `go-relay-server/inbox.go`
- Likely named gates:
  - direct suites above are mandatory
  - `./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh runtime-telemetry` if push preview telemetry or gate classification changes
  - `./scripts/run_test_gates.sh transport` if foreground/background push routing touches startup or bridge/reconnect paths
- Matrix/closure docs to update when done:
  - update this breakdown ledger with the session verdict
  - final stable docs stay with `GIRD-007`
- Dependency on earlier sessions:
  - `GIRD-003`
  - `GIRD-004`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Execution result:
  - `accepted` after local GIRD-006 continuation completed the planned repo-level notification proof
  - RED evidence exists for the background data-only group fallback path marking `RecentRemoteNotificationGate` before fallback display success
  - production change is limited to `lib/features/push/application/background_message_handler.dart`, where the recent remote gate now records data-only fallback only after local fallback display succeeds while preserving visible FCM notification behavior
  - focused Flutter GIRD-006 tests cover background fallback failure/success/dedupe, canonical group payloads, foreground group push drain, exact-id local replay suppression, and tap route preparation
  - Go relay payload proof passed with the GIRD-006 selector, iOS repo-level NSE proof passed through `NotificationPreviewResolverTests`, direct Flutter preservation passed with `301` tests, `./scripts/run_test_gates.sh groups` passed with `313` tests, `./scripts/run_test_gates.sh runtime-telemetry` passed with `4` tests, `dart format --set-exit-if-changed` had no pending changes, and `git diff --check` passed
  - no real APNs background/terminated device-context delivery, OS coalescing, or notification-open claim is made here; that evidence/classification remains with `GIRD-007`

### Session GIRD-007

- Title:
  `Incident acceptance, simulator/device evidence, gates, and closure docs`
- Session id:
  `GIRD-007`
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-GIRD-007-plan.md`
- Exact scope:
  - reproduce the reported three-user incident at acceptance level: User A sends one image, sees a transient error, retries, closes/reopens, resumes or continues, and User B/User C end with one visible image message rather than three
  - prove sender local state is not misleadingly one sent row while recipients have multiple rows for the same user-intended image
  - prove recipients do not briefly see terminal `Media unavailable` for media that actively retries and later loads
  - prove Android foreground/background notification behavior for the same logical group image send
  - prove iOS repo-level foreground/background/open behavior, and run or explicitly classify the narrow real APNs background/terminated NSE device-context evidence
  - run the final source-required host and reliability gates with fix-as-you-go in the future execution phase, recording all failures and final status
  - update stable matrix/closure docs and this breakdown ledger with each gap classified as closed, residual-only with follow-up, or blocked with evidence
- Why it is its own session:
  - final acceptance validates multiple earlier implementation slices together and should not be hidden inside any one coding session
  - simulator/device and docs/matrix closure have different prerequisites and failure handling than focused unit/integration implementation work
- Likely code-entry files:
  - no planned product-code ownership at decomposition time
  - acceptance may add or update dedicated incident simulator harnesses under `integration_test/` and orchestration scripts only if needed by the implementation plan
  - docs likely touched: source spec, this breakdown, group closure reference, notification matrix, test inventory, and gate definitions
- Likely direct tests/regressions:
  - new or tightened three-user group image incident simulator/integration coverage
  - `integration_test/foreground_group_push_drain_test.dart`
  - existing group recovery and group media simulator/e2e scripts if extended by earlier sessions
  - focused direct suites from `GIRD-001` through `GIRD-006` as needed for final replay
- Likely named gates:
  - `$run-flutter-host-gates` with fix-as-you-go for group host coverage, including `./scripts/run_test_gates.sh groups` and broader feature host scope when shared media, notification, bridge, repository, lifecycle, or database code changed
  - `$run-flutter-reliability-sims` with fix-as-you-go for group reliability simulator coverage
  - `./scripts/run_test_gates.sh completeness-check`
  - Go relay/native tests if `GIRD-004` changed Go code
  - narrow iOS device-context APNs/NSE notification pass, or explicit residual/blocker classification if unavailable
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if new high-value tests or gate classifications are added
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` if row-level group matrix classifications change
- Dependency on earlier sessions:
  - `GIRD-001`
  - `GIRD-002`
  - `GIRD-003`
  - `GIRD-004`
  - `GIRD-005`
  - `GIRD-006`
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`

## why this is not fewer sessions

- Sender in-doubt classification and sender retry surface work must split because one is an application status contract and the other is UI/lifecycle/retry orchestration.
- Recipient Flutter dedupe and relay group inbox idempotency must split because they live in different trees, use different direct tests, and can fail independently.
- Media unavailable behavior must stay separate because it changes display state and integrity policy, not message identity.
- Notification behavior must stay separate because local notification, remote push, NSE, mute, active conversation, and tap routing use separate services and gates.
- Final incident acceptance must stay separate because it validates cross-session behavior, simulator/device proof, source-required gates, and docs/matrix closure.

## why this is not more sessions

- Bridge timeout and weak-peer evidence share one sender in-doubt classification contract, so splitting them would create duplicated status work.
- Failed-card retry, restored composer continuation, upload-pending retry feedback, and resume overlap all converge on one sender retry-ownership problem and one verified user-visible state.
- Android and iOS repo-level notification paths share the same notification identity/suppression/tap contract; iOS real APNs device-context evidence is handled by final acceptance instead of a separate implementation session.
- Recoverable failed-download and done-but-not-yet-verifiable media states both need the same media display classifier and widget contract.
- The source doc contains many test cases, but most are acceptance axes of the same seven seams rather than independent implementation slices.

## regression and gate contract

- `Test-Flight-Improv/14-regression-test-strategy.md` applies by requiring one permanent targeted regression for this escaped production bug and change-based named gates for shared group, media, notification, bridge, lifecycle, and relay paths.
- `Test-Flight-Improv/test-gate-definitions.md` is the named-gate source of truth. The Group Messaging Gate is required whenever group send, receive, retry, resume, metadata/photo authority, or announcement behavior changes.
- The final source spec requires `$run-flutter-host-gates` with fix-as-you-go for group host coverage and `$run-flutter-reliability-sims` with fix-as-you-go for group reliability simulator coverage. That execution belongs to `GIRD-007`, not this decomposition.
- Direct test suites named in each session are mandatory before the named gates. The downstream plan for each session should narrow or expand exact commands based on landed code.
- If Go relay/native code changes, direct Go tests must run in the owning session and be rerun or summarized in final acceptance.
- If push preview telemetry or runtime gate logic changes, `./scripts/run_test_gates.sh runtime-telemetry` must be included.
- If bridge, resume, reconnect, startup, or transport wiring changes, `./scripts/run_test_gates.sh transport` must be included with device requirements from `test-gate-definitions.md`.
- Final evidence must record every failing command encountered, root cause, fix category, files changed, and final pass/fail status, as required by the source doc.

## matrix update contract

- Reuse existing stable docs; do not create a new matrix doc for this rollout.
- `GIRD-007` owns final updates to:
  - `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if new tests enter or stay outside named gates by explicit classification
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md` only if row-level group matrix status changes
- Each implementation session updates this breakdown ledger with its verdict and exact evidence, but stable closure-doc reconciliation waits until `GIRD-007`.

## downstream execution path

For each session in ledger order:

- run `$implementation-plan-orchestrator` against the session's doc-scoped plan path
- run `$implementation-execution-qa-orchestrator` against the accepted plan
- run `$implementation-closure-audit-orchestrator` after execution and verification
- refresh later session plans against landed code before executing them

After `GIRD-007`, run the pipeline final program acceptance pass and persist one final rollout verdict in this breakdown: `closed`, `residual-only`, or `blocked`.

## structural blockers remaining

- None for decomposition.

## accepted differences intentionally left unchanged

- The decomposition does not assume the exact implementation mechanism, storage shape, idempotency key format, timeout value, or protocol change. Those are downstream plan decisions.
- The source doc's exact reported count of three recipient rows is not treated as proven from one linear mechanism. `GIRD-007` must reproduce and bound the incident without overclaiming an unproven path.
- Same-message-id live pubsub plus group inbox replay is not treated as the primary duplicate-row mechanism because current receiver code already dedupes same stable ids; it remains a preservation regression.
- Repo-local evidence can prove iOS payload shape, NSE preview/fallback, duplicate preview behavior, and notification-open routing. Real APNs background/terminated delivery and OS coalescing stay a narrow device-context evidence item for `GIRD-007`.
- Intentional separate successful sends of the same image remain in scope to preserve and must not be collapsed by any duplicate-prevention work.

## exact docs/files used as evidence

- `Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage.md`
- `Test-Flight-Improv/90-group-media-all-recipient-coverage-session-breakdown.md`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/node/config.go`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/inbox.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/inbox_dedup_test.go`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/core/media/group_media_integrity_policy.dart`
- `lib/shared/widgets/media/media_grid_cell.dart`
- `lib/shared/widgets/media/media_thumbnail_image.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/core/notifications/recent_remote_notification_gate.dart`
- `lib/core/notifications/recent_background_notification_gate.dart`
- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/notification_route_target.dart`
- `ios/NotificationService/NotificationPreviewResolver.swift`
- `ios/NotificationService/NotificationService.swift`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/shared/widgets/media/media_grid_cell_test.dart`
- `test/core/media/group_media_integrity_policy_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `ios/RunnerTests/NotificationPreviewResolverTests.swift`

## why the decomposition is safe to send into downstream planning/execution

- Every session has a doc-scoped, non-colliding plan path under the source doc stem.
- Every source acceptance gap is owned by at least one session and final classified by `GIRD-007`.
- Dependencies prevent recipient, relay, notification, and final acceptance work from executing before sender logical-send identity and retry ownership are refreshed against landed code.
- Each session ends in a meaningful verified state with direct tests and named gate expectations.
- Existing matrix and closure docs are reused instead of creating a new tracker.
- No implementation or test execution was performed during this decomposition.

## Final rollout verdict

- Persisted: `2026-06-02 07:40 CEST`
- Pipeline verdict: `accepted_with_explicit_follow_up`
- Source rollout classification: `residual-only with explicit APNs provider follow-up`
- Stop point: none for group reliability. `GIRD-007` host, completeness, Go preservation, and full `group` reliability simulator scope are accepted.
- Reason: `GIRD-001` through `GIRD-006` are accepted. `GIRD-007` closed final host, completeness, Go preservation, and all `122` group reliability commands with fix-as-you-go classification. The former `#49` Dana online-readiness blocker is closed as environment/harness preflight; the only remaining item is the narrow real provider APNs background/terminated physical-device/TestFlight proof, which the repo cannot execute without a provider-backed harness.
- Current runnable state: no group reliability blocker remains. Future work is limited to adding and running the provider-backed physical-device/TestFlight APNs background/terminated harness for same-id and re-minted group image pushes.

| Source acceptance gap family | Final classification | Evidence / follow-up |
|---|---|---|
| Reliable-send timeout, weak peer evidence, durable custody, and false failed state | `closed` | `GIRD-001` accepted with RED/GREEN sender-state evidence. Final host, `groups`, completeness, Go preservation, and full group reliability evidence passed in `GIRD-007`. |
| Same-id own replay/receipt repair and already-open sender status refresh | `closed` | `GIRD-001` and `GIRD-002` accepted with same-id failed-row repair, retry ownership, and resume/open-screen refresh evidence. Final host and group gate coverage through `GIRD-007` did not expose a product regression. |
| Failed-card retry, restored composer continuation, upload-pending retry feedback, resume overlap, and close/reopen continuation | `closed` | `GIRD-002` accepted with focused RED/GREEN coverage for restored composer id reuse, upload-pending failed-card feedback, late final-send abort, resume refresh, and preservation gates. |
| Recipient live/inbox replay, re-minted-id duplicate image rows, attachment ownership, and intentional separate sends | `closed` | `GIRD-003` recipient logical media retry dedupe is accepted; `GIRD-004` relay/native idempotency is accepted. The full group reliability scope passed after the unrelated never-member `#49` online-readiness blocker was classified as environment/harness preflight. |
| Relay group inbox repeated durable store attempts and push fanout duplication | `closed` | `GIRD-004` accepted after RED-first relay tests, memory/Redis exact duplicate idempotency, conflict rejection, ACL merge, duplicate push suppression, native preservation blocker-resolution, and required relay/native GREEN gates. `GIRD-006` accepted relay-origin notification identity proof. |
| Recoverable media unavailable flash and terminal unsafe media preservation | `closed` | `GIRD-005` accepted after policy/widget/wired RED/GREEN evidence, direct preservation suites, `groups`, and hygiene. Terminal unsafe media remains unavailable; verified done/no-path and retryable visible media stay recoverable/loading. |
| Android active, muted, foreground, background, duplicate, display-failure, and tap notification paths | `closed` | `GIRD-006` accepted after RED-first background fallback display-failure proof, data-only fallback recent-remote gating fix, focused Flutter notification/listener/route tests, `groups`, and `runtime-telemetry`. Foreground group push simulator smoke command `#10` passed during `GIRD-007`. |
| iOS APNs payload, NSE preview/fallback, duplicate same-id/re-minted-id behavior, and notification-open routing | `residual-only with explicit follow-up` | Repo-level proof is closed through Go APNs payload tests, iOS `NotificationPreviewResolverTests`, simulator tap/open coverage, and push-decrypt simulator coverage. Residual follow-up: add/run a provider-backed physical-device/TestFlight APNs harness for background/terminated same-id and re-minted group image pushes, proving visible notification, NSE preview/fallback, OS coalescing, tap route, and catch-up. |
| Three-user reported incident, simulator evidence, narrow iOS device-context evidence, final host/reliability gates, and docs/matrix closure | `residual-only with explicit follow-up` | Host, completeness, Go preservation, and full group reliability passed. `#49 private_never_member_publish_rejected` is closed as an environment/harness preflight issue with passing artifacts `K8Q6OU` and `YwrP1Q`; `#68` and `#72` were harness fixes; `#43` and `#86` were environment/storage interruptions. The narrow APNs device-context path is residual-only as above. |

Go reconciliation:

- Accepted GIRD-004 evidence now includes RED-first relay tests plus GREEN relay/native implementation and preservation gates in `go-relay-server/group_inbox_test.go`, `go-relay-server/backend_redis_test.go`, `go-relay-server/inbox_test.go`, `go-mknoon/node/group_inbox_test.go`, `go-mknoon/node/multi_relay_test.go`, `go-mknoon/node/pubsub_delivery_test.go`, and `go-mknoon/node/pubsub_test.go`.
- Current dirty Go production deltas in `go-relay-server/backend_memory.go`, `go-relay-server/backend_redis.go`, `go-relay-server/group_inbox_store.go`, `go-relay-server/inbox.go`, and `go-mknoon/node/pubsub.go` are accepted as GIRD-004 work, not GIRD-005 evidence.
- `cd go-mknoon && go test ./node ./bridge ./internal` is now accepted GIRD-004 native module evidence after blocker-resolution.
