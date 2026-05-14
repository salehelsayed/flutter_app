# GP-028 Session Plan: High-Volume Burst With Membership Mutation

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-028`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 02:48:00 CEST | Controller | Source matrix GP-028 row; breakdown row 121; existing fake-network burst test in `group_edge_cases_smoke_test.dart`; existing membership mutation and cutoff tests in `group_membership_smoke_test.dart`; current fake group PubSub/test-user harness | At preflight, the source row had no closure evidence. Existing burst coverage sends 20 messages without add/remove mutation, and existing membership tests cover removal windows without 100+ burst pressure. No exact row-owned proof sends 100+ messages while adding and removing D at fixed offsets and verifying per-recipient exact-once windows. | Add exact fake-network integration regression for 120 explicit-id messages with D added and removed at fixed offsets, then run focused and adjacent burst gates. |

## Scope

GP-028 owns high-volume app/fake-network group delivery while membership mutates during the burst. A long burst from A must reach all currently entitled recipients exactly once; a member added mid-burst must receive only post-add/pre-remove messages, and after removal must receive no later burst messages.

Out of scope: real multi-device simulator proof, Go raw GossipSub stress, durable inbox replay, and UI scroll performance.

## Execution Contract

1. Add row-owned fake-network integration test `GP-028 high-volume burst keeps entitlement windows exact while adding and removing Diana`.
2. Use explicit message ids for at least 100 messages to avoid timestamp-id collision masking.
3. Start with A/B/C, add D at a fixed offset, remove D at a later fixed offset, and keep A sending throughout.
4. Assert A stores all outgoing messages once, B/C receive all burst messages once, D receives only the add-to-remove window once, and D receives no post-removal burst messages.
5. Run focused GP-028 and adjacent existing rapid-burst gates plus formatter and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-028 fake-network burst proof | `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'GP-028'` |
| Adjacent existing burst proof | `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'rapid message burst'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/integration/group_edge_cases_smoke_test.dart` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-026 closure artifacts. GP-028 scope is limited to the row-owned fake-network integration test, this plan, and closure documentation updates unless the focused regression exposes a production gap.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 02:48:00 CEST | Executor | Added `test/features/groups/integration/group_edge_cases_smoke_test.dart::GP-028 high-volume burst keeps entitlement windows exact while adding and removing Diana`. The test sends 120 explicit-id messages, adds Diana at offset 30, removes Diana at offset 90, reads an expanded repository page, and asserts exact once-only message windows for Alice/Bob/Charlie/Diana plus Diana's post-removal unsubscribe. | Covered row-owned behavior with tests-only Flutter fake-network proof; no production code change required. |
| 2026-05-13 02:56:00 CEST | Executor | Initial focused gate attempts exposed two test-contract issues: future timestamps were clamped by the incoming handler before membership-window checks, and the default in-memory page limit of 50 masked full-burst counts. | Corrected the regression to use a fixed past timestamp and an expanded repository page instead of weakening the row expectation. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'GP-028'` | Passed (`00:00 +1: All tests passed!`). |
| `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'rapid message burst'` | Passed (`00:00 +1: All tests passed!`). |
| `dart format --set-exit-if-changed test/features/groups/integration/group_edge_cases_smoke_test.dart` | Passed (`Formatted 1 file (0 changed)`). |
| `git diff --check -- test/features/groups/integration/group_edge_cases_smoke_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GP-028-plan.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` | Passed. |

## Final Verdict

Accepted/closed. GP-028 is covered by exact tests-only Flutter fake-network evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GP-028; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GP-028 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 121, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-028 ownership and does not mask a repo-owned blocker.
