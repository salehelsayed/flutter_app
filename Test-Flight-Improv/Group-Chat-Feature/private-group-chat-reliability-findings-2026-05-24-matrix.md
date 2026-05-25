# Private Group Chat Reliability Findings - 2026-05-24 Matrix

Source: user-supplied critical/high findings batch received 2026-05-24.

Status vocabulary:
- `Open`: meaningful current code gap, assigned to a session.
- `Closed`: meaningful current code gap fixed in this batch with focused evidence.
- `Covered`: current repo already has code/schema/tests covering the finding.
- `Skipped`: finding is stale, mismapped, or not meaningful for current repo.
- `Blocked`: meaningful but not safe as a row-local patch without a larger protocol/session contract.

| Row | Source Finding | Status | Session | Current Assessment |
|---|---|---:|---|---|
| PGC2-001 | EventDispatcher package mismatch | Skipped | S0 | Stale: `go-mknoon/node/node.go` defines `node.EventCallback`; bridge adapts with `nodeCallbackAdapter`. |
| PGC2-002 | Rotation succeeds when `sendP2PMessage` is null | Closed | S2 | Fixed: rotation fails closed when distribution targets exist without direct transport; per-device send fallback no longer reports silent success. |
| PGC2-003 | Rotation retry audit material not idempotent | Closed | S2 | Fixed within current schema: pending draft `createdAt` is reused as direct update `eventAt`; no regenerated timestamp for the same draft retry. Full signed-payload persistence remains part of the two-phase protocol follow-up if adopted. |
| PGC2-004 | Batch timeout leaves in-flight key sends | Closed | S2 | Fixed: distribution is sequential/per-device; late direct-send success after timeout is awaited and counted before promotion. |
| PGC2-005 | Direct key update activates before signed rotation commit | Blocked | S5 | Meaningful protocol gap, but current code treats direct key update as activation and `key_rotated` as audit/timeline only. Safe closure needs a two-phase pending-key activation schema and listener contract. |
| PGC2-006 | Dispatcher drops message-bearing events | Closed | S1 | Fixed: critical message-bearing events are preserved past nominal cap while overflow diagnostics are emitted; lossy behavior remains limited to non-critical events. |
| PGC2-007 | Rotation skips active members without ML-KEM device | Closed | S2 | Fixed: rotation validates active non-self member coverage and fails closed for undeliverable active members. |
| PGC2-008 | Invite listener handles messages concurrently | Closed | S3 | Fixed: invite listener serializes async message handling through a processing chain. |
| PGC2-009 | Revocation expiry uses sender timestamp | Closed | S3 | Fixed: revocation handling uses local receive time and no longer falls back to sender-controlled message timestamps for freshness. |
| PGC2-010 | Invite acceptance does not record consumption/tombstone | Covered | S0 | `accept_pending_group_invite_use_case.dart` commits consumed invites and welcome tombstones after successful materialization. |
| PGC2-011 | Missing invite revocation/consumption/tombstone schema | Covered | S0 | Migrations `055`, `056`, and `064` plus helpers are wired in `main.dart`. |
| PGC2-012 | Invite send trusts caller-supplied key/epoch | Closed | S3 | Fixed: `sendGroupInvite` compares caller key/epoch with `groupRepo.getLatestKey` and rejects stale/mismatched material. |
| PGC2-013 | Invite acceptance persists group before bridge join | Covered | S0 | Current design keeps pending invite retryable after `bridgeError`; duplicate compatible retry re-runs `group:join`. No schema change in this batch. |
| PGC2-014 | Live key repair without replay envelope becomes undecryptable | Closed | S4 | Fixed: live repair rows without replay envelopes record a waiting attempt and remain pending. |
| PGC2-015 | `dbInsertGroupKey` uses `replace` | Closed | S4 | Fixed: same-epoch insert is idempotent for identical material and throws on conflicting material instead of replacing. |
| PGC2-016 | Same-epoch key conflict only logs | Closed | S4 | Fixed: same-epoch key conflicts now request key repair with `same_epoch_key_conflict`. |
| PGC2-017 | Dispatcher shutdown unsafe | Closed | S1 | Fixed: dispatcher stop is idempotent and emit-after-stop is a no-op. |
| PGC2-018 | Dispatcher mutates caller data map | Closed | S1 | Fixed: dispatcher clones caller event maps before enqueue and mutates only the clone during delivery. |
| PGC2-019 | Key distribution lacks inbox fallback/retry state | Closed | S2 | Fixed: rotation supports optional inbox fallback for failed direct key update delivery; durable per-device state remains part of the blocked two-phase protocol if expanded. |
| PGC2-020 | Batch invite targets one device only | Closed | S3 | Fixed: batch invite sending expands to active recipient devices, using legacy peer fallback only when no active devices exist. |
| PGC2-COMPAT | Null-aware map entries need Dart 3.8+ | Skipped | S0 | `pubspec.yaml` has `sdk: ^3.9.0`, so syntax is supported. |

## Evidence

- `go test ./node -run 'TestEventDispatcher|TestDE010|TestDE011|TestDE012|TestDE020|TestST005|TestPL008' -count=1`
- `flutter test test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_pending_key_repair_service_test.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/send_group_invite_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `flutter analyze lib/core/database/helpers/group_keys_db_helpers.dart lib/features/groups/application/broadcast_voluntary_leave_use_case.dart lib/features/groups/application/group_invite_listener.dart lib/features/groups/application/group_key_update_listener.dart lib/features/groups/application/group_pending_key_repair_service.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart lib/features/groups/application/send_group_invite_use_case.dart lib/features/groups/presentation/screens/group_info_wired.dart test/core/database/helpers/group_keys_db_helpers_test.dart test/features/groups/application/group_invite_listener_test.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/application/group_pending_key_repair_service_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/application/send_group_invite_use_case_test.dart`
- `git diff --check -- <batch touched files>`
