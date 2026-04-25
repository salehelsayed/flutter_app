# Report 75 Session 1 Plan - Relay APNs Audible Message Push Contract

## Final verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-24`
- Execution mode:
  `local bounded fallback after fresh child materialization failed because codex could not access /Users/I560101/.codex/sessions`
- Why:
  - `go-relay-server/inbox.go` now sets the explicit APNs sound contract on
    both the top-level 1:1 alert branch and the shared ciphertext-only message
    APNs builder used by encrypted 1:1 and group message pushes.
  - `go-relay-server/inbox_test.go` now pins that sound contract in the three
    existing message payload-shape tests without weakening the privacy,
    route-data, `content-available`, `mutable-content`, or Android data-only
    assertions those seams already carried.
  - The focused relay regression command and full `go test ./...` pass when run
    with `GOCACHE=/tmp/go-build-report75` inside the sandbox.

## real scope

- Add the explicit APNs audible background contract for user-visible 1:1 and group message pushes in `go-relay-server/inbox.go`.
- Add deterministic relay tests in `go-relay-server/inbox_test.go` that pin the APNs sound field for:
  - legacy/plaintext-envelope 1:1 message pushes that already fall back to ciphertext-only push shaping
  - encrypted 1:1 message pushes
  - encrypted group message pushes
- Keep the change limited to message push families handled by `buildPushMessage(...)` and `buildCiphertextOnlyPushMessage(...)`.

Out of scope for this session:

- intros, contact requests, and group invites
- Flutter local notification behavior, foreground presentation, or notification tap routing
- iOS simulator or device audio proof

## closure bar

Session 1 is good enough only when relay-built APNs payloads for message notifications include an explicit sound value, and all touched relay tests still prove that privacy, route data, APNs alert headers, `content-available`, `mutable-content`, and Android data-only behavior remain unchanged.

## source of truth

- Active session contract: `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- Proposal context: `Test-Flight-Improv/75-ios-background-push-sound.md`
- Gate source of truth: `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win on disagreement:
  - `go-relay-server/inbox.go`
  - `go-relay-server/inbox_test.go`

## session classification

`implementation-ready`

## exact problem statement

Relay-built APNs message notification payloads currently emit visible alerts without an explicit APNs `sound` contract. That leaves iOS background message pushes able to appear silently even though Android remains high priority and the Flutter local fallback path is configured to play sound. This session fixes only the relay-side APNs message payload shape and must not reintroduce plaintext preview leakage or alter non-message push families.

## files and repos to inspect next

- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `Test-Flight-Improv/75-ios-background-push-sound-session-breakdown.md`
- `Test-Flight-Improv/75-ios-background-push-sound.md`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `TestBuildChatPushMessage_LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData`
  already proves no top-level FCM notification payload, data-only Android behavior, APNs fallback alert presence, and no sender/body leakage.
- `TestBuildChatPushMessage_CarriesEncryptedDataWithoutPlaintextPreview`
  already proves APNs alert headers, `content-available`, `mutable-content`, encrypted data carriage, and no plaintext leakage for encrypted 1:1 pushes.
- `TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview`
  already proves the equivalent encrypted group push privacy and APNs shape.

Missing coverage:

- no current test asserts an explicit APNs sound field for any relay-built message push

## regression/tests to add first

- Extend the three existing relay payload-shape tests above to assert the APNs sound field after the smallest production change lands.
- Do not add a new higher-level smoke or Flutter test in this session; the relay seam already has exact direct tests in `go-relay-server/inbox_test.go`.

## step-by-step implementation plan

1. Add a single relay-local constant for the message APNs sound value if that keeps the payload contract explicit without widening scope.
2. Set that sound value on the APNs `Aps` payload built by `buildCiphertextOnlyPushMessage(...)` so both encrypted 1:1 and group message pushes inherit it.
3. Set the same sound value on the APNs `Aps` payload built by the top-level alert branch in `buildPushMessage(...)` so non-ciphertext user-visible 1:1 message pushes also remain audible.
4. Extend the existing message relay tests to assert the APNs sound value while preserving all prior privacy and payload-shape assertions.
5. Run focused relay tests for the touched message push builders.
6. Run `go test ./...` from `go-relay-server` as the session-wide direct verification.

Stop if repo evidence shows the APNs sound field is already present for message pushes; in that case convert the session to acceptance-only rather than changing production code.

## risks and edge cases

- A helper-level change could accidentally affect non-message notification families; keep the sound write scoped to message builders only.
- Adding sound must not remove or alter `mutable-content`, which the iOS Notification Service Extension depends on for preview rewrite.
- Encrypted/ciphertext-only pushes must stay data-only on Android.
- The APNs fallback alert must stay privacy-preserving; no sender name, group name, or plaintext body may leak into the ciphertext-only contract.

## exact tests and gates to run

Direct tests:

- `cd go-relay-server && go test ./... -run 'TestBuildChatPushMessage_(LegacyPlaintextEnvelopeEmitsOnlyFallbackAndRouteData|CarriesEncryptedDataWithoutPlaintextPreview)|TestBuildGroupPushMessage_CarriesEncryptedDataWithoutPlaintextPreview'`
- `cd go-relay-server && go test ./...`

Named gates:

- none for this session

## known-failure interpretation

- Treat any failure in the touched relay tests or `go test ./...` as a blocking regression for this session.
- There is no documented known-red exception for this relay push-shape seam in the session sources.

## done criteria

- `go-relay-server/inbox.go` sets an explicit APNs sound value for user-visible 1:1 and group message pushes.
- The three message payload-shape tests in `go-relay-server/inbox_test.go` assert that sound contract.
- Focused relay tests pass.
- `cd go-relay-server && go test ./...` passes.
- No non-message push family behavior is changed.

## scope guard

- Do not alter Flutter notification code, iOS app project files, or smoke harnesses in this session.
- Do not redesign the relay push schema or rename existing data keys.
- Do not widen sound behavior to intros, contact requests, or group invites unless current code proves they already share the exact message helper and cannot be isolated safely.

## accepted differences / intentionally out of scope

- Manual iOS audible proof remains for later acceptance work; Session 1 only proves the deterministic relay payload contract.
- Foreground quiet behavior (`sound: false`) and local fallback duplicate suppression remain owned by later sessions.

## dependency impact

- Session 2 depends on this session only as the relay-side background sound contract input; if Session 1 stays blocked, Session 2 may still inspect Flutter proof but Session 3 cannot honestly claim final closure.
- Session 3 should reuse this session's exact relay test evidence rather than restating the payload logic from prose.
