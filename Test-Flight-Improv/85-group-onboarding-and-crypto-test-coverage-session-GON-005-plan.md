# GON-005 Plan: Real-Crypto First-Add And Re-Add Onboarding Decrypt Proof

## real scope

- Add a macOS/device integration test using `GoBridgeClient` real bridge crypto.
- Prove Bob receives the group key through the app's encrypted group-invite acceptance path before decrypting a group ciphertext.
- Prove re-add after rotation uses the current epoch: Bob decrypts the new epoch after re-invite and his retained old key cannot decrypt that ciphertext.

## closure bar

- `TC-13` has automated real-bridge evidence with no pre-saved Bob group key.
- `TC-26` has automated real-bridge evidence for remove/rotate/re-add, current-epoch decrypt, and retained-old-key failure.
- The test is clearly classified as fixture/device-backed evidence, not part of the frozen host-side `groups` gate.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-005`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-13 and TC-26.
- Existing bridge reference: `integration_test/benchmark_encryption_harness.dart` and `lib/core/bridge/bridge_group_helpers.dart`.

## session classification

`implementation-ready`

## exact problem statement

The repo has ML-KEM and group AES-GCM primitive tests, plus fake/passthrough invite tests, but it does not connect those pieces into one app-boundary proof where Bob accepts an encrypted group invite through the production handler and then decrypts a group ciphertext with the accepted key.

## files and repos to inspect next

- `lib/core/bridge/go_bridge_client.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/create_group_with_members_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `integration_test/benchmark_encryption_harness.dart`

## existing tests covering this area

- `integration_test/benchmark_encryption_harness.dart` proves Go bridge ML-KEM and group encrypt/decrypt primitives.
- `invite_round_trip_test.dart` proves app invite acceptance with passthrough crypto.
- `group_membership_smoke_test.dart` proves fake-network re-add/current-epoch behavior.

## regression/tests to add first

- Add `integration_test/group_real_crypto_onboarding_test.dart` with one end-to-end real-bridge test covering both TC-13 and TC-26.

## step-by-step implementation plan

1. Generate Alice identity, Alice ML-KEM keys, Bob identity, and Bob ML-KEM keys through `GoBridgeClient`.
2. Create a group with Bob through `createGroupWithMembers`; capture the encrypted invite from `FakeP2PService`.
3. Handle Bob's invite through `handleIncomingGroupInvite` with Bob's real ML-KEM secret key.
4. Encrypt a group payload using Alice's latest group key and decrypt it with Bob's accepted key.
5. Simulate Bob removal, generate the next real group key, re-send an encrypted invite, and accept it after clearing Bob's removed group state.
6. Encrypt an epoch-2 payload and assert Bob decrypts it with the accepted new key while the retained old key fails.
7. Run the integration test on macOS and update docs/gates.

## risks and edge cases

- This is real bridge crypto and app invite materialization, but it is not a full two-node GossipSub delivery test.
- `group:publish` inside `createGroupWithMembers` may have no live peers; the test must assert the invite/key/decrypt path, not topic fan-out.
- macOS/device integration tests are slower and should be classified outside the host-side `groups` gate.

## exact tests and gates to run

- `flutter test integration_test/group_real_crypto_onboarding_test.dart -d macos`

## known-failure interpretation

- If the macOS bridge is unavailable, the session is fixture-blocked and cannot truthfully close TC-13/TC-26.
- If invite decryption fails, TC-13 remains open.
- If old-key decrypt succeeds after rotation, TC-26 exposes a real security regression.

## done criteria

- The new macOS integration test passes.
- Source doc marks TC-13 and TC-26 as covered by real-bridge app-boundary evidence while preserving the separate full two-node real-network residual.
- Breakdown ledger and gate definitions record the test truthfully.

## scope guard

- Do not build a new two-node simulator orchestrator in this session.
- Do not claim this satisfies TC-17, TC-18, TC-20, or recurring gate sufficiency.

## accepted differences / intentionally out of scope

- This is a fixture-light real-bridge crypto integration test, not live GossipSub delivery.

## dependency impact

- Later real-network sessions can use this as the crypto acceptance baseline but still own live receiver-visible delivery.
