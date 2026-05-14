# GI-019 Session Plan: Re-Added Member Replay Respects Membership Gap

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-019`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 06:34:00 CEST | Controller | Source matrix GI-019 row; breakdown row 138; existing GK-023 and GM-033 replay re-add tests in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `drain_group_offline_inbox_use_case.dart`; `group_message_listener.dart`; prior GI-018 closure artifacts | The source row remains `Open` and the breakdown marks GI-019 `evidence-gated` with missing exact row-owned proof. Existing GK-023/GM-033 tests cover adjacent re-add replay semantics, but no GI-019-named proof closes the reported before/during/after inbox replay scenario in the source matrix. | Add a narrow row-named GI-019 Flutter app regression and use adjacent GK-023/GM-033 selectors as supporting evidence. |

## Scope

GI-019 owns the app-layer offline inbox replay timeline for a local member removed and later re-added while offline. The row closes only when replay keeps the pre-removal message, omits the removed-window message, renders the post-readd message, and drains the relevant cursor pages without queuing repair for removed-window traffic.

Out of scope: non-member sender replay, revoked-device replay, key epoch grace policy, duplicate replay attack hardening, history-gap repair integrity, notification policy, and real-device relay fixtures.

## Execution Contract

1. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-019 re-added member replay keeps pre-remove skips removed-window and renders post-readd`.
2. Seed a first replay page with a pre-removal message for Charlie and drain one page to persist the cursor.
3. Apply a replayed self-removal event to persist Charlie's removal cutoff and clean up the local group.
4. Re-create the group as Charlie re-added with a later membership timestamp and a newer key epoch.
5. Seed remaining cursor pages with removed-window and post-readd replay records, including a duplicate removed-window record.
6. Drain all remaining pages and assert pre-removal plus post-readd messages render exactly once, removed-window id/plaintext is absent, no pending key repair is queued for removed-window traffic, the cursor clears, and cursor requests include the full replay sequence.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-019 app replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-019'` |
| Adjacent GK-023 re-add replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-023 re-added member skips removed-window replay and renders post-readd replay'` |
| Adjacent GM-033 replay resume proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GM-033 replay resume rejects removed-window messages after self re-add'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-018 artifacts. GI-019 scope is limited to the row-owned Flutter replay-gap regression, this plan, and closure documentation updates unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 06:43:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-019 re-added member replay keeps pre-remove skips removed-window and renders post-readd`. The test drains a signed pre-removal inbox page for Charlie, persists the cursor, applies a replayed self-removal event and removal cutoff, re-adds Charlie with a later `joinedAt` and key epoch 2, then drains remaining cursor pages containing removed-window traffic, post-readd traffic, and a duplicate removed-window record. It asserts the pre-removal and post-readd messages render exactly once with expected plaintext, the removed-window id/plaintext is absent, no removed-window key repair is queued, the cursor clears after `''`, `gi019-page-2`, and `gi019-page-3`, and the self-removed-window-after-rejoin diagnostic fires. | Covered the re-added member membership-gap replay contract without production changes; existing drain/listener behavior already skips removed-window traffic once the self-removal cutoff and later re-add timestamp are present. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-019'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GK-023 re-added member skips removed-window replay and renders post-readd replay'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GM-033 replay resume rejects removed-window messages after self re-add'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-019 is covered by exact Flutter app offline replay membership-gap evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-019; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-019 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 138, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-019 ownership and must not mask a repo-owned blocker.
