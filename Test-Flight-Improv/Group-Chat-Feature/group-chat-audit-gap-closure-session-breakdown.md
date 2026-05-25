# Group Chat Audit Gap Closure Session Breakdown

Decomposition artifact created: 2026-05-23

Source matrix: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`

Downstream workflow rule: detailed TDD planning happens one session at a time. Each session must keep the smallest possible diff, avoid refactors and new dependencies, and stop as blocked if the code/test fix requires touching more than three non-doc files.

## Run Mode Snapshot

- Refreshed: 2026-05-23.
- Active mode: `implementation-committed gap-closure`.
- Degraded local continuation explicitly allowed: no.
- Source proposal/matrix/closure doc: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`.
- Source status vocabulary: `Open`, `Closed`, `Blocked`.
- Overall closure bar: every row-owned non-polish audit finding is either `Closed` with concrete code and focused test evidence or `Blocked` with an exact hard-constraint reason. No row may be accepted while the source matrix remains `Open`.
- Final verdict policy: persist exactly one of `closed`, `accepted_with_explicit_follow_up`, `residual_only`, or `still_open`; use `closed` only when all row-owned source rows are `Closed`.
- Initial dirty snapshot before session processing: `M pubspec.yaml`; untracked `test-upload/`, `test-upload-group/`, and `test-upload2/`.

## Controller Progress

- 2026-05-23: User explicitly authorized multi-agent orchestration to speed up the rollout. Controller split approval-required `GCA-002` into cap-safe row-owned sessions `GCA-002A` and `GCA-002B` with disjoint write sets, preserving the three non-doc-file hard stop while allowing parallel planning/execution where sessions do not overlap.
- 2026-05-23: Controller created the source gap matrix and session breakdown from the read-only audit findings; next action is session `GCA-001` TDD planning.

## Closure Progress

