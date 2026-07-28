# 288 - DTR-12 architecture and layer boundary guard

Status: Plan-green — implementation-complete
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-12`)
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-12` / Wave 4A — Boundaries and composition roots
Date: 2026-07-27

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | The current graph fingerprint is `8f78bbbd5362f189`; it anchored `scripts/run_test_gates.sh` but had no deterministic DTR-12 proof candidate. | Verify the roadmap, layer model, current imports, tool precedents, tests, and gate registrations in source. |
| 2026-07-27 | Evidence Collector — source | roadmap; `C4/components.md`; root `lib/`; DTR-01/DTR-02 tools, manifests, tests, and wrappers | DTR-12 is the only unblocked Wave-4A candidate. The current tree has 174 core-to-feature directives, eight additional upward layer directives, and 24 feature-domain repository implementation paths. | Define the minimum source-backed rule set and pin the exact current multiset. |
| 2026-07-27 | Independent refute pass | all `lib/core/**/*.dart`; feature domain/application imports; shared widgets; historical DTR snapshot | The supplied count `154` includes only package URIs and misses 20 relative imports. The roadmap's historical `175` count is stale by one after DTR-03 removed `contact_request_listener.dart`. Shared widgets are presentation and add four more application-to-presentation exceptions. | Record the corrected 206-entry baseline and bypass cases in the Test Contract. |
| 2026-07-27 | Planner | tier matrix; plan template; gate cadence; current clean worktree | This is deterministic repository tooling. Exact host unit/process proof plus a first-class `architecture-boundaries` lane is the causal closure; no app family, database, simulator, device, native, relay, or performance proof applies. | Apply the blocking sufficiency checklist, then run the requested independent review. |
| 2026-07-27 | Independent reviewer | Plan 288; DTR-01/DTR-02 CLI and identity precedents; Sims major manifest/contracts; host-family registration | Verdict `plan-fixes-required`: normalized architectural identity, semantic placement detection, release-required Sims registration, a coherent fixture-capable CLI, and current test-family wording were missing. | Apply only those reliability deltas, rerun the five review lenses, and hand the repaired plan to execution. |
| 2026-07-27 | Planner / closer | repaired Scope, Test Contract, implementation steps, gate cadence, and acceptance commands | All blocking review findings are resolved without widening DTR-12 into debt repair or undocumented layer policy. Verdict `ready`; classification remains `implementation-ready`. | Execute TC-DTR12 RED/GREEN/mutation proof and close the focused gates. |

## Problem And Evidence

- Behavior to improve: a repository change must fail a machine gate when it
  introduces a new dependency against the documented layer direction or puts a
  new concrete repository implementation below a feature `domain/` directory.
  Existing debt is reviewed and pinned; DTR-12 does not repair or relocate it.
- Impact: the C4 model names presentation, application, domain, and core
  layers at `C4/components.md:13`, `:202`, `:361`, and `:447`, but no current
  tool or named gate turns that direction into an admission rule. Later
  DTR-13, DTR-15, and DTR-18 work can therefore add more inversions while
  appearing locally green.
- Confirmed current gap and ownership:
  - the DTR-12 registry row requires “exact boundary-tool tests; current
    exceptions pinned”; it entered this planning turn as the unblocked
    candidate and is now linked to this plan at
    `dead-code-and-technical-debt-removal-roadmap.md:227`;
  - Wave 4A requires new forbidden dependencies to fail at `:435`, while
    DTR-18—not DTR-12—owns exception reduction at `:464-472`;
  - DTR-13 and DTR-15 depend directly on DTR-12 at `:198-203` and `:228-233`.
- Confirmed layer policy:
  - permitted direction is presentation -> application -> domain -> core;
    same-layer and downward dependencies remain permitted by this first guard;
  - `lib/shared/widgets/**` is presentation because the C4 presentation block
    contains `SHARED WIDGETS` at `C4/components.md:178-198`;
  - root-package `infrastructure/`, `data/`, generated, native, vendor, and
    nested-package directories have no cited ordering in this four-layer
    contract and are not guessed into DTR-12.
  - the later production audit explicitly names feature-first
    presentation/application/domain/data layering and says concrete
    implementations must leave domain at
    `Test-Flight-Improv/production-stack-layer-audit.md:120-143`; older C4
    listings of current repository implementations describe debt rather than
    overriding that relocation direction.
