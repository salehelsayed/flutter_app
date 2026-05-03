# ER-005 Session Plan - Safe error messages never expose secrets or sensitive peer data

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:49:00+02:00 | Local planner completed | ER-005 source matrix row; ordered-session ER-005 row; `flow_event_emitter.dart`; `go_bridge_client.dart`; `bridge.dart`; bridge and flow-event tests | Current repo has a central path for flow logs, bridge errors, and group diagnostics. The row-owned fix should sanitize those central outputs rather than chasing every caller. | Add shared redaction for flow/diagnostic details and sanitize GoBridge returned error messages, then run focused tests. |

## real scope

ER-005 asks for error and diagnostic surfaces across group invite/sync/media/key/discovery/bridge paths to avoid exposing keys, raw encrypted blobs, internal dumps, or sensitive multiaddrs. This session scopes the implementation to the shared bridge/flow-event surfaces used by those paths:

- flow event details and debug `[FLOW]` logs
- group diagnostic event stream payloads
- native bridge `PlatformException` and unexpected exception error messages returned through `GoBridgeClient.send`

## closure bar

ER-005 can be resolved only when focused tests prove:

- sensitive detail keys such as private keys, secret keys, ciphertexts, plaintexts, nonces, signatures, and raw multiaddrs are redacted from flow event payloads and logs
- group diagnostic stream payloads are sanitized before Flutter listeners receive them
- platform bridge errors returned to callers and emitted to flow logs redact secret-bearing message text
- existing non-sensitive bridge error behavior remains intact

## session classification

`implementation-ready`. The missing behavior is central sanitization plus direct tests.

## Device/Relay Proof Profile

- Profile for this session: host-only Flutter bridge and flow-event unit tests.
- Real-network proof is supplemental for this row because the vulnerable surfaces are local emission and error-return paths.

## files expected to change

- `lib/core/utils/flow_event_emitter.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/go_bridge_client.dart`
- `test/core/utils/flow_event_emitter_test.dart`
- `test/core/bridge/go_bridge_client_test.dart`

## exact tests and gates to run

- `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'ER005'`
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'PlatformException'`
- `git diff --check`

## scope guard

Do not rewrite every application-level message. Keep the protection at the shared emission/bridge boundary and avoid changing command payloads sent to the native bridge.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T09:59:00+02:00 | Local executor completed | `flow_event_emitter.dart`; `bridge.dart`; `go_bridge_client.dart`; focused flow-event and bridge tests | Central redaction is implemented for flow events, group diagnostics, native bridge error returns, and platform/unexpected exception flow details. | Persist ER-005 as `Covered` with focused evidence. |

## Final Execution Verdict

Accepted on 2026-05-01. ER-005 is covered for the shared bridge/diagnostics surfaces: sensitive keys, raw encrypted blobs, long peer IDs, and multiaddrs are redacted before flow-event sinks/logs, group diagnostic listeners, and GoBridge error responses. The session does not claim every app-specific snackbar string was rewritten; it closes the row-owned central emission and bridge-error boundary with direct tests.
