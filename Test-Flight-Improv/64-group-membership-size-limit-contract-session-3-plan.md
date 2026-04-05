# 64 Session 3 Plan: Surface Truthful Group Size Limit Feedback

## Final verdict

- `implementation-ready`

## Final plan

### Real scope

- catch the typed `GroupMembershipLimitException` in the shipped create-group
  and add-member wired flows and replace the generic failure snackbar with
  truthful limit-specific feedback
- keep create and add surfaces aligned on the same 50-member contract and the
  same all-or-nothing overflow rule from Session `2`
- add or update localized strings for the limit-specific messages in the
  supported app locales
- add focused widget regressions proving the visible size-limit feedback while
  preserving the generic failure path for non-limit errors

Out of scope for this session:

- changing the chosen 50-member contract or the all-or-nothing overflow rule
- maintained-doc and matrix closure work
- deeper screen redesign beyond the minimum truthful feedback needed on the
  existing create and invite surfaces

### Closure bar

Session `3` is done only when:

- create-group overflow shows user-visible copy that states the concrete member
  limit and that the selection must be reduced before creation can continue
- add-member overflow shows user-visible copy that states the same concrete
  member limit and selection-reduction rule without implying any partial add
  happened
- non-limit failures still use the existing generic failure snackbars
- direct presentation tests prove the limit-specific snackbar behavior in both
  wired flows and the locale files stay generated and in sync

### Source of truth

- active session contract:
  `Test-Flight-Improv/64-group-membership-size-limit-contract-session-breakdown.md`
- session `1` policy seam:
  `lib/features/groups/domain/models/group_membership_limit_policy.dart`
- session `2` enforcement seams:
  `lib/features/groups/application/create_group_with_members_use_case.dart`
  `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- product/problem doc:
  `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- named gate contract:
  `Test-Flight-Improv/test-gate-definitions.md`

### Exact problem statement

The repo now enforces one shared 50-member limit, but both shipped wired
surfaces still collapse every failure into a generic snackbar. That leaves
`UX-009` only partially true because admins cannot tell when they hit the
product-owned size contract versus a normal transport or bridge error.

### Files and repos to inspect next

Production files:

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_de.arb`
- `lib/l10n/app_ar.arb`
- `lib/l10n/app_localizations.dart`
- `lib/l10n/app_localizations_en.dart`
- `lib/l10n/app_localizations_de.dart`
- `lib/l10n/app_localizations_ar.dart`

Direct tests:

- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`

### Existing tests covering this area

- `create_group_picker_wired_test.dart` already proves generic failure
  snackbar behavior, so it can absorb a size-limit-specific create regression
- `contact_picker_wired_test.dart` already proves over-limit batch rejection
  leaves state unchanged, so it can also pin the user-visible limit snackbar

### Regression/tests to add first

- add a create-group widget regression that exceeds the limit and asserts the
  limit-specific snackbar copy
- extend the existing over-limit invite regression to assert the limit-specific
  snackbar copy
- keep or add one generic create failure assertion so non-limit errors still
  fall back to the old generic message

### Step-by-step implementation plan

1. Add localized create and invite size-limit message keys that include the
   concrete max-member count and how much the selection must be reduced.
2. Regenerate the localizations so the typed getters exist in the generated
   Dart files.
3. In `CreateGroupPickerWired`, catch `GroupMembershipLimitException` and show
   the create-specific localized message; preserve the existing generic
   snackbar for every other failure.
4. In `ContactPickerWired`, catch `GroupMembershipLimitException` and show the
   invite-specific localized message; preserve the existing generic snackbar
   for every other failure.
5. Add the focused widget regressions above and rerun them plus the required
   `groups` gate.

### Risks and edge cases

- keep the create message explicit that the creator counts toward the 50-member
  limit, otherwise the copy can contradict the enforced rule
- do not imply partial success on the invite surface; the overflow rule is
  still all-or-nothing
- avoid inventing new UI chrome when the existing snackbar surface is enough to
  make the rule truthful
- ensure localized getters are regenerated so CI and the analyzer do not drift

### Exact tests and gates to run

Direct tests:

- `flutter test test/features/groups/presentation/create_group_picker_wired_test.dart test/features/groups/presentation/contact_picker_wired_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`

### Done criteria

- both wired flows show limit-specific feedback on typed overflow exceptions
- generic failures still show the existing generic copy
- the direct widget suites above pass
- the required named gate is run

### Scope guard

- do not reopen Session `2` mutation behavior unless the widget feedback work
  proves a real enforcement bug
- do not start maintained-doc closure until the limit-specific feedback is
  shipped and verified
