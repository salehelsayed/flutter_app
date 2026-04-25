# 73 - Session 3 Plan: Shared Push Fixture And Security Foundation

## Scope

Create the shared fixture and invariant layer needed before platform decrypt
handlers are implemented:

- add committed push decrypt fixture payloads for 1:1 and group message shapes
- add frozen rollout payload examples for post-Phase-1 ciphertext-only and
  legacy pre-Phase-1 compatibility states
- extend notification route tests so ciphertext-shaped data still routes
  correctly
- add Go and Dart forbidden-field classifier tests that scan relay/message push
  surfaces for preview-derived canaries
- classify the new security test directory in the gate script and gate docs

## Code Entry Points

- `test/features/push/fixtures/`
- `test/features/push/frozen_payloads/`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_contract_matrix_test.dart`
- `test/security/forbidden_field_classifier_test.dart`
- `go-relay-server/forbidden_field_classifier_test.go`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## Tests And Gates

Focused verification:

- `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_route_contract_matrix_test.dart test/security/forbidden_field_classifier_test.dart`
- `go test ./...` from `go-relay-server`
- `./scripts/run_test_gates.sh completeness-check`

## Done Criteria

- Ciphertext-shaped route data resolves to the same notification targets as the
  existing routes.
- Dart and Go classifier tests fail if plaintext preview canaries appear in
  push-visible message surfaces.
- New tests are classified by the gate script.

## Scope Guard

- Do not implement platform decrypt/render handlers in this session.
- Do not add iOS NSE targets or telemetry gates in this session.
