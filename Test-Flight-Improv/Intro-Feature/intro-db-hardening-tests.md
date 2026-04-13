# Intro DB Hardening Tests

## 1. Title and Type

- Title: Intro persistence and migration hardening tests
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/Intro-Feature/intro-db-hardening-tests.md`

## 2. Problem Statement

Users rely on Introduction state to stay truthful across app upgrades, resume,
offline replay, and retry paths. That includes pending intro visibility,
already-connected visibility without badge inflation, deferred response replay,
and retryable intro delivery rows.

The repo already has broad Intro coverage and one upgrade-chain proof, but the
direct intro database helper and migration surface is still relatively thin
compared with the stronger Group Chat persistence bar.

From the user's perspective, this matters because silent SQL or migration drift
can make the Intro feature look wrong only after restart, upgrade, or retry,
which is exactly when trust is hardest to rebuild.

## 3. Impact Analysis

- Who is affected: users who reopen the app after intro activity, drain deferred
  intro responses, retry intro deliveries, or upgrade from older local schemas.
- When the issue appears: after app upgrade, app restart, retry selection, or
  UI reload driven by persisted intro state rather than only live in-memory
  state.
- Severity: low to medium. The current feature is already broadly covered, but
  persistence regressions in this area can create stale counts, missing repair
  rows, or wrong visibility after restart.
- Frequency: not established by repo evidence. This is a hardening gap rather
  than a confirmed production regression.
- User-visible consequence: pending counts, intro visibility, or retry/replay
  behavior can silently drift only in persistence-driven cases.

## 4. Current State

- Production intro persistence spans:
  - `lib/core/database/helpers/introductions_db_helpers.dart`
  - `lib/core/database/helpers/pending_introduction_responses_db_helpers.dart`
  - `lib/core/database/helpers/introduction_outbox_db_helpers.dart`
- Production intro migrations span:
  - `lib/core/database/migrations/019_introductions_table.dart`
  - `lib/core/database/migrations/022_introduction_keys.dart`
  - `lib/core/database/migrations/023_introduction_recipient_keys.dart`
  - `lib/core/database/migrations/025_introduction_already_connected_status.dart`
  - `lib/core/database/migrations/046_pending_introduction_responses.dart`
  - `lib/core/database/migrations/047_introduction_outbox.dart`
- Existing direct coverage includes:
  - `test/core/database/migrations/046_pending_introduction_responses_test.dart`
    for the deferred-response table
  - `test/core/database/integration/full_migration_chain_test.dart`, which
    proves a migrated schema can persist newly arrived introductions and
    deferred responses
  - `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`,
    which proves intro delete cleanup also clears staged deferred responses and
    outbox rows
- Existing intro inventory already records the remaining thin areas:
  - no dedicated migration tests for 019, 022, 023, 025, or 047
  - no direct intro DB helper tests
- Important current persistence contracts already embodied in code include:
  - pending loader includes `already_connected` rows for visibility in
    `introductions_db_helpers.dart`
  - pending badge count excludes `already_connected`
  - deferred intro responses load in stable chronological order in
    `pending_introduction_responses_db_helpers.dart`
  - retryable intro outbox rows are selected by status/path rules in
    `introduction_outbox_db_helpers.dart`

## 5. Scope Clarification

- In scope: strengthening direct repo-owned persistence proof for Intro across
  migrations, helper queries, and retry/deferred-response selection behavior.
- In scope: user-visible persistence contracts such as pending list truth,
  pending badge truth, deferred response replay inputs, and retryable outbox
  selection.
- In scope: upgrade-path confidence for intro-specific schema columns and
  persistence tables.
- Out of scope: redesigning Intro storage, adding new Intro product behavior,
  or changing the meaning of intro statuses.
- Out of scope: relay inbox behavior, push routing, avatar recovery, or Orbit
  and Feed copy.
- Accepted ambiguity for later implementation: this spec does not require every
  migration to receive equal test weight. It only requires the current thin
  intro persistence surface to be tightened enough that restart and upgrade
  behavior is less dependent on indirect coverage.

## 6. Test Cases

### Happy Path

- `TC-IDHT-HP-01` Given a user upgrades from an older schema, when a new intro
  is persisted after upgrade, then the intro still loads with the expected IDs,
  usernames, key fields, and visibility behavior.
- `TC-IDHT-HP-02` Given a deferred intro response is stored before the intro is
  replayed, when the intro later loads, then the deferred response rows are
  still present and ordered deterministically for replay.
- `TC-IDHT-HP-03` Given intro outbox rows exist after stalled or failed
  delivery, when retry selection runs later, then only the intended rows are
  surfaced as retryable and delivered rows already completed through inbox do
  not remain stuck forever.

### Edge Cases

- `TC-IDHT-EC-01` Given an `alreadyConnected` intro exists locally, when the
  app reloads pending intro UI state, then the intro remains visible for
  context but does not inflate the pending badge count.
- `TC-IDHT-EC-02` Given multiple deferred intro responses exist for the same
  introduction, when they are later loaded for replay, then their replay input
  order remains stable and deterministic.
- `TC-IDHT-EC-03` Given intro outbox rows span `failed`, `sending`, `sent`, and
  `delivered via inbox` states, when retry selection runs, then only the rows
  matching the intended retry rules are returned.

### Regressions To Preserve

- `TC-IDHT-RG-01` Given the app deletes an intro, then any staged deferred
  responses and outbox rows tied to that intro are still cleaned up together.
- `TC-IDHT-RG-02` Given the app upgrades from an older schema, then existing
  intro persistence and deferred-response behavior already covered by the full
  migration chain remains green.
- `TC-IDHT-RG-03` Given pending intro UI is driven from persisted rows, then
  current pending-count truth remains unchanged: only true `pending` rows count
  toward the badge.

### Existing Coverage And Gaps

- Existing partial coverage:
  - `test/core/database/migrations/046_pending_introduction_responses_test.dart`
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/introduction/domain/repositories/introduction_repository_impl_test.dart`
  - indirect coverage through Intro use-case and integration suites
- Current gap:
  - no direct migration tests for intro migrations 019, 022, 023, 025, or 047.
- Current gap:
  - no direct helper tests for intro pending-loader SQL, pending-count SQL,
    deferred-response helper behavior, or outbox retry-selection helper
    behavior.
- Preservation note:
  - this spec is hardening for persistence confidence, not a claim that the
    current Intro feature is broadly unreliable.
