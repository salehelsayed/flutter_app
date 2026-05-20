# INTEGRATE-IR-015 Minimal Integration Contract

Status: accepted

## Source Evidence

- Source row: `IR-015` / `Replay supports text, quotes, image, video, files, GIFs, and voice uniformly`.
- Source worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-015-plan.md`.
- Source closure state: covered/accepted with direct app, MIME policy, fake-network, criteria, runner, and iOS 26.2 3-party live proof evidence.
- Source live proof run: `1778627714711`, using iOS 26.2 Alice `560D3E2D-78F8-4D28-A010-16B399581C99`, Bob `511B36DA-7113-41A7-A718-4450C87C0E62`, and Charlie `DE36DBBE-64FC-4652-AAD9-17329A1BA245`.

This contract is only for importing and verifying the already-closed source row in main. It does not recreate or replace the historical source implementation plan.

## Integration Scope

IR-015 imports only missing row-owned replay-variant breadth support and proof artifacts:

- `lib/core/media/group_media_mime_policy.dart`
  - Added safe generic file replay support by mapping `application/octet-stream` to media type `file`.
- `test/core/media/group_media_mime_policy_test.dart`
  - Pinned `application/octet-stream` as an allowed file MIME and kept missing, wildcard, dangerous, and unsupported MIME values rejected.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - Added `IR-015 replay rehydrates text quote image video file GIF and voice after live duplicate`.
  - The test proves a live duplicate plus encrypted replay persists one message, preserves `quotedMessageId`, keeps key epoch `1`, and rehydrates image, video, file, GIF, and voice attachments including duration and waveform metadata.
- `test/features/groups/integration/group_resume_recovery_test.dart`
  - Added `IR-015 fake-network replay drains text quote image video file GIF and voice uniformly`.
  - The test proves Alice sends text, quote, image, video, file, GIF, and voice variants while Bob is offline; Bob drains durable replay exactly once across repeat drains; quote, media descriptors, and key epoch are preserved.
- `integration_test/group_multi_party_device_real_harness.dart`
  - Added `ir015` role/scenario support, variant send/drain proof helpers, and media descriptor serialization for duration/waveform in `mediaAttachments`.
- `integration_test/scripts/run_group_multi_party_device_real.dart`
  - Added `ir015` scenario discovery and dispatch using the existing 3-role offline/relaunch orchestration path.
- `integration_test/scripts/group_multi_party_device_criteria.dart`
  - Added `ir015` requirements and `ir015VariantReplayProof` validation for variant counts, quote target, exact-once proof, media descriptor rehydration, and role-specific live/offline-drain evidence.
- `test/integration/group_multi_party_device_criteria_test.dart`
  - Added the `ir015` scenario requirement plus valid, missing-media-proof, and quote-target-mismatch criteria selectors.

The row was partially present in main through neighboring quote/media/video/GIF/voice coverage, but main lacked the row-owned `IR-015` selectors, criteria/live harness support, and safe generic file replay MIME mapping. The integration therefore imported only the missing meaningful IR-015 delta.

Out of scope: `IR-016` retention cutoff, `IR-017` dispatcher overflow replay, `IR-018` restart freshness, `IR-019` hidden outer-id dedupe, relay opacity, history repair validation, UI, notifications, Android, physical iOS, macOS app-peer roles, and adjacent replay rows.

## Verification

Passed:

```bash
flutter test --no-pub test/core/media/group_media_mime_policy_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'IR-015'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-015'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'IR-015'
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir015 --list-scenarios
flutter analyze --no-pub lib/core/media/group_media_mime_policy.dart test/core/media/group_media_mime_policy_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'drains encrypted replay with quote plus image, video, GIF, and voice attachments|skips encrypted replay with dangerous media before message or attachment storage|GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects dangerous media MIME before persistence, publish, or inbox store'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name 'GE-023 media attachments in private group through remove/re-add respect entitlement|GE-024 quoted replies across membership boundary preserve entitlement fallback'
flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'GE-024 renders available and unavailable quote parents without crashing'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'accepts valid GE-023 media remove/re-add verdicts|accepts valid GE-024 quoted reply boundary verdicts'
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'IR-014 group inbox store relay payload omits plaintext and secrets'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'IR-014 fake-network inbox store relay payload is opaque while delivery succeeds'
dart format --set-exit-if-changed lib/core/media/group_media_mime_policy.dart test/core/media/group_media_mime_policy_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
```

iOS 26.2 live proof passed:

```bash
MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario ir015 -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

- Run id: `1779171554812`.
- Shared proof directory: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ir015_jcVFVS`.
- Alice device: `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3` (`UP004 Alice iPhone 17 Pro iOS 26.2`).
- Bob device: `279B82AE-2BB9-4924-9AAE-581870ED3FA9` (`UP004 Bob iPhone Air iOS 26.2`).
- Charlie device: `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` (`UP004 Charlie iPhone 17 iOS 26.2`).
- Verdict: `ir015 proof passed: ir015 verdicts valid for alice, bob, charlie`.

Classified residual gates:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
# +217 -3, red only on preserved non-IR-015 residuals BB-007, BB-012, and GM-029

./scripts/run_test_gates.sh completeness-check
# 732/733, red only on unrelated test/shared/fakes/fake_group_pubsub_network_test.dart classification
```

Additional preservation checks were red only on pre-existing bootstrap/key fixture residuals outside IR-015:

- `group_media_fanout_test.dart` selector `discussion members independently download image, video, and voice for every eligible recipient` failed with `GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING`.
- `group_new_member_onboarding_test.dart` selector `quoted reply to pre-join parent keeps missing-parent fallback for new member` failed with `GROUP_SEND_MSG_USE_CASE_BOOTSTRAP_PENDING`.

## Closure Verdict

`INTEGRATE-IR-015` is accepted. Main now has row-owned direct, fake-network, criteria, runner, and iOS 26.2 live proof that replay uniformly preserves text, quotes, image, video, file, GIF, and voice variants while deduping live-plus-replay delivery and retaining quote/media/key-epoch evidence.
