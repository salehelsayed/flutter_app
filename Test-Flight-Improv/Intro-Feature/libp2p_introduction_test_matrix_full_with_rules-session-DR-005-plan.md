# Session DR-005 Plan: Delayed same-intro merge/replay convergence fix

## Real scope

- Refresh row `DR-005` from an evidence-gap plan into an implementation-ready
  fix plan.
- Fix only the product-side delayed-delivery same-intro convergence defect
  exposed by `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`.
- Reuse the already-landed proof harness in
  `lib/core/debug/intro_e2e_runner.dart` and `smoke_test_friends.sh` exactly as
  the reproducer; do not spend this session inventing a different proof seam.
- Keep the source matrix, session breakdown, and test inventory unchanged until
  the `partial` scenario and required gates are green on landed product code.
- Do not widen into generic transport fallback, sender-crash recovery,
  partition-healing, restart-healing, or later `DR-*` rows.

## Closure bar

Session `DR-005` is only good enough when the repo has both a narrow
product-level regression and a green transport-grade proof showing that:

- A sends one introduction.
- B receives that intro and accepts while C is still unreachable.
- C later receives that same `introductionId`.
- B's earlier accept is merged/replayed through C's late-delivery path.
- C can accept and the pair converges without duplicate intro rows or duplicate
  B/C contacts.
- A also converges to the final accepted state for that same intro.

Required closure verification for this session is:

- `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`
- `./scripts/run_test_gates.sh intro`
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`

## Source of truth

- Active row:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Active session ledger:
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- Intro inventory:
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests/harness:
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`,
  `lib/features/introduction/application/accept_introduction_use_case.dart`,
  `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`,
  `lib/features/introduction/application/introduction_listener.dart`,
  `test/features/introduction/integration/introduction_multi_node_test.dart`,
  `test/features/introduction/application/handle_incoming_introduction_test.dart`,
  `test/features/introduction/application/introduction_listener_test.dart`,
  `test/features/introduction/regression/introduction_regression_test.dart`,
  `lib/core/debug/intro_e2e_runner.dart`, and `smoke_test_friends.sh`

When docs and repo evidence disagree, repo evidence wins. When
`Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`
disagree, the script wins. The breakdown currently still records `DR-005` as
blocked; this plan refresh does not change that ledger by itself.

## Session classification

`implementation-ready`

## Exact problem statement

- `DR-005` is no longer blocked by a missing proof seam. The repo now has a
  truthful three-simulator reproducer in
  `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`.
- The current red behavior is product-visible and stable: B reaches
  `mutual_accepted`, but A and C remain `pending`, and C never gets the B
  contact.
- The landed harness already proves the recovery path stays on the same
  `introductionId`, so the remaining defect is not "missing proof" or "wrong
  scenario"; it is a delayed-delivery merge/replay failure in the intro
  lifecycle.
- The most likely failing seam is that B's earlier accept is not being staged,
  replayed, merged, or followed by the correct mutual-acceptance side effects
  when C receives the intro later.
- Existing intentional behavior that must stay unchanged:
  accept-before-send staging, blocked-`send` suppression, accept/pass
  completion for already-started intros, idempotent contact creation, and
  same-pair dedupe semantics.

## Files and repos to inspect next

Repo scope: the current `flutter_app` repo only.

Primary production files:

- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/accept_introduction_use_case.dart`
- `lib/features/introduction/application/handle_mutual_acceptance_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`

Conditional production file if the new regression shows the late accept is not
being durably staged or replay-delivered at all:

- `lib/features/introduction/application/introduction_outbound_delivery.dart`

Direct tests and proof harness:

- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/regression/introduction_regression_test.dart`
- `lib/core/debug/intro_e2e_runner.dart`
- `smoke_test_friends.sh`

## Existing tests covering this area

- `test/features/introduction/integration/introduction_multi_node_test.dart`
  already proves that accept notifications can fall back to inbox while peers
  are unreachable and later converge after drain, but that proof is fake-network
  and does not pin the real stopped-node `partial` failure.
- `test/features/introduction/integration/introduction_multi_node_test.dart`
  already proves introducer-side convergence to `mutualAccepted` without
  duplicate B/C contacts on the normal path.
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
  already proves `accept` before `send` is durably deferred and replayed when
  the send row arrives.
- `test/features/introduction/application/introduction_listener_test.dart`
  already proves the listener replays a staged deferred accept when `send`
  arrives later.
- `test/features/introduction/regression/introduction_regression_test.dart`
  already proves blocked stranger accept delivery still completes the handshake
  path and contact creation on the receiver.

What is still missing:

- a row-owned product regression that matches the same-intro delayed-recovery
  path from the red `partial` transport run, including final convergence on A,
  B, and C plus exact-one contact creation.

## Regression/tests to add first

- Add a focused regression to
  `test/features/introduction/integration/introduction_multi_node_test.dart`
  that models this exact contract:
  A sends one intro, C misses the initial send, B accepts first, C later gets
  that same intro, C replays B's earlier accept, C accepts, and A/B/C all
  converge on the same intro without duplicate B/C contacts.
- Keep that new regression red-first. Do not patch production code before the
  new test proves or closely matches the same delayed merge/replay seam.
