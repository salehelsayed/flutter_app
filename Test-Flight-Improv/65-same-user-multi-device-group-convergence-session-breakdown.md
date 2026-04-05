# 65 - Same-User Multi-Device Group Convergence Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
- Decomposition date:
  `2026-04-05`

## Downstream execution path

- detailed planning happens one session at a time
- later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `65` closed only when the repo owns one explicit, testable same-user
multi-device contract instead of leaving `UX-013` contract-undefined:

- one repo-owned policy names which group states converge across two devices
  that restore the same identity and which remain device-local
- the test harness can model two joined devices that share one peer identity
  without inventing duplicate group membership rows
- shared group state converges truthfully across those devices for the current
  repo-owned scope, including live message history and supported group state
  updates
- device-local state such as mute, unread, local notifications, and pending
  invite review follows one explicit non-drifting rule instead of being left
  implicit
- maintained architecture and matrix docs no longer describe `UX-013` as
  contract-undefined once the landed code, tests, and visible behavior all
  match the same rule

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`

Current repo facts that govern the split:

- identity persistence is explicitly single-install and single-row, so any
  same-user multi-device contract must be written in terms of two installations
  restoring the same identity, not one app instance magically syncing local
  state for free
- group-authoritative state is keyed by the same peer/group facts on every
  device, while mute, unread, notification suppression, and pending-invite
  review are stored only in each installation's local repo/runtime
- the current fake group pubsub network assumes one controller per peer id and
  sender devices never receive their own publish copy, so same-identity sibling
  devices cannot be proven without a harness seam
- `handleIncomingGroupMessage(...)` always persists replay/live deliveries as
  incoming rows today, so if the repo wants another joined device with the same
  identity to reflect that user's own sent history truthfully, the receive seam
  must become self-aware
- maintained matrix docs still mark `UX-013` as `Contract-undefined`, so final
  closure must update those docs only after the shared-vs-local contract and
  supporting proof are both real

Source-of-truth conflicts that materially affected decomposition:

- the source doc leaves mute, unread, notification, and invite-review scope
  open; this breakdown treats those as an explicit contract-selection session
  rather than silently inferring account-wide sync
- there is no out-of-tree account sync system in this repo, so closure must be
  honest about which states are shared because they are group-authoritative and
  which remain installation-local today

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Define the repo-owned same-user multi-device contract` | `implementation-ready` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`, `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-1-plan.md` | Accepted on `2026-04-05` after landing the shared `group_multi_device_policy.dart` seam, encoding joined-device shared state versus device-local state explicitly, and passing the direct policy proof. |
| `2` | `Support same-identity joined-device convergence in the harness and receive path` | `implementation-ready` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`, `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-2-plan.md` | Accepted on `2026-04-05` after landing the device-aware fake pubsub harness, sibling-device self-delivery sent-state handling, the new same-user joined-device convergence integration proof, and the required `groups` gate. |
| `3` | `Prove device-local mute, unread, notification, and invite-review behavior` | `implementation-ready` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md`, `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-3-plan.md` | Accepted on `2026-04-05` after landing same-user sibling-device proof that mute, unread, and local notifications stay device-local, plus direct accept/decline pending-invite regressions that pin invite review as installation-local, then passing the focused direct suites and the required `groups` gate. |
| `4` | `Close UX-013 with maintained-doc updates and final verification` | `implementation-ready` | `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`, `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-breakdown.md` | Accepted on `2026-04-05` after updating the maintained architecture and matrix docs to close `UX-013`, removing the row from the contract-undefined/open trackers, and rerunning the direct policy/same-user proof suites plus the `groups` gate. |

## Pipeline progress

- `2026-04-05`: Reusable doc-65 breakdown artifact created via bounded local
  decomposition fallback. Session `1` is the first runnable session.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-1-plan.md`
  to choose one repo-owned same-user multi-device contract.
- `2026-04-05`: Session `1` accepted after bounded local execution/QA fallback
  landed `group_multi_device_policy.dart`, encoded joined-device shared state
  versus device-local state once in repo-owned code, and passed:
  `flutter test test/features/groups/domain/models/group_multi_device_policy_test.dart`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-2-plan.md`
  for the same-identity joined-device convergence slice.
- `2026-04-05`: Session `2` accepted after bounded local execution/QA fallback
  landed the device-aware `FakeGroupPubSubNetwork`, updated
  `GroupTestUser` and the incoming-message receive seam for sibling-device
  self-delivery, added direct same-user joined-device convergence proof in
  `test/features/groups/integration/group_multi_device_convergence_test.dart`,
  and passed:
  `flutter test test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_multi_device_convergence_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-3-plan.md`
  for the device-local mute/unread/notification/invite-review proof slice.
- `2026-04-05`: Session `3` accepted after bounded local execution/QA fallback
  added same-user sibling-device proof that mute, unread, and local
  notifications stay device-local in
  `test/features/groups/integration/group_multi_device_convergence_test.dart`,
  added repo-local accept/decline pending-invite independence proof in
  `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  and
  `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`,
  refreshed one stale retained-backlog invite fixture to match the already
  landed Session-63 retention contract, and passed:
  `flutter test test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-4-plan.md`
  for the maintained-doc closure pass.
