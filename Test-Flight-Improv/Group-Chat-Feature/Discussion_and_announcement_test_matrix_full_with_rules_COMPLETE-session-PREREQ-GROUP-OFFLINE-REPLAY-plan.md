# Session Plan: PREREQ-GROUP-OFFLINE-REPLAY

## Session Contract

- source row: `shared prerequisite for RY-013, RY-014, RY-015, and RY-016`
- session classification after execution: `accepted`
- closure target for this session: replace the plaintext relay-backed group replay seam with one opaque encrypted replay-envelope contract that every current group inbox caller and the Flutter drain path can use without splitting the stored-envelope story
- controller-local note: the earlier stale broad contract was tightened and finished under degraded local continuation mode instead of remaining blocked

## Scope Guard

- keep this session on the shared replay-envelope seam only
- do not let prerequisite acceptance overclaim row-owned closure for `RY-013..016`
- keep the stored wrapper intentionally minimal: replay kind, payload type, key epoch, optional message id, ciphertext, and nonce

## Executed Proof

1. `lib/features/groups/application/group_offline_replay_envelope.dart` now materializes opaque encrypted replay envelopes and the current Flutter replay callers now store those envelopes instead of plaintext relay payloads.
2. `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` now recognizes that wrapper, loads the keyed epoch, decrypts through `group.decrypt`, and hands the plaintext back into the existing message or reaction handling path.
3. `go-mknoon/node/group_inbox_test.go` now proves request marshaling preserves the opaque replay envelope exactly, while `go-relay-server/group_inbox_test.go` and `go-relay-server/backend_redis_test.go` prove the shared-store and Redis-backed retrieval surfaces preserve the same opaque payload across cursor reads.
4. The replay gate passed in the current session across `drain_group_offline_inbox_use_case_test.dart`, `send_group_message_use_case_test.dart`, `send_group_reaction_use_case_test.dart`, `remove_group_reaction_use_case_test.dart`, `accept_pending_group_invite_use_case_test.dart`, `dissolve_group_use_case_test.dart`, `group_info_wired_test.dart`, and `group_resume_recovery_test.dart`.

## Files Expected

- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/send_group_reaction_use_case.dart`
- `lib/features/groups/application/remove_group_reaction_use_case.dart`
- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`
- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `go-mknoon/node/group_inbox_test.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

