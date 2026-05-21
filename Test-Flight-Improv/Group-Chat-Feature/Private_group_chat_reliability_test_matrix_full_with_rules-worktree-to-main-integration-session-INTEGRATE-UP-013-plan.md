# INTEGRATE-UP-013 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-013-plan.md`
- Source row: `UP-013` / Group route change or widget unmount does not drop incoming events
- Row-owned source anchors:
  - `test/features/groups/application/group_message_listener_test.dart`: listener persists incoming messages without a UI stream subscriber.
  - `test/features/groups/presentation/group_conversation_wired_test.dart`: route reopen hydrates messages persisted while the widget was unmounted.
  - `test/features/groups/integration/group_messaging_smoke_test.dart`: fake-network app-level listener persists incoming traffic while no conversation route is mounted.

Imported delta:
- Added only the missing row-owned UP-013 listener, widget, and fake-network smoke selectors.
- Existing production architecture stayed unchanged because current main already persists incoming messages before UI broadcast and reloads conversation route state from `GroupMessageRepository` on build/reopen.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, outbound route-unmount send durability, notification-open routing, unread-count policy beyond persisted unread state, media, reactions, share targets, security/privacy rows, adjacent UP rows, or production rewrites.

Verification evidence:
- `dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name "UP-013"` - first parallel attempt hit a macOS native-assets `lipo` race while other Flutter commands held startup/build state; serial rerun passed.
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "UP-013"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "UP-013"` - pass.
- Scoped `flutter analyze --no-pub` over the three touched Dart test files - pass, `No issues found!`.
- Scoped `git diff --check` over the three touched Dart test files - pass.
- No iOS 26.2 simulator proof was required or claimed because the source row marks Fake Network and 3-Party E2E as `N/A`.

Controller status:
- The row is `accepted`. Row-owned tests, format, analyzer, and diff evidence passed.
- Safe next action is `INTEGRATE-UP-014` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation because UP-014 owns share-target filtering and is independent from the accepted UP-013 route lifecycle persistence contract.
