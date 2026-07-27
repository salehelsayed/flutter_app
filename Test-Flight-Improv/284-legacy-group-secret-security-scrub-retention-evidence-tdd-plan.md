# 284 - Legacy Group-Secret Security Scrub Retention Evidence

Status: acceptance-verified — retained
Type: Modification
Spec: free-text DTR-10 item 8
Classification: acceptance-only
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 CEST | Evidence Collector | legacy scrub source/tests, `main.dart`, secure-reference repository tests, DTR08-COMP-011, release and migration documentation | Confirmed the scrub remains production-wired; repository evidence is local-namespace only and contains no fleet-wide completion/adoption proof | Preserve the scrub and define the evidence floor for any future retirement plan |
| 2026-07-26 CEST | Planner | tier matrix, plan template, sufficiency checklist, host gate registrations | This is acceptance-only retention: no causal RED, production edit, schema change, or device claim is justified | Hand off exact verification and terminal retention condition |
| 2026-07-27 CEST | TDD Reviewer | Plan; current startup/background/import/reset source; scrub/repository/migration tests; gate registrations; DTR08-COMP-011 | `plan-fixes-required`: keep the accepted-retention direction, but remove profile/telemetry/recovery overclaims, make the startup audit fail closed, add v96-v98 and secure upload-completion preservation, and record the background/import marker bypasses as unresolved accepted differences | Execute the corrected acceptance-only contract |

## Problem And Evidence

- Behavior to improve: prevent technical-debt cleanup from deleting the startup
  safety scrub that moves legacy group/media secrets out of SQL rows and into
  secure storage.
- Impact: premature removal could leave a supported upgraded, long-dormant, or
  release-supported imported profile with plaintext legacy key material. The
  scrub deliberately skips existing secure references and therefore does not
  repair missing secure material; dangling-reference recovery is a separate
  unresolved condition rather than a benefit claimed for this scrub.
- Confirmed root cause/current gap: N/A — HEAD already performs the requested
  retention. `scrubLegacyGroupSecretsToSecureStorage` remains production-called
  at `lib/main.dart:609`; its secure-store-namespace completion sentinel and
  migration behavior are implemented at
  `lib/core/secure_storage/legacy_group_secret_storage_scrub.dart:13-49`.
- Existing coverage:
  `test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart`
  proves plaintext media and group rows move to secure references, reruns are
  idempotent, and a second invocation against the same DB/secure-store namespace
  skips DB scans. It does not simulate a process restart, profile replacement,
  or database import. Group/media repository tests prove secure-reference
  writes, hydration, and fail-closed behavior.
- Missing coverage: the repository has no release telemetry, supported
  Move-Account/database-replacement census, release-declared backup census, or
  release-owner evidence proving zero eligible legacy rows across every
  supported population.
- Confirmed: the v96 global DB release floor does not prove scrub completion;
  older data can survive through upgraded profiles and database replacement.
  Any additional backup mechanism must be declared and evidenced by Release.
- Owner decision: the current authenticated project owner explicitly requires
  retention unless release/security evidence proves that no supported account
  still needs the scrub.
- Refuted: “the one-shot `group_secrets_scrubbed` sentinel proves all users or
  even every later database in that install are migrated” is refuted. The fixed,
  non-profile-qualified key proves only that a prior invocation completed in
  the current secure-store namespace. It is not owned by the Move Account
  registry/reset lifecycle, and there is no release aggregation.
- Refuted: “current repositories write only secure references, therefore the
  scrub is obsolete” is refuted. New writes do not establish the state of old,
  restored, or previously dormant rows.
- Unresolved findings: installed-profile completion rate, Move Account/database
  replacement and any release-declared backup floor, zero-legacy-row evidence,
  marker-by-data lifecycle alignment (including marker-present plus newly
  imported legacy rows), background-isolate access before foreground startup,
  missing secure material recovery, and mixed-client crypto-format adoption.
  Their absence requires retention but is not claimed to be solved by retention
  alone.
