# Group New Member Send Receive Media Voice Coverage Session Breakdown

## decomposition artifact

- Artifact path:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- Supporting docs:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
  - `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`
- Decomposition date:
  `2026-04-29`
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must refresh against landed code before execution
  - reuse Report 85 group onboarding evidence where it directly proves this narrower report
  - do not count text-only group success as closure for image, video, or voice
  - do not count descriptor-only evidence as simulator playback or restart evidence

## downstream execution path

- Sessions should run, in breakdown order, through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`
- Run `GNM-005` only after the preceding runnable sessions are resolved or have a truthful persisted blocker.
- After `GNM-005`, run the pipeline's final whole-program acceptance/closure pass and persist one final program verdict in this breakdown artifact.
- Allowed final program verdicts for this rollout are `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `stale/already-covered`.
- A verdict is not trustworthy if the reported regression, "new member sees text but misses video", is only covered by text participation evidence.

## recommended plan count

- `5`
- The smallest safe split is:
  - `1` evidence/consolidation session for existing new-member receive coverage and no-backfill boundaries
  - `1` implementation session for the current missing discussion path: a newly-added member sending image, video, and voice after bootstrap
  - `1` implementation session for visible media recovery, retry, inbox, duplicate, and restart behavior that descriptor tests do not prove
  - `1` implementation/evidence session for announcement and removal-role boundaries that must not regress while media coverage tightens
  - `1` acceptance/closure session for simulator truth, gate classification, closure docs, and final verdict
- Session disposition counts:
  - `implementation-ready`: `3`
  - `evidence-gated`: `1`
  - `acceptance-only`: `1`
  - `stale/already-covered`: `0` at decomposition time; individual plans may mark a session already covered if current code and tests provide direct evidence

## overall closure bar

`Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md` stays `still_open` until all of the following are true at the same time:

- a newly-added discussion member receives post-join text, image, video, and voice without receiving pre-join history
- the reported bug shape has direct evidence: a newly-added member who receives post-join text also visibly receives a post-join video in the same active group
- a newly-added discussion member can send image, video, and voice after membership/bootstrap is active, and existing eligible members receive exactly one row with stable sender identity and media metadata
- receiver-side media rows do not silently disappear when download, retry, inbox drain, duplicate live/inbox delivery, or app restart is involved
- announcement readers keep receiving eligible post-join admin media under the current product contract while read-only users remain blocked from sending; no writer-role media claim is made unless product policy changes
- removed users and dissolved-group users do not regain media access through send, inbox, retry, notification, or reopen paths
- simulator or device-backed evidence truthfully records which visible media/playback/restart rows are automated now and which, if any, remain explicit follow-up
- `Test-Flight-Improv/test-gate-definitions.md`, the relevant discussion/announcement closure references, the source doc, and this breakdown agree on covered, residual, and manual/device-gated evidence

## source of truth

Primary governing docs:

- `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`

Current repo facts that materially affected decomposition:

- `test/features/groups/integration/group_new_member_onboarding_test.dart` already contains focused fake-network/app-layer coverage for a newly-added member receiving only post-join text, image, video, and voice descriptors, plus multiple-add, add/send boundary, reaction, and quoted missing-parent cases.
- `test/features/groups/integration/group_membership_smoke_test.dart` proves newly-added-member text sending after bootstrap, and pre-bootstrap send denial, but current evidence found no equivalent newly-added-member send coverage for image, video, and voice.
- `test/features/groups/integration/group_media_fanout_test.dart` proves existing discussion members receive image, video, and voice descriptors from another existing member.
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart` proves newly-added announcement readers receive post-join admin image, video, and voice descriptors with no pre-join backfill.
- `scripts/run_test_gates.sh` and `Test-Flight-Improv/test-gate-definitions.md` classify `group_new_member_onboarding_test.dart`, `group_media_fanout_test.dart`, and `announcement_new_reader_onboarding_test.dart` as optional/manual direct suites, while the frozen `groups` gate remains `group_messaging_smoke_test.dart`, `group_resume_recovery_test.dart`, `group_edge_cases_smoke_test.dart`, `invite_round_trip_test.dart`, `group_membership_smoke_test.dart`, and `group_startup_rejoin_smoke_test.dart`.
- Media attachment state and metadata flow through `lib/features/conversation/domain/models/media_attachment.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, and `lib/features/groups/presentation/screens/group_conversation_screen.dart`.

## source test case inventory

