# INTEGRATE-IR-014 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-014` / `Relay replay payloads are opaque to relay operators`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-014-plan.md`.
- Source closure state: covered/accepted with direct app, fake-network, and native group inbox replay-opacity proofs.
- Source proof profile: host-only. Unit, Integration, and Fake Network are required; Smoke is recommended; `3-Party E2E` is `N/A`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-014 imports only missing row-owned Dart proof artifacts for relay replay payload opacity:

- `test/features/groups/application/send_group_message_use_case_test.dart`
  - Added `IR-014 group inbox store relay payload omits plaintext and secrets`.
  - The test proves the actual `group:inboxStore` command carries only `groupId`, opaque replay `message`, and `recipientPeerIds`; omits retired push preview fields; keeps replay content in ciphertext/nonce; and excludes protected plaintext, sender display name, invite/member secrets, and group key fragments.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-014 fake-network inbox store relay payload is opaque while delivery succeeds`.
  - The test proves fake-network live delivery still succeeds while the relay-visible durable inbox payload remains routing-limited and opaque.

Production code stayed untouched because current main already builds `group_offline_replay` envelopes through `group.encrypt`, sends only the replay envelope through `group:inboxStore`, and omits retired native push preview fields from the group inbox request path.

The source native Go selector body is already present in main as `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope`, so `TestIR014BuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope` was treated as `skipped_already_present` rather than duplicated.

Out of scope: `IR-012`/`IR-013` repair validation, `IR-015` media replay breadth, relay ACL changes, criteria/live harnesses, iOS 26.2 proof, UI, notifications, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'IR-014'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-014'
(cd go-mknoon && go test ./node -run 'TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|TestGI035GroupInboxStoreSendsEncryptedEnvelopeWithoutPlaintextToRelay' -count=1)
flutter analyze --no-pub lib/features/groups/application/send_group_message_use_case.dart lib/features/groups/application/group_offline_replay_envelope.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name 'GO-008 EK-002 GI-035|text group message does not send plaintext preview fields|media-only group message does not send plaintext media preview fields|IR-006|IR-007'
flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --plain-name 'IR-007'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-007'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'IR-006'
(cd go-mknoon && go test ./node -run 'Test(BuildGroupInboxStoreRequest_(MarshalsRecipientPeerIds|OmitsRetiredPushTitle|OmitsRetiredPushBody|PreservesOpaqueReplayEnvelope)|GM028BuildGroupInboxStoreRequestDropsBlankRecipientPeerIds|GI003GroupInboxStoreOmitsPlaintextPushPreviewFields|GI035GroupInboxStoreSendsEncryptedEnvelopeWithoutPlaintextToRelay)$' -count=1)
dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart
git diff --check
```

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +216 -3, red only on preserved non-IR-014 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

No iOS 26.2 simulator/live proof was run or required because source `3-Party E2E` is `N/A`.

## Closure Verdict

`INTEGRATE-IR-014` is accepted. Main now has row-owned direct and fake-network proofs that relay inbox replay payloads remain opaque and routing-limited while preserving delivery, with native Go replay-envelope opacity already covered by existing equivalent main coverage.
