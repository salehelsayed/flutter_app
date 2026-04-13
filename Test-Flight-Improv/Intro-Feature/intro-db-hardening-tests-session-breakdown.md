# Intro DB Hardening Tests Session Breakdown

## Decomposition artifact updated

- Artifact path:
  `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
- Proposal/source doc path:
  `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests.md`
- Decomposition date:
  `2026-04-13`
- Decomposition mode:
  bounded local decomposition fallback after the fresh decomposition agent left
  no reusable current-doc artifact on disk
- Downstream workflow rule:
  - detailed planning happens one session at a time
  - later sessions must be refreshed against landed code before execution

## Downstream execution path

- Session `1` should run through:
  1. `$implementation-plan-orchestrator`
  2. `$implementation-execution-qa-orchestrator`
  3. `$implementation-closure-audit-orchestrator`

## Recommended plan count

- `1`

## Overall closure bar

`intro-db-hardening-tests.md` is only closed when all of the following are true
at the same time:

- the repo has direct migration proof for the intro-owned schema surface in
  migrations `019`, `022`, `023`, `025`, and `047`
- the repo has direct helper-query proof that:
  - pending intro loading still includes `already_connected` rows for context
  - pending intro badge count still counts only true `pending` rows
  - deferred intro responses still load in stable replay order
  - retryable intro outbox selection still returns only the intended rows
- existing intro persistence guarantees already covered indirectly remain
  truthful, especially delete-time cleanup and the broader full migration chain
- stable intro docs record the narrowed persistence-hardening proof without
  overstating it as a broad feature-reliability reopen

## Source of truth

Primary governing docs:

- `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/Intro-Feature/test-inventory.md`
- `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md`

Current repo facts that govern the split:

- `lib/core/database/helpers/introductions_db_helpers.dart` owns the exact SQL
  for pending intro visibility and badge count truth, including the
  `already_connected` visibility rule.
- `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
  already encodes the stable replay ordering contract as
  `created_at ASC, response_key ASC`.
- `lib/core/database/helpers/introduction_outbox_db_helpers.dart` already
  encodes retry selection around `failed`, stalled `sending` / `sent`, and
  `delivered` rows that completed through inbox.
- direct intro migration coverage currently exists only for
  `046_pending_introduction_responses_test.dart`.
- `test/core/database/integration/full_migration_chain_test.dart` and
  `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`
  already provide higher-level persistence regression coverage that this report
  should preserve rather than replace.

Source-of-truth conflicts that materially affected decomposition:

- the current gap is concentrated in direct SQL and migration proof, not in
  product behavior or multi-device orchestration
- splitting migrations and helper queries into separate sessions would add
  bookkeeping without creating a safer closure path because the doc closes on
  one persistence-hardening seam and the same focused database suite can verify
  it together

## Session ledger

| Session ID | Title | Classification | Intended plan file | Depends on | Current status | Closure docs touched | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `1` | `Add direct intro migration and helper-query persistence proof` | `implementation-ready` | `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-1-plan.md` | none | `accepted` | `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`, `Test-Flight-Improv/Intro-Feature/test-inventory.md`, `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md` | Accepted on `2026-04-13`: landed `test/core/database/migrations/intro_migrations_test.dart` and `test/core/database/helpers/intro_db_helpers_test.dart`, refreshed the intro inventory and the two-pass audit, and reran `flutter test --no-pub test/core/database/migrations/intro_migrations_test.dart`, `flutter test --no-pub test/core/database/helpers/intro_db_helpers_test.dart`, and `flutter test --no-pub test/core/database` green with no production code changes required. |

## Ordered session breakdown

### Session 1

- Title:
  `Add direct intro migration and helper-query persistence proof`
- Session id:
  `1`
- Session classification:
  `implementation-ready`
- Intended plan file:
  `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-1-plan.md`
- Exact scope:
  - add direct migration tests for the intro-owned schema surface:
    - `019_introductions_table.dart`
    - `022_introduction_keys.dart`
    - `023_introduction_recipient_keys.dart`
    - `025_introduction_already_connected_status.dart`
    - `047_introduction_outbox.dart`
  - add direct helper tests for:
    - `dbLoadPendingIntroductionsForUser(...)`
    - `dbCountPendingIntroductions(...)`
    - `dbLoadPendingIntroductionResponses(...)`
    - `dbLoadRetryableIntroductionOutboxDeliveries(...)`
  - keep the change test-only unless execution exposes a real schema or helper
    bug that must be fixed to make the new proof truthful
  - update stable intro docs only enough to record that the direct persistence
    seam is now covered
  - update this breakdown with the landed execution and closure result