- If that multi-node regression exposes a narrower seam than expected, add the
  smallest companion regression in
  `test/features/introduction/application/handle_incoming_introduction_test.dart`
  or `test/features/introduction/application/introduction_listener_test.dart`
  to pin the exact missing replay or side-effect rerun. Do not start by adding
  more simulator harness logic.

## Step-by-step implementation plan

1. Re-run `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh` and confirm the
   red state still matches the current target defect before touching code.
2. Add the smallest new host-side regression in
   `test/features/introduction/integration/introduction_multi_node_test.dart`
   that mirrors the delayed same-intro recovery contract from `partial`.
3. If the new regression does not fail, stop and compare it against the
   simulator trace before broadening scope; do not guess at a fix.
4. Once the regression is red, trace only the seams needed to explain it:
   staged pending responses, late `send` replay, status derivation, and
   idempotent rerun of mutual-acceptance side effects.
5. Patch the smallest product path necessary in
   `handle_incoming_introduction_use_case.dart`,
   `accept_introduction_use_case.dart`,
   `handle_mutual_acceptance_use_case.dart`,
   `introduction_listener.dart`, or repository persistence only if the failing
   regression proves that seam is responsible.
6. Add one smaller application/listener regression only if the final fix needs
   extra protection at the exact seam found. Avoid test sprawl.
7. Run the directly touched intro suites until the new regression and nearby
   intro correctness tests are green.
8. Run `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh`.
9. Run `./scripts/run_test_gates.sh intro`.
10. Run `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`.
11. Only after all of the above are green may the later closure step update the
   matrix, breakdown, and inventory and mark `DR-005` closed.

## Risks and edge cases

- Replaying a delayed accept can accidentally double-run contact creation or
  duplicate intro system messages unless mutual-acceptance side effects stay
  idempotent.
- A fix that only repairs C's local row can still leave A stale; introducer-side
  convergence must remain part of the closure bar.
- The fix must not reopen terminal `passed`, `alreadyConnected`, or stale-row
  cases while hardening late accept replay.
- Blocked-`send` behavior and accept/pass block-bypass behavior must not change.
- The real stopped-node reproducer can tempt timing-only tweaks; those are out
  of scope unless the new regression proves the bug is not in product logic.

## Exact tests and gates to run

Direct suites:

```bash
flutter test --no-pub test/features/introduction/integration/introduction_multi_node_test.dart
flutter test --no-pub test/features/introduction/application/handle_incoming_introduction_test.dart
flutter test --no-pub test/features/introduction/application/introduction_listener_test.dart
flutter test --no-pub test/features/introduction/regression/introduction_regression_test.dart
```

Required transport-grade proof and named gates:

```bash
INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh
./scripts/run_test_gates.sh intro
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport
```

## Known-failure interpretation

- If the new regression or the `partial` scenario still ends with B
  `mutual_accepted` while A/C remain `pending` or C still lacks the B contact,
  that is the target `DR-005` bug, not a flaky result.
- If `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh` fails because of
  simulator boot, device selection, firewall, or other environment/runtime
  issues, treat that as an environment blocker and do not claim the product fix
  is proven.
- A green host-side regression by itself is not sufficient to close `DR-005`;
  the real `partial` scenario and the required intro/transport gates must also
  be green.
- If the host-side regression is green but `partial` stays red, stop and
  investigate why the real stack diverges before broadening product scope.

## Done criteria

- A new row-owned regression protects the delayed same-intro recovery seam.
- The minimal product fix is landed with no unrelated harness expansion.
- `INTRO_E2E_SCENARIO=partial ./smoke_test_friends.sh` is green.
- `./scripts/run_test_gates.sh intro` is green.
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD ./scripts/run_test_gates.sh transport`
  is green.
- Only after those commands are green may `DR-005` be treated as closed and the
  matrix, breakdown, and inventory be updated as covered.

## Scope guard

- Do not mark `DR-005` closed and do not update the matrix, breakdown, or
  inventory until the `partial` scenario is green.
- Do not reopen `lib/core/debug/intro_e2e_runner.dart` or `smoke_test_friends.sh`
  for new scenario design unless current evidence proves the reproducer is
  untrustworthy.
- Do not widen into `DR-003`, `DR-004`, `DR-008`, `DR-009`, `DR-010`,
  `DR-011`, `DR-012`, or `DR-014`.
- Do not redesign the intro transport stack, resume retrier, or generic
  recovery architecture in this session.
- Stop if new evidence proves the defect is not in delayed same-intro
  merge/replay logic; do not continue with speculative fixes.

## Accepted differences / intentionally out of scope

- No sender-crash durability work for post-send local persistence (`DR-009`).
- No broad partition-healing or restart-healing work (`DR-010`, `DR-014`).
- No new UI, Orbit, Feed, or notification behavior changes.
- No new fake-network or simulator harness features beyond using the already
  landed `partial` proof seam.
- No closure-doc updates as part of this plan refresh alone.

## Dependency impact

- `DR-005` remains the active ordered blocker in the current breakdown until
  this fix lands and the required proof is green.
- Later unresolved delivery rows should not be marked covered by analogy while
  `DR-005` is still red.
- A truthful `DR-005` fix will reduce ambiguity for later convergence rows such
  as `DR-010`, `DR-012`, and `DR-014`, but it does not close them automatically.
