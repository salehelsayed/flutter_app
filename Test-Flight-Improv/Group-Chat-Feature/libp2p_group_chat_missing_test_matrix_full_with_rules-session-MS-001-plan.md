# MS-001 Session Plan - Message ID Collision Handling

## Final Verdict

- Session id: `MS-001`
- Source row: `Message ID collision handling under rapid, offline, and multi-device sends`
- Current source status: `Partial`
- Session classification: `code-and-tests-required`
- Planned final row truth: `Covered` if the implementation rejects or resolves outgoing message-id collisions and the direct collision, replay, offline, and fake-network gates pass.

The breakdown originally marks this row `needs_tests_only`, but current repo behavior has an implementation gap: `sendGroupMessage` pre-persists by `id`, and both the in-memory repository and SQLite helper replace an existing row for the same primary key. Existing incoming replay dedupe protects already-stored incoming rows, but outgoing forced id collisions are not protected before the pre-persist save.

## Scope

In scope:

- Add a narrow outgoing message-id collision guard in `send_group_message_use_case.dart`.
- Preserve legitimate in-place retries for existing outgoing `sending` or `failed` rows with the same group, sender, text, timestamp, and quote id.
- Treat `null` or empty outgoing ids as generated ids.
- Add tests for generated-id collision resolution, explicit duplicate-id collision resolution, trusted-row preservation, conflicting duplicate incoming replay, offline inbox replay, and fake-network simultaneous sends.
- Update only MS-001 matrix, inventory, and breakdown closure docs after gates pass.

Out of scope:

- GossipSub hash/sequence collision internals.
- UI visual proof beyond repository and fake-network assertions.
- Device-lab proof.
- Receipt semantics.
- Message ordering or causal-reference policy beyond stable message identity.

## Closure Bar

MS-001 can move to `Covered` when:

- A generated message-id collision is forced and resolved without overwriting the trusted existing outgoing row.
- A second outgoing send with an explicit duplicate id but different content resolves or rejects without overwriting the first row.
- Legitimate failed/sending in-place retry paths still reuse the original id and timestamp.
- Incoming replay with the same `messageId` and different content is ignored without overwriting trusted text, timestamp, sender, status, or media already saved.
- Offline inbox replay with a duplicate `messageId` but conflicting content does not overwrite a live-delivered row.
- Fake-network rapid/simultaneous sends retain distinct message ids and all recipients converge without lost or overwritten messages.

## Implementation Plan

1. In `lib/features/groups/application/send_group_message_use_case.dart`, add a small message-id resolver before wire and inbox payload construction.
2. The resolver should:
   - use the provided non-empty `messageId` or call a generator;
   - check `msgRepo.getMessage(candidate)`;
   - allow reuse only when the existing row is a local outgoing retry/update candidate: same group, same sender, same text, same timestamp, same quote id, and status `sending` or `failed`;
   - otherwise generate a fresh id and retry a bounded number of times;
   - emit a collision flow event and return an error if it cannot find a safe id.
3. Add an optional injectable generator to `sendGroupMessage` so tests can force a generated-id collision deterministically.
4. Add focused tests in `test/features/groups/application/send_group_message_use_case_test.dart`:
   - generated-id collision tries the colliding id first, then saves under the second generated id while preserving the trusted existing row;
   - explicit duplicate id with different content resolves without overwriting the existing row;
   - failed-message retry still reuses the original id.
5. Add or tighten focused tests in `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` and `test/features/groups/integration/group_resume_recovery_test.dart` to prove conflicting duplicate payloads do not overwrite trusted live/inbox rows.
6. If needed, add a fake-network simultaneous bridge-backed send test in `test/features/groups/integration/group_messaging_smoke_test.dart` to prove rapid multi-sender sends retain distinct ids and all recipients converge.
7. Update MS-001 in the source matrix, `test-inventory.md`, and the session breakdown closure note/ledger only after verification passes.

## Exact Tests And Gates

Direct focused gates:

```sh
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --name "message id collision"
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --name "same messageId"
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --name "same message is not duplicated if both pubsub and group inbox deliver it"
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --name "simultaneous sends"
```

Aggregate focused gate:

```sh
flutter test --no-pub \
  test/features/groups/application/send_group_message_use_case_test.dart \
  test/features/groups/application/handle_incoming_group_message_use_case_test.dart \
  test/features/groups/integration/group_resume_recovery_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart
```

Named gate:

```sh
./scripts/run_test_gates.sh groups
```

Final hygiene:

```sh
git diff --check
```

## Residual Risks

- Equal-content, equal-timestamp, same-sender duplicate ids are intentionally treated as the same outgoing send only when the existing row is still `sending` or `failed`; a true independent collision with every field identical is indistinguishable at this layer.
- Live GossipSub hash and sequence collision behavior remains broader than MS-001 and should stay under LP-013 or a transport-specific row.
- The fake-network tests are accepted for MS-001's repository and inbox convergence proof, not as live device-lab proof.