- Affected production, test, and gate files: no files are changed by this
  acceptance-only plan. Verification reads `main.dart`, the scrub, secure
  storage reference helpers, group/media repositories, their focused tests,
  and DTR08-COMP-011.

## Release/Security Retirement Evidence Decision

Retirement requires one auditable evidence package that proves all of the
following, not a collection of local implementation clues:

| Required proof | Repository-held evidence | Decision |
|---|---|---|
| The supported install/profile, Move Account/database-replacement, and any release-declared backup floors postdate successful scrub rollout | The repository records a v96 database floor and scrub history, but does not tie every supported profile or imported database to completed scrub execution. Android system backup/device transfer is disabled and iOS secure values are device-only, so generic OS backup support is not assumed | Not satisfied |
| Every supported population has zero eligible plaintext legacy rows and an aligned completion marker | Scrub events are debug/test diagnostics only, the marker is non-profile-qualified, and there is no release population artifact | Not satisfied |
| Every marker x data/material state has an approved recovery outcome | Marker-present returns before a DB read; Move Account can replace active rows after startup; the marker is absent from its secure-storage registry/reset ownership; the background isolate can read legacy plaintext without invoking the scrub; and existing tests cover only same-namespace rerun plus fail-closed reads | Not satisfied |
| Mixed-client and crypto-format rollout/rollback no longer depend on the compatibility path | DTR08-COMP-011 keeps the crypto/client floor `UNKNOWN`; no audited atomic-rollout evidence is present | Not satisfied |

Therefore repository evidence is insufficient to authorize removal, and the
terminal decision for this plan is `Retained`. This does not claim that no
external evidence can exist; it records that none was supplied to or is
auditable from this repository. If Security + Release later supply all four
proofs, create a separate removal TDD plan rather than changing this plan's
acceptance-only scope.

## Graph Grounding Snapshot

- Planning graph fingerprint / freshness: `0c2b989ba6d96ada`; current when
  captured on 2026-07-26.
- Planning query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-10 retain scrubLegacyGroupSecretsToSecureStorage legacy_group_secret_storage_scrub.dart and determine whether release security evidence proves no supported account needs it" --profile tdd --budget 700`.
- Review query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 284 counterexample audit: verify scrubLegacyGroupSecretsToSecureStorage startup ordering, group_secrets_scrubbed profile scope, repository secure-reference tests, DTR08-COMP-011 retention evidence, and gate registration" --profile review --budget 800`.
- Review fingerprint / freshness: `27c36c44774fc4ee`; anchored. Graphify
  reported `stale:lib/core/bridge/bridge_group_helpers.dart`, an unrelated
  concurrent path. The scrub/startup/import/background linchpins were therefore
  verified directly in current source; no review-time refresh was needed.
- Anchor:
  `scrubLegacyGroupSecretsToSecureStorage` ->
  `lib/core/secure_storage/legacy_group_secret_storage_scrub.dart:15`.
- Surfaced proof/gate files:
  `test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart`,
  auto-registered under `core-host-all`.
- Graph gaps requiring source search: production startup caller, secure-reference
  repository consumers, release/adoption evidence, Go crypto preservation
  boundaries, and curated gate ownership.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Verify and record that the scrub remains retained under DTR08-COMP-011.
- Verify the absence of sufficient repository-held release/security evidence
  for retirement.
- Define the exact trigger for a future, separate removal TDD plan.

Must preserve:

- Startup invocation and ordering after secret-null migration preparation.
- Active-database plaintext-to-secure-reference movement for media and group
  keys.
- Idempotent same-namespace sentinel/skip behavior and zero second-invocation DB
  scans when the active database/profile has not been replaced.
- Secure-reference write/hydration and fail-closed repository behavior.
- Production group-upload retry delegation through
  `completeGroupUploadRetrySecurely`, ahead of its raw compatibility fallback.

Hard `Do not`:

