Status: execution-ready

# Session C Plan: Local-WiFi Durable Fallback

## Planning Progress

- 2026-06-11T20:19:49+0200 - Role: Arbiter completed. Files inspected since last update: complete Session C plan artifact and `git diff --check` for the plan file. Last completed command/result: mandatory sections are present and diff whitespace check passed. Decision/blocker: no structural blockers; plan is execution-ready. Next action: hand off compact final planning verdict.
- 2026-06-11T20:19:49+0200 - Role: Reviewer completed / Arbiter started. Files inspected since last update: complete Session C plan artifact. Last completed command/result: reviewer found simulator proof acceptable only as Session F-owned because the plan explicitly does not claim overall source closure from Session C host gates. Decision/blocker: no structural blocker; one incremental detail remains that exact `--plain-name` filters may need adjustment after test names land. Next action: arbiter classification.
- 2026-06-11T20:19:49+0200 - Role: Planner completed / Reviewer started. Files inspected since last update: drafted Session C plan sections. Last completed command/result: plan includes all mandatory sections plus Device/Relay Proof Profile. Decision/blocker: no blocker; review required for simulator-gate sufficiency and voice-scope ambiguity. Next action: sufficiency review.
- 2026-06-11T20:18:27+0200 - Role: Evidence Collector completed / Planner started. Files inspected since last update: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`, `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`, `lib/core/services/p2p_service.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart` fake P2P fixtures. Last completed command/result: graphify-arch symbol query surfaced `linkIncomingLocalMedia` and local media test nodes but not the sender upload branch; direct source reads were authoritative. Decision/blocker: no blocker; Session C remains implementation-ready as a narrow sender fallback slice. Next action: draft mandatory plan sections, then review for simulator-gate sufficiency.
- 2026-06-11T20:17:55+0200 - Role: Evidence Collector in progress. Files inspected since last update: source plan, session breakdown, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/features/conversation/application/link_incoming_local_media_use_case.dart`, `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_media_sender.dart`, `lib/core/local_discovery/local_media_server.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`. Last completed command/result: direct source reads show image/GIF local success skips `uploadMediaFn` today, voice local success returns before `sendVoiceMessageFn`, and local `media_uploaded` ACK is emitted after HTTP/SHA success before DB/local-path linking is proven. Decision/blocker: no blocker; default plan should keep relay upload fallback after local transfer success rather than add a new durable ACK protocol in Session C. Next action: finish evidence notes, draft the mandatory plan sections, then run Reviewer and Arbiter passes.

## Execution Progress

