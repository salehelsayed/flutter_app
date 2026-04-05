# Doc 66 Session 2 Plan

## Scope

- Add a retrier-owned ack callback path for successful
  `nodeRequestedRecovery` rejoins.
- Apply that ack rule to all retrier-owned recovery entry points:
  immediate edge-triggered sweep, 30-second continuity sweep, and 5-minute
  retry/debounce sweep.
- Keep ack absent on failed rejoin attempts.
- Preserve `handleAppResumed` semantics.

## Files

- `lib/core/services/pending_message_retrier.dart`
- `lib/main.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

## Tests

- `flutter test test/core/services/pending_message_retrier_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`

## Gates

- `./scripts/run_test_gates.sh groups`

## Done Criteria

- Successful retrier-owned `nodeRequestedRecovery` rejoins send
  `group:acknowledgeRecovery`.
- Failed retrier-owned rejoins do not send `group:acknowledgeRecovery`.
- The ack rule is shared across the immediate trigger and the unchanged fallback
  retry paths.
- Existing non-retrier resume-time ack behavior remains intact.

## Scope Guard

- No changes to `handleAppResumed` behavior.
- No timer cadence changes.
- No adaptive timer backoff.
- No Go group discovery loop changes.
- No inbox cursor optimization.
