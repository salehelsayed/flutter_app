# INTEGRATE-DE-015 Payload Parse Failure Continuity Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-015` Payload parse failure does not poison the group stream.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-015-plan.md`.
- Source status: accepted/covered with native, bridge, and fake-network proof that malformed group payloads emit `group:payload_parse_failed`, route no normal message, and do not block later valid delivery.

## Integration Scope

Imported only the missing row-owned Dart bridge and fake-network proof artifacts. Current main already had equivalent or stronger native malformed-payload then valid-delivery coverage in `TestGP023ReceivePathContinuesAfterMalformedPayload`, so the source row's native Go selector was recorded as already present and not duplicated.

In scope:
- `test/core/bridge/go_bridge_client_test.dart`: rename/extend the existing payload-parse diagnostic test as the DE-015 bridge selector and prove a later valid `group_message:received` callback fires exactly once.
- `test/shared/fakes/fake_group_pubsub_network.dart`: add minimal diagnostic stream registration and `emitPayloadParseFailureDiagnostic` for row-owned fake-network proof.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add the DE-015 fake-network diagnostic-continuity selector.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- Duplicating the already-covered native Go continuity test, production app/native behavior changes, source fake-network route-mode/delivery-record/decryption/validation helper changes, source `GroupTestUser` wholesale changes, DE-013 schema validation, DE-014 decryption repair, DE-016 validation diagnostics, DE-017 ordering, DE-019 EventChannel recovery, DE-020 starvation, UI, notification routing, relay/device proof, simulator proof, 3-party E2E proof, and unrelated completeness inventory repair.

## Verification

Focused row checks:
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'DE-015'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-015'` passed (`+1`).

Already-present native coverage check:
- `cd go-mknoon && go test ./node -run 'TestGP023ReceivePathContinuesAfterMalformedPayload' -count=1` passed (`ok github.com/mknoon/go-mknoon/node 2.128s`), covering malformed payload parse diagnostics, no malformed receive/plaintext side effect, and later valid `group_message:received` delivery.

Static and hygiene checks:
- `dart format test/core/bridge/go_bridge_client_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_resume_recovery_test.dart` completed (`0 changed` after patch formatting).
- `flutter analyze --no-pub test/core/bridge/go_bridge_client_test.dart test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`No issues found!`).
- Scoped `git diff --check` passed before ledger closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+206 -3` only on preserved non-DE-015 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-015 required host native-equivalent, Dart bridge, and fake-network proof only; no iOS 26.2 simulator/live proof was required or run.
