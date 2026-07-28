# 297 - Application Resume and Posts Adapter Layer Relocation

Status: Plan-green / implementation-complete
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-18`)
Classification: implemented-and-verified
Closure tier: host + pinned available Android curated-lane execution

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-28 19:20 CEST | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | Current anchored graph fingerprint `5f2656692cadb1f9` surfaced the stabilized DTR-14/DTR-17 seams but not the DTR-12 manifest or Posts adapters. | Verify the exact boundary identities, callers, tests, and gates in current source. |
| 2026-07-28 19:26 CEST | Evidence Collector — source | DTR roadmap; Plans 288, 293, 295, 296; architecture checker/manifest; app lifecycle; Posts repositories/tests; gate scripts | The live guard is trustworthy at 182 dependency and 24 placement exceptions. Moving resume orchestration removes 17 exact rows; moving the two 99-line Posts Phase-3 adapters removes two placement rows without behavior changes. | Define causal destination proof and preservation sentinels. |
| 2026-07-28 19:34 CEST | Independent refute passes | lifecycle/P2P caller census; all 24 placement pins; C4; source locks | A bulk 24-file move is refuted by the roadmap's incremental rule. The pause handler is a separate iOS background-task boundary, and `P2PServiceImpl` has 62 import/source-lock consumers plus a transport boundary. | Keep pause, P2P, and all unrelated placement families out of Plan 297. |
| 2026-07-28 19:38 CEST | Planner | tier matrix; plan template; sufficiency checklist; current dirty-tree/device snapshot | Two independently gateable relocation rows satisfy both halves of DTR-18: resume behavior is byte-preserved; Posts adapters retain their real SQLite FFI tests. The initial host-only classification is corrected below from the real curated-gate dispatch. | Run the requested independent `$tdd-review`, apply only verified deltas, then execute. |
| 2026-07-28 19:52 CEST | Independent critical reviewer | review-profile Graphify query; all contract rows; exact import/path census; DTR-16/17 selectors; manifest arithmetic and gate registration | Core bet confirmed. Three proof gaps required tightening: pin byte/import-only fingerprints, advance DTR-16's removed scoped exception to an empty selector, and distinguish 33 directives, two live file reads, one semantic-negative literal, and `resumed -> _onResumed` dispatch. | Apply only those deltas in place; no scope expansion or fix-list artifact. |

## Problem And Evidence

- Behavior to improve: application-level resume orchestration must no longer
  live in `lib/core`, and concrete Posts persistence adapters must no longer
  live in a feature `domain` directory.
- Impact: the DTR-12 guard currently needs reviewed exceptions for these exact
  inversions. Leaving orchestration in `core` and concrete persistence in
  `domain` obscures ownership and makes future dependency direction harder to
  enforce.
- Confirmed current gaps:
  - `handle_app_resumed.dart` is under `lib/core/lifecycle` while importing 17
    feature application/domain libraries at
    `lib/core/lifecycle/handle_app_resumed.dart:8-24`. Its public
    `handleAppResumed` seam begins at `:59`, consumes the stabilized
    `P2PService` and `GroupMessageListener` facades at `:61,66`, and is
    application orchestration rather than a core primitive.
  - `ApplicationRoot` is the production lifecycle owner and imports/calls that
    seam at `lib/app/application_root.dart:81,1741`; production bootstrap is
    the only other live production importer, for
    `runGroupExitIntentRecoveryPass`, at
    `lib/app/bootstrap/production_application_bootstrap.dart:215`.
  - `ContactPresenceSnapshotRepositoryImpl` and
    `PostsPrivacySettingsRepositoryImpl` are concrete adapters under feature
    domain at
    `lib/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart:6`
    and
    `lib/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart:6`.
    Their construction is adjacent and callback-injected in
    `production_application_bootstrap.dart:1055-1079`.
  - The exact live architecture lane passes at 182 dependency violations, 24
    placement violations, and zero issues. The 17 resume rows and two Posts
    rows are owned by DTR-18 in
    `tool/architecture_guard/architecture_boundary_exceptions.json`.
- Existing coverage:
  - `./scripts/run_test_gates.sh architecture-boundaries` verifies a
    trustworthy exact-set manifest and rejects both new and stale rows.
  - `test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart`
    proves local recovery precedes the migration network gate.
  - `test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart` proves
    bridge health and parallel re-prime ordering.
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart` proves
    DTR-16 group recovery ownership and ordering.
  - `test/features/posts/phase3/contact_presence_snapshot_repository_test.dart`
    and `posts_privacy_settings_repository_test.dart` exercise the real
    migrations 027-029 on SQLite FFI and verify row mapping/persistence.
