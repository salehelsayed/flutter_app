# INTEGRATE-PL-014 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-014-plan.md`
- Source row: `PL-014` / Media and blob metadata never leak group keys or plaintext
- Row-owned source anchors:
  - `go-mknoon/node/media_test.go`: `TestPL014MediaMetadataAndProgressEventsDoNotExposeSecrets`
  - `test/features/groups/application/send_group_message_use_case_test.dart`: `_expectNoForbiddenKeys` and `PL-014 media metadata omits group keys plaintext and private keys from diagnostics and relay replay`
  - `test/features/groups/integration/group_media_fanout_test.dart`: `expectNoFragmentsInJson`, `expectNoForbiddenKeys`, and `PL-014 fake-network media fanout keeps relay records and download metadata free of group secrets`

Imported delta:
- Added the row-owned native proof that media upload/list metadata and upload progress/complete events omit group-key, plaintext, private-key, and unsafe secret-shaped fields while preserving the allowed progress event key set.
- Added the row-owned application proof that group media publish descriptors omit protected plaintext, group key, and private-key fragments; relay inbox replay remains opaque; diagnostics omit protected fragments; and forbidden secret-shaped keys are absent.
- Added the row-owned fake-network proof that media fanout relay records, recipient download commands, persisted downloaded attachment metadata, and publish media descriptors stay free of protected fragments and unsafe secret-shaped keys.
- Adapted the fake-network selector to current main's explicit group key bootstrap fixture by seeding Alice/Bob latest keys before the row-owned send.

Out of scope:
- No original source worktree plan recreation or rerun.
- No production behavior rewrite; current main already keeps relay/media transport metadata bounded while preserving per-object encrypted media metadata inside encrypted message descriptors.
- No PL-005/PL-006/PL-007 media ACL behavior, PL-012 schema rendering, PL-013 partial-download cleanup, MD-004 media key separation semantics, UI, notification, relay production rewrite, criteria, runner, live-harness, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No simulator/live proof is required or claimed because source 3-Party E2E is `N/A`.

Verification evidence:
- `cd go-mknoon && go test ./node -run 'TestPL014MediaMetadataAndProgressEventsDoNotExposeSecrets|TestMediaUploadProgressReader_EventStructureHasSentAndTotalOnly' -count=1` - pass.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-014 media metadata omits group keys plaintext and private keys from diagnostics and relay replay"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-014 fake-network media fanout keeps relay records and download metadata free of group secrets"` - pass.
- Preservation selectors passed: `GO-008 EK-002 GI-035 pending inbox retry and flow logs omit protected plaintext`; `IR-014 group inbox store relay payload omits plaintext and secrets`; and native `TestMediaUploadProgressReader_EventStructureHasSentAndTotalOnly`.
- `gofmt -w go-mknoon/node/media_test.go` - pass.
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_media_fanout_test.dart` - pass with 0 changed after formatting.
- Scoped `dart analyze test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_media_fanout_test.dart` - pass, `No issues found!`.
- Scoped `git diff --check` over the touched PL-014 code/test files - pass.

Controller acceptance evidence:
- Read-only scouts and controller disk checks found PL-014 production behavior already compatible with current main; the missing meaningful row-owned delta was proof coverage in three existing test files plus closure bookkeeping.
- The controller imported only PL-014 test assertions/helpers and did not bulk-apply source hunks that also contained PL-005, PL-006, PL-013, source-doc, criteria, or unrelated updates.
- The controller preserved the current-main media delivery contract: per-object encryption metadata remains available only where the encrypted message descriptor requires it, while relay-visible replay, diagnostics, progress events, and download metadata are proven free of protected plaintext/group-key/private-key fragments and unsafe secret-shaped keys.
- All required focused row tests and affected privacy/media preservation selectors passed, with no iOS 26.2 proof required for this row.
