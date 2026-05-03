# Session EK-006 Plan - Stale Epoch and Removed-Sender Rejection

Status: accepted

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `EK-006` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: move EK-006 to `Covered` only if concrete raw/protocol and app-level evidence proves policy-allowed grace traffic is accepted while stale or unauthorized epoch traffic is rejected before user-visible message state.
- Source status at intake: `Partial`.

## Evidence Intake

Current repo behavior:

- Go PubSub validator accepts authorized previous-epoch traffic during the configured grace period.
- Go PubSub validator rejects previous-epoch traffic after grace expiry before delivery.
- Go PubSub validator rejects a removed/non-member sender even when the sender has a valid previous-epoch envelope during grace.
- Go subscription handling decrypts previous-epoch traffic during grace and drops previous-epoch traffic after grace expiry without emitting `group_message:received`.
- Flutter send, live fake-network, direct incoming-handler, and offline replay tests enforce the persisted removal cutoff so only pre-cutoff removed-sender traffic is accepted; at-cutoff or later traffic does not create a normal UI/message row.

## Scope Guard

Do not require new product code for EK-006 if the existing raw Go and app-level tests already satisfy the row. Do not claim first-class device identity, MLS commit semantics, packet capture, or real-device proof from this row.

## Direct Evidence

Passed commands:

- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_(AcceptsPreviousEpochDuringGrace|RejectsPreviousEpochAfterGraceExpires|AcceptsCurrentEpochDuringGrace|RejectsRemovedSenderPreviousEpochDuringGrace)$|TestHandleGroupSubscription_(DecryptsPreviousEpochDuringGrace|DropsPreviousEpochAfterGraceExpires)$' -v`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'removed-sender'`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed member_removed lets remaining peers accept only removed-sender inbox messages from before removedAt'`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects stale send after local membership removal before persistence'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff'`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'removed member cannot send after self-removal cleanup'`
- `git diff --check`

## Execution Result

Verdict: accepted.

EK-006 is covered by existing row-owned evidence. The Go tests prove epoch grace, epoch expiry, and removed-sender rejection at the validator/subscription boundary. The Flutter tests prove the shipped app and fake-network paths do not persist or surface stale removed-sender traffic after the removal cutoff, while preserving policy-allowed pre-cutoff traffic. No production code change was needed.

Supporting `group-real-network-nightly`, device-lab, and packet-capture proof was not run and remains supplemental because the row now has host-side raw-protocol plus app-level fake-network/offline-replay evidence.