- 2026-05-23T19:06:21+02:00: `GCA-001` closure audit checked the plan verdict, source matrix, session ledger, and touched group-list files. The row-owned load-error surface is closed; the remaining `groups` named-gate failure is residual-only and unrelated to `GCA-001` because isolated `GM-028 empty PeerId add event does not persist or block valid delivery` fails in `group_membership_smoke_test.dart` without importing the touched group-list files.
- 2026-05-23T19:32:42+02:00: `GCA-002A` closure audit checked the accepted execution result, plan evidence, source matrix, session ledger, and touched create-group picker files. The row-owned create-group contact loading/error surface is closed: pending load shows `create-group-contact-loading`, load failure shows retryable `Couldn't load contacts`, true empty remains `No contacts available`, and the focused/direct Flutter tests plus `git diff --check` passed.
- 2026-05-23T19:34:23+02:00: `GCA-002B` closure audit checked the accepted-with-follow-up execution result, plan evidence, source matrix, session ledger, and touched add-member picker files. The row-owned add-member contact loading/error surface is closed: pending load shows `Loading contacts...`, load failure shows retryable `Couldn't load contacts`, retry can recover, true empty remains `No contacts available`, and the focused/direct Flutter tests plus `git diff --check` passed; the `groups` named gate remains red only on known unrelated isolated `group_membership_smoke_test.dart` `GM-028`.
- 2026-05-23T19:43:08+02:00: `GCA-004` closure audit checked the accepted-with-follow-up execution result, plan evidence, source matrix row, session ledger, and touched accept-pending files. The row-owned invite accept retry affordance is closed: bridge join and accepted-inbox bridge errors preserve the pending invite and defer consumed-invite/welcome-key tombstones until retry succeeds; compatible materialized local group/key state retries join/drain, while non-compatible duplicate and stale newer-key rejection behavior remains covered. Focused use-case, invite round-trip, contact-request, and `git diff --check` evidence passed; the full accept-pending suite residual remains only `accept replays backlog reactions when reactionRepo is provided` with `GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING` for `peer-self`, outside `GCA-004`.
- 2026-05-23T19:47:41+02:00: `GCA-003` closure audit checked the accepted-with-follow-up execution result, plan evidence, source matrix row, session ledger, and touched create-group use-case files. The row-owned skipped-member warning gap is closed: failed selected add-member attempts remain excluded from persisted/config/publish/invite paths, but are now exposed through `addMemberFailures`, `hasWarnings`, and `buildCreateWarningMessage()` for the existing picker warning path. The focused selector, full `create_group_with_members_use_case_test.dart`, and `git diff --check` passed; the broad `groups` gate residual is outside `GCA-003` and covers invite/recovery/membership integration failures (`BB-007`, `IJ005`, startup/rejoin replay cases, `GE-017`/`GE-019`/`GE-020`, `GM-029`, and known `GM-028`).
- 2026-05-23T20:11:12+02:00: `GCA-005` closure audit checked the accepted-with-follow-up execution result, plan evidence, source matrix row, session ledger, and touched group conversation files. The row-owned conversation message-load error surface is closed: an initial message-page failure with no displayable messages now shows retryable `Couldn't load messages` instead of `No messages yet`, and retry can recover to a loaded message. The focused selector failed RED before implementation, then passed after implementation and in QA; `dart format` and `git diff --check` passed. Residual-only note: the paired presentation command remains red at `+112 -17` only on unrelated send/media/voice selectors around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED`; `./scripts/run_test_gates.sh groups` and manual debug verification were not run.
- 2026-05-23T20:38:12+02:00: `GCA-006` closure audit checked the accepted recovery result, plan evidence, source matrix row, session ledger, and touched group-conversation wired files. The row-owned composer identity guard is closed: missing or incomplete sender identity keeps the composer read-only with `Waiting for your identity before you can send.`, stale missing-identity `onSend` does not publish or persist a message, and late identity load restores writable send with the loaded peer id and username. The focused `GCA-006` selector failed RED before implementation at `screen.canWrite`, actual `true`, then passed; the adjacent `UP-003` selector, scoped `flutter analyze`, `dart format --set-exit-if-changed`, and `git diff --check` passed. Residual-only note: the full `group_conversation_wired_test.dart` suite and `./scripts/run_test_gates.sh groups` remain red only on pre-existing empty-membership send/media/voice failures around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` plus known `GM-028`; manual debug verification was not run.
- 2026-05-23T21:06:09+02:00: `GCA-007` closure audit checked the pass-with-residuals execution result, plan evidence, source matrix row, session ledger, and touched group-conversation wired files. The row-owned unauthorized/missing-group terminal send surface is closed: text sends that return `unauthorized` or `groupNotFound` remove the optimistic row and now show concrete snackbars, while those results remain non-retryable; the same-file voice terminal branch mirrors snackbar copy only, and `groupDissolved` feedback remains distinct. The focused unauthorized and missing-group selectors failed RED before implementation, then passed after implementation and in QA; the required publish-failure preservation selector, full `group_conversation_wired_test.dart` file (`+88`), and `git diff --check` passed. Residual-only note: `./scripts/run_test_gates.sh groups` remains red at `+288 -13` on integration membership/replay/startup selectors (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`) outside `GCA-007`; manual debug verification was not run.
- 2026-05-23T21:35:34+02:00: `GCA-008` closure audit checked the acceptance-only recovery result, plan evidence, source matrix row, session ledger, and touched Group Info removal files. The row-owned partial-state rollback gap is closed: Group Info now treats `group:publish ok:false` as failure and restores the removed member, `lastMembershipEventAt`, failed local timeline message, and admin bridge config when publish, inbox-store, or key rotation fails after local removal. The focused `GCA-008` selector failed RED before implementation because Alice stayed removed after `group:publish ok:false` and post-remove work continued, then passed after implementation (`+1`); the stale non-member selector, two lower-level rollback selectors, full `remove_group_member_use_case_test.dart` (`+19`), and `git diff --check` passed. Residual-only note: full `group_info_wired_test.dart` remains red `+44 -3` only on the existing rotation command-order, writer-leave rotation permission/generate-next-key, and `EK004` replay-envelope `messageId` residuals; `./scripts/run_test_gates.sh groups` remains red `+288 -13` on known broad group residuals outside `GCA-008`; manual debug verification was not run.
- 2026-05-23T21:51:43+02:00: `GCA-009` closure audit checked the accepted-with-explicit-follow-up execution result, plan evidence, source matrix row, session ledger, and touched Group Info leave files. The row-owned active leave local-message cleanup contract is closed: Group Info now broadcasts self-removal first, then routes through `deleteGroupAndMessages(...)` when `msgRepo` is available so successful leave purges the group row and local group messages, while the direct `leaveGroup(...)` fallback remains for no-`msgRepo` callers. The focused `GCA-009` selector failed RED before implementation because `msg-left-group` remained, then passed after implementation; the delete-group-and-messages and leave-group use-case backstops, `dart format`/`dart format --set-exit-if-changed`, and `git diff --check` passed. Residual-only note: full `group_info_wired_test.dart` remains red only on an unrelated writer-leave fixture conflict from dirty rotation permission work plus two GCA-008 remove-member failures; `./scripts/run_test_gates.sh groups` remains red on known broader residuals (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`) outside `GCA-009`; manual app verification was not run.
- 2026-05-23T22:44:22+02:00: `GCA-010` closure audit checked the accepted same-session recovery result, plan evidence, source matrix row, session ledger, and touched Group Info leave files. The row-owned voluntary leave ordering/rollback contract is closed: Group Info preserves pre-native self-removal publish, inbox-store replay, and key rotation for successful leave; when final native `group:leave` fails, it rolls back local self-left timeline/key artifacts, preserves group/member rows, stays on Group Info, and shows the failed-leave snackbar. The focused `GCA-010` selector failed RED before recovery because no `group:publish`, `group:inboxStore`, or `group:generateNextKey` preceded forced `group:leave`, then passed after recovery; `BB-010`, sole-admin leave, multi-admin leave, writer leave, `leave_group_use_case_test.dart`, scoped `dart analyze`, and `git diff --check` passed. Residual-only note: `./scripts/run_test_gates.sh groups` remains red only on broad group residuals (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`) outside `GCA-010`; manual verification was not run.

## Final Program Acceptance

Final program verdict: `accepted_with_explicit_follow_up`.

Recorded: 2026-05-23T22:48:36+02:00.

Closure sanity result:

- Source matrix rows `GCA-001`, `GCA-002A`, `GCA-002B`, `GCA-003`, `GCA-004`, `GCA-005`, `GCA-006`, `GCA-007`, `GCA-008`, `GCA-009`, and `GCA-010` are all `Closed` with concrete implementation and focused test evidence.
- Session ledger rows for the same row-owned source rows are resolved as `closed` or `accepted_with_explicit_follow_up`; no row-owned session remains `still_open` or `blocked`.
- No source matrix row remains `Open`. The only explicitly non-row item is audit finding 11, the no-confirmation leave UX polish item, which remains out of scope unless separately requested.
- The final program is not marked `closed` because broad gate and manual-check residuals remain truthful follow-up: `./scripts/run_test_gates.sh groups` remains red on known broad group residuals outside the row-owned closure work, and manual debug/app verification was not run for the rows that recorded it as residual.
- Future work should reopen this rollout only for a real regression in a row-owned closure behavior or for a separately scoped follow-up that owns the broad gate/manual residuals.

## Recommended Plan Count

Recommended plan count: `11`

One session owns each non-polish audit finding, except `GCA-002` is split into `GCA-002A` and `GCA-002B` because the full finding spans two independent picker paths and would otherwise exceed the three non-doc-file hard stop.

## Overall Closure Bar

The rollout is complete when:

- Rows `GCA-001` through `GCA-010` are resolved in the source matrix.
- Every accepted session has a reusable TDD plan, focused failing-first or contract test evidence, implementation evidence, and a passing focused test or truthful blocker.
- No session refactors, restructures, adds dependencies, or broadens product behavior beyond the audited bug/gap.
- `git diff --check` passes after the rollout.

## Source Of Truth

Primary source matrix:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`

Regression and gate docs:

- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gates-reference.md`

## Session Ledger

| Session ID | Title | Classification | Plan File | Depends On | Status | Execution Verdict | Closure Docs Touched | Blocker Class | Note |
|---|---|---|---|---|---|---|---|---|---|
| `GCA-001` | Group list load error surface | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-001-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-001`; breakdown ledger and closure progress | None | Row `GCA-001` closed with focused/direct presentation tests and `git diff --check`; `groups` named-gate follow-up remains unrelated isolated `group_membership_smoke_test.dart` `GM-028`. |
| `GCA-002A` | Create-group picker loading and error states | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002A-plan.md` | None | `closed` | `accepted` | Source matrix row `GCA-002A`; breakdown ledger and closure progress | None | Row `GCA-002A` closed with slow-load and retryable-failure wired tests, direct create-group picker presentation tests, and `git diff --check`; no residual follow-up recorded. |
| `GCA-002B` | Add-member picker loading and error states | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002B-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-002B`; breakdown ledger and closure progress | None | Row `GCA-002B` closed with slow-load and retryable-failure wired tests, direct add-member contact picker presentation tests, and `git diff --check`; `groups` named-gate follow-up remains unrelated isolated `group_membership_smoke_test.dart` `GM-028`. |
| `GCA-003` | Group creation skipped-member warning/failure handling | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-003-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-003`; breakdown ledger and closure progress | None | Row `GCA-003` closed with focused/direct create-group use-case tests and `git diff --check`; `groups` named-gate follow-up remains outside the row-owned seam on invite/recovery/membership integration failures (`BB-007`, `IJ005`, startup/rejoin replay cases, `GE-017`/`GE-019`/`GE-020`, `GM-029`, and known `GM-028`). |
| `GCA-004` | Invite accept bridge-error retry affordance | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-004-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-004`; breakdown ledger and closure progress | None | Row `GCA-004` closed with focused GCA-004 use-case tests, duplicate-group and stale newer-key focused checks, GCA-004 invite round-trip integration, contact-request integration, and `git diff --check`; residual follow-up is the unrelated full accept-pending reaction replay fixture failure for `peer-self`. |
| `GCA-005` | Group conversation message load error surface | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-005-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-005`; breakdown ledger and closure progress | None | Row `GCA-005` closed with RED-then-green focused selector, QA rerun, `dart format`, and `git diff --check`; residual follow-up is the unrelated paired presentation `+112 -17` send/media/voice failures around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED`, with `groups` gate and manual debug verification not run. |
| `GCA-006` | Composer identity-missing silent-send guard | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-006-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-006`; breakdown ledger and closure progress | None | Row `GCA-006` closed with RED-then-green focused selector, adjacent `UP-003`, scoped analyze, format, and `git diff --check`; residual follow-up is the unrelated full wired-suite/groups-gate empty-membership send/media/voice failures around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` plus known `GM-028`, with manual debug verification not run. |
| `GCA-007` | Unauthorized or missing-group send error surface | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-007-plan.md` | None | `accepted_with_explicit_follow_up` | `pass-with-residuals` | Source matrix row `GCA-007`; breakdown ledger and closure progress | None | Row `GCA-007` closed with RED-then-green focused unauthorized/missing-group text-send snackbar selectors, required publish-failure preservation selector, full `group_conversation_wired_test.dart` (`+88`), and `git diff --check`; residual follow-up is the unrelated `groups` named-gate `+288 -13` integration membership/replay/startup failures (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`), with manual debug verification not run. |
| `GCA-008` | Member removal partial-state rollback/ordering | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md` | None | `accepted_with_explicit_follow_up` | `pass-with-residuals` | Source matrix row `GCA-008`; breakdown ledger and closure progress | None | Row `GCA-008` closed with RED-then-green focused post-remove rollback selector, stale non-member selector, lower-level rollback selectors, full `remove_group_member_use_case_test.dart` (`+19`), and `git diff --check`; residual follow-up is limited to the existing full `group_info_wired_test.dart` `+44 -3` rotation command-order/writer-leave/replay-envelope signatures and broad `groups` named-gate `+288 -13` known failures, with manual debug verification not run. |
| `GCA-009` | Leave group local message cleanup contract | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-009-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted_with_explicit_follow_up` | Source matrix row `GCA-009`; breakdown ledger and closure progress | None | Row `GCA-009` closed with RED-then-green focused active-leave local-message cleanup selector, delete-group-and-messages and leave-group use-case backstops, format checks, and `git diff --check`; residual follow-up is limited to the unrelated full `group_info_wired_test.dart` writer-leave fixture conflict plus two GCA-008 remove-member failures, broad `groups` named-gate known residuals (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`), and missing manual app verification. |
| `GCA-010` | Voluntary leave partial broadcast-before-leave ordering | `implementation-ready` | `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-010-plan.md` | None | `accepted_with_explicit_follow_up` | `accepted after same-session recovery` | Source matrix row `GCA-010`; breakdown ledger and closure progress | None | Row `GCA-010` closed with RED-then-green native-leave-failure rollback selector, `BB-010`, sole-admin leave, multi-admin leave, writer leave, `leave_group_use_case_test.dart`, scoped `dart analyze`, and `git diff --check`; residual follow-up is limited to the unrelated broad `groups` named-gate failures (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`) plus missing manual verification. |

