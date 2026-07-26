# 272 - DTR-01 runtime-root inventory and advisory reachability guard

Status: Plan-green
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-01`)
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-01` / Wave 0 — Safety rails
Date: 2026-07-25

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-24 | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture and full Graphify graphs | Compact queries remained broad and the graph is stale only for an unrelated private-media file. The full graph surfaced `main.dart` and `background_message_handler.dart`, but not an authoritative runtime-root inventory. | Verify every load-bearing root in current source. |
| 2026-07-24 | Evidence Collector — source census | `lib/**/*.dart`; `main.dart`; smoke entrypoints; callback/native/generated/tooling/compatibility anchors | A current directive-closure probe reproduced the roadmap census exactly: 1,056 app-owned Dart files, 986 main-reachable, 3 manual roots, 60 test/integration-only, and 7 with no Dart importer. Counts are planning evidence, not a fixed gate contract. | Reconcile the seven no-importer paths. |
| 2026-07-24 | Independent refute pass | `smoke_test_runner.dart`; reliability discovery; active smoke runner; safe-cleanup audit | Missing imports are not deletion proof. `smoke_test_runner.dart` has no proven caller and must be `retained-unresolved`, while the other six no-importer files remain advisory candidates. | Encode reachability and disposition as separate axes. |
| 2026-07-24 | Evidence Collector — gates | both gate runners; Sims manifest/contracts; CI handoff | Existing completeness classifies tests only. No repo-local CI workflow exists. Add one repo-owned named guard and register it as a required major/infra capability; external workflow wiring stays an explicit release-owner follow-up. | Freeze the test and registration contract. |
| 2026-07-24 | Planner | tier matrix, plan template, roadmap gate cadence | Tool-only change: deterministic host fixtures and process contracts are causal. No app family sweep, native execution, SQLCipher, simulator, relay, or device proof is justified. | Run the blocking sufficiency check. |
| 2026-07-24 | Baseline verifier | completeness, callback, migration, Sims manifest, and major-plan contract tests | All five exact current-HEAD commands passed. Callback/SQLCipher tests remain useful grounding evidence but were removed from per-plan closure as non-adjacent to the hard tool-only scope; completeness and existing nested-capability assertions remain affected sentinels. | Complete the independent sufficiency audit. |
| 2026-07-24 | Independent sufficiency audit | Test Contract, RED sequence, root precedence, unknown-gate branch, Sims typed row | Corrected no-importer vs unrooted modeling, test-vs-tool root overlap, recursive gate design, `dart run` stdout risk, actual unknown-gate exit `1`, compile-RED ordering, ceremonial FCM/SQLCipher gates, and under-specified Sims fields. Sixteen rows now have causal or affected-sentinel ownership. | Run structural and diff hygiene checks, then hand off for optional `$tdd-review`. |
| 2026-07-24 | Sufficiency closer | Plan 272, roadmap registry, `00-INDEX.md`, structural row checks, `git diff --check` | Plan number/link are unique, all 16 contract rows are sequential and complete, no trailing-whitespace/diff errors were found, and no evidence blocker remains. | Offer optional `$tdd-review`; otherwise start with TC-DTR01-01 only. |
| 2026-07-24 | `$tdd-review` counterexample verifier | Plan 272; root `pubspec.yaml`; current multiline directives; nested packages; test-driver invocation; iOS registrant call; Git deletion behavior; gate scripts | Pre-amendment verdict `plan-fixes-required`: a regex/hard-coded package parser, literal-only evidence, tracked deletions, nested packages outside `packages/`, test-only disposition rules, and filtered dirty-tree proof all admitted false-green implementations. The advisory tool/gate architecture and gate cadence remain sound. | Apply only the verified parser, boundary, evidence, CLI, and closure-proof corrections, then re-read the plan. |
| 2026-07-24 | `$tdd-review` amendment pass | Amended Scope, Test Contract, implementation, risks, acceptance, and handoff | Syntax parsing is AST-based/fail-closed, package boundaries are discovered, structural evidence is mandatory, external entrypoints and tracked deletions ratchet, and closure proof is non-vacuous. | Re-read the amended plan for introduced contradictions. |
| 2026-07-24 | Amended-plan verifier | Convention entrypoint and manual-root policy contracts | Found two residual contradictions: convention tests could be read as requiring per-entrypoint records, and generic self-only rejection made the three documented manual targets unsatisfiable. | Exempt computed convention roots and define a closed three-target manual-policy predicate. |
| 2026-07-24 | `$tdd-review` closer | Final amended plan plus structural/shell hygiene | Both residual counterexamples now re-red TC-DTR01-02/10/13. All 16 rows remain structurally complete, the acceptance block is valid Bash, and no trailing whitespace remains. | Verdict `ready`; begin with TC-DTR01-01 only when execution is authorized. |

## Problem And Evidence

- Behavior to improve: repository contributors need one deterministic inventory
  that distinguishes ordinary Dart reachability from callbacks, manual targets,
  native/generated registrations, tooling, resources, and compatibility roots,
  then reports genuinely unresolved files without calling them removable.
- Impact: a no-import result can currently be mistaken for deletion evidence,
  while a newly production-unreachable file can enter the tree without an
  owner, reason, or review disposition.
- Confirmed current gap:
  - `scripts/run_test_gates.sh:1002-1202` classifies test paths, and
    `scripts/run_test_gates.sh:1204-1232` scans only
    `test/**` and `integration_test/**`; it is not a production reachability
    classifier.
  - `scripts/check_reliability_simulation_discovery.sh:629-649` scans a bounded
    simulator/E2E candidate universe and fails unclassified rows at
    `scripts/check_reliability_simulation_discovery.sh:1126-1146`; this is a
    useful typed-classifier precedent, not an app source inventory.
  - `tool/sims/critical_features.json:759-794` maps directories to proof
    capabilities, not files to runtime-root kinds, evidence, dispositions, or
    removal conditions.
  - Targeted current-source search found no dedicated runtime-root manifest,
    CLI, guard test, or repo-local CI workflow.
- Current source census:
  - The roadmap records 1,056 `lib` Dart files, 986 main-reachable files, 3
    manual targets, 60 test/integration-only files, and 7 no-importer files at
    `dead-code-and-technical-debt-removal-roadmap.md:109-129`; a fresh
    import/export/part closure reproduced those values.
  - The three manual roots declare their exact `flutter run -t` invocation and
    own `main()` at `lib/smoke_test_main.dart:2-3,37`,
    `lib/smoke_test_messages.dart:2-5,37`, and
    `lib/smoke_test_restore.dart:2-3,38`.
  - The seven no-importer files are
    `lib/core/debug/smoke_test_runner.dart`,
    `lib/core/services/chat_message.dart`,
    `lib/features/feed/presentation/widgets/feed_ring_avatar.dart`,
    `lib/features/groups/domain/models/group_inbox_cursor.dart`,
    `lib/features/groups/presentation/widgets/group_compose_area.dart`,
    `lib/features/posts/application/post_pass_follow_on_support.dart`, and
    `lib/features/settings/presentation/widgets/settings_move_account_card.dart`.
    The latter six total the roadmap's approximately 564 LOC and remain
    candidates only.
  - Current directives are not safely line-regex parseable:
    `lib/main.dart:131-134,276-282` and
    `integration_test/_support/fake_secure_key_store.dart:17-20` contain
    multiline combinators. The self-package name is declared by
    `pubspec.yaml:1`; it must not be hard-coded in the classifier.
  - The root package currently contains two descendant package boundaries:
    `packages/background_push_crypto/pubspec.yaml:1` and
    `third_party/bonsoir_darwin/pubspec.yaml:1-7`. A `packages/**` exclusion
    alone would cross the vendored override boundary.
  - `test_driver/integration_test.dart:1-3` is a real non-convention Dart
    entrypoint. It is selected by
    `scripts/run_received_video_picture_in_picture_proof.sh:21-22,809-813` and
    `integration_test/scripts/run_1to1_device_real.dart:74-75,867-874,1082-1089`;
    placement outside `test/**/*_test.dart` cannot make it invisible to the
    inventory.
  - `git ls-files --cached --others --exclude-standard` includes an
    unstaged-deleted tracked path. DTR removal and rename workflows therefore
    require NUL-delimited enumeration of existing worktree files plus a
    separate stale-declaration drift result, not an I/O/parse failure.
