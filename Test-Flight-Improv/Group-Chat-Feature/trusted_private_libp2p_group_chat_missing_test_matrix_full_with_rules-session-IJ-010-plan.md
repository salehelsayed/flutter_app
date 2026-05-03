# IJ-010 Session Plan - Concurrent Joins Converge Membership And Epoch State

Status: execution-accepted

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T04:35:56+02:00 | Evidence Collector started | `implementation-plan-orchestrator/SKILL.md`; `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`; `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`; `test-inventory.md`; `invite_round_trip_test.dart`; `git status --short` | IJ-010 source row confirmed `Open`/`needs_repo_evidence`/`evidence-gated`; target plan file was absent; dirty worktree is unrelated existing work and must be preserved. | Collect direct code/test evidence around concurrent invite accepts, membership convergence, key epoch/material convergence, and current gaps. |
| 2026-05-01T04:38:31+02:00 | Evidence Collector completed; Planner started | `accept_pending_group_invite_use_case.dart`; `handle_incoming_group_invite_use_case.dart`; `send_group_invite_use_case.dart`; `group_message_listener.dart`; `GroupTestUser`; `FakeGroupPubSubNetwork`; `group_membership_smoke_test.dart`; `invite_round_trip_test.dart`; `scripts/run_test_gates.sh` | Existing `invite_round_trip_test.dart` proves two local pending accepts converge each receiver's membership/key/sendability, but it is not fake-network or existing-member convergence proof. No production gap is proven yet. | Plan fake-network 3+ peer proof first; patch only if the proof exposes a concrete race/convergence failure. |
| 2026-05-01T04:38:31+02:00 | Planner completed; Reviewer started | Drafted scope, closure bar, tests, gate contract, and non-goals | Plan stays row-owned: concurrent direct invite accepts, full member snapshot convergence, key epoch/material convergence, no unintended identities, post-join sendability. | Review for overclaiming against IJ-011, IJ-013, EK-004, and real device fixtures. |
| 2026-05-01T04:38:31+02:00 | Reviewer completed; Arbiter started | Source row required layers, fake-network harness, current real-network gate definition, prior IJ-009 closure caveats | Sufficient with one adjustment: the row may close on host fake-network plus focused invite gates only if the source row explicitly records real-device nightly as supporting/unconfigured, not claimed. | Finalize execution-ready plan and accepted differences. |
| 2026-05-01T04:38:31+02:00 | Arbiter completed | Final plan sections below | No structural blocker. IJ-010 remains evidence-gated but execution-ready: add fake-network proof first, then production fixes only for observed failures. | Execute the RED/proof-first test and required gates. |

## real scope

Close IJ-010 for trusted-private direct invites by proving concurrent invite acceptance converges:

- the same trusted member set and roles across an existing member and both joiners
- the same current group key epoch and material across participants
- no unintended identity admission
- sendability after both joiners are admitted
- pending invite cleanup and single-use consumption for both accepts

The session may add focused fake-network/integration proof and patch only row-owned accept/materialization or membership/key convergence code if that proof exposes a real failure.

Do not implement public/open join, join requests, history entitlement, device registry semantics, broad event-family signature parity, or relay/device infrastructure.

## closure bar

IJ-010 may move to `Covered` only when:

- a focused test proves two distinct signed direct invites are accepted concurrently from separate recipients
- the proof includes an existing third participant on the fake group network, not just isolated receiver repos
- all trusted participants converge on exactly the intended peer ids and roles
- all joined participants converge on the expected key epoch and encrypted key material
- both new members can send after convergence and existing members receive those sends
- no non-invited identity is present in membership, key state, pending invites, fake-network subscription, or received messages
- predecessor invite protections from IJ-001/IJ-002/IJ-003/IJ-005/IJ-009 remain green
- the source matrix, `test-inventory.md`, and this breakdown record concrete file, test, command, and caveat evidence

## source of truth

- Source row IJ-010 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`.
- Row 10 in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`.
- Current inventory row `IJ-010` in `test-inventory.md`.
- Current behavior in `accept_pending_group_invite_use_case.dart`, `handle_incoming_group_invite_use_case.dart`, `send_group_invite_use_case.dart`, `group_message_listener.dart`, `GroupTestUser`, and `FakeGroupPubSubNetwork`.
- `scripts/run_test_gates.sh groups` and `group-real-network-nightly` definitions.

