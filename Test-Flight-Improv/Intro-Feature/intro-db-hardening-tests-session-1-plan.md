# Session 1 Plan: Intro DB Hardening Tests

**Final verdict:** sufficient as revised

## 1. Real Scope

- Keep Session 1 limited to direct intro database proof at the migration and
  helper-query layer.
- Add direct migration coverage for `019`, `022`, `023`, `025`, and `047`.
- Add direct helper coverage for:
  - `dbLoadPendingIntroductionsForUser(...)`
  - `dbCountPendingIntroductions(...)`
  - `dbLoadPendingIntroductionResponses(...)`
  - `dbLoadRetryableIntroductionOutboxDeliveries(...)`
- Prefer test-only changes. Only touch production DB code if the new direct
  proof shows a real correctness bug that must be fixed for the tests to stay
  truthful.
- Do not execute product, UI, transport, or multi-device intro work in this
  session.

## 2. Closure Bar

- `test/core/database/migrations/intro_migrations_test.dart` directly proves:
  - `019` creates the `introductions` table with the expected recipient,
    introduced, and introducer indexes
  - `022` and `023` add the four intro key columns
  - `025` rebuilds the table without losing preexisting row data or key-column
    values and allows `already_connected`
  - `047` creates `introduction_outbox_deliveries` with its retry, intro, and
    target indexes
- `test/core/database/helpers/intro_db_helpers_test.dart` directly proves:
  - pending intro loading includes `already_connected` rows for context and
    still orders by `created_at DESC`
  - pending intro counting still includes only true `pending` rows
  - deferred intro responses still load by `created_at ASC, response_key ASC`
  - retryable intro outbox selection still returns only the helper's intended
    rows and keeps `created_at ASC, delivery_id ASC` order
- Existing higher-level intro persistence coverage remains green and is treated
  as preserved behavior, not replaced behavior.
- This doc is only ready to close once the direct persistence seam is proven
  without overstating the result as broad intro reliability work.

## 3. Source Of Truth

- Active session contract:
  - `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests-session-breakdown.md`
- Product/problem contract:
  - `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests.md`
- Named gate authority:
  - `Test-Flight-Improv/test-gate-definitions.md`
- Live repo authority on disagreement:
  - `lib/core/database/migrations/019_introductions_table.dart`
  - `lib/core/database/migrations/022_introduction_keys.dart`
  - `lib/core/database/migrations/023_introduction_recipient_keys.dart`
  - `lib/core/database/migrations/025_introduction_already_connected_status.dart`
  - `lib/core/database/migrations/047_introduction_outbox.dart`
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
  - `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
  - `test/core/database/migrations/046_pending_introduction_responses_test.dart`
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`
- Rule on conflict:
  - current code and tests beat stale prose
  - `test-gate-definitions.md` decides whether a named gate is required

## 4. Session Classification

- `implementation-ready`

## 5. Exact Problem Statement

- The repo already has broad intro behavior coverage and one migration-chain
  proof, but it does not directly test the intro-owned migration seam for
  `019`, `022`, `023`, `025`, or `047`.
- The repo also does not directly test the helper-query seam that drives:
  - pending intro visibility from persisted rows
  - pending intro badge truth
  - deferred intro response replay order
  - retryable intro outbox selection
- The live SQL contract is narrow and concrete:
  - pending intro loader selects statuses `pending` and `already_connected`
  - pending intro count selects only status `pending`
  - deferred responses order by `created_at ASC, response_key ASC`
  - retryable outbox rows include `failed`, stale `sending` / `sent`, and
    `delivered` rows whose `delivery_path` is `inbox`
- User-visible risk is persistence-only drift after restart, upgrade, or retry,
  not a confirmed product-scope intro regression.

## 6. Files And Repos To Inspect Next

- Primary migration files:
  - `lib/core/database/migrations/019_introductions_table.dart`
  - `lib/core/database/migrations/022_introduction_keys.dart`
  - `lib/core/database/migrations/023_introduction_recipient_keys.dart`
  - `lib/core/database/migrations/025_introduction_already_connected_status.dart`
  - `lib/core/database/migrations/047_introduction_outbox.dart`
