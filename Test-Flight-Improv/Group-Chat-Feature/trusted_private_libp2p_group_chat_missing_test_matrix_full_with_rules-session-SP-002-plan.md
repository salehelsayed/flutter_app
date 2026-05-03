# SP-002 Session Plan - Metadata minimization covers topics, discovery, relays, push, and diagnostics

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:14:00+02:00 | Local planner completed | SP-002 source matrix row; ordered-session SP-002 row; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/group_inbox.go`; `go-mknoon/node/group_inbox_test.go`; `go-relay-server/inbox.go`; push fallback tests; bridge diagnostics sanitization tests; group retry/send tests | Existing evidence covers group topic/rendezvous names omitting human-readable metadata, generic encrypted group push, privacy-safe diagnostics, and Flutter group inbox helpers omitting preview fields. The native Go group inbox request builder still serializes caller-supplied retired `pushTitle` and `pushBody`, which is a row-owned relay/push metadata gap. | Remove retired preview-field serialization at the native request boundary, add focused Go and Dart retry proof, then close SP-002 only if direct gates pass and docs record concrete evidence. |

## Execution Progress

| timestamp | role | files inspected or updated | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T11:22:00+02:00 | Local executor completed | `go-mknoon/node/group_inbox.go`; `go-mknoon/node/group_inbox_test.go`; `go-mknoon/bridge/bridge.go`; `go-mknoon/bridge/bridge_test.go`; `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | Removed retired native `pushTitle` / `pushBody` serialization, made bridge JSON parsing ignore those legacy fields, and proved stale Flutter retry payloads do not re-emit them to `group:inboxStore`. | Run focused Go, relay, Flutter retry, push, diagnostics, and diff hygiene gates. |
| 2026-05-01T11:31:00+02:00 | Local verifier completed | Go node request/topic/relay-visible/protocol tests; Go bridge group inbox tests; relay push/group inbox tests; Flutter retry, push, and diagnostics tests; `git diff --check` | All direct SP-002 gates passed. A first diagnostics command used `--plain-name` with a regex and ran no tests; rerunning with `--name` selected the intended diagnostics slice and passed. | Update source matrix, inventory, and session ledger to `Covered`/accepted. |

## real scope

SP-002 asks that sensitive group names, membership, plaintext previews, relay addresses, and diagnostics are minimized across shipped metadata surfaces. This session covers:

- group topic and rendezvous identifiers
- relay/group inbox store requests and relay-visible replay envelopes
- data-only encrypted group push payloads
- local retry of stale inbox retry payloads
- Go and Flutter diagnostics surfaces

## closure bar

SP-002 can be resolved when direct code and tests prove:

- group topics and rendezvous namespaces do not embed human-readable group names/descriptions
- native group inbox requests do not serialize retired plaintext push preview fields even if callers supply them
- stale persisted retry payloads containing old `pushTitle` / `pushBody` fields are replayed through the Flutter bridge without those fields
- encrypted group push and diagnostics evidence remains green

## session classification

`needs_code_and_tests`, reclassified from evidence-gated because native group inbox request proof exposed a row-owned metadata leak.

## Device/Relay Proof Profile

- Profile for this session: host-only Go and Flutter proof.
- Live packet capture and device-lab proof are supplemental because the row-owned leak is visible in deterministic request serialization and push/diagnostics unit tests.

## files expected to change

- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/bridge/bridge_test.go`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- SP-002 closure docs after tests pass

## exact tests and gates run

- `cd go-mknoon && go test ./node -run 'GroupTopicAndRendezvousNamespace|JoinGroupTopic_LogOmitsHumanReadableMetadata|GroupInboxStoreRequest|GroupRelayVisible|PubSub|Protocol' -v -count=1` passed.
- `cd go-mknoon && go test ./bridge -run 'GroupInboxStore' -v -count=1` passed.
- `cd go-relay-server && go test ./... -run 'GroupPush|Push|Forbidden|GroupInbox|Unauthorized' -count=1` passed.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` passed (`+10`).
- `flutter test --no-pub test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/push_decrypt_preview_test.dart` passed (`+34`).
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name 'group validation reject|ER005|PlatformException|group decryption failure|group payload parse failure'` passed (`+8`).
- `git diff --check` passed.

## Recovery Input

- Misrun command: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group validation reject|ER005|PlatformException|group decryption failure|group payload parse failure'`.
- Result: no tests ran because `--plain-name` is literal and does not apply the regex selector as intended.
- Blocker class: command selector mistake; no code or test failure.
- Recovery command: `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --name 'group validation reject|ER005|PlatformException|group decryption failure|group payload parse failure'` passed.

## scope guard

Do not claim that relay participation metadata is hidden from the relay. The shipped relay necessarily sees relay peer IDs, registered push tokens, group IDs, recipient peer IDs, and encrypted group replay blobs. SP-002 closes only avoidable metadata: human-readable group metadata, plaintext previews, raw secrets, raw peer IDs in diagnostics, and sensitive multiaddrs in Flutter logs/errors.

## Final Execution Verdict

`accepted`: SP-002 is covered for shipped metadata-minimization surfaces. Group topics/rendezvous/logs omit human-readable group metadata; native group inbox requests no longer serialize retired plaintext push preview fields; stale Flutter retry payloads with legacy preview fields replay through `group:inboxStore` without those fields; relay and push tests keep encrypted group pushes generic/data-only; and diagnostics/flow logs stay sanitized. Relay-visible participation metadata remains unavoidable and explicitly scoped: group IDs, recipient peer IDs, registered push tokens, relay addresses, and encrypted replay blobs are still visible to relay infrastructure.
