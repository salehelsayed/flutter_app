# Session 6 Plan: Announcement-Specific Happy-Path Regression

## Scope
- Add one focused regression that makes announcement coverage easier to trust in a single place.
- The regression should prove the end-to-end Flutter-side announcement happy path: create announcement group, send as admin, reader receives and stays read-only, and a member can react.
- Stay inside the Flutter repo and keep the work to tests plus any minimal test scaffolding needed for determinism.
- Do not change production app code in this session.

## Files To Inspect Next
- `lib/features/groups/application/create_group_use_case.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
- `test/features/groups/presentation/create_group_screen_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `scripts/run_test_gates.sh`

## Existing Tests Covering This Area
- `test/features/groups/application/create_group_use_case_test.dart` covers group creation, persistence, and key storage, but only for chat groups.
- `test/features/groups/application/create_group_with_members_use_case_test.dart` covers the real create-with-members/config/invite flow, but only for chat groups.
- `test/features/groups/application/send_group_message_use_case_test.dart` already proves announcement-specific send rules, including non-admin rejection, admin success, `successNoPeers`, and key-epoch handling.
- `test/features/groups/application/send_group_reaction_use_case_test.dart` already proves announcement members can react.
- `test/features/groups/presentation/create_group_screen_test.dart` already proves the create UI can preselect `GroupType.announcement`.
- `test/features/groups/presentation/group_conversation_screen_test.dart` already proves readers in announcement groups see the read-only banner instead of compose.
- `test/features/groups/presentation/group_conversation_wired_test.dart` already proves non-admin announcement wiring disables write callbacks and hides compose affordances.
- `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` already proves announcement admin send uses the durable wired path and preserves status under background/task conditions.
- `test/features/groups/integration/group_resume_recovery_test.dart` already proves announcement reader resume/recovery and media replay behavior.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` already proves announcement inbox draining for offline readers.

## Regressions/Tests To Add First
- Add one new focused integration test in `test/features/groups/integration/`.
- Candidate home: `test/features/groups/integration/announcement_happy_path_test.dart` if a new file is cleaner, or a tightly scoped existing group integration file only if the new case can be added without burying the signal.
- If a new integration file is added, classify it in `scripts/run_test_gates.sh` and mirror that classification in `Test-Flight-Improv/test-gate-definitions.md` so `./scripts/run_test_gates.sh completeness-check` stays green. Prefer the existing Optional / Manual direct-suite bucket over widening the frozen named gate lists for this one focused regression.
- The test should cover all of these in one flow:
  - create an announcement group
  - have the admin send the first announcement
  - have one non-admin announcement member receive the message, verify the UI remains read-only, and react to that announcement
- Minimum sufficient layer: `test/features/groups/integration/` is the right home because the behavior crosses creation, send, receive, and reaction boundaries, and the existing unit/presentation tests already cover the pieces separately.
- A second new test is not required unless the first one becomes too large to stay deterministic; if that happens, split only by boundary, not by reintroducing duplicate happy-path assertions.

## Step-by-Step Implementation Plan
1. Add the new announcement happy-path integration test under `test/features/groups/integration/`.
2. Build the test from existing in-memory fakes and the current group helper patterns, but keep the create step on a production create surface (`createGroup()` or `createGroupWithMembers()`) rather than relying only on `GroupTestUser.createGroup()` repo seeding.
3. Reuse the current multi-user helper patterns after the group exists: use `GroupTestUser.addMember`, network subscription helpers, and the current send helpers only where they do not replace the production create/send behavior being claimed by the test.
4. Assert read-only state with a real reader `GroupModel` and a focused `GroupConversationScreen` or `GroupConversationWired` pump after delivery, so the same non-admin member is proven non-writable after the announcement arrives.
5. For reactions, instantiate a test-local `ReactionRepository` and call `sendGroupReaction()` from the reader against the delivered message; do not rely on `GroupTestUser` alone because it does not currently wrap reactions or own a reaction repo.
6. Assert the announcement creation result/type, the admin send result, the non-admin member receipt, the read-only UI state, and the same member's reaction result in the same scenario.
7. Keep the assertions focused on the contract, not on every intermediate log or bridge call.
8. If any setup friction appears, add only the smallest local test helper needed for readability inside the test file.
9. If a new integration file is created, classify it in `scripts/run_test_gates.sh`, mirror the classification in `Test-Flight-Improv/test-gate-definitions.md`, and keep `./scripts/run_test_gates.sh completeness-check` green.
10. Run the new direct test file first, or the edited existing integration file if the fallback home was used, then the roadmap-required direct feature directories, then the script-backed subsystem and baseline gates.

## Risks And Edge Cases
- The main risk is overextending the test into a broad group workflow matrix. The regression should remain one happy-path announcement flow, not a new group feature suite.
- Another risk is duplicating evidence that already exists in the unit and presentation tests. Those tests already cover the pieces; this session should stitch them together once, not restate them many times.
- The biggest structural risk is overclaiming the create step. If the setup only seeds repo state through `GroupTestUser.createGroup()`, the test no longer proves the production announcement-create path and should not be described that way.
- Reader state needs to be asserted carefully. The important contract is that the same non-admin announcement member remains read-only after delivery while still being allowed to react.
- Reaction coverage should remain a member reaction on the announcement message, not a separate reaction matrix.
- A new `test/features/groups/integration/...` file that is not classified in `scripts/run_test_gates.sh` will break `./scripts/run_test_gates.sh completeness-check` even if the Dart test itself passes.
- The Baseline Gate is already documented as red in the repo notes, and the cited line reference for that failure is stale. Execution should rerun the script and record the current failure output rather than blindly copying the older note.
- If the happy path cannot be expressed cleanly in one file, prefer one integration test plus one narrowly focused widget assertion only if needed to keep the integration test deterministic.

## Exact Tests To Run After Implementation
- Direct announcement test set:
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart` if a new file is added, otherwise `flutter test` against the edited existing integration file that carries the happy-path case
- `flutter test test/features/groups/application`
- `flutter test test/features/groups/presentation`
- Classification / gate validation:
- `./scripts/run_test_gates.sh completeness-check`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- Known repo-state note for the execution session:
- The repo currently documents the Baseline Gate as pre-existing red. The execution session should rerun `./scripts/run_test_gates.sh baseline` and record the current failure output verbatim if it is still red, rather than assuming Session 6 introduced it.

