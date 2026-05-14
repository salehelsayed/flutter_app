# GI-020 Session Plan: Inbox Replay Repairs Zero-Peer Publish

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-020`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 06:55:00 CEST | Controller | Source matrix GI-020 row; breakdown row 139; existing zero-peer send/inbox tests in `test/features/groups/application/send_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, and `test/features/groups/integration/group_membership_smoke_test.dart`; `send_group_message_use_case.dart`; `drain_group_offline_inbox_use_case.dart`; prior GI-019 closure artifacts | The source row remains `Open` and the breakdown marks GI-020 `evidence-gated` with missing exact row-owned proof. Existing GP-005/GP-015/GM-035 and Section 11 tests prove adjacent zero-peer and durable replay behavior, but no GI-020-named proof closes the reported A publishes/stores, B later retrieves, sender durable/sent scenario. | Add a narrow row-named GI-020 integration regression using the existing zero-peer bridge and cursor inbox harness. |

## Scope

GI-020 owns the app-level zero-live-peer durable fallback repair contract: when Alice publishes with no live peers but durable inbox store succeeds, Alice's sender row must be durable/sent and Bob must later recover the message exactly once from inbox replay.

Out of scope: inbox failure retry ownership, multi-recipient partial delivery, re-added-member first send, device-backed simulator proof, relay server persistence internals, non-member/revoked-device replay auth, and history repair integrity.

## Execution Contract

1. Add `test/features/groups/integration/group_resume_recovery_test.dart::GI-020 zero-peer publish is repaired by later inbox replay exactly once`.
2. Create Alice with `ZeroPeerPublishBridge` and Bob with `_CursorInboxBridge`.
3. Create a private group, add Bob, save matching key material, and unsubscribe Bob to force zero live topic peers.
4. Send a deterministic message id through Alice's real send use case and assert `successNoPeers`, returned/saved sender status `sent`, `inboxStored == true`, no retry payload, and emitted publish plus inbox-store commands.
5. Inject Alice's latest stored replay envelope into Bob's cursor inbox page, drain Bob's offline inbox, and assert Bob has exactly one incoming message with the deterministic id/text.
6. Drain Bob again and assert the replay remains exactly once, proving no duplicate resurrection.
7. Run focused GI-020 and adjacent zero-peer/replay selectors, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-020 integration replay proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GI-020'` |
| Adjacent Section 11 zero-peer fallback proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'publish with zero peers falls back to inbox'` |
| Adjacent GP-005 send-state proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-005 zero topic peers records durable fallback custody'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-019 artifacts. GI-020 scope is limited to the row-owned integration replay regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 07:04:00 CEST | Executor | Added `test/features/groups/integration/group_resume_recovery_test.dart::GI-020 zero-peer publish is repaired by later inbox replay exactly once`. The test creates Alice with `ZeroPeerPublishBridge` and Bob with `_CursorInboxBridge`, unsubscribes Bob to force zero live topic peers, sends deterministic message `gi020-zero-peer-replay`, asserts Alice returns `successNoPeers`, persists sender status `sent`, marks `inboxStored == true`, clears retry payload, and emits publish plus inbox-store commands. It injects Alice's latest durable replay envelope into Bob's inbox cursor page, drains Bob, proves Bob receives exactly one incoming id/text row, drains Bob again to prove dedupe remains exact-once, and verifies Alice's sender row remains durable/sent. | Covered the zero-peer durable inbox repair contract without production changes; existing send/drain behavior already satisfied the row once exact proof was added. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GI-020'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'publish with zero peers falls back to inbox'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-005 zero topic peers records durable fallback custody'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-020 is covered by exact Flutter integration zero-peer inbox repair evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-020; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-020 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 139, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-020 ownership and must not mask a repo-owned blocker.