- Confirmed current exception inventory:
  - 174 exact core-to-feature Dart URI directives across 43 core files:
    154 use `package:flutter_app/features/...` and 20 use relative
    `../../features/...` or `../../../features/...`; all are imports on current
    HEAD. Relative examples are
    `lib/core/bridge/bridge.dart:3-4`,
    `lib/core/services/p2p_service_impl.dart:23-30`, and
    `lib/core/database/helpers/group_sync_receipts_db_helpers.dart:3`.
  - one domain-to-application import at
    `lib/features/account_migration/domain/models/migration_database_manifest.dart:2`;
    three application-to-feature-presentation imports at
    `lib/features/settings/application/download_profile_picture_use_case.dart:11`,
    `upload_profile_picture_use_case.dart:11`, and
    `lib/features/conversation/application/chat_message_listener.dart:24`;
    four application-to-shared-presentation imports at
    `direct_private_media_viewer_controller.dart:12`,
    `media_viewer_repository_resume_store.dart:3-4`, and
    `lib/features/groups/application/group_private_media_lifecycle.dart:14`.
  - 24 exact `lib/features/*/domain/**/*_repository_impl.dart` paths; the
    roadmap's audit records the same placement debt at
    `dead-code-and-technical-debt-removal-roadmap.md:150-153`.
  - total pinned baseline: 182 forbidden dependency identities plus 24
    forbidden placement identities = 206 exceptions.
- Existing coverage:
  - DTR-01 proves the established deterministic read-only `report/check`
    pattern in `test/unit/runtime_root_inventory_test.dart` and the
    `runtime-roots` lane at `scripts/run_test_gates.sh:1238-1246,1563-1569`;
  - DTR-02 proves strict identity manifests and AST-backed policy scanning in
    `test/unit/analyzer_suppression_ratchet_test.dart`;
  - neither tool classifies layer direction or repository placement.
- Missing coverage: no test currently rejects package/relative/conditional
  imports, exports, or parts across the forbidden direction; no test rejects a
  new domain repository implementation; no exact manifest owns today's
  exceptions; and no first-class boundary lane exists.
- Refuted findings:
  - “154 is the complete core-to-feature baseline” is refuted by 20 current
    relative URI imports. The exact current value is 174.
  - “The roadmap's 175 is the current baseline” is refuted by current source
    and the historical diff: DTR-03 removed the sole old
    `lib/core/services/contact_request_listener.dart` edge, leaving 174.
  - “Only feature-local presentation paths count as presentation” is refuted
    by C4's explicit placement of shared widgets inside the presentation block.
- Unresolved findings: none blocking. The ordering of `infrastructure/` and
  `data/` is intentionally outside this source-backed first rule; broadening it
  requires a later architecture decision rather than a DTR-12 guess.
- Affected implementation, test, gate, and documentation files:
  `tool/architecture_guard/**`,
  `test/unit/architecture_boundary_checker_test.dart`,
  `scripts/check_architecture_boundaries.sh`,
  `scripts/test/architecture_boundary_checker_contract_test.sh`,
  `scripts/run_test_gates.sh`,
  `tool/sims/critical_features.json`,
  `test/tool/sims/sims_manifest_test.dart`,
  `scripts/test/sims_major_plan_contract_test.sh`,
  `Test-Flight-Improv/test-gate-definitions.md`, this plan, the roadmap, and
  `Test-Flight-Improv/00-INDEX.md`. No `lib/`, package dependency, generated,
  database, native, or application test file is in scope.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `8f78bbbd5362f189`; `current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-12 architecture layer boundary checker patterned after tool/runtime_roots/runtime_root_inventory.dart and tool/analyzer_guard/analyzer_suppression_ratchet.dart, with exception manifest, exact tests, and run_test_gates.sh lane" --profile tdd --budget 700`.
- Anchors:
  `TRANSPORT_TESTS` -> `scripts/run_test_gates.sh:664`; the deterministic
  overlay returned no direct boundary-tool proof candidate.
