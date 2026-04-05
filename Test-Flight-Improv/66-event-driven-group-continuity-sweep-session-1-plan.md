# Doc 66 Session 1 Plan

## Scope

- Detect an online `needsGroupRecovery` `false -> true` edge inside
  `PendingMessageRetrier`.
- Trigger immediate retrier-owned group continuity recovery from that edge.
- Keep the existing 30-second group continuity timer unchanged as fallback.
- Keep the existing 5-minute full retry timer unchanged.
- Stay behind the existing retrier guards: online-only, feature-enabled, no
  overlapping retry, no overlapping continuity sweep, and no external recovery.

## Files

- `lib/core/services/pending_message_retrier.dart`
- `test/core/services/pending_message_retrier_test.dart`

## Tests

- `flutter test test/core/services/pending_message_retrier_test.dart`

## Gates

- `./scripts/run_test_gates.sh groups`

## Done Criteria

- A same-session online `needsGroupRecovery` edge triggers immediate retrier
  recovery without waiting for the next 30-second tick.
- The existing continuity timer still fires on its original cadence after the
  immediate recovery path.
- No timer cadence or broader recovery policy changes are introduced.

## Scope Guard

- No ack contract changes in this session.
- No adaptive timer backoff.
- No Go group discovery loop changes.
- No inbox cursor optimization.
