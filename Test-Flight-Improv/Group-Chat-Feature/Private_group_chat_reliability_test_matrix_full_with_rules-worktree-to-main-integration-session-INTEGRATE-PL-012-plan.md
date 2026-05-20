# INTEGRATE-PL-012 Worktree-to-Main Integration Contract

Status: accepted

Source of truth:
- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-012-plan.md`
- Source row: `PL-012` / Voice, GIF, file, image, and video payload schemas survive bridge publish opts
- Row-owned source anchors:
  - `go-mknoon/bridge/bridge_test.go`: `TestPL012GroupPublishOptsPreserveMediaSchemaVariants`
  - `test/features/groups/application/send_group_message_use_case_test.dart`: `PL-012 media schema variants survive live publish and replay payloads`
  - `test/features/groups/integration/group_media_fanout_test.dart`: `PL-012 fake-network media schema variants survive fanout and downloads`
  - `integration_test/group_multi_party_device_real_harness.dart`: `pl012` media variant live proof
  - `integration_test/scripts/run_group_multi_party_device_real.dart`: `pl012` runner registration
  - `integration_test/scripts/group_multi_party_device_criteria.dart`: `pl012` media schema criteria
  - `test/integration/group_multi_party_device_criteria_test.dart`: PL-012 criteria accept/reject selectors

Imported delta:
- Added the row-owned native bridge proof that image, video, file, GIF, and voice media descriptors retain schema fields through publish opts.
- Added the row-owned app publish/replay proof that outgoing payloads and stored replay payloads preserve content type, dimensions, thumbnail/blob ids, file metadata, GIF metadata, voice duration/waveform, hashes, and encryption metadata.
- Added the row-owned fake-network proof that all five media variants fan out to recipients and remain downloadable with the expected schema.
- Added a dedicated `pl012` live scenario, proof emission, runner registration, criteria validation, and criteria fixtures.
- Adapted the imported proof to current main's privacy-preserving live payload shape by accepting `mediaAttachments` plus `hasEncryptionMetadata` when raw encryption keys/nonces are intentionally omitted.

Out of scope:
- No original source worktree plan recreation or rerun.
- No PL-013 partial-download cleanup, PL-014 metadata leak checks, notifications, Android, physical iOS, source-doc, COMPLETE_1 doc, or unrelated fixture repair.
- No production media schema rewrite; current main already carried the runtime schema behavior, so this row imports the missing row-owned proof and regression coverage.

Verification evidence:
- `cd go-mknoon && go test ./bridge -run TestPL012 -count=1` - pass.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-012 media schema variants survive live publish and replay payloads"` - pass.
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-012 fake-network media schema variants survive fanout and downloads"` - pass.
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name "PL-012"` - pass.
- Preservation selectors passed: Go PL-002/PL-003 bridge selectors, PL-002 app selector, PL-002 fake-network selector, and PL-002/PL-011/PL-012 criteria selectors.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario pl012 --list-scenarios` - pass, lists `pl012`.
- `dart format --set-exit-if-changed` over the six touched Dart files - pass with 0 changed after formatting.
- Scoped `dart analyze` over the six touched Dart files - pass, `No issues found!`.
- `git diff --check` - pass.
- Required iOS 26.2 live proof passed: `pl012` run id `1779315442068`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_pl012_IzemJ1`, Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`, orchestrator verdict `pl012 proof passed: pl012 verdicts valid for alice, bob, charlie`.

Controller acceptance evidence:
- Read-only scouts and controller disk checks found the PL-012 selectors, `pl012` runner registration, criteria validation, and live proof fields missing from main while adjacent PL-002/PL-011 coverage was already present.
- The first iOS 26.2 live attempt `1779314975420` exposed a current-main proof-shape mismatch: verdict payloads used privacy-preserving `mediaAttachments` and `hasEncryptionMetadata` rather than raw `media` key/nonce fields. The row-owned harness/criteria/test fixtures were reconciled to that stronger privacy shape and rerun.
- The controller rechecked row-owned file inventory before execution and imported only PL-012 media schema proof deltas, leaving PL-013+ media cleanup/privacy rows untouched.
- All required focused row tests, affected PL-002/PL-011 preservation selectors, scoped maintenance checks, and iOS 26.2 live proof passed.