- Confirmed restricted-root examples:
  - The FCM callback is protected by `@pragma('vm:entry-point')` at
    `lib/features/push/application/background_message_handler.dart:350-351`
    and registered at `lib/main.dart:483-485`.
  - Android names its activity, PiP activity, service, provider, and Flutter
    generated-registration metadata at
    `android/app/src/main/AndroidManifest.xml:28-36,93-118`.
  - iOS names extension principal classes at
    `ios/NotificationService/Info.plist:23-29` and
    `ios/Share Extension/Info.plist:30-33`; its Xcode project owns the generated
    registrant at `ios/Runner.xcodeproj/project.pbxproj:10,325-327,753`.
  - Tracked generated registration is invoked on macOS, Linux, and Windows at
    `macos/Runner/MainFlutterWindow.swift:10-18`,
    `linux/runner/my_application.cc:58-74`, and
    `windows/runner/flutter_window.cpp:21-28`.
  - iOS invokes generated registration at
    `ios/Runner/AppDelegate.swift:275-277`; the same symbol also occurs only in
    comments at `ios/Runner/AppDelegate.swift:304-307`, proving that literal
    containment is not sufficient invocation evidence.
  - Generated localization ownership is declared by `l10n.yaml:1-3`, and the
    generated delegate/locales are installed at `lib/main.dart:7676-7677`.
  - The graph-blind headless plugin is declared at `pubspec.yaml:72-76`, names
    `BackgroundPushCryptoPlugin` at
    `packages/background_push_crypto/pubspec.yaml:18-23`, and attaches its
    channel at
    `packages/background_push_crypto/android/src/main/kotlin/com/mknoon/background_push_crypto/BackgroundPushCryptoPlugin.kt:29,47-50`.
  - A real manually registered tool root is the Sims command at
    `tool/sims/critical_features.json:697-713`, whose executable `main()` is at
    `integration_test/scripts/run_group_multi_party_sims.dart:200-212`.
  - Ordered migrations are centralized in
    `lib/core/database/production_migration_registry.dart:3-106,118-129,606-616`;
    the compatibility export
    `lib/features/conversation/presentation/widgets/recording_overlay.dart:1`
    is production-imported by `compose_area.dart:10`.
- Existing coverage:
  - `test/core/gate_classification_completeness_test.dart:5-55` preserves
    test-gate classification, not production source reachability.
  - `test/features/push/application/background_message_handler_test.dart:2263-2271`
    exercises the callback behavior, but no test pins both its pragma and FCM
    registration.
  - `test/core/database/integration/full_migration_chain_test.dart:1851-1887`
    preserves ordered production migration registries.
  - `tool/sims/critical_features.json:195-211` preserves the nested
    `background_push_crypto` Dart tests/analyzer lane; it does not run or replace
    the plugin's Kotlin boundary test.
- Missing coverage: no causal unit/process test proves import-closure parsing,
  root evidence, two-axis classifications, advisory output, candidate ratchet,
  deterministic non-mutation, or release-gate registration.
- Refuted findings:
  - “No Dart importer means dead” is refuted by the manual roots, callback,
    native/generated/tooling surfaces, and the explicit warning at
    `Test-Flight-Improv/109-safe-dead-code-cleanup.md:258-279`.
  - “Graphify or analyzer dead-code/reachability output is sufficient
    authority” is refuted: both are shortlist inputs only and cannot establish
    string/native/tool invocation. Analyzer syntax ASTs remain appropriate for
    parsing Dart grammar.
  - “Existing `classify_path` can be reused unchanged” is refuted because its
    input universe and output vocabulary are test-gate-specific.
  - “`smoke_test_runner.dart` is a confirmed tooling root” is refuted. Current
    search finds no caller; discovery only labels it support at
    `scripts/check_reliability_simulation_discovery.sh:155-157`, while the
    active smoke flow imports `intro_e2e_runner.dart` at `lib/main.dart:226`.
    The roadmap therefore retains it pending ownership at
    `dead-code-and-technical-debt-removal-roadmap.md:99-100`.
- Unresolved findings:
  - Runtime ownership of `smoke_test_runner.dart` remains unresolved by design;
    this plan can safely classify it `retained-unresolved` with the DTR-13 /
    QA+release revisit condition and cannot promote it to either live or dead.
  - The external CI repository, workflow path, and owner are absent, as already
    confirmed by `Test-Flight-Improv/ci-gate-handoff.md:9-30`. This does not
    block the repo-owned guard and required major/infra registration; actual
    external invocation remains a declared Release/CI follow-up.
- Affected implementation, test, and gate files:
  `pubspec.yaml`, `pubspec.lock`, `tool/runtime_roots/**`,
  `scripts/check_runtime_root_inventory.sh`,
  `test/unit/runtime_root_inventory_test.dart`,
  `scripts/test/runtime_root_inventory_contract_test.sh`,
  `scripts/run_test_gates.sh`, `tool/sims/critical_features.json`,
  `test/tool/sims/sims_manifest_test.dart`,
  `scripts/test/sims_major_plan_contract_test.sh`, and the CI/gate/roadmap
  documentation named below.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `fc333c615c1b3e10`;
  `stale:lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
  (unrelated to DTR-01).
- Primary query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-01 advisory runtime-root inventory and CI reachability classifier: current production roots, tool tests, and gate registration for lib/main.dart, lib/smoke_test_main.dart, @pragma('vm:entry-point') callbacks, native/generated registrations, migrations, protocol strings, and scripts/run_host_test_gates.sh" --profile tdd --budget 700`.
- One allowed refinement:
  `python3 graphify-arch/tdd_context.py query "lib/main.dart lib/smoke_test_main.dart scripts/run_host_test_gates.sh scripts/run_test_gates.sh runtime roots and exact tests/gate registration" --profile tdd --budget 700`.
- Full-graph fallback:
  `graphify query "firebaseMessagingBackgroundHandler GeneratedPluginRegistrant smoke_test_main background_push_crypto runtime entrypoint registration" --budget 800`.
- Anchors: `scripts_run_test_gates_runtime_telemetry_tests` ->
  `scripts/run_test_gates.sh`; `main.dart` -> `lib/main.dart`;
  `background_message_handler.dart` ->
  `lib/features/push/application/background_message_handler.dart`.
- Surfaced proof/gate files: `scripts/run_test_gates.sh`,
  `scripts/run_host_test_gates.sh`, `lib/main.dart`,
  `lib/features/push/application/background_message_handler.dart`, and
  `test/core/database/integration/full_migration_chain_test.dart`.
- Graph gaps requiring source search: both compact queries remained
  `confidence=broad`; no DTR-specific classifier exists; manual targets,
  native/plist/Xcode registrations, generated registrants, shell/tool
  invocation, resources, and the headless package required current-source
  verification.
- Reuse rule: these anchors may be handed to review/execution; every conclusion
  still requires current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a pure host-side Dart classifier under `tool/runtime_roots/`, a
  versioned `runtime_roots.json` manifest, and a thin
  `scripts/check_runtime_root_inventory.sh` wrapper that resolves the repository
  root and argument-preservingly invokes
  `dart tool/runtime_roots/runtime_root_inventory_cli.dart` so package
  build-hook chatter cannot corrupt machine-readable stdout.
- Add `analyzer: ^9.0.0`, `yaml: ^3.1.3`, and `xml: ^6.6.1` as direct dev
  dependencies and update the lockfile. Use the analyzer syntax AST only for
  directives, top-level entrypoint detection, and Dart structural evidence; use
  format parsers for YAML and XML/plist evidence. These libraries are not
  dead-code or reachability oracles and never determine a disposition by
  themselves. The selected versions satisfy the repository's `sdk: ^3.9.0`
  constraint and are present in the current offline package cache.
- Scan the working-tree app-owned `lib/**/*.dart` source set, including
  non-ignored new files. Derive the self-package name from the root
  `pubspec.yaml`; resolve relative and self-package imports, exports, library
  `part` directives, every conditional branch, multiline combinators, and
  cycles against the exact case-sensitive enumerated path set. Normalize legal
  relative dot segments. An absolute/file, out-of-root, unresolved, or
  wrong-case self/relative target makes the scan untrustworthy (`2`) instead of
  silently dropping an edge. `part of`, external packages, comments, and string
  literals outside a directive are not root-package edges.
- Enumerate tracked plus non-ignored new source/test roots through injected
  `git -C <repo> ls-files -z --cached --others --exclude-standard` and parse the
  NUL-delimited result. The scan universe contains existing worktree files only:
  deleting/renaming an ordinary tracked source yields classification or
  stale-manifest drift (`check` exit `1`), not an accidental file-I/O exit `2`;
  absence of a required scan anchor such as the root pubspec or main entrypoint
  remains an untrustworthy-scan exit `2`. A Git failure is also exit `2`, and
  ignored build output never becomes an accidental candidate.
- Parse every existing enumerated root-package Dart file with the analyzer AST.
  Error diagnostics or an ambiguous/malformed directive preamble that prevents
  trustworthy edge or entrypoint extraction fail closed as exit `2`; there is
  no regex, line-parser, or empty-edge fallback.
- Discover every descendant package boundary from an existing enumerated
  descendant `pubspec.yaml` and exclude that directory's entire Dart tree,
  regardless of whether it lives under `packages/`, `third_party/`, or another
  prefix. Nested-package tests, tools, or mains cannot seed root-package app
  reachability. Only `lib/**/*.dart` is the reported app universe; root-package
  Dart files elsewhere can contribute incoming-edge facts but establish a
  reachability origin only when they are a convention entrypoint or have
  validated invocation evidence.