- Missing coverage: no current test requires the exact new destinations,
  forbids an old-path export/shim, proves only the reviewed 17+2 exception
  identities disappeared, or selects both Posts repository tests in the
  `posts` curated gate.
- Refuted findings:
  - “Move every one of the 24 repositories now” is refuted by the roadmap at
    `dead-code-and-technical-debt-removal-roadmap.md:507-510`; each relocation
    must be incremental and tied to an affected proof family.
  - “Move `handle_app_paused.dart` with resume for symmetry” is refuted as the
    minimum safe slice. Pause owns the iOS background assertion, grant probe,
    shipping kill switch, and bounded network deposit at
    `lib/core/lifecycle/handle_app_paused.dart:20-109`; that boundary requires a
    separate reviewed proof profile.
  - “Move `P2PServiceImpl` now because DTR-17 is green” is refuted as necessary
    for this increment. It would move three implementation/part files, rewrite
    62 import or source-lock consumers, and trigger transport/performance proof
    to eliminate only its eight current rows.
- Unresolved findings: none blocking. The remaining exception families are
  intentionally deferred below rather than claimed complete.
- Affected production, test, gate, and documentation files:
  `lib/core/lifecycle/handle_app_resumed.dart`,
  new `lib/app/lifecycle/handle_app_resumed.dart`,
  the two named Posts implementation paths and their new
  `lib/features/posts/data/repositories/**` destinations,
  direct import/source-lock consumers,
  `tool/architecture_guard/architecture_boundary_exceptions.json`,
  three exact-count predecessor tests, a new DTR-18 contract test,
  `scripts/run_test_gates.sh`, C4, this roadmap, and the index.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `5f2656692cadb1f9`; `freshness=current`,
  `confidence=anchored`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-18 layering relocation: exact current forbidden core-to-feature dependency identities and misplaced feature-domain repository implementation pins after DTR-14 DTR-16 DTR-17; architecture_guard manifest, P2PServiceImpl, GroupMessageListener, ApplicationBootstrap, boundary tests and core/feature gate registrations" --profile tdd --budget 700`.
- Anchors:
  `P2PServiceImpl` ->
  `lib/core/services/p2p_service_impl.dart:83`
  (`lib_core_services_p2p_service_impl_p2pserviceimpl`);
  `ApplicationBootstrap` ->
  `lib/app/bootstrap/application_bootstrap.dart:5`
  (`lib_app_bootstrap_application_bootstrap_applicationbootstrap`);
  `groupMessageListener` ->
  `test/shared/fakes/group_test_user.dart:68`.
- Surfaced proof/gate files:
  `p2p_service_impl_presence_cache_test.dart`,
  `p2p_service_impl_wake_attach_test.dart`, and core-family registration.
- Graph gaps requiring source search: the exact DTR-12 manifest rows,
  application lifecycle callers, Posts adapter destinations/tests, historical
  DTR-16/DTR-17 count locks, C4 ownership, and curated Posts registration.
- Reuse rule: these anchors may be handed to review/execution; all conclusions
  still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Move
  `lib/core/lifecycle/handle_app_resumed.dart` byte-for-byte to
  `lib/app/lifecycle/handle_app_resumed.dart`, then update every current Dart
  import and live source-path lock to the app-owned path. Pin the moved bytes
  to SHA-256
  `7b1c335dd6f55f82afa659b99373b9538db01c32dd2caa91393e6e1f5695f65c`,
  all 33 exact import directives, both live source-file reads, and the
  application-root `AppLifecycleState.resumed -> _onResumed` dispatch.
- Move the two byte-identical Posts Phase-3 adapters:
  - `features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart`
    -> `features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart`;
  - `features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart`
    -> `features/posts/data/repositories/posts_privacy_settings_repository_impl.dart`.
  Pin their moved bytes respectively to
  `d177b34246373d54d3ff3541603c465ae82b89550ea02f1dcdb30f6e30deee5b`
  and
  `302be89b18d29b3997e171a2859084eb44a8a5360c7e24e6b3d85c3b6883f718`.
- Update only their six current import sites: application root, production
  bootstrap, and the two direct repository tests. Normalize the three new
  production import URIs back to their old URIs before hashing and require
  application-root SHA-256
  `d7c4a02461be35951be84c5555e71bb3e9f386774126893baaf2addd4b1c542e`
  and production-bootstrap SHA-256
  `fb242e6d06086a87841a6a54393a2d1b93e40c57ee23c2b87a85daa7127f9717`;
  this proves those consumers changed only at the reviewed import lines.
- Remove exactly the 17 dependency exception identities whose source is the old
  resume path and exactly the two placement identities whose paths are the old
  Posts implementations. The post-change canonical inventory is 165 dependency
  and 22 placement exceptions; core package violations become 137, core
  relative violations remain 20, core-debug remains 92, and the eight exact
  P2P implementation rows remain.
