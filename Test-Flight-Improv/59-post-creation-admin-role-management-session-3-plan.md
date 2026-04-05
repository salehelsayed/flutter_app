# 59 Session 3 Plan: Matrix Closure, Multi-Admin Leave, and Conflict Proof

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- add the exact remaining regressions that close the doc-owned matrix rows for
  multi-admin leave and concurrent/conflicting admin-change convergence
- document the landed conflict-resolution rule the repo now implements for
  post-creation admin-role changes
- update the maintained audit and matrix docs so they stop describing this seam
  as unsupported once the code/test proof is in place
- persist the final doc-59 verdict in the breakdown after code, tests, and
  docs agree

Out of scope for this session:

- new product features beyond the already-landed admin role-management seam
- reopening metadata editing, notification mute, or dissolve scope from later
  docs
- inventing a richer arbitration protocol than the current repo-owned
  timestamp-plus-authoritative-snapshot contract

### Closure bar

Session `3` is done only when:

- the repo has a direct proof for `MR-021` showing a multi-admin leave keeps
  the group healthy and remaining admins retain admin-only actions
- the repo has direct proof for `SC-013` and `SC-014` showing near-simultaneous
  admin changes converge deterministically to one final member/admin map
- the maintained docs no longer mark `MR-016`, `MR-017`, `MR-018`, `MR-019`,
  `MR-021`, `UX-011`, `SC-013`, and `SC-014` as unsupported once the evidence
  is landed
- the final documented conflict rule matches the actual repo behavior instead
  of an aspirational design
- the required direct suites and the named `groups` gate pass

### Source of truth

- active session contract:
  `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- product intent:
  `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- maintained closure docs to refresh:
  `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  `Test-Flight-Improv/09-network-group-messaging.md`
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- regression and gate authority:
  `Test-Flight-Improv/14-regression-test-strategy.md`
  `Test-Flight-Improv/test-gate-definitions.md`
- landed code/tests beat stale prose when they disagree

### Session classification

- `implementation-ready`

### Exact problem statement

Sessions `1` and `2` landed the core mutation seam and the shipped group-info
surface, but doc `59` is not safely closed while the repo’s long-lived audits
and matrix still say the feature is unsupported. The remaining work is to pin
the exact row-owned convergence journeys, write down the real conflict rule,
and update the maintained docs so future work reopens only on regression.

### Files and repos to inspect next

Production and direct-proof files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- `test/shared/fakes/fake_group_pubsub_network.dart`

Closure docs:

- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`

### Existing tests covering this area

- session `1` already proved admin promotion, demotion, non-admin rejection,
  non-member rejection, listener propagation, and stale role-update rollback
- session `2` already proved the shipped group-info affordance, badge refresh,
  promotion timeline payload, and demotion feedback
- `leave_group_use_case_test.dart` already proves the local rule that an admin
  may leave when another admin exists, but doc `59` still lacks the exact
  multi-peer row proof for `MR-021`

Missing direct proof for this session:

- a row-owned multi-admin leave smoke proving remaining admins stay healthy on
  all peers
- a row-owned convergence proof for different admin changes made near the same
  time
- a row-owned conflict proof for remove-versus-promote on the same member
- maintained docs updated to describe the landed role-management contract

### Regression/tests to add first

- extend `test/features/groups/application/group_message_listener_test.dart`
  with a direct stale-order/conflict regression for remove-versus-role-update
  on the same member
- extend `test/features/groups/integration/group_membership_smoke_test.dart`
  with:
  - a multi-admin leave journey for `MR-021`
  - a near-simultaneous different-change convergence journey for `SC-013`
  - a same-member remove-versus-promote convergence journey for `SC-014`
- refresh the matrix/audit docs only after those tests are green

### Step-by-step implementation plan

1. Tighten the listener-level stale-order proof for same-member role/remove
   conflicts so the final conflict rule is explicit.
2. Add the exact smoke journeys for multi-admin leave and near-simultaneous
   admin changes, reusing the fake-network stack already used by the membership
   smoke suite.
3. Run the direct listener and smoke suites first, then rerun the `groups`
   gate.
4. Update the maintained audit/matrix docs to remove the affected rows from
   unsupported scope and replace that wording with the actual landed evidence.
5. Persist the final doc-59 breakdown verdict only after the code/tests/docs
   all agree on the same closure story.

### Risks and edge cases

- doc updates can easily overclaim broader admin tooling if they describe more
  than the landed promote/demote plus multi-admin-leave seam
- the current conflict contract is based on authenticated full snapshots plus
  membership-event timestamp ordering; do not rewrite that into a stronger
  consensus claim than the code proves
- same-member remove-versus-promote tests must pin one explicit winner instead
  of merely asserting “no crash”
- the final doc closure must not silently reopen future doc `60`, `61`, or `62`
  scope

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/groups/application/leave_group_use_case_test.dart`
- `flutter test test/features/groups/integration/group_membership_smoke_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Known-failure interpretation

- treat unrelated pre-existing failures outside the touched group-admin seams as
  known only if they reproduce on unchanged code and do not involve the
  listener, membership smoke, or matrix docs touched here
- do not waive failures in the new row-owned regressions or the `groups` gate

### Done criteria

- the remaining row-owned regressions for doc `59` exist and pass
- the `groups` gate passes after those regressions land
- the maintained matrix/audit docs describe the shipped contract truthfully
- the doc `59` breakdown can persist a finished program verdict

### Scope guard

- do not widen into metadata editing, notification mute, or dissolve features
- do not change the role-management product contract without updating the docs
  and rerunning the row-owned proof
- do not update unrelated matrix rows just because they are nearby

### Accepted differences / intentionally out of scope

- the current conflict rule may remain “latest authenticated membership-event
  snapshot wins” rather than a more complex merge strategy
- same-timestamp ties are not a row-owned contract here; the closure focuses on
  near-simultaneous events with explicit ordering

### Dependency impact

- if this session lands cleanly, doc `59` should be able to close and the batch
  may advance to doc `60`
- if the row-owned convergence proof does not hold, doc `59` stays open and the
  batch must stop before doc `60`

## Structural blockers remaining

- none

## Incremental details intentionally deferred

- any broader roadmap discussion about future admin tooling beyond doc `59`
- closure for later docs `60`, `61`, and `62`

## Accepted differences intentionally left unchanged

- the repo still uses membership-event timestamps and authoritative group
  config snapshots instead of a separate vector-clock or revision ledger
- the final doc closure is scoped to the landed promote/demote/leave seam, not
  every conceivable moderation workflow

## Exact docs/files used as evidence

- `Test-Flight-Improv/59-post-creation-admin-role-management-session-breakdown.md`
- `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_features_did_not_exist.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/leave_group_use_case.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`

## Why the plan is safe to implement now

- it builds on already-landed code and focuses only on the remaining row-owned
  proof plus closure docs
- it names the exact remaining regressions and the single named gate required
  for truthful closure
- it keeps later-doc scope out of the current context so the batch can obey
  `finish_current_doc_before_advancing`