- Why it is its own session:
  - the report is a single persistence-hardening seam
  - the migrations and helper queries share one SQL-owned verification surface
  - splitting test files into multiple rollout sessions would add overhead
    without reducing implementation risk
- Likely code-entry files:
  - `test/core/database/migrations/intro_migrations_test.dart`
  - `test/core/database/helpers/intro_db_helpers_test.dart`
  - `lib/core/database/migrations/019_introductions_table.dart`
  - `lib/core/database/migrations/022_introduction_keys.dart`
  - `lib/core/database/migrations/023_introduction_recipient_keys.dart`
  - `lib/core/database/migrations/025_introduction_already_connected_status.dart`
  - `lib/core/database/migrations/047_introduction_outbox.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
  - `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md`
  - `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
- Likely direct tests/regressions:
  - `flutter test --no-pub test/core/database/migrations/intro_migrations_test.dart`
  - `flutter test --no-pub test/core/database/helpers/intro_db_helpers_test.dart`
  - `flutter test --no-pub test/core/database`
- Likely named gates:
  - none for the default test-only database hardening path
  - if execution needs a production DB helper or migration fix, also rerun
    `./scripts/run_test_gates.sh intro`
- Matrix/closure docs to update when done:
  - required:
    - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
    - `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md`
    - `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
  - intentionally unchanged unless execution widens:
    - `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`
    - `Test-Flight-Improv/Intro-Feature/libp2p_introduction_test_matrix_full_with_rules.md`
- Dependency on earlier sessions:
  - none
- Downstream execution path:
  - `$implementation-plan-orchestrator`
  - `$implementation-execution-qa-orchestrator`
  - `$implementation-closure-audit-orchestrator`
- Closure note:
  - Accepted on `2026-04-13` after the direct intro migration and helper-query
    proof landed in `intro_migrations_test.dart` and `intro_db_helpers_test.dart`,
    the broader `test/core/database` suite passed, and stable intro docs were
    updated to record the closed persistence seam truthfully.

## Why this is not fewer sessions

- A docs-only pass would still leave the direct SQL and migration seams
  unproven.
- The report closes on one focused persistence-hardening slice, so a separate
  planning-only or docs-only session would add process without new verification
  value.

## Why this is not more sessions

- The intro migrations and helper queries are part of the same small database
  seam and can be verified with the same targeted database suites.
- No product, UI, transport, or multi-device work is justified by the current
  repo evidence for this report.

## Regression and gate contract

- Add the direct migration and helper tests first.
- Run the touched targeted suites before widening to `test/core/database`.
- No named Test-Flight gate is required for the default test-only path.
- If execution reveals a production database bug and fixes repo code, rerun
  `./scripts/run_test_gates.sh intro` before closure.

## Matrix update contract

- Update:
  - `Test-Flight-Improv/Intro-Feature/test-inventory.md`
  - `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md`
  - `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
- Session ownership:
  - Session `1` owns the closure update because there is only one meaningful
    direct persistence-hardening seam in this report.
- Truthfulness rule:
  - record only the direct migration and helper-query coverage that actually
    lands
  - do not overclaim full feature reliability or a broader schema redesign

## Structural blockers remaining

- none

## Accepted differences intentionally left unchanged

- This report does not require a database version bump or new intro schema.
- This report does not require new multi-device or transport coverage when the
  current gap is direct SQL and migration proof.

## Current pipeline state

- sessions processed so far: `1/1`
- sessions accepted so far: `1`
- sessions accepted_with_explicit_follow_up so far: `0`
- sessions currently blocked: `0`
- next runnable session in order: `none`
- current doc state: `closed`
- final program verdict is persisted below

## Final program acceptance

- final program verdict:
  `closed`
- docs updated:
  `test/core/database/migrations/intro_migrations_test.dart`,
  `test/core/database/helpers/intro_db_helpers_test.dart`,
  `Test-Flight-Improv/Intro-Feature/test-inventory.md`,
  `Test-Flight-Improv/Intro-Feature/Two-Pass-Intro-Reliability-Audit-2026-04-13.md`,
  `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-1-plan.md`,
  `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
- why the rollout is safe to complete:
  - the repo now has direct intro migration proof for `019`, `022`, `023`,
    `025`, and `047`
  - the repo now has direct helper-query proof for pending intro visibility,
    pending count truth, deferred-response replay ordering, and retryable
    outbox selection
  - the touched targeted suites and the broader `test/core/database` regression
    pass all completed green without needing a runtime code change
