# Session 4 Plan: Contact lifecycle and relay-race journey coverage

## Real scope

- Close the Session 4 coverage gaps for `13.1`, `13.2`, `13.3`, `13.4`,
  `14.6`, `14.7`, and `14.9` from
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`.
- Keep the work on contact lifecycle truth only: block/unblock, archive,
  delete/re-add, delete-vs-delivery races, offline queued-message acceptance,
  and same-relay dual-thread isolation.
- Do not widen into generic 1:1 ordering work, intro matrix refresh, group
  behavior, or transport failover design.

## Closure bar

Session 4 is good enough when the repo has direct automated evidence that:

- a blocked contact is suppressed, then after unblock a new message from that
  same peer becomes visible again on the real conversation/orbit seam,
- an archived contact can still refresh truthful last-activity state without
  leaking back into the active friend set,
- deleting a contact while outbound or inbound delivery is still racing does
  not resurrect stale visible history or leave related local state behind,
- deleting and later re-adding the same contact starts from a clean history
  instead of reviving the deleted thread,
- accepting a contact request while an offline message is queued results in one
  accepted contact and one honest delivered conversation state after inbox
  replay, and
- two concurrent conversations sharing the same fake relay path stay isolated
  per recipient instead of cross-contaminating message delivery or thread
  state.

The session may finish as test-only if current production behavior is already
correct and the missing gap is only combined direct proof.

## Source of truth

- Active controller doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md`
- Proposal/source doc:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-todo.md`
- Coverage matrix and gap statements:
  `Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md`
- Regression policy:
  `Test-Flight-Improv/14-regression-test-strategy.md`
- Gate source of truth:
  `Test-Flight-Improv/test-gate-definitions.md`

When docs disagree with live repo evidence, repo evidence wins.

## Session classification

`implementation-ready`

## Exact problem statement

The current repo already covers important pieces of this surface, but the
remaining Session 4 story is still split across seams:

- `test/features/contacts/application/block_contact_use_case_test.dart` and
  `test/features/contacts/application/unblock_contact_use_case_test.dart`
  prove the use-case calls only; they do not prove the blocked-then-unblocked
  message visibility journey.
- `test/features/conversation/application/chat_message_listener_test.dart`
  already proves blocked senders are suppressed and archived senders persist
  without UI emission, which is strong lower-level evidence for `13.1` and
  `13.2`, but it does not prove the later Orbit-visible recovery path.
- `test/features/contacts/application/delete_contact_use_case_test.dart`
  already proves delete ordering and related-state cleanup across visible,
  failed, unacked, and sending message buckets, but it does not prove a live
  delivery race or re-add-after-delete conversation truth.
- `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  proves single-friend refresh and archived hydration behavior, but not the
  archived-contact thread refresh ask from `13.2`.
- `test/features/contact_request/integration/contact_request_flow_test.dart`
  now proves mutual-scan race and offline bootstrap replay, while
  `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  proves queued-message replay; the remaining gap is the combined
  accept-while-message-queued journey from `14.7`.
- `integration_test/wifi_transport_test.dart` and
  `integration_test/transport_e2e_test.dart` already prove adjacent
  concurrency/relay behavior, but they do not explicitly prove one sender
  racing two same-relay 1:1 conversations as requested by `14.9`.

The goal is to add only the minimum direct proof still missing after this
current-repo refresh.

## Files and repos to inspect next

Production files:

- `lib/features/contacts/application/delete_contact_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/orbit/application/load_orbit_data_use_case.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/contact_request/application/accept_contact_request_use_case.dart`
- `lib/features/contact_request/application/accept_and_reciprocate_use_case.dart`

Primary direct tests:

- `test/features/contacts/application/delete_contact_use_case_test.dart`
- `test/features/contacts/application/block_contact_use_case_test.dart`
- `test/features/contacts/application/unblock_contact_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/orbit/presentation/screens/orbit_wired_test.dart`
- `test/features/contact_request/integration/contact_request_flow_test.dart`
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/features/conversation/integration/two_user_message_exchange_test.dart`

Likely new narrow integration file only if existing suites become too contorted:

- `test/features/conversation/integration/contact_lifecycle_race_test.dart`

Conditional transport proof only if deterministic current seams are still
insufficient:

- `integration_test/transport_e2e_test.dart`
- `integration_test/wifi_transport_test.dart`

## Existing tests covering this area

- `test/features/conversation/application/chat_message_listener_test.dart`
  already proves blocked contacts are rejected and archived contacts are
  persisted without UI emission.
- `test/features/contacts/application/delete_contact_use_case_test.dart`
  already proves delete cleanup order and related-state purging.
- `test/features/orbit/application/load_orbit_data_use_case_test.dart` and
  `test/features/orbit/presentation/screens/orbit_wired_test.dart` already
  prove active-vs-archived filtering and single-row refresh behavior.
- `test/features/contact_request/integration/contact_request_flow_test.dart`
  already proves accept/decline, mutual race, and offline bootstrap replay.
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  already proves queued inbox replay after reconnect.
- `integration_test/wifi_transport_test.dart` already proves concurrent sends
  on one pooled connection, and `integration_test/transport_e2e_test.dart`
  already proves adjacent relay-path behavior.

