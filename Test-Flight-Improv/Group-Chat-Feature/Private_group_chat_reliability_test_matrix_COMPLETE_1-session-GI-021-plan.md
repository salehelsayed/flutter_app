# GI-021 Session Plan: Non-Member Sender Replay Rejection

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-021`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:45:00 CEST | Controller | Source matrix GI-021 row; breakdown row 140; existing replay signature, unknown-sender, live-listener, and handle-incoming tests; `lib/features/groups/application/group_offline_replay_envelope.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; prior GI-020 closure artifacts | The source row remains `Open` and the breakdown marks GI-021 `evidence-gated` with missing exact row-owned proof. Existing live and handle-incoming guards reject unknown senders, and offline replay signature verification checks current group membership before trusted signature verification or decrypt, but no GI-021-named inbox replay proof closes the stored-envelope retrieval path. | Add a narrow row-named Flutter offline replay regression proving a relay-stored envelope from a non-member is retrieved, rejected as `unknown_sender`, not signature-verified with untrusted material, not decrypted, and not rendered. |

## Scope

GI-021 owns the app offline replay authorization contract for a relay-stored group message whose signed replay envelope claims a sender that is not a current group member. The row closes only when the replay path proves the message is rejected and absent from the timeline.

Out of scope: live PubSub non-member publishing, delayed membership catch-up acceptance, revoked-device binding, zero-peer durable fallback, relay authorization internals, and device-backed simulator proof.

## Execution Contract

1. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-021 inbox replay rejects non-member sender without rendering`.
2. Seed a current private group and replay key while intentionally leaving `peer-non-member` absent from the member repository.
3. Build a signed group offline replay envelope claiming `peer-non-member`, store it in the cursor inbox page, and drain the inbox.
4. Assert the relay retrieve command ran, the row-owned message id/text is absent from the message repository and timeline, `payload.verify` is not called with untrusted sender material, and `group.decrypt` is not called.
5. Assert the flow event evidence includes `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED` with `unknown_sender`.
6. Run focused GI-021 and adjacent live/app unknown-sender regressions, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-021 offline replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` |
| Adjacent handle-incoming unknown-sender proof | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'rejects unknown sender when persisted removal cutoff belongs to another peer'` |
| Adjacent live-listener unknown-sender proof | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ER002 rejects unknown sender message before stream, storage, or notification'` |
| Delayed membership catch-up guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-020 artifacts. GI-021 scope is limited to the row-owned offline replay regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 07:16:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-021 inbox replay rejects non-member sender without rendering`. The test leaves `peer-non-member` absent from the group repository, builds a signed offline replay envelope claiming that non-member sender, stores it in the cursor inbox page, drains the inbox, proves `group:inboxRetrieveCursor` ran, proves the row-owned message id/text is absent from repository and visible timeline, proves `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED` reports `unknown_sender`, and proves neither `payload.verify` nor `group.decrypt` is called with untrusted non-member material. | Covered the non-member replay rejection contract without production changes; existing replay signature membership validation already rejects before trusted verification or decryption once exact proof was added. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'rejects unknown sender when persisted removal cutoff belongs to another peer'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'ER002 rejects unknown sender message before stream, storage, or notification'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GEK004 delayed membership config catch-up recovers newly accepted sender durable message exactly once'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-021 is covered by exact Flutter app offline replay evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-021; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-021 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 140, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-021 ownership and must not mask a repo-owned blocker.
