# Session SC-004 Plan: Normalize missing messageId without breaking legacy id envelopes

## Real scope

- Close row `SC-004` from
  `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`.
- Add row-owned regression proof that `ensureEnvelopeMessageId` patches a
  missing top-level `messageId` while preserving compatibility with legacy
  top-level `id` envelopes.
- Keep the session test-only unless the new proof exposes a real helper bug.

## Closure bar

Session `SC-004` is good enough when the repo has direct automated proof that:

- a legacy-shaped intro envelope missing top-level `messageId` gains the
  caller-provided dedupe-safe `messageId`,
- the legacy top-level `id` field remains accepted instead of causing parse or
  normalization failure, and
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
  `test/features/introduction/application/introduction_payload_test.dart`

When docs and repo evidence disagree, repo code and tests win.

## Session classification

`implementation-ready`

## Exact problem statement

- The repo already has direct proof that intro-only envelope IDs are replaced
  with scoped `messageId` values so `send` and `accept` retries do not collide.
- The row still lacks dedicated proof for the specific legacy shape called out
  by the matrix: a top-level `id` envelope with no `messageId`.
- Without that narrow regression, the row remains open even though the helper is
  present and current behavior appears compatible.

## Files and repos to inspect next

- `test/features/introduction/application/introduction_payload_test.dart`
- `lib/features/introduction/domain/models/introduction_payload.dart`

## Existing tests covering this area

- `introduction_payload_test.dart` already proves the helper replaces intro-only
  IDs with scoped `messageId` values.
- `introduction_payload_test.dart` already proves the v2 encrypted envelope
  builder emits a default top-level `messageId`.
- No existing row-owned test pins the legacy top-level `id` plus missing
  `messageId` shape.

## Regression/tests to add first

- Add one helper regression in
  `test/features/introduction/application/introduction_payload_test.dart` that
  starts from a legacy-shaped v2 envelope missing `messageId`, normalizes it,
  and proves the envelope still parses while preserving `id`.

## Step-by-step implementation plan

1. Add the missing legacy-envelope normalization regression in
   `introduction_payload_test.dart`.
2. Run the targeted payload suite.
3. Run `./scripts/run_test_gates.sh intro`.
4. If green, refresh matrix, inventory, and breakdown for `SC-004`.

## Risks and edge cases

- Keep the assertions focused on row truth: message ID is added, legacy `id`
  survives, and the normalized encrypted envelope remains parseable.
- Do not widen into delivery orchestration, listener dedupe, or replay rows
  owned elsewhere.

## Exact tests and gates to run

Direct suite:

```bash
flutter test --no-pub \
  test/features/introduction/application/introduction_payload_test.dart
```

Required named gate:

```bash
./scripts/run_test_gates.sh intro
```

## Known-failure interpretation

- If normalization drops legacy `id`, fails to add the provided `messageId`, or
  makes the envelope unparsable, that is a current-session product bug.
- If the regression passes and the gate stays green, the row can close as
  covered.

## Done criteria

- Missing-`messageId` plus legacy-`id` normalization is directly covered.
- `./scripts/run_test_gates.sh intro` is green.
- The matrix, inventory, and breakdown are updated truthfully.

## Scope guard

- Do not widen into `SC-001`, `DR-001`, or transport-level replay rows unless
  the helper regression reveals a real product gap.

## Accepted differences / intentionally out of scope

- This session does not add new production behavior unless the targeted
  regression proves one is needed.
- This session does not add simulator, relay, or multi-node proof.

## Dependency impact

- Later security and delivery rows can cite this row-owned helper regression as
  the direct proof that legacy-shaped intro envelopes normalize into
  dedupe-compatible transport IDs without breaking compatibility.