- Do not remove, bypass, reorder, or modify the scrub, sentinel, startup call,
  SQL fields, secure-store key naming, repository hydration, migrations,
  Dart/native/Go crypto, or persisted key generations.
- Do not interpret local events, a clean new install, the DB v96 floor, current
  secure writes, or passing tests as fleet adoption evidence.
- Do not describe the foreground scrub as a barrier that every background
  isolate or post-startup imported database necessarily crosses.
- Do not create or authorize the future removal plan unless Security + Release
  provide all named population, recovery, and compatibility evidence.

Deferred / accepted difference:

- Retirement remains deferred to a new TDD plan owned by Security + Release +
  Groups + Crypto. That plan is triggered only after supported-profile,
  Move-Account/database-replacement and any release-declared backup floors,
  zero-legacy-row population evidence, the full marker x data/material recovery
  table, and mixed-client/crypto rollout compatibility are proven.
- Current background FCM reads can open `identity.db` in a separate process and
  accept a legacy plaintext group key without invoking the foreground scrub.
  Current Move Account import can also replace active rows after startup while
  `group_secrets_scrubbed` has no registry/reset owner. These are explicit
  unresolved security-hardening boundaries: retention is still necessary, but
  this acceptance-only plan does not claim it is sufficient or authorize their
  production correction.

Dependencies:

- DTR08-COMP-011 remains the compatibility authority. DEP-01 must not remove or
  alter supporting crypto/storage behavior under a dependency-upgrade label.
- DTR10-AUTH-08 records accepted retention and does not authorize removal.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-284-01 | Production foreground startup still invokes the retained scrub after opening/preparing the identity store | Observable source proof: `lib/main.dart:588-613` opens the database, prepares/checks secret storage, then calls `scrubLegacyGroupSecretsToSecureStorage` before readiness | Acceptance-only fail-closed source verification | GREEN sentinel: exactly one awaited caller exists in the ordered startup window on HEAD -> remain unchanged | N/A — no edit is authorized; deleting/reordering the call fails the line-order audit and moves this plan out of acceptance-only scope | Exact count/order shell audit below; declaration check is separate |
| TC-284-02 | Legacy plaintext media and group keys move to secure storage and SQL retains references | `test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart::PREREQ-SECRET-STORAGE-WRAPPING plaintext media key row moves to secure storage and SQL reference form`; `::PREREQ-SECRET-STORAGE-WRAPPING plaintext group key row moves to secure storage and SQL reference form` | Core security/repository host / SQLite FFI plus fake secure key store | GREEN sentinels -> remain green without edits | Bypass secure-store write or leave plaintext in SQL -> corresponding test red | `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'`; AUTO (`test/core/**`) |
| TC-284-03 | A second scrub invocation in the same unchanged DB/secure-store namespace skips without touching the DB | `test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart::TC-14: scrub short-circuits on second launch (emits SCRUB_SKIPPED, no START/SUCCESS)`; `::TC-15: second scrub run performs ZERO table scans` | Core security host / two calls in one process, counting DB proxy, same fake secure store | GREEN sentinels -> remain green for that exact fixture; no production-relaunch/import claim is made | Remove or change the sentinel guard -> TC-14/15 red | `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart`; AUTO (`test/core/**`) |
| TC-284-04 | Current group/media repositories store secure references, hydrate material, fail closed when referenced material is missing, and keep group-upload completion on the secure callback in production | Existing six `PREREQ-SECRET-STORAGE-WRAPPING` selectors; `media_attachment_repository_impl_test.dart::exact group upload completion stores only a secure reference and compensates CAS refusal`; source proof that `GroupMessageRepositoryImpl.completeUploadRetry` prioritizes `completeGroupUploadRetrySecurelyFn` and `main.dart` supplies `mediaAttachmentRepository.completeGroupUploadRetrySecurely` | Feature repository host / real SQLite FFI plus fake secure store; fail-closed production source audit | GREEN sentinels/source proof -> remain green | Return raw reference text, accept missing material, or remove/miswire the secure upload callback -> corresponding selector/source audit red | Seven exact selector commands plus two multiline source audits below; AUTO (`test/features/**`) and existing `GROUP_TESTS` registrations |
| TC-284-05 | The supported production registry and baseline migration order remain unchanged while the scrub is retained | `full_migration_chain_test.dart::production registries preserve the exact ordered v95 baseline`; `::production create and v95 upgrade registries include media library state v96`; `::production registries contain one ordered direct forwarded v97 entry`; `::production registries contain one ordered deletion journal v98 entry`; `::production registries preserve v100-v103 and end with diagnostics v104` | Core migration-chain host / production registries | GREEN sentinels -> remain green without edits | Reorder/drop a supported migration or change the current registry end -> corresponding sentinel red | Five exact `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart --plain-name ...` commands below; AUTO (`test/core/**`) |
| TC-284-06 | Repository evidence does not overclaim fleet-wide completion or foreground-boundary coverage | Acceptance-only evidence package: DTR08-COMP-011, database-floor/platform-backup source, scrub history/tags, debug/test diagnostic census, marker/import/reset lifecycle source, and background-isolate source | Acceptance-only release/security evidence review | HEAD proves local implementation/history plus unresolved bypass states; no external audited population package was supplied -> terminal `Retained` without an operational-sufficiency claim | N/A — absence of external fleet evidence is not mutation-testable; any claimed external evidence must be supplied and independently audited before status changes | Literal history, tag, roadmap/floor, diagnostic, marker/import/reset, background, and platform-policy commands below; direct evidence audit |