- Surfaced proof/gate files: `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: DTR-01/DTR-02 tool APIs and manifests,
  C4 layer placement, relative imports, shared-widget imports, repository
  implementation paths, exact unit coverage, and the DTR roadmap state.
- Reuse rule: these anchors may be handed to review/execution; all conclusions
  still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a pure Dart, AST-backed checker library and CLI under
  `tool/architecture_guard/`. Scan only Git-visible, non-ignored current Dart
  files below the root application package's `lib/`; subtract Git-reported
  deletions, reject unsafe/enumeration/symlink/parse state, and keep scan order
  deterministic.
- Resolve the root package name from `pubspec.yaml`. Structurally inspect
  import, export, part, and conditional URI branches. Resolve exact same-package
  `package:` and relative URIs with POSIX normalization and case-sensitive
  current-path validation; reject a local URI that escapes, uses a query,
  fragment, unsafe scheme, or cannot be trusted.
- Classify sources/targets as:
  `core` (`lib/core/**`), `domain`, `application`, or `presentation`
  (`lib/features/<feature>/<layer>/**`), with `lib/shared/widgets/**` as
  presentation. Independently forbid any core dependency into
  `lib/features/**`, including a future unclassified feature subpath.
- Reject a dependency when the source is lower than the target in
  core -> domain -> application -> presentation. Permit same-layer and
  downward dependencies. Cross-feature identity alone is not forbidden.
- Reject a feature-domain file when its path matches
  `**/*_repository_impl.dart` or its AST declares a concrete
  `*RepositoryImpl` class or another concrete class that implements/extends a
  `*Repository` contract. Emit one exact placement identity per path. This
  prevents a filename-only rename from bypassing the guard while leaving
  repository interfaces and abstract contracts permitted. DTR-18 chooses the
  eventual destination.
- Add a strict schema-1
  `tool/architecture_guard/architecture_boundary_exceptions.json` with exact
  top-level keys `schemaVersion`, `policy`, `dependencyExceptions`, and
  `placementExceptions`. Dependency rows contain exact rule, source/target
  layer, canonical source, directive kind/conditional-branch kind, canonical
  normalized target, count `1`, owner, reason, evidence, and condition.
  Literal URI and line are report diagnostics, not exception identity.
  Placement rows contain exact rule, path, owner, reason, evidence, and
  condition. Unknown/missing keys, duplicates, wildcard/glob or unsafe paths,
  blank metadata, derived-layer mismatch, and count other than one are invalid.
- Seed exactly 182 dependency rows and 24 placement rows. Existing rows are
  exceptions, not approvals. Core-debug rows are owned by `DTR-13 / DTR-18`;
  all other rows are owned by `DTR-18`. Every condition says to remove the row
  with the exact dependency/placement under its owner and never substitute a
  new exception silently.
- Exact-set compare actual and reviewed identities. A new/duplicated/relocated
  violation or removed violation with a stale row makes `check` fail.
  Invalid metadata/schema makes the result untrustworthy; valid metadata
  changes remain visible in review. Line numbers and equivalent literal URI
  spellings are diagnostics, never identity.
- Provide deterministic text/JSON `report` and `check` modes with exit `0` for
  a trustworthy exact check (and trustworthy report even with drift), `1` for
  trusted policy drift, and `2` for usage/configuration/Git/I/O/parse state
  that makes the result untrustworthy. The CLI may accept validated
  `--repo-root` and `--manifest` read-only overrides so its real process
  contract is testable against disposable Git fixtures. Provide no update,
  generate, accept, fix, or manifest-writing mode.
- Add a no-argument `architecture-boundaries` lane that runs the exact unit
  file first and the real repository check second, propagating the first
  failure. Its wrapper supplies the fixed repository root/manifest and accepts
  no arguments.
- Register `architecture.boundaries` as a required, active,
  automation-ready `major`/`infra` Sims capability whose command is the named
  lane. Pin the typed row and its inclusion in the unfiltered release-major
  plan with the existing Sims manifest and major-plan contracts.

Must preserve:

- DTR-01 remains advisory and unchanged ->
  `./scripts/run_test_gates.sh runtime-roots`.
- Strict analyzer behavior and the existing DTR-02 suppression inventory remain
  unchanged -> `./scripts/check_flutter_analyze_strict.sh`.
- All root application production bytes remain unchanged ->
  `git diff --exit-code -- lib`.
- Existing app gates and all pre-existing Sims capability rows remain
  unchanged. Package dependencies, generated outputs, schemas, and platform
  code remain unchanged.

Hard `Do not`:

- Do not repair, relocate, rename, re-export, or rewrite any of the 206 current
  violations in DTR-12.
- Do not introduce a broad directory allowlist, regex-only source scanner,
  line-number identity, ignored-file exemption, auto-generated manifest, or
  write/update/accept mode.
- Do not classify tests, plans, generated Graphify output, native/vendor code,
  nested packages, `infrastructure/`, or `data/` as one of the root app's four
  layers without a separately source-backed contract.
- Do not run `core-host-all`, `feature-host-all`, performance, simulator,
  device, relay, SQLCipher, or full `host-all` as a DTR-12 per-plan gate.

Deferred / accepted difference:

- DTR-13 owns composition-root movement, DTR-15 owns conversation-controller
  extraction, and DTR-18 owns decreasing the exception manifest. DTR-12 only
  makes additions and removals explicit.
- A reviewer may still approve a future new exception by changing the manifest,
  but it cannot be silent: the exact normalized source/target/directive identity
  or path and its
  owner/reason/condition must appear in a reviewed diff.
- `infrastructure/` and `data/` ordering is deferred to a later architecture
  contract because the cited C4 four-layer model does not place them.

Dependencies:

- DTR-01 is Wave-accepted; Wave 3 is accepted and the roadmap records DTR-12
  planning unblocked. There is no open DTR-12 owner decision.

## Test Contract

Use zero empty cells. All cases are host tooling tests with temporary
Git-backed repositories or the read-only real tree.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR12-01 | The canonical manifest exactly owns the current 174 core-to-feature, eight other upward-layer, and 24 domain repository-implementation violations, with no new or stale row. | `test/unit/architecture_boundary_checker_test.dart::canonical DTR-12 manifest pins 182 dependency and 24 placement exceptions` | Host tool / real read-only repository plus strict manifest | HEAD has no checker/manifest; after a minimum compile scaffold the test assertion is RED on an empty inventory -> trustworthy exact result, totals 182/24/206, core split 154 package + 20 relative, and exit `0` | Remove any row, add an unreviewed import/placement fixture, or restore the historical 175 assumption -> TC-DTR12-01 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'canonical DTR-12 manifest pins 182 dependency and 24 placement exceptions'`; exact direct path and `architecture-boundaries` lane |
| TC-DTR12-02 | Structural URI discovery catches package and relative import/export/part/part-of plus every conditional branch without matching comments/strings, normalizes exact local targets independent of line movement, and treats package/relative spellings of the same edge as one identity. | `test/unit/architecture_boundary_checker_test.dart::discovers and normalizes package relative export part and conditional dependencies without lexical decoys` | Host unit / temporary root package with package, relative, multiline, conditional, comment, string, line-shift, and spelling-equivalent fixtures | Compile scaffold returns no edges -> exact normalized identities and counts; external packages and `dart:` remain outside policy | Replace AST traversal with regex, ignore a configuration URI/export/part/part-of, key by line/literal spelling, or skip relative normalization -> TC-DTR12-02 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'discovers and normalizes package relative export part and conditional dependencies without lexical decoys'`; exact direct path and named lane |
| TC-DTR12-03 | The layer matrix rejects core-to-any-feature, core/domain/application-to-presentation (including shared widgets), domain-to-application, while allowing same-layer and downward imports. | `test/unit/architecture_boundary_checker_test.dart::enforces the documented four-layer direction and shared-widget presentation alias` | Host unit / complete source/target matrix fixture | Scaffold permits all -> every forbidden matrix cell reports its derived layers/rule while allowed cells remain empty | Remove shared-widget alias, allow an unclassified feature target, reverse rank comparison, or ban a permitted downward/same-layer edge -> TC-DTR12-03 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'enforces the documented four-layer direction and shared-widget presentation alias'`; exact direct path and named lane |
| TC-DTR12-04 | A new concrete repository implementation in feature domain is forbidden even after a filename rename; repository interfaces, abstract contracts, and implementations outside domain are not placement violations. | `test/unit/architecture_boundary_checker_test.dart::pins concrete domain repository implementations semantically without widening relocation policy` | Host unit / temporary feature domain/application/infrastructure paths with suffix, renamed concrete class, and abstract/interface controls | Scaffold reports no placement -> suffix and semantic declarations each report once by exact path; permitted comparison paths remain absent | Remove declaration inspection, rename `_repository_impl.dart` to `_repository_adapter.dart`, flag an interface/abstract contract, or ban the potential infrastructure destination -> TC-DTR12-04 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'pins concrete domain repository implementations semantically without widening relocation policy'`; exact direct path and named lane |
| TC-DTR12-05 | Manifest schema and identities are strict, reviewed, line-independent, and exact-set compared. | `test/unit/architecture_boundary_checker_test.dart::rejects unknown duplicate wildcard ownerless stale and target-swapped exception rows` | Host unit / table of malformed and drifted JSON manifests | Scaffold accepts/ignores invalid rows -> every malformed manifest is untrustworthy and every new/stale/swapped identity is drift | Accept unknown keys, blank metadata, glob/traversal, count >1, duplicate identity, source/target relocation, or a stale row -> TC-DTR12-05 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'rejects unknown duplicate wildcard ownerless stale and target-swapped exception rows'`; exact direct path and named lane |
| TC-DTR12-06 | Git discovery is NUL-safe and fail-closed: current cached/non-ignored-untracked root-app sources are scanned, deletions subtracted, path/index/worktree redirection and symlink escape rejected, and repeated output is deterministic. | `test/unit/architecture_boundary_checker_test.dart::git-visible discovery rejects redirected or escaping state and is byte deterministic` | Host unit / temporary Git repository with spaces/newline path, deletion, untracked/ignored file, symlink, and environment fixtures | Scaffold trusts filesystem-only enumeration -> exact current set or fatal issue; two JSON reports are byte-identical | Use newline parsing, scan ignored sources, retain deleted bytes, honor redirected Git state, follow escape symlink, or depend on filesystem order -> TC-DTR12-06 red | `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'git-visible discovery rejects redirected or escaping state and is byte deterministic'`; exact direct path and named lane |
| TC-DTR12-07 | CLI/wrapper and named gate are CWD-independent and read-only; validated CLI fixture overrides preserve exact `0/1/2`, while the wrapper/lane reject arguments, run unit before the fixed-root real check, and fail fast. | `scripts/test/architecture_boundary_checker_contract_test.sh::architecture boundary CLI and named gate process contract` | Host process / disposable Git fixture using real Dart CLI plus fake gate-child command log and before/after digest | HEAD has no entrypoint/lane -> real fixture report/check formats and statuses are exact; gate invokes exact unit then fixed-root check and propagates either failure | Add update/generate mode, permit unsafe override, accept gate args, swallow status, reorder children, depend on caller CWD, or mutate fixture bytes -> TC-DTR12-07 red | `bash scripts/test/architecture_boundary_checker_contract_test.sh`; AUTO (`scripts/test/*_test.sh` under `sims-contracts`) and first-class `architecture-boundaries` lane |
| TC-DTR12-08 | Existing runtime-root and strict-analyzer rails remain green and no application production byte changes. | `./scripts/run_test_gates.sh runtime-roots`; `./scripts/check_flutter_analyze_strict.sh`; scoped diff | GREEN sentinel / real repository | GREEN on HEAD -> GREEN after DTR-12 with zero `lib/` delta and zero analyzer issues | Disturb DTR-01/DTR-02 policy, add a production edit, or add an unresolved dependency -> sentinel red | exact commands; existing `runtime-roots` and strict analyzer registrations |
| TC-DTR12-09 | Canonical gate docs/dispatcher expose the exact no-argument boundary lane; the unit test remains auto-classified under `core-host-all`; and the lane is a required typed Sims-major capability. | `scripts/test/architecture_boundary_checker_contract_test.sh::named architecture-boundaries lane is documented classified ordered and fail-fast`; `test/tool/sims/sims_manifest_test.dart::critical manifest pins architecture boundary release capability`; `scripts/test/sims_major_plan_contract_test.sh::architecture boundary release row contract`; completeness | Host shell/tool / real gate and Sims manifests | HEAD omits the lane/capability -> usage, runner, docs, host classification, typed capability, and unfiltered major plan agree | Omit usage/dispatcher/docs, accept lane args, unclassify the unit path, or mark the capability optional/inactive/non-major -> TC-DTR12-07/09 red | exact unit/shell commands; named lane plus `completeness-check`; required `architecture.boundaries` registration |

