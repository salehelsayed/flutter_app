# 64 - Group Membership Size Limit Contract Session Breakdown

## Decomposition artifact

- Artifact path:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- Decomposition date:
  `2026-04-05`

## Downstream execution path

- detailed planning happens one session at a time
- later sessions must be refreshed against landed code before execution

## Recommended plan count

- `4`

## Overall closure bar

Report `64` closed only when the repo owns one explicit, testable max-group-size
contract instead of leaving `UX-009` contract-undefined:

- one concrete member cap is encoded in repo-owned code, with one shared helper
  that later sessions and maintained docs can cite
- creating or growing a group up to that cap continues to work normally
- adding one or more members beyond the cap fails cleanly under one
  deterministic rule, without partial phantom members, duplicate rows, or
  broken existing membership state
- shipped create-group and add-member flows show truthful feedback when the cap
  is exceeded
- maintained architecture and matrix docs no longer describe `UX-009` as
  contract-undefined once the landed code, tests, and UI agree on the same rule

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`

Current repo facts that govern the split:

- `09-network-group-messaging.md` currently describes `10-50` as a reasonable
  current target and `50-100` as unprofiled, but it does not claim a hard,
  enforced product cap
- `addGroupMember(...)` currently checks only recovery state, admin role, and
  duplicate membership, so a size-limit contract does not yet exist at the
  single-add seam
- `createGroupWithMembers(...)` and `ContactPickerWired._inviteSelected()`
  currently add each selected contact individually and continue past member-add
  failures, so an over-limit batch rule would be ambiguous without an explicit
  app-owned contract
- `CreateGroupPickerWired` and `ContactPickerWired` currently surface only
  generic create/invite failure snackbars, so even a future limit rejection
  would not yet be user-visible or truthful by default
- maintained matrix docs still mark `UX-009` as `Contract-undefined`, so final
  closure must update those docs only after code, tests, and visible UX agree
  on one concrete cap and overflow rule

Source-of-truth conflicts that materially affected decomposition:

- the source doc intentionally leaves the exact numeric cap and batch-overflow
  rule open; this breakdown treats that as a repo-owned contract-selection
  session, not as a reason to defer indefinitely
- there is no bridge or relay-side hard member-limit seam in this tree, so the
  closure target is a truthful client-owned cap enforced in the Flutter-owned
  create/add flows the repo controls today

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Define the repo-owned max-group-size contract and shared overflow helper` | `implementation-ready` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`, `Test-Flight-Improv/64-group-membership-size-limit-contract-session-1-plan.md` | Accepted on `2026-04-05` after landing the shared `group_membership_limit_policy.dart` seam, the typed `GroupMembershipLimitException`, direct overflow-math proof, and the required `groups` gate. |
| `2` | `Enforce the cap in single-add, create-with-members, and batch invite flows` | `implementation-ready` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-2-plan.md` | `1` | `accepted` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`, `Test-Flight-Improv/64-group-membership-size-limit-contract-session-2-plan.md` | Accepted on `2026-04-05` after enforcing the shared 50-member cap in the single-add, create-with-members, and batch invite seams with all-or-nothing overflow rejection, then passing the direct mutation-path suites plus the `groups` gate. |
| `3` | `Expose truthful size-limit feedback in create-group and add-member UI` | `implementation-ready` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-3-plan.md` | `1`, `2` | `accepted` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`, `Test-Flight-Improv/64-group-membership-size-limit-contract-session-3-plan.md` | Accepted on `2026-04-05` after landing localized size-limit snackbars in the shipped create-group and add-member wired flows, preserving generic failure fallback for non-limit errors, and passing the direct presentation suites plus the `groups` gate. |
| `4` | `Close UX-009 with maintained-doc updates and final verification` | `implementation-ready` | `Test-Flight-Improv/64-group-membership-size-limit-contract-session-4-plan.md` | `1`, `2`, `3` | `accepted` | `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`, `Test-Flight-Improv/libp2p_group_chat_matrix_not_fully_implemented.md`, `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md` | Accepted on `2026-04-05` after updating the maintained network and matrix docs to close `UX-009`, removing the row from the contract-undefined/open trackers, and rerunning the direct policy/create/add/presentation suites plus the `groups` gate. |

## Pipeline progress

- `2026-04-05`: Reusable doc-64 breakdown artifact created via bounded local
  decomposition fallback. Session `1` is the first runnable session.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-1-plan.md`
  to select one repo-owned member cap and shared overflow seam for `UX-009`.
- `2026-04-05`: Session `1` accepted after bounded local execution/QA fallback
  landed `group_membership_limit_policy.dart`, the typed overflow exception,
  direct policy proof in
  `test/features/groups/domain/models/group_membership_limit_policy_test.dart`,
  and passed:
  `flutter test test/features/groups/domain/models/group_membership_limit_policy_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-2-plan.md`
  for the create/add enforcement slice.
- `2026-04-05`: Session `2` accepted after bounded local execution/QA fallback
  enforced the shared 50-member cap in
  `add_group_member_use_case.dart`,
  `create_group_with_members_use_case.dart`, and
  `contact_picker_wired.dart`, added direct regressions for at-limit success,
  over-limit single-add rejection, over-limit create rejection, and
  over-limit batch rejection, and passed:
  `flutter test test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-3-plan.md`
  for the truthful size-limit feedback slice.
