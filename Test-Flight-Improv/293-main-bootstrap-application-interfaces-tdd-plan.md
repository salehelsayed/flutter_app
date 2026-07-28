# 293 - DTR-14 main bootstrap application interfaces

Status: Plan-green
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-14`)
Classification: implementation-complete / Plan-green
Closure tier: host
Roadmap ID / wave: `DTR-14` / Wave 4B — Bootstrap and conversation seams
Owner authorization: the current project-owner request explicitly authorizes
planning, critical review, necessary plan repair, and implementation of DTR-14
Date: 2026-07-28

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-28 CEST | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | Initial query was broad; the permitted exact-file refinement anchored `lib/main.dart` and `lib/debug/debug_e2e_composition_root.dart` at current fingerprint `c4692c00a63044ee`. | Verify production phases, callers, tests, and gates in current source. |
| 2026-07-28 CEST | Evidence Collector — production | `lib/main.dart`; `lib/debug/debug_e2e_composition_root.dart`; startup router; FCM background handler; DTR-12 checker | `main.dart` owns entrypoint, preflight, the complete production graph, `runApp`, post-launch work, root widget, lifecycle, notification routing, foreground push, and Move Account refresh. `lib/app/**` is unclassified by the current DTR-12 layer checker and can hold an application composition root without a new exception. | Define a stable application-level phase contract and a bounded move. |
| 2026-07-28 CEST | Evidence Collector — proof | startup/lifecycle/notification/push/account-migration tests; `run_test_gates.sh`; `run_host_test_gates.sh`; DTR-13 contracts | No causal DTR-14 architecture test exists. Existing coverage is preservation-only and 35 test files directly read `lib/main.dart`; those locks must follow the exact new owner instead of being deleted or weakened. | Build one causal boundary row, semantic phase rows, and preservation rows. |
| 2026-07-28 CEST | Existing-coverage probe | seven focused startup/lifecycle/push/Move Account files | Existing baseline passed 26 tests with zero failures. This is preservation evidence only, not DTR-14 RED/GREEN evidence. | Retain the same semantic assertions after ownership moves. |
| 2026-07-28 CEST | Planner | tier matrix; plan template; sufficiency checklist; dirty-tree snapshot | Host closure is sufficient because no schema, native callback, OS delivery, crypto, relay, or cross-device behavior changes. Core and feature family sweeps are justified by 23 core and 13 feature files that directly touch `main.dart`/`MyApp`. | Run the requested independent counterexample review before production edits. |
| 2026-07-28 CEST | Reviewer | Plan 293; exact reset/root/post-launch, Move Account, Firebase registration, and DTR-13 ownership anchors | `plan-fixes-required`: the architecture direction is sound, but fake-only phase tests and broad preservation locks can miss wrong production phase ownership, omitted optional Move Account ports, lost background-handler registration, constructor work before binding, or an asynchronous launch boundary. The current public facade also includes `keychainMirrorBackfill`, and DTR-13 has a single-file entrypoint/order assertion that must become an explicit cross-library proof. | Apply only these verified causal/proof corrections, then close review before RED. |
| 2026-07-28 CEST | Plan Fixer | Plan 293 | Added lazy bootstrap creation after binding, synchronous launch/post requirements, a method-scoped production phase contract, exact Move Account and FCM registration assertions, all three public symbols, and an explicit DTR-13 cross-library phase proof. No product/runtime scope or gate family expanded. | Begin assertion-RED tests. |
| 2026-07-28 CEST | Execution gate auditor | Current live device matrix; `baseline`; `sims-contracts`; exact DTR-13 shell owners | The reviewed commands had two execution-only defects: baseline integration entries were not pinned despite multiple available devices, and the aggregate Sims lane contained an unrelated pre-existing Wave-4A contract stale against its already-moved Android launch helper. | Pin every curated command to discovered `emulator-5556`; retain only the four exact DTR-13 shell contracts affected by this extraction. Do not edit or absorb the unrelated Wave-4A harness contract. |

## Problem And Evidence

- Behavior to improve: application startup must be driven through stable,
  injectable application interfaces while the default `lib/main.dart`
  entrypoint remains supported and every current runtime phase retains its
  order and failure behavior.
- Impact: `lib/main.dart` is 7,262 lines and has 310 imports. It currently
  combines:
  - Flutter binding and disposable-profile preflight at `lib/main.dart:344-356`;
  - launch instrumentation, concurrent share/documents probes, lazy Firebase,
    SQLCipher, security, repository, service, and listener composition at
    `lib/main.dart:357-4845`;
  - pre-`runApp`, root construction, and post-`runApp` work at
    `lib/main.dart:4853-5103`;
  - the `MyApp` application root, lifecycle, notification routing, foreground
    push, and Move Account receiver refresh at `lib/main.dart:5106-7262`.
  A source-string test can observe pieces of this graph, but there is no stable
  application seam that a host test can drive through prepare, root creation,
  launch, and post-launch failure paths.
- Confirmed current gap: `main()` at `lib/main.dart:344` directly performs the
  concrete phases and calls `runApp(MyApp(...))` at `lib/main.dart:4873`;
  neither `ApplicationBootstrap` nor `PreparedApplication` exists, and the
  DTR-12 boundary checker has no main/bootstrap rule.
- Confirmed ordering that must remain:
  - Flutter binding precedes disposable reset; a handled reset launches an
    inert root and returns before `app_start`;
  - share-intent and documents-directory probes start before one joined
    `Future.wait`, and Firebase remains deferred;
  - security/database migrations and global installations finish before
    production runtime construction;
  - debug contact prepopulation is awaited immediately before the root is
    built/launched;
  - sender projection, the `run_app_called` mark, local recovery/sweeps, and
    the conditional intro poller remain after `runApp`;
  - lifecycle resume stays coalesced, pause/detach remain unawaited at the
    observer boundary, foreground push remains readiness-armed/idempotent, and
    Move Account local recovery precedes its network gate.
- Existing coverage:
  - startup:
    `main_parallel_launch_probe_wiring_test.dart`,
    `main_deferred_startup_wiring_test.dart`, startup decision/router suites,
    and the `baseline` gate;
  - lifecycle:
    `test/core/lifecycle/**`, with curated 1:1/group memberships for resume,
    presence, keepalive, recovery, and cleanup;
  - push:
    `test/core/notifications/**`,
    `test/features/push/**`, and curated `1to1`, `intro`, and `groups` rows;
  - Move Account:
    `run_host_test_gates.sh move-feature`, which currently discovers every
    account-migration test plus six shared lifecycle/push/discovery/startup/P2P
    sentinels;
  - DTR-13:
    debug composition phase/order tests and four registered shell contracts in
    `sims-contracts`.
- Missing coverage:
  - an assertion-RED contract proving `main.dart` no longer owns concrete
    composition and delegates through the stable interface;
  - semantic injected-trace tests for binding -> bootstrap creation -> prepare
    -> root creation -> launch -> post-launch order and for
    failure/short-circuit behavior.
- Confirmed source-lock migration risk: 35 current test files read
  `lib/main.dart` directly. Ownership assertions must point to the exact new
  owner (`production_application_bootstrap.dart` or
  `application_root.dart`); they must not concatenate every application source
  into one permissive string.
- Refuted findings:
  - `main.dart` is not currently the largest app source. At this snapshot,
    `group_conversation_wired.dart` is 7,767 lines, `main.dart` is second at
    7,262, and `conversation_wired.dart` is 7,099. The bootstrap hotspot and
    extraction need remain confirmed; only the ranking claim is refuted.
  - a layer-manifest exception is not required: the checker classifies
    `lib/app/**` as unclassified and flags no upward dependency from it.
  - host policy/source proof does not claim to re-prove Firebase/APNs/FCM OS
    delivery. No native callback or payload behavior changes in this plan.
- Unresolved findings: none blocking. Further decomposition of the concrete
  repository/service graph is deliberately deferred because its late-binding
  cycles are DTR-17/DTR-18 work, not evidence that DTR-14 is unsafe.
- Affected production, test, and gate files:
  `lib/main.dart`; new `lib/app/bootstrap/application_bootstrap.dart`,
  `lib/app/bootstrap/production_application_bootstrap.dart`, and
  `lib/app/application_root.dart`; exact source-lock tests under
  `test/core/**`, `test/features/**`, and `test/integration/**`;
  the four DTR-13 shell contracts; `test/unit/runtime_root_inventory_test.dart`;
  `tool/runtime_roots/runtime_roots.json`; `scripts/run_test_gates.sh`; the
  roadmap and index.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `c4692c00a63044ee`; current.
- Initial query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-14 extract lib/main.dart bootstrap phases behind stable application interfaces after lib/debug/debug_e2e_composition_root.dart; startup lifecycle push notification Move Account tests and core/feature gate registrations" --profile tdd --budget 700`.
- Exact permitted refinement:
  `python3 graphify-arch/tdd_context.py query "lib/main.dart bootstrap startup lifecycle push notifications Move Account debug_e2e_composition_root.dart runApp WidgetsBindingObserver" --profile tdd --budget 700`.
- Anchors:
  `lib/main.dart`; package anchor
  `package:flutter_app/debug/debug_e2e_composition_root.dart`;
  `WidgetsBindingObserver`.
- Surfaced proof/gate files:
  `test/core/debug/debug_e2e_composition_root_test.dart`,
  `test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart`,
  and `scripts/run_host_test_gates.sh`/`scripts/run_test_gates.sh` verified in
  source.
- Graph gaps requiring source search: exact bootstrap phases, 35 direct
  `main.dart` source readers, Move Account gate inventory, public `MyApp`
  imports, background-isolate bypass, and DTR-12 path classification.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add `lib/app/bootstrap/application_bootstrap.dart` with:
  - `ApplicationBootstrap.prepare()`;
  - `PreparedApplication.buildRootWidget()` and `afterRunApp()`;
  - an injectable `ApplicationHost` with synchronous binding initialization and
    root launch;
  - `runApplicationBootstrap(...)`, the only phase sequencer.
  The runner accepts a lazy bootstrap factory so binding initialization
  necessarily precedes even construction of the production bootstrap.
- Add `ProductionApplicationBootstrap` in
  `lib/app/bootstrap/production_application_bootstrap.dart`.
  It owns the existing concrete imports, helpers, preflight, persistence,
  repository/service/listener composition, and returns one prepared
  application:
  - handled disposable reset -> inert prepared root, no normal composition;
  - normal prepare -> existing production graph;
  - `buildRootWidget` -> existing awaited contact prepopulation, debug root
    ports, and unchanged `MyApp(...)`;
  - `afterRunApp` -> existing sender projection, startup mark, local
    recovery/sweeps/reconciliation, and conditional poller.
- Move `openIntroNotificationOrbitRoute`, `MyApp`, and `_MyAppState` unchanged
  in behavior to `lib/app/application_root.dart`.
- Keep `lib/main.dart` as the supported default/profile entrypoint. It exports
  `MyApp`, `openIntroNotificationOrbitRoute`, and the current public retained
  `keychainMirrorBackfill` handle for current callers and delegates once to the
  production bootstrap through the stable sequencer.
- Migrate each source lock to its exact owner:
  composition/startup locks read `production_application_bootstrap.dart`;
  root/lifecycle/notification locks read `application_root.dart`; entrypoint
  and profile locks continue to read `main.dart`.
- Repoint the retained group-inbox-cursor source anchor and FCM callback
  registration evidence to `production_application_bootstrap.dart`; preserve
  every runtime-root disposition and restricted-root identity.
- Register the three new bootstrap test files in `BASELINE_TESTS`; they also
  auto-glob into `core-host-all`.

Must preserve:

- Startup parallelism, lazy Firebase, resumable live-service steps, and
  retained keychain backfill ->
  `main_parallel_launch_probe_wiring_test.dart` and
  `main_deferred_startup_wiring_test.dart`.
- Lifecycle dispatch, coalescing, resume ordering, presence/keepalive,
  cleanup, pause, and detach ->
  `test/core/lifecycle/**`.
- Push readiness, exact route event discrimination, cancellation, dedupe,
  home-ready deferral, and foreground handling ->
  `main_deferred_push_rearm_wiring_test.dart`,
  `test/core/notifications/**`, and `test/features/push/**`.
- Move Account startup/cutover/receiver semantics and local-before-network
  recovery -> `./scripts/run_host_test_gates.sh move-feature`.
- DTR-13 reset/auto-setup/prepopulation/overlay/runtime-ready/sender/poller
  phases, all build profiles, and `lib/main.dart` targeting ->
  debug composition tests plus the four affected registered shell contracts.
- Public `package:flutter_app/main.dart` access to `MyApp`,
  `openIntroNotificationOrbitRoute`, and `keychainMirrorBackfill`.
- The FCM background handler remains a standalone restricted
  `@pragma('vm:entry-point')` boundary and must not depend on the foreground
  prepared application.

Hard `Do not`:

- Do not change payload parsing, notification event selection/navigation,
  lifecycle operation labels, Move Account authority/cutover behavior, schema,
  migration order, native callbacks, relay/crypto/wire behavior, build
  profiles, entrypoint targets, or runtime timing semantics.
- Do not change the existing `MyApp` constructor or downstream widget APIs.
- Do not decompose `P2PServiceImpl`, `GroupMessageListener`, or conversation
  controllers; do not relocate feature implementations; those belong to
  DTR-15 through DTR-18.
- Do not add/rebaseline a DTR-12 architecture exception.
- Do not satisfy the boundary test with comments, generated code, a source
  concatenation helper, or by moving all 7,262 lines into one renamed file.

Deferred / accepted difference:

- The concrete production graph remains one private implementation library
  during DTR-14 because its real late-bound cycles require a separately
  reviewable DTR-17/DTR-18 decomposition. The stable bootstrap/prepared/host
  interfaces and separate application-root owner are the DTR-14 seam.
- Existing `main_*` test filenames may remain for gate/backward compatibility;
  their descriptions and source paths must identify the new exact owner.
- DTR-15 owns conversation-controller extraction; DTR-17 owns the P2P split;
  DTR-18 owns broader layering relocation.

Dependencies:

- DTR-13 is Plan-green/Wave-accepted and its exact preservation contract is an
  input. The current owner request supplies the previously missing DTR-14
  execution authority.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-293-01 | `main.dart` is a real thin entrypoint whose live `main()` body delegates exactly once through stable application interfaces, preserves its three current public symbols, and owns no concrete Firebase/DB/P2P/root-state composition or executable top-level bootstrap initialization | `test/core/bootstrap/main_bootstrap_boundary_test.dart::DTR-14 main delegates bootstrap through stable application interfaces` | Host syntax/source/compile contract / real repository files | causal assertion RED: current `main.dart` owns concrete composition and stable files are absent -> GREEN: the live body, allowlisted imports/exports, exact files, and delegation exist; `main.dart` has no feature/core/debug imports, concrete constructors, `MyApp(` call, root-state class, unused delegation helper, or eager bootstrap instance; production/root libraries do not import `main.dart`; `MyApp`, `openIntroNotificationOrbitRoute`, and `keychainMirrorBackfill` remain addressable through `package:flutter_app/main.dart` | hide delegation in an unused helper/barrel, eagerly initialize the bootstrap, reintroduce `Firebase.initializeApp`, `openEncryptedDatabase`, `P2PServiceImpl`, `MyApp(`, `_MyAppState`, a feature import, or production->main import; duplicate declarations; remove a public symbol -> TC-293-01 red | `flutter test --no-pub test/core/bootstrap/main_bootstrap_boundary_test.dart --plain-name 'DTR-14 main delegates bootstrap through stable application interfaces'`; add path to `BASELINE_TESTS`; AUTO `core-host-all` |
| TC-293-02 | Normal application launch is ordered synchronous binding -> bootstrap creation -> prepare -> awaited root build -> synchronous host launch -> synchronous post-launch kickoff, once each and with the same root identity | `test/core/bootstrap/application_bootstrap_test.dart::runs binding bootstrap creation prepare root launch and post-launch in order` | Host unit / lazy fake factory, fake bootstrap, prepared application, and host trace | intentional compile RED after test addition: interfaces absent -> GREEN: exact ordered trace and identical root object, with no microtask turn between launch and post | construct bootstrap before binding, move post-launch before host launch, make launch/post asynchronous, omit an await, call a phase twice, or substitute the root -> TC-293-02 red | `flutter test --no-pub test/core/bootstrap/application_bootstrap_test.dart --plain-name 'runs binding bootstrap creation prepare root launch and post-launch in order'`; add path to `BASELINE_TESTS`; AUTO `core-host-all` |
| TC-293-03 | Phase failures remain fail-fast: bootstrap-factory failure prevents prepare/root/launch/post; prepare failure prevents root/launch/post; root-build failure prevents launch/post; host-launch failure prevents post; post failure propagates after one launch. The real production handled-reset branch launches only the inert prepared root and never enters normal composition | `test/core/bootstrap/application_bootstrap_test.dart::propagates each phase failure without running later phases`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::handled production reset bypasses normal composition` | Host unit + production control-flow fixture / injected throwing factory/phases, injectable production reset and normal-composition probe | intentional compile/assertion RED -> GREEN: exact exception identity, negative trace assertions, and production reset `true` never touches the normal composition probe | catch/swallow a factory/phase error, use `whenComplete` for post-launch, ignore reset result, continue normal composition after terminal reset, or invoke a later phase -> TC-293-03 red | focused bootstrap command; add both paths to `BASELINE_TESTS`; AUTO `core-host-all` |
| TC-293-03A | Reachable production methods own the correct phases: terminal reset returns before normal composition; normal preparation owns the graph and lazy Firebase registration; root build owns awaited prepopulation plus direct `MyApp(...)`; post-launch exclusively owns sender projection, immediate startup mark, recovery/sweeps/reconciliation, and conditional poller | `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::DTR-14 production bootstrap owns each reachable phase exactly once` | Host balanced method/source contract / exact production implementation | causal assertion RED: implementation file/methods absent -> GREEN: balanced-body slices and their direct call bridge establish exact ownership and exclusivity rather than merely finding tokens somewhere in the file | move a phase to a dead helper/wrong method, break the prepare-to-normal call bridge, duplicate a token, or leave post-launch work in root build -> TC-293-03A red | focused bootstrap command; add path to `BASELINE_TESTS`; AUTO `core-host-all` |
| TC-293-04 | Startup retains concurrent launch probes, lazy Firebase, resumable exactly-once live-service steps, unconditional deferred runtime startup, and off-critical-path retained keychain backfill after ownership moves | `test/core/lifecycle/main_parallel_launch_probe_wiring_test.dart::TC-164-03 share-intent probe and docs-dir run concurrently (Future.wait); Firebase stays uniformly deferred`; `test/core/lifecycle/main_deferred_startup_wiring_test.dart::TC-16a every fallible live-service startup step is resumable and run once`; `::TC-164-01 main wires the live-services outcome wrapper as unconditional deferredRuntimeStartup and drops both eager pre-runApp awaits`; `::TC-164-06 the keychain mirror runs OFF the critical path but is guaranteed to run (retained, not dropped)` | Host source/behavior preservation / exact production bootstrap owner | GREEN sentinel on current source -> remains GREEN against `production_application_bootstrap.dart` with assertions unchanged semantically | serialize either probe, eagerly await Firebase/live services, remove a startup checkpoint, or drop/await the mirror before launch -> TC-293-04 red | `flutter test --no-pub test/core/lifecycle/main_parallel_launch_probe_wiring_test.dart test/core/lifecycle/main_deferred_startup_wiring_test.dart`; AUTO `core-host-all`; startup surface also selected by `./scripts/run_test_gates.sh baseline` |
| TC-293-05 | Application lifecycle retains observer dispatch, foreground/background presence and keepalive, coalesced resume, pause/detach async ownership, upload/recovery ordering, and cleanup | `test/core/lifecycle/main_presence_lifecycle_wiring_test.dart::TC-181-W2: resume announces foreground, unawaited`; `test/core/lifecycle/main_keepalive_wiring_test.dart::TC-183-52: cold start arms the keepalive + presence when launched foreground`; full `test/core/lifecycle/**` | Host application/source + fakes; no OS callback claim | GREEN sentinel -> same tests target `application_root.dart` or behavior units and remain GREEN | remove resumed/paused/detached branch discrimination, await the best-effort presence edge, weaken `_isResuming`, reorder local recovery behind the network gate, or omit disposal -> TC-293-05 red | `flutter test --no-pub test/core/lifecycle`; AUTO `core-host-all`; curated coverage in `1to1`, `groups`, and `move-feature` |
| TC-293-06 | Push/notification behavior retains retryable Firebase readiness, one listener arm, exact route/event discrimination, cancellation/dedupe/home-ready deferral, staged-ingest preparation, foreground routing, and exact background-handler registration inside the successful Firebase initializer while the independently annotated handler remains headless | `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart`; `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart::191: listener arm rides Firebase readiness and emits PUSH_LISTENERS_ARMED`; `test/core/notifications/intro_accept_open_coordinator_wiring_test.dart::main intros branch wires the accept open coordinator`; full `test/core/notifications/**` and `test/features/push/**` | Host application/unit/integration / fakes and exact owner locks | GREEN sentinel -> source locks follow bootstrap or root owner, the production `FirebaseReadiness.initialize` closure registers `firebaseMessagingBackgroundHandler`, its owner retains `@pragma('vm:entry-point')`, and behavior suites remain GREEN | remove/move registration outside the initializer, remove readiness/idempotence, route a sibling event, use a bare pop/wrong target, suppress the wrong notification, omit staged ingest, or weaken exact cancellation -> TC-293-06 red | focused bootstrap test; `flutter test --no-pub test/core/notifications test/features/push`; AUTO core/feature families; selected by `1to1`, `intro`, and `groups` |
| TC-293-07 | Move Account bootstrap/resume/receiver handoffs remain present; every current optional Move Account port is passed exactly once in the reachable direct `MyApp(...)` construction; interrupted export recovery and local cleanup precede network gating; post-cutover push registration remains safe | `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart`; `test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart::handleAppResumed — stale export-pause recovery recovery runs BEFORE the migration network gate`; `test/features/push/application/push_registration_post_cutover_test.dart`; complete `move-feature` inventory | Host application/integration / exact production construction plus fake network and existing fixtures | GREEN sentinel -> exact Move Account arguments survive in the reachable root-building method and all move-feature paths remain GREEN after relocation | omit/rebind `runOldPhoneTransfer`, size gate, receiver start/stop/events, or interrupted-export recovery; recover after the network gate; start networking while old phone is blocked; skip post-cutover registration -> production phase contract or TC-293-07 red | focused bootstrap test; `./scripts/run_host_test_gates.sh move-feature --batch-flutter --concurrency 4 --reporter failures-only`; named family inventory |
| TC-293-08 | DTR-13 reset, auto-setup, prepopulation, overlay/node/runtime-ready, sender, recovery, and poller phases retain their order while `lib/main.dart` remains every current default/profile target | `test/core/debug/debug_e2e_composition_root_test.dart::composition phases preserve reset auto-setup runApp fixture runtime-ready and poller ownership`; `scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh` and the registered voice/notification/private-media contracts | Host source/process preservation / explicit entrypoint, production phase, root, profile, and script owners | GREEN sentinel -> the former single-file order assertion becomes explicit entrypoint delegation plus method-scoped production ordering (never a concatenated source string); every target/profile remains unchanged and `void main() async` remains the supported entrypoint signature | start reset after normal composition, move prepopulation after launch, start sender/poller before launch, satisfy order with tokens in unrelated/dead files, import `main.dart` from the debug root, or change a target/define -> TC-293-08 red | focused production phase contract; `flutter test --no-pub test/core/debug/debug_e2e_composition_root_test.dart test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart`; run the four exact affected DTR-13 shell contracts named below; AUTO core + registered shell contracts |
| TC-293-09 | Shared source-lock owners outside core/feature families retain group-media, reaction, Android push registration, direct-text, and iOS background wiring after the move | `test/integration/android_group_media_reliability_controller_test.dart`; `test/integration/group_media_ios_background_recovery_test.dart`; `test/integration/reaction_notification_proof_support_test.dart`; `test/integration/android_push_relay_registration_contract_test.dart`; `test/integration/direct_text_public_relay_contract_test.dart` | Host shared integration/source contracts / fakes and real source files | GREEN sentinel -> exact owner paths change, assertions do not weaken | point a lock at the wrong owner, drop a construction/handoff, or accept a concatenated application-source blob -> corresponding file red | `flutter test --no-pub test/integration/android_group_media_reliability_controller_test.dart test/integration/group_media_ios_background_recovery_test.dart test/integration/reaction_notification_proof_support_test.dart test/integration/android_push_relay_registration_contract_test.dart test/integration/direct_text_public_relay_contract_test.dart`; exact direct registration because core/feature globs do not include `test/integration/**` |
| TC-293-10 | Extraction introduces no architecture exception, unclassified runtime root, or unregistered test | `test/unit/architecture_boundary_checker_test.dart::canonical DTR-12 manifest pins 182 dependency and 24 placement exceptions`; runtime-root/completeness named lanes | Host tool / real repository | GREEN sentinel -> counts stay exact and new paths are classified/discovered | add/rebaseline an exception, omit a runtime-root disposition, or leave a test unclassified -> named lane red | `./scripts/run_test_gates.sh architecture-boundaries`; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh completeness-check`; named lanes |

### Test Notes

- TC-293-01 must inspect the live `main()` body, imports/exports, declarations,
  and executable top-level initialization; a raw LOC/token-only assertion or
  delegation hidden in an unused helper is insufficient.
- TC-293-02/03 use an event trace plus negative events. A broad "completed"
  boolean would pass if prepare/build/launch/post were reordered.
- TC-293-03A must slice balanced bodies of the actual reachable concrete
  methods. Token presence anywhere in the production file, a concatenated
  source string, or an uncalled helper is insufficient.
- Migrated source locks must read one exact owner. Where one legacy test
  genuinely asserts both composition and root behavior, split its assertions
  between two explicit variables rather than joining sources.
- The background FCM handler is a bypass boundary, not a prepared-application
  consumer. Preserve its registration from the production bootstrap while the
  callback stays independently importable/headless.

## Implementation Steps

1. Snapshot `git status --short` and preserve the existing DTR-13/Wave-4A dirty
   tree. Add TC-293-01 first and record its assertion RED on the concrete
   `main.dart` ownership.
2. Add TC-293-02/03/03A, then add the minimum
   `application_bootstrap.dart` scaffold. Stop-if the runner cannot express
   binding -> lazy bootstrap creation -> prepare -> awaited root -> synchronous
   launch -> synchronous post without changing current failure propagation or
   inserting a microtask boundary.
3. Implement the stable runner and production bootstrap:
   - keep binding initialization in the injectable host;
   - move the reset/preflight and current concrete graph into
     `ProductionApplicationBootstrap.prepare`;
   - return an inert prepared application for handled reset;
   - return the normal `MyApp` root from the awaited root-building phase;
   - retain all current post-launch work in `afterRunApp`.
4. Move `openIntroNotificationOrbitRoute`, `MyApp`, and `_MyAppState` to
   `application_root.dart` without changing constructor or behavior. Preserve
   all three current public `main.dart` symbols, including the retained
   `keychainMirrorBackfill` handle. Stop-if any supported import, profile
   target, or background entrypoint cannot resolve without a cycle.
5. Reduce `main.dart` to one stable production delegation. Keep the production
   bootstrap and application root cycle-free and forbid either from importing
   `main.dart`.
6. Migrate all direct `main.dart` source locks to their exact owner; update the
   four DTR-13 shell contracts and shared `test/integration/**` contracts.
   Preserve assertions and ordering; do not replace them with existence-only
   checks.
7. Add the three new test files to `BASELINE_TESTS`; verify discovery and run focused
   GREEN plus representative mutations for TC-293-01, TC-293-02, TC-293-05,
   TC-293-06, and TC-293-07.
8. Run the exact preservation, curated, move, affected core/feature, policy,
   analysis, and hygiene gates below. Refresh Graphify incrementally once after
   the coherent app-owned change.

## Risks And Blind Spots

- Phase extraction could silently move awaited work across `runApp` -> guarded
  by TC-293-02/03, TC-293-04, and TC-293-08.
- A moved source lock could go green against the wrong file or duplicated
  token -> exact-owner variables plus TC-293-01/09.
- Late-bound repository/listener cycles could be "cleaned up" into a different
  construction order -> production graph stays one private concrete
  implementation; TC-293-04/08 and affected families guard behavior.
- Background-isolate bypass -> FCM handler remains independent; DTR-13/profile
  and push contracts guard registration without claiming an OS-delivery rerun.
- Public facade drift -> TC-293-01 compiles existing
  `package:flutter_app/main.dart` users and checks all three current symbols.
- Constructor/plugin timing -> the lazy factory and TC-293-02 lock binding
  before production-bootstrap construction.
- Synchronous launch boundary -> TC-293-02 locks launch and post-launch kickoff
  in one synchronous trace without a microtask.
- Lifecycle / derived-state durability: TC-293-05 plus full lifecycle suite;
  no marker/storage semantics change.
- Sibling-surface consistency: TC-293-06 plus `1to1`, `intro`, and `groups`
  preserve direct/group/introduction routing separately.
- Destructive-action side effects: N/A — no delete, cleanup policy, schema, or
  persisted state changes; existing cleanup behavior is preservation-only.
- Invariant re-verification under new transitions: TC-293-03 tests every phase
  failure boundary; TC-293-05/07 retain resume re-entry and Move recovery.

## Gate Cadence

- Per-plan closure:
  - TC-293-01 causal RED/GREEN and TC-293-02/03 semantic GREEN;
  - exact migrated startup/lifecycle/push/DTR-13/shared source locks;
  - full host lifecycle and notification directories;
  - `baseline`, `1to1`, `intro`, `groups`, `transport`, the four exact affected
    DTR-13 shell contracts, and `move-feature`;
  - justified `core-host-all` and `feature-host-all` because the extraction
    changes the owner read by 23 core and 13 feature tests;
  - architecture, runtime-root, completeness, strict-analysis, and diff gates.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 4B dependency
  batch (DTR-14 plus DTR-15), and once at final rollout/release closure.
- Shared tests outside feature/core globs: run the five exact
  `test/integration/**` paths in TC-293-09 directly.
- `performance-host`: N/A — structural extraction preserves current timing
  contracts and adds no quantitative performance claim.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated DTR-13/Wave-4A work.
git status --short

# First causal RED before production edits: expect non-zero because current
# main.dart owns concrete composition and stable interface files are absent.
flutter test --no-pub \
  test/core/bootstrap/main_bootstrap_boundary_test.dart \
  --plain-name 'DTR-14 main delegates bootstrap through stable application interfaces'

# Focused GREEN: expect exit 0, exact ordered/negative traces and concrete
# method ownership, zero failures.
flutter test --no-pub \
  test/core/bootstrap/main_bootstrap_boundary_test.dart \
  test/core/bootstrap/application_bootstrap_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart

# Startup/lifecycle/push exact owners: exit 0, zero failures.
flutter test --no-pub \
  test/core/lifecycle \
  test/core/notifications \
  test/features/push

# DTR-13 structural preservation: exit 0, exact phase ownership retained.
flutter test --no-pub \
  test/core/debug/debug_e2e_composition_root_test.dart \
  test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart
bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh
bash scripts/test/voice_message_prebuilt_runner_contract_test.sh
bash scripts/test/notification_tap_campaign_adapter_contract_test.sh
bash scripts/test/private_media_outbox_restore_sims_adapter_contract_test.sh

# Shared source-locks outside core/feature family globs: exit 0.
flutter test --no-pub \
  test/integration/android_group_media_reliability_controller_test.dart \
  test/integration/group_media_ios_background_recovery_test.dart \
  test/integration/reaction_notification_proof_support_test.dart \
  test/integration/android_push_relay_registration_contract_test.dart \
  test/integration/direct_text_public_relay_contract_test.dart

# Curated startup/push/sibling preservation: each exits 0 with its final PASS.
FLUTTER_DEVICE_ID=emulator-5556 ./scripts/run_test_gates.sh baseline
FLUTTER_DEVICE_ID=emulator-5556 ./scripts/run_test_gates.sh 1to1
FLUTTER_DEVICE_ID=emulator-5556 ./scripts/run_test_gates.sh intro
FLUTTER_DEVICE_ID=emulator-5556 ./scripts/run_test_gates.sh groups
FLUTTER_DEVICE_ID=emulator-5556 ./scripts/run_test_gates.sh transport

# Move Account and affected families: each exits 0 with zero failed tests.
./scripts/run_host_test_gates.sh move-feature \
  --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Policy/discovery: exit 0; no new/stale exception or unclassified path.
./scripts/run_test_gates.sh architecture-boundaries
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check

# Hygiene: zero new analyzer diagnostics and no whitespace errors.
./scripts/check_flutter_analyze_strict.sh
git diff --check

# Coherent app-owned graph update after tests/code settle.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-293-01 fails on current concrete ownership, not on a missing
  test fixture or unrelated analyzer error.
- Green sentinel: the 26-test planning probe and every TC-293-04 through
  TC-293-10 preservation contract remain green against the exact new owner.
- Pre-existing dirty tree / known failure: DTR-13/Wave-4A plans, source,
  scripts, tests, evidence, and graph outputs are pre-existing user-owned work;
  preserve them and attribute any failure before editing it.
- Environment blocker: none for host closure. The pre-existing baseline and
  transport integration entries are pinned to the discovered available Android
  emulator `emulator-5556`; they do not add an OS-specific behavior claim.
  Unavailable device versions are N/A by project policy.
- Scope drift: any schema/native/wire/payload behavior change, new architecture
  exception, changed profile/entrypoint, changed `MyApp` constructor, or
  production service decomposition blocks completion and requires replanning.

- [x] Every behavior has a named test or justified proof.
- [x] TC-293-01 assertion RED, focused GREEN, and representative mutation
      re-reds are recorded.
- [x] Startup, lifecycle, push, Move Account, DTR-13, and shared exact-owner
      preservation tests pass.
- [x] `baseline`, affected curated lanes, `move-feature`, `core-host-all`, and
      `feature-host-all` pass with semantic outcomes.
- [x] New test files are registered in `BASELINE_TESTS` and discovered by
      `core-host-all`.
- [x] DTR-12 counts remain exact; runtime roots/completeness remain trustworthy.
- [x] Strict analysis has no new issue; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected and Graphify is refreshed once.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/core/bootstrap/main_bootstrap_boundary_test.dart --plain-name 'DTR-14 main delegates bootstrap through stable application interfaces'`.
- Preservation command:
  `flutter test --no-pub test/core/lifecycle/main_parallel_launch_probe_wiring_test.dart test/core/lifecycle/main_deferred_startup_wiring_test.dart test/core/lifecycle/main_presence_lifecycle_wiring_test.dart test/core/lifecycle/main_keepalive_wiring_test.dart test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart test/core/notifications/intro_accept_open_coordinator_wiring_test.dart test/core/lifecycle/handle_app_resumed_export_pause_recovery_test.dart`.
- Manual registration: add TC-293-01, TC-293-02/03, and TC-293-03A test paths
  to `BASELINE_TESTS`; core family discovery is automatic.
- Migration: none.
- Boundary closure: host-only structural/application proof; no OS/native,
  device, relay, crypto, or schema boundary changes.
- Unresolved evidence: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-28 CEST | review closed | Plan 293 | independent counterexample audit plus current-source verification | Five reviewer gaps and two independently verified facade/ownership gaps were repaired without expanding production scope or gate families. | none; final review verdict `implementation-ready` | assertion RED |
| 2026-07-28 CEST | causal RED | `test/core/bootstrap/main_bootstrap_boundary_test.dart` | exact named `flutter test --no-pub ... --plain-name ...` exited 1 after compiling and running | Expected one live delegation statement; actual current `main()` has 234 statements. Failure is the intended concrete-ownership assertion, not a missing fixture or analyzer error. | none | implement stable runner and extraction |
| 2026-07-28 CEST | semantic RED | `test/core/bootstrap/application_bootstrap_test.dart` | exact file command exited 1 at compile | Expected compile RED: `application_bootstrap.dart` and its runner/interfaces do not yet exist. | none | add minimum stable interface |
| 2026-07-28 CEST | implementation GREEN | `lib/main.dart`; `lib/app/**`; three bootstrap tests; migrated exact-owner locks | Focused final restoration command passed 11/11; broad startup/lifecycle/notification/push passed 825/825; shared integration passed 142/142; DTR-13 structure passed 5/5 and its four affected shell contracts all reported PASS. | `main.dart` is 14 lines; stable runner 45; concrete bootstrap 5,225; application root 2,295. Public facade, reset, startup, lifecycle, push, Move Account, and DTR-13 ownership are preserved. | none | mutation and family gates |
| 2026-07-28 CEST | mutation re-red | TC-293-01/02/05/06/07 owners | Five temporary mutations each exited 1 for the intended causal assertion: removed entrypoint `await`; bootstrap factory before binding; paused->inactive lifecycle edge; duplicate FCM registration; omitted Move Account size gate. Final restoration passed 11/11. | The contracts discriminate ordering, lifecycle dispatch, exact callback registration, and optional-port loss rather than only compiling the extraction. | none | acceptance matrix |
| 2026-07-28 CEST | curated and Move closure | explicit `emulator-5556`; named gates | `baseline`: 148 host + 6 + 1 emulator tests; `1to1`: 2,441 plus Go tails; `intro`: 300; clean isolated `groups`: 3,239 plus all Go/toolchain tails; `transport`: 21/21 wrappers and 4/4 internal scenarios; `move-feature`: 497 pass, 1 skip. All final commands exited 0. | An overlapping diagnostic attempt produced only load/time-out contamination; the clean sequential reruns are the acceptance evidence. | none | affected families |
| 2026-07-28 CEST | affected family closure | `core-host-all`; `feature-host-all` | Core: 365 items, 2,830/2,830 plus renderer tail, exit 0. Feature: 805 paths, 8,416 pass, 1 declared SQLCipher integration skip, 0 fail, exit 0. | Full per-plan affected families are green; full `host-all` remains Wave 4B work after DTR-15. | none | policy/hygiene |
| 2026-07-28 CEST | policy and final hygiene | DTR-12; runtime roots; completeness; analyzer; Graphify | Architecture 6/6 with 1,029 sources, 182 dependency and 24 placement pins, zero issues; runtime roots 20/20, trustworthy/no drift; completeness 1,349/1,349; strict analysis zero diagnostics; `git diff --check` clean. Incremental Graphify refresh: 62,934 nodes / 94,662 edges; overlay 1,450 files / 14,176 tests / 1,089 targets; fingerprint `e9799c1d98ffcf86`. | The only runtime-root change is exact evidence ownership; no disposition, boundary exception, schema, native, wire, profile, or entrypoint changed. | none | Plan-green |

## Reviewer Findings

Initial verdict: **plan-fixes-required**. Core bet: **confirmed**.
Disposition: **apply-plan-fixes**.

- L1 evidence truth — cleared after correcting the public facade from two to
  three current symbols and preserving the supported `void main() async`
  entrypoint.
- L2 test causality — repaired with a balanced, method-scoped production phase
  contract, a real handled-reset control-flow fixture, exact Move Account
  construction assertions, and factory-failure coverage.
- L3 bypass/scope safety — repaired by proving the production Firebase
  initializer registers the independently annotated headless handler and by
  rejecting dead-helper/wrong-method token placement.
- L4 gate integrity — repaired only by registering the additional focused
  production contract in `BASELINE_TESTS`; no broader family or full
  `host-all` was added.
- L5 state transitions/timing — repaired with binding-before-bootstrap-factory
  creation and synchronous host launch/post-launch kickoff.

Blind spots hit and closed: B-2 bypassing entrypoints, B-4 vacuous contract,
B-7 technical mechanism, and B-9 untested preservation. The DTR-13
single-source phase assertion must be migrated to explicit entrypoint and
method-owner proofs, never a permissive concatenated string.

Final verdict after the verified plan fixes: **implementation-ready**.

Execution counterexample amendment: the initial unpinned baseline command and
the over-broad aggregate Sims command were corrected exactly as recorded above.
The aggregate diagnostic reached an unrelated pre-existing Wave-4A assertion
that still expects an inline Android status regex after that dirty worktree
already delegated to `isAndroidActivityStartAccepted`. DTR-14 neither edits nor
claims that harness repair; all four DTR-13 contracts whose ownership DTR-14
actually changed pass. Final implementation verdict: **Plan-green**.
