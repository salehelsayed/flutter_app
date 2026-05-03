# Session EK-012 Plan - Replay Protection Across Messages, Commits, Invites, and Key Packages

Status: prerequisite-blocked

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `EK-012` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: move EK-012 to `Covered` only if replay protection is concrete for messages, signed commits/transitions, invites, and key packages, with replays rejected or idempotent before rollback, permission downgrade, stale key, or UI/data corruption.
- Source status at intake: `Partial`.

## Evidence Intake

Current repo behavior:

- Message replay and duplicate delivery dedupe by application `messageId` without overwriting trusted content.
- Live PubSub plus inbox delivery of the same message converges to one stored row.
- Go PubSub duplicate/sequence tests preserve application message IDs for Dart dedupe and fail closed for bad signatures, unknown future epochs, wrong keys, and tampered nonce/ciphertext.
- Invite replay paths are idempotent or blocked: duplicate direct invites for an already joined group reject, multi-use replay becomes duplicate-safe, consumed single-use invites return `alreadyUsed`, expired pending invites are removed without join, and signed revocation tombstones keep delayed direct/mailbox invite copies rejected.

Known current gap:

- There is no repo-owned signed commit/transition replay model, commit event log, key-package replay/freshness/tombstone model, or cross-surface replay diagnostics contract.
- Direct invite and message replay evidence is real, but it cannot close commit or key-package replay requirements that have no production primitive yet.

## Scope Guard

Do not mark EK-012 `Covered` from message and invite replay evidence alone. A complete closure needs signed commit/transition and first-class key-package replay protection or an explicit product decision removing those primitives from scope.

## Direct Evidence

Passed commands:

- `cd go-mknoon && go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery|TestHandleGroupSubscription_EmitsDecryptionFailedEvent(ForTamperedNonce|ForTamperedCiphertext)?$' -v`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'IJ005 multi-use direct credential replay is duplicate-safe'`
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'IJ003 revoked invite removes pending state and delayed direct plus mailbox copies stay rejected'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'alreadyUsed'`
- `flutter test --no-pub test/features/groups/application/accept_pending_group_invite_use_case_test.dart --plain-name 'expired'`
- `git diff --check`

## Blocker

- Blocker classes:
  - `missing_signed_commit_replay_protection`
  - `missing_first_class_key_package_replay_model`
  - `missing_cross_surface_replay_diagnostics`
  - `missing_commit_transition_event_log`
  - `missing_key_package_tombstone_or_freshness_contract`
- EK-012 remains `Partial`; current evidence proves message and invite replay behavior, but signed commit/transition and key-package replay protection are not implemented or testable as first-class surfaces.
