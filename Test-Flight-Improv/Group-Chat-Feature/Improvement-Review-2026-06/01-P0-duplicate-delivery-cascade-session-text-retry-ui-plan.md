Status: accepted_with_explicit_follow_up

# 01-P0 Duplicate Delivery Cascade - Session Plan: text-retry-ui

## Planning Progress

- 2026-06-03 18:55 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with host direct tests plus `./scripts/run_test_gates.sh groups`; no blocker. Next action: reviewer sufficiency pass.
- 2026-06-03 18:56 CEST - Reviewer started. Files inspected since last update: draft plan artifact. Decision/blocker: reviewing for missing tests, stale assumptions, simulator-gate rationale, and scope drift. Next action: record sufficiency findings and patch if structural issues exist.
- 2026-06-03 18:57 CEST - Reviewer completed. Files inspected since last update: draft plan artifact, `group_message.dart`. Decision/blocker: sufficient with two adjustments applied: removed stale deleted-message predicate and made l10n retry-failure copy exact. Next action: arbiter classification.
- 2026-06-03 18:58 CEST - Arbiter started. Files inspected since last update: reviewer-pass plan artifact. Decision/blocker: classifying review output; no new evidence requested. Next action: record final decision and execution readiness.
- 2026-06-03 18:58 CEST - Arbiter completed. Files inspected since last update: reviewer-pass plan artifact. Decision/blocker: no structural blockers remain; host-only closure accepted for this UI-wiring session. Next action: execute via the downstream implementation/QA workflow.

## Execution Progress

- 2026-06-03 19:21 CEST - Broad-gate failure classified as not session-owned. Files inspected or touched: `test/features/groups/integration/invite_round_trip_test.dart`, `/tmp/text-retry-ui-groups-gate.log`, this plan artifact, and reverted out-of-scope spawned-agent delta in `02-P0-undecryptable-messages-self-heal.md`. Command currently running: none. Decision/blocker: rerunning `flutter test test/features/groups/integration/invite_round_trip_test.dart --plain-name "GCA-004 bridgeError recovery drains inbox after settled materialized invite"` fails independently with the same assertion at `invite_round_trip_test.dart:2930` (`Expected: not null`, `Actual: <null>`), while `dart format --output=none --set-exit-if-changed` over touched text retry UI/test files passes with `0 changed`. The failure is outside `text-retry-ui` scope and touched files; no session-owned blocker remains. Next action: spawn a fresh closure child for `text-retry-ui` with the focused green tests and explicit unrelated broad-gate residual.
- 2026-06-03 19:19 CEST - Local execution fallback in progress after spawned Execution+QA produced scoped code/test deltas but no final verdict. Files inspected or touched: `/tmp/text-retry-ui-groups-gate.log`, scoped source/test/l10n files, and this plan artifact. Command currently running: none. Decision/blocker: focused session tests are green (`group_conversation_screen_test.dart --plain-name "failed outgoing text-only rows show retry"`, `group_conversation_wired_test.dart --plain-name "retry control re-sends the targeted failed outgoing text row"`, full `group_conversation_screen_test.dart`, full `group_conversation_wired_test.dart`, and `retry_failed_group_messages_use_case_test.dart` all passed); broad `./scripts/run_test_gates.sh groups` failed with the first concrete assertion at `test/features/groups/integration/invite_round_trip_test.dart` `GCA-004 bridgeError recovery drains inbox after settled materialized invite [E]`, `Expected: not null`, `Actual: <null>`. This failure is outside the text retry UI owner files and is being classified against the session scope before closure. Next action: verify whether the broad-gate failure reproduces independently or is unrelated, then either fix a session-owned issue or hand the session to closure with explicit residual gate evidence.
- 2026-06-03 19:11 CEST - Named gate failed. Files inspected or touched: changed source/tests/l10n plus plan artifact. Command currently running: none. Decision/blocker: `./scripts/run_test_gates.sh groups` exited 1 after direct focused/regression suites passed; visible output shows one failure in `test/features/groups/integration/group_messaging_smoke_test.dart` during the broad gate, but the captured stream is too large/truncated to classify yet. Next action: inspect gate failure details and fix only if the failure is caused by this session.
- 2026-06-03 19:08 CEST - Executor bounded wait extended. Files inspected or touched: this plan artifact, scoped diff list. Command currently running: nested Executor agent `019e8e70-818c-75c2-8d5d-f3f5b4919125` (`Ptolemy`). Decision/blocker: first bounded wait timed out, but real assigned-step progress exists (`group_conversation_screen.dart`, `group_conversation_wired.dart`, l10n files, and group screen/wired tests modified; focused screen regression triaged as session-caused). Next action: allow one additional bounded wait for Executor completion.
- 2026-06-03 19:08 CEST - Focused screen regression failed. Files inspected or touched: `group_conversation_screen_test.dart`, `group_conversation_screen.dart`, `group_conversation_wired.dart`, l10n ARBs/generated files. Command currently running: none. Decision/blocker: session-caused regression/test failure; `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "failed outgoing text-only rows show retry"` found zero `failed-message-retry-failed-text-retry` widgets. Next action: inspect the pure screen visibility conditions and fix only this session's text retry rendering path.
- 2026-06-03 19:03 CEST - Executor started/running. Files inspected or touched: this plan artifact. Command currently running: none. Decision/blocker: nested Executor accepted the `text-retry-ui` scope guard and will add regressions before production edits; no blocker. Next action: inspect named screen/wired/widget/l10n/test files and implement only the failed outgoing non-empty text-only group retry UI callback.
- 2026-06-03 19:02 CEST - Contract extracted. Files inspected or touched: this plan artifact only. Command currently running: none. Decision/blocker: scope is limited to failed outgoing non-empty text-only group retry UI/wired callback, l10n failure copy, row refresh, and preservation of existing failed-media retry/delete behavior; direct tests are the two focused text retry tests plus full screen/wired/use-case regression files and `./scripts/run_test_gates.sh groups`; no blocker. Next action: spawn isolated Executor with model `gpt-5.5` and reasoning_effort `xhigh`.
- 2026-06-03 19:03 CEST - Executor spawned/running. Files inspected or touched: this plan artifact. Command currently running: nested Executor agent `019e8e70-818c-75c2-8d5d-f3f5b4919125` (`Ptolemy`). Decision/blocker: spawned-agent isolation available; no blocker. Next action: bounded wait for Executor result, then inspect plan/test/code evidence.

