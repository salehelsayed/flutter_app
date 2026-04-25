# 73 - Session 4 Plan: Android Data-Only Decrypt Preview

## Scope

Implement the Android/Dart decrypt-and-replace slice in a testable way:

- add a pure push preview resolver that can decrypt 1:1 and group
  ciphertext-shaped data using injected decrypt callbacks
- preserve fallback behavior when decrypt callbacks, keys, ciphertext fields,
  or plaintext parsing fail
- render sender-aware 1:1 and group preview bodies from decrypted plaintext
- cap push preview text to 140 Unicode scalar values
- keep `NotificationRouteTarget` payload routing unchanged
- wire the background handler through the resolver seam so tests and later
  runtime key/bridge wiring can replace fallback-only behavior

## Code Entry Points

- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/push/application/background_message_handler.dart`
- `test/features/push/application/push_decrypt_preview_test.dart`
- `test/features/push/application/background_message_handler_test.dart`

## Tests And Gates

Focused verification:

- `flutter test test/features/push/application/push_decrypt_preview_test.dart test/features/push/application/background_message_handler_test.dart`
- notification route/security tests touched in earlier sessions if affected

Named gates:

- Notification direct suites remain direct-file tests in this repo.

## Done Criteria

- 1:1 ciphertext data can resolve to sender title and decrypted body.
- Group ciphertext data can resolve to sender-prefixed decrypted body.
- Missing decrypt capability, bad ciphertext, unknown payloads, and missing
  keys degrade to the static fallback without throwing.
- Background handler still shows routable fallback notifications and remains
  testable through the resolver seam.

## Scope Guard

- Do not implement iOS NSE, shared iOS keychain, telemetry dashboards, or
  simulator smoke in this session.