| Source case | Primary session | Disposition at decomposition |
| --- | --- | --- |
| `NGM-001` | `GNM-001` | receive text/no-backfill evidence exists; revalidate and record |
| `NGM-002` | `GNM-001` | receive image descriptor/download evidence exists; visible restart evidence belongs to `GNM-003` |
| `NGM-003` | `GNM-001`, `GNM-003`, `GNM-005` | reported video receive path needs descriptor, visible row/playback, and simulator truth |
| `NGM-004` | `GNM-001`, `GNM-003` | receive voice descriptor evidence exists; playback/restart evidence remains visible-state work |
| `NGM-005` | `GNM-002` | text send evidence exists; keep as baseline while extending to media |
| `NGM-006` | `GNM-002` | newly-added-member image send gap |
| `NGM-007` | `GNM-002` | newly-added-member video send gap |
| `NGM-008` | `GNM-002` | newly-added-member voice send gap |
| `NGM-009` | `GNM-001` | multiple-add receive convergence evidence exists for at least one post-add message; media-specific assertions should be verified if reused |
| `NGM-010` | `GNM-001` | add/send boundary evidence exists; media boundary should be verified or documented |
| `NGM-011` | `GNM-004` | announcement reader receive media evidence exists |
| `NGM-012` | `GNM-004` | role-eligible announcement sender media requires verification beyond admin-only proof if writer behavior is claimed |
| `NGM-013` | `GNM-001`, `GNM-004` | no-backfill preservation for discussion and announcement |
| `NGM-014` | `GNM-003` | text success must not mask media failure |
| `NGM-015` | `GNM-003` | offline inbox media recovery |
| `NGM-016` | `GNM-003` | foreground push media drain |
| `NGM-017` | `GNM-003` | receiver-side download retry visibility |
| `NGM-018` | `GNM-003` | upload retry visibility for new-member sends |
| `NGM-019` | `GNM-003` | restart preserves pending/completed media |
| `NGM-020` | `GNM-003` | duplicate live/inbox suppression |
| `NGM-021` | `GNM-004` | removed-before-send denial |
| `NGM-022` | `GNM-004` | removed-after-send retention/access policy |
| `NGM-023` | `GNM-004` | announcement reader remains read-only |
| `NGM-024` | `GNM-002`, `GNM-003`, `GNM-004` | media metadata stability across send, receive, and role-boundary paths |

## session ledger

| Session ID | Source cases | Classification | Intended plan file | Depends on | Current status |
| --- | --- | --- | --- | --- | --- |
| `GNM-001` | `NGM-001`, `NGM-002`, `NGM-003`, `NGM-004`, `NGM-009`, `NGM-010`, `NGM-013` | `evidence-gated` | `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-001-plan.md` | none | `accepted` |
| `GNM-002` | `NGM-005`, `NGM-006`, `NGM-007`, `NGM-008`, `NGM-024` | `implementation-ready` | `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-002-plan.md` | none | `accepted` |
| `GNM-003` | `NGM-003`, `NGM-004`, `NGM-014`, `NGM-015`, `NGM-016`, `NGM-017`, `NGM-018`, `NGM-019`, `NGM-020`, `NGM-024` | `implementation-ready` | `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-003-plan.md` | `GNM-002` if it adds shared media-send helpers | `accepted` |
| `GNM-004` | `NGM-011`, `NGM-012`, `NGM-013`, `NGM-021`, `NGM-022`, `NGM-023`, `NGM-024` | `implementation-ready` | `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-004-plan.md` | none | `accepted` |
| `GNM-005` | final acceptance and closure | `acceptance-only` | `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-005-plan.md` | `GNM-001`, `GNM-002`, `GNM-003`, `GNM-004` resolved or explicitly blocked | `accepted_with_explicit_follow_up` |

## ordered session breakdown

### Session GNM-001

- Title:
  `Discussion new-member receive media and no-backfill evidence`
- Session id:
  `GNM-001`
- Source cases:
  `NGM-001`, `NGM-002`, `NGM-003`, `NGM-004`, `NGM-009`, `NGM-010`, `NGM-013`
- Session classification:
  `evidence-gated`
