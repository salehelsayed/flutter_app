# Session Plan: RY-013

## Row Contract

- source row: `RY-013`
- matrix contract: Offline group replay payloads stored on the relay are opaque to relay operators.
- current source truth before execution: `Open`
- closure target for this session: update the source matrix row to `Covered` only if repo-local proof directly shows the relay path stores only the approved minimal wrapper around ciphertext and never exposes plaintext replay content

## Scope Guard

- keep scope on relay opacity, not replay reliability or membership-window behavior
- reuse the shared replay-envelope contract from `PREREQ-GROUP-OFFLINE-REPLAY`
- do not claim stronger secrecy than the intentionally approved wrapper metadata

## Executed Proof

1. `group_offline_replay_envelope.dart` now stores only replay kind, payload type, key epoch, optional message id, ciphertext, and nonce.
2. `go-mknoon/node/group_inbox_test.go` proves request marshaling preserves that opaque envelope exactly.
3. `go-relay-server/group_inbox_test.go` and `go-relay-server/backend_redis_test.go` prove shared-store and Redis-backed retrieval preserve the same opaque payload across cursor retrieval.

## Files Expected

- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `go-mknoon/node/group_inbox_test.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