### Test Notes

- TC-DTR12-02 keys a dependency on rule, canonical source, directive/branch
  kind, and canonical target. Literal URI and line remain diagnostics, so an
  equivalent package-to-relative spelling rewrite does not manufacture new and
  stale architectural edges. Conditional alternatives remain individual
  branch identities. Duplicate identical identities are forbidden rather than
  hidden by set de-duplication.
- TC-DTR12-03 treats `lib/core/**` as core even for `core/debug` and
  `core/widgets`; the current 92 core-debug edges remain pinned. It treats only
  `lib/shared/widgets/**` as the shared presentation alias.
- TC-DTR12-06 may inject Git enumeration into pure scanner tests. The CLI
  validates any explicit fixture root/manifest and rejects Git redirection;
  the wrapper and named gate expose no override and always pin the real root.
- TC-DTR12-07's mutation digest covers the disposable fixture's source,
  manifest, and Git-visible files. Ephemeral SDK/package caches are not claimed
  byte-stable.

## Implementation Steps

1. Snapshot `git status --short`; re-run the exact source census. Stop and
   replan if current HEAD is not 174 core-to-feature directives, eight other
   upward directives, and 24 placement paths. Do not copy the roadmap's stale
   175 or package-only 154 as the baseline.
2. Add `test/unit/architecture_boundary_checker_test.dart` and the shell
   process contract. Add only a compile-capable checker API scaffold that
   returns an empty/unimplemented trustworthy scan; run TC-DTR12-01 through
   TC-DTR12-07 and record assertion-level RED. A missing import/compile failure
   is not the causal RED.