## Closure Progress

- 2026-06-03 19:23 CEST - Closure auditor completed. Files inspected: this plan, the session breakdown, source proposal, `group_conversation_screen.dart`, `group_conversation_wired.dart`, l10n ARBs/generated localizations, `group_conversation_screen_test.dart`, and `group_conversation_wired_test.dart`. Decision/blocker: landed code matches the `text-retry-ui` contract; the only non-green evidence is the independently reproduced `GCA-004 bridgeError recovery drains inbox after settled materialized invite` failure in `invite_round_trip_test.dart`, outside this session's owner files and behavior. Next action: record the breakdown ledger as resolved with explicit follow-up for that unrelated broad-gate failure.

## Closure Verdict

Verdict: `accepted_with_explicit_follow_up`.

Closed for this session:

- `GroupConversationScreen` now exposes `onRetryFailedMessage` and only renders `LetterCard.onRetryFailedMessage` for failed outgoing non-empty text-only rows when the view is writable and the callback exists.
- Failed-media retry/delete remains on the existing media-only path; media rows with captions do not receive the text retry control.
- `GroupConversationWired._onRetryFailedMessage(String messageId)` calls the existing `retryFailedGroupMessage(messageId: ...)`, refreshes the hydrated row afterward, and shows `failed_message_retry_failed` when no row is retried.
- `GroupConversationWired` passes the text retry callback only when writable and `mediaAttachmentRepo` exists, without requiring `mediaFileManager` for text retry.
- `failed_message_retry_failed` is present in ARB files and generated localizations.
- Screen and wired regressions cover positive text retry, negative incoming/empty/sent/read-only/media cases, targeted same-id publish, untouched peer failed row, and refreshed visible `sent` row.

