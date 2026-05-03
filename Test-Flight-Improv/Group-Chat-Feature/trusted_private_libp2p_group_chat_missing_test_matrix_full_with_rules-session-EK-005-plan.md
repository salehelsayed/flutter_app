# Session EK-005 Plan - Future Epoch Queue And Key Repair

Status: prerequisite-blocked

## Run Mode

- Active mode: implementation-committed gap-closure.
- Source row: `EK-005` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Closure bar: move EK-005 to `Covered` only if unknown future-epoch messages are queued or marked pending, key-sync repair is triggered, and replay after the missing epoch arrives either decrypts correctly or remains safely undecryptable.
- Source status at intake: `Open`.

## Evidence Intake

Current repo behavior:

- Go PubSub validator rejects unknown future live epochs before delivery.
- Offline replay with a missing future epoch key does not call `group.decrypt`, does not expose plaintext, and stores one safe `undecryptable` placeholder keyed by the replay `messageId`.
- Mixed known-epoch offline replay remains decryptable and persists under each envelope epoch.

Known current gap:

- There is no durable future-epoch pending queue state, key-sync repair trigger, retry-after-key-arrival owner, or UI/lifecycle contract for pending key repair.
- The current placeholder is fail-closed recovery, not a complete queue-and-repair implementation.

## Scope Guard

Do not mark EK-005 `Covered` from fail-closed placeholder behavior alone. A complete closure needs a real repair primitive that knows how to hold or reattempt future-epoch content after the missing key arrives.

## Direct Evidence

Passed commands:

- `cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery' -v`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'`

## Blocker

- Blocker class: `missing_future_epoch_queue_repair_primitives`.
- EK-005 remains `Partial`; it has fail-closed evidence but lacks the row's required queue, key-sync repair trigger, and retry/decrypt-after-key-arrival behavior.