- 2026-06-11T20:22:22+0200 - Phase: contract extracted / local fallback selected. Files inspected or touched: Session C plan, session breakdown, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, scoped owner-file diffs for `conversation_wired.dart`, `conversation_wired_test.dart`, and `link_incoming_local_media_use_case_test.dart`; graph query run in `graphify-arch`. Last completed command/result: contract requires local transfer first, relay fallback after local success with stable media ID, voice alignment or explicit accepted difference, focused tests, `1to1`, explicit-device `transport`, `graphify update .`, and `git diff --check`; nested child-agent tooling is unavailable in this environment. Decision/blocker: no blocker; using the bounded local sequential fallback explicitly allowed by the user, with unrelated dirty owner-file edits preserved. Next action: local Executor adds failing-first image/GIF/file and voice regressions before production edits.
- 2026-06-11T20:41:47+0200 - Phase: progress heartbeat / local Executor not yet edited. Files inspected or touched: Session C plan has been updated with `## Execution Progress`; no Session C production or regression edits have been applied after the prior heartbeat. Last completed command/result: user progress request received after the first heartbeat was written; current plan section is present. Decision/blocker: no blocker; nested child-agent tooling remains unavailable, so bounded local sequential fallback continues. Next action: add the required image/GIF/file and voice failing-first regressions, then run the focused RED checks before production edits.
- 2026-06-11T20:56:14+0200 - Phase: local Executor RED regressions added. Files inspected or touched: `test/features/conversation/presentation/screens/conversation_wired_test.dart`. Last completed command/result: added local media ID/path capture to `FakeP2PService`, updated the local-peer GIF test to require `sendLocalMedia` before `uploadMedia` with the same stable ID, and aligned the voice local-transfer test to require `sendVoiceMessageFn` after local success with the same optimistic attachment ID. Decision/blocker: no blocker; production code not edited yet. Next action: run focused RED checks for `local-peer GIF transport` and `voice local transfer uses relay fallback`.
- 2026-06-11T20:57:30+0200 - Phase: local Executor RED checks completed. Files inspected or touched: `test/features/conversation/presentation/screens/conversation_wired_test.dart`; scoped diff reviewed before production edits. Last completed command/result: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "local-peer GIF transport"` failed at `pumpUntil` because `uploadMedia` was never called after local success; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "voice local transfer uses relay fallback"` failed at `pumpUntil` because `sendVoiceMessageFn` was never called after local success. Decision/blocker: no blocker; failures match intended pre-fix behavior. Next action: patch `conversation_wired.dart` so local media remains first but relay fallback still runs for attachment and voice sends.
- 2026-06-11T20:59:10+0200 - Phase: local Executor production edit completed. Files inspected or touched: `lib/features/conversation/presentation/screens/conversation_wired.dart`. Last completed command/result: removed the attachment local-success relay-skip branch so `sendLocalMedia` is attempted first and `uploadMediaFn` still runs with the same `mediaId`; removed the voice local-success early return so `sendVoiceMessageFn` still runs with the same `voiceAttachmentId`; voice UI now preserves relay-backed message media when returned. Decision/blocker: no blocker; unrelated pre-existing owner-file edits left intact. Next action: format touched Dart files and rerun focused GREEN checks.
- 2026-06-11T21:00:24+0200 - Phase: local Executor focused GREEN checks completed. Files inspected or touched: `lib/features/conversation/presentation/screens/conversation_wired.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`. Last completed command/result: `dart format lib/features/conversation/presentation/screens/conversation_wired.dart test/features/conversation/presentation/screens/conversation_wired_test.dart` completed; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "local-peer GIF transport"` passed; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "voice local transfer uses relay fallback"` passed. Decision/blocker: no blocker. Next action: run the required broader direct tests: `--plain-name "voice"`, `link_incoming_local_media_use_case_test.dart`, and full `conversation_wired_test.dart`.
- 2026-06-11T21:00:59+0200 - Phase: direct test failure triage. Files inspected or touched: `test/features/conversation/presentation/screens/conversation_wired_test.dart`. Last completed command/result: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "voice"` failed only in `swipe-to-reply voice send preserves quotedMessageId`; log shows `CONV_FL_VOICE_SEND_NO_BRIDGE` and `capturedQuotedMessageId` stayed null. Decision/blocker: pending fix, classified as caused by this session because the test fixture still asserted the old local-only voice path without a bridge/sendVoice fallback. Next action: update that fixture to provide `FakeBridge` and capture `quotedMessageId` through `sendVoiceMessageFn`, then rerun `--plain-name "voice"`.
- 2026-06-11T21:01:49+0200 - Phase: local Executor fix pass completed. Files inspected or touched: `test/features/conversation/presentation/screens/conversation_wired_test.dart`. Last completed command/result: updated the swipe-to-reply voice fixture to capture `quotedMessageId` through `sendVoiceMessageFn` with `FakeBridge`; `dart format test/features/conversation/presentation/screens/conversation_wired_test.dart` completed; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "voice"` passed. Decision/blocker: no blocker. Next action: run `flutter test test/features/conversation/application/link_incoming_local_media_use_case_test.dart`.
- 2026-06-11T21:09:25+0200 - Phase: direct test sweep in progress. Files inspected or touched: `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`, scoped diff stat for Session C owner files. Last completed command/result: `flutter test test/features/conversation/application/link_incoming_local_media_use_case_test.dart` passed, including persist-failure and error tests that prove local media ACK is not treated as durable app persistence. Decision/blocker: no blocker. Next action: run full `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`.
- 2026-06-11T21:10:00+0200 - Phase: direct test sweep completed. Files inspected or touched: `lib/features/conversation/presentation/screens/conversation_wired.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`, Session C plan file. Last completed command/result: full `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` passed; scoped `git diff --name-only` shows the Dart owner files while the plan remains untracked and updated separately. Decision/blocker: no blocker. Next action: run required named gate `./scripts/run_test_gates.sh 1to1`.
- 2026-06-11T21:18:53+0200 - Phase: named gates in progress. Files inspected or touched: Session C plan; Flutter device list inspected. Last completed command/result: `./scripts/run_test_gates.sh 1to1` passed; `flutter devices` found 12 connected devices plus one wireless device warning, including simulator `iPhone Air` with id `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`. Decision/blocker: no blocker; transport gate will use that explicit simulator. Next action: run `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`.
- 2026-06-11T21:27:13+0200 - Phase: named gates completed. Files inspected or touched: Session C plan and scoped status for owner files. Last completed command/result: `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport` passed; within the gate `background_reconnect_test.dart` was skipped by its own conditions, while `wifi_relay_fallback_smoke_test.dart`, `transport_e2e_test.dart`, and `media_stable_id_smoke_test.dart` passed on the explicit simulator. Decision/blocker: no blocker. Next action: run `graphify update .`, `git diff --check` on touched files, then local QA review.
- 2026-06-11T21:35:38+0200 - Phase: graph refresh and diff checks completed. Files inspected or touched: `graphify-out`, `graphify-arch`, Session C owner files, and the Session C plan. Last completed command/result: `graphify update .` completed AST refresh for 5034/5034 files and rebuilt `graphify-out`; HTML report generation was skipped by graphify because the graph is over the 5000-node limit. `git diff --check` passed for the touched Dart owner files and the plan file. Decision/blocker: no blocker. Next action: perform final local QA review and record execution verdict.
- 2026-06-11T21:35:38+0200 - Phase: local QA review completed / Session C verdict recorded. Files inspected or touched: `lib/features/conversation/presentation/screens/conversation_wired.dart`, `test/features/conversation/presentation/screens/conversation_wired_test.dart`, `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`, and this plan. Last completed command/result: local QA verified attachment sends still call `sendLocalMedia` before `uploadMediaFn` with the same stable `mediaId`, voice sends still call `sendLocalMedia` before `sendVoiceMessageFn` with the same `voiceAttachmentId`, focused RED failures were captured before production edits, focused GREEN tests and required gates passed, and no local protocol/server changes were made. Decision/blocker: Session C accepted with explicit follow-up; no blockers. Next action: none for Session C. Session F still owns final simulator matrix/source-report/closure evidence and overall source-plan closure.