- Add exact destination/no-shim/no-wrong-row-deletion proof. Advance the
  historical DTR-16 selector to require its now-removed resume-to-listener
  exception set to be empty while preserving its anti-retarget/no-DTR-16
  safeguards; preserve DTR-17's exact eight P2P identities. Register both Posts
  tests in `POSTS_TESTS`, and update C4 plus the DTR/index state.

Must preserve:

- Resume source bytes, public functions, parameters, constants,
  catch/continue policy,
  lifecycle ordering, local cleanup before account-migration gating, bridge/P2P
  health, inbox/retry/rejoin behavior, and event discrimination ->
  `handle_app_resumed_export_pause_recovery_test.dart`,
  `handle_app_resumed_parallel_reprime_test.dart`, and
  `handle_app_resumed_group_recovery_test.dart`.
- DTR-16 `GroupMessageListener` and DTR-17 `P2PService` public facades and exact
  component ownership ->
  `group_message_listener_decomposition_contract_test.dart` and
  `p2p_service_impl_composition_contract_test.dart`.
- Posts adapter constructors, row mapping, stream emission, and disposal ->
  exact moved-source fingerprints; the two direct repository tests additionally
  preserve their currently exercised mapping/persistence paths.
- Existing pause/iOS behavior and its exact eight exception identities ->
  no production or test edit to `handle_app_paused.dart` except a source census
  proving it stayed put.

Hard `Do not`:

- Do not leave an export, barrel, part, proxy, or compatibility shim at any old
  production path.
- Do not edit resume or Posts adapter behavior while moving files; import/path
  edits and documentation are the only production-byte differences allowed.
- Do not move `handle_app_paused.dart`, `P2PService`,
  `P2PServiceImpl`/its parts, any other repository implementation, or any test
  file in this plan.
- Do not change schema/migrations, database helpers, wire/native/Go/crypto code,
  public signatures, runtime ordering, profiles, or build defines.
- Do not add, retarget, or rebaseline an architecture exception. Remove only
  identities that the real checker proves stale after the moves.
- Do not weaken DTR-16/DTR-17 scoped facade/component assertions to a global
  count-only check.

Deferred / accepted difference:

- `handle_app_paused.dart` and its eight rows -> a later DTR-18 iOS
  lifecycle-boundary plan, because it owns real background assertion behavior.
- `P2PServiceImpl`, its two private parts, and its eight rows -> a later DTR-18
  transport/performance plan, because relocation touches the real Go-bridge
  implementation and 62 direct import/source-lock consumers.
- The remaining 22 placement exceptions and all other dependency exception
  families -> separately reviewed feature/boundary slices. High-risk media,
  identity, group, and post repositories retain their own persistence,
  secure-storage, projection, and queue proof floors.
- `lib/app/**` and feature `data/**` remain outside DTR-12's ranked four-layer
  rule. Plan 297 locks the exact destination paths; it does not broaden the
  architecture policy.

Dependencies:

- DTR-12/Plan 288 is Wave-accepted and supplies the exact fail-closed guard.
- DTR-14/Plan 293 is Plan-green/Wave-accepted and supplies the app composition
  and lifecycle owner.
- DTR-16/Plan 296 and DTR-17/Plan 295 are Plan-green and supply the stable
  listener/P2P facades consumed by the moved resume orchestration.

## Test Contract