- Intended plan file:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-001-plan.md`
- Exact scope:
  - verify whether current Report 85 tests already prove newly-added discussion members receive post-join text, image, video, and voice without pre-join backfill
  - ensure the specific text-plus-video regression is mapped to concrete app-layer evidence, not only text participation
  - add or tighten focused assertions only if current evidence cannot prove media descriptors, download trigger behavior, multi-add convergence, or the add/send boundary for media
- Why it is its own session:
  - this is primarily receive-side evidence and should not be mixed with the missing new-member media-send implementation path
- Likely code-entry files:
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/domain/models/group_message_payload.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_media_fanout_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
- Likely named gates:
  - direct suite: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - shared group behavior changes: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - this breakdown ledger
- Dependency on earlier sessions:
  - none
- Closure result:
  - accepted on `2026-04-29`
  - plan artifact: `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-001-plan.md`
  - direct verification passed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - evidence: newly-added Bob receives only post-join text, image, video, and voice from Alice, including the reported text-plus-video shape in the same active group
  - evidence: Bob's image/video/audio descriptors preserve identity, MIME/media type, size-related metadata, dimensions/duration/waveform where present, and complete the fake bridge media-download path
  - evidence: pre-join history remains absent, multiple newly-added members converge on the latest epoch, and the add/send boundary excludes staged but unsubscribed recipients
  - test maintenance delta: the quoted-reply widget assertion now allows the current UI to render the reply text in more than one text element while still requiring the missing-parent fallback

### Session GNM-002

- Title:
  `Newly-added discussion member sends image video and voice`
- Session id:
  `GNM-002`
- Source cases:
  `NGM-005`, `NGM-006`, `NGM-007`, `NGM-008`, `NGM-024`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-002-plan.md`
- Exact scope:
  - extend newly-added-member send coverage from text to image, video, and voice after bootstrap is active
  - prove existing eligible members receive each media row exactly once with the newly-added member as sender
  - assert attachment identity, MIME/media type, size, duration, dimensions, waveform where available, and sender message-id preservation where the product supports it
  - preserve the pre-bootstrap send denial already covered for text
- Why it is its own session:
  - this is the main missing correctness gap in the source doc and exercises send authorization, upload descriptor persistence, fan-out, and receiver mapping from the new member's perspective
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/conversation/domain/models/media_attachment.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `test/features/groups/integration/group_media_fanout_test.dart`
- Likely named gates:
  - direct focused suite added or extended in this session
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` if shared group send behavior changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if a new direct suite is added
  - this breakdown ledger
- Dependency on earlier sessions:
  - none
- Closure result:
  - accepted on `2026-04-29`
  - plan artifact: `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-002-plan.md`
  - landed `test/features/groups/integration/group_media_fanout_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_media_fanout_test.dart`
  - evidence: newly-added Bob sends post-bootstrap image, video, and voice through `sendGroupMessageViaBridge`
  - evidence: Alice and Charlie receive exactly one incoming row for each new-member media send, preserving the sender message id and image/video/audio attachment metadata
  - evidence: Bob's outgoing rows persist matching attachments, and Alice's fake-bridge receive path completes three media downloads; Charlie's descriptor-only receive path mirrors the existing fan-out harness contract

### Session GNM-003

- Title:
  `Visible media recovery retry inbox duplicate and restart behavior`
- Session id:
  `GNM-003`
- Source cases:
  `NGM-003`, `NGM-004`, `NGM-014`, `NGM-015`, `NGM-016`, `NGM-017`, `NGM-018`, `NGM-019`, `NGM-020`, `NGM-024`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-003-plan.md`
- Exact scope:
  - prove media rows remain visible and truthful when download is pending, failed, retried, completed, reopened, or replayed through inbox drain
  - cover the reported video path at the conversation surface: a new member who sees post-join text also sees a post-join video row with the expected affordance/state
  - prove duplicate live plus inbox delivery does not duplicate media rows or attachments
  - verify outgoing upload failure/retry state for image, video, and voice sent by a newly-added member when existing hooks make this deterministic
- Why it is its own session:
  - descriptor persistence can pass while the user-visible media row is missing, stale, duplicated, or unplayable; this session owns that UI/recovery risk separately from send/receive correctness
- Likely code-entry files:
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_conversation_wired_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`
  - `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - `integration_test/foreground_group_push_drain_test.dart` when foreground media drain is in scope