- `2026-04-05`: Session `3` accepted after bounded local execution/QA fallback
  landed typed size-limit feedback in
  `create_group_picker_wired.dart` and `contact_picker_wired.dart`, added
  localized limit strings for the shipped locales, and passed:
  `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`
  and `./scripts/run_test_gates.sh groups`.
- `2026-04-05`: Local planning created
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-4-plan.md`
  for the maintained-doc closure pass.
- `2026-04-05`: Session `4` accepted after the bounded local closure pass
  updated `09-network-group-messaging.md`, closed `UX-009` in the full
  matrix, removed the row from the policy-needed and not-fully-implemented
  trackers, and passed:
  `flutter test test/features/groups/domain/models/group_membership_limit_policy_test.dart test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/create_group_with_members_use_case_test.dart test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`
  and `./scripts/run_test_gates.sh groups`.

## Final program verdict

- Status:
  `closed`
- Last updated:
  `2026-04-05`
- Completion summary:
  - decomposition is complete
  - sessions `1` through `4` are accepted
  - `UX-009` is closed in maintained docs with same-day policy,
    create/add, UI, and gate evidence

## Ordered session breakdown

### Session 1

- Title:
  `Define the repo-owned max-group-size contract and shared overflow helper`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-1-plan.md`
- Exact scope:
  - choose one explicit repo-owned max group size, including whether the count
    includes the creator and the member total later sessions must enforce
  - encode that cap once in a shared helper/policy seam so create, add, UI, and
    maintained docs do not silently fork the rule
  - expose the minimum shared overflow metadata or exception shape needed for
    later sessions to reject over-limit operations without stringly typed logic
  - add direct policy proof for the chosen cap and overflow math
- Why it is its own session:
  - later enforcement and UX work cannot be truthful until one concrete cap and
    counting rule exist
  - isolating the contract selection reduces the risk of mixing policy drift
    with broader create/add behavior changes
- Likely code-entry files:
  - `lib/features/groups/domain/models/group_membership_limit_policy.dart`
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `test/features/groups/domain/models/group_membership_limit_policy_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 2

- Title:
  `Enforce the cap in single-add, create-with-members, and batch invite flows`
- Session id:
  `2`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-2-plan.md`
- Exact scope:
  - enforce the chosen cap for single-member add, create-with-members, and the
    add-member batch invite path
  - choose and implement one deterministic batch-overflow rule, with the
    existing group state left intact if the requested batch exceeds the cap
  - prevent partial phantom members, duplicate rows, or config-sync side
    effects on rejected over-limit operations
  - add direct application and integration regressions for at-limit success,
    single-member overflow rejection, and batch overflow rejection
- Why it is its own session:
  - this is the highest-risk correctness seam because it changes mutation paths
    for both existing groups and initial group creation
  - it can be verified independently before user-facing copy lands
- Likely code-entry files:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/presentation/screens/contact_picker_wired.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/features/groups/presentation/contact_picker_wired_test.dart`
  - `test/features/groups/presentation/contact_picker_multi_select_integration_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 3

- Title:
  `Expose truthful size-limit feedback in create-group and add-member UI`
- Session id:
  `3`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-3-plan.md`
- Exact scope:
  - surface one clear user-visible limit outcome in the shipped add-member and
    create-group flows when a requested selection would exceed the cap
  - make the chosen overflow rule understandable without implying that the
    existing group is broken or partially updated
  - keep create and add-member surfaces aligned on the same cap and wording
  - add focused presentation/wired regressions for the visible limit feedback
- Why it is its own session:
  - the UX must explain the real enforcement behavior from Session `2`, not a
    hypothetical rule
  - separating UI work keeps presentation changes from obscuring mutation-path
    regressions
- Likely code-entry files:
  - `lib/features/groups/presentation/screens/contact_picker_wired.dart`
  - `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
  - `lib/features/groups/presentation/screens/contact_picker_screen.dart`
  - `lib/l10n/app_en.arb`
  - `lib/l10n/app_de.arb`
  - `lib/l10n/app_ar.arb`
  - `test/features/groups/presentation/contact_picker_wired_test.dart`
  - `test/features/groups/presentation/create_group_picker_wired_test.dart`
- Likely named gates:
  - `./scripts/run_test_gates.sh groups`

### Session 4

- Title:
  `Close UX-009 with maintained-doc updates and final verification`
- Session id:
  `4`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-4-plan.md`
- Exact scope:
  - update the maintained architecture and matrix docs so `UX-009` moves from
    `Contract-undefined` to landed behavior with concrete proof references
  - remove the row from the policy-needed tracker if the implementation now
    owns the contract completely
  - persist the final doc-64 program verdict only after code, direct tests,
    visible UX, and maintained docs all agree on the same max-size rule
- Why it is its own session:
  - matrix closure should happen only after shipped behavior and feedback are
    both real and verified
  - keeping closure separate prevents premature tracker cleanup