Verification recorded by execution:

- `dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_screen.dart lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_screen_test.dart test/features/groups/presentation/group_conversation_wired_test.dart` passed with 4 files formatted and 0 changed.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "failed outgoing text-only rows show retry"` passed.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "retry control re-sends the targeted failed outgoing text row"` passed.
- `flutter test test/features/groups/presentation/group_conversation_screen_test.dart` passed: 47 tests.
- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed: 105 tests.
- `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart` passed: 14 tests.

Residual-only / explicit follow-up:

- `./scripts/run_test_gates.sh groups` is not green because `test/features/groups/integration/invite_round_trip_test.dart` fails at `GCA-004 bridgeError recovery drains inbox after settled materialized invite`, `invite_round_trip_test.dart:2930`, with `Expected: not null`, `Actual: <null>`.
- The same `GCA-004` assertion failed under a focused reproduction command, so it is carried forward as an unrelated broad-gate follow-up rather than a blocker for this UI retry slice.

Still open outside this session:

- `text-continuation-id`, `voice-id-stable-retry`, `timeout-pending-retry`, `local-status-broadcasts`, `status-timestamp-migration`, `live-replay-dedup`, and `acceptance-doc-closure` remain unexecuted.
- No final whole-program verdict is persisted here.

Accepted differences:

- No failed text delete control was added; text retry mirrors the existing 1:1 failed-message retry affordance, while failed-media delete remains the media cleanup path.
- No send id semantics, voice upload behavior, bridge timeout, DB migration, local sweep broadcast, replay/live dedup, notification matrix, or source-doc final closure was changed in this session.

## real scope

Implement only the failed text-only outgoing group retry affordance and its wired callback:

- Add `onRetryFailedMessage` plumbing to `GroupConversationScreen`.
- Render `LetterCard.onRetryFailedMessage` only for failed, outgoing, text-only, non-empty group messages when the user can write and a callback is available.
- Add `GroupConversationWired._onRetryFailedMessage(String messageId)` that calls the existing `retryFailedGroupMessage(messageId: ...)`, then refreshes the row with `_refreshMessageWithHydratedMedia(messageId)`.
- Pass the text retry callback from `GroupConversationWired` to `GroupConversationScreen` when `_canWrite` and `mediaAttachmentRepo` are available.
- Preserve existing failed-media retry/delete behavior, including the `upload_pending` media snackbar/no-publish behavior and media delete cleanup.

This session does not implement text continuation id reuse, failed voice/upload-pending retry, bridge timeout changes, local sweep status broadcasts, DB migrations, live/replay dedup, notification behavior, or final matrix closure.

## closure bar

The session is good enough when host tests prove the UI exposes a Retry control for the exact failed text-only row that can be retried in place, the wired callback invokes `retryFailedGroupMessage(messageId: ...)` for that id, the refreshed `GroupConversationScreen` row reflects the persisted retry result, and existing failed-media retry/delete tests remain green.

Coverage ledger for the requested scope:

| Requirement | Planned proof |
|---|---|
| Group screen has `onRetryFailedMessage` for failed text-only outgoing rows | New `group_conversation_screen_test.dart` widget regression finds `ValueKey('failed-message-retry-<messageId>')` for a failed outgoing text-only row and tapping it reports that id. |
| Mirror 1:1 retry affordance | Use the same `LetterCard.onRetryFailedMessage` and `failedMessageActionKeySuffix` path that `conversation_screen.dart` already uses; no new visual widget. |
| Call existing `retryFailedGroupMessage(messageId: ...)` | New `group_conversation_wired_test.dart` regression seeds a failed text row with text-only retry payload, invokes `screen.onRetryFailedMessage!(id)`, and expects one `group:publish` plus a `sent` persisted row for the same id. |
| Refresh hydrated row after retry | The wired regression must observe the post-callback `GroupConversationScreen.messages` row status update or `CountingGroupMessageRepository.getMessageCalls` plus a repumped screen containing the updated row. |
| Preserve failed-media retry/delete behavior | Existing media tests in `group_conversation_screen_test.dart` and `group_conversation_wired_test.dart` continue to pass unchanged. |