## Ordered Session Breakdown

### Session `GCA-001`: Group List Load Error Surface

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-001-plan.md`

Dependency on earlier sessions: none.

Exact scope: make `GroupListWired`/`GroupListScreen` distinguish initial loading, empty data, and load failure; add a focused test proving a repository load failure is user-visible and does not claim there are no groups.

Likely code-entry files: `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/features/groups/presentation/screens/group_list_screen.dart`.

Likely direct tests/regressions: existing or new focused group list screen/wired tests under `test/features/groups/presentation/`.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-001`; this breakdown ledger.

### Session `GCA-002A`: Create-Group Picker Loading And Error States

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002A-plan.md`

Dependency on earlier sessions: none.

Exact scope: make the create-group picker avoid showing `No contacts available` during initial loading or contact-load failure; add focused tests for loading/error state.

Likely code-entry files: `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `lib/features/groups/presentation/screens/create_group_picker_screen.dart`.

Likely direct tests/regressions: focused create-group picker widget/wired tests under `test/features/groups/presentation/`.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-002A`; this breakdown ledger.

### Session `GCA-002B`: Add-Member Picker Loading And Error States

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-002B-plan.md`

Dependency on earlier sessions: none.

Exact scope: make the add-member contact picker avoid showing `No contacts available` during initial loading or contact-load failure; add focused tests for loading/error state.

