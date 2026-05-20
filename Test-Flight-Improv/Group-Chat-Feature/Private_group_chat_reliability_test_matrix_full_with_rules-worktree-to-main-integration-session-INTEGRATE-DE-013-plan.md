# INTEGRATE-DE-013 Group Message Event Schema Validation Import Contract

Status: accepted

## Historical Source Of Truth

- Source row: `DE-013` Message event schema is validated before persistence.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-013-plan.md`.
- Source status: accepted/covered with listener schema guard, safe diagnostics, listener unit proof, fake-network continuity proof, and signed-system replay preservation evidence.

## Integration Scope

Imported only the missing row-owned Flutter listener schema validation and proof artifacts. Current main already had empty-body malformed-event dropping and COMPLETE_1/native malformed payload coverage, but did not validate the incoming Dart `group_message:received` event map before defaulting malformed fields into persistence.

In scope:
- `lib/features/groups/application/group_message_listener.dart`: add a listener-entry schema validator before typed extraction/persistence, emit `GROUP_MESSAGE_LISTENER_SCHEMA_REJECTED`, reject malformed user-message schema, and preserve signed system payload replay when legacy system plaintext omits `keyEpoch`.
- `test/features/groups/application/group_message_listener_test.dart`: add the DE-013 malformed-schema then valid-event listener proof.
- `test/features/groups/integration/group_resume_recovery_test.dart`: add the DE-013 fake-network malformed-pubsub then valid-delivery proof.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`, this plan, and the integration breakdown ledger.

Out of scope:
- DE-014 decryption repair, DE-015 payload parse diagnostics, DE-016 validation diagnostics, DE-017 membership/content ordering, DE-019 EventChannel recovery, DE-020 starvation, source docs wholesale, COMPLETE_1 docs, native/bridge production changes, fake-network helper expansion beyond this row's test need, criteria/live-harness changes, simulator/device proof, 3-party E2E, UI, notification, media, relay durability, and unrelated adjacent-row tests.

## Verification

Focused row checks:
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'DE-013'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'DE-013'` passed (`+1`).

Affected preservation checks:
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages'` passed (`+1`).

Static and hygiene checks:
- `dart format lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` completed (`0 changed` after patch formatting).
- `flutter analyze --no-pub lib/features/groups/application/group_message_listener.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_resume_recovery_test.dart` passed (`No issues found!`).
- Scoped `git diff --check` passed before ledger closure.

Named gates:
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+204 -3` only on preserved non-DE-013 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remains red on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`732/733`).

## Verdict

Accepted. DE-013 required host Flutter listener and fake-network schema-continuity proof only; no iOS 26.2 simulator/live proof was required or run.