Current code and tests beat stale broad prose. The local `group-real-network-nightly` gate requires `FLUTTER_DEVICE_ID`; it is supporting evidence unless configured fixtures are available and the test actually runs.

## session classification

`evidence-gated`

The row is execution-ready because the repo already has a fake-network multi-user harness capable of proving the missing evidence. It is not stale/already-covered because the existing `invite_round_trip_test.dart` concurrent pending-accept test is host-only and does not prove fake-network participant convergence or existing-member receipt after simultaneous joins.

## exact problem statement

Trusted-private groups can invite two users at nearly the same time. The current inventory proves isolated concurrent pending accepts, but not the user-visible multi-peer case where an existing member and both joiners converge on the same trusted membership and epoch state and can exchange messages after admission. IJ-010 must close that evidence gap without weakening signed invite, reuse, revocation, or local identity binding behavior.

## files and repos to inspect next

Production candidates, only if the proof fails:

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `lib/features/groups/application/send_group_invite_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`

Primary test files:

- `test/features/groups/integration/invite_round_trip_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`
- focused invite application tests if production changes are needed

## existing tests covering this area

- `invite_round_trip_test.dart` includes `concurrent pending accepts converge members, key epoch, and sendability`, proving two separate pending invite accepts can converge each receiver repo on the same member set, roles, latest key, pending cleanup, consumed invite tombstones, and local sendability.
- `send_group_invite_use_case_test.dart` proves `sendGroupInvitesInParallel` sends multiple signed/encrypted direct invites concurrently.
- `create_group_with_members_use_case_test.dart` proves selected-member-only `members_added` config and invite fanout.
- `group_membership_smoke_test.dart`, `group_messaging_smoke_test.dart`, and `group_resume_recovery_test.dart` provide fake-network multi-user delivery and membership convergence harnesses.

Missing before IJ-010 execution:

- a fake-network proof where an existing member plus both concurrent joiners converge and receive post-join messages
- explicit negative assertion that an uninvited identity is not admitted or subscribed
- closure docs for the IJ-010 source row

## regression/tests to add first

Add a focused proof test, preferably in `test/features/groups/integration/group_membership_smoke_test.dart`, with a name containing `IJ010`, such as:

`IJ010 concurrent direct invite accepts converge membership epoch and delivery`

The test should:

1. Build a fake-network group with admin and one existing member.
2. Seed two pending signed direct invites for Charlie and Dave whose group config contains exactly admin, existing member, Charlie, and Dave with stable roles and the same key epoch/material.
3. Accept Charlie and Dave concurrently with `Future.wait`.
4. Subscribe the joiners to the fake network only after their bridge `group:join` commands are observed, matching current fake-network patterns.
5. Verify admin/existing/joiner repositories converge on the exact peer set and roles, latest key epoch/material, no pending invite, and consumed invite tombstones.
6. Send messages from Charlie and Dave after convergence and verify the existing member receives both while an uninvited Eve has no group, key, subscription, or messages.

If this proof fails, patch only the row-owned failure and keep the test as RED evidence. If it passes without production edits, close IJ-010 as evidence-only with concrete commands.

## step-by-step implementation plan

1. Add the IJ-010 fake-network proof test.
2. Run the focused proof command:
   `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010'`
3. If the proof fails because repository state, membership snapshots, keys, or join subscription do not converge, patch the smallest owner file that caused that failure.
4. If production changes are required, add or update the matching direct unit/application tests for the changed function.
5. Run preservation checks for invite acceptance and invite wildcard.
6. Run the groups gate and diff hygiene.
7. Attempt `group-real-network-nightly` only if the required local fixture env is available; otherwise record it as unconfigured supporting evidence.
8. Close IJ-010 in the source matrix, inventory, and breakdown only after the proof and required gates pass.

## risks and edge cases

- A fake-network test can accidentally prove only local repository setup. It must include an existing member receiving post-join messages from both joiners.
- The test must not admit a non-invited peer by pre-seeding Eve into the group config, repository, or fake network subscription.
- Do not treat `member_joined` timeline rows as membership convergence; membership convergence must be checked from `GroupRepository.getMembers`.
- Do not use transport `message.to` as local identity; IJ-009 requires persisted/local peer identity.
- If `group-real-network-nightly` is unconfigured, that is not a production failure, but the closure must say it was not real-device proof.