- Likely named gates:
  - direct focused widget/application suites
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` if listener or inbox behavior changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if a new direct suite is added or reclassified
  - this breakdown ledger
- Dependency on earlier sessions:
  - `GNM-002` only if it creates shared media-send fixtures or helpers
- Closure result:
  - accepted on `2026-04-29`
  - plan artifact: `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-003-plan.md`
  - landed `test/features/groups/presentation/group_conversation_screen_test.dart`
  - direct verification passed: `flutter test test/features/groups/presentation/group_conversation_screen_test.dart`
  - direct verification passed: `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - direct verification passed: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
  - direct verification passed: `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
  - direct verification passed after explicit device selection: `flutter test -d macos integration_test/foreground_group_push_drain_test.dart`
  - evidence: the group conversation surface renders text plus video duration/play affordance, voice/audio affordance, and failed media state instead of silently omitting media
  - evidence: host-side inbox drain, retry, and foreground push paths preserve media attachments, avoid duplicate rows, and keep download/retry state truthful
  - follow-up evidence added by `GNM-005`: Android emulator and iPhone 17 simulator proof now cover new-member video and voice render/play/reopen behavior; process-kill restart, paired-simulator real-stack, and real-device/TestFlight proof remain final acceptance residuals

### Session GNM-004

- Title:
  `Announcement reader and removal boundary media parity`
- Session id:
  `GNM-004`
- Source cases:
  `NGM-011`, `NGM-012`, `NGM-013`, `NGM-021`, `NGM-022`, `NGM-023`, `NGM-024`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-004-plan.md`
- Exact scope:
  - verify newly-added announcement readers receive eligible post-join admin media and never receive pre-join media
  - verify role-eligible announcement sender media if writer posting is part of the current product contract; otherwise document the narrower admin-only evidence truthfully
  - preserve read-only announcement denial for text, image, video, and voice sends
  - preserve removed-before-send, removed-after-send, and dissolved-group media access boundaries
- Why it is its own session:
  - announcement and removal rules protect access control and should stay separate from discussion media send/recovery implementation
- Likely code-entry files:
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/features/groups/domain/models/group_model.dart`
  - `lib/features/groups/domain/models/group_member.dart`
- Likely direct tests/regressions:
  - `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - `test/features/groups/integration/announcement_happy_path_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
  - `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- Likely named gates:
  - direct focused suites
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` if shared group authorization, removal, or dissolved behavior changes
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md` if direct-suite classification changes
  - this breakdown ledger
- Dependency on earlier sessions:
  - none
- Closure result:
  - accepted on `2026-04-29`
  - plan artifact: `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-004-plan.md`
  - landed `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_membership_smoke_test.dart`
  - direct verification passed: `flutter test test/features/groups/integration/group_edge_cases_smoke_test.dart`
  - evidence: newly-added announcement readers receive only post-join admin image, video, and voice descriptors and complete three media-download attempts
  - evidence: the newly-added reader is denied text, image, video, and voice sends with `SendGroupMessageResult.unauthorized`, no `group:publish`, and no outgoing attempted rows
  - evidence: existing membership suites continue to prove removed and dissolved discussion users do not regain send or receive access through the covered host-side paths
  - accepted difference: current product code allows announcement sends only for `GroupRole.admin`; no writer-role announcement media claim is made

### Session GNM-005

- Title:
  `Simulator acceptance gate classification and final closure`
- Session id:
  `GNM-005`
- Source cases:
  final acceptance and closure for all source cases
- Session classification:
  `acceptance-only`
- Intended plan file:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-005-plan.md`
- Exact scope:
  - run or truthfully classify the direct suites and named gates needed for the finished sessions
  - verify whether simulator/device-backed coverage exists for the reported text-plus-video failure, visible video playback affordance, voice playback affordance, and restart persistence
  - update source doc status, closure references, gate definitions, and this breakdown with covered versus residual evidence
  - persist the final program verdict in this breakdown
- Why it is its own session:
  - this work validates multiple preceding slices and may legitimately end with explicit simulator/device-lab residuals even when host-side correctness is closed
- Likely code-entry files:
  - no product code expected
  - `scripts/run_test_gates.sh` only if test classification needs a narrow update
- Likely direct tests/regressions:
  - `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart`
  - `flutter test test/features/groups/integration/group_media_fanout_test.dart`
  - `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
  - direct suites added by `GNM-002`, `GNM-003`, or `GNM-004`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - simulator/device-backed smoke commands only when fixtures are available
- Likely named gates:
  - `./scripts/run_test_gates.sh completeness-check`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `./scripts/run_test_gates.sh group-real-network-nightly` only if the current plan touches that fixture-backed evidence