Use zero empty cells. The causal rows are architectural path/ownership changes;
behavior rows are explicitly preserved-green sentinels.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-297-01 | Resume orchestration has exactly one app-owned source with the reviewed byte fingerprint; all 33 exact import directives and two live source reads use it; the root still dispatches `AppLifecycleState.resumed` to `_onResumed`; no old-core shim/barrel/part remains. | `test/unit/dtr18_layering_relocation_contract_test.dart::DTR-18 relocates resume orchestration to app without a core shim` | Host source/AST/hash contract / real repository | Causal RED after test addition: new app path absent and old core path present -> GREEN: exact new bytes and census exist, normalized production consumers retain pre-move hashes, and the old path is absent | Recreate an old core export/shim, restore one old directive/file read, alter the moved body/caller beyond imports, or remove lifecycle dispatch -> TC-297-01 red | `flutter test --no-pub test/unit/dtr18_layering_relocation_contract_test.dart --plain-name 'DTR-18 relocates resume orchestration to app without a core shim'`; AUTO `core-host-all` |
| TC-297-02 | Resume ordering, lifecycle discrimination, DTR-16 group recovery, DTR-17 P2P health, and migration gating are byte-preserved. | TC-297-01 moved-source and normalized-consumer hashes; `test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart::recovery runs BEFORE the migration network gate`; `test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart::bridge health check precedes the parallel re-prime`; `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart::PB264-18 resume recovery drains all before processing all and isolates errors` | GREEN sentinel / host unit+integration fakes and real source owners | GREEN on current source -> GREEN after path-only relocation with identical bytes plus the same event/order/negative assertions | Change any moved byte, move the migration gate before interrupted-export recovery, serialize re-prime behind inbox drain, or process exit intents before pending broadcasts -> hash or sentinel red | exact direct files; existing `ONE_TO_ONE_TESTS`, `GROUP_TESTS`, `move-feature`; AUTO `core-host-all` |
| TC-297-03 | The two concrete Posts Phase-3 persistence adapters retain exact reviewed bytes, live only under `features/posts/data/repositories`, all six live directives use those destinations, and neither old domain path is shimmed or excepted. | `test/unit/dtr18_layering_relocation_contract_test.dart::DTR-18 relocates the two Posts Phase-3 adapters to data` | Host source/AST/hash contract / real repository | Causal RED: new data paths absent and old paths present -> GREEN: exact new fingerprints/directive census exist, normalized production consumers retain pre-move hashes, and old paths are absent | Restore either domain implementation/export, point one caller to a wrong layer, or alter any moved byte/production consumer beyond the reviewed imports -> TC-297-03 red | direct test command; AUTO `core-host-all`; both existing persistence tests added once to `POSTS_TESTS` |
| TC-297-04 | The currently exercised contact-presence/privacy mapping and persistence paths stay green against migrations 027-029; the exact source fingerprints preserve the otherwise unexercised load/emit/dispose methods. | TC-297-03 moved-source fingerprints; `test/features/posts/phase3/contact_presence_snapshot_repository_test.dart::persists active friend snapshots`; `test/features/posts/phase3/posts_privacy_settings_repository_test.dart::persists updated nearby sharing state` | GREEN sentinel / exact source hash plus real in-memory SQLite FFI | GREEN on current source -> GREEN after byte-identical adapter moves and import-only test updates | Change any adapter byte, skip an exercised upsert, or corrupt the exercised row conversion -> hash or direct test red | `flutter test --no-pub test/features/posts/phase3/contact_presence_snapshot_repository_test.dart test/features/posts/phase3/posts_privacy_settings_repository_test.dart`; add both paths exactly once to `POSTS_TESTS`; AUTO `feature-host-all` |
| TC-297-05 | The exact manifest shrinks only by the reviewed 17 dependency and two placement identities: 165/22 current totals, 137 package-core, 20 relative-core, 92 debug, DTR-16's scoped resume-to-listener set empty, eight unchanged P2PImpl rows, zero new/stale issue. | `test/unit/architecture_boundary_checker_test.dart::canonical DTR-12 manifest pins 165 dependency and 22 placement exceptions`; `test/unit/dtr18_layering_relocation_contract_test.dart::DTR-18 removes only the reviewed exception identities`; DTR-16 empty-set/anti-retarget and DTR-17 eight-row structural selectors | Host architecture tool / real Git-visible repository and strict JSON manifest | Causal assertion RED when expected counts/identity delta are advanced before moves -> GREEN: trustworthy exact inventory, removed DTR-16 identity, and surviving named predecessor safeguards | Restore one removed row, remove an unrelated row, retarget the DTR-16 row to app, retain a stale row, add a new exception, or weaken a scoped safeguard -> TC-297-05 red | `./scripts/run_test_gates.sh architecture-boundaries`; canonical test is owned by the named lane; contract AUTO `core-host-all` |
| TC-297-06 | Application composition, runtime-root classification, test discovery, and affected host families compile against the new paths with no behavior/schema/native drift. | `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::DTR-14 production bootstrap owns each reachable phase exactly once`; `test/features/groups/application/group_message_listener_decomposition_contract_test.dart::TC-296-07 keeps DTR-16 registration and architecture scope exact`; `test/core/services/p2p_service_impl_composition_contract_test.dart::TC-295-08 registers the ownership contract in every affected lane without exception drift`; named policy/family gates | GREEN sentinel / real source, compiler, architecture/runtime-root/completeness tools | GREEN -> all exact owners, registrations, and affected core/feature paths remain GREEN after relocation | Leave one stale source lock/import, duplicate a curated registration, drop a runtime root, alter a facade, or introduce any analyzer error -> relevant sentinel/gate red | focused selectors; `1to1`, `groups`, `posts`, `move-feature`; `core-host-all`, `feature-host-all`; named policy lanes |

### Test Notes

- TC-297-01/03 parse exact import directives, not arbitrary literals; comments
  and plan prose are not live evidence. The resume census distinguishes the 33
  directives, two real source-file reads, and DTR-16's old-path literal retained
  only as a semantic expected-absent/anti-retarget assertion. The contract
  excludes itself from all literal scans.
