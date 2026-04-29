# GON-007 Plan: Existing-Member Discussion Media Fan-Out

## real scope

- Add focused fake-network/app-layer coverage for existing discussion members receiving image, video, and voice messages.
- Reuse the bridge-backed send path and receiver media-download assertions already proven useful in the new-member onboarding suite.
- Do not claim simulator or live Go GossipSub media delivery closure from this host-side suite.

## closure bar

- `TC-14`, `TC-15`, and `TC-16` have one deterministic suite proving existing members receive discussion image/video/voice fan-out with intact descriptors.
- Both receiver peers persist one message per media type with intact
  descriptors; the primary receiver starts media-download work. The host-side
  multi-user harness shares the process-wide in-flight media-download cache,
  so it should not require two simultaneous bridge download calls for the same
  group/blob.
- The suite is classified outside the frozen named `groups` gate.

## source of truth

- Active session contract: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage-session-breakdown.md`, session `GON-007`.
- Product intent: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`, TC-14 through TC-16.

## session classification

`implementation-ready`

## exact problem statement

Report 85 had send-side media payload coverage and broad group text fan-out, but it did not pin the user-visible receive side for existing discussion members across image, video, and voice attachments in one deterministic app-layer test.

## files and repos to inspect next

- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`

## existing tests covering this area

- `group_messaging_smoke_test.dart` covers existing-member text fan-out.
- `group_new_member_onboarding_test.dart` covers new-member post-join media receive and download behavior.
- `media_message_journey_e2e_test.dart` remains simulator/device-context media evidence but is not a focused discussion group fake-network fan-out test.

## regression/tests to add first

- Add `test/features/groups/integration/group_media_fanout_test.dart`.

## step-by-step implementation plan

1. Create Alice, Bob, and Charlie on `FakeGroupPubSubNetwork`.
2. Create a discussion group and add both receivers before media sends.
3. Send image, video, and voice through `sendGroupMessageViaBridge`.
4. Assert Bob and Charlie each receive the three incoming rows with the sender message IDs.
5. Assert persisted media descriptors for both receivers and media-download
   attempts on the primary receiver.
6. Update gate classification and Report 85 docs.

## risks and edge cases

- This proves app-layer fake-network fan-out, not real GossipSub delivery.
- The helper writes fake downloaded files so the listener can settle deterministically.

## exact tests and gates to run

- `flutter test test/features/groups/integration/group_media_fanout_test.dart`
- `./scripts/run_test_gates.sh completeness-check`

## known-failure interpretation

- Missing receiver rows or descriptor mismatches are app-layer media fan-out regressions.
- Download count failures indicate listener/download trigger regressions.

## done criteria

- New direct suite passes.
- Source doc, gate definitions, discussion closure reference, and breakdown ledger record `TC-14` through `TC-16` truthfully.

## scope guard

- Do not broaden the frozen `groups` gate in this session.
- Do not implement simulator media matrix rows; `GON-012` owns those.

## accepted differences / intentionally out of scope

- This is host-side fake-network evidence. Live receiver-visible Go network delivery remains in later simulator sessions.

## dependency impact

- Later simulator media work can reuse this as the app-layer descriptor/download baseline.
