# GI-023 Session Plan: Replay Key Epoch Grace Parity

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-023`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:03:00 CEST | Controller | Source matrix GI-023 row; breakdown row 142; `lib/features/groups/application/group_offline_replay_envelope.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/domain/repositories/group_repository_impl.dart`; `test/shared/fakes/in_memory_group_repository.dart`; adjacent future-key repair and mixed-epoch replay tests | The source row remained `Open` while the breakdown treated GI-023 as evidence-gated. Repo inspection found the app key retention contract keeps only the latest and immediately previous group key. Replay with a retained previous key already rendered, and future/current missing keys already queued repair or placeholder, but a missing epoch older than the retained previous generation could still enter generic missing-key repair/placeholder behavior instead of being treated as expired outside live grace. | Reclassify GI-023 to `needs_code_and_tests`, add stale replay-epoch skip logic for key epochs older than `latestKeyGeneration - 1`, keep future/current/previous missing-key repair behavior intact, and add an exact GI-023 Flutter replay regression covering during-grace and after-grace replay. |

## Scope

GI-023 owns the Flutter offline replay key-epoch policy at drain time. The row closes only when replay accepts retained previous/current epochs consistently with local live key retention, continues to repair current/future/previous missing-key gaps, and skips replay older than the retained previous generation without decrypting, rendering, or queuing key repair.

Out of scope: Go live PubSub crypto changes, relay retention policy changes, simulator-only timing proof, and product changes to the number of key generations retained.

## Execution Contract

1. Treat the app's live key grace as the existing repository retention rule: latest generation plus immediately previous generation.
2. In offline drain missing-key handling, detect signed replay envelopes whose `keyEpoch < latestKeyGeneration - 1`.
3. Skip those stale replay envelopes with flow evidence, without decrypting, rendering placeholders, or queuing pending-key repair.
4. Preserve missing-key repair/placeholder behavior for future/current/previous-grace epochs.
5. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-023 replay uses previous-epoch grace but skips expired replay epoch`.
6. Assert previous/current replay render while previous key is retained, key generation 1 is pruned after generation 3 arrives, expired generation-1 replay is absent after grace, latest generation-3 replay renders, only the latest replay decrypts, and no stale pending-key repair is queued.
7. Run focused GI-023 and adjacent replay-key regression selectors, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-023 offline replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-023'` |
| Future-key repair guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR'` |
| Future missing-key placeholder guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` |
| Retained mixed-epoch replay guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'drains mixed epoch encrypted replay out of order without rewriting epochs'` |
| Adjacent replay auth guards | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-022'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` |
| Hygiene | `dart format --set-exit-if-changed lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-022 artifacts. GI-023 scope is limited to offline replay stale-epoch missing-key handling, the exact row-owned test, this plan, and closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:05:00 CEST | Executor | Updated `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` so missing-key replay envelopes older than the retained previous generation emit `GROUP_DRAIN_OFFLINE_INBOX_STALE_REPLAY_EPOCH_SKIPPED` and are skipped before placeholder or pending-key repair. Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-023 replay uses previous-epoch grace but skips expired replay epoch`, which proves epoch 1 and epoch 2 replay render while latest is 2, epoch 1 is pruned after latest advances to 3, stale epoch-1 replay is absent with no pending repair, and epoch-3 replay continues with exactly one unique decrypt. | Covered the row-owned replay/live epoch-grace parity gap with code plus test evidence. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-023'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-FUTURE-EPOCH-KEY-REPAIR'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'drains mixed epoch encrypted replay out of order without rewriting epochs'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-022'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-021'` | Passed (`+1`). |
| `dart format --set-exit-if-changed lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-023 is covered by code-plus-test Flutter replay evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-023; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-023 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 142, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-023 ownership and must not mask a repo-owned blocker.