- Source SHA-256 proves all unexercised moved behavior remains byte-identical.
  Normalized application-root/bootstrap hashes replace only the reviewed new
  URIs with old URIs before comparison, so unrelated consumer drift cannot hide.
- TC-297-05 enumerates every reviewed removed identity rather than relying only
  on new totals. The architecture lane separately proves that the current
  manifest equals the live inventory; the DTR-18 contract deliberately does
  not freeze every unrelated exception against later approved reductions.
- Posts repository tests intentionally remain at their current test paths.
  Moving tests would add gate/history churn without proving production
  ownership.

## Implementation Steps

1. Snapshot `git status --short`; record all pre-existing Wave 4 changes as
   user-owned. Re-run the current architecture lane and exact source/import
   census. Stop if the trustworthy baseline is not 182 dependency/24 placement
   with exactly 17 rows sourced by the old resume path and the two exact Posts
   placement rows.
2. Add `test/unit/dtr18_layering_relocation_contract_test.dart`, pin the three
   pre-move source hashes and two normalized production-consumer hashes, advance
   the causal assertions to the reviewed destinations/delta, and add the two Posts
   behavior files once to `POSTS_TESTS`. Run TC-297-01, TC-297-03, and
   TC-297-05 before production edits; record assertion-level RED for the
   missing destinations/present old rows. A missing test import/compile failure
   is not the intended RED.
3. Move `handle_app_resumed.dart` byte-for-byte into `lib/app/lifecycle/`.
   Update every current Dart import and exact source lock to the new path.
   Stop if a cycle, new non-app production caller, signature/body edit, or
   compatibility shim becomes necessary.
4. Move the two Posts implementation files byte-for-byte into
   `lib/features/posts/data/repositories/`. Update only application-root,
   production-bootstrap, and the two direct-test imports. Stop if a schema,
   helper, constructor, callback, stream, or test-location edit becomes
   necessary.
5. Delete only the 17+2 manifest rows that the real checker proves stale.
   Advance the canonical and predecessor global totals to 165/22 while
   changing DTR-16's scoped resume-to-listener exception selector to empty and
   retaining its anti-retarget/no-DTR-16 checks; preserve DTR-17's exact eight
   P2P assertions.
   Update C4, the DTR-18 registry/authorization receipt, and the index.
6. Run focused GREEN and one representative mutation re-red for each causal
   contract: temporary old-core resume shim, temporary old-domain Posts
   implementation, and temporary restored stale manifest row. Remove every
   mutation and re-run the focused GREEN set.
7. Run exact lifecycle/Posts/predecessor sentinels, affected curated lanes,
   justified core/feature families, policy/discovery, strict analysis, diff
   hygiene, and one incremental Graphify refresh.

## Reviewer Findings

Verdict: `plan-fixes-required` before revision; `execution-ready` after three
verified pre-execution corrections and one closure-audit correction below.

- High — the original direct tests did not prove byte-identical moves or the
  unexercised Posts stream/dispose paths. Applied: three exact moved-source
  hashes and normalized import-only hashes for both production consumers.
- High — DTR-16 currently requires the exact exception that this move removes.
  Applied: require the scoped selector to become empty while preserving the
  anti-retarget and no-DTR-16-exception safeguards.
- Medium — the original caller proof conflated imports, source reads, and a
  semantic-negative old-path literal, and did not pin lifecycle dispatch.
  Applied: exact 33-directive/two-file-read census plus structural
  `resumed -> _onResumed` proof.
- Medium — the execution draft described TC-297-05 as a frozen full-manifest
  set-difference snapshot, but its contract only pinned totals, scoped absence,
  and selected survivors. Applied: enumerate all 17 reviewed dependency
  identities, anchor them to the byte-preserved source's feature imports, and
  state the canonical live-inventory guard's separate wrong-row role without
  freezing unrelated future exception reductions.

All reviewed arithmetic, destinations, gate registrations, predecessor
selectors, and the decision to combine these two small relocation rows were
confirmed. Execution corrected one proof-profile statement: the `posts`
curated gate dispatches five existing `integration_test/**` suites and
therefore requires an explicit live device even though Plan 297 makes no
platform-behavior claim. No broader relocation or new test tier was added.

## Risks And Blind Spots

- Wrong destination hidden by the guard's unclassified `app/**` and `data/**`
  paths -> TC-297-01/03 pin exact destinations and forbid old shims.
- Wrong-row deletion masked by the expected total -> TC-297-05 enumerates all
  17 reviewed dependency identities plus the two placement paths; the
  canonical live-inventory lane rejects an unrelated stale/missing row, while
  DTR-16/DTR-17 selectors preserve their named survivor identities.