- Treat `test/**/*_test.dart`, `integration_test/**/*_test.dart`, and
  `test/flutter_test_config.dart` as computed convention origins; they do not
  require one manifest record per test entrypoint. Separately detect every other
  root-package top-level `main()` outside `lib/main.dart` and the three manual
  targets as an external-entrypoint candidate. Each non-convention candidate
  that can reach `lib` directly or through a declared
  command/`--target`/`-t`/`--driver` relation requires an exact reviewed external
  record. Only structurally validated invocation evidence promotes it to a
  tooling origin; an uninvoked or unresolved candidate remains visible and does
  not seed reachability. This covers `test_driver/integration_test.dart` and
  runner-to-harness edges without treating directory placement as invocation.
- Emit two separately reported dimensions for every app-owned Dart file:
  - computed root-origin reachability, with the full origin set plus a stable
    exclusive reporting bucket:
    `main-reachable` when in the `lib/main.dart` closure,
    `manual-root-reachable` when outside main but in one or more of the three
    manual-root closures, `tooling-reachable` when outside main/manual and
    reached from a source-evidenced registered Dart tool root, and
    `test/integration-reachable` when outside higher-precedence closures and
    reached from tracked/non-ignored convention entrypoints
    `test/**/*_test.dart`, `integration_test/**/*_test.dart`, or
    `test/flutter_test_config.dart`, and `unrooted` when reached from none of
    those roots. A Dart file under `integration_test/scripts/` is not
    automatically a test root; it must have exact tooling invocation evidence.
    Exclusive reporting precedence is
    main > manual > tooling > test/integration > unrooted;
  - reviewed declaration metadata, with zero or more root-kind tags:
    `app-entrypoint`, `manual-entrypoint`, `vm-callback`,
    `convention-callback`, `native-registration`, `generated`,
    `headless-plugin`, `tooling`, `compatibility`, or `resource`; plus exactly
    one disposition:
    `explained-root`, `candidate`, `deferred-review`, or
    `retained-unresolved`.
- Emit the exact incoming Dart import/export/part edges independently. Zero
  Dart importers remains a diagnostic, not a reachability class; a multi-file
  unrooted island must still report every member.
- Require exact path, stable owner/roadmap owner, reason, source evidence
  anchors, and a removal/revisit condition for every non-main-reachable Dart
  file. A manual/tooling root-kind declaration may seed an origin only after
  its manual-policy/invocation evidence validates; root-kind tags remain visible
  separately,
  while dispositions can never seed, override, or suppress computed
  reachability. `explained-root` requires either a nonempty validated computed
  origin (`main`, `manual`, `tooling`, or `test/integration`) or validated
  restricted-root evidence; a convention-test closure does not invent a
  `tooling` or other root-kind tag. `deferred-review` requires a downstream roadmap
  owner/condition; none of the four dispositions means deletion-safe.
- Store evidence as typed structural predicates over repository-relative source
  paths. Supported root-proving predicates distinguish at least Dart
  directive/annotation/call-argument relations, comment-aware source call-token
  relations for non-Dart languages, structured JSON/YAML/XML/plist
  key/element/attribute/value relations, and command target/driver argument
  relations. A narrowly bounded `manual-policy` predicate may seed only the
  three exact smoke targets and requires all of: an AST top-level `main()`, the
  leading documented `flutter run -t <same exact path>` command, and a separate
  roadmap retention record. Its reviewed owner is DTR-13 / QA+release and its
  removal condition is a registered replacement composition root with
  equivalent smoke-entrypoint proof. Other self-only comments/literals never
  prove a root. All predicates reject wrong
  keys/elements, wrong callees/arguments, mismatched targets, generic
  comment/string decoys, and unknown evidence kinds.
  Unstructured literal containment may be retained only as non-rooting
  diagnostic context. Planning line numbers, Graphify node IDs, aggregate
  counts, and hashes are not durable manifest evidence.
- Permit no path globs except a narrowly scoped generator-owned output rule with
  tracked generator/build evidence. Candidate, manual, tooling, compatibility,
  and retained-unresolved declarations use exact paths.
- Seed the reviewed manifest with the current 3 manual-root-reachable paths,
  the freshly recomputed exact current test/integration-only set represented by
  the roadmap's aggregate count of 60, every detected non-convention external
  entrypoint that can reach app source, 6 advisory unrooted/no-importer
  `candidate` rows, and the policy-retained unresolved smoke runner. Recompute
  every path under the stricter convention/tool root rules and map it to a
  source-backed `explained-root`, owned `deferred-review`, or
  `retained-unresolved` state as applicable. The manifest records exact paths;
  changed derived bucket totals are accepted when exact origin evidence
  explains them, and the gate does not pin aggregate counts.
- Record representative generated-localization, Android, Apple, desktop, web,
  headless-plugin, convention, tooling, migration/protocol,
  compatibility-export, and resource evidence. External records explain
  restricted roots; they do not pretend to be an exhaustive native dead-code
  analyzer. Representative current evidence includes the actual iOS
  `GeneratedPluginRegistrant.register` call and the validated
  `test_driver/integration_test.dart` `--driver` selection, not only project
  inclusion, comments, or directory placement.
- Provide read-only modes:
  - `report`: exit `0` whenever scanning and schema/config parsing are
    trustworthy, including when classification/stale-evidence drift would fail
    `check`; emit that drift explicitly in text/JSON. Declared candidates and
    retained-unresolved rows are ordinary advisory results;
  - `check`: exit `0` only when every non-main-reachable source and detected
    restricted root has a valid current declaration, exit `1` for
    classification/evidence drift, and exit `2` for usage/config/parse/I/O
    failures that prevent a trustworthy result.
  - Both accept `--format text|json`; read-only `--repo-root` and `--manifest`
    overrides exist only to make isolated process fixtures executable. The
    canonical gate omits both and scans the resolved repository/default
    manifest.
- Add a named `runtime-roots` gate and register exactly one active required
  capability with `id: runtime.roots.advisory`, `owner: flutter-app`,
  `proofBoundary: host.runtime-roots.advisory`,
  `assertions: [runtime_roots.inventory_accounted]`, `lane: host-dart`,
  `modes: [major]`, `families: [infra]`,
  `command: [./scripts/run_test_gates.sh, runtime-roots]`,
  `buildProfile: host.flutter_tester`, no dependencies,
  read-only `host.cpu`, targets `host.flutter-tester`, `host.bash`, and
  `host.git`, no artifact/validator/N/A allowance, `automationReady: true`, and
  no declared build exception. Update the external CI handoff to invoke the
  repo-local command without copying its inventory.

Must preserve:

- Missing imports remain a review signal only; output never asserts
  `deletion-safe`, `dead`, or an automatic disposition.
- All source, manifest, generated, native, package, database, and asset files
  remain byte-unchanged by report and check runs -> TC-DTR01-12.
- Existing test completeness stays green ->
  `test/core/gate_classification_completeness_test.dart`.
- The existing `nested.background_push_crypto` major capability remains present
  and unchanged; DTR-01 adds static inventory evidence but does not claim its
  real Kotlin plugin boundary.

Hard `Do not`:

- Do not delete, move, wire, rewrite, or suppress any current candidate.
- Do not add `--fix`, auto-baseline, manifest-writing, source-writing, or file
  deletion behavior.
- Do not use Graphify, analyzer reachability/unused findings, missing imports,
  LOC, or test-only status as deletion authority. The analyzer dependency is a
  syntax parser only.
- Do not turn `smoke_test_runner.dart` into confirmed tooling without a proven
  caller and owner decision.
- Do not change `lib/`, platform/native code, generated outputs,
  `packages/background_push_crypto`, database schema/version, persisted/wire
  values, assets, runtime dependencies, or application behavior. The only
  package metadata change is the direct dev-only syntax-parser dependency and
  its lockfile resolution.
- Do not add a `core-host-all`, `feature-host-all`, performance, native,
  simulator, relay, or device gate to this tool-only plan.
- Do not claim the missing external workflow has been wired.

Deferred / accepted difference:

- Candidate deletion or wiring -> DTR-03, DTR-04, DTR-06, DTR-07, DTR-09,
  DTR-10, and DTR-11, because DTR-01 classifies but never disposes.
- Compatibility floors and symbol/protocol removal proof -> DTR-08.
- `smoke_test_runner.dart` ownership/wiring decision -> DTR-13 and QA+release;
  retained-unresolved until then.
- External CI repository/path/owner -> Release/CI via
  `ci-gate-handoff.md`; this plan lands the canonical repo command and required
  major/infra registration only.
- Exhaustive native, generated build-output, vendor, and symbol-level
  reachability -> later boundary-specific plans; DTR-01 validates representative
  tracked evidence and preserves uncertainty.