3. Implement strict manifest models, safe exact-path/URI validation, sorted
   issue/result rendering, and exact-set comparison. Keep scanner, Git path
   lister, and manifest input injectable for tests.
4. Implement NUL-safe Git discovery and repository-integrity validation, root
   package resolution, AST parsing, URI normalization, the four-layer matrix,
   shared-widget presentation alias, and suffix-plus-semantic domain
   repository-placement rule.
   Stop if any current source cannot be parsed/resolved trustworthily.
5. Add the exact 206-entry JSON manifest with per-entry owner, reason, and
   condition. There is no generator/update command; build the first reviewed
   file from the trustworthy report and verify every row in source.
6. Add the fixture-capable read-only CLI, fixed-root wrapper, and no-argument
   `architecture-boundaries` lane. The lane runs the unit file before the real
   fixed-root check. Add the required typed `architecture.boundaries`
   Sims-major capability and pin it in the manifest/major-plan contracts.
   Update the canonical gate documentation, roadmap DTR-12 row, and index.
7. Execute RED -> GREEN -> representative mutation re-RED cycles for:
   relative core import, shared-widget upward import, repository placement,
   stale manifest row, and gate child-status propagation. Restore each
   mutation before continuing.
8. Run the focused exact unit/process proofs, real named lane, preservation
   sentinels, completeness, strict analysis, source-scope guard, and diff
   hygiene. Refresh the architecture graph once after the coherent change.