## Subsystem Gate(s) And Whether Startup/Transport Tests Are Needed
- Required subsystem gate: `Group Messaging Gate`.
- Baseline gate is also required because this is a new regression that should not destabilize unrelated app behavior.
- Startup / transport tests are not needed for this session.
- Source of truth is `scripts/run_test_gates.sh`; use `Test-Flight-Improv/test-gate-definitions.md` for classification rationale and `Test-Flight-Improv/test-gates-reference.md` for the plan-facing gate notes and known-failure summary.
- Reason: the scope is announcement coverage inside the group messaging stack, and the existing evidence already shows the relevant send/receive/reaction/read-only behavior without involving bootstrap, relay fallback, or device-backed transport recovery.

## Done Criteria
- There is one permanent announcement-specific happy-path regression in `test/features/groups/integration/`.
- The test proves the full Flutter-side announcement contract in one flow: announcement creation through a production create surface, admin send, reader receive/read-only, and member react.
- If a new integration file was added, it is explicitly classified in `scripts/run_test_gates.sh` and mirrored in `Test-Flight-Improv/test-gate-definitions.md`, and `./scripts/run_test_gates.sh completeness-check` remains green.
- Existing unit and presentation coverage remain intact and are not replaced by broader smoke coverage.
- The plan stays inside the Session 6 scope and does not pull in startup, transport, or unrelated group feature work.
- The next execution session can run the new or edited direct test file, the roadmap-required group application/presentation directories, and the script-backed gates without guessing which announcement behavior is covered where.

## Explicit Assumptions For Review
- The new regression belongs in `test/features/groups/integration/` because it spans multiple existing layers and should be expressed as one orchestration test.
- The current announcement send, read-only UI, and reaction tests are sufficient supporting evidence, so this session only needs one new end-to-end announcement regression plus the classification updates needed to keep the repo's gate inventory valid.
- The create claim is only sufficient if the new regression uses a production create surface (`createGroup()` or `createGroupWithMembers()`) rather than only helper-seeded repo state.
- If a new file is added, it should be classified in the existing Optional / Manual direct-suite bucket instead of widening the frozen named gate lists for Session 6.
- One non-admin announcement member is enough to prove both read-only UI and reaction allowance; a second reader should be added only if the first approach becomes nondeterministic.
- The test should target the Flutter tree only; Go-side writer enforcement remains outside this repo and is not part of Session 6.