## Final Execution Verdict

Verdict: `accepted_with_explicit_follow_up`.

Local fallback usage: nested Executor/QA child-agent tooling was unavailable in this Codex surface, so Session C used the bounded local sequential fallback allowed by the user and recorded above. A local Executor pass implemented the scoped change and a local QA pass reviewed it after tests and gates.

Session C is accepted because local-WiFi media remains attempted first for local peers, relay upload fallback now runs after local media success with the same stable media ID, final outgoing attachment metadata is relay-backed/recoverable, and voice is aligned to the same fallback rule. No durable ACK protocol or local protocol/server change was added.

Blocking issues remaining: none.

Non-blocking follow-up: Session F still owns final simulator proof, final matrix/source-report updates, closure-reference updates, and overall source-plan closure.

## Evidence Summary

- The source plan and breakdown both define Session C as the local-WiFi sender fallback slice: local transfer success must be a fast optimization, not the only durable copy, unless a durable receiver ACK is added after receiver DB/local-path persistence.
- `conversation_wired.dart` currently tries local media first for image/GIF/file attachments. When `sendLocalMedia` returns true, it saves a local `done` attachment and does not call `uploadMediaFn`.
- `conversation_wired.dart` has an analogous voice branch: when local voice media transfer succeeds, it sends the message through `sendChatMessageFn` with a local attachment and returns before the relay upload path through `sendVoiceMessageFn`.
- `LocalMediaSender` treats success as HTTP upload plus `media_uploaded` ACK, and `P2PService.sendLocalMedia` documents success as uploaded plus SHA-256 verified by the receiver. This proves byte receipt/hash validation, not receiver DB/local-path persistence.
- `LocalWsServer` sends `media_uploaded` immediately after `LocalMediaServer.handleUpload` succeeds. `LocalMediaServer` emits `LocalMediaReady` with a temp path before the later app-level link step.
- `linkIncomingLocalMedia` is the later receiver-side DB/local-path link. It can return `persistFailed`, `error`, or `skippedNotPending`; comments explicitly say relay fallback remains responsible for eventual delivery when local linking fails.
- Existing `conversation_wired_test.dart` currently pins the opposite image/GIF behavior by expecting no `uploadMedia` call after local success. Existing voice tests pin local success and stable local attachment behavior but do not prove relay fallback after local success.
- Existing `link_incoming_local_media_use_case_test.dart` covers pending link, delayed row, failed-row repair, done-row skip, persist failure, and error handling. It does not produce or consume a sender-side durable ACK.
- `test-gate-definitions.md` says 1:1 changes use `./scripts/run_test_gates.sh 1to1`, and transport fallback/local discovery changes use `./scripts/run_test_gates.sh transport`. `scripts/run_test_gates.sh` confirms the 1:1 and transport file lists.
- The source debug report confirms the risk: local-WiFi media can skip relay upload after an ACK that proves temp-file receipt, not durable receiver attachment linkage.

