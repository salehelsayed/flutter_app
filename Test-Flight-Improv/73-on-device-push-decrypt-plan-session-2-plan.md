# 73 - Session 2 Plan: Client Send-Path Redaction

## Scope

Implement the sender-owned Phase 2 slice:

- new encrypted 1:1 chat envelopes no longer put `senderUsername` in the outer
  relay-visible envelope
- the username remains inside the encrypted inner payload and existing receive
  parsing continues to read it after decrypt
- group offline replay send paths stop serializing or forwarding `pushTitle`
  and `pushBody`
- group dissolve replay uses the same ciphertext-only store contract
- legacy retry payloads that still contain `pushTitle` / `pushBody` are
  tolerated, but the retry handoff does not forward them to the relay

## Code Entry Points

- `lib/features/conversation/domain/models/message_payload.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/dissolve_group_use_case.dart`

## Tests And Gates

Focused tests:

- `flutter test test/features/conversation/domain/models/message_payload_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- targeted group retry tests if helper behavior changes legacy retry payloads

Named gates if runtime allows after focused suites:

- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`

## Done Criteria

- New v2 encrypted chat envelopes omit outer `senderUsername`.
- Group message/dissolve/retry store calls omit `pushTitle` and `pushBody`.
- Legacy payloads containing those fields do not crash retry.
- Focused tests pass or a real blocker is recorded with evidence.

## Scope Guard

- Do not implement Android decrypt handling, iOS NSE work, fixture generation,
  telemetry gates, simulator smoke, or cleanup in this session.