## Implementation Steps

1. Snapshot `git status --short`; do not scaffold a causal RED because requested
   retention is already satisfied and no production edit is authorized.
2. Run TC-284-01 through TC-284-06 verification and record semantic results.
3. Confirm the roadmap keeps DTR08-COMP-011 `Retained` with Security + Release
   ownership, the explicit future-removal trigger, and the unresolved
   background/import marker alignment without implying operational sufficiency.
4. If new external fleet evidence is presented, stop this acceptance-only plan.
   Audit the evidence first; only after it satisfies every condition should a
   newly numbered TDD plan be created for removal.

## Risks And Blind Spots

- Local sentinel mistaken for global adoption -> TC-284-06 and the hard
  prohibition prevent that inference.
- Lifecycle / derived-state durability: TC-284-03 proves only a second
  invocation with the same DB and fake secure-store namespace. The marker is
  non-profile-qualified, is absent from Move Account registry/reset ownership,
  and can survive a post-startup active-database replacement; marker-present
  plus eligible legacy rows is therefore an unresolved counterexample.
- Background bypass: the registered FCM handler opens `identity.db` in a
  separate process and may accept a legacy plaintext group-key row without
  invoking the foreground scrub. This strengthens retention but prevents an
  “all runtime reads cross the scrub” claim.
- Raw compatibility fallback: group upload completion can serialize the raw
  attachment when its secure callback is absent. TC-284-04 now protects the
  current production callback wiring and its secure-reference compensation
  behavior.
- Sibling-surface consistency: TC-284-02/04 cover both media and group secrets.
- Destructive-action side effects: N/A — no deletion is permitted. A future
  removal plan must cover existing SQL rows, secure-store entries, backups, and
  recovery.
- Invariant re-verification under new transitions: a future missing-sentinel,
  restore, or format transition must re-check SQL/reference/material
  consistency; this plan adds no transition.

## Gate Cadence

- Per-plan closure: exact startup source audit, focused scrub and repository
  sentinels, the existing `groups` curated gate, strict analysis, and diff
  hygiene. No family-wide sweep is justified because this plan changes no
  application source.
- Do not run full `host-all` for this individual acceptance-only plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 3 DTR-09/10/11
  batch is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs: N/A.

## Acceptance Gates

