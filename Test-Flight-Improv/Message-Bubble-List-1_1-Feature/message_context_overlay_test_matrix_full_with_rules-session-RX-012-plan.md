# RX-012 Session Plan

## Scope

- Close row `RX-012`: reactions targeting an unknown, missing, or deleted
  message must not persist orphan `message_reactions` rows or broadcast UI
  changes.
- Keep the change bounded to the inbound reaction receive seam.

## Files

- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `lib/main.dart`
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`
- `test/features/conversation/application/reaction_listener_test.dart`
- `test/shared/fakes/test_user.dart`

## Tests

- `flutter test --no-pub test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/application/reaction_listener_test.dart`
- `flutter test --no-pub test/features/conversation/integration/emoji_reaction_exchange_test.dart`

## Gates

- No named gate required for this bounded application seam.

## Done Criteria

- Inbound reactions are ignored when the target message is missing or already
  deleted.
- No orphan reaction rows are persisted for missing/deleted targets.
- No reaction stream broadcast is emitted for ignored targets.
- Targeted tests pass.

## Scope Guard

- Do not widen into overlay UI behavior, reaction picker UX, or out-of-order
  reaction conflict resolution.
