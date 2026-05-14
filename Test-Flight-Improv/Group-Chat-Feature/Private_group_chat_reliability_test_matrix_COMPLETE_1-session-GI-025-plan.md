# GI-025 Session Plan: Pre-Removal Replay After Removal Boundary

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-025`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:31:00 CEST | Controller | Source matrix GI-025 row; breakdown row 144; adjacent GI-018/GI-019/GM-013 cutoff proofs; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/group_offline_replay_envelope.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; group repository and DB helper wiring | The source row remained `Open` and the breakdown marked GI-025 `needs_repo_evidence` / `evidence-gated`. Adjacent removed-sender cutoff tests proved live/app cutoff behavior, but no exact signed inbox replay proof existed for a valid old envelope delivered after the sender was removed. The first exact test attempt exposed a repo-owned blocker: once `member_removed` deleted the active member row, replay signature verification could no longer resolve the removed sender's signing key and rejected valid pre-removal history as `unknown_sender`. | Reclassify GI-025 as code-plus-tests. Persist a bounded removed-member identity snapshot before active deletion, use it only as replay signature verification fallback for removed members, keep non-member and after-cutoff rejection behavior intact, add exact GI-025 replay proof plus repository persistence proof, and close only after focused/adjacent gates pass. |

## Scope

GI-025 owns signed inbox replay delivered to remaining members after a sender has been removed. The row closes when valid pre-removal replay from the removed sender can still be verified and accepted exactly once as history, while duplicate replay is deduped and post-removal content from the same sender is rejected by the persisted removal cutoff.

Out of scope: allowing never-members to replay messages, changing live PubSub authorization, changing relay storage policy, changing user-facing timeline copy, or simulator-only proof.

## Execution Contract

1. Add a repository contract for removed-member identity snapshots with active member/device signing material.
2. Persist the removed member snapshot before deleting active membership during `member_removed` processing.
3. Add SQLCipher migration/helper wiring and production repository wiring for the snapshot table.
4. Use the snapshot only as a replay signature fallback when the active member row is absent.
5. Preserve existing inactive/revoked-device and unknown-sender rejection behavior.
6. Add an exact GI-025 Flutter offline replay test: removal page first, then duplicate signed pre-removal replay and signed post-removal replay from the removed sender.
7. Assert the pre-removal replay persists once as history, the duplicate emits duplicate diagnostics, and the post-removal replay is rejected with the removal cutoff.
8. Add repository persistence proof that the snapshot survives active member deletion with signing device data intact.
9. Run focused GI-025, adjacent cutoff/listener/replay gates, GI-021 non-member regression, GI-024 duplicate regression, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-025 offline replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-025'` |
| Removed-member replay cutoff adjacency | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'` |
| Handler before-cutoff proof | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'accepts removed-sender message when it predates the persisted removal cutoff'` |
| Handler cutoff rejection proof | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'rejects removed-sender message when it is at the persisted removal cutoff'` |
| GM-013 handler aggregate | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'` |
| Listener removal update proof | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_removed removes other member and calls updateConfig'` |
| Listener cutoff proof | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013 listener preserves member_removed cutoff and emits after-cutoff rejection'` |
| Non-member replay regression | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` |
| Duplicate replay regression | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-024'` |
| Snapshot repository persistence proof | `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'removed member snapshot survives active member deletion'` |
| Hygiene | `dart format --set-exit-if-changed lib/features/groups/domain/repositories/group_repository.dart test/shared/fakes/in_memory_group_repository.dart lib/features/groups/domain/repositories/group_repository_impl.dart lib/core/database/helpers/group_members_db_helpers.dart lib/core/database/migrations/068_removed_group_member_snapshots.dart lib/main.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_offline_replay_envelope.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-025 scope is limited to removed-member snapshot persistence/replay verification support, exact row-owned tests, this plan, source matrix row GI-025, and breakdown closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:31:00 CEST | Executor | Added `RemovedGroupMemberSnapshotRepository`, fake and production repository support, SQL helper functions, migration `068_removed_group_member_snapshots`, main DB version/wiring, listener snapshot persistence before member deletion, and replay signature fallback to removed-member snapshots. Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-025 valid pre-removal replay after removal is accepted only as history` and `test/features/groups/domain/repositories/group_repository_impl_test.dart::removed member snapshot survives active member deletion`. | Covered the repo-owned missing prerequisite: remaining members can verify valid pre-removal signed replay from a removed sender after active membership deletion without treating post-removal traffic as allowed content. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-025'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'accepts removed-sender message when it predates the persisted removal cutoff'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'rejects removed-sender message when it is at the persisted removal cutoff'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'GM-013'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_removed removes other member and calls updateConfig'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-013 listener preserves member_removed cutoff and emits after-cutoff rejection'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-024'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'removed member snapshot survives active member deletion'` | Passed (`+1`). |
| `dart format --set-exit-if-changed ...` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-025 is covered by code-plus-test Flutter app and repository evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-025; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-025 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 144, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- The original evidence-gated disposition is corrected to code-plus-tests because exact signed replay proof found a repo-owned missing snapshot prerequisite.
- Never-member replay remains rejected by GI-021; duplicate replay remains idempotent by GI-024.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
