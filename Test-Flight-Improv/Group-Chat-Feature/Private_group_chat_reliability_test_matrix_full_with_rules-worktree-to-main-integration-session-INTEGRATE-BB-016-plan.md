Status: accepted

# INTEGRATE-BB-016 Standard Integration Plan

## Planning Progress

- 2026-05-17T07:43:00+02:00 - Inspected source matrix row `BB-016`, source session breakdown row, historical source plan/closure evidence, source test-inventory note, source production/test files, current main code/tests, and COMPLETE_1 metadata/config overlap language. Main has existing Dart description payload support and some metadata rejoin coverage, but lacks native create description preservation, native metadata-field preservation, and exact BB-016 selectors. Decision: import only the missing meaningful BB-016-owned native metadata delta and row-named Go/Dart tests.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-016` / source row `BB-016`: optional description and supported metadata fields must not drift between Dart payloads, Go config storage, native create return values, persistence, update config, and restart rejoin.

Reuse the historical source worktree BB-016 plan and closure as evidence only. Do not recreate, rewrite, or rerun the original implementation plan. Do not reimplement this row from scratch. Import only the missing meaningful BB-016-owned delta into main, adapted to current main drift.

In scope:

- Extend native `node.GroupConfig` to preserve `avatarBlobId`, `avatarMime`, `metadataUpdatedAt`, `configVersion`, and `stateHash` in addition to existing `description`.
- Update native `GroupCreate` to parse optional `description`, store it in `GroupConfig`, and return it in `groupConfig` when present.
- Add row-named Go bridge/node selectors for native description and metadata preservation.
- Add row-named Dart helper/create/rejoin selectors for create/update/rejoin metadata alignment.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or historical source plan docs into main.
- Do not edit COMPLETE_1 docs.
- Do not import metadata editing UI, avatar upload/media ACL, membership lifecycle, key-rotation, notification, device/relay, simulator, or broader config convergence rows.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-016`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-016`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-016-plan.md`.
- Source closure evidence: source `test-inventory.md` row `BB-016` and source matrix `BB-016` covered note.
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Source File Evidence

Meaningful source files for integration:

- `go-mknoon/node/group.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/pubsub_test.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/create_group_use_case_test.dart`
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`

Source docs changed in the worktree closure are historical evidence only and must not be copied.

## Duplicate Presence In Main

Main already sends optional Dart create descriptions, builds metadata in rejoin config payloads, and has adjacent non-row-named metadata assertions. Main lacks the native BB-016 metadata fields in `GroupConfig`, lacks `GroupCreate` description echo in returned `groupConfig`, and lacks the exact BB-016 selectors. Import only those missing deltas.

## COMPLETE_1 Overlap Rows

Inspect and preserve COMPLETE_1 config convergence, metadata, and bridge contract rows by behavior and file overlap. No COMPLETE_1 row owns the exact BB-016 worktree-to-main native create description plus native metadata-field preservation contract.

## Tests And Gates To Run

Focused BB-016 proof:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name "BB-016"
(cd go-mknoon && go test ./bridge ./node -run 'TestBB016' -count=1)
```

Preservation/backstop:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name "callGroupUpdateConfig"
flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart --plain-name "persists creator identity"
flutter test --no-pub test/features/groups/application/rejoin_group_topics_use_case_test.dart --plain-name "rejoin sends latest metadata"
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart
gofmt -w go-mknoon/node/group.go go-mknoon/bridge/bridge.go go-mknoon/bridge/bridge_test.go go-mknoon/node/pubsub_test.go
flutter analyze --no-pub test/core/bridge/bridge_group_helpers_test.dart test/features/groups/application/create_group_use_case_test.dart test/features/groups/application/rejoin_group_topics_use_case_test.dart
git diff --check
```

## Final Status Contract

- `accepted`: missing meaningful BB-016 code/tests imported and required focused/preservation tests pass.
- `skipped_already_present`: all meaningful BB-016 code and selector evidence already exists in main.
- `blocked_conflict`: focused tests expose a conflict with accepted COMPLETE_1/main behavior.
- `blocked_external_fixture`: only if a required external fixture unexpectedly blocks closure.

## Execution Progress

- 2026-05-17T07:50:00+02:00 - Imported only the missing BB-016 native metadata delta: `node.GroupConfig` now preserves `avatarBlobId`, `avatarMime`, `metadataUpdatedAt`, `configVersion`, and `stateHash`, and native `GroupCreate` parses/stores/returns optional `description`. Did not import adjacent source-worktree key-material guard or metadata/UI work.
- 2026-05-17T07:53:00+02:00 - Added exact row-named selectors: Go bridge `TestBB016GroupCreatePreservesDescriptionInReturnedConfig`, Go node `TestBB016GroupConfigMetadataFieldsSurviveSerializationAndUpdate`, Dart helper `BB-016 group create and update config preserve metadata fields`, Dart create `BB-016 create with description persists and matches bridge config`, and Dart rejoin `BB-016 rejoin sends metadata fields with valid state hash`.
- 2026-05-17T07:58:00+02:00 - Focused BB-016 Flutter selector passed (`+3`) and Go `TestBB016` passed for `bridge` and `node`. Affected overlap selectors passed: helper `callGroupUpdateConfig` (`+3`), create identity preservation (`+1`), BB-011 rejoin latest config preservation (`+1`), and native update-config snapshot preservation (`ok node 0.363s`).
- 2026-05-17T08:01:00+02:00 - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passed (`+167`). Initial scoped analyzer found one non-functional unnecessary null assertion in touched `create_group_use_case_test.dart`; removed the redundant `!`, then reran focused BB-016 Flutter (`+3`), Go `TestBB016` (`bridge`/`node`), scoped analyzer (`No issues found`), Dart format (`0 changed`), gofmt, and row-scoped `git diff --check` successfully.

## Final Verdict

`accepted` - BB-016's missing meaningful row-owned delta has been imported into main. Accepted files are `go-mknoon/node/group.go`, `go-mknoon/bridge/bridge.go`, `go-mknoon/bridge/bridge_test.go`, `go-mknoon/node/pubsub_test.go`, `test/core/bridge/bridge_group_helpers_test.dart`, `test/features/groups/application/create_group_use_case_test.dart`, and `test/features/groups/application/rejoin_group_topics_use_case_test.dart`. Source docs and unrelated worktree changes were not copied.