## Regression/tests to add first

- Extend `test/features/orbit/presentation/screens/orbit_wired_test.dart`
  with the smallest archived-contact refresh proof: an archived friend receives
  a later message, the archived row updates truthfully, and the contact does
  not leak back into the active list.
- Add one deterministic cross-feature lifecycle integration, preferably in
  `test/features/conversation/integration/contact_lifecycle_race_test.dart`,
  covering the combined journeys that current unit/widget seams do not prove:
  blocked-then-unblocked visibility, delete-during-flight or inbound-arrival
  race, clean re-add after delete, queued offline message plus later contact
  acceptance, and same-relay A->B plus A->C isolation.
- Reuse the existing contact-request and offline-inbox helpers rather than
  inventing a new multi-simulator harness.
- Only touch production code if deterministic direct proof reveals a real
  contract hole; prefer test-only additions first.

## Step-by-step implementation plan

1. Re-read Session 4 rows in the coverage audit and the current worktree
   versions of the eight primary test files above.
2. Reclassify which parts of `13.1`-`14.9` are already closed by current repo
   evidence before adding anything new.
3. Prefer widget/screen proof first in `orbit_wired_test.dart` for the
   archived-contact refresh path.
4. Build one narrow deterministic lifecycle-race integration harness by
   reusing `two_user_message_exchange_test.dart` / `offline_inbox_roundtrip_test.dart`
   helpers instead of modifying device-backed transport tests first.
5. Add only the missing combined journey cases:
   blocked-then-unblocked visibility, delete-vs-delivery race,
   delete-then-readd clean slate, accept-while-offline-message-queued, and
   same-relay dual-recipient isolation.
6. If one of those cases exposes a real production gap, make the smallest fix
   in the responsible lifecycle or listener seam.
7. Run the exact direct Session 4 suites.
8. Run `./scripts/run_test_gates.sh 1to1` only if accepted changes touch shared
   message-listener or conversation-delivery code.
9. Run `./scripts/run_test_gates.sh transport` only if accepted execution
   changes `integration_test/transport_e2e_test.dart`,
   `integration_test/wifi_transport_test.dart`, or real transport-backed
   production seams.
10. Run `./scripts/run_test_gates.sh baseline` only if execution touches shared
    startup, app-root, or notification wiring.

## Risks and edge cases

- A delete-contact test can accidentally prove repository cleanup only, not the
  live race where delivery arrives during deletion.
- The archived-contact proof can regress into a generic archived hydration test
  unless it asserts a real incoming refresh path and active-list exclusion.
- The accept-while-queued case can become dishonest if the message is delivered
  before the contact acceptance step instead of through the intended queued
  replay order.
- The same-relay race can become too generic if both recipients are not
  asserted independently for isolation and ordering.
- The dirty worktree already contains unrelated conversation and orbit edits;
  execution must work with them instead of overwriting them.

## Exact tests and gates to run

Direct suites required for Session 4:

```bash
flutter test test/features/contacts/application/delete_contact_use_case_test.dart
flutter test test/features/contacts/application/block_contact_use_case_test.dart
flutter test test/features/contacts/application/unblock_contact_use_case_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/features/contact_request/integration/contact_request_flow_test.dart
flutter test test/features/conversation/integration/offline_inbox_roundtrip_test.dart
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart
```

If execution adds the planned narrow lifecycle integration file, run it too:

```bash
flutter test test/features/conversation/integration/contact_lifecycle_race_test.dart
```

Conditional named gates:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh baseline
```

Run `1to1` only if execution touches shared 1:1 delivery or listener code.
Run `transport` only if accepted work touches transport-backed integration
files or real transport production seams. Run `baseline` only if execution
touches shared startup, app-root, or notification behavior.

## Known-failure interpretation

- Treat unrelated dirty-worktree failures as historical noise unless one of the
  exact Session 4 direct suites or a required named gate fails.
- Existing relay/device limitations in `integration_test` are not a Session 4
  blocker unless deterministic direct seams prove insufficient.

## Done criteria

- Session 4 has direct proof or honest current-repo reclassification for
  `13.1`, `13.2`, `13.3`, `13.4`, `14.6`, `14.7`, and `14.9`.
- The exact direct suites are green.
- Any required conditional gate is green.
- No intro-matrix, posts, group, or transport-redesign scope was pulled in.
- The breakdown ledger is updated with the accepted outcome and exact evidence.

## Scope guard

- No generic text-ordering or unread-thread work.
- No posts, groups, or broader intro-matrix coverage.
- No device-orchestrator or multi-simulator harness work unless deterministic
  direct seams are proven insufficient.
- No gate-definition edits unless an accepted new direct suite truly needs
  permanent classification.

## Accepted differences / intentionally out of scope

- Session 4 does not need to prove every contact-management UI gesture; it
  only needs the missing lifecycle journeys from the audit rows above.
- Session 4 does not need to move relay coverage into real device tests if a
  deterministic fake-relay integration proves the same isolation contract
  honestly.
- Session 4 does not own the final matrix refresh; Session `10` still does.

## Dependency impact

- Session `4` remains independent of Sessions `1`-`3`, but if accepted changes
  touch shared conversation listener code then later Session `7` should be
  refreshed against the new behavior before execution.