- Lifecycle / derived-state durability: no state mechanism changes; resume
  reconstruction/recovery ordering remains guarded by TC-297-02 and the full
  lifecycle directory.
- Sibling-surface consistency: pause remains deliberately asymmetric and
  unchanged; its source/path and eight exception rows are preservation
  assertions in TC-297-01/05.
- Destructive-action side effects: no deletion behavior changes. The only
  production removals are old source paths after byte-identical moves; new-path
  existence, old-path absence, compile proof, and behavior sentinels guard
  against code loss.
- Invariant re-verification under new transitions: no new runtime transition is
  introduced; TC-297-02 re-proves resume re-entry, ordering, and failure
  isolation.
- SQLite fixture strength: the direct tests prove current mapping/persistence,
  not SQLCipher migration or durability. No schema/migration/SQLCipher claim is
  made.

## Device / Relay Proof Profile

- Production closure remains host-causal, but the required `posts` curated
  lane also dispatches its five existing fake `integration_test/**` suites.
  Run that lane with `FLUTTER_DEVICE_ID=emulator-5554`; this pins a target
  available in the execution-time matrix and avoids an interactive selector.
  Plan 297 makes no Android-, native-, relay-, or OS-boundary behavior claim.
- Live discovery found physical Android `21071FDF600CSC` plus Android emulators
  `emulator-5554` and `emulator-5556`. Only `emulator-5554` is required for the
  existing curated-lane replay; unavailable device/version bands cannot block
  this plan.
- Relay startup/readiness, identities, cleanup, and diagnostics: N/A because no
  network/device integration behavior is exercised or claimed.

## Rollback / Fallback

- Each relocation is independently reversible by restoring its old file path,
  exact import directives/source reads, and only its reviewed manifest rows.
  Restore the corresponding 182/24-era structural expectations at the same
  time; never leave a compatibility shim or dual implementation.
- There is no data, schema, migration, wire, or native rollback. If any
  byte/import-only fingerprint cannot be preserved, stop and replan that slice
  instead of relaxing the contract.

## Gate Cadence