```bash
# Snapshot before verification; no production edit follows.
git status --short

# Production retention source proof; expect exactly one awaited foreground
# caller and this strict order: general secret migration < null checks < group
# scrub < identity-store readiness. The declaration is checked separately so it
# cannot make a deleted-caller audit pass.
migrate_line=$(rg -n \
  '^[[:space:]]*await migrateSecretsToSecureStorage' lib/main.dart |
  cut -d: -f1)
null_checks_line=$(rg -n \
  '^[[:space:]]*await runSecretNullChecksMigration' lib/main.dart |
  cut -d: -f1)
scrub_call_line=$(rg -n \
  '^[[:space:]]*await scrubLegacyGroupSecretsToSecureStorage' lib/main.dart |
  cut -d: -f1)
ready_line=$(rg -n \
  "^[[:space:]]*StartupTiming\\.instance\\.mark\\('identity_store_ready'\\)" \
  lib/main.dart | cut -d: -f1)
test "$(rg -c \
  '^[[:space:]]*await scrubLegacyGroupSecretsToSecureStorage' \
  lib/main.dart)" -eq 1
test "$migrate_line" -lt "$null_checks_line"
test "$null_checks_line" -lt "$scrub_call_line"
test "$scrub_call_line" -lt "$ready_line"
rg -n '^[[:space:]]*await (migrateSecretsToSecureStorage|runSecretNullChecksMigration|scrubLegacyGroupSecretsToSecureStorage)|identity_store_ready' \
  lib/main.dart
rg -n '^Future<void> scrubLegacyGroupSecretsToSecureStorage' \
  lib/core/secure_storage/legacy_group_secret_storage_scrub.dart

# Focused security preservation; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING saveKey stores group key material in secure storage and only a reference in SQL'
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING getLatestKey and getKeyByGeneration hydrate group key material'
flutter test --no-pub \
  test/features/groups/domain/repositories/group_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING getLatestKey and getKeyByGeneration fail closed when secure material is missing'
flutter test --no-pub \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING saveAttachment stores media key in secure storage and only a reference in SQL'
flutter test --no-pub \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage hydrates media key from secure storage'
flutter test --no-pub \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage clears missing secure media key reference'
flutter test --no-pub \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'exact group upload completion stores only a secure reference and compensates CAS refusal'
rg -n -U \
  '(?s)final secureComplete = completeGroupUploadRetrySecurelyFn;.{0,500}?if \(secureComplete != null\).{0,500}?await secureComplete\(' \
  lib/features/groups/domain/repositories/group_message_repository_impl.dart
rg -n -U \
  '(?s)completeGroupUploadRetrySecurelyFn:.{0,1200}?mediaAttachmentRepository\.completeGroupUploadRetrySecurely\(' \
  lib/main.dart
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production registries preserve the exact ordered v95 baseline'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production create and v95 upgrade registries include media library state v96'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production registries contain one ordered direct forwarded v97 entry'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production registries contain one ordered deletion journal v98 entry'
flutter test --no-pub \
  test/core/database/integration/full_migration_chain_test.dart \
  --plain-name 'production registries preserve v100-v103 and end with diagnostics v104'

# Existing curated preservation; expect exit 0 and zero failed tests.
./scripts/run_test_gates.sh groups

# Repository-held evidence audit. These commands prove local implementation,
# debug/test diagnostics, unresolved lifecycle/bypass states, history, and
# documented floors only; none is release population evidence.
git log --follow --format='%h %ad %s' --date=short -- \
  lib/core/secure_storage/legacy_group_secret_storage_scrub.dart
git tag --sort=-creatordate
rg -n \
  'GROUP_SECRET_STORAGE_SCRUB_(START|SUCCESS|SKIPPED)|group_secrets_scrubbed' \
  lib/core/secure_storage/legacy_group_secret_storage_scrub.dart \
  test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart
rg -n \
  'flowEventLoggingEnabled = kDebugMode|_flowEventTestSink|if \(!flowEventLoggingEnabled\)' \
  lib/core/utils/flow_event_emitter.dart
rg -n \
  '_scrubCompletedSentinelKey|containsKey\(_scrubCompletedSentinelKey\)|secureKeyStore.write\(_scrubCompletedSentinelKey' \
  lib/core/secure_storage/legacy_group_secret_storage_scrub.dart
! rg -n 'group_secrets_scrubbed' \
  lib/features/account_migration/application/migration_secure_storage_registry.dart \
  lib/features/account_migration/application/migration_secure_storage_cleanup.dart
rg -n \
  'importVerifiedStagedDatabase|secureStorageStaging.promote' \
  lib/features/account_migration/application/account_migration_bundle_transfer.dart
rg -n \
  'openBackgroundIdentityDbReadTolerant|dbLoadGroupKeyByGeneration|hydrateBackgroundGroupKeyRow|return groupKeyRow' \
  lib/features/push/application/background_message_handler.dart
rg -n \
  'allowBackup="false"|dataExtractionRules|fullBackupContent' \
  android/app/src/main/AndroidManifest.xml
rg -n 'exclude domain=' \
  android/app/src/main/res/xml/data_extraction_rules.xml \
  android/app/src/main/res/xml/backup_rules.xml
rg -n \
  'first_unlock_this_device|excluded from iCloud/iTunes backups' \
  lib/core/secure_storage/flutter_secure_key_store.dart
rg -n 'DTR08-COMP-011|supported release floor|v96' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  lib/core/database/app_database_version.dart

# Interpretation gate: unless Security + Release also supplied an independently
# auditable population/database-replacement/release-declared-backup/recovery/
# compatibility package satisfying all four conditions above, record
# `Retained`; do not create a removal plan.

# Hygiene; expect no new analyzer issues or whitespace errors. With no edits,
# these verify the retained baseline rather than an implementation delta.
./scripts/check_flutter_analyze_strict.sh
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: N/A — acceptance-only retention is already source-proven; a
  fabricated RED would falsely imply an authorized production change.
- Green sentinel: startup call, scrub conversion/idempotence/skip tests, and
  repository secure-reference tests plus production group-upload secure-callback
  wiring remain green.
- Pre-existing dirty tree / known failure: record and preserve all unrelated
  user-owned changes; this plan should create no application delta.
- Environment blocker: external fleet telemetry is unavailable in the
  repository, but that is a retention condition rather than a closure blocker.
- Accepted unresolved security boundary: current background and Move Account
  database-replacement paths do not prove marker/data alignment. This prevents
  an operational-sufficiency claim but does not make scrub removal safe or
  convert this accepted-retention plan into an unapproved production fix.
- Scope drift: any proposal to remove/reorder the scrub or change storage,
  schema, crypto, native, Go, or persisted keys requires a new plan and owner
  evidence.

- [x] Requested retention is verified without inventing a causal RED.
- [x] Every preservation behavior has a named test or source proof.
- [x] Focused sentinels and the named curated gate pass.
- [x] No production, test, schema, native, Go, or harness file changes.
- [x] The four-part release/security evidence matrix is not overclaimed; absent
      a supplied auditable package, the recorded disposition is `Retained`.
- [x] Background-isolate and Move Account marker/data bypasses remain explicitly
      unresolved; closure does not claim they are repaired.
- [x] DTR08-COMP-011 remains retained with its exact future-plan trigger.
- [x] Strict analysis and `git diff --check` report no new issues.

## Handoff

- First causal RED command: N/A — acceptance-only; HEAD already retains and
  invokes the scrub.
- Contract size: six acceptance/preservation rows; no causal RED is invented.
- Preservation command:
  `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart`.
- Manual registration: none; all tests are auto-globbed and existing group
  repository coverage is already registered where applicable.
- Migration: none; no DB version or schema changes.
- Boundary closure: host-only retention evidence. The real crypto/device/Go
  proof in DTR08-COMP-011 belongs to a future removal plan, not this no-change
  disposition.
- Unresolved evidence: fleet completion, Move Account/database-replacement and
  any release-declared backup floor, marker x data/material recovery, background
  isolate ordering, zero legacy rows, and mixed-client crypto adoption.
  Therefore no follow-up removal plan is authorized now; create one only when
  owners supply them. A production correction for the marker/import/background
  boundary would require separate security authorization and a causal plan.

## Reviewer Findings

### Independent counterexample audit - 2026-07-27

- Initial verdict: `plan-fixes-required`; disposition `apply-plan-fixes`.
- Core bet: confirmed. The foreground scrub remains live and repository-held
  evidence does not authorize removal.
- Required corrections applied in place:
  - made TC-284-01 fail closed on the awaited foreground caller and exact order;
  - added the missing v96, v97, and v98 registry selectors;
  - corrected same-process/same-namespace tests that had been described as
    per-profile relaunch proof;
  - corrected debug/test flow events that had been described too much like
    population telemetry;
  - narrowed the scrub benefit to legacy plaintext conversion rather than
    dangling-reference recovery;
  - protected the secure group-upload completion callback and its production
    wiring ahead of the raw compatibility fallback;
  - recorded background-isolate legacy reads and post-startup Move Account
    database replacement with an unowned marker as explicit unresolved
    boundaries; and
  - narrowed generic backup prose to Move Account/database replacement plus any
    backup mechanism Release actually declares supported.
- Five-lens rerun after revision: L1 `clear`; L2 `clear`; L3 `clear`; L4
  `clear`; L5 `clear` for the acceptance-only no-removal decision. Blind-spot
  hits B-2/B-3/B-4/B-6/B-7/B-9 are closed by bounded source/tests or explicit
  unresolved disposition; B-1/B-5 are N/A because this plan changes no data or
  state, and B-8/B-10 are N/A because it makes no new device/cross-version
  behavior claim.
- Final verdict after revision: `ready`; disposition `execute` (run and record
  the acceptance-only retention contract, with no production edit).

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 CEST | Review closure | Plan 284 plus current foreground/background/import/reset, repository, migration, gate, and release-policy evidence | Five-lens rerun: L1-L5 `clear`; final verdict `ready`, disposition `execute` | Corrected startup audit, registry coverage, lifecycle/telemetry/recovery claims, raw callback bypass, background bypass, and marker/import alignment | No review blocker; operational hardening remains outside this accepted-retention scope | Run acceptance-only verification |
| 2026-07-27 CEST | Focused acceptance | Startup/order, scrub, repository, secure group-upload completion, v95-v104 registry, and release-policy evidence | TC-284-01 through TC-284-06 source/evidence audits passed; 17 focused tests passed | Foreground ordering, conversion/idempotence/skip behavior, secure-reference persistence/hydration/fail-closed handling, production upload callback wiring, and migration coverage remain preserved | No production correction authorized; marker/import/background gaps remain explicit | Run curated gate and hygiene |
| 2026-07-27 CEST | Curated preservation | Existing `groups` gate and registered Go tails | `./scripts/run_test_gates.sh groups`: 3,235 Flutter tests passed; Go bridge, node, relay-notification, toolchain-contract, and relay-server tails passed; exit 0 | The affected group/security family remains green without a Plan 284 code delta | Full `host-all` remains deferred to Wave 3 closure by cadence policy | Run strict analysis and protected-scope check |
| 2026-07-27 CEST | Closure | Analyzer, diff hygiene, and protected production/test/gate/native/Go scope | Strict analyzer: three reviewed suppressions, no issues; `git diff --check`: pass; 28 protected files byte-identical to the pre-execution snapshot | Acceptance-only retention is verified; repository evidence still cannot establish fleet completion or repair the accepted marker/import/background boundaries | Terminal disposition `Retained`; any fix or removal requires a separately authorized causal security plan | Complete — roadmap and index updated |