## Real Scope

Session C changes only the local-WiFi sender fallback behavior for direct 1:1 media sends.

In scope:

- Make local-WiFi media transfer success remain an optimization for fast peer delivery/display.
- Keep or create a relay-backed media copy after local media success by default.
- Preserve stable media IDs so the local transfer, relay upload, outgoing attachment metadata, and later receiver retry all refer to the same attachment identity.
- Update tests that currently expect local success to skip relay upload.
- Cover the receiver persistence-failure side as evidence that no durable ACK exists today and that relay fallback remains necessary.

Out of scope:

- New durable receiver ACK protocol unless implementation evidence proves it is smaller than retaining relay fallback. The default plan must not introduce one.
- Group media, public post media, feed media, migration transfer media, relay-server metadata, multi-relay Go failover, receiver orphan adoption, retry UI, duplicate replay repair, or thumbnail fallback.
- Final source-report, matrix, or 1:1 closure-reference updates; Session F owns those.

## Closure Bar

Session C is good enough for implementation acceptance when:

- The new image/GIF/file regression fails first because local success currently prevents relay upload.
- After implementation, local media success still calls the relay upload path using the same stable media ID and leaves the sent outgoing message with relay-backed media metadata.
- The existing local-media-first behavior still happens before relay fallback; local delivery is not removed.
- Voice media is explicitly handled: either aligned to the same durable fallback rule in this session with a focused regression, or recorded as an accepted difference with evidence that the source plan's Session C scope is limited to image/video/file attachments.
- `linkIncomingLocalMedia` persist-failure/error behavior remains non-crashing and continues to leave eventual delivery to relay fallback; no code assumes `media_uploaded` is durable.
- Focused Flutter tests pass, plus named `1to1` and `transport` gates pass when devices are available for transport integration tests.
- Full user-journey closure is not claimed from Session C host evidence alone. The source plan remains open until Session F runs or extends a 1:1 simulator scenario covering local-WiFi success plus relay fallback/retry.

## Source Of Truth

