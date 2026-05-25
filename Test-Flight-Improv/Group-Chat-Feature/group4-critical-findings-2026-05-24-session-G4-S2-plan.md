Status: execution-ready

# Group4 Critical Findings 2026-05-24 Session G4-S2 Plan

## Planning Progress

- 2026-05-24T01:24:36+02:00 - Planner intake started and confirmed G4-S2 target path.
- 2026-05-24T01:28:50+02:00 - Spawned planner collected evidence but did not produce an execution-ready plan under bounded wait.
- 2026-05-24T01:35:00+02:00 - Controller local plan fallback used. Breakdown entry is execution-safe, rows are implementation-ready, and this artifact is scoped to G4-S2 only.

## Scope

Rows: G4-001, G4-010, G4-011, G4-012, G4-013, G4-014, G4-015, G4-016, G4-017, G4-018, G4-020.

Implement only group conversation/media/send-state/read/reaction fixes:

- cast `clamp()` results to the expected static types in `GroupConversationWired`
- validate actual file bytes before durable group upload rows and retry uploads
- reject `application/octet-stream` for group media sends/retries
- align display resolution with `GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia`, allowing missing encryption metadata only for local outgoing owned media
- when restoring the composer after upload/send failure, remove old durable retry state so the user cannot create duplicate sends by re-sending restored attachments
- persist successful media uploads immediately when another attachment fails
- stabilize voice attachment local paths to owned media storage before deleting pending upload dirs
- guard background task begin/end so `_isSending` always resets
- reset group conversation state/subscriptions on group id changes
- gate group read marking on foreground active visibility
- rollback optimistic reaction add/remove on non-success and exceptions

Non-goals:

- no notification routing/dedupe changes beyond the already closed G4-S1 contract
- no lifecycle pause/resume/retry-concurrency changes from G4-S3
- no schema lease migrations
- no Go/relay changes
- no broad UI redesign

## Owner Files

Production:

- `lib/core/media/group_media_mime_policy.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`

Tests:

- `test/core/media/group_media_mime_policy_test.dart`
- `test/core/media/group_media_integrity_policy_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`

Docs:

- `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-breakdown.md`

## Implementation Steps

1. Add focused regressions for the rows where existing tests currently encode the unsafe behavior, especially octet-stream acceptance, partial upload persistence, restored-composer retry cleanup, background end failure, group change reset, read gating, and reaction rollback.
2. Patch `GroupMediaMimePolicy` to remove generic octet-stream from allowed group media and make unknown signature handling reject suspicious known mismatches while accepting only allowed declared MIME values.
3. Patch `GroupConversationWired` in narrow helpers:
   - `_activeGroupConversationKey`
   - `_canMarkVisibleRead`
   - `_markVisibleReadIfAllowed`
   - `_validatePreparedGroupMediaFile`
   - `_cleanupRestoredComposerRetryState`
   - `_buildStableVoiceAttachment`
4. Patch durable media upload preparation and retry preparation to call `GroupMediaMimePolicy.validateFile`.
5. Patch upload result handling to save successful completed attachments before returning failure for failed plans.
6. Patch `_onSend` and voice send background task cleanup so `callBgEnd` errors are logged and `_endSendFlow()` runs in a nested `finally`.
7. Patch `didUpdateWidget` to reset group-bound message/media/reaction/load state and restart subscriptions when the group id changes.
8. Patch `_loadMessages` and `_applyMessageUpdate` to mark read only when the app is resumed and the active tracker key matches.
9. Patch optimistic reaction add/remove to restore the prior reaction list on any non-success or thrown exception, preserving dissolved-group refresh behavior.
10. Run focused tests and update matrix/breakdown evidence.

## Tests And Gates

Direct focused tests:

```bash
flutter test test/core/media/group_media_mime_policy_test.dart
flutter test test/core/media/group_media_integrity_policy_test.dart
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

Useful combined suites after direct tests:

```bash
flutter test test/core/media
flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart
```

Named gates when direct tests are green:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known residual classification from G4-S1: broad `groups`, `baseline`, and `completeness-check` have unrelated dirty-worktree failures outside notification/push scope. Reclassify for G4-S2 only if the failing signature touches G4-S2 owner behavior.

## Done Criteria

- G4-001/G4-010/G4-011/G4-012/G4-013/G4-014/G4-015/G4-016/G4-017/G4-018/G4-020 are Closed or Covered in the matrix with concrete file/test evidence.
- Focused direct tests pass, or any failure is proven pre-existing and outside G4-S2 owner files.
- Scoped `git diff --check` passes for owner files and docs.
- Source matrix and breakdown ledger are updated for G4-S2 only.

## Scope Guard

Do not touch lifecycle pause/resume retry logic, group recovery ack, retry leases, notification route parsing, notification dedupe, foreground push fallback, schema migrations, or broad group membership implementation. If a test failure points there, record it as G4-S3 or unrelated unless the failure is caused by this session's owner files.

## Dirty Worktree Caution

The repo is already heavily dirty, including group-chat code, tests, docs, Go, relay, Android, and iOS files. Preserve unrelated hunks. Do not reset, checkout, or reformat unrelated files. Inspect owner files before editing and report overlap if it blocks safe changes.

## Reviewer Findings

Local fallback reviewer verdict: execution-ready. The plan is narrow enough to code safely, lists owner files/tests/gates/done criteria/scope guard, and separates G4-S2 from closed G4-S1 and pending G4-S3.

## Arbiter Decision

Proceed to execution for G4-S2. No structural blocker.

## Execution Progress

- 2026-05-24T01:35:15+02:00 - contract extraction started. Files inspected: plan, skill contract, git status, scoped owner/test diff. Decision: spawned nested agents are not exposed in this worker; because this is the fresh isolated G4-S2 execution worker, use the skill's local sequential fallback and record Executor/QA evidence here. Next action: complete contract extraction and inspect scoped owner files/tests before edits.
- 2026-05-24T01:35:15+02:00 - contract extracted. Scope: G4-S2 rows only across group media MIME/file validation, group conversation media/send/read/reaction state, incomplete group upload retry, focused tests, and G4-S2 docs. Non-goals confirmed: no lifecycle pause/resume retry logic, notifications, schema, Go/relay, or broad membership changes. Required direct tests: five focused flutter test commands listed in Tests And Gates. Named gates: groups and completeness-check after direct tests, with known unrelated dirty-worktree failure classification from the plan. Next action: Executor inspect scoped files and add regressions/implementation.
- 2026-05-24T01:35:15+02:00 - Executor implementation started. Files to touch: `lib/core/media/group_media_mime_policy.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`, focused tests, and G4-S2 docs only. Decision: preserve existing dirty hunks in `GroupConversationWired` and tests; no lifecycle retry, notification, schema, Go, or relay edits. Next action: land regressions and narrow fixes.
- 2026-05-24T01:35:15+02:00 - Executor implementation completed. Files touched: G4-S2 production files and focused tests only. Changes: octet-stream removed from group media allow-list; durable send, voice send, and retry upload now validate file bytes; clamp results cast; background begin/end guarded; restored composer terminalizes old upload-pending retry rows; partial upload successes persist immediately; voice upload rows stabilize to owned media paths; resolver quarantines incoming unencrypted done media while allowing local outgoing owned media; group id changes reset group-bound state/subscriptions; read marking gates on resumed active visibility; optimistic reactions roll back on non-success/throw. Fast structural validation: `dart analyze lib/core/media/group_media_mime_policy.dart lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` passed. Next action: run required direct tests and gates.
- 2026-05-24T01:35:15+02:00 - Direct test phase started. Command currently running next: `flutter test test/core/media/group_media_mime_policy_test.dart`. Next action: run all five focused direct tests, then named gates if direct tests are green or classify any failure first.
- 2026-05-24T01:35:15+02:00 - Direct test finished: `flutter test test/core/media/group_media_mime_policy_test.dart` passed (`+6`). Command currently running next: `flutter test test/core/media/group_media_integrity_policy_test.dart`.
- 2026-05-24T01:35:15+02:00 - Direct test finished: `flutter test test/core/media/group_media_integrity_policy_test.dart` passed (`+6`). Command currently running next: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`.
- 2026-05-24T01:35:15+02:00 - Direct test finished: `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed (`+15`). Command currently running next: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`.
- 2026-05-24T01:59:30+02:00 - Direct widget test triage/fix pass: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` initially exposed remaining G4-S2 failures in the new media-display regression and two additional widget cases. Root cause for the media-display failure: the resolver performed extra file hash I/O for attachments that already failed `canDisplayVerifiedGroupMedia` due missing encryption metadata, leaving the widget test stuck before state publication. Fix landed in `group_conversation_wired.dart`: missing-encryption display gating now quarantines non-allowed incoming media and allows only local outgoing owned media from valid persisted hashes before file existence work. Regression adjusted to drive the live resolver path. Targeted command `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "incoming done media without encryption metadata is quarantined but local outgoing owned media can display" --reporter expanded` passed. Next action: rerun full focused widget suite.
- 2026-05-24T02:03:57+02:00 - Direct focused tests completed. `dart analyze lib/core/media/group_media_mime_policy.dart lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` passed; `dart analyze test/features/groups/presentation/group_conversation_wired_test.dart` passed. Required direct tests: `flutter test test/core/media/group_media_mime_policy_test.dart` passed (`+6`), `flutter test test/core/media/group_media_integrity_policy_test.dart` passed (`+6`), `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` passed (`+15`), `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed (`+98`), and `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` passed (`+18`). Additional fix-pass detail: `GroupMediaMimePolicy.validateFile` now keeps the async API but reads the first 64 bytes synchronously, preventing widget-test fake-async stalls while preserving send/retry byte validation. Next action: run required named gates `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh completeness-check`.
- 2026-05-24T02:07:40+02:00 - Required named gates completed. `./scripts/run_test_gates.sh groups` was run once to terminal output and once to `/tmp/g4s2_groups_gate.log`; it failed at `+261 -40`. Failure signatures are in broad invite/membership/rejoin/resume integration paths, including `SendGroupInviteResult.invalidPayload`, `Bad state: Stale group membership event`, missing replayed messages, pending/sent expectation mismatches, and `GM-028` empty peer-id membership expectation; these are outside G4-S2 owner behavior and consistent with already dirty group integration residuals. `./scripts/run_test_gates.sh completeness-check` failed at `744/746`, with unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart` and `test/shared/fakes/seeded_group_reproduction_log_test.dart`; both are outside G4-S2 owner files. Decision/blocker: no G4-S2 blocker from named gates. Next action: update G4-S2 matrix/breakdown closure docs, then perform scoped QA.
- 2026-05-24T02:07:40+02:00 - Closure docs update started. Files to touch: source matrix, session breakdown, and this plan only. Decision/blocker: close only rows G4-001/G4-010/G4-011/G4-012/G4-013/G4-014/G4-015/G4-016/G4-017/G4-018/G4-020 with focused evidence; keep G4-S3 lifecycle/retry rows unresolved. Next action: run scoped diff hygiene and local QA review.
- 2026-05-24T02:14:04+02:00 - Local QA review completed with two scoped hardening fixes before verdict. Findings/fixes: `GroupMediaMimePolicy.validateFile` now returns `unreadable_file` instead of throwing when the file cannot be opened, and the group media resolver no longer lets incoming `done` media on pending-upload paths bypass the missing-encryption display gate. Post-QA validation passed: `dart analyze` on the three production owner files, `dart analyze test/features/groups/presentation/group_conversation_wired_test.dart`, `flutter test test/core/media/group_media_mime_policy_test.dart` (`+6`), `flutter test test/core/media/group_media_integrity_policy_test.dart` (`+6`), `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart` (`+15`), `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` (`+18`), and `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` (`+98`). Next action: rerun required named gates on the final code snapshot.
- 2026-05-24T02:14:04+02:00 - Final required named gates rerun on post-QA code. `./scripts/run_test_gates.sh groups` failed at `+261 -40`; log: `/tmp/g4s2_groups_gate_final.log`. Failures remain in broad invite/membership/startup/rejoin/resume integration paths and not in G4-S2 media MIME, upload retry, conversation widget, background task, read, or reaction focused coverage. `./scripts/run_test_gates.sh completeness-check` failed at `744/746`; log: `/tmp/g4s2_completeness_gate_final.log`, with the same unmatched shared fake test files. Decision/blocker: no G4-S2 blocking issue remains; named gate failures are explicit unrelated follow-up.
- 2026-05-24T02:14:04+02:00 - Final verdict written. Files touched since closure-doc update: this plan and G4-S2 owner code only. Command currently running: none. Decision/blocker: verdict `accepted_with_explicit_follow_up`; no additional fix pass required. Next action: hand off changed paths, test results, and classified residuals.

## Final Execution Verdict

- Final verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: no nested spawn tool was available in this tool session; this worker proceeded as the fresh isolated execution+QA worker using the skill's local sequential fallback.
- Local sequential fallback used: yes.
- Blocking issues remaining: none for G4-S2.
- Non-blocking follow-ups deferred: clean the unrelated broad group invite/membership/rejoin/resume residuals causing `./scripts/run_test_gates.sh groups` to fail, and classify the already documented unmatched shared fake tests so `./scripts/run_test_gates.sh completeness-check` returns green.
- Why safe to consider G4-S2 complete: the eleven scoped rows have owner-code fixes and focused regression coverage, all direct G4-S2 analyzers/tests pass on the final code snapshot, G4-S1 notification work was preserved, G4-S3 lifecycle/retry rows remain unresolved, and broad red gates are outside G4-S2 owner behavior.

## Fresh Closure Review - 2026-05-24 02:21 CEST

- Review verdict: `accepted_with_explicit_follow_up`.
- Rows verified: G4-001, G4-010, G4-011, G4-012, G4-013, G4-014, G4-015, G4-016, G4-017, G4-018, and G4-020 remain `Closed` in the source matrix with code/test evidence; no G4-S3 row was reclassified.
- Re-run direct gates: `dart analyze lib/core/media/group_media_mime_policy.dart lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart` passed; `dart analyze test/features/groups/presentation/group_conversation_wired_test.dart` passed; `flutter test test/core/media/group_media_mime_policy_test.dart test/core/media/group_media_integrity_policy_test.dart` passed (`+12`); `flutter test test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` passed (`+131`).
- Persisted named gate evidence verified: `/tmp/g4s2_groups_gate_final.log` fails at `+261 -40` in broad invite/membership/rejoin/resume signatures outside G4-S2 owner behavior; `/tmp/g4s2_completeness_gate_final.log` fails at `744/746` on unmatched shared fake tests.
- Closure rule: reopen G4-S2 only if media MIME/file validation, durable send/retry state, voice path durability, read gating, group-id reset, or optimistic reaction rollback tests regress, or if a broad red gate is newly traced to those owner behaviors.