- Matrix/closure docs to update when done:
  - `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - this breakdown ledger and final verdict
- Dependency on earlier sessions:
  - `GNM-001`, `GNM-002`, `GNM-003`, and `GNM-004` resolved or explicitly blocked
- Closure result:
  - accepted with explicit follow-up on `2026-04-29`
  - plan artifact: `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-GNM-005-plan.md`
  - direct verification passed: `flutter test test/features/groups/integration/group_new_member_onboarding_test.dart test/features/groups/integration/group_media_fanout_test.dart test/features/groups/integration/announcement_new_reader_onboarding_test.dart test/features/groups/presentation/group_conversation_screen_test.dart`
  - named gate passed: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - Android emulator simulator proof passed: `flutter test -d emulator-5554 integration_test/group_new_member_media_simulator_proof_test.dart`
  - Android emulator companion media suites passed: `flutter test -d emulator-5554 integration_test/media_message_journey_e2e_test.dart`, `flutter test -d emulator-5554 integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d emulator-5554 integration_test/foreground_group_push_drain_test.dart`
  - iOS simulator proof passed on `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`): `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/group_new_member_media_simulator_proof_test.dart`
  - iOS simulator companion media suites passed on `iPhone 17` (`5BA69F1C-B112-47BE-B1FF-8C1003728C8F`): `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_message_journey_e2e_test.dart`, `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/media_stable_id_smoke_test.dart`, and `flutter test -d 5BA69F1C-B112-47BE-B1FF-8C1003728C8F integration_test/foreground_group_push_drain_test.dart`
  - completeness gate passed: `./scripts/run_test_gates.sh completeness-check` with `684/684` test files classified
  - docs updated: source report, discussion closure reference, announcement closure reference, test-gate definitions, and this breakdown
  - residual: true process-kill newly-added-member media restart persistence, broader paired-simulator real-stack coverage, and real-device/TestFlight playback remain explicit follow-up

## reviewer notes

- The decomposition intentionally reuses Report 85 evidence instead of recreating every receive-side app-layer test.
- The main uncovered source-doc gap is newly-added-member send coverage for image, video, and voice.
- Visible media behavior is separated because descriptor/download-trigger evidence can pass while the mobile conversation row still fails the reported user outcome.
- Announcement and removal boundaries are separate because access-control regressions have different direct tests and closure docs from discussion media fan-out.
- Simulator proof is kept as a final acceptance session because it depends on device availability and should not block host-side implementation sessions from recording truthful closure.

## arbiter notes

- Structural blockers:
  - none at decomposition time
- Mergeable sessions:
  - none; merging send, visible recovery, and role-boundary work would obscure distinct failure modes and gate requirements
- Required splits:
  - none beyond the five listed sessions
- Accepted differences:
  - Report 89 overlaps with Report 85 receive-side onboarding evidence; downstream plans should mark already-covered rows explicitly when current tests are sufficient
  - simulator/device-backed playback and restart evidence may close as `accepted_with_explicit_follow_up` or `residual_only` if the current environment lacks fixtures

## why this is not fewer sessions

- Receive proof, new-member send proof, visible media recovery, and access-control boundaries exercise different seams and need different direct regressions.
- Combining new-member media sends with retry/restart UI behavior would create a broad session that could pass descriptor checks while leaving the reported visible video failure unresolved.
- Combining discussion and announcement/removal behavior would risk changing access-control policy while chasing media delivery coverage.
- Final simulator and closure work depends on the evidence produced by earlier sessions and must be able to record residual device-lab gaps without reopening implementation slices.

## Final Program Verdict

- Verdict:
  `accepted_with_explicit_follow_up`
- Date:
  `2026-04-29`
- Source doc:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage.md`
- Breakdown artifact:
  `Test-Flight-Improv/89-group-new-member-send-receive-media-voice-coverage-session-breakdown.md`
- Summary:
  - host-side Report 89 coverage is accepted for newly-added discussion members receiving and sending text/image/video/voice media, visible media row rendering, inbox/retry/foreground-drain recovery, announcement reader receive/read-only behavior, and removed/dissolved host-side boundaries
  - final acceptance gates passed: focused direct suites, Android emulator simulator proof and companion media suites, iPhone 17 simulator proof and companion media suites, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`, and `./scripts/run_test_gates.sh completeness-check`
  - the rollout now claims Android emulator and iPhone 17 simulator render/play/reopen proof for representative newly-added-member video and voice rows; it does not claim process-kill restart persistence, paired-simulator real-stack coverage, or real-device/TestFlight playback
- Explicit follow-up:
  - run true process-kill restart persistence, broader paired-simulator real-stack coverage, and real-device/TestFlight playback checks for newly-added-member receive/send media rows when those fixtures are available