- Active Session C contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`.
- Source problem and session split: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Root-cause report: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Named gate source: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is the human-readable companion.
- Current code and tests win over stale prose when they disagree.

## Session Classification

`implementation-ready`.

Reason: the failing behavior is localized and directly testable in `conversation_wired_test.dart`; no new protocol is required for the default fix. The final multi-device simulator proof is required for the overall source plan but is Session F-owned by the breakdown.

## Exact Problem Statement

Direct 1:1 media sends can treat a local-WiFi upload ACK as sufficient durability. Today, the sender skips relay upload after `sendLocalMedia` returns true. That success means the receiver accepted the HTTP upload and verified bytes, but it does not prove that the receiver persisted the media to app-owned storage or linked the attachment row. If receiver linking later misses the envelope row, times out, or fails to persist, the receiver has no relay-backed copy to retry and the user can see permanently unavailable media.

Session C must make local-WiFi success a fast path, not the only copy. It must preserve local send speed while retaining a durable relay fallback for recovery.

## Files And Repos To Inspect Next

Production:

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/link_incoming_local_media_use_case.dart`
- `lib/core/services/p2p_service.dart`
- `lib/core/local_discovery/local_ws_server.dart`
- `lib/core/local_discovery/local_media_sender.dart`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart` if voice fallback is aligned in this session.

Tests:

- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/link_incoming_local_media_use_case_test.dart`
- `test/core/local_discovery/local_media_sender_test.dart` only if local ACK semantics are changed.
- `test/core/local_discovery/local_ws_server_test.dart` only if local WS ACK semantics are changed.

Docs/config:

- `Test-Flight-Improv/test-gate-definitions.md` only if new tests are added outside already classified direct suites.
- `scripts/run_test_gates.sh` for authoritative gate membership.

## Existing Tests Covering This Area

- `conversation_wired_test.dart` covers upload-pending persistence before upload starts, durable media prep, relay stable-ID upload, local-peer GIF transport, voice upload-pending persistence before local transfer, voice local stable-ID cleanup, voice relay fallback stable ID, upload progress, and upload cancellation.
- The current local-peer GIF test expects `uploadMedia` not to run after `sendLocalMedia` succeeds; this is now the regression target to invert.
- Existing voice local-success tests prove local media path behavior and cleanup, but not relay fallback after local success.
- `link_incoming_local_media_use_case_test.dart` covers local ready arriving before metadata, failed row repair, done row skip, persist failure, and error handling.
- `local_media_sender_test.dart` and `local_ws_server_test.dart` cover ACK/nonce/HTTP local media protocol mechanics. These should remain unchanged if Session C chooses relay fallback instead of durable ACK.

Missing:

- No test proves local success still uploads a relay fallback.
- No sender-side test proves the final outgoing attachment keeps a relay-backed stable ID after local success.
- No test proves `media_uploaded` is not treated as durable receiver persistence.

## Regression/Tests To Add First

1. In `conversation_wired_test.dart`, replace or add beside `local-peer GIF transport is attempted before relay upload fallback`:
   - Arrange local peer true and `sendLocalMedia` true.
   - Arrange `uploadMediaFn` to record `uploadMedia` and return a `MediaAttachment` with `id: blobId`.
   - Assert call order includes `save:upload_pending`, `sendLocalMedia`, then `uploadMedia`.
   - Assert `uploadMediaFn` receives the same stable `blobId` used for local media.
   - Assert final saved/sent attachment is `done`, has the stable ID, and has relay-backed metadata/local path from the upload result or finalized plan.

2. Add a focused voice regression in `conversation_wired_test.dart`, unless the implementer records voice as an accepted difference before coding:
   - Arrange local peer true and `sendLocalMedia` true for a voice recording.
   - Assert relay voice upload path still runs through `sendVoiceMessageFn` with the same `blobId`.
   - Assert local transfer is attempted first and the optimistic upload-pending attachment is cleaned up after relay-backed success.

3. Add or extend `link_incoming_local_media_use_case_test.dart` only as a negative durable-ACK guard:
   - Keep existing persist-failure test as evidence if unchanged.
   - If a durable ACK protocol is introduced despite the default plan, add tests proving ACK is emitted only after `updateLocalPath` succeeds and is not emitted on `persistFailed`, `error`, or unknown-row timeout.

Do not add local protocol tests if no ACK protocol changes are made.

## Step-By-Step Implementation Plan

