# Session UX-001 Plan: Pin Orbit intro review grouping and pending count

## Real scope

- Close row `UX-001` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned screen-level proof that the Orbit `Intros` review surface
  renders grouped intros and carries the correct pending count into the active
  filter toggle.
- Keep the session test-only unless the new proof exposes a real UI bug.

## Closure bar

Session `UX-001` is good enough when the repo has direct automated proof that:

- the real Orbit screen renders intro groups for distinct introducers in the
  `Intros` view,
- the same screen carries the correct pending intro count into the `Intros`
  filter toggle, and
- the intro gate stays green.

## Source of truth

- Breakdown artifact:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current tests:
  `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
  `test/features/orbit/presentation/screens/orbit_intros_wiring_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already has wiring-level intro count and grouping checks in
  `orbit_intros_wiring_test.dart`.
- The repo also already has one OrbitScreen widget test that proves intro rows
  render in the sliver list.
- The row still lacks one direct screen-level proof that grouped intro sections
  and the `Intros` pending count are present together on the actual Orbit
  review surface.

## Files and repos to inspect next

- `test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart`
- `lib/features/orbit/presentation/screens/orbit_screen.dart`
- `lib/features/orbit/presentation/widgets/friends_filter_toggle.dart`

## Existing tests covering this area

- `orbit_intros_wiring_test.dart` covers data loading, grouping, and pending
  counts at the wiring layer.
- `orbit_screen_archived_groups_test.dart` already proves the intro sliver
  renders one grouped intro without a nested list.
- No existing row-owned test proves the grouped review UI and `Intros` pending
  count together on the same rendered Orbit screen.

## Regression/tests to add first

- Add one OrbitScreen widget regression in
  `orbit_screen_archived_groups_test.dart` that renders multiple grouped intros
  and asserts `FriendsFilterToggle.introsCount`.

## Step-by-step implementation plan

1. Add the missing OrbitScreen regression in
   `orbit_screen_archived_groups_test.dart`.
2. Run the targeted Orbit screen widget suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `UX-001`.

## Risks and edge cases

- Keep the assertions tied to the row contract: grouped sections, rendered intro
  rows, and the correct `Intros` count.
- Do not widen into the banner-variant row (`UX-011`), deep-linking, or delete
  flows owned by other sessions.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_screen_archived_groups_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If grouped intros render but the filter toggle count is wrong, that is a
  current-session Orbit UI bug.
- If the new regression passes and the gate stays green, the row can close as
  covered.

## Done criteria

- Orbit intro review grouping and `Intros` pending count are directly covered.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into `UX-011`, `UX-006`, or navigation-shell badge rows unless
  the direct Orbit review regression reveals a real product gap.

## Accepted differences / intentionally out of scope

- This session does not add new production behavior unless the new widget proof
  exposes one.
- This session does not add simulator or multi-node UI proof.

## Dependency impact

- Later Orbit UX rows can cite this row-owned screen regression as the direct
  proof that the rendered review surface matches the grouped intro state and
  visible pending count.