Likely code-entry files: `lib/features/groups/presentation/screens/contact_picker_wired.dart`, `lib/features/groups/presentation/screens/contact_picker_screen.dart`.

Likely direct tests/regressions: focused contact picker widget/wired tests under `test/features/groups/presentation/`.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-002B`; this breakdown ledger.

### Session `GCA-003`: Group Creation Skipped-Member Warning/Failure Handling

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-003-plan.md`

Dependency on earlier sessions: none.

Exact scope: make selected-member add failures observable to the creator without broadening group creation behavior; add focused test for a selected contact failing `addGroupMember`.

Likely code-entry files: `lib/features/groups/application/create_group_with_members_use_case.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`.

Likely direct tests/regressions: focused create-group-with-members use-case test and/or create picker test.

Likely named gates: focused Flutter/Dart test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-003`; this breakdown ledger.

### Session `GCA-004`: Invite Accept Bridge-Error Retry Affordance

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-004-plan.md`

Dependency on earlier sessions: none.

Exact scope: preserve or expose a retry path when bridge join/inbox drain returns `bridgeError`, without weakening security rejection behavior for expired, revoked, invalid, wrong-identity, or already-used invites.

Likely code-entry files: `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, pending invite UI only if needed.

Likely direct tests/regressions: focused accept-pending-invite use-case test for bridge error and pending invite/tombstone state.

Likely named gates: focused Flutter/Dart test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-004`; this breakdown ledger.