9. Mark the plan and roadmap `Plan-green` only after every per-plan gate is
   green. Wave 4A aggregate `host-all` remains pending until DTR-13 is terminal.

## Rollback Contract

- Keep the checker, CLI, manifest, wrapper, process/unit tests, gate
  registration, and canonical docs in one coherent DTR-12 commit/range.
  Rollback reverts that exact range; never delete only the manifest or only the
  gate because either leaves an unusable or silently unenforced policy.
- After rollback, run `./scripts/run_test_gates.sh runtime-roots`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`; restore
  the roadmap row to `Candidate` and re-block DTR-13/DTR-15/DTR-18 on DTR-12.
- Rollback never restores the stale audit count or alters any application
  source. Git makes the tooling/docs change recoverable; there is no persisted
  user data, migration, or external side effect.

## Risks And Blind Spots

- Package-only matching can miss relative imports -> TC-DTR12-02 and the
  canonical 154+20 split prove both forms.
- Regex scanning can miss multiline, conditional, export, and part directives
  or match decoys -> analyzer AST traversal and TC-DTR12-02.
- A rank model can omit shared presentation -> the C4 alias and TC-DTR12-03.
- A set can hide duplicate identical imports -> exact count `1` and duplicate
  drift in TC-DTR12-02/05.
- A stale exception can make debt disappear without review -> exact actual vs
  expected comparison and stale-row failure in TC-DTR12-01/05.
- Git/environment/path tricks can shrink scan scope -> fail-closed repository
  validation and TC-DTR12-06/07.
- An allowlist can become a silent escape hatch -> every row is exact,
  owner/reason/condition metadata is mandatory, and no glob or write mode
  exists.
- Lifecycle / derived-state durability:
  N/A — the tool derives no application state; each run rescans the current
  repository.
- Sibling-surface consistency:
  TC-DTR12-03 covers feature-local and shared presentation aliases; other
  undocumented folder taxonomies are deliberately deferred.
- Destructive-action side effects:
  N/A — DTR-12 changes read-only tooling/docs/tests and no application or user
  data.
- Invariant re-verification under new transitions:
  TC-DTR12-01/05 run exact new-and-stale comparison on every gate invocation.

## Gate Cadence

- Per-plan closure: focused boundary unit/process contracts, the exact real
  `architecture-boundaries` lane, `runtime-roots`, strict analysis,
  completeness, application-source preservation, and diff hygiene.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure` once after
  Wave 4A (`DTR-12` and `DTR-13`) is integrated/terminal, and once again at
  final rollout/release closure.