1. Add the failing image/GIF/file regression first.
   - Start from the existing local-peer GIF test fixture and invert the expectation that `uploadMedia` is empty.
   - Keep the test focused on `ConversationWired`; do not involve real sockets.

2. Decide voice handling before production edits.
   - Preferred: align voice with the same fallback rule because `conversation_wired.dart` has the same local-success early return for voice.
   - Accepted difference option: keep voice unchanged only if the implementer documents evidence that Session C source scope is file/video/image media and schedules voice separately. Do not silently leave it out.

3. In `conversation_wired.dart`, remove the early relay-skip behavior after local media success for attachments.
   - Still call `sendLocalMedia` first when the peer is local.
   - Regardless of `localSuccess`, continue into relay upload unless a real durable receiver ACK exists.
   - Preserve stable `mediaId` and source path.
   - Avoid double-saving a final `done` local-only attachment that would clobber relay-backed metadata.

4. Preserve upload progress and cancellation behavior.
   - Ensure relay upload tracking starts when the relay fallback begins, even after local success.
   - Do not mark relay upload complete before the relay upload actually completes.
   - Keep cancellation cleanup behavior for active relay upload unchanged.

5. If aligning voice, refactor the voice local-success branch.
   - Keep `sendLocalMedia` as a first attempt.
   - Continue to the existing relay `sendVoiceMessageFn` path after local success.
   - Preserve `voiceAttachmentId`, waveform, duration, quoted-message data, and optimistic attachment cleanup.

6. Do not change `LocalMediaSender`, `LocalWsServer`, or `LocalMediaServer` unless implementing a durable ACK protocol.
   - If such protocol is attempted, stop and add explicit receiver-side ACK tests first.

7. Run focused tests and gates.

## Risks And Edge Cases

- Bandwidth increases because local success no longer suppresses relay upload. This is accepted for durability.
- Saving a local-only `done` attachment before relay upload could make receiver retry metadata ambiguous. Final outgoing attachment should be relay-backed while preserving local preview paths where needed.
- Stable IDs must not diverge between local offer, relay blob, attachment row, and message payload.
- Upload cancellation after local success must not send a final message that claims relay-backed media when relay upload was cancelled.
- Relay upload failure after local success should follow existing upload-failure UX and preserve the composer/draft state; do not mark the message delivered solely because local transfer succeeded.
- Voice may be an adjacent behavior because it shares the same local media API and early-return pattern. Leaving it unchanged should be explicit, not accidental.
- Dirty worktree contains many unrelated edits; implementation must not revert or normalize files outside the Session C owner set.

## Device/Relay Proof Profile

- Session C touches local discovery, transport fallback, stable media IDs, and 1:1 media behavior.
- Host/unit/widget proof can verify the sender wiring: local media attempted first, relay upload still invoked, stable ID preserved, and local ACK not treated as durable persistence.
- Host proof cannot prove the real two-device journey where receiver local temp upload succeeds, receiver persistence fails, and later retry recovers via relay.
- Therefore Session C can be implementation-accepted with focused host tests plus `1to1` and `transport` gates, matching the breakdown, but the overall source plan cannot be closed until Session F runs simulator evidence.
- Session F-owned simulator command to preserve in closure planning:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

- If Session C adds a new simulator scenario itself, it must be classified through Session F or `test-gate-definitions.md`; otherwise do not update final matrix/closure docs in Session C.

## Exact Tests And Gates To Run

Focused direct tests:

```sh
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "local-peer GIF transport"
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "voice"
flutter test test/features/conversation/application/link_incoming_local_media_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
```

Named gates:

```sh
./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport
```

Run `./scripts/run_test_gates.sh completeness-check` only if Session C adds or reclassifies a new integration, cross-feature, core-service, lifecycle, resilience, or orchestration test. It is not required for editing existing feature-local tests only.

Session F-owned simulator proof, not a Session C implementation gate:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

## Known-Failure Interpretation

