# INTEGRATE-UP-014 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-014-plan.md`
- Source row: `UP-014` / Removed or pending member cannot be selected as share target
- Row-owned source anchors:
  - `lib/features/share/presentation/screens/share_target_picker_wired.dart`: load only writable group targets and revalidate selected group targets before delivery.
  - `test/features/share/presentation/share_target_picker_wired_test.dart`: focused UP-014 load-time filtering and stale-selection widget proofs plus updated group fixtures for existing share picker selectors.

Imported delta:
- Added identity-aware writable group filtering in `ShareTargetPickerWired`: current local identity, current local member row, latest group key, non-archived/non-dissolved state, and announcement-admin role where applicable.
- Added send-time selected-group revalidation after runtime readiness so stale removed group ids are dropped before delivery.
- Added row-owned UP-014 widget tests for removed, pending/no-key, dissolved, and announcement-reader exclusion plus stale selected group removal before send.
- Updated existing share picker widget fixtures to seed current member/key state for selectable groups.

Out of scope:
- No original source worktree plan recreation or rerun.
- No unrelated source-worktree changes, source-doc rewrites, COMPLETE_1 doc updates, Android, physical iOS, contact sharing, batch delivery result semantics, media compression/upload policy, notification routing, group send validators, group conversation compose behavior, share picker screen UI rewrites, or adjacent UP rows.

Verification evidence:
- `dart format --set-exit-if-changed lib/features/share/presentation/screens/share_target_picker_wired.dart test/features/share/presentation/share_target_picker_wired_test.dart` - pass with 0 changed.
- `flutter test --no-pub test/features/share/presentation/share_target_picker_wired_test.dart --plain-name "UP-014"` - pass (`+2`).
- `flutter test --no-pub test/features/share/presentation/share_target_picker_wired_test.dart --plain-name "loads only active contacts and writable groups"` - pass.
- `flutter test --no-pub test/features/share/presentation/share_target_picker_wired_test.dart --plain-name "send invokes the coordinator exactly once with selected targets"` - pass.
- `flutter test --no-pub test/features/share/presentation/share_target_picker_wired_test.dart --plain-name "partial failure keeps only failed targets selected"` - pass.
- `flutter test --no-pub test/features/share/presentation/share_target_picker_wired_test.dart` - pass (`+11`).
- `dart analyze lib/features/share/presentation/screens/share_target_picker_wired.dart test/features/share/presentation/share_target_picker_wired_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the two touched Dart files - pass.
- No iOS 26.2 simulator proof was required or claimed because the source row marks 3-Party E2E as `N/A`.

Controller status:
- The row is `accepted`. Row-owned production, widget, preservation, full-file, format, analyzer, and diff evidence passed.
- Safe next action is `INTEGRATE-SV-001` after ledger sanity, dirty-state safety checks, and fresh row-specific revalidation because SV-001 begins the security/authorization row family and is independent from UP-014 share-target filtering.