- Shared/direct registration:
  `scripts/test/architecture_boundary_checker_contract_test.sh` runs directly
  and under auto-discovered `sims-contracts`.
  `test/unit/architecture_boundary_checker_test.dart` is already auto-classified
  under `core-host-all`, but the new named lane executes it directly for this
  per-plan cadence; no per-plan core-family sweep is required.

## Acceptance Gates

```bash
# Snapshot before execution; expect the pre-existing state to be recorded.
git status --short

# Reconfirm the current baseline before writing the manifest. Each command must
# print the pinned semantic count: 154 package core imports, 20 relative core
# imports, one domain->application, seven application->presentation (including
# four shared-widget imports), and 24 domain repository implementations.
rg -n "^\s*(import|export)\s+['\"]package:flutter_app/features/" \
  lib/core -g '*.dart' | wc -l
rg -n "^\s*(import|export)\s+['\"](?:\.\./)+features/" \
  lib/core -g '*.dart' | wc -l
rg -n "^\s*(import|export)\s+['\"]package:flutter_app/features/[^/]+/(application|presentation)/" \
  lib/features/*/domain -g '*.dart' | wc -l
rg -n "^\s*(import|export)\s+['\"]package:flutter_app/(features/[^/]+/presentation|shared/widgets)/" \
  lib/features/*/application -g '*.dart' | wc -l
rg --files lib/features | rg '/domain/.+_repository_impl\.dart$' | wc -l

# After the compile-only API scaffold, expect assertion RED for an empty
# inventory rather than a missing import or compile failure.
flutter test --no-pub test/unit/architecture_boundary_checker_test.dart \
  --plain-name \
  'discovers and normalizes package relative export part and conditional dependencies without lexical decoys'

# Process/gate RED before CLI/wrapper/registration; expect non-zero for the
# named missing behavior.
bash scripts/test/architecture_boundary_checker_contract_test.sh

# Release-orchestration registration; expect the typed capability and the
# unfiltered major plan to pin the exact required boundary command.
flutter test --no-pub test/tool/sims/sims_manifest_test.dart \
  --plain-name 'critical manifest pins architecture boundary release capability'
bash scripts/test/sims_major_plan_contract_test.sh

# Focused GREEN; expect exit 0 and zero failed tests/assertions.
flutter test --no-pub test/unit/architecture_boundary_checker_test.dart
bash scripts/test/architecture_boundary_checker_contract_test.sh

# Canonical named lane; expect the exact unit file to pass first, then a
# trustworthy real-tree check with 182 dependency and 24 placement exceptions,
# no new/stale identity, and exit 0.
./scripts/run_test_gates.sh architecture-boundaries

# Existing DTR-01 preservation; expect its exact unit/check sequence and no
# runtime-root drift.
./scripts/run_test_gates.sh runtime-roots

# Test classification; expect every test path classified and exit 0.
./scripts/run_test_gates.sh completeness-check

# No application/dependency mutation is permitted.
git diff --exit-code -- lib pubspec.yaml pubspec.lock

# Strict analyzer and whitespace hygiene; expect zero issues and exit 0.
./scripts/check_flutter_analyze_strict.sh
git diff --check

# Graph closure after the coherent app-owned tooling/gate change.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Observed causal RED: TC-DTR12-02 compiled against the empty checker scaffold
  and failed its semantic assertion with expected eight normalized
  dependencies versus actual zero. Before registration, the named lane exited
  `1` through canonical usage because it did not exist.
- Green sentinel: `runtime-roots`, strict analyzer, and zero `lib/`/dependency
  diff remain green.
- Pre-existing dirty tree / known failure: none at planning snapshot; record
  any later concurrent state and preserve it.
- Environment blocker: none; the proof is host-only and uses the already
  resolved Dart/Flutter analyzer dependencies.
- Scope drift: any application source edit, dependency/lock change, attempt to
  repair current exceptions, undocumented folder ordering, manifest write
  mode, or device/native requirement blocks completion.

- [x] Every behavior has a named automated test or exact command.
- [x] Causal assertion RED, focused GREEN, and representative mutation re-RED
      are recorded.
- [x] The 206-entry current manifest is exact, reviewed, and metadata-complete.
- [x] The named lane runs the exact unit suite then the real check and fails on
      drift.
- [x] The required typed Sims-major capability invokes that named lane.
- [x] Preservation, analyzer, completeness, graph, and hygiene gates pass.
- [x] No application, package, database, native, generated, or device surface
      changes.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/unit/architecture_boundary_checker_test.dart --plain-name 'discovers and normalizes package relative export part and conditional dependencies without lexical decoys'`
  after the compile-only scaffold; observed expected eight, actual zero.
