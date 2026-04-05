# 64 Session 4 Plan: Close UX-009 In Maintained Docs

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- update the maintained architecture note and matrix docs so they describe the
  landed repo-owned 50-member max-group-size contract instead of leaving
  `UX-009` contract-undefined
- close `UX-009` with concrete proof references spanning the shared policy
  seam, create/add enforcement, and truthful shipped feedback
- remove `UX-009` from the policy-needed and not-fully-implemented trackers
- record the final doc-64 closure verdict after same-day verification is
  attached

Out of scope for this session:

- changing the chosen 50-member contract or the user-visible limit copy
- same-user multi-device convergence work, which remains open under `UX-013`
- new scale profiling beyond the repo-owned cap already chosen in sessions `1`
  to `3`

### Closure bar

Session `4` is done only when:

- `09-network-group-messaging.md` states the explicit 50-member cap, the
  creator-counting rule, the all-or-nothing overflow behavior, and the truthful
  shipped feedback seam
- the full matrix marks `UX-009` closed with exact repo-local proof references
- the policy-needed and not-fully-implemented trackers no longer list `UX-009`
- the doc-64 breakdown records a final `closed` verdict with same-day
  verification evidence

### Source of truth

- active session contract:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`
- product/problem doc:
  `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- session `1` contract seam:
  `lib/features/groups/domain/models/group_membership_limit_policy.dart`
- session `2` enforcement seams:
  `lib/features/groups/application/add_group_member_use_case.dart`
  `lib/features/groups/application/create_group_with_members_use_case.dart`
  `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- session `3` UX seams:
  `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
  `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- maintained architecture note:
  `Test-Flight-Improv/09-network-group-messaging.md`
- maintained matrix docs:
  `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
  `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`

### Exact problem statement

The repo now owns the max-group-size contract in code, tests, and shipped UI,
but the long-lived maintenance docs still describe `UX-009` as
contract-undefined. Session `4` must bring those docs back into sync so the row
stays closed unless the behavior truly regresses.

### Files and repos to inspect next

Docs:

- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`
- `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`

Verification artifacts:

- `test/features/groups/domain/models/group_membership_limit_policy_test.dart`
- `test/features/groups/application/add_group_member_use_case_test.dart`
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`

### Step-by-step implementation plan

1. Refresh the maintained network architecture note so it names the explicit
   50-member cap, the fact that the creator counts toward that total, and the
   all-or-nothing rejection rule for over-limit create/add selections.
2. Update the full matrix row for `UX-009` from `Contract-undefined` to
   `Closed`, using the direct policy, create/add, and presentation suites as
   proof.
3. Remove `UX-009` from the policy-needed and not-fully-implemented trackers,
   updating the tracker counts to match.
4. Re-run the targeted policy and presentation suites plus the required named
   gate, then write the final doc-64 breakdown verdict with same-day evidence.

### Risks and edge cases

- do not overclaim scale support above the chosen 50-member cap; the closure is
  a truthful product contract, not new large-group profiling proof
- keep the docs aligned on the same counting rule: the creator/admin is part of
  the 50-member total
- do not imply partial acceptance on over-limit batch invites; the landed rule
  is all-or-nothing with no state mutation
- avoid touching `UX-013` or other still-open rows unless the count or wording
  change is required after removing `UX-009`

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/domain/models/group_membership_limit_policy_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- maintained docs all agree that `UX-009` is landed repo behavior
- the trackers and full matrix no longer disagree about max-group-size support
- doc `64` records a final closed verdict with same-day verification evidence

### Scope guard

- do not start doc `65` until the doc-64 breakdown records a final close
- do not widen this pass into broader scale-architecture or profiling work
