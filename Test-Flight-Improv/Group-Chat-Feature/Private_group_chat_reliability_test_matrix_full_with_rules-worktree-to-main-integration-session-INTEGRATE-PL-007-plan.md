# INTEGRATE-PL-007 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-007-plan.md`
- Source row: `PL-007` / Re-added member can download only post-readd media
- Row-owned source anchors:
  - `test/features/groups/integration/group_media_fanout_test.dart`: `PL-007 re-added member downloads only post-readd media`
  - `integration_test/group_multi_party_device_real_harness.dart`: `pl007ReaddMediaProof` emission under `private_readd_current`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: `pl007ReaddMediaProof` validation
  - `test/integration/group_multi_party_device_criteria_test.dart`: five PL-007 criteria acceptance/rejection tests

Imported delta:
- Added the PL-007 fake-network selector proving Charlie receives no removed-window media message, row, pending download, download/decrypt call, or plaintext while removed, then downloads only Alice's post-readd media after re-add.
- Added only the PL-007 `pl007ReaddMediaProof` criteria validator and five PL-007 criteria tests.
- Added only PL-007 removed-window/post-readd media upload, Bob download, Charlie direct-denial, and Charlie post-readd download proof emission to the existing `private_readd_current` harness flow.

Out of scope:
- No PL-008+, reaction, notification, unrelated media/privacy, Android, physical iOS, COMPLETE_1, or source-doc import.
- No production file changes.
- No original source worktree plan recreation or rerun.

Verification evidence:
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-007"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "PL-007"` - pass
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-005"` - pass
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-006"` - pass
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "GE-023"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_readd_current"` - pass
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "PL-006"` - pass
- `cd go-relay-server && go test -run TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia` - pass
- `dart format test/features/groups/integration/group_media_fanout_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass
- `flutter analyze --no-pub test/features/groups/integration/group_media_fanout_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass
- `git diff --check` - pass before closure docs

Controller acceptance evidence:
- Required iOS 26.2 live proof passed: `private_readd_current` run id `1779300390272`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_WyxlOa`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`.
- Orchestrator verdict: `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.
- Live verdicts proved Alice's removed-window media upload allowed Alice/Bob and excluded Charlie, Alice's post-readd media upload allowed Alice/Bob/Charlie, Bob downloaded both windows, and Charlie had no removed-window media artifacts while downloading, persisting, and decrypting only the post-readd media.
- Named broad gates remain residual-only: `./scripts/run_test_gates.sh groups` ended red at `+250 -9` on the known non-PL-007 residual set, and `./scripts/run_test_gates.sh completeness-check` remained red at `735/736` on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