- Per-plan closure: causal DTR-18 contract; exact lifecycle and Posts
  sentinels; DTR-16/DTR-17 structural selectors; curated `1to1`, `groups`,
  `posts`, and `move-feature`; justified `core-host-all` and
  `feature-host-all`; architecture/runtime-root/completeness; analyzer,
  hygiene, and incremental Graphify.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure` once after
  the Wave 4C batch (DTR-16, DTR-17, and reviewed DTR-18 increments) is
  Plan-green, and once again at final rollout/release closure.
- `performance-host` is not a Plan 297 gate: no implementation logic,
  scheduling hop, P2P implementation, or performance threshold changes.
- Shared tests outside feature/core globs: the five existing Posts fake
  integration suites run through the pinned curated lane. Strict
  `flutter analyze` also compiles their new URI; Plan 297 makes no new device
  or integration-behavior claim.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated dirty-tree changes.
git status --short

# Current trustworthy baseline before edits: exit 0, 182/24, zero issues.
./scripts/run_test_gates.sh architecture-boundaries

# Causal RED after adding/advancing tests but before production moves:
# each command must exit non-zero for missing new destination/present old path.
flutter test --no-pub \
  test/unit/dtr18_layering_relocation_contract_test.dart \
  --plain-name 'DTR-18 relocates resume orchestration to app without a core shim'
flutter test --no-pub \
  test/unit/dtr18_layering_relocation_contract_test.dart \
  --plain-name 'DTR-18 relocates the two Posts Phase-3 adapters to data'

# Focused GREEN after implementation: exit 0, zero failed tests.
flutter test --no-pub test/unit/dtr18_layering_relocation_contract_test.dart
flutter test --no-pub \
  test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart \
  test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart \
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
flutter test --no-pub \
  test/features/posts/phase3/contact_presence_snapshot_repository_test.dart \
  test/features/posts/phase3/posts_privacy_settings_repository_test.dart

# Stable predecessor/source-owner sentinels: exit 0, exact selectors green.
flutter test --no-pub \
  test/features/groups/application/group_message_listener_decomposition_contract_test.dart \
  --plain-name 'TC-296-07 keeps DTR-16 registration and architecture scope exact'
flutter test --no-pub \
  test/core/services/p2p_service_impl_composition_contract_test.dart \
  --plain-name 'TC-295-08 registers the ownership contract in every affected lane without exception drift'
flutter test --no-pub \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --plain-name 'DTR-14 production bootstrap owns each reachable phase exactly once'

# Curated affected lanes: exit 0; Posts output must select both repository tests.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=emulator-5554 ./scripts/run_test_gates.sh posts
./scripts/run_host_test_gates.sh move-feature \
  --batch-flutter --concurrency 4 --reporter failures-only

# DTR-01 deliberately reports an unstaged tracked lib rename as
# `tracked-path-deleted`, independently of the runtime-root manifest. Build a
# copied index containing only Plan 297's approved moves for the named
# runtime-root proof.
DTR18_INDEX_DIR=$(mktemp -d)
DTR18_INDEX_PATH="$DTR18_INDEX_DIR/index"
cp "$(git rev-parse --git-path index)" "$DTR18_INDEX_PATH"
GIT_INDEX_FILE="$DTR18_INDEX_PATH" git add -A -- \
  lib/core/lifecycle/handle_app_resumed.dart \
  lib/app/lifecycle/handle_app_resumed.dart \
  lib/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart \
  lib/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart \
  lib/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart \
  lib/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart

# The core family includes repository guards that intentionally reject a
# redirected GIT_INDEX_FILE. Back up the real index, admit only the six move
# endpoints for that ordinary-environment proof, and restore it byte-for-byte
# even when the gate fails.
DTR18_REAL_INDEX=$(git rev-parse --git-path index)
DTR18_REAL_INDEX_BACKUP=$(mktemp)
cp "$DTR18_REAL_INDEX" "$DTR18_REAL_INDEX_BACKUP"
trap 'cp "$DTR18_REAL_INDEX_BACKUP" "$DTR18_REAL_INDEX"' EXIT INT TERM
DTR18_CORE_STATUS=0
git add -A -- \
  lib/core/lifecycle/handle_app_resumed.dart \
  lib/app/lifecycle/handle_app_resumed.dart \
  lib/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart \
  lib/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart \
  lib/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart \
  lib/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart \
  || DTR18_CORE_STATUS=$?
if [ "$DTR18_CORE_STATUS" -eq 0 ]; then
  ./scripts/run_host_test_gates.sh core-host-all \
    --batch-flutter --concurrency 4 --reporter failures-only \
    || DTR18_CORE_STATUS=$?
fi
cp "$DTR18_REAL_INDEX_BACKUP" "$DTR18_REAL_INDEX"
cmp "$DTR18_REAL_INDEX_BACKUP" "$DTR18_REAL_INDEX"
trap - EXIT INT TERM
rm "$DTR18_REAL_INDEX_BACKUP"
test "$DTR18_CORE_STATUS" -eq 0

# Remaining justified affected family: exit 0 and zero failed tests.
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Policy/discovery: exit 0; exact 165/22, no drift/unclassified test.
./scripts/run_test_gates.sh architecture-boundaries
GIT_INDEX_FILE="$DTR18_INDEX_PATH" ./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check
rm -r "$DTR18_INDEX_DIR"

# Hygiene and graph: zero analyzer issues/new whitespace errors; refresh exits 0.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-297-01/03 fail because the new app/data paths do not exist
  and the old core/domain paths plus exact manifest rows still exist.
- Green sentinels: TC-297-02/04/06 preserve resume, Posts persistence,
  stabilized predecessor facades, and composition/discovery behavior.
- Pre-existing dirty tree / known failure: the execution snapshot is heavily
  dirty from the integrated DTR-13 through DTR-17 work. Those changes are
  user-owned baseline; only Plan 297's reviewed path/import/manifest/test/gate/
  C4/roadmap/index delta is attributable here. Any unrelated failure is
  recorded separately and cannot be hidden as expected RED.
- Runtime-root worktree interpretation: DTR-01 correctly reports any unstaged
  tracked `lib/**.dart` rename as `tracked-path-deleted`; that signal is
  independent of runtime-root declarations. The named runtime-root proof uses
  a copied temporary index containing only the three approved Plan 297 moves.
  Because the core family deliberately rejects redirected Git-index
  environments, its final ordinary-environment proof temporarily admits only
  the six move endpoints to the real index and restores the original index
  byte-for-byte before returning.
- Environment blocker: none. The existing Posts integration harness requires
  a device target, and available Android emulator `emulator-5554` is pinned;
  Plan 297 still claims no OS/device boundary behavior.
- Scope drift: any behavior-body, schema/helper, native/Go/wire/crypto,
  pause/P2P, unrelated repository, new exception, or compatibility-shim edit
  blocks completion and requires replanning.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Both Posts tests are registered once in the curated `POSTS_TESTS` array;
      the new unit contract is AUTO-discovered by `core-host-all`.
- [x] The real architecture lane is trustworthy at exactly 165 dependency and
      22 placement violations with zero issues.
- [x] `flutter analyze` has zero issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/unit/dtr18_layering_relocation_contract_test.dart --plain-name 'DTR-18 relocates resume orchestration to app without a core shim'`.
- Preservation command:
  `flutter test --no-pub test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart test/core/lifecycle/handle_app_resumed_parallel_reprime_test.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`.
- Manual registration: both existing Posts repository tests are verified
  exactly once in `POSTS_TESTS`; the new DTR-18 contract is AUTO under
  `core-host-all`.
- Migration: none.
- Boundary closure: host-causal path/AST, lifecycle, real SQLite FFI Posts
  repositories, exact architecture manifest, affected curated/family gates,
  plus the pinned available-Android replay already owned by the Posts gate.
- Unresolved evidence: none blocking; pause, P2P implementation, and every
  other exception family are explicit later DTR-18 work.
- Final classification: `Plan-green / implementation-complete`. Wave 4C
  aggregate `host-all` and final-release closure remain separately owned.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-28 19:52 CEST | review complete | Plan 297; DTR-16/17 selectors; exact source/import/manifest census | independent verdict `plan-fixes-required`; three minimal deltas applied in place | hashes, empty DTR-16 selector, exact census/dispatch now close all reproduced counterexamples | none | add causal test and capture RED |
| 2026-07-28 19:57 CEST | preservation baseline | three named resume suites; two Posts Phase-3 repository suites | combined `flutter test --no-pub ...`; exit 0, 33 tests passed | ordering/failure-isolation and real SQLite FFI mapping/persistence are green before any production move | none | compile causal contract and capture intended RED |
| 2026-07-28 20:01 CEST | causal RED | new DTR-18 contract | `flutter test --no-pub test/unit/dtr18_layering_relocation_contract_test.dart`; exit 1, all three cases reached intended assertions | TC-297-01: new resume path false; TC-297-03: old Posts path true; TC-297-05: actual 182 vs expected 165 | intended RED, no compile/import failure | perform byte-identical moves and reviewed metadata rewrites |
| 2026-07-28 20:08 CEST | implementation + focused GREEN | three byte-identical relocations; 39 import rewrites plus two source reads; manifest; structural sentinels; Posts gate registration; C4 | DTR-18 contract +3; architecture lane +6 at 165/22 and zero issues; DTR-14/16/17 selectors and 33-test preservation set all exit 0 | exact hashes/censuses and predecessor survivors are green; three representative mutations each re-red and were removed | none | run curated and affected-family gates |
| 2026-07-28 20:14 CEST | curated gates / proof-profile correction | `1to1`; `groups`; `posts`; `move-feature`; this plan | `1to1` +2464 and relay gate green; `move-feature` 50 paths/+497/1 skipped green; first `groups` aggregate had one load-sensitive ML-008 failure whose exact rerun passed; initial unpinned `posts` run passed its +7 host tests then reached the device selector and was quit | real gate dispatch disproves the plan's host-only execution assumption; no DTR-18 product assertion failed | pin available `emulator-5554`; rerun complete Posts and Groups aggregates |
| 2026-07-28 20:50 CEST | curated/family closure | pinned `posts`; repeated `groups`; `core-host-all`; `feature-host-all` | pinned Posts host + all five integration suites green; repeated Groups +3265 plus Go/relay tails green; core 366 paths/+2843 and feature 811 paths/+8441/1 declared skip green | an initial ordinary core run correctly exposed unstaged-rename drift; a redirected-index attempt was rejected by repository guards and is not evidence; the accepted ordinary-environment run admitted only the six endpoints and restored the real index byte-for-byte | none | close policy and graph evidence |
| 2026-07-28 20:50 CEST | policy, hygiene, graph, closure | architecture/runtime-root/completeness; analyzer; graph; plan/roadmap/index | architecture +6 at trustworthy 165/22/zero issues; runtime roots +20 with all three destinations `main-reachable`, trustworthy and drift-free; completeness 1358/1358; `flutter analyze` zero issues; `git diff --check` clean; incremental graph refresh wrote 63,518 nodes/95,277 edges and refreshed the TDD overlay | no runtime-root declaration or exception was needed; affected-context query resolves the new app/data paths to their expected consumers | none | Plan-green; defer only Wave 4C aggregate `host-all` and later DTR-18 increments |
| 2026-07-28 21:05 CEST | independent closure counterexample audit | Plan 297 wording; DTR-18 contract; manifest/import/runtime-root census | audit found and corrected one 39-import-plus-two-read wording error and one overstrong full-manifest-snapshot claim; the contract now enumerates all 17 reviewed dependency identities and anchors them to the moved source | focused contract +3, architecture +6 at 165/22/zero issues, and strict analysis are green after the correction; final incremental graph is 63,520 nodes/95,279 edges with 1,459 files/14,217 named tests in the overlay | no implementation issue or remaining closure mismatch found | complete |