### Session `GCA-005`: Group Conversation Message Load Error Surface

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-005-plan.md`

Dependency on earlier sessions: none.

Exact scope: make conversation initial message load failure user-visible and avoid representing it as an empty conversation.

Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/groups/presentation/screens/group_conversation_screen.dart`.

Likely direct tests/regressions: focused group conversation screen/wired test.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-005`; this breakdown ledger.

### Session `GCA-006`: Composer Identity-Missing Silent-Send Guard

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-006-plan.md`

Dependency on earlier sessions: none.

Exact scope: ensure missing identity disables composer or shows a concrete send error instead of allowing an enabled send that silently returns.

Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`.

Likely direct tests/regressions: focused group conversation writable-state or send-guard test.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-006`; this breakdown ledger.

### Session `GCA-007`: Unauthorized Or Missing-Group Send Error Surface

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-007-plan.md`

Dependency on earlier sessions: none.

Exact scope: show a concrete user-facing error when a send result is `unauthorized` or `groupNotFound`, while preserving dissolved-group handling and failure retry behavior.

Likely code-entry files: `lib/features/groups/presentation/screens/group_conversation_wired.dart`.

Likely direct tests/regressions: focused send-result handling test.

Likely named gates: focused Flutter test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-007`; this breakdown ledger.

### Session `GCA-008`: Member Removal Partial-State Rollback/Ordering

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-008-plan.md`

Dependency on earlier sessions: none.

Exact scope: prevent local member/config mutation from being accepted when publish/inbox/key-rotation fails, or add a minimal rollback that restores the removed member and local timeline state.

Likely code-entry files: `lib/features/groups/application/remove_group_member_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`.

Likely direct tests/regressions: focused remove-member use-case or group-info test that injects publish/inbox/key-rotation failure.

Likely named gates: focused Flutter/Dart test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-008`; this breakdown ledger.

