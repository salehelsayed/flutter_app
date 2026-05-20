# INTEGRATE-PL-013 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-013-plan.md`
- Source row: `PL-013` / Partial media download cleans up local files and retries safely
- Row-owned source anchors:
  - `go-mknoon/node/media.go`: `copyMediaDownloadToFile`
  - `go-mknoon/node/media_test.go`: `TestPL013MediaDownloadRemovesPartialOutputOnIncompleteTransfer`
  - `lib/features/conversation/application/download_media_use_case.dart`: failed `media:download` partial-output cleanup
  - `test/features/conversation/application/download_media_use_case_test.dart`: `PL-013 removes partial failed download and retry succeeds`
  - `test/features/groups/integration/group_media_fanout_test.dart`: `PL-013 partial fake-network media download cleans up and retries`

Imported delta:
- Extracted native media download writes through `copyMediaDownloadToFile` so incomplete-write cleanup is directly testable without changing runtime behavior.
- Added the row-owned native proof that incomplete native downloads remove the partial output path and a same-path retry succeeds.
- Added Flutter failed-result cleanup for explicit `media:download` responses that return `ok:false` after creating local bytes, deleting both encrypted and final output candidates before marking the attachment failed.
- Added the row-owned Flutter unit proof for failed-result cleanup and retry-to-done behavior.
- Added the row-owned fake-network proof that Bob's first media download can write partial bytes, fail, leave no partial local file or localPath, and then retry the same attachment successfully.
- Adapted the fake-network selector to current main's explicit group key bootstrap fixture by seeding Alice/Bob latest keys before the row-owned send.

Out of scope:
- No original source worktree plan recreation or rerun.
- No PL-006/PL-007 media ACL changes, PL-012 schema preservation, PL-014 metadata privacy, MD-012 quarantine retry behavior, UI, notification, relay, criteria, runner, live-harness, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No simulator/live proof is required or claimed because source 3-Party E2E is `N/A`.

Verification evidence:
- `cd go-mknoon && go test ./node -run TestPL013 -count=1` - pass.
- `cd go-mknoon && go test ./node -run 'TestPL013|TestIdleTimeoutReader_StalledDownloadFails' -count=1` - pass.
- `flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart --plain-name "PL-013"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-013"` - pass after adding current-main latest-key setup to the row-owned selector.
- Preservation selectors passed: `flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart --plain-name "MD-012"`; `PL-012 fake-network media schema variants survive fanout and downloads`; `PL-006 MD-011 removed member is excluded from future media descriptors and downloads`; and `PL-007 re-added member downloads only post-readd media`.
- A combined preservation bundle containing `one recipient media download failure remains observable per recipient` stayed red on that existing selector's pre-download send bootstrap, not on PL-013 cleanup; the failure is classified as non-PL-013.
- `gofmt` over the two touched Go files - pass.
- `dart format --set-exit-if-changed` over the three touched Dart files - pass with 0 changed after formatting.
- Scoped `dart analyze` over the three touched Dart files - pass, `No issues found!`.
- `git diff --check` - pass.

Controller acceptance evidence:
- Read-only scouts and controller disk checks found the native cleanup behavior partially present inline, but missing row-owned native proof, missing Flutter failed-result cleanup, and missing Flutter/fake-network PL-013 selectors.
- The controller imported only the PL-013 helper/proof/cleanup/test deltas and did not bulk-apply source file hunks that also contained PL-005, PL-006, PL-014, source-doc, criteria, or unrelated updates.
- All required focused row tests and affected media preservation selectors passed, with no iOS 26.2 proof required for this row.
