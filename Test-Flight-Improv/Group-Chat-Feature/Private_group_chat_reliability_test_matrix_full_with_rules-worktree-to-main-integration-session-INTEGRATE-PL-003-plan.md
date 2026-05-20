# INTEGRATE-PL-003 Integration Contract

Row: PL-003 empty/whitespace-only group sends without media.

Status: accepted

Scope:
- Import only the missing PL-003 behavior into the current main worktree.
- Preserve existing accepted or blocked integration edits in the target files.
- Do not update the integration ledger, test inventory, source docs, harness scripts, or unrelated rows.

Acceptance:
- `GroupPublish` rejects whitespace-only text when no media is present.
- The PL-003 Go selector covers the bridge invalid-input response.
- The PL-003 Dart application selector proves no local row, requested ID, bridge command, or bridge publish is created.
- The PL-003 Dart integration selector proves no Alice row, no Bob row, no fake-network publish, and no bridge publish/inbox side effects.

## Execution Evidence

- Imported only the PL-003 bridge validation and row-owned test proof deltas into current main.
- `GroupPublish` now rejects `strings.TrimSpace(params.Text) == "" && len(params.Media) == 0`.
- Added `TestPL003GroupPublishEmptyTextAndNoMediaFailsInvalidInput`.
- Added `PL-003 empty text without media is rejected before local ghost row or bridge publish`.
- Added `PL-003 empty text without media creates no local or remote ghost row`.

Controller verification passed:

- `cd go-mknoon && go test ./bridge -run 'TestPL003|TestGroupPublish_EmptyTextAndNoMedia_Fails|TestGroupPublish_MediaOnly_AcceptsEmptyText|TestPL002' -count=1`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "PL-003 empty text without media is rejected before local ghost row or bridge publish"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "PL-003 empty text without media creates no local or remote ghost row"`
- PL-002 app selector, PL-002 fake-network selector, generic empty-text selector, and generic whitespace-only selector.
- `go test ./internal -run TestGK029ParseGroupPayloadAcceptsPresentEmptyTextWithTimestamp -count=1`
- `dart format --set-exit-if-changed` over touched Dart tests.
- Scoped `flutter analyze --no-pub` over touched Dart tests.
- Scoped `git diff --check` over PL-003 write scope.

Broad residuals are non-PL-003: `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` is red at `+249 -9` on the known non-row residual set, and `./scripts/run_test_gates.sh completeness-check` is red at `734/735` on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