- Preservation command: `./scripts/run_test_gates.sh runtime-roots`.
- Registration complete: the no-argument `architecture-boundaries` usage,
  runner, and dispatcher are in `scripts/run_test_gates.sh`; canonical docs and
  the required `architecture.boundaries` Sims-major row/contracts invoke it.
  The row is appended so pre-existing JSON-index runtime-root evidence remains
  stable. The exact unit path is named directly.
- Migration: none.
- Boundary closure: host-only deterministic tooling; no simulator/device,
  relay, native, SQLCipher, or real-network proof.
- Gate cadence: DTR-12 runs focused/new-lane proof only; Wave 4A owns one full
  `host-all` after DTR-13, and final rollout/release owns the final full run.
- Unresolved evidence: none blocking; undocumented infrastructure/data ordering
  remains explicitly deferred.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | reviewed | Plan 288 and cited guardrail/release precedents | independent verdict `plan-fixes-required`; repaired five blocking/reliability gaps; closer verdict `ready` | normalized identity, semantic placement, fixture-capable CLI, direct lane, and required Sims-major enforcement are explicit | none | execute TC-DTR12-02 causal RED |
| 2026-07-27 | causal RED | checker scaffold; TC-DTR12-02; canonical gate dispatcher | focused unit exited `1`: expected eight normalized AST dependencies, actual zero; missing named lane exited `1` through usage | failures were assertion/registration causal, not missing imports or compilation | none | implement the minimum checker, manifest, and lane |
| 2026-07-27 | GREEN | `tool/architecture_guard/**`; focused unit/process tests; gate/Sims surfaces | six focused unit tests, process contract, typed Sims test, major-plan contract, and named lane passed; real check was exact at 182 dependencies + 24 placements / zero issues | package/relative normalization, layer matrix, semantic placement, exact manifest drift, Git integrity, and 0/1/2 process behavior are machine-enforced | none | run independent implementation audit and mutations |
| 2026-07-27 | audit hardening | checker and focused tests | two independent audits found and then closed class-alias/typedef ancestry, duplicate JSON-key, and mismatched named-`part of` bypasses | regression fixtures pass without changing the canonical 182/24 inventory | none | execute representative mutation re-RED |
| 2026-07-27 | mutation re-RED | checker classifier/resolver/semantic rule; canonical manifest; process contract | relative-URI mutation produced 5/12 edges; shared-widget mutation omitted three required edges; class-alias mutation omitted its exact placement; manifest target swap produced one new + one stale finding; fake child statuses `23`/`24` propagated | every high-risk admission seam is causally sensitive; all temporary mutations restored | none | close preservation and release gates |
| 2026-07-27 | Plan-green closure | focused/new gates; DTR-01/analyzer/completeness sentinels; graph | named lane exact 182/24/0; process and Sims contracts passed; `runtime-roots` trustworthy/no drift over 1,025 files; strict analyzer no issues; completeness 1,340/1,340; zero `lib`/dependency diff; Graphify incremental refresh wrote current fingerprint `332fe23f228dfb75` | first Sims-row placement shifted DTR-01 JSON-index evidence; appending the new row preserved every existing index and the final sentinel passed | none | hand DTR-12 to Wave 4A; aggregate `host-all` waits for DTR-13 |

## Reviewer Findings

Initial verdict: `plan-fixes-required`.

- `High` — a first-class manual lane was not sufficient release enforcement.
  Applied: required typed `architecture.boundaries` Sims-major capability and
  exact manifest/major-plan proof.
- `High` — suffix-only placement detection was rename-bypassable.
  Applied: AST-backed concrete repository declaration detection plus renamed
  filename and abstract/interface controls.
- `High` — the fixed-root CLI contradicted a real disposable-fixture process
  contract. Applied: validated read-only CLI overrides with a no-argument,
  fixed-root wrapper/lane.
- `Medium` — literal URI spelling was incorrectly part of architectural
  identity. Applied: normalized source/directive-branch/target identity with
  literal URI retained only for diagnostics.
- `Medium` — the plan's test-family wording predated Plan 287's recursive
  `test/unit/**` registration. Applied: core-host classification is acknowledged
  while direct per-plan execution remains mandatory.

Five-lens closer: the architecture rule remains source-backed and bounded; the
checker, tests, gate, and release capability now join coherently; exact
new/stale/duplicate and semantic-rename cases provide depth; DTR-01/analyzer/app
source preservation remains explicit; and the cadence avoids a per-plan
`host-all`. Final verdict: `ready`.