- Primary helper files:
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
  - `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
- Closest existing test patterns:
  - `test/core/database/migrations/046_pending_introduction_responses_test.dart`
  - `test/core/database/migrations/026_group_quoted_message_id_test.dart`
  - `test/core/database/helpers/messages_db_helpers_test.dart`
  - `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- Existing higher-level intro regressions to preserve:
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`

## 7. Existing Tests Covering This Area

- `test/core/database/migrations/046_pending_introduction_responses_test.dart`
  already proves direct creation and idempotence for the deferred-response
  table.
- `test/core/database/integration/full_migration_chain_test.dart` already
  proves a migrated schema can persist newly arrived introductions and deferred
  responses.
- `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`
  already proves delete-time cleanup clears staged deferred responses before
  removing the intro row and outbox rows.
- Missing today:
  - direct migration proof for `019`, `022`, `023`, `025`, and `047`
  - direct helper proof for pending intro loader/count SQL
  - direct helper proof for deferred-response ordering
  - direct helper proof for retryable outbox selection

## 8. Regressions/Tests To Add First

- Add `test/core/database/migrations/intro_migrations_test.dart` with focused
  cases for:
  - `019` table creation plus `idx_introductions_recipient`,
    `idx_introductions_introduced`, and `idx_introductions_introducer`
  - `022` adding `introduced_public_key` and
    `introduced_ml_kem_public_key`
  - `023` adding `recipient_public_key` and
    `recipient_ml_kem_public_key`
  - `025` upgrade flow that seeds a pre-migration intro row, runs the rebuild,
    verifies row preservation, key-column preservation, recreated indexes, and
    acceptance of `already_connected`
  - `047` table creation plus `idx_intro_outbox_retry`,
    `idx_intro_outbox_intro`, and `idx_intro_outbox_target`
- Add `test/core/database/helpers/intro_db_helpers_test.dart` with focused
  cases for:
  - pending loader includes `already_connected` rows for the current peer and
    excludes terminal or unrelated rows
  - pending loader preserves descending `created_at` order
  - pending count excludes `already_connected`
  - pending response loading uses `created_at` first and `response_key` as the
    tiebreaker
  - retryable outbox loading includes `failed`, stale `sending`, stale `sent`,
    and `delivered` + `inbox` rows, excludes fresh or wrong-path rows, honors
    the limit, and preserves `created_at ASC, delivery_id ASC`

## 9. Step-By-Step Implementation Plan

- Create `test/core/database/migrations/intro_migrations_test.dart` first.
- Reuse the simple migration-test style from
  `046_pending_introduction_responses_test.dart` and
  `026_group_quoted_message_id_test.dart` rather than inventing a new harness.
- For `025`, run `019`, `022`, and `023`, seed a row with the key columns
  populated, then run `025` so the test proves rebuild preservation instead of
  just schema presence.
- Create `test/core/database/helpers/intro_db_helpers_test.dart` second.
- Use an in-memory SQLite setup that runs only the migrations needed for the
  helper cases: `019`, `022`, `023`, `025`, `046`, and `047`.
- Keep fixtures explicit and local to the file so the SQL contract is obvious
  from the assertions.
- Stop and reassess before touching production code if the new direct tests
  contradict the current helper SQL or migration behavior. First decide whether
  the test expectation is wrong or the repo has a real DB bug.
- Only after that evidence pass should execution run the targeted direct suites,
  then widen to the broader database suite, then update the stable intro docs.

## 10. Risks And Edge Cases

- `025` is the highest-risk migration because it recreates the table. A weak
  schema-only test would miss lost rows, lost key-column values, or missing
  recreated indexes.
- The pending loader and pending count intentionally disagree on
  `already_connected`. The tests must pin that asymmetry rather than "fix" it.
- The deferred-response helper order is two-part. A test that varies only
  `created_at` would miss regression in the `response_key` tiebreaker.
- The outbox helper has both status and path logic. A status-only test would
  miss the special `delivered` + `inbox` branch.
- If any direct proof shows a production bug, keep the fix limited to the
  smallest intro DB seam needed to make the new tests truthful.

## 11. Exact Tests And Gates To Run

- Direct suites during execution:
  - `flutter test --no-pub test/core/database/migrations/intro_migrations_test.dart`
  - `flutter test --no-pub test/core/database/helpers/intro_db_helpers_test.dart`
- Broader touched suite:
  - `flutter test --no-pub test/core/database`
- Named gates:
  - none for the expected test-only path
- If execution changes production intro behavior or runtime intro DB code:
  - `./scripts/run_test_gates.sh intro`

## 12. Known-Failure Interpretation

- No documented known-red state currently targets the direct intro migration or
  helper suites this session adds.
- Treat failure in the new targeted tests as one of two things only:
  - a real intro DB regression
  - a mistaken test expectation that does not match the current live contract
- If `flutter test --no-pub test/core/database` fails outside the new files,
  isolate whether the failure is preexisting before expanding session scope.

## 13. Done Criteria

- `intro_migrations_test.dart` exists and proves the intended migration seam.
- `intro_db_helpers_test.dart` exists and proves the intended helper-query
  seam.
- The new direct suites pass.
- The broader `test/core/database` suite passes, or any unrelated preexisting
  failure is explicitly separated from this session.
- Stable intro docs are ready for a later closure pass to mark only the direct
  persistence gap as covered.

## 14. Scope Guard

- Do not add a new intro schema, database version bump, or migration beyond the
  direct proofs already scoped here.
- Do not widen into introduction application logic, UI, transport, Orbit, Feed,
  push, or multi-device reliability work.
- Do not rewrite helper semantics unless the new direct proof shows the current
  repo behavior is wrong.
- Do not reopen broader intro reliability audits from this test-hardening
  session.

## 15. Accepted Differences / Intentionally Out Of Scope

- Existing higher-level intro persistence coverage remains as-is and is not
  duplicated.
- Multi-device, transport, notification, and follow-up surface reliability are
  outside this session.
- No named Test-Flight gate is required unless execution stops being test-only.

## 16. Dependency Impact

- This is the only implementation session needed for
  `intro-db-hardening-tests.md` under the current breakdown.
- If the direct tests land cleanly, the current doc can proceed to execution
  and later closure without creating a second plan for the same persistence
  seam.
- If the direct tests expose a wider production DB issue that cannot be fixed
  narrowly, stop this doc's pipeline and record the blocker rather than
  broadening Session 1 into redesign work.

## Structural Blockers Remaining

- None.