- A local-worktree failure in unrelated dirty files is not a Session C blocker unless it affects the Session C owner files or named gates.
- The new local-WiFi fallback regression must fail before implementation for the intended reason: local success currently bypasses relay upload.
- If `transport` fails because no simulator/device is selected, rerun with explicit `FLUTTER_DEVICE_ID=<device-id>` and classify the first run as device-selection failure, not product regression.
- If `transport` fails inside `integration_test/wifi_relay_fallback_smoke_test.dart` or `integration_test/media_stable_id_smoke_test.dart`, treat it as potentially relevant until proven pre-existing.
- Do not treat missing Session F simulator evidence as Session C implementation failure; treat it as final source-plan closure still open.

## Done Criteria

- Plan owner files only are changed: primarily `conversation_wired.dart` and `conversation_wired_test.dart`; `link_incoming_local_media_use_case_test.dart` only if needed for the durable-ACK negative proof.
- New or updated Session C regression fails first and passes after implementation.
- Local media transfer is still attempted before relay upload for local peers.
- Relay upload fallback runs after local media success using the same stable media ID.
- Final outgoing media metadata remains recoverable through relay fallback.
- Voice is either aligned with the same durable fallback rule or explicitly documented as an accepted difference before implementation ends.
- Focused tests pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` passes or any device-selection issue is explicitly classified.
- No final source-report, matrix, or closure-reference updates are made in Session C unless new test classification requires `test-gate-definitions.md`.

## Scope Guard

Do not:

- Build a broad local-discovery protocol redesign.
- Add receiver durable ACK handshakes unless the default relay-fallback fix is proven unsafe or larger.
- Modify relay-server or Go media failover code.
- Modify receiver orphan adoption, retry UI, duplicate replay, resume recovery, or thumbnail fallback.
- Change group, post, feed, migration, push, or unrelated media widgets.
- Revert unrelated dirty worktree changes.
- Expand named gate membership unless new tests require classification.

Overengineering signs:

- New local media protocol states when a simple relay fallback preserves durability.
- Refactoring `P2PService` or local WS server APIs just to express "local temp upload succeeded".
- Combining Session D retry/replay work into this sender fallback slice.

## Accepted Differences / Intentionally Out Of Scope

- Final 1:1 simulator proof is intentionally Session F-owned. Session C records the command and requirement but does not close the overall source plan.
- A durable receiver ACK protocol is intentionally out of scope for the default implementation. If it is chosen, it must be proven with receiver DB/local-path persistence tests before it can replace relay fallback.
- Bandwidth cost from keeping relay upload after local success is accepted for correctness.
- Matrix/closure/source-report updates are deferred to Session F.
- Voice may be accepted as separate only with an explicit documented rationale; otherwise it should be aligned because it shares the same local media early-return risk.

## Dependency Impact

- Session D retry/replay work depends on Session C leaving a relay-backed copy to retry when local receiver persistence fails.
- Session E thumbnail work is independent but benefits from media state no longer being falsely terminal after local-only success.
- Session F simulator acceptance must include or discover a scenario that proves local-WiFi success plus relay fallback/retry.
- If Session C instead implements durable receiver ACK, Sessions D and F must refresh their assumptions around retry timing and receiver-side persistence proof.

## Reviewer Pass

Reviewer verdict: sufficient with one required adjustment captured in the plan.

Findings:

- Required simulator evidence is present but Session F-owned. This is acceptable only because the plan explicitly avoids claiming overall source closure from Session C host gates.
- The plan must not leave voice ambiguous. The done criteria now require either voice alignment or an explicit accepted difference before implementation ends.
- Direct tests and named gates are specific enough for implementation.
- No hidden scope expansion into Sessions D-F is present.

## Arbiter Pass

Structural blockers: none.

Incremental details:

- The exact `--plain-name` strings may need adjustment after the implementer names the new tests.
- `FLUTTER_DEVICE_ID` must be filled with an available simulator/device at execution time for the transport gate.

Accepted differences:

- Session C implementation acceptance can use host/focused gates, but final multi-device media proof remains Session F-owned.
- Durable ACK is not planned as the default fix.
