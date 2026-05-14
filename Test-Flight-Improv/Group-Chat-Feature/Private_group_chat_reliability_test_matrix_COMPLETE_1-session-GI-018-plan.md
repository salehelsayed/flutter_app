# GI-018 Session Plan: Removed Member Replay Stops At Removal Cutoff

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-018`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 06:10:00 CEST | Controller | Source matrix GI-018 row; breakdown row 137; existing self-removal, removed-sender cutoff, GK-022, GK-023, and GM-033 replay tests in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `drain_group_offline_inbox_use_case.dart`; `group_message_listener.dart`; no existing GI-018 plan file | The source row remains `Open`. Existing tests prove self-removal stops later queued traffic when no pre-removal message exists, and prove remaining-peer removed-sender cutoffs and re-add windows, but no exact row-owned test proves the removed local member keeps/decrypts only pre-removal inbox content while post-removal same-page/next-page traffic is not decrypted or persisted. | Add a row-named GI-018 Flutter application regression around signed offline replay, local self-removal, and post-removal drain stop. |

## Scope

GI-018 owns the app-layer offline replay cutoff for the locally removed member. The row closes only when a removed local member retrieving inbox pages receives/decrypts the allowed pre-removal message and does not decrypt or persist post-removal queued messages after replayed self-removal.

Out of scope: re-add gap semantics, non-member sender replay, revoked-device replay, key epoch grace, duplicate replay attacks, history-gap repair, relay pagination volume, and real device relay fixtures.

## Execution Contract

1. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-018 removed member offline replay keeps pre-removal message and stops at removal cutoff`.
2. Seed a signed pre-removal replay message on the first cursor page.
3. Seed a signed self-removal system replay envelope followed by a signed post-removal message on the next cursor page, plus a further next-page post-removal message.
4. Drain with a `GroupMessageListener` configured for the local removed member.
5. Assert the pre-removal message is persisted/decrypted, post-removal same-page and next-page messages are absent, the group is deleted, the leave command and removal stream fire, only pre-removal/system decrypts occur, and the next page after removal is never fetched.
6. Run focused GI-018 and adjacent self-removal/cutoff replay gates, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-018 app replay cutoff proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-018'` |
| Adjacent self-removal replay cutoff proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed self-removal cuts off later queued inbox traffic for that group'` |
| Adjacent removed-sender cutoff proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-017 artifacts. GI-018 scope is limited to the row-owned Flutter replay cutoff regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 06:22:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-018 removed member offline replay keeps pre-removal message and stops at removal cutoff`. The test seeds a signed pre-removal message on the first cursor page, then a signed self-removal system envelope followed by same-page post-removal traffic and a further next-page post-removal message. It drains through `GroupMessageListener` as local removed peer `peer-self`, asserts the pre-removal message is persisted with plaintext, asserts both post-removal message ids are absent, proves the group is deleted, `group:leave` is called, the removal stream fires, cursor requests stop at `''` and `cursor-removal`, and unique decrypted plaintexts contain only the pre-removal user message plus the self-removal control envelope. | Covered the removed-member offline replay cutoff without production changes; existing drain/listener behavior already stops post-removal replay once the self-removal envelope is applied. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-018'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed self-removal cuts off later queued inbox traffic for that group'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-018 is covered by exact Flutter app offline replay cutoff evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-018; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-018 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 137, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-018 ownership and must not mask a repo-owned blocker.
