# GON-006 Plan: Ciphertext Security, Replay Boundary, And Membership Signature Evidence

## real scope

- Map retained-old-key decrypt failure to the accepted real-bridge evidence from `GON-005`.
- Map wrong/corrupt ciphertext behavior to existing Go crypto/node decryption-failure tests.
- Pin the current replay contract as Flutter `messageId` dedupe, not nonce-cache rejection.
- Add one missing membership-system-event signature regression at the Go group-topic validator boundary.

## closure bar

- `TC-9` has real-ciphertext evidence that retained old key material cannot decrypt current-epoch ciphertext.
- `TC-10` is covered by Go/node tampered nonce/ciphertext tests and no-received-event assertions.
- `TC-11` records the explicit product replay boundary: duplicate encrypted/live+inbox delivery converges by `messageId` at Flutter persistence/notification.
- `TC-12` has membership-system-event-specific signed-envelope evidence plus existing Flutter admin-authorization evidence.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-006`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-9 through TC-12.

## session classification

`implementation-ready`

## exact problem statement

Report 85 had lower-level crypto/signature evidence, but it still described old-key decrypt, replay, and membership-system-event signature coverage as partial or missing. The safest closure is to add only the missing membership-system-event signature test and truthfully map existing old-key, tamper, and replay evidence to their exact layers.

## files and repos to inspect next

- `integration_test/group_real_crypto_onboarding_test.dart`
- `go-mknoon/crypto/group_test.go`
- `go-mknoon/node/pubsub_decryption_failure_test.go`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`

## existing tests covering this area

- `integration_test/group_real_crypto_onboarding_test.dart` proves retained old group key material cannot decrypt the re-add/current-epoch ciphertext.
- `go-mknoon/crypto/group_test.go` covers wrong key, tampered ciphertext, and tampered nonce failures.
- `go-mknoon/node/pubsub_decryption_failure_test.go` covers node-level malformed/tampered envelope failure events without `group_message:received`.
- `handle_incoming_group_message_use_case_test.dart` covers `messageId` dedupe for pubsub+inbox and duplicate replay with tampered timestamp.
- `group_message_listener_test.dart` covers live+replay duplicate notification suppression and app-layer unauthorized membership-event rejection.
- `go-mknoon/node/pubsub_test.go` covers generic bad-signature and spoofed-public-key rejection.

## regression/tests to add first

- Add a focused `go-mknoon/node/pubsub_test.go` case proving a forged signed `members_added` system event that claims the admin peer is rejected as `reject:bad_signature`.

## step-by-step implementation plan

1. Add the membership-system-event forged-signature Go validator regression.
2. Run the targeted Go node validator test.
3. Run the existing Go decryption-failure suite for corrupt ciphertext/nonce.
4. Run the Flutter incoming-message dedupe suite for replay boundary evidence.
5. Update the source doc, closure reference, and breakdown ledger with exact evidence and residuals.

## risks and edge cases

- Flutter receives already-decoded events from the Go bridge, so envelope signature rejection belongs at the Go node validator boundary.
- The current product does not maintain a nonce replay cache. Closure for TC-11 must explicitly say replay convergence is by stable `messageId`/content dedupe at the app layer.

## exact tests and gates to run

- `(cd go-mknoon && go test ./node -run 'TestGroupTopicValidator_RejectsForgedMembershipSystemEventSignature|TestGroupTopicValidator_BadSignature|TestGroupTopicValidator_SpoofedPublicKey')`
- `(cd go-mknoon && go test ./node -run 'TestHandleGroupSubscription_EmitsDecryptionFailedEvent')`
- `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart`

## known-failure interpretation

- If forged membership system events are accepted, TC-12 exposes a real envelope-auth regression.
- If corrupt ciphertext produces a received event, TC-10 exposes a real decrypt-boundary regression.
- If duplicate `messageId` replay persists or notifies twice, TC-11 exposes a replay-convergence regression.

## done criteria

- The new Go validator test passes.
- Existing targeted Go and Flutter suites pass.
- Report 85 marks TC-9 through TC-12 with exact covered layer and leaves only honest residuals.

## scope guard

- Do not add nonce-cache replay rejection unless product code already has that contract.
- Do not build simulator or relay recovery harnesses in this session.

## accepted differences / intentionally out of scope

- `TC-11` is closed as app-layer `messageId` replay convergence, not cryptographic nonce reuse rejection.
- `TC-12` uses Go envelope signature validation plus Flutter admin-authorization tests; Flutter does not re-verify Ed25519 signatures after Go emits decoded events.

## dependency impact

- Later simulator sessions can rely on this security baseline while still owning receiver-visible live-network delivery and replay ordering.
