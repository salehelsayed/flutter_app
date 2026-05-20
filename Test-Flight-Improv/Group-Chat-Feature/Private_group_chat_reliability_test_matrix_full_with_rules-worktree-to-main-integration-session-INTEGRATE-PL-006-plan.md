# INTEGRATE-PL-006 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Row-owned source anchors:
  - `go-relay-server/media_test.go`: `TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia`
  - `test/features/groups/integration/group_media_fanout_test.dart`: `PL-006 removed member is excluded from future media descriptors and downloads`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`: `PL-006 removed member cannot decode future media replay with only the old epoch`
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: `pl006RemovedMediaProof` validation
  - `test/integration/group_multi_party_device_criteria_test.dart`: five PL-006 criteria rejection tests
  - `integration_test/group_multi_party_device_real_harness.dart`: `pl006RemovedMediaProof` emission under `private_online_remove`

Imported delta:
- Added the PL-006 relay ACL regression proving a removed peer cannot directly download post-removal group media while an active peer can.
- Reconciled main's stronger MD-011 Flutter media fanout and offline replay coverage by adding PL-006 row selectors to the existing equivalent tests instead of duplicating full broad tests.
- Added only the PL-006 `pl006RemovedMediaProof` criteria validator, five PL-006 criteria tests, and PL-006 proof fixture fields for `private_online_remove`.
- Added only PL-006 media upload/download/direct-denial proof emission to the existing `private_online_remove` harness flow.

Out of scope:
- No PL-007, PL-012, PL-013/014, reactions, notifications, unrelated media/privacy, or broader harness imports.
- No production file changes.
- No integration breakdown ledger or `test-inventory.md` updates.
- No live simulator proof; controller can run it separately if needed.

Verification evidence:
- `cd go-relay-server && go test ./... -run TestPL006RemovedPeerCannotDownloadPostRemovalGroupMedia` - pass
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-006"` - pass
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "PL-006"` - pass
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "PL-006"` - pass
- `gofmt -w go-relay-server/media_test.go` - pass
- `dart format test/features/groups/integration/group_media_fanout_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass
- `dart analyze test/features/groups/integration/group_media_fanout_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` - pass
- `git diff --check -- <touched files and contract>` - pass

Controller acceptance evidence:
- Preserved the existing MD-011 selector text while adding the PL-006 row tag to the reused Flutter tests, then reran the PL-006 and MD-011 focused selectors.
- Focused and affected preservation checks passed: PL-006 relay ACL selector, PL-006 fake-network media fanout selector, PL-006 offline replay selector, PL-006 criteria selector, old MD-011 fake-network and replay selectors, `private_online_remove` criteria selector, PL-005 media ACL preservation, GM-004, ML-005, and KE-006 preservation selectors.
- Required iOS 26.2 live proof passed: `private_online_remove` run id `1779298927256`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_m8Kl1s`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `private_online_remove verdicts valid for alice, bob, charlie`.
- Live verdicts proved Alice uploaded post-removal media with allowedPeers limited to Alice/Bob, Bob received and downloaded that media, and Charlie's direct media download was denied with `download failed: not authorized`, `directDownloadOutputBytes=0`, no post-removal message, no media rows, and no pending downloads.
- Named broad gates remain residual-only: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` ended red at `+250 -9` on the known non-PL-006 residual set, and `./scripts/run_test_gates.sh completeness-check` remained red at `735/736` on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