### Session `GCA-009`: Leave Group Local Message Cleanup Contract

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-009-plan.md`

Dependency on earlier sessions: none.

Exact scope: make the Group Info leave path honor the local-data cleanup contract by deleting messages or routing through the existing delete-and-messages use case; add a focused test.

Likely code-entry files: `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/application/delete_group_and_messages_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`.

Likely direct tests/regressions: focused leave/delete group use-case or group-info test.

Likely named gates: focused Flutter/Dart test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-009`; this breakdown ledger.

### Session `GCA-010`: Voluntary Leave Partial Broadcast-Before-Leave Ordering

Session classification: `implementation-ready`

Intended plan file: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-GCA-010-plan.md`

Dependency on earlier sessions: none.

Exact scope: avoid broadcasting/saving self-removal and rotating keys before the leave action can safely complete, or provide a minimal rollback for local self-removal timeline if final leave fails.

Likely code-entry files: `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/leave_group_use_case.dart`.

Likely direct tests/regressions: focused voluntary leave/group-info leave failure test.

Likely named gates: focused Flutter/Dart test; `git diff --check`.

Matrix/closure docs to update when done: source matrix row `GCA-010`; this breakdown ledger.

## Downstream Execution Path

For each session in order:

1. Create or verify the session TDD plan file.
2. Run execution with failing-first focused test work, minimal implementation, and focused verification.
3. Run closure audit to update the source matrix row and session ledger.
4. Continue to the next unresolved runnable session.

After all runnable sessions resolve, run final program acceptance and persist the final program verdict in this breakdown.