## exact tests and gates to run

Focused proof:

```sh
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010'
```

Preservation and gates:

```sh
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'concurrent pending accepts converge members, key epoch, and sendability'
flutter test --no-pub test/features/groups/application/*invite*_test.dart
flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart
flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart
./scripts/run_test_gates.sh groups
git diff --check
```

Supporting only when configured:

```sh
FLUTTER_DEVICE_ID=<device> MKNOON_RELAY_ADDRESSES=<relays> ./scripts/run_test_gates.sh group-real-network-nightly
```

## known-failure interpretation

- `group-real-network-nightly` failing immediately with missing `FLUTTER_DEVICE_ID` is an unconfigured fixture, not an IJ-010 regression.
- Existing broad Go peer-mismatch failures from earlier sessions are unrelated unless IJ-010 changes Go/libp2p code, which this plan does not intend.
- Any failure in the new IJ-010 proof, the existing concurrent pending-accept test, invite wildcard, or `groups` gate is blocking for IJ-010.

## done criteria

- IJ-010 proof test exists and either passes against current production or records a clear RED signature before a row-owned fix.
- Existing concurrent pending-accept test remains green.
- Invite predecessor protections remain green.
- `./scripts/run_test_gates.sh groups` and `git diff --check` pass.
- Source matrix row IJ-010, `test-inventory.md`, and the session breakdown record `Covered` with concrete evidence and caveats.

## scope guard

Do not implement:

- public rooms or open auto-join
- join request moderation
- account-wide or device-specific invite binding beyond current peer-id binding
- IJ-011 history entitlement
- IJ-013 richer device registry
- EK-004 broad signature parity
- new relay/device infrastructure
- new production membership semantics unless the focused proof fails

Do not close TP-SMOKE-01 as a source row; it remains a supporting scenario.

## accepted differences / intentionally out of scope

- Host fake-network evidence is acceptable for IJ-010 if it proves multi-user delivery and convergence inside the repo harness; true device/relay nightly remains supporting unless configured.
- The row does not require pinned items, custom history policy, device sibling admission, or event-family signature parity.
- Current direct invites carry an authoritative group config snapshot; the proof may rely on that snapshot as long as it verifies no unintended identity is admitted.

## dependency impact

- IJ-011 may build on IJ-010's converged member/key state but still owns authorized state/history entitlement.
- IJ-013 may build on IJ-010 and IJ-009 but still owns wrong identity/device coverage.
- RP, MS, and EK rows must not be treated as closed by IJ-010 unless their own row evidence lands later.

## execution and closure evidence

Status: `execution-accepted`

IJ-010 closed as evidence-plus-test. No production code changed.

Implemented proof:

- `test/features/groups/integration/group_membership_smoke_test.dart` adds `IJ010 concurrent direct invite accepts converge membership epoch and delivery`.
- The proof builds an admin plus existing member fake-network group, publishes a batch `members_added` authoritative config to the existing member, accepts two signed direct pending invites for Charlie and Dave concurrently with `Future.wait`, manually subscribes joiners only after successful `group:join`, and verifies exact member/role convergence, key epoch/material convergence, consumed invite tombstones, no uninvited Eve group/key/subscription/messages, and post-join delivery from both joiners to the existing member, admin, and each other where applicable.

Passed verification:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'IJ010'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart --plain-name 'concurrent pending accepts converge members, key epoch, and sendability'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/*invite*_test.dart` passed (`+100`).
- `flutter test --no-pub test/features/groups/integration/invite_round_trip_test.dart` passed (`+14`).
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart` passed (`+6`).
- `./scripts/run_test_gates.sh groups` passed (`+97`).
- `git diff --check` passed.

Supporting `group-real-network-nightly` was not run because `FLUTTER_DEVICE_ID` and `MKNOON_RELAY_ADDRESSES` are unset. This is non-blocking for IJ-010 because the row closure is host fake-network repo proof, not device-lab relay proof.

Closure caveat:

- IJ-010 closes concurrent trusted direct invite accept convergence for membership, roles, epoch/key material, pending cleanup, and post-join delivery. It does not close IJ-011 history entitlement, IJ-013 richer account/device binding, EK-004 broad event signatures, RP conflict semantics, or any first-class real relay/device nightly behavior.