Simulator/device profile: no session-local simulator or relay proof is required. This plan changes a host-testable UI-to-use-case callback and does not claim end-to-end duplicate-delivery closure; the breakdown assigns final device/relay acceptance and matrix ownership to `acceptance-doc-closure`.

## source of truth

- Active session contract: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade-session-breakdown.md`, session `text-retry-ui`.
- Product context: `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/01-P0-duplicate-delivery-cascade.md`.
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`; it defines `./scripts/run_test_gates.sh groups` for group retry behavior.
- Regression strategy context: `Test-Flight-Improv/14-regression-test-strategy.md`.
- Code and tests beat prose if they disagree. The breakdown's narrower scope wins over the source doc's broader cascade items and any phrasing that could imply text delete, text continuation, voice retry, or transport changes.

## session classification

`implementation-ready`

## exact problem statement

Failed outgoing text-only group messages currently render as failed but have no in-place Retry control. The shared `LetterCard` widget supports failed-message retry, and 1:1 conversations wire that affordance, but the group screen only computes failed-media actions and only passes `onRetryFailedMedia` / `onDeleteFailedMedia`. The group retry use case already supports text-only failed rows and same-id retry, but the group UI cannot reach it for text rows.

The user-visible improvement is that a failed outgoing text group message can be retried from the failed row without retyping. Existing media retry and failed media delete controls must continue behaving exactly as they do now.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart` as read-only reference unless a compile issue proves otherwise
- `lib/features/conversation/presentation/screens/conversation_screen.dart` and `conversation_wired.dart` as 1:1 reference only
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart` as the existing call target, not a planned behavior-change file
- `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`, and generated `app_localizations*.dart` for the localized `failed_message_retry_failed` string

Tests:

- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` only if a focused single-text retry unit proof is added or the use case behavior is touched
- `Test-Flight-Improv/test-gate-definitions.md` only if a new high-value test file is created; no update is needed for new tests inside existing files

## existing tests covering this area

- `group_conversation_screen_test.dart` already proves failed outgoing media rows show retry/delete controls and tap the correct ids.
- The same screen test already proves failed-media controls are hidden for incoming rows, text-only rows, and read-only rows. That text-only expectation must be narrowed so it remains a failed-media assertion and does not block the new failed-message retry affordance.
- `group_conversation_wired_test.dart` already proves the media retry callback re-sends only the targeted failed outgoing media row, leaves another failed media row untouched, and preserves upload-pending media retry as snackbar/no-publish.
- `retry_failed_group_messages_use_case_test.dart` already proves text-only failed rows retry in place using original ids, and that failed text rows can retry from `wireEnvelope` when `inboxRetryPayload` was cleared.
- `retry_failed_group_messages_use_case_test.dart` also proves `retryFailedGroupMessage` targets a single failed media row, but it does not currently isolate single-target text retry.

## regression/tests to add first

Add or update tests before production edits:

1. In `group_conversation_screen_test.dart`, add a widget test for a failed outgoing text-only row with non-empty text, `canWrite: true`, and `onRetryFailedMessage`. It should find `ValueKey('failed-message-retry-<id>')`, tap it, and assert the callback receives `<id>`. It should also assert no failed-media retry/delete keys are shown for that text row.
2. In `group_conversation_screen_test.dart`, add negative coverage or extend the same test to prove no failed-message retry appears for incoming failed text, read-only failed text, empty-text failed rows, non-failed outgoing text, or failed media rows that should keep media actions.
3. In `group_conversation_wired_test.dart`, add a widget test that seeds a failed outgoing text row with a text-only retry payload, supplies `mediaAttachmentRepo`, invokes `GroupConversationScreen.onRetryFailedMessage!(messageId)`, and asserts one `group:publish`, same persisted message id, final `sent` status, and refreshed visible screen row.
4. Add a `retry_failed_group_messages_use_case_test.dart` single-target text regression only if the wired test cannot precisely prove the use-case call or if implementation touches the use case. Existing use-case text retry and single-target media retry coverage are otherwise sufficient.

## step-by-step implementation plan

1. Add `ValueChanged<String>? onRetryFailedMessage` to `GroupConversationScreen`, constructor wiring, and the test helper in `group_conversation_screen_test.dart`.
2. In the group message item builder, compute `showFailedTextRetry` using the 1:1 predicate as the model: writable, sent by own peer, `status == 'failed'`, no media after resolving `mediaMap`, non-empty trimmed text, and callback present.
3. Pass `onRetryFailedMessage: showFailedTextRetry ? () => onRetryFailedMessage!(message.id) : null` and `failedMessageActionKeySuffix: message.id` into `LetterCard`. Keep `onRetryFailedMedia`, `onDeleteFailedMedia`, and `failedMediaActionKeySuffix` unchanged.
4. Add `_onRetryFailedMessage(String messageId)` to `GroupConversationWired`. It should require `mediaAttachmentRepo`; if absent, show the existing generic retry-unavailable snackbar and return.
5. In `_onRetryFailedMessage`, call `retryFailedGroupMessage(messageId: messageId, groupMsgRepo: widget.msgRepo, groupRepo: widget.groupRepo, identityRepo: widget.identityRepo, bridge: widget.bridge, mediaAttachmentRepo: mediaAttachmentRepo)`.
6. After the call, invoke `_refreshMessageWithHydratedMedia(messageId)` even for text-only rows so the open screen reflects the persisted status update.
7. If `retried == 0`, show `AppLocalizations.of(context)!.failed_message_retry_failed`. Add `failed_message_retry_failed` to the English, German, and Arabic ARB files and regenerate checked-in localizations, matching the group screen's existing localized retry snackbar pattern.
8. Pass `onRetryFailedMessage: _canWrite && widget.mediaAttachmentRepo != null ? _onRetryFailedMessage : null` when constructing `GroupConversationScreen`. Do not require `mediaFileManager` for text-only retry.
9. Run direct tests. If any existing failed-media retry/delete test fails, stop and fix the regression before broadening anything.
10. Run the named group gate.

Stop early if code inspection after the red tests shows the group screen already gained equivalent `onRetryFailedMessage` wiring from concurrent work; in that case, tighten tests and classify the session as `stale/already-covered` only if all closure-bar proofs already pass.

## risks and edge cases

- Media rows with text captions must continue using media retry/delete, not the new text retry button.
- Read-only or dissolved group views must not expose text retry.
- Incoming failed rows must not expose retry.
- Empty text-only failed rows should not expose text retry because there is no user-visible message body to retry and it may represent unsupported payload state.
- `mediaAttachmentRepo` is optional in `GroupConversationWired`; the text retry callback must not be wired when the use case cannot run.
- The retry use case can return `0` for missing identity, unsupported payload, non-failed row, or still-failed send; the UI should refresh and then show failure feedback without deleting or restoring composer state.
- This session must not alter upload-pending media behavior, failed media delete cleanup, or restored media continuation tracking.

## exact tests and gates to run

Focused direct tests during implementation:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart --plain-name "failed outgoing text-only rows show retry"
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "retry control re-sends the targeted failed outgoing text row"
```

Direct regression files before closure:

```bash
flutter test test/features/groups/presentation/group_conversation_screen_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
```

Named gate:

```bash
./scripts/run_test_gates.sh groups
```

Run `flutter gen-l10n` before tests after adding the new l10n key.

No `$run-flutter-reliability-sims` command is part of this session's closure; end-to-end duplicate delivery simulator/device proof belongs to later acceptance work after all send/retry/dedup sessions land.

## known-failure interpretation

The new direct tests should fail on current code before implementation because `GroupConversationScreen` has no `onRetryFailedMessage` field and `GroupConversationWired` passes no text retry callback. After implementation, all direct tests listed above must pass.