Dependencies:

- Upstream: none.
- Downstream: DTR-03, DTR-04, DTR-08, DTR-12, and DTR-13 consume this
  inventory, but none may reinterpret a candidate row as deletion proof.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR01-01 | Conservatively and fail-closed parse Dart directives | `test/unit/runtime_root_inventory_test.dart::resolves package relative export part conditional and cyclic directives without comment/string decoys` | Host unit / synthetic temp repository with root package name, exact Git path set, multiline `show`/`hide`/`deferred`, every conditional branch, `part`/`part of`, cycles, external packages, legal relative dot segments, wrong-case/absolute/out-of-root URIs, comments, raw/multiline strings, and malformed syntax | Causal RED — HEAD has no classifier or test; GREEN derives the self-package name, assigns every valid fixture path the correct transitive reachability, ignores genuine non-edges, and returns an untrustworthy parse result for an invalid self/relative target or malformed/ambiguous source rather than an empty edge set | Replace AST parsing with line regex, hard-code `flutter_app`, ignore multiline combinators/relative exports/library parts, reject a legal dot segment, follow only the default conditional branch, silently drop an escaping/unresolved/wrong-case target, accept `part of`/comment/string decoys as edges, or silently accept malformed syntax -> TC-DTR01-01 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'resolves package relative export part conditional and cyclic directives without comment/string decoys'`; AUTO later `host-all`, existing `test/unit/**` direct-suite classification |
| TC-DTR01-02 | Derive total root-origin reachability with stable precedence; preserve all three manual targets and package boundaries while keeping dispositions separate | `test/unit/runtime_root_inventory_test.dart::main manual tooling test and unrooted buckets stay separate from dispositions` | Host unit / synthetic main; three manual roots with AST main, exact documented command target, and separate policy-owner records; evidenced tool/driver entrypoints; convention-discovered test entrypoint; non-root integration script; descendant packages under both `packages/` and `third_party/`; and imported unrooted island | Causal RED — after the TC-DTR01-01 parser scaffold, no origin model/manual roots exist; GREEN preserves the full origin set, derives main>manual>tooling>test>unrooted reporting buckets, validates/tags all three narrowly policy-backed manual roots, auto-roots convention tests without per-test records, records the non-root script's incoming edge without rooting its lib dependency, discovers/excludes both nested packages and their tests/tools, and reports every unrooted-island member | Fold a lower-priority closure into a higher one, omit a manual/tool/driver root, accept a manual root with missing/mismatched main-command-policy evidence, require per-entrypoint records for convention tests, auto-root all integration scripts, hard-code a `packages/**` boundary, let a nested test/tool seed app reachability, classify only zero-importer island members, or let a disposition rewrite computed origins -> TC-DTR01-02 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'main manual tooling test and unrooted buckets stay separate from dispositions'`; AUTO later `host-all` |
| TC-DTR01-03 | Detect and evidence VM/convention callbacks | `test/unit/runtime_root_inventory_test.dart::vm and convention callbacks require both declaration and registration evidence` | Host unit / FCM pragma+registration and `flutter_test_config.dart::testExecutable` fixtures with comment/string, wrong-annotation, and wrong-callee/argument decoys | Causal RED — the minimal declaration model has no paired callback validator; GREEN emits callback tags only with valid typed declaration and registration relationships | Remove pragma, FCM registration, or convention anchor; move the same literals into comments/strings; or register a different callback while retaining the row -> TC-DTR01-03 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'vm and convention callbacks require both declaration and registration evidence'`; AUTO later `host-all` |
| TC-DTR01-04 | Classify Android and Apple manifest/reflection/extension roots without treating them as Dart importers | `test/unit/runtime_root_inventory_test.dart::native manifest and principal-class evidence yields native-registration tags` | Host unit / parsed Android activity-service-provider-reflection and Apple plist fixtures with wrong-key/element/attribute and comment decoys | Causal RED — the minimal classifier has no native evidence type; GREEN validates exact typed native records without a runtime/deletion claim | Change the manifest/plist structural relationship or target, retain the literal under the wrong key/element, or leave it only in a comment -> TC-DTR01-04 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'native manifest and principal-class evidence yields native-registration tags'`; AUTO later `host-all`; no native execution |
| TC-DTR01-05 | Classify tracked/generated localization, iOS/desktop, and web roots from generator plus invocation evidence | `test/unit/runtime_root_inventory_test.dart::generated localization desktop and web roots require generator ownership and invocation evidence` | Host unit / l10n config+delegate, actual iOS `GeneratedPluginRegistrant.register` call, macOS, Linux, Windows, and web bootstrap fixtures with comment/wrong-callee decoys | Causal RED — the minimal classifier has no generated-root evidence; GREEN distinguishes tracked/optional output and validates its generator/call owner | Remove l10n output/delegate, generated header, actual callsite, bootstrap, or tracked generator evidence; retain the symbol only in a comment or on a wrong callee/argument -> TC-DTR01-05 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'generated localization desktop and web roots require generator ownership and invocation evidence'`; AUTO later `host-all`; no platform build |
| TC-DTR01-06 | Preserve the graph-blind headless plugin boundary | `test/unit/runtime_root_inventory_test.dart::headless plugin requires app dependency package pluginClass native class and shared channel evidence` | Host unit / parsed pubspec+Dart+Kotlin fixture with wrong-key, wrong-class, wrong-channel-call, and comment/string decoys | Causal RED — the minimal classifier has no cross-file plugin evidence; GREEN validates all stable structural declarations without claiming generated execution proof | Remove `pluginClass` or native class, mismatch the channel call, retain values under wrong YAML keys/callees, or leave them only in comments/strings -> TC-DTR01-06 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'headless plugin requires app dependency package pluginClass native class and shared channel evidence'`; AUTO later `host-all`; existing nested major row remains a sentinel |
| TC-DTR01-07 | Distinguish proven tooling/driver roots and their closure from retained-unresolved support | `test/unit/runtime_root_inventory_test.dart::tool command roots its closure while an uncalled support file remains retained-unresolved` | Host unit / parsed Sims command, shell/Dart `--target` and `--driver` relations including `test_driver/integration_test.dart`, tool-reachable lib dependency, uninvoked external main, and orphan support fixture | Causal RED — the minimal classifier cannot distinguish command reachability from an unsupported label; GREEN validates exact target/driver relations as tool roots, assigns their exclusive lib dependency `tooling-reachable`, lists the uninvoked external main without rooting its closure, and keeps the orphan `retained-unresolved` | Promote a discovery label, directory, bare literal, or uninvoked `main()` to tooling/candidate deletion; accept a wrong option/callee/argument; or stop closure at the executable tool/driver file -> TC-DTR01-07 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'tool command roots its closure while an uncalled support file remains retained-unresolved'`; AUTO later `host-all` |
| TC-DTR01-08 | Tag compatibility migration/protocol/export roots without changing their computed reachability | `test/unit/runtime_root_inventory_test.dart::compatibility registries and export facades remain protected by exact evidence` | Host unit / ordered migration, channel/wire/key, and one-line export fixtures with wrong-registry/call/key and comment/string decoys | Causal RED — the minimal classifier has no compatibility evidence; GREEN retains exact typed owner/removal conditions without rewriting computed reachability | Ignore export directives, reorder registry evidence, accept the same token under the wrong registry/callee/key or only in a comment/string, or drop the compatibility tag -> TC-DTR01-08 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'compatibility registries and export facades remain protected by exact evidence'`; AUTO later `host-all` |
| TC-DTR01-09 | Tag pubspec, Android, Apple, and web resources without broad auto-allow | `test/unit/runtime_root_inventory_test.dart::resource roots require exact manifest or catalog ownership evidence` | Host unit / parsed asset directory, exact fixtures, catalog/resource/web icon fixture with wrong-key/element and comment decoys | Causal RED — the minimal classifier has no resource evidence; GREEN explains exact resources by their typed owner anchors and never infers them from Dart imports | Accept an unowned asset, retain its name under a wrong key/element or only in a comment, or remove its manifest/catalog anchor -> TC-DTR01-09 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'resource roots require exact manifest or catalog ownership evidence'`; AUTO later `host-all` |
| TC-DTR01-10 | Reject unsafe, contradictory, or stale declarations | `test/unit/runtime_root_inventory_test.dart::manifest rejects escapes broad globs duplicates overlaps ownerless rows stale evidence and stale candidates` | Host unit / malformed JSON records, valid convention-test closure, and bounded manual-policy record | Causal RED — HEAD has no schema/validator; GREEN requires exact paths, compatible root kinds, exactly one valid disposition, owners/reasons/conditions, and current typed evidence; permits `explained-root` from a validated convention-test origin without an invented root-kind tag; accepts manual-policy only for the three exact configured targets with AST main, matching documented command, and external retention/owner/condition; and permits only narrow generator-owned patterns | Permit `..`, absolute paths, wildcard candidates, duplicate rows, missing/multiple dispositions, unknown or literal-only root evidence, evidence/origin-free `explained-root`, ownerless `deferred-review`, stale evidence, require an invented tag/per-test record for a convention origin, or accept manual-policy for another path or with any missing/mismatched component -> TC-DTR01-10 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'manifest rejects escapes broad globs duplicates overlaps ownerless rows stale evidence and stale candidates'`; AUTO later `host-all` |
| TC-DTR01-11 | Advisory report never promotes or blocks reviewed nonterminal dispositions | `test/unit/runtime_root_inventory_test.dart::report returns zero for candidate deferred-review and retained-unresolved rows without deletion verdicts` | Host unit / candidate, deferred, and unresolved fixture | Causal RED — HEAD has no report interface; GREEN exits `0`, retains typed rows, excludes `dead`/`deletion-safe` from structured dispositions, and never labels a text row with either verdict | Exit `1` for a declared nonterminal row or introduce a `dead`/`deletion-safe` structured/text verdict -> TC-DTR01-11 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'report returns zero for candidate deferred-review and retained-unresolved rows without deletion verdicts'`; AUTO later `host-all` |
| TC-DTR01-12 | Check mode ratchets unreviewed/deleted drift, report remains advisory, CLI boundaries hold, and the complete tree is preserved | `scripts/test/runtime_root_inventory_contract_test.sh::report/check 0-1-2 semantics are deterministic and non-mutating` | Host process / isolated temp Git repository whose repo/manifest paths contain spaces and whose Git-listed Dart fixtures include quote/newline names, invoked both from outside the repo and with canonical defaults; NUL-safe path and full tree path+byte digests including ignored/new files | Causal RED — HEAD has no script/tool; GREEN NUL-parses tracked/non-ignored new sources including the quote/newline paths, excludes ignored output from classification, returns report `0` with explicit drift and check `1` for an ordinary tracked deletion/rename or unreviewed source, returns `2` when a required root/config/Git/parse failure prevents trust, produces parseable stable sorted text/JSON on stdout, sends diagnostics to stderr, passes declared candidates, rejects unknown/missing/duplicate options as `2`, preserves exact argv, and leaves the complete fixture tree unchanged | Split on newline/quotes, make report block on classification drift, treat an ordinary tracked deletion as I/O `2` or a missing root anchor as drift `1`, miss a non-ignored new source, include ignored output, use CWD-relative defaults, drop/splice an argument, accept bad/duplicate options, disable set-diff/stale checks, collapse exit codes, leak chatter to JSON stdout, shuffle output, or create/change/delete any fixture path including ignored output -> TC-DTR01-12 red | `bash scripts/test/runtime_root_inventory_contract_test.sh`; AUTO `sims-contracts` via `scripts/test/*_test.sh` |
| TC-DTR01-13 | Reconcile every current non-main-reachable Dart file, external entrypoint candidate, and representative restricted root | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory` | Host repository contract / real working tree, no fixture mutation | Causal RED — HEAD has only a prose census; GREEN leaves no unreviewed non-main path, validates all three exact manual-policy triples, captures the freshly recomputed exact test/integration-only set as computed explained/deferred states without per-test records or invented tags, accounts for every detected non-convention external entrypoint that can reach app source, validates `test_driver/integration_test.dart` selection and the actual iOS registrant call, keeps six no-importer files as candidates and smoke runner as retained-unresolved, and avoids hard-coded aggregate counts | Remove/change one exact declaration or structural relationship, break a manual main/command/retention-owner triple, replace a call with a comment/wrong callee, strip a downstream owner/condition, add an unreviewed source/external entrypoint, require an invented tag/per-entrypoint record for convention-test reachability, or pin the roadmap's aggregate `60` as an exact path list -> TC-DTR01-13 red | `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'repository manifest accounts for current non-main sources and keeps known candidates advisory'`; AUTO later `host-all` |
| TC-DTR01-14 | Named gate runs the unit suite and real repository check without recursively invoking its own shell contract | `scripts/test/runtime_root_inventory_contract_test.sh::named runtime-roots gate invokes exact unit and check legs once` | Host process / fake command shims plus real gate on GREEN | Causal RED — HEAD `./scripts/run_test_gates.sh runtime-roots` exits unknown-gate `1`; GREEN invokes the unit and real-check legs once, never invokes the contract script from inside itself, propagates the first failing leg, and exits `0` only with trustworthy inventory | Remove the gate branch, omit a leg, swallow its failure, recurse through the contract script, or copy a file list into the wrapper -> TC-DTR01-14 red | `./scripts/run_test_gates.sh runtime-roots`; manual named-gate branch; contract AUTO `sims-contracts` |
| TC-DTR01-15 | Required major/infra registration selects one semantically exact host guard row | `scripts/test/sims_major_plan_contract_test.sh::major plan requires exact runtime.roots.advisory host row`; `test/tool/sims/sims_manifest_test.dart::runtime-root guard has exact required host execution contract` | Host process/unit / canonical manifest and compiled major plan | Causal RED — HEAD manifest/major plan omit DTR-01; GREEN pins the exact id, owner, proof/assertion, `host-dart` lane, major-only/infra selectors, required+active+automation-ready state, two-argument command, `host.flutter_tester` profile, empty dependencies, read-only host CPU, `host.flutter-tester`+`host.bash`+`host.git` targets, `artifactRequired: false`, no validator/N/A allowance, and `declaredBuildException: false` exactly once | Remove/duplicate the row or mutate any pinned selector, command, profile, resource, target, artifact, automation, active, required, N/A, or exception field -> TC-DTR01-15 red | `bash scripts/test/sims_major_plan_contract_test.sh`; `flutter test test/tool/sims/sims_manifest_test.dart`; shell AUTO `sims-contracts`, Dart AUTO later `host-all` |
| TC-DTR01-16 | Existing test completeness remains intact | `test/core/gate_classification_completeness_test.dart::run_test_gates.sh completeness-check classifies every test file (PASS)` | GREEN sentinel / host process | GREEN sentinel — passes on HEAD; GREEN after DTR-01 still prints `Completeness check PASS.` after the new unit/gate tests land | Remove the existing `test/unit/**` classification or leave a new test path unclassified -> TC-DTR01-16 red | `flutter test test/core/gate_classification_completeness_test.dart`; AUTO later `core-host-all`; exact per-plan only |

### Test Notes

- TC-DTR01-01 is the intentional compile RED because the new tool interface
  does not exist on HEAD. TC-DTR01-02 through TC-DTR01-15 are added
  incrementally against the smallest preceding scaffold and must fail by
  assertion or process exit for the missing behavior before each GREEN.
- TC-DTR01-01 uses the analyzer only as a syntax parser. Any source diagnostic
  that makes directive or top-level-main extraction ambiguous is a fatal scan
  result; tests explicitly prohibit a regex/line-parser or empty-edge fallback.
  Package identity and descendant package boundaries come from parsed root and
  nested `pubspec.yaml` files, not hard-coded names/directories.
- TC-DTR01-02/03/07 assert separately reported origins, root kinds, and
  dispositions. A main-reachable file may also be a callback; a zero-importer
  file may be a manual root; a validated tool declaration seeds a factual
  tooling closure; and an unrooted imported island may have nonzero internal
  importer counts. Dispositions never rewrite computed origins or the derived
  reporting bucket. Directory placement, a top-level `main()`, or a bare target
  literal alone never turns a script into a tool root; exact invocation evidence
  does. A manual root requires the bounded main+matching-command+external-policy
  triple; its header comment alone is insufficient. A validated convention-test
  origin may be `explained-root` without a reviewed root-kind tag or one
  manifest row per test entrypoint.
- TC-DTR01-04/05/06/09 use source-shaped fixtures only. They prove the
  classifier recognizes stable evidence; they do not claim that Android, Apple,
  desktop, web, or generated runtime behavior executed. TC-DTR01-03 through
  TC-DTR01-10 pair every positive root-proving predicate with a
  comment/string/wrong-structure negative appropriate to that evidence kind, so
  generic `contains` cannot pass.
- TC-DTR01-10 permits a generator-owned pattern only when its generator/build
  declaration is exact and tracked. It never permits wildcard candidate or
  compatibility allowlisting.
- TC-DTR01-11 and TC-DTR01-12 deliberately separate advisory findings from
  admission integrity: declared candidate/deferred/unresolved rows pass both
  modes; new unreviewed or stale rows are emitted by `report` with exit `0` and
  fail `check` with exit `1` until a human adds a compatible disposition, owner,
  evidence, reason, and condition. Untrustworthy syntax/schema/root/Git failures
  are exit `2` in both modes. TC-DTR01-12 computes its fixture digest from the
  sorted complete path set plus file/link type, executable bit, and bytes before
  and after each default/override invocation; hashing only pre-existing
  classified files is insufficient.
- TC-DTR01-13 validates freshly recomputed exact current paths, external
  entrypoint candidates, and representative structural anchors. The planning
  census may be recorded in report metadata, but numeric totals—including the
  roadmap's aggregate 60—are not acceptance constants.

## Implementation Steps

1. Snapshot `git status --short` and preserve every unrelated user-owned
   modification. Add only TC-DTR01-01, run its exact command, and record the
   intentional compile RED while the imported tool interface is absent.
2. Add the smallest compilable
   `tool/runtime_roots/runtime_root_inventory.dart` parser/closure seam. Add the
   three direct dev-only parser dependencies and resolve the lockfile offline;
   stop if resolution changes packages outside their required transitive
   closure. Make TC-DTR01-01 GREEN with analyzer AST parsing, the root-pubspec
   package name, exact enumerated paths, discovered descendant pubspec
   boundaries, relative/self-package import/export/library-part edges, every
   conditional branch, multiline combinators, comment/string exclusion, cycle
   termination, and injected filesystem/process seams. Syntax ambiguity fails
   closed; do not add a regex/line-parser fallback.
3. Add TC-DTR01-02 through TC-DTR01-10 one at a time against that compiling
   scaffold. Before each matching implementation edit, run its exact
   `--plain-name` command and record an assertion RED. Extend immutable models,
   root-origin sets/bucket precedence, incoming-edge diagnostics, validated
   manual/tool/driver roots, external-entrypoint candidates,
   root-kind/disposition compatibility, typed structural evidence predicates,
   path/schema validation, and deterministic sorting only as each RED requires.
   Implement the three-path manual-policy validator as a closed set requiring
   AST main + exact documented target + external retention/owner/condition, and
   keep convention-test roots computed without individual manifest records.
   Every root-proving evidence kind gets a matching wrong-context decoy before
   GREEN; generic literal containment cannot seed reachability or
   `explained-root`.
4. Add TC-DTR01-11 against the compiling library, record its report-policy
   assertion RED, then add the read-only report model/renderers. Structured
   dispositions remain limited to the reviewed enum; no output labels a path
   dead or deletion-safe.
5. Add TC-DTR01-12 before the process entrypoint and record its independent
   process RED. Then add
   `tool/runtime_roots/runtime_root_inventory_cli.dart` and the root-resolving,
   argument-preserving `scripts/check_runtime_root_inventory.sh` around
   `dart tool/runtime_roots/runtime_root_inventory_cli.dart`. Support only
   `report`/`check`, `text`/`json`, and read-only root/manifest fixture
   overrides; NUL-parse Git results, operate correctly outside the repository
   and with spaced paths, reject unknown/missing/duplicate arguments, classify
   tracked deletion/rename as drift, and enforce clean stdout, diagnostic
   stderr, full-tree non-mutation, and exit `0/1/2`. Provide no
   write/fix/update/delete option.
6. Add TC-DTR01-13 with a deliberately incomplete real-repository manifest and
   record its classification-drift RED. Add schema-versioned
   `tool/runtime_roots/runtime_roots.json`. Populate exact source declarations
   and policy triples for the three manual roots, the freshly recomputed exact
   current test/integration-only set, every detected non-convention external entrypoint
   that can reach app source, the six candidate files, and the
   retained-unresolved smoke runner. Add the representative restricted-root
   evidence enumerated in Scope, including the actual iOS registration call and
   `test_driver/integration_test.dart` invocation.
   Stop-if: any row lacks a source-backed owner/reason/evidence/removal
   condition; keep it retained-unresolved rather than guessing. Stop-if also
   applies if trustworthy disposition would require Graphify/analyzer
   reachability or unused-symbol authority, platform compilation, or network
   access.
7. Add the TC-DTR01-14 named-gate assertion, record unknown-gate exit `1`, then
   add `runtime-roots` to `scripts/run_test_gates.sh`. It runs the unit suite and
   real `check` once, propagates failure, embeds no inventory in shell, and
   never recursively runs its shell contract. The process contract runs
   directly and through `sims-contracts`.
8. Add both TC-DTR01-15 assertions and record their omission REDs. Add the exact
   `runtime.roots.advisory` capability contract from Scope to
   `tool/sims/critical_features.json`; pin the full manifest row and compiled
   major-plan row, not only its id/command.
9. Update `Test-Flight-Improv/ci-gate-handoff.md` and
   `Test-Flight-Improv/test-gate-definitions.md` with the canonical local
   command, advisory/check semantics, and the unresolved external workflow
   owner. Do not copy manifest paths into CI prose.
10. Run focused GREEN, the affected completeness/nested-capability sentinels,
   `runtime-roots`,
   `completeness-check`, `sims-contracts`, the current analyzer-baseline gate,
   direct dependency resolution, full baseline-to-close scope attribution, and
   scoped diff hygiene. Update the DTR roadmap row/evidence to `Plan-green` only
   after all per-plan commands pass. Do not refresh Graphify for this
   tool/script/manifest/package-metadata-only implementation. If execution needs
   any `lib/` change, stop for scope drift and replan; a coherent app-owned
   change would require the normal incremental refresh.

## Rollback

1. Remove the `runtime.roots.advisory` capability and its exact contract
   assertion first so the major plan never references a missing command.
2. Remove the `runtime-roots` gate branch, wrapper, tool, manifest, and their
   unit/process tests as one coherent tooling rollback. Remove the three direct
   dev-only parser dependencies and restore the pre-plan lockfile in the same
   rollback; do not run a broad dependency upgrade.
3. Restore the prior CI/gate handoff and roadmap state, then run
   `./scripts/run_test_gates.sh completeness-check`,
   `flutter test test/tool/sims/sims_manifest_test.dart`, and
   `./scripts/run_test_gates.sh sims-contracts`.
4. No app binary, database, native/generated output, persisted data, protocol,
   asset, or device rollback exists because this plan changes none of them.

## Risks And Blind Spots

- Parser false negative creates a false candidate -> TC-DTR01-01 uses the Dart
  syntax AST, derives package identity, covers current multiline and
  package/relative/export/part/conditional/cycle/decoy shapes, and fails closed
  on syntax ambiguity instead of returning no edges.
- A hard-coded package directory crosses vendored/local package boundaries ->
  TC-DTR01-02 discovers both `packages/` and `third_party/` fixtures from nested
  pubspecs and prevents their tests/tools from seeding app reachability.
- Broad or stale allowlisting hides new debt -> TC-DTR01-10 requires exact
  paths and live evidence; TC-DTR01-12 ratchets drift.
- A root kind overwrites factual reachability -> TC-DTR01-02/03/07 keep the
  axes independent.
- Manual documentation is either ignored or promoted on self-assertion alone ->
  TC-DTR01-02/10/13 require the closed three-target
  main+matching-command+external-policy predicate.
- Convention roots explode into a per-test allowlist -> TC-DTR01-02/10/13
  compute convention reachability without individual test-entrypoint records.
- Literal-only evidence survives in comments or wrong structural contexts ->
  TC-DTR01-03 through TC-DTR01-10 require typed relations and paired negative
  decoys; unstructured literals cannot prove a root.
- A real driver/tool entrypoint is omitted or an uninvoked `main()` is promoted
  -> TC-DTR01-02/07/13 inventory external candidates and require validated
  target/driver relations before their closures become tooling-reachable.
- Static native/generated evidence is mistaken for runtime proof ->
  TC-DTR01-04/05/06 label the boundary and the plan makes no execution claim.
- Optional ignored generated outputs differ by checkout -> manifest validates
  tracked generator/build ownership and does not require ignored output to be
  present.
- Candidate presence makes the advisory command falsely red, or a new
  unreviewed file falsely green -> distinct report/check semantics in
  TC-DTR01-11/12.
- Git quoting, tracked deletions, or hidden writes corrupt the scan ->
  TC-DTR01-12 uses NUL-delimited enumeration, spaced-path/outside-CWD fixtures,
  deletion/rename drift, and a complete path+byte tree digest.
- A filtered closure diff conceals forbidden edits or blames unrelated dirty
  work -> acceptance compares full baseline/close status, patch, and untracked
  evidence, attributes only the DTR delta, and scopes whitespace checks to the
  DTR allowlist.
- External CI remains unwired -> required repo-major registration is causal in
  TC-DTR01-15; the absent external owner remains explicit rather than silently
  claimed.
- Lifecycle / derived-state durability: N/A — no application state or lifecycle
  transition changes.
- Sibling-surface consistency: N/A — no UI or feature surface changes.
- Destructive-action side effects: N/A — the CLI has no mutation option and
  TC-DTR01-12 hashes the fixture before/after.
- Invariant re-verification under new transitions: N/A — no production
  transition is introduced, and the scope guard prohibits production edits.

## Gate Cadence

- Per-plan closure: focused unit/process contracts, exact real-repository
  `check`, named `runtime-roots`, existing `completeness-check`, exact
  Sims-manifest/nested-capability contracts, affected infrastructure
  `sims-contracts`, offline direct-dependency resolution, analyzer-baseline
  gate, scoped diff hygiene, and full out-of-scope baseline preservation.
- No `core-host-all`, `feature-host-all`, performance family, native, simulator,
  relay, device, or SQLCipher proof is justified because no app production
  surface changes.
- Do not run full `host-all` for this individual plan. Wave 0 owns one
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure` after
  DTR-01, DTR-02, and DTR-08 are all `Plan-green`; final rollout/release owns an
  independent full `host-all` run.
- Shared tests outside feature/core globs:
  `test/unit/runtime_root_inventory_test.dart`,
  `scripts/test/runtime_root_inventory_contract_test.sh`,
  `test/tool/sims/sims_manifest_test.dart`, and
  `scripts/test/sims_major_plan_contract_test.sh` run directly during DTR-01.
  Later `host-all`/`sims-contracts` registration does not widen per-plan
  cadence.

## Acceptance Gates

```bash
# Snapshot the complete dirty state outside the repository before execution.
# Keep all artifacts through closure; paths are NUL-delimited where Git supports
# it. The digest helper makes every Git-visible out-of-scope path and byte a
# failing preservation sentinel, including paths that were already dirty.
DTR01_AUDIT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dtr01-audit.XXXXXX")"
dtr01_tree_digest() {
  git ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' dtr01_path; do
      test -e "$dtr01_path" || test -L "$dtr01_path" || continue
      printf '%s\0' "$dtr01_path"
      if test -L "$dtr01_path"; then
        printf 'link\0'
        readlink "$dtr01_path" | shasum -a 256 | awk '{printf "%s%c", $1, 0}'
      else
        if test -x "$dtr01_path"; then
          printf 'executable\0'
        else
          printf 'file\0'
        fi
        shasum -a 256 <"$dtr01_path" | awk '{printf "%s%c", $1, 0}'
      fi
    done
}
dtr01_out_of_scope_digest() {
  git ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' dtr01_path; do
      case "$dtr01_path" in
        pubspec.yaml|pubspec.lock|tool/runtime_roots/*|\
        scripts/check_runtime_root_inventory.sh|scripts/run_test_gates.sh|\
        scripts/test/runtime_root_inventory_contract_test.sh|\
        scripts/test/sims_major_plan_contract_test.sh|\
        test/unit/runtime_root_inventory_test.dart|\
        test/tool/sims/sims_manifest_test.dart|\
        tool/sims/critical_features.json|\
        Test-Flight-Improv/272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md|\
        Test-Flight-Improv/ci-gate-handoff.md|\
        Test-Flight-Improv/test-gate-definitions.md|\
        Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md)
          continue
          ;;
      esac
      test -e "$dtr01_path" || test -L "$dtr01_path" || continue
      printf '%s\0' "$dtr01_path"
      if test -L "$dtr01_path"; then
        printf 'link\0'
        readlink "$dtr01_path" | shasum -a 256 | awk '{printf "%s%c", $1, 0}'
      else
        if test -x "$dtr01_path"; then
          printf 'executable\0'
        else
          printf 'file\0'
        fi
        shasum -a 256 <"$dtr01_path" | awk '{printf "%s%c", $1, 0}'
      fi
    done
}
git status --porcelain=v1 -z >"$DTR01_AUDIT_DIR/status-before.z"
git diff --binary HEAD -- >"$DTR01_AUDIT_DIR/worktree-before.patch"
git ls-files --others --exclude-standard -z \
  >"$DTR01_AUDIT_DIR/untracked-before.z"
dtr01_out_of_scope_digest \
  >"$DTR01_AUDIT_DIR/out-of-scope-before.digest"

# First causal RED after adding the test but before the classifier.
# Expect non-zero because runtime_root_inventory.dart and its behavior are absent.
flutter test test/unit/runtime_root_inventory_test.dart \
  --plain-name \
  'resolves package relative export part conditional and cyclic directives without comment/string decoys'

# Process-contract RED after adding the contract but before the CLI/wrapper.
# Expect non-zero because the read-only report/check entrypoint is absent.
bash scripts/test/runtime_root_inventory_contract_test.sh

# Registration RED on current HEAD. Expect unknown-gate exit 1 because the
# named gate does not exist yet.
./scripts/run_test_gates.sh runtime-roots

# Resolve only the reviewed direct dev dependencies. Expect an offline,
# unrelated-dependency-stable lock resolution.
flutter pub get --offline

# Focused GREEN. Expect exit 0 and zero failed tests.
flutter test test/unit/runtime_root_inventory_test.dart
bash scripts/test/runtime_root_inventory_contract_test.sh

# The real report is advisory and deterministic. Both report invocations exit 0
# even with declared candidate/retained-unresolved rows, JSON is byte-equal, and
# the default-manifest invocations leave repo path set and bytes unchanged.
DTR01_REPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dtr01-runtime-roots.XXXXXX")"
dtr01_tree_digest >"$DTR01_REPORT_DIR/repo-before.digest"
git status --porcelain=v1 -z >"$DTR01_REPORT_DIR/status-before.z"
git diff --binary HEAD -- >"$DTR01_REPORT_DIR/worktree-before.patch"
./scripts/check_runtime_root_inventory.sh report --format json \
  >"$DTR01_REPORT_DIR/report-a.json"
./scripts/check_runtime_root_inventory.sh report --format json \
  >"$DTR01_REPORT_DIR/report-b.json"
cmp "$DTR01_REPORT_DIR/report-a.json" "$DTR01_REPORT_DIR/report-b.json"

# Real admission check. Expect exit 0: every current non-main-reachable path is
# declared, while candidates remain advisory rather than deletion-ready.
./scripts/check_runtime_root_inventory.sh check --format text
dtr01_tree_digest >"$DTR01_REPORT_DIR/repo-after.digest"
git status --porcelain=v1 -z >"$DTR01_REPORT_DIR/status-after.z"
git diff --binary HEAD -- >"$DTR01_REPORT_DIR/worktree-after.patch"
cmp "$DTR01_REPORT_DIR/repo-before.digest" \
  "$DTR01_REPORT_DIR/repo-after.digest"
cmp "$DTR01_REPORT_DIR/status-before.z" \
  "$DTR01_REPORT_DIR/status-after.z"
cmp "$DTR01_REPORT_DIR/worktree-before.patch" \
  "$DTR01_REPORT_DIR/worktree-after.patch"

# Existing test-discovery sentinel. Exits 0 with one passing test.
flutter test test/core/gate_classification_completeness_test.dart

# Canonical named gate and test-discovery integrity. Each exits 0.
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check

# Required major/infra registration. Contract tests below pin the complete
# typed row; list output includes it exactly once. The named gate above is the
# passing execution evidence.
./scripts/run_test_gates.sh sims major \
  --only runtime.roots.advisory \
  --list \
  --format json

# Affected infra contracts. Expect exit 0 and zero failed contract tests.
flutter test test/tool/sims/sims_manifest_test.dart
bash scripts/test/sims_major_plan_contract_test.sh
./scripts/run_test_gates.sh sims-contracts

# Changed-language syntax/format hygiene. Each exits 0.
dart format --output none --set-exit-if-changed \
  tool/runtime_roots \
  test/unit/runtime_root_inventory_test.dart \
  test/tool/sims/sims_manifest_test.dart
bash -n \
  scripts/check_runtime_root_inventory.sh \
  scripts/test/runtime_root_inventory_contract_test.sh \
  scripts/run_test_gates.sh \
  scripts/test/sims_major_plan_contract_test.sh

# Until DTR-02 lands, use the current analyzer ratchet rather than replacing it
# with a strict-analyzer acceptance claim. Expect zero new findings/errors.
./scripts/check_flutter_analyze_baseline.sh

# Hygiene is scoped to DTR-01 because the starting tree has unrelated dirty
# work. First assert every allowed path exists so an rg I/O error cannot turn a
# negated check into a false pass; then require rg's exact no-match status 1.
for dtr01_path in \
  pubspec.yaml \
  pubspec.lock \
  tool/runtime_roots \
  scripts/check_runtime_root_inventory.sh \
  scripts/run_test_gates.sh \
  scripts/test/runtime_root_inventory_contract_test.sh \
  scripts/test/sims_major_plan_contract_test.sh \
  test/unit/runtime_root_inventory_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  tool/sims/critical_features.json \
  Test-Flight-Improv/272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md \
  Test-Flight-Improv/ci-gate-handoff.md \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md; do
  test -e "$dtr01_path"
done
git diff --check HEAD -- \
  pubspec.yaml \
  pubspec.lock \
  tool/runtime_roots \
  scripts/check_runtime_root_inventory.sh \
  scripts/run_test_gates.sh \
  scripts/test/runtime_root_inventory_contract_test.sh \
  test/unit/runtime_root_inventory_test.dart \
  tool/sims/critical_features.json \
  test/tool/sims/sims_manifest_test.dart \
  scripts/test/sims_major_plan_contract_test.sh \
  Test-Flight-Improv/272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md \
  Test-Flight-Improv/ci-gate-handoff.md \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md
DTR01_WHITESPACE_STATUS=0
rg -n '[[:blank:]]+$' \
  pubspec.yaml \
  pubspec.lock \
  tool/runtime_roots \
  scripts/check_runtime_root_inventory.sh \
  scripts/run_test_gates.sh \
  scripts/test/runtime_root_inventory_contract_test.sh \
  scripts/test/sims_major_plan_contract_test.sh \
  test/unit/runtime_root_inventory_test.dart \
  test/tool/sims/sims_manifest_test.dart \
  tool/sims/critical_features.json \
  Test-Flight-Improv/272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md \
  Test-Flight-Improv/ci-gate-handoff.md \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  || DTR01_WHITESPACE_STATUS=$?
test "$DTR01_WHITESPACE_STATUS" -eq 1

# Full dirty-tree closure evidence. These are intentionally unfiltered: compare
# them with the three starting artifacts and attribute every changed or new
# path. Only the explicit DTR-01 allowlist above may be attributable to this
# execution; any new lib/native/local-package/asset/generated/schema/wire path
# blocks closure. Pre-existing unrelated differences remain byte-preserved.
git status --porcelain=v1 -z >"$DTR01_AUDIT_DIR/status-after.z"
git diff --binary HEAD -- >"$DTR01_AUDIT_DIR/worktree-after.patch"
git ls-files --others --exclude-standard -z \
  >"$DTR01_AUDIT_DIR/untracked-after.z"
dtr01_out_of_scope_digest \
  >"$DTR01_AUDIT_DIR/out-of-scope-after.digest"
cmp "$DTR01_AUDIT_DIR/out-of-scope-before.digest" \
  "$DTR01_AUDIT_DIR/out-of-scope-after.digest"
# Review the complete status/patch/untracked before/after artifacts as
# attribution evidence; the digest comparison above automatically fails any
# Git-visible out-of-scope path/content delta.
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-DTR01-01 fails because the classifier is absent;
  TC-DTR01-12 fails because the CLI/wrapper are absent; TC-DTR01-14 fails with
  unknown-gate exit `1` because `runtime-roots` is not a named gate.
- Green sentinels: existing test completeness and the pre-existing nested
  package capability assertions remain green.
- Pre-existing dirty tree / known failure: the planning tree already contains
  user-owned Plan 271/private-media edits, Graphify output, `info.plist`, a
  Docker result, the DTR roadmap, and index changes. Execution must take a fresh
  snapshot, preserve unrelated work, and attribute only DTR-01 files.
- Environment blocker: none. All causal and preservation proof is host-side;
  the three reviewed dev dependencies are available in the current offline
  cache; external CI absence is a scoped follow-up, not a device/environment
  gate.
- Scope drift: any app `lib/`, platform/native, generated, local-package,
  database/schema, asset, protocol/wire, candidate source edit, or automatic
  disposition promotion blocks closure and requires re-planning.

- [x] Every behavior has a named causal test or exact preservation proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red evidence are
      recorded for parser, evidence, advisory, ratchet, non-mutation, and
      registration contracts.
- [x] Every current non-main-reachable Dart path and relevant external
      entrypoint candidate has an exact reviewed declaration; candidate,
      deferred-review, and retained-unresolved rows remain visible and
      non-deletion-ready.
- [x] The real report is deterministic/read-only and the real check passes with
      contracted `0/1/2` semantics.
- [x] `runtime-roots`, `completeness-check`, the affected Sims/nested-capability
      contracts, and `sims-contracts` pass with zero failures.
- [x] The complete typed `runtime.roots.advisory` host contract is active,
      required, and selected exactly once by the major/infra manifest.
- [x] Offline dependency resolution changes only the three reviewed direct dev
      dependencies and their required transitive lockfile closure; the current
      analyzer-baseline gate has no new debt/errors and scoped diff/whitespace
      hygiene is clean.
- [x] The out-of-scope baseline digest is byte-equal at closure; no
      app/native/local-package/schema/wire/asset/generated-output change or
      automatic candidate disposition occurred.
- [x] Scope Contract And Guard and rollback order are respected.

## Handoff

- First causal RED command:
  `flutter test test/unit/runtime_root_inventory_test.dart --plain-name 'resolves package relative export part conditional and cyclic directives without comment/string decoys'`.
- Preservation command:
  `flutter test test/core/gate_classification_completeness_test.dart`.
- Test Contract: 16 canonical rows.
- Tiers / fixtures: host unit and host process only; synthetic temp repositories
  with multiline/invalid syntax, spaced paths, nested packages, structural
  evidence decoys, tracked deletions, and full-tree digests, plus one read-only
  real working-tree reconciliation; no native, SQLCipher, simulator, relay, or
  device fixture.
- Manual registration:
  `runtime-roots` in `scripts/run_test_gates.sh` and required
  `runtime.roots.advisory` in `tool/sims/critical_features.json`.
  Unit tests are AUTO in later `host-all`; the shell contract is AUTO in
  `sims-contracts`.
- Migration: none. Database code and SQLCipher proof are outside this
  tool-only plan.
- Boundary closure: host-only static discovery semantics; no native/generated
  runtime execution claim.
- Wave cadence: DTR-01 per-plan gates above; Wave 0 owns one full `host-all`
  after DTR-01/DTR-02/DTR-08; final rollout/release owns another.
- Confirmed: current census, manual roots, FCM callback registration,
  multiline directives, both descendant package boundaries, the active
  test-driver invocation, representative structural
  native/generated/headless/tooling/compatibility/resource evidence, Git
  tracked-deletion behavior, and absence of an existing production
  reachability guard.
- Refuted: no-importer-is-dead, Graphify/analyzer reachability authority, reuse
  of test-only `classify_path`, and confirmed tooling status for
  `smoke_test_runner.dart`.
- Unresolved evidence: no implementation blocker. The smoke runner remains
  explicitly retained-unresolved, and external CI invocation remains a named
  Release/CI follow-up rather than a claimed repo edit.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-25 | RED and dependency closure | Unit/process/Sims contracts; `pubspec.yaml`; `pubspec.lock` | The three pre-implementation contracts failed for the missing classifier, wrapper, and named gate; `flutter pub get --offline` then resolved the three reviewed direct dev dependencies and required transitive closure only | RED was causal and the dependency cache was sufficient | No environment blocker | Implement only the host-side inventory surface |
| 2026-07-25 | Initial GREEN | `tool/runtime_roots/**`; wrapper; named gate; manifest; docs/tests | Focused unit and process contracts, `runtime-roots`, completeness, Sims manifest/major contract, and registration listing passed | Canonical report accounted for 1,056 files and the required typed capability selected exactly once | Independent counterexample audit still required | Refute false-green paths |
| 2026-07-25 | Independent counterexample audit | Classifier, manifest, process contract | Six false-green classes were reproduced: omitted restricted roots, comment/string evidence, deleted tracked source, invalid descendant packages, incompatible evidence kinds, and loose manual-root evidence | Audit reopened implementation despite the initial green suite | Closure blocked until every mutation re-red | Harden parser, Git deletion channel, root schema, and fixtures |
| 2026-07-25 | Hardened GREEN | Classifier, canonical manifest, unit/process contracts | Unit suite passed 13/13; the process contract passed its report/check `0/1/2`, NUL-safe, deterministic, non-mutating, deletion/rename, malformed-package, structural-evidence, and argument-boundary mutations | All 17 required restricted roots validate; removing or corrupting each reviewed root re-reds | No remaining classifier counterexample | Run affected gate and analyzer closure |
| 2026-07-25 | Focused and affected closure | Named gates; Sims registration/contracts; current analyzer ratchet | `runtime-roots`, `completeness-check`, Sims manifest, major-plan contract, and `sims-contracts` all passed; the legacy analyzer gate reported 0 errors, 0 current warning/info findings, and 0 new debt | `runtime.roots.advisory` remains active/required and its exact typed row is pinned | Full `host-all` intentionally deferred to Wave 0 after DTR-02/DTR-08 | Prove real-tree determinism and hygiene |
| 2026-07-25 | Real-tree preservation and Plan-green closure | Full Git-visible tree; Plan 272; DTR roadmap | Two full JSON reports were byte-identical (`94d66a0ed28ba6b3c9e7db228d8be7473ad3baf32c3e694de32bbb7c302c2d57`); real check was trustworthy/no-drift; pre/post complete status, patch, and path-byte digests matched; diff/format/shell hygiene passed | Census: 986 main-reachable, 3 manual-root, 60 test/integration-reachable, 7 reviewed unrooted; 17/17 restricted roots validated; no app-owned production source changed | None; DTR-01 is Plan-green | Start DTR-02 from this exact state; preserve runtime-root/Sims sentinels |