- `2026-04-05`: Session `4` accepted after the bounded local closure pass
  updated `09-network-group-messaging.md`, closed `UX-013` in the full
  matrix, removed the row from the policy-needed and not-fully-implemented
  trackers, and passed:
  `flutter test test/features/groups/domain/models/group_multi_device_policy_test.dart test/features/groups/application/handle_incoming_group_message_use_case_test.dart test/features/groups/integration/group_multi_device_convergence_test.dart test/features/groups/application/accept_pending_group_invite_use_case_test.dart test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
  and `./scripts/run_test_gates.sh groups`.

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-05`
- Completion summary:
  - decomposition is complete
  - sessions `1` through `4` are accepted
  - `UX-013` is closed in maintained docs with same-day policy, convergence,
    device-local, and gate evidence

## Ordered session breakdown

### Session 1

- Title:
  `Define the repo-owned same-user multi-device contract`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-1-plan.md`
- Exact scope:
  - choose one explicit contract for which group facts are shared across two
    devices that restore the same identity and which remain device-local
  - encode that contract once in a repo-owned seam so later tests and docs can
    cite it without stringly typed drift
  - state the joined-device precondition clearly: shared-state convergence
    applies after the device has materialized the group locally, not to
    unresolved pending invites by implication
  - add direct proof for the chosen shared-vs-local mapping
- Why it is its own session:
  - later harness and regression work cannot be truthful until the product
    contract is explicit
  - isolating the contract selection keeps later same-peer behavior changes
    from smuggling in policy assumptions
- Likely code-entry files:
  - `lib/features/groups/domain/models/group_multi_device_policy.dart`
  - `test/features/groups/domain/models/group_multi_device_policy_test.dart`
  - `Test-Flight-Improv/09-network-group-messaging.md`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 2

- Title:
  `Support same-identity joined-device convergence in the harness and receive path`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-2-plan.md`
- Exact scope:
  - extend the fake group pubsub harness so two devices can share one peer
    identity without clobbering each other's controllers or subscriptions
  - make the receive path self-aware so a sibling device that receives the same
    user's own sent message persists truthful sent history instead of unread
    incoming state
  - add same-user joined-device regressions for live shared message/state
    convergence inside the current repo-owned scope
  - preserve existing distinct-peer behavior and avoid duplicate membership rows
- Why it is its own session:
  - same-peer multi-device modeling is the highest-risk technical seam because
    the current harness and receive path both assume one device per peer id
  - it can be verified independently before device-local policy tests land
- Likely code-entry files:
  - `test/shared/fakes/fake_group_pubsub_network.dart`
  - `test/shared/fakes/group_test_user.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `test/features/groups/integration/group_multi_device_convergence_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Prove device-local mute, unread, notification, and invite-review behavior`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-3-plan.md`
- Exact scope:
  - prove the chosen device-local rule for mute, unread counts, notification
    suppression, and pending-invite review across two devices with the same
    identity
  - preserve joined-device shared state from Session `2` while making the
    device-local exceptions explicit and testable
  - add focused direct or integration regressions for these local-only seams
- Why it is its own session:
  - the row stays contract-undefined unless the non-shared states are just as
    explicit as the shared ones
  - separating device-local proofs keeps them from being hidden inside the
    harder same-peer harness work
- Likely code-entry files:
  - `test/features/groups/integration/group_multi_device_convergence_test.dart`
  - `test/features/groups/application/accept_pending_group_invite_use_case_test.dart`
  - `test/features/groups/application/decline_pending_group_invite_use_case_test.dart`
  - `test/shared/fakes/in_memory_pending_group_invite_repository.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 4

- Title:
  `Close UX-013 with maintained-doc updates and final verification`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/65-same-user-multi-device-group-convergence-session-4-plan.md`
- Exact scope:
  - update the maintained architecture and matrix docs so `UX-013` moves from
    `Contract-undefined` to landed behavior with concrete proof references
  - remove the row from the policy-needed and not-fully-implemented trackers if
    the implementation now owns the contract completely
  - persist the final doc-65 program verdict only after the shared-state proof,
    the device-local proof, and the maintained docs all agree on the same
    multi-device rule
- Why it is its own session:
  - matrix closure should happen only after both the shared and device-local
    sides of the contract are real and verified
  - keeping closure separate prevents premature tracker cleanup