If `./scripts/run_test_gates.sh groups` fails in an unrelated pre-existing integration suite, keep the direct tests green, capture the failing suite and reason, and do not classify this session closed unless the failure is demonstrably unrelated to changed files and no failed-media retry/delete regression is present.

## done criteria

- `GroupConversationScreen` exposes `onRetryFailedMessage` and renders `failed-message-retry-<id>` for failed outgoing non-empty text-only rows only.
- Tapping the text retry action invokes the callback with the exact message id.
- `GroupConversationWired` wires text retry when writable and `mediaAttachmentRepo` is available, without requiring `mediaFileManager`.
- `_onRetryFailedMessage` calls `retryFailedGroupMessage(messageId: ...)`, refreshes the hydrated row after the call, and shows failure feedback when `retried == 0`.
- The wired regression proves one same-id publish and a refreshed `sent` row for the targeted failed text message.
- Existing failed-media retry, upload-pending retry feedback, and delete tests still pass.
- Direct tests and `./scripts/run_test_gates.sh groups` pass or have a documented unrelated known-failure interpretation accepted by the execution reviewer.
- No new test-gate classification doc update is needed unless a new test file is created.

## scope guard

Do not:

- Add a failed text delete control in this session; the title's delete concern is preserving existing failed-media delete wiring.
- Change retry id semantics, restored composer continuation, voice recording retry, upload-pending media retry, bridge timeout, pending recovery, DB schema, local status broadcast, live/replay dedup, notifications, or matrix closure.
- Modify `LetterCard` visuals unless the existing text retry hook is broken.
- Change `retryFailedGroupMessage` behavior unless a direct regression proves the existing text-only support is stale.
- Add simulator/device harness work to this session.
- Update broad docs or matrices except `test-gate-definitions.md` if a new high-value test file must be classified.

## accepted differences / intentionally out of scope

- Text delete is intentionally out of scope. Failed text retry mirrors the 1:1 retry affordance, while media delete remains the existing group media cleanup path.
- End-to-end "recipient receives exactly one copy" proof is intentionally out of scope here because this session only exposes existing same-id retry plumbing. Later sessions and `acceptance-doc-closure` own duplicate-delivery journey proof.
- Local-only background sweep refresh gaps remain out of scope; this session refreshes only after the user-triggered retry callback.
- Generated l10n files for the new failed-text retry failure string are an implementation detail, not a product-scope expansion.

## dependency impact

This session unblocks `text-continuation-id` and `voice-id-stable-retry` by establishing the shared failed-row action convention in group UI. If this plan changes to include text delete, use-case behavior changes, or simulator proof, later sessions should be refreshed because their dependency assumptions about UI-only scope would no longer hold.

## reviewer pass

Verdict: sufficient with adjustments applied.

- Missing files/tests/gates: no structural gaps after adding the l10n files as planned production touches. Existing direct tests plus the new screen/wired regressions and `./scripts/run_test_gates.sh groups` are sufficient for this UI-wiring session.
- Stale assumptions corrected: `GroupMessage` has no deleted-message field, so the predicate must not include `isDeleted`.
- Simulator gate review: no session-local simulator gate is required because the plan does not claim cross-device duplicate-delivery closure and assigns that proof to later acceptance work.
- Overengineering review: adding text delete, send semantics, voice retry, transport timeout, or schema work would be scope drift.
- Decomposition review: the work is narrow enough for implementation; the executor can add tests first, wire one screen callback, wire one wired callback, and stop.

## arbiter decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact test names may differ from the suggested `--plain-name` filters, but the tests must cover the same behaviors.
- A new single-target text use-case unit test is optional unless implementation touches `retry_failed_group_messages_use_case.dart` or the wired test cannot isolate the use-case call.

Accepted differences intentionally left unchanged:

- No text delete control in this session.
- No session-local simulator or relay proof; final duplicate-delivery journey proof belongs to later acceptance work.
- No matrix or closure-doc update unless a new test file needs gate classification.

Why the plan is safe to implement now: it is grounded in current code evidence, has regression-first host tests, preserves the existing media path, includes an exact named gate, and has an explicit scope guard against the broader duplicate-delivery cascade work.
