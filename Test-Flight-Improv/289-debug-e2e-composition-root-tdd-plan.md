# 289 - DTR-13 debug/E2E composition root isolation

Status: Implementation complete / four coherent-source live blockers green — final host, Graphify, and Wave 4A aggregate closure pending
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-13`)
Classification: implemented; live acceptance green; Plan-green awaits final integrated host/graph receipts
Closure tier: host + availability-bounded affected simulation
Roadmap ID / wave: `DTR-13` / Wave 4A — Boundaries and composition roots
Owner authorization: `DTR13-AUTH-01`; narrow blocker follow-ups authorized by `W4A-BLOCKERS-AUTH-01`
Date: 2026-07-27

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-27 | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | Fingerprint `332fe23f228dfb75` was current and anchored the registered smoke roots, but did not surface `lib/main.dart` or the active controller/poller composition. | Verify the production seam, Sims manifests/build orchestration, runtime-root policy, scripts, tests, and gates in source. |
| 2026-07-27 | Evidence Collector — production | `lib/main.dart`; 16 directly imported harness libraries; production lifecycle/startup wiring; harness implementations | Reset, five controller/observer constructions, simulator auto-setup, contact fixture loading, iOS sender/receiver fixtures, disposable transport override, overlay, and one process-global poller are currently composed from `main.dart`. `TransportMetrics` is live production diagnostics and is not DTR-13 harness wiring. | Define a phased, nullable composition seam that preserves ordering and exact workflow activation. |
| 2026-07-27 | Evidence Collector — profiles/workflows | `tool/sims/critical_features.json`; `tool/sims/build_orchestrator.dart`; all profile contracts; manual roots; reliability discovery; headless runners | There are exactly 10 profiles. Six built profiles resolve to `lib/main.dart`, two use separate integration roots, and two host profiles build nothing. All existing roots, defines, commands, override behavior, artifact types, and profile handshakes must remain byte-for-byte equivalent. | Pin the complete inventory and migrate only structural ownership assertions. |
| 2026-07-27 | Evidence Collector — policy | runtime-root manifest/tool/tests; DTR-12 checker/manifest/tests; roadmap/index | `DTR13-AUTH-01` clears the owner blocker and requires the three manual roots plus the uncalled `smoke_test_runner.dart` to remain. Moving construction from unclassified `main.dart` eliminates zero DTR-12 exceptions: canonical counts remain 182 dependencies, 24 placements, and 92 `core/debug` dependencies. | Record the authorization, preserve the manifest row without activating it, and forbid exception drift. |
| 2026-07-27 | Planner | tier matrix; plan template; gate cadence; current dirty tree | The minimum closure needs host causal exclusion/preservation proof, all Sims contracts, the affected group gate, justified core family coverage, strict analysis, and only live available affected simulation legs. Full `host-all` belongs to Wave 4A after Plan-green. | Apply the blocking sufficiency checklist, then perform the requested independent review before any production edit. |
| 2026-07-27 | Independent reviewers | Plan 289; exact production phases; Sims builder/manifest/runners; runtime roots; gate discovery; rollback | Initial verdict `plan-fixes-required`: component activation, exact lifecycle/async ownership, the bounded UI port, hardcoded-main inventory, effective build defines, affected simulations, standalone iOS contracts, and inverse rollback needed repair. No production code was edited. | Apply only the reliability deltas and run a five-lens closer. |
| 2026-07-27 | Review closer | repaired Scope, component matrix, Test Contract, acceptance commands, rollback | Both independent reviews confirm all findings resolved after the four-simulator and surviving-rollback-contract corrections. Final verdict `ready`; classification remains `implementation-ready`. | Begin TC-DTR13-02 causal RED. |
| 2026-07-27 | Implementer / closer | `lib/main.dart`; new debug/E2E root; migrated ownership locks; Sims/profile contract; runtime roots; gates | The authorized construction move, causal RED/GREEN, five mutation re-REDs, every original host-side per-plan gate, affected passing live rows, and an incremental Graphify refresh completed. Four live rows remained non-green; later source/session/live-relay recovery proved they were distinct verifier, product, budget, and fixture defects rather than one missing-input condition. | Withhold Plan-green and the Wave 4A aggregate while the separately authorized narrow blocker repairs and final coherent-source proof run. |
| 2026-07-27 | Wave 4A blocker owner | Plans 290–292; iOS verifier; live Sims evidence; Plan-252 exact-anchor boundary | `W4A-BLOCKERS-AUTH-01` authorizes the narrow verifier/product/harness repairs needed to finish the four exact rows, without changing any DTR-13 profile, entrypoint, define, command, or workflow preservation contract. | Finish final coherent-source live rows, affected gates, one final graph refresh, and the full aggregate `host-all`. |
| 2026-07-28 | Live acceptance closer | four exact Sims rows; Pixel 6; two API-35 emulators; physical iPhone; live EC2 relay | Wake directionality, both intro roles, all four group/announcement message/reaction scenarios, and the complete seven-assertion iOS APNs/NSE/offline-tap journey passed against source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`. iOS cleanup again proved `result.apps=[]`; no credential, token, payload, or raw handoff entered tracked evidence. | Live blockers are closed. Finish the integrated host/analysis gates, final incremental Graphify refresh, and the cadence-protected Wave 4A aggregate. |

## Problem And Evidence

- Behavior to improve: the default application bootstrap must not construct
  debug/E2E controllers, observers, polling timers, reset machinery, fixture
  coordinators, or simulator auto-setup wiring. Explicitly authorized
  debug/E2E/Sims workflows must construct the same objects at the same
  lifecycle phases and retain the same behavior.
- Impact: current default launches construct disabled
  `GroupMediaReliabilityE2EController`,
  `GroupMediaIosBackgroundE2EController`,
  `PrivateMediaOutboxE2EController`, and
  `WakeTokenAcceptedAttachmentObserver` instances. `main.dart` also owns the
  reset, auto-setup, sender/receiver fixture, disposable-node, overlay, and
  poller composition. That makes production bootstrap responsible for proof
  machinery even when the machinery is disabled.
- Owner decision: `DTR13-AUTH-01` authorizes this structural move and no
  workflow retirement. It preserves every profile, define, command, artifact,
  entrypoint, the three manual smoke roots, every current manual/simulation/
  headless workflow, and `lib/core/debug/smoke_test_runner.dart` in its current
  uncalled state.
- Confirmed production lifecycle:
  - disposable-profile reset validation and execution occurs before
    `StartupTiming.app_start`, share-intent capture, Firebase, SQLCipher, and
    the normal app; handled reset renders an inert app and returns;
  - group-media controllers are constructed after the parallel share/documents
    probes and before Firebase;
  - private-media controller and simulator auto-setup are composed after
    repositories/audio and after the Go bridge respectively, before local P2P;
  - accepted-wake observation is injected during `P2PServiceImpl` construction;
  - contact fixture prepopulation is awaited immediately before `runApp`;
  - sender projection and the intro poller start after `runApp`;
  - receiver bootstrap starts only after deferred runtime readiness;
  - the intro poller owns one initial timer, one process-global periodic timer,
    and a process-global in-flight latch. It has no cancellation API.
- Confirmed activation rules to preserve:
  - `E2E_TEST_MODE` defaults false; ordinary default builds have an empty
    `SIMS_BUILD_PROFILE_ID`;
  - general file-channel polling requires debug mode plus `E2E_TEST_MODE` or
    `MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF`;
  - the exact `ios.device.group_media_269` profile retains its existing
    release-build file-channel exception;
  - `ios.device.production` retains its sender-projection/receiver-bootstrap
    proof channel even though it does not set `E2E_TEST_MODE`;
  - `AUTO_SETUP_USERNAME` and `Documents/auto_setup.json` retain the existing
    independently triggered auto-setup path and its current pre-`runApp`
    timing;
  - default/no-profile/no-define/no-auto-setup composition returns `null`
    before invoking any harness constructor factory.
- Complete current build-profile inventory:

| Profile ID | Platform / artifact | Entrypoint | Manifest defines | Effective/build-only contract |
|---|---|---|---|---|
| `host.process` | host / none | none | none | reserved `SIMS_BUILD_PROFILE_ID` removed; no build |
| `host.flutter_tester` | host / none | none | none | reserved `SIMS_BUILD_PROFILE_ID` removed; no build |
| `android.e2e.standard` | Android / APK | `integration_test/sims_dispatcher.dart` | `E2E_TEST_MODE=true` | `SIMS_BUILD_PROFILE_ID=android.e2e.standard`; optional resolved relay define; debug arm64 APK with explicit target |
| `android.e2e.main` | Android / APK | `lib/main.dart` | `E2E_TEST_MODE=true` | `SIMS_BUILD_PROFILE_ID=android.e2e.main`; optional resolved relay define; debug arm64 APK with explicit target |
| `android.e2e.group_media_269` | Android / APK | `lib/main.dart` | `E2E_TEST_MODE=true`; `SIMS_ANDROID_DISPOSABLE_PACKAGE_ID=com.mknoon.sims.groupmedia269` | `SIMS_BUILD_PROFILE_ID=android.e2e.group_media_269`; optional relay; exact Gradle properties `disableGoogleServicesForDisposableProof=true` and `enableGroupMedia269DisposableProof=true` |
| `android.production_fcm` | Android / APK | `lib/main.dart` | `E2E_TEST_MODE=true`; `PRODUCTION_FCM=true`; `MKNOON_EMIT_WAKE_TOKEN=true` | `SIMS_BUILD_PROFILE_ID=android.production_fcm`; optional relay; debug arm64 APK with explicit target |
| `android.e2e.wake_token` | Android / APK | `lib/main.dart` | `E2E_TEST_MODE=true`; `MKNOON_EMIT_WAKE_TOKEN=true` | `SIMS_BUILD_PROFILE_ID=android.e2e.wake_token`; optional relay; debug arm64 APK with explicit target |
| `ios.simulator.e2e` | iOS simulator / app | `integration_test/group_multi_party_device_real_harness.dart` | `E2E_TEST_MODE=true` | `SIMS_BUILD_PROFILE_ID=ios.simulator.e2e`; `MKNOON_KEY_ROTATION_GRACE_PERIOD_MS=1500`; optional relay; explicit simulator target |
| `ios.device.production` | physical iOS / xctestrun | `lib/main.dart` | `PRODUCTION_APNS=true` | `SIMS_BUILD_PROFILE_ID=ios.device.production`; optional relay; exact `FLUTTER_TARGET`, base64 `DART_DEFINES`, production native conditions/signing |
| `ios.device.group_media_269` | physical iOS / xctestrun | `lib/main.dart` | `E2E_TEST_MODE=true`; `PRODUCTION_APNS=true`; `SIMS_IOS_DISPOSABLE_BUNDLE_ID=com.mknoon.sims.groupmedia269` | `SIMS_BUILD_PROFILE_ID=ios.device.group_media_269`; optional relay; exact `FLUTTER_TARGET`, base64 `DART_DEFINES`, disposable native conditions/signing |

  Every build-required profile continues to receive the reserved effective
  `SIMS_BUILD_PROFILE_ID=<profile-id>` define from the builder. The optional
  `SIMS_BUILD_ENTRYPOINT` override remains supported and unchanged.
- Entrypoint/workflow inventory:
  - registered manual roots:
    `lib/smoke_test_main.dart`, `lib/smoke_test_messages.dart`, and
    `lib/smoke_test_restore.dart`, with their documented `flutter run -t`
    commands unchanged;
  - retained uncalled support:
    `lib/core/debug/smoke_test_runner.dart`; it is neither imported nor
    activated by Plan 289;
  - centrally built roots:
    `lib/main.dart`, `integration_test/sims_dispatcher.dart`, and
    `integration_test/group_multi_party_device_real_harness.dart`;
  - active main-app harness consumers include connectivity restore, private
    media outbox restore, wake-token directionality, voice-message, Android
    notification payload, intro acceptance, group reaction, Android group
    media, iOS notification, iOS receiver bootstrap/sender projection, direct
    text relay-token proof, `reset_simulators.sh`/`smoke_test_friends.sh`, and
    legacy capture runners. Their targets and commands do not change.
  - exact explicit/default-main command and metadata owners pinned by the new
    preservation contract:

| Owner path | Current target/define contract to preserve |
|---|---|
| `scripts/run_ios_notification_tap_ui_smoke.sh` | all three build/drive legs retain explicit/default `lib/main.dart` targeting and their current defines |
| `integration_test/scripts/capture_android_push_relay_registration.dart` and `test/integration/android_push_relay_registration_contract_test.dart` | `lib/main.dart`; `MKNOON_PUSH_RELAY_REGISTRATION_PROOF=true`; `FDC_FLOW_LOG=1`; unchanged proof metadata |
| `integration_test/scripts/capture_1to1_reaction_head_provenance.dart` | default `lib/main.dart` for the current E2E true/false and wake-token build variants |
| `integration_test/scripts/capture_group_reaction_notification_device.dart` | default `lib/main.dart` for the current Android/iOS E2E true/false variants |
| `integration_test/scripts/reaction_notification_proof_support.dart` | emitted proof `entrypoint` remains `lib/main.dart` in both current metadata locations |
| `reset_simulators.sh` and `smoke_test_friends.sh` | default `lib/main.dart`; `E2E_TEST_MODE=true`; `DISABLE_LOCAL_DISCOVERY=true`; unchanged CoreSimulator file workflow |
| `docker-ws/run_fresh_all_phones.sh`, `docker-ws/run_fresh_three_phones.sh`, `docker-ws/deploy_all_phones.sh`, and `docker-ws/build_pixel_production.sh` | production/default `lib/main.dart`; current iOS release/`PRODUCTION_APNS` and Android non-E2E commands |
| `scripts/build_ios_appstore_ipa.sh` and `.metadata` | production/default `lib/main.dart` remains the application root |
- Source locks that currently confuse behavior preservation with textual
  ownership in `main.dart`:
  `test/core/lifecycle/main_private_media_outbox_e2e_wiring_test.dart`,
  `test/core/debug/group_media_disposable_transport_start_test.dart`,
  `test/core/debug/group_media_ios_background_e2e_test.dart`,
  `test/features/groups/integration/group_media_reliability_wiring_test.dart`,
  `test/integration/group_media_ios_background_recovery_test.dart`,
  `test/integration/android_group_media_reliability_controller_test.dart`,
  `test/integration/reaction_notification_proof_support_test.dart`,
  `scripts/test/private_media_outbox_restore_sims_adapter_contract_test.sh`,
  `scripts/test/voice_message_prebuilt_runner_contract_test.sh`, and
  `scripts/test/notification_tap_campaign_adapter_contract_test.sh`.
  These assertions must follow the new composition root without weakening the
  behavior, timing, or target contract.
- Refuted:
  - all Sims profiles do not target `lib/main.dart`; only six do;
  - `smoke_test_runner.dart` is not active and must not be wired;
  - `TransportMetrics` is not debug/E2E-only despite its directory;
  - this move does not eliminate a DTR-12 exception because `main.dart` has no
    exception identity.
- Unresolved findings: none blocking. `PRODUCTION_APNS` currently has no Dart
  reader but is an owner-preserved build marker and is not removed. The
  process-lifetime poller/fixture ownership is retained rather than redesigned;
  cancellation is a separately behavior-changing concern.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `332fe23f228dfb75`; `current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-13 lib/main.dart debug E2E controller polling reset fixture simulator auto-setup composition root Sims profiles smoke_test_main.dart smoke_test_messages.dart smoke_test_restore.dart run_test_gates" --profile tdd --budget 700`.
- Anchors: the graph surfaced registered manual smoke roots and their runtime
  policy but missed the `main.dart` construction seam.
- Graph gaps requiring source verification: profile-to-target mapping,
  compile-time activation, controller construction, reset order, fixture
  timing, poller lifetime, source-lock tests, headless scripts, and DTR-12
  exception identity.
- Reuse rule: review/execution may reuse the fingerprint and source anchors;
  current source remains authoritative for all exact wiring assertions.

## Scope Contract And Guard

In scope:

- Add one library composition root at
  `lib/debug/debug_e2e_composition_root.dart`. It may import the existing
  debug/E2E helpers and the production ports required to compose them.
- Keep `lib/main.dart` as the unchanged public/default/Sims entrypoint. Add a
  nullable phased seam:
  - an early static reset handoff before `app_start`;
  - a factory after documents-directory resolution that returns `null` before
    all controller/observer/dependency-bundle/callback construction for an
    ordinary default build;
  - active-root, exactly-once phase methods that construct the group-media
    controllers after documents resolution, the private-media controller after
    audio-service creation, and the wake observer immediately before
    `P2PServiceImpl`, matching their current effective lifetimes;
  - one **static root-module** simulator auto-setup handoff at its current
    post-bridge/pre-local-P2P phase. It resolves `AUTO_SETUP_USERNAME` and
    `Documents/auto_setup.json` at that exact phase even when the controller
    root is null; absent/malformed/blank input constructs nothing, while
    define-only and file-only input retain the current independent auto-setup;
  - nullable hooks for download recovery and accepted-wake observation. Keep
    the existing concrete nullable `PrivateMediaOutboxE2EController` pass-
    through into `MyApp`/`ConversationWired` unchanged rather than redesigning
    the feature port;
  - only three minimal root-widget/startup handoffs:
    `Widget Function(Widget)?` for overlay decoration,
    `Future<StartNodeResult> Function()?` for disposable-node start, and
    `Future<void> Function()?` for post-runtime-ready receiver publication;
  - contact prepopulation immediately before `runApp`;
  - sender fixture and intro polling after `runApp`;
  - receiver publication after runtime readiness.
- Move the concrete construction/calls for
  `GroupMediaReliabilityE2EController`,
  `GroupMediaIosBackgroundE2EController`,
  `PrivateMediaOutboxE2EController`,
  `WakeTokenAcceptedAttachmentObserver`,
  `runGroupMediaIosDisposableResetIfRequested`,
  simulator auto-setup/export,
  `IosSenderProjectionFixtureStore`/
  `runIosSenderProjectionFixtureLoop`,
  `startIntroE2EPoller`,
  `publishIosReceiverBootstrapIdentityWhenReady`,
  `GroupMediaIosBackgroundE2EOverlay`, and
  `startGroupMediaDisposableTransportNode` into that root.
- Move the two group-media proof actions and their callback construction with
  the poller. `main.dart` supplies current production repositories/services
  through explicit parameters and the existing navigator key; the root owns
  their debug/E2E assembly. The root must never import `lib/main.dart`.
- Preserve the current process-lifetime async behavior: one idempotent global
  poller, unchanged two-second initial delay/three-second interval, the
  45-minute sender loop, two-minute receiver wait, and current absence of an
  app-disposal cancellation transition. The active root remains strongly
  referenced by the same coordinator/widget callbacks for the process
  lifetime; default composition retains no root or harness closure.
- Add a pure/injectable construction gate used by the real root so a causal
  host test proves the default branch invokes zero factories. Test root
  activation and every component factory/scheduler separately with this exact
  matrix:

| Activation | Root | Reset/probes | Android/iOS group controllers | Private / wake | Poller timer | Sender / receiver fixtures | Overlay / disposable start | Auto-setup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| empty-profile debug or release; no flags/config | no | no | 0 / 0 | 0 / 0 | no | no / no | no / no | no |
| valid `AUTO_SETUP_USERNAME` only | no | no | 0 / 0 | 0 / 0 | no | no / no | no / no | yes, later phase |
| valid `auto_setup.json` only | no | no | 0 / 0 | 0 / 0 | no | no / no | no / no | yes, later phase |
| malformed/blank auto-setup input only | no | no | 0 / 0 | 0 / 0 | no | no / no | no / no | no |
| debug + `E2E_TEST_MODE=true` | yes | profile-only | 1 / 1 | 1 / 1 | one | profile-only | profile-only | configured-only |
| debug + direct-text proof, E2E false | yes | no | 1 / 1 | 1 / 1 | one | no / no | no / no | configured-only |
| Android disposable profile | yes | yes | 1 / 1 | 1 / 1 | one | no / no | no / yes | configured-only |
| iOS group-media profile in its release exception | yes | yes | 1 / 1 | 1 / 1 | one | no / no | yes / yes | configured-only |
| `ios.device.production` | yes | no | 1 / 1 | 1 / 1 | no timer | one / one | no / no | configured-only |

  “1” is an exact constructor/scheduler count for one process bootstrap; an
  inactive component factory must remain at zero even when another component
  activates the root.
- Pin one root creation, each phase method exactly once, one immediate
  post-`runApp` sender handoff, one post-cold-recovery/reconcile poller
  handoff, one runtime-ready callback, no root dispose/cancel call, unchanged
  `unawaited` sender/receiver starts, and no duplicate scheduler invocation.
- Update structural contracts to assert the same behavior through
  `lib/debug/debug_e2e_composition_root.dart` plus the thin lifecycle handoffs
  in `lib/main.dart`.
- Add one exact Sims/profile/manual/headless preservation contract under
  `scripts/test/` so `sims-contracts` discovers it automatically.
- Update the runtime-root evidence text for
  `lib/core/debug/smoke_test_runner.dart` to cite `DTR13-AUTH-01` retention
  while keeping its `retained-unresolved` tool disposition, empty root kinds,
  no evidence edge, and zero caller/activation.
- Update this plan, the roadmap, and `00-INDEX.md` with exact RED/GREEN,
  per-plan, Graphify, and Wave 4A aggregate results.

Must preserve:

- All 10 profile IDs, platforms, artifact kinds, manifest define maps,
  effective `SIMS_BUILD_PROFILE_ID` injection, canonical targets, optional
  target override, build commands, native flags, signing/native configuration,
  cache/attestation closure, and runtime profile/nonce handshake.
- Exact public targets:
  `lib/main.dart`,
  `integration_test/sims_dispatcher.dart`,
  `integration_test/group_multi_party_device_real_harness.dart`,
  `lib/smoke_test_main.dart`,
  `lib/smoke_test_messages.dart`, and
  `lib/smoke_test_restore.dart`.
- Every current manual, reliability-simulation, Sims, headless capture, and
  device workflow; no command acquires a new target or define.
- Reset platform/bundle fail-closed checks and early-return ordering; share/
  documents parallel startup; Firebase/deferred-live-services timing;
  database/migration wiring; foreground/resume behavior; push permission/
  presentation suppression; group-media download semantics; and application
  navigation.
- `lib/core/debug/smoke_test_runner.dart` byte-for-byte and uncalled.
- DTR-12 canonical counts at 182 dependency exceptions, 24 placement
  exceptions, and 92 `core/debug` dependencies. The architecture exception
  manifest is unchanged.

Hard `Do not`:

- Do not add, delete, rename, or retarget an entrypoint. Do not change a Sims
  profile, define, command, artifact kind, native configuration, or capability.
- Do not activate `smoke_test_runner.dart`, merge the three manual roots, or
  represent them as equivalent to the production composition.
- Do not extract general bootstrap phases or alter production service
  ownership; that is DTR-14.
- Do not relocate the existing `core/debug` helpers or repair general layer
  debt; that is DTR-18.
- Do not add/rebaseline a DTR-12 exception. Do not remove one merely because
  its owner mentions DTR-13; this move eliminates zero exact identities.
- Do not redesign poller cancellation, fixture timeouts,
  `ConversationWired`'s concrete private-media controller port/endpoint
  behavior, push semantics, schema/storage, native/Go code, or runtime
  behavior. The three explicitly named nullable handoffs are the complete
  DTR-13 UI/startup port delta, not a DTR-14 bootstrap or general port
  extraction.
- Do not run full `host-all` as Plan 289's per-plan gate.

Dependencies:

- DTR-01 and DTR-12 are Plan-green; Wave 3 is accepted.
- `DTR13-AUTH-01` is recorded in the owner-decision ledger and clears the only
  remaining DTR-13 decision blocker.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR13-01 | An ordinary default launch constructs zero debug/E2E root/controller/observer/reset/fixture/poller/auto-setup objects, while the exact component truth table remains available. | `test/core/debug/debug_e2e_composition_root_test.dart::default composition invokes zero harness factories and exact proof activations remain enabled`; `::component factory matrix preserves independent profile flag and auto setup activation` | Host Flutter unit / injected per-component counters, temp auto-setup files, activation matrix | HEAD has unconditional main constructors and no root gate -> new structural test RED; GREEN returns null and leaves every counter zero for empty/default production, distinguishes root activation from each component, and preserves valid define-only/file-only auto-setup plus malformed/blank no-op behavior | Make the default predicate true, eagerly create an unrelated component, remove one exact profile, or break valid/invalid auto-setup classification -> test re-RED | Exact path; `core-host-all` |
| TC-DTR13-02 | `main.dart` owns only phased nullable handoffs; all named concrete constructors and long-lived scheduler calls live in the separate root, while existing concrete feature pass-through types may remain. | `test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart::production main owns no concrete debug E2E harness construction` | Host source contract / real source | HEAD contains every forbidden constructor/call -> assertion RED; GREEN finds each exact constructor/call only in the new root, permits the unchanged private-controller type/DI thread, forbids a root import of `main.dart`, and observes one ordered handoff per phase | Reinsert any constructor/poller in main, import main from the root, delete a handoff, or duplicate scheduler start -> test re-RED | Exact path outside curated feature families; `core-host-all` |
| TC-DTR13-03 | Disposable reset retains exact validation, probes, early inert app, and precedes all production startup boundaries. | Updated `test/core/debug/group_media_ios_background_e2e_test.dart::dedicated profile reset runs before production bootstrap boundaries`; `test/core/debug/group_media_disposable_transport_start_test.dart::main delegates disposable profile start only through the debug E2E root` | Host unit/source / fake directories, stores, and real source | Source locks currently require implementation in main -> RED after ownership assertion update; GREEN proves root implementation plus main ordering and exact fail-closed profile/bundle behavior | Move reset after `app_start`, omit Android or iOS profile, or expose start override for default -> tests re-RED | Exact paths; `groups`; `core-host-all` |
| TC-DTR13-04 | Controller hooks, private-media endpoint, wake observation, group proof actions, overlay, navigation, and poller remain behaviorally wired only for authorized composition. | Updated `test/core/lifecycle/main_private_media_outbox_e2e_wiring_test.dart`; `test/features/groups/integration/group_media_reliability_wiring_test.dart`; `test/integration/android_group_media_reliability_controller_test.dart`; `test/integration/group_media_ios_background_recovery_test.dart`; `test/integration/reaction_notification_proof_support_test.dart` | Host source/behavior / current fakes and fixtures | Updated ownership locks fail against HEAD path -> GREEN follows the root while preserving exact callbacks, production singleton coordinator, labels, and route threading | Drop any action callback, private controller thread, recovery hold, post-claim hook, overlay, or navigation endpoint -> named test re-RED | All exact paths; `groups`; core test direct |
| TC-DTR13-05 | Simulator auto-setup, intro contact prepopulation, sender projection, receiver bootstrap, and process-global poll timing retain exact phase/order/await ownership. | `test/core/debug/debug_e2e_composition_root_test.dart::composition phases preserve auto setup runApp fixture runtime-ready and poller ownership`; `test/core/debug/auto_setup_config_test.dart`; `test/core/debug/intro_e2e_runner_private_media_outbox_test.dart`; exact `dart run scripts/test/ios_receiver_bootstrap_contract_test.dart`; exact `dart run scripts/test/ios_sender_projection_fixture_contract_test.dart` | Host unit/source/process / temp auto-setup file, injected ordered trace, fake services | HEAD has no phase root -> new phase assertion RED; GREEN traces reset before `app_start`; joined share/doc probes before group controllers/Firebase; awaited auto-setup post-bridge/pre-local-P2P; awaited contacts immediately pre-`runApp`; unawaited sender scheduling after `runApp` but before `run_app_called`; cold recovery/reconcile before poller; unawaited receiver publication only through runtime-ready `.then`; exactly one root, one sender handoff, one later poller handoff, one runtime callback, and no root disposal | Move any phase, change awaited/unawaited ownership, duplicate a sender/receiver/poller start, change timer defaults, or cancel on app dispose -> tests re-RED | Exact new/core paths plus two explicitly named standalone Dart processes; `core-host-all` does not discover those scripts |
| TC-DTR13-06 | All profile IDs, targets, manifest/effective define maps, native/build arguments, commands, manual roots, exact headless-owner table, proof metadata, and override policy remain exact. | New `scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh`; existing `test/tool/sims/sims_manifest_test.dart`; `test/tool/sims/sims_build_cache_test.dart`; `test/tool/sims/sims_ios_group_media_269_profile_test.dart`; `test/unit/runtime_root_inventory_test.dart` | Host process/Flutter / canonical manifests, builder source, command/proof sources | The new contract first fails because no explicit DTR-13 preservation lock/root exists; GREEN pins the current 10-row inventory, relay/profile/grace defines, Android disposable Gradle properties, physical-iOS `FLUTTER_TARGET`/base64 define/native conditions, every enumerated explicit/default `lib/main.dart` command/metadata owner, and structural ownership change without target drift | Change one define/target/profile/artifact/native flag/manual root/headless command/proof entrypoint or disable `SIMS_BUILD_ENTRYPOINT` -> exact contract re-RED | New shell path is outside Flutter families and auto-discovered by `sims-contracts`; exact Dart paths; `runtime-roots` |
| TC-DTR13-07 | Existing Sims adapters still build/use `lib/main.dart` and reach the same root-owned poller actions. | Updated `scripts/test/private_media_outbox_restore_sims_adapter_contract_test.sh`, `scripts/test/voice_message_prebuilt_runner_contract_test.sh`, and `scripts/test/notification_tap_campaign_adapter_contract_test.sh`; existing connectivity, wake, keepalive, build-count, and iOS companion contracts | Host process / fake command runners and source inspection | Ownership assertions point at main -> RED after contract migration; GREEN verifies unchanged targets/profiles/commands and follows action wiring into the root | Retarget an adapter, drop a profile/action dependency, or weaken artifact/profile checks -> process contract re-RED | Exact shell paths; auto-discovered `sims-contracts` |
| TC-DTR13-08 | Manual smoke roots remain registered and `smoke_test_runner.dart` remains present, uncalled, and not activated. | Updated `test/unit/runtime_root_inventory_test.dart::canonical manifest reconciles every app file and required root`; new shell preservation assertions in TC-DTR13-06 | Host tool/source / real repository | Existing policy says owner unresolved -> GREEN cites `DTR13-AUTH-01` while keeping the same retained disposition and zero reachability edge | Delete/rename a smoke root, import/call the runner, change its bytes, or promote it to a root -> exact proof re-RED | Exact unit path; `runtime-roots`; `sims-contracts` |
| TC-DTR13-09 | Startup/lifecycle and production behavior outside the harness remain unchanged. | `test/core/lifecycle/main_parallel_launch_probe_wiring_test.dart`; `test/core/lifecycle/main_deferred_startup_wiring_test.dart`; `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart`; `test/core/lifecycle/main_presence_lifecycle_wiring_test.dart`; `test/core/notifications/intro_accept_open_coordinator_wiring_test.dart` | Host source/behavior / current fixtures | Current tests are green on HEAD; they remain preservation sentinels after movement | Serialize share/doc probes, await live services before `runApp`, alter push rearm/presence/open routing -> sentinel red | Exact paths; `core-host-all` |
| TC-DTR13-10 | No DTR-12 exception is added, substituted, or incorrectly removed. | `./scripts/run_test_gates.sh architecture-boundaries`; `test/unit/architecture_boundary_checker_test.dart::canonical DTR-12 manifest pins 182 dependency and 24 placement exceptions` | Host tool / real repository | HEAD exact set is green; GREEN remains 182/24 with 92 core-debug and no manifest diff | Add root under a forbidden classified path, add an exception, or remove a stale row without removing its exact edge -> gate red | Named lane and exact unit selector |
| TC-DTR13-11 | Every affected main-app Sims action plus the legacy group/intro headless plans remains discoverable and executes or returns the exact policy-authorized target-unavailable N/A on the live matrix without command/define drift. | Filtered `sims major --only` runs for `android.connectivity_restore_inbox_drain`, `android.connectivity_restore_media_outbox`, `android.keepalive_drop_skip_direct`, `android.wake_token_directionality`, `android.voice_message_e2e`, `notifications.android_payload_campaign`, `notifications.ios_payload_fast_path`, `intro.accept_notification_campaign`, `groups.reaction_notification_campaign`, `groups.media_send_reliability`, and the otherwise runtime-unowned `build.ios.device.group_media_269`; `reliability-sim group --list`; `reliability-sim intro --list`; legacy `smoke_test_friends.sh` only when four available iOS simulators satisfy its full `all` topology | Typed Sims live execution + discovery; default Android physical/emulator pair, exact iOS-only target where available | Discovery is green on HEAD; post-change plans remain identical. Each filtered Sims row includes its canonical build dependency and must PASS or produce only `N/A (target unavailable by project policy)`; the legacy intro leg runs only on its actually available four-simulator topology | Remove a workflow, alter its command/define/target, make a root action unreachable, or convert an available-target failure into N/A -> named row red | Exact filtered commands and verdicts recorded at execution; not an unfiltered Sims/reliability aggregate |

## Implementation Steps

1. Snapshot `git status --short`, current profile/root tables, DTR-12 exact
   counts, and the three manual-root declarations. Preserve all existing
   Plan-288/tooling changes.
2. Add TC-DTR13-02 first against current source and run its exact test. Capture
   the assertion RED showing concrete controller/poller construction still in
   `lib/main.dart`; do not accept an import/compile failure as the causal RED.
3. Add TC-DTR13-01's injectable construction policy scaffold and capture the
   default factory-counter assertion RED before implementing the real guard.
4. Add `lib/debug/debug_e2e_composition_root.dart`; move only the named
   harness construction and action assembly. Preserve current activation
   constants, component-specific predicates, method bodies, delays, timeouts,
   error handling, and process lifetime. The root receives the navigator key
   and production dependencies as parameters and never imports `main.dart`.
5. Replace the concrete `main.dart` sites with nullable ordered phase
   handoffs. Keep every production object, startup phase, lifecycle callback,
   flag-dependent production behavior, and public entrypoint in place.
6. Move simulator auto-setup as one static root-module method invoked at the
   same post-bridge location even when the controller root is null. It checks
   the same file/define at the same phase; absent/malformed/blank input creates
   no root or harness object, while valid file-only/define-only input retains
   identity setup/export.
7. Update only the ownership-sensitive Dart/shell tests. Preserve the
   production singleton-coordinator assertions and every entrypoint/profile/
   command assertion; add the exact profile/manual/headless contract.
8. Update the runtime-root evidence for the retained runner without changing
   its disposition, reachability, or source. Do not edit the architecture
   exception manifest.
9. Run focused GREEN, representative mutations (default gate, one profile,
   one phase-order seam, one action callback, and one profile/target row), and
   restore every mutation.
10. Run all per-plan acceptance gates below. Resolve live devices before any
    affected simulation and pin every command to discovered IDs. Run the
    architecture refresh once after the coherent app-owned change.
11. Mark Plan 289 and DTR-13 Plan-green only after every required per-plan
    gate is green. Then run and archive the one Wave 4A aggregate `host-all`
    required after DTR-12 + DTR-13; update the plan, roadmap, index, and stable
    evidence with exact results.

## Rollback Contract

- Keep the new root, thin main handoffs, migrated tests/contracts, runtime-root
  evidence, and plan/roadmap/index records in one coherent DTR-13 range.
  Rollback restores the exact pre-DTR-13 constructor/call blocks to their
  original `main.dart` phases; restores every migrated existing Dart/shell
  ownership contract; restores the prior runtime-root reason/condition; removes
  the new root, two new Flutter tests, and new shell contract; and restores the
  plan/roadmap/index state to owner-authorized/planned while retaining the
  historical `DTR13-AUTH-01` receipt.
- Rollback must not change any profile, target, define, command, entrypoint,
  manual root, `smoke_test_runner.dart`, DTR-12 manifest row, production
  service, schema, native/Go source, or owner receipt.
- After rollback, run focused startup/wiring tests, `sims-contracts`,
  `runtime-roots`, `architecture-boundaries`, `groups`, strict analysis, and
  `core-host-all` plus the surviving pre-DTR-13 Sims/profile/headless
  contracts, and `git diff --check`; then run one incremental Graphify refresh.
  Restore
  DTR-13 to authorized/planned, not decision-blocked; `DTR13-AUTH-01` remains
  historical authorization.
- There is no persisted-data migration. Existing auto-setup/reset actions are
  already explicit harness side effects and remain unchanged; the code move is
  Git-recoverable.

The Wave 4A blocker repairs have separate inverse ranges. Do not roll back a
shared file wholesale: restore only the named execution-start hunks, preserve
unrelated dirty-tree and DTR-13 composition-root edits, and update the
plan/roadmap/index verdict in the same rollback.

- **Plan 290 wake repair:** restore only the execution-start
  `storeInInboxDetailed`/node-readiness hunks in
  `lib/core/services/p2p_service_impl.dart` and remove
  `test/core/debug/wake_token_directionality_readiness_test.dart`. Preserve
  wake-token bytes/omission, the bridge API, `android.e2e.wake_token`, the
  debug/E2E root, relay/native code, and every token issuer/observer contract.
  Then run
  `flutter test test/core/services/p2p_service_impl_test.dart`,
  `flutter test test/core/bridge/p2p_bridge_client_wake_attach_test.dart`,
  `flutter test test/core/debug/wake_token_directionality_e2e_test.dart`,
  `flutter test test/integration/android_wake_token_directionality_campaign_test.dart`,
  `./scripts/run_test_gates.sh 1to1`,
  `./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`.
  Withdraw Plan 290 focused-host/Plan-green status and any current-source wake
  live-row claim; retain old reports only as historical evidence for their
  tested source digest.
- **Plan 291 harness repair:** restore only the execution-start deadline,
  phase-budget, child-supervision, acceptance-discriminator, and cleanup hunks
  in `integration_test/scripts/run_intro_accept_notification_android.dart` and
  `integration_test/scripts/run_intro_accept_notification_sims.dart`; remove
  `test/core/debug/intro_e2e_budget_test.dart` and
  `test/core/debug/intro_e2e_runner_test.dart`. Preserve the registered
  three-party scenario, profiles/defines, notification payload/order, invite
  protocol, relay/provider boundary, and every Plan-252 product correction.
  Then run
  `flutter test integration_test/intro_accept_notification_android_proof_test.dart`,
  `flutter test test/core/debug/intro_e2e_runner_custody_test.dart test/core/debug/intro_e2e_runner_token_proof_test.dart`,
  `bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh`,
  `./scripts/run_test_gates.sh intro`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`.
  Withdraw Plan 291 focused-host/Plan-green status and any intro live-row claim
  based on its enlarged budget; do not withdraw the separately owned Plan-252
  product correction unless its own inverse below is executed.
- **Plan 292 group harness repair:** restore only the execution-start fixture
  selector/recovery/readiness/invite/cleanup/log-read hunks in
  `integration_test/scripts/capture_group_reaction_notification_device.dart`,
  `lib/features/groups/presentation/widgets/expandable_fab.dart`,
  `lib/features/orbit/presentation/screens/orbit_screen.dart`, and
  `test/integration/group_reaction_notification_device_criteria_test.dart`;
  remove `test/core/debug/group_reaction_notification_fixture_test.dart`.
  Preserve group membership/reaction semantics, notification schema, relay
  deployment/provider inputs, the outer `AndroidAppStateGuard` owner, build
  profiles, and DTR-13 composition. Then run
  `flutter test test/integration/group_reaction_notification_device_criteria_test.dart`,
  `flutter test integration_test/group_announcement_reaction_notification_proof_test.dart`,
  `flutter test test/features/groups/presentation/widgets/expandable_fab_test.dart`,
  `./scripts/run_test_gates.sh groups`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`.
  Withdraw Plan 292 focused-host/Plan-green status and any current-source group
  live-row claim; the prior PASS report remains historical only.
- **iOS verifier repair:** restore only
  `devicectlResultAppsAreEmpty`/`_verifyCandidateApplicationRemoved` and the
  matching causal-test hunks in
  `integration_test/scripts/ios_notification_payload_xcui_driver.dart` and
  `test/integration/ios_notification_payload_xcui_contract_test.dart`.
  Preserve the APNs/NSE payload journey, airplane-before-tap ordering, network
  restoration, provider/relay cleanup, signing/build profile, entrypoint, and
  every protected credential/input path, `auto_setup.json` provisioning, and
  receiver-bootstrap capture. Then run
  `flutter test --no-pub test/integration/ios_notification_payload_xcui_contract_test.dart`,
  `./scripts/run_test_gates.sh sims-contracts`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`.
  Withdraw the iOS verifier GREEN and all final iOS live-row/Plan-green claims:
  the restored substring verifier cannot prove cleanup despite
  `result.apps=[]`.
- **Plan-252 product corrective amendment:** this inverse is separate from Plan
  291. Restore only the exact convergence/subscription hunks in
  `lib/features/introduction/application/resolve_introduction_notification_target_use_case.dart`,
  `lib/features/push/application/intro_accept_notification_open_flow.dart`,
  and the Intros branch of `lib/main.dart`, plus their exact additions in
  `test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart`,
  `test/features/push/application/intro_accept_notification_open_flow_test.dart`,
  and
  `test/core/notifications/intro_accept_open_coordinator_wiring_test.dart`.
  Never restore `lib/main.dart` wholesale: preserve Plan 289's composition root
  and Plan 252's original anchored payload/copy/A-to-B routing. Then run
  `flutter test test/features/introduction/application/resolve_introduction_notification_target_use_case_test.dart test/features/push/application/intro_accept_notification_open_flow_test.dart test/core/notifications/intro_accept_open_coordinator_wiring_test.dart`,
  `./scripts/run_test_gates.sh intro`,
  `./scripts/run_test_gates.sh 1to1`,
  `./scripts/check_flutter_analyze_strict.sh`, and `git diff --check`.
  Withdraw only the Plan-252 corrective GREEN and any intro live-row claim that
  requires exact C-anchor convergence; Plan 291's harness receipt remains
  independent.

## Risks And Blind Spots

- A nullable root can still construct disabled controllers before returning
  null -> TC-DTR13-01 injects constructor counters and requires the guard to
  precede every factory.
- A source move can subtly change startup timing -> TC-DTR13-03/05/09 pin every
  load-bearing phase and existing delay/timeout constants.
- `ios.device.production` can be mistaken for the ordinary default artifact ->
  the profile matrix distinguishes the explicit Sims proof profile from an
  empty/default production launch and preserves its receiver/sender fixtures.
- Reset can move past SQLCipher/Firebase or lose early return -> exact order
  proof in TC-DTR13-03.
- The root can start duplicate timers or be recreated during widget rebuild ->
  construction occurs once in `main()`, and the existing process-global
  idempotence/lifetime is pinned by TC-DTR13-05.
- A generic cleanup can dispose the iOS notifier or cancel loops, changing
  proof timing -> cancellation/disposal redesign is excluded and mutation
  coverage requires unchanged process-lifetime ownership.
- A structural test can be weakened to path-only existence -> migrated tests
  still assert concrete callback/action/target behavior across both files.
- A new entrypoint can silently change build caches/commands -> TC-DTR13-06/07
  require the exact existing targets and effective define behavior.
- An uncalled runner can be accidentally activated during consolidation ->
  TC-DTR13-08 requires no importer/caller/evidence edge and unchanged source.
- Moving into `lib/debug/` can be mistaken for DTR-12 debt reduction -> exact
  DTR-12 gate and no-manifest-diff rule retain 182/24/92.
- Lifecycle / derived-state durability: reset and auto-setup preserve their
  current storage actions and phase; no database/schema or recovery change.
- Sibling-surface consistency: Android/iOS group media, push, wake, voice,
  intro, private media, manual smoke, legacy simulations, and headless Sims are
  all represented by exact preservation tests/contracts.
- Destructive-action side effects: none new. Existing explicit disposable
  reset remains fail-closed and profile/bundle-bound.
- Invariant re-verification under new transitions: default null, every
  supported activation, every phase, and rollback are separately tested.

## Gate Cadence

- Per-plan closure: focused causal/root tests, exact existing ownership and
  lifecycle sentinels, `sims-contracts`, `runtime-roots`,
  `architecture-boundaries`, group/intro discovery, the affected `groups`
  curated lane, justified `core-host-all`, completeness, strict analysis,
  source/diff bounds, and availability-bounded affected live selectors.
- `core-host-all` is justified because the production bootstrap lifecycle and
  `lib/core/debug` composition contracts change. `feature-host-all`,
  performance, native, Go, SQLCipher-family, full reliability, and full
  `host-all` are not Plan-289 gates because no feature algorithm, performance
  contract, native boundary, schema, or broad feature surface changes.
- The new shell contract is outside Flutter curated families and is named
  directly; `sims-contracts` auto-discovers it. The new lifecycle/root Flutter
  tests are under `test/core/**` and are also run directly before the family
  sweep.
- After Plan 289 is Plan-green, run
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only`
  once for Wave 4A. This aggregate is separate from the per-plan gates and
  must receive a stable archived log/checksum/tree receipt.

## Acceptance Gates

```bash
# Dirty-tree/profile/root/exception snapshot; preserve all unrelated changes.
git status --short
git diff --name-status
: "${DTR13_EXECUTION_START_PROTECTED_HASHES:?set to the owner-retained pre-RED SHA-256 receipt}"
test -s "$DTR13_EXECUTION_START_PROTECTED_HASHES"

# Causal RED before production movement: assertion failure must name concrete
# construction that remains in lib/main.dart.
flutter test --no-pub \
  test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart \
  --plain-name 'production main owns no concrete debug E2E harness construction'

# Default-factory RED against the compile-only policy scaffold.
flutter test --no-pub \
  test/core/debug/debug_e2e_composition_root_test.dart \
  --plain-name 'default composition invokes zero harness factories and exact proof activations remain enabled'

# Focused GREEN for the new causal contract and all migrated source locks.
flutter test --no-pub \
  test/core/debug/debug_e2e_composition_root_test.dart \
  test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart \
  test/core/lifecycle/main_private_media_outbox_e2e_wiring_test.dart \
  test/core/debug/group_media_disposable_transport_start_test.dart \
  test/core/debug/group_media_ios_background_e2e_test.dart \
  test/features/groups/integration/group_media_reliability_wiring_test.dart \
  test/integration/android_group_media_reliability_controller_test.dart \
  test/integration/group_media_ios_background_recovery_test.dart \
  test/integration/reaction_notification_proof_support_test.dart

# Auto-setup/poller and production startup/lifecycle preservation sentinels.
flutter test --no-pub \
  test/core/debug/auto_setup_config_test.dart \
  test/core/debug/intro_e2e_runner_private_media_outbox_test.dart \
  test/core/lifecycle/main_parallel_launch_probe_wiring_test.dart \
  test/core/lifecycle/main_deferred_startup_wiring_test.dart \
  test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart \
  test/core/lifecycle/main_presence_lifecycle_wiring_test.dart \
  test/core/notifications/intro_accept_open_coordinator_wiring_test.dart

# These standalone Dart process contracts are outside test/** and are not
# discovered by core-host-all or sims-contracts.
dart run scripts/test/ios_receiver_bootstrap_contract_test.dart
dart run scripts/test/ios_sender_projection_fixture_contract_test.dart

# iOS verifier causal selector, then its complete eight-test contract.
flutter test --no-pub \
  test/integration/ios_notification_payload_xcui_contract_test.dart \
  --plain-name 'cleanup verifies devicectl result apps rather than echoed arguments'
flutter test --no-pub \
  test/integration/ios_notification_payload_xcui_contract_test.dart

# Exact profile/entrypoint/manual/headless preservation contract outside the
# Flutter families, followed by all registered Sims process contracts.
bash scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh
bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh
./scripts/run_test_gates.sh sims-contracts

# Existing profile/tool and retained-root exactness.
flutter test --no-pub \
  test/tool/sims/sims_manifest_test.dart \
  test/tool/sims/sims_build_cache_test.dart \
  test/tool/sims/sims_ios_group_media_269_profile_test.dart \
  test/unit/runtime_root_inventory_test.dart
./scripts/run_test_gates.sh runtime-roots

# DTR-12 exact-set preservation: expect 182 dependency, 24 placement, 92
# core/debug exceptions and no new/stale row. Byte preservation is checked
# against the execution-start hash receipt below, not against a dirty HEAD.
./scripts/run_test_gates.sh architecture-boundaries

# Simulation discovery/command preservation. Resolve the live matrix first;
# filtered Sims injects and records the exact discovered IDs. Every available
# target must execute; only the manifest's exact target-unavailable reason may
# produce N/A.
./scripts/run_test_gates.sh reliability-sim group --list
./scripts/run_test_gates.sh reliability-sim intro --list
flutter devices --machine
adb devices
xcrun simctl list devices available
for capability in \
  android.connectivity_restore_inbox_drain \
  android.connectivity_restore_media_outbox \
  android.keepalive_drop_skip_direct \
  android.wake_token_directionality \
  android.voice_message_e2e \
  notifications.android_payload_campaign \
  notifications.ios_payload_fast_path \
  intro.accept_notification_campaign \
  groups.reaction_notification_campaign \
  groups.media_send_reliability \
  build.ios.device.group_media_269; do
  ./scripts/run_test_gates.sh sims major --only "$capability"
done

# Legacy Android group discovery must identify the exact Android scenario,
# never expand into the separate iOS recovery scenario.
RELIABILITY_MULTI_DEVICE_IDS=<physical-id>,<emulator-id> \
  ./scripts/run_test_gates.sh reliability-sim group \
  --only \
  integration_test/scripts/run_group_media_send_reliability.dart:group_media_foreground_retry_acl_roundtrip

# The registered Android intro Sims capability above is the default live intro
# proof. This separate legacy CoreSimulator file/container workflow runs only
# when four compatible iOS simulators are actually available; otherwise
# record N/A by the repository availability policy.
DEVICE_A=<sim-a> DEVICE_B=<sim-b> DEVICE_C=<sim-c> DEVICE_D=<sim-d> \
  INTRO_E2E_DEVICE_SET=four \
  ./scripts/run_test_gates.sh reliability-sim intro \
  --only smoke_test_friends.sh

# Affected curated and justified family gates.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh intro
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Classification, strict analyzer, scope, and hygiene.
./scripts/run_test_gates.sh completeness-check
./scripts/check_flutter_analyze_strict.sh
git diff --check
shasum -a 256 \
  tool/sims/critical_features.json \
  tool/architecture_guard/architecture_boundary_exceptions.json \
  lib/smoke_test_main.dart \
  lib/smoke_test_messages.dart \
  lib/smoke_test_restore.dart \
  lib/core/debug/smoke_test_runner.dart \
  | cmp "$DTR13_EXECUTION_START_PROTECTED_HASHES" -

# After the integrated source is frozen for acceptance, prove that the
# worktree copies of the protected files still equal that tested tree. This
# catches post-freeze edits without assuming the pre-existing dirty tree
# equals HEAD.
: "${WAVE4A_FROZEN_TESTED_TREE:?set to the retained tested-tree object}"
git cat-file -e "${WAVE4A_FROZEN_TESTED_TREE}^{tree}"
git diff --quiet "$WAVE4A_FROZEN_TESTED_TREE" -- \
  tool/sims/critical_features.json \
  tool/architecture_guard/architecture_boundary_exceptions.json \
  lib/smoke_test_main.dart \
  lib/smoke_test_messages.dart \
  lib/smoke_test_restore.dart \
  lib/core/debug/smoke_test_runner.dart

# Coherent app-owned graph closure.
./graphify-arch/refresh_arch_graph.sh --incremental

# Separate Wave 4A aggregate only after DTR-13 is Plan-green. Archive the
# exact log, SHA-256, tested tree/commit, counts, Go tails, and final PASS.
./scripts/run_host_test_gates.sh host-all --continue-on-failure \
  --batch-flutter --concurrency 4 --reporter failures-only
```

## Execution Interpretation And Done Criteria

- Required causal RED: TC-DTR13-02 must compile and fail because current
  `main.dart` still contains the exact named harness constructors/calls.
  TC-DTR13-01 then fails a semantic factory-count assertion against a
  compile-only scaffold.
- Green sentinel: all profile/target/define/command/manual-root and DTR-12
  exact sets remain unchanged; default factory count is zero.
- Pre-existing dirty tree: the integrated DTR-12 Plan-288/tool/manifest/gate
  delta listed in the planning snapshot is unrelated and must remain intact.
- Availability policy: an unavailable device type/version is N/A under the
  repository policy, never an environment blocker. A discovered required
  target that fails the exact affected command is a real gate failure.
- Scope drift: any entrypoint/profile/define/command change, workflow removal,
  new runner activation, DTR-12 exception drift, general bootstrap extraction,
  helper relocation, async-lifetime redesign, or runtime behavior change
  blocks completion.

- [x] Every named constructor/poller/fixture/reset/auto-setup assembly site is
      owned by `lib/debug/debug_e2e_composition_root.dart`.
- [x] Default/no-profile/no-define/no-auto-setup launch invokes zero harness
      constructor factories.
- [x] Every existing authorized proof activation and command remains available.
- [x] Reset/startup/runApp/runtime-ready ordering is unchanged.
- [x] Manual smoke roots and uncalled smoke runner remain intact.
- [x] Causal RED, focused GREEN, and representative mutation re-RED evidence
      are recorded.
- [ ] `sims-contracts`, simulations, `groups`, `intro`, `1to1`,
      `core-host-all`, `runtime-roots`, `architecture-boundaries`,
      completeness, strict analysis, final graph refresh, scope, and hygiene
      gates pass on the final coherent source. The original Plan-289 host set
      was green; the blocker repairs require the affected gates and four exact
      live rows to be replayed before those earlier receipts can close the
      integrated Wave 4A tree.
- [x] DTR-12 remains exactly 182/24/92 with no manifest edit.
- [x] Scope Contract And Guard is respected.
- [ ] Plan 289 and DTR-13 are Plan-green, then the separate **full** Wave 4A
      aggregate `host-all` passes with stable evidence. A Dart-only run is not
      Wave 4A acceptance evidence.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart --plain-name 'production main owns no concrete debug E2E harness construction'`.
- Production seam:
  `lib/main.dart` remains the only default app entrypoint and calls a nullable,
  phased `lib/debug/debug_e2e_composition_root.dart` composition.
- Exact shared/non-curated test paths:
  `test/core/debug/debug_e2e_composition_root_test.dart`,
  `test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart`,
  `test/unit/runtime_root_inventory_test.dart`, and
  `scripts/test/dtr13_profile_entrypoint_preservation_contract_test.sh`.
- Migration: none. Native/Go/schema/storage formats are unchanged.
- Boundary closure: host causal proof plus availability-bounded affected
  simulation legs; no unavailable hardware version can block closure.
- Gate cadence: no per-plan full `host-all`; one Wave 4A aggregate immediately
  after Plan-green, then the final rollout aggregate remains separate.
- Current blocker-closure evidence:
  - `android.wake_token_directionality` is implemented under Plan 290 at the
    shared `P2PServiceImpl` store seam. Causal host RED/GREEN now pins
    token-bearing node-readiness waiting, one original deadline across the
    wait and bridge dispatch, immediate tokenless behavior, and safe
    disposal/closed-stream failure without dispatch. The final physical Pixel
    `21071FDF600CSC` + API-35 `emulator-5560` run passed both live assertions
    and its build capability on source digest `e2ab677e…`. Report:
    `build/sims/operator-inputs/wave4a-wake-token-final-pass-report.json`,
    SHA-256
    `7da2c832c98e9954580c46c1244fe5123869ae31083bea6cbcba1257d63d9557`;
    proof artifact SHA-256
    `fe2721f78e75be0adba8a1320ada3840276cbee12de43fe807abfd07013180b2`.
  - `groups.reaction_notification_campaign` is implemented under Plan 292:
    exact `orbit_create_group_fab` semantics, one non-force-stop recovery,
    current-process `TIME_TO_SENDABLE_BADGE`, pending-invite discrimination,
    split/idempotent cleanup, and bounded read-only final-log retries are host
    covered. The same final physical/emulator pair passed all four
    group/announcement message/reaction scenarios and cleanup on source digest
    `e2ab677e…`. Report:
    `build/sims/operator-inputs/wave4a-group-final-pass-report.json`, SHA-256
    `0aa1c02f5f03986a443297424aeeb12422db65d6796f45fd7fb6da7b08c0b116`;
    proof artifact SHA-256
    `e8b9a8cda9a4539580745006262f5102ff9c062aebecdb67e12b9db51bd8dad5`.
  - `intro.accept_notification_campaign` retains Plan 291's harness-only
    boundary. The absolute 24-minute deadline, shared phase allocations,
    acceptance discriminator, bounded child termination, and idempotent late
    cleanup are focused-host-green. The retained causal failure at Plan 252's
    exact-anchor convergence boundary is
    `build/sims/operator-inputs/wave4a-intro-anchor-race-report.json`, SHA-256
    `dad8b23c965df1de12302752798e9be390107ca1cdc43a3652421279af3492b2`.
    `W4A-BLOCKERS-AUTH-01` treats its product correction as a narrow Plan-252
    corrective amendment, not as silent Plan-291 scope expansion. The final
    Pixel `21071FDF600CSC` + `emulator-5558` + `emulator-5560` run then passed
    both physical-introducer and emulator-introducer assertions, cleanup, and
    its build capability on source digest `e2ab677e…`. Report:
    `build/sims/operator-inputs/wave4a-intro-pass-report.json`, SHA-256
    `85ac10b661e90b2d3bccc5a09117d5962f83fb074eeab24ed9ba94e6d9e45a47`;
    proof artifact SHA-256
    `87e42b8a657baed90edf445c57016c42b91d76871e422db36e52571cd649660b`.
  - `notifications.ios_payload_fast_path` recovered the complete existing
    APNs/signing/relay inputs and fixed only the deterministic cleanup verifier:
    it now parses JSON and requires `result.apps` to be empty instead of
    substring-searching echoed filter arguments. The retained current-source
    missing-identity failure (SHA-256 `54be15da…`) and zero-NSE-marker timeout
    (SHA-256 `41d10ea6…`) stayed red. After the existing auto-setup/bootstrap
    seam and registered permission XCUITest prepared a fresh dedicated
    receiver, the final physical iPhone
    `00008110-00184D622289801E` run passed all seven APNs, ordered
    NSE-decrypt, airplane-before-tap visibility, restoration, termination, and
    cleanup assertions on source digest `e2ab677e…`. The NSE diagnostic records
    exactly one ordered staged/decrypt/content-handoff sequence and zero
    failure/rejection markers. Cleanup again proved `result.apps=[]`, zero
    child builds, and zero manual actions. Report:
    `build/sims/operator-inputs/wave4a-ios-final-pass-report.json`, SHA-256
    `29f4d86574a56de803058363a91d52613127c93d3d8c6a5929f915a2a62d5b46`;
    proof artifact SHA-256
    `9ac71646c8aa8eb2edf952b1a7a7276a7eca6eff1147dae9478329160fec5b1b`.
  - All four live blockers are closed on one source digest. Plan-green now
    waits only for the final integrated host/analysis receipts and Graphify
    refresh; the cadence-protected **full** Wave 4A aggregate follows.

Recovered-input evidence is retained only in ignored/private `build/sims`
operator and proof paths; no credential, APNs token, payload, or raw handoff is
recorded here. The rebound iOS report is
`build/sims/operator-inputs/dtr13-ios-rebound-report.json` (SHA-256
`d1743a86290049a006e3b984ec4fb9e4950ab55ce9925739331cd0cdd556885c`).
Its redacted capture is
`build/sims/proofs/notifications.ios_payload_fast_path/capture-1785175691633447-58500/`;
the NSE diagnostic, payload-tap log, provider receipt, cleanup receipt, and
post-cleanup app inventory hashes are respectively
`2ea6b34dfcd5f8b50c852f6c62cd0b6ef316f0aadb8c4aedccbd7b85c6a376da`,
`e2ca937e4c33386b4600c7d705b5056419159a5b51367f317b0fe71c836c1c14`,
`fd3913894c0205e619ca090b8490f2a77663c50f625a7fd69e6562f6b7ee3e72`,
`2fb3d160b38a80fdca180106091467c2ec70c2b7e97e39ea3b94e1e68521b0cb`,
and `e3fdc34d7e06e05a5633e034fa6eac02ffdccf2d6a2b18b1c0ffcdf1b36159bd`.
An independent post-run `devicectl` query also returned zero matching apps.
The three reaction captures are
`capture-1785173379964132-30665`,
`capture-1785173643484847-32447`, and
`capture-1785173905339794-34258`; the final central report SHA-256 is
`f1a47002a156282d5f72421a4b9e4dd9bf3d1aa95c7f5418b0b74f2e15608b6b`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | planned | Plan 289; roadmap authorization/status | source inventory complete; plan sufficiency checklist applied | exact profile/root/workflow matrix, production phases, DTR-12 zero-exception delta, causal proof, gates, and rollback are explicit | independent review pending; no production edit permitted yet | run `$tdd-review` and repair only reliability gaps |
| 2026-07-27 | reviewed | Plan 289 and all cited production/Sims/runtime-root/gate sources | two independent `plan-fixes-required` audits repaired; closers found the final four-simulator and rollback wording issues, now corrected | per-component zero-construction, exact phase/async ownership, minimal ports, complete main-root inventory, exact live rows, discoverability, and inverse rollback are explicit | none | execute causal RED, then minimum GREEN |
| 2026-07-27 | RED — production boundary | `test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart`; unchanged `lib/main.dart` | `flutter test --no-pub test/core/lifecycle/main_debug_e2e_composition_boundary_test.dart --plain-name 'production main owns no concrete debug E2E harness construction'` -> exit 1 | test compiled and failed its assertion because `lib/main.dart` still contained `GroupMediaReliabilityE2EController.forInstalledProfile(` | causal RED accepted; not an import or compile failure | implement the separate root and thin ordered handoffs |
| 2026-07-27 | RED — nullable composition gate | `test/core/debug/debug_e2e_composition_root_test.dart`; unchanged `lib/main.dart` | `flutter test --no-pub test/core/debug/debug_e2e_composition_root_test.dart --plain-name 'default composition invokes zero harness factories and exact proof activations remain enabled'` -> exit 1 | test compiled and failed because `DebugE2ECompositionRoot.tryCreate(` did not exist in the production bootstrap | causal RED accepted; no production gate existed | add the minimum guarded construction policy, then preserve every authorized activation |
| 2026-07-27 | GREEN — authorized extraction | `lib/main.dart`; `lib/debug/debug_e2e_composition_root.dart`; nine migrated/new ownership suites; seven lifecycle/auto-setup sentinels; two standalone iOS contracts | focused nine-file run: 151 pass; lifecycle/auto-setup run: 24 pass; both standalone Dart contracts pass | Default composition returns before any harness factory; all authorized activation predicates and the original reset/startup/`runApp`/runtime-ready ordering remain. Five representative mutations each re-REDed and were restored: default guard, iOS production activation, sender phase, Android peer callback, and manifest define. | GREEN accepted; no production behavior, entrypoint, define, or command changed | run preservation and per-plan host gates |
| 2026-07-27 | GREEN — host preservation | Sims/profile/runtime-root/DTR-12 contracts; `groups`; `core-host-all`; completeness; analyzer; hygiene | `sims-contracts`: 38 pass; exact Sims/profile/runtime-root Flutter set: 59 pass; `runtime-roots`: 20 pass over 1,026 files; `architecture-boundaries`: 6 pass with 182/24/92 and zero issues; `groups`: 3,235 Flutter tests plus all Go tails; `core-host-all`: 357 paths / 2,805 tests; completeness: 1,342/1,342; strict analysis: zero issues; `git diff --check`: clean | All host-side per-plan gates are green. The DTR-12 exception manifest and every protected profile/manual-root/smoke-runner artifact retain their execution-start hashes. | host-green; live affected rows still required | execute the availability-bounded live matrix |
| 2026-07-27 | GREEN — affected live rows | discovered Android physical `21071FDF600CSC`; emulators `emulator-5554` and `emulator-5556`; four available iOS simulators; signed iOS group-media device build | inbox drain 3 assertions; media outbox 8; keepalive retry 6; voice 1; Android payload 4; typed group media 1; legacy Android group scenario PASS; four-simulator intro 11/11 scenarios; `build.ios.device.group_media_269` PASS | The preserved main-app, group, notification, keepalive, intro, and iOS group-media build paths remain executable on the available matrix. The keepalive row's initial transient `StateError` passed on an exact retry against the same cached APK. | passing rows accepted; no unavailable-hardware N/A used | classify the remaining four exact rows |
| 2026-07-27 | non-green — initial affected-live classification | unchanged wake/intro workflows; initially unresolved iOS/reaction operator inputs | wake failed twice with zero assertions; intro campaign failed twice after one assertion; iOS fast path blocked before proof; reaction campaign exited 78 before proof | Wake logs identify cold-start `INBOX_ERROR`; intro logs identify the unchanged workflow-budget exhaustion. At this point the iOS and reaction rows were provisionally classified as lacking external release/relay inputs. The recovery/reclassification row below supersedes that input diagnosis. | wake/intro behavior blockers accepted as out of scope; investigate existing source/session/live-relay provenance before treating iOS/reaction as external blockers | withhold Plan-green and Wave aggregate pending reclassification |
| 2026-07-27 | blocker recovery and live reclassification | archived Codex run provenance; owner-only local inputs; read-only live EC2; generated ignored operator inputs; exact iOS/reaction rows | reaction: build PASS, then three one-assertion fixture/UI failures; iOS: fresh build PASS, one automation-mode retry, current-peer rebind, then six-assertion functional/cleanup proof followed by app-removal-verifier false positive | Every previously alleged external input was found or regenerated without exposing secrets. Live EC2 attested the active Plan-257 relay/flag/digest/provider boundary. iOS APNs/NSE/offline-tap/visibility/network restoration and cleanup all succeeded; `result.apps=[]` proves removal despite the filter echo. Reaction reached real fixture setup on both available emulators. | input blockers refuted; four distinct narrow corrections required owner authorization outside the original DTR-13 structural boundary | record `W4A-BLOCKERS-AUTH-01` and execute Plans 290–292 plus the iOS verifier correction |
| 2026-07-27 | authorized blocker implementation / intermediate live evidence | iOS verifier; Plans 290–292; exact live rows | iOS causal/full contract 8 pass; Plan 290 focused set 17 pass; Plan 291 focused set 7 pass plus adapter contract; Plan 292 focused set 45 pass plus 12-widget sentinel. Intermediate live reports: wake two assertions PASS (SHA `1b958612…`), group four assertions PASS (SHA `58931a97…`), intro one-assertion FAIL exposing the Plan-252 exact-anchor race (SHA `dad8b23c…`). | The iOS verifier, wake product repair, intro harness budget/process repair, and group fixture/driver repair are implemented without changing protected profiles/roots. Plan 291 remains harness-only; the newly reproduced product correction is a narrow Plan-252 amendment under the same owner receipt. | later source changes supersede the two PASS reports as current-source closure; iOS live and Plan-252 correction remain pending | finish correction, rerun all four exact rows, then affected gates |
| 2026-07-27 | graph / Wave 4A closure staging | prior architecture refresh; current integrated blocker delta | The earlier incremental refresh mapped the DTR-13 extraction, but the final coherent blocker delta still requires one incremental refresh. No Dart-only aggregate is accepted or recorded as Wave 4A evidence. | Protected exception/profile/root hashes remain unchanged in the staged documentation. | final live rows, affected gates, graph refresh, and full aggregate pending | run the full `host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only` only after Plan-green |
| 2026-07-28 | iOS current-source causal recovery | protected receiver handoff; prior cleanup receipt; existing `auto_setup.json` seam; bootstrap capture; sanitized staging manifest; live relay attestation | First report FAIL before the APNs journey: `build/sims/operator-inputs/wave4a-ios-missing-identity-failure-report.json`, SHA-256 `54be15da5b9b55c1fd1d18fc07d0e5b15a020de37796f8fbc505db28b3f52b9e`, source digest `e2ab677e…`. Prior cleanup had `result.apps=[]`; the fresh install had no identity and relay history ended at that cleanup, so the protected handoff correctly timed out. Auto-setup then provisioned a fresh identity; protected bootstrap capture PASS; staging-manifest SHA-256 `17c9e86d754535a59bc87ca503e32ce2251bdc8f5bb77bfa8170edcd0dea4e62`; relay active at `v1.6.0`, binary SHA-256 `54b29298f1894c56a2b22eac9b1b234596fc6872fd7d54e30f31b97c01797594`. A second run reached accepted APNs but retained a zero-marker NSE timeout in `wave4a-ios-nse-timeout-failure-report.json`, SHA-256 `41d10ea64aee5c6a9157b2acb55676854604b822de8824258c9a7f8572a863a9`. | Recovery reused existing authorized auto-setup/bootstrap/XCUITest seams and exposed no identity, credential, token, or peer value. Both failures remain causal RED evidence and were not rebaselined. | exact permission and NSE observation state classified | rerun unchanged with the registered permission selector and independent private observer |
| 2026-07-28 | GREEN — final coherent-source live blocker replay | four exact Sims rows; Pixel `21071FDF600CSC`; API-35 `emulator-5558`/`emulator-5560`; iPhone `00008110-00184D622289801E`; live relay | Wake 2/2, intro 2/2, group/announcement 4/4, and iOS 7/7 assertions PASS; all build dependencies PASS; all four reports carry source digest `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e` and `validationErrors=[]`. iOS NSE counts are staged 1, decrypt OK 1, content handoff OK 1, and every failure/rejection count 0; provider cleanup and independent inventory both prove no candidate app remains. | Four blocker rows are accepted. Unavailable extra hardware/version bands remain N/A by policy, not blockers. | integrated host/analysis/graph closure remains | finish the per-plan gates, refresh Graphify, then run the one full Wave 4A aggregate |
| 2026-07-28 | GREEN — integrated affected gates in progress | affected exact tests; `1to1`; `intro`; `groups`; Sims/runtime/boundary contracts; analyzer | Focused wake 140/140, intro budget/runner 8, intro routing/wiring 13, group fixture/criteria/FAB 57, iOS causal/full 1/1 and 8/8, and preservation contracts PASS. `1to1`: 2,441 Flutter plus relay Go gates; `intro`: 300; `groups`: 3,239 Flutter plus 13 focused Go and relay toolchain; `sims-contracts`: 38/38; `runtime-roots`: 20/20 over 1,026 files with no drift; completeness: 1,346/1,346; architecture boundaries: 6/6, 182 dependencies, 24 placements, zero issues; strict analysis: zero errors/warnings/infos in 405.8 s with three reviewed suppressions unchanged. | No causal failure. `core-host-all` is the only still-running per-plan command. | wait for terminal core-family result | then run hygiene, refresh the graph, and freeze the tested tree |

## Final Wave 4A Evidence

- Final live reports; each carries coherent source digest
  `e2ab677e61688505cf0af0a1b3b3d5e62c4a7fc9fb94cc549b0c6bc0c0237f8e`,
  a passing build dependency, and no validation errors:
  - `android.wake_token_directionality`: 2 assertions PASS on
    `21071FDF600CSC` + `emulator-5560`;
    `build/sims/operator-inputs/wave4a-wake-token-final-pass-report.json`,
    SHA-256
    `7da2c832c98e9954580c46c1244fe5123869ae31083bea6cbcba1257d63d9557`;
    artifact SHA-256
    `fe2721f78e75be0adba8a1320ada3840276cbee12de43fe807abfd07013180b2`.
  - `groups.reaction_notification_campaign`: 4 assertions PASS on
    `21071FDF600CSC` + `emulator-5560`;
    `build/sims/operator-inputs/wave4a-group-final-pass-report.json`, SHA-256
    `0aa1c02f5f03986a443297424aeeb12422db65d6796f45fd7fb6da7b08c0b116`;
    artifact SHA-256
    `e8b9a8cda9a4539580745006262f5102ff9c062aebecdb67e12b9db51bd8dad5`.
  - `intro.accept_notification_campaign`: 2 assertions PASS on
    `21071FDF600CSC` + `emulator-5558` + `emulator-5560`;
    `build/sims/operator-inputs/wave4a-intro-pass-report.json`, SHA-256
    `85ac10b661e90b2d3bccc5a09117d5962f83fb074eeab24ed9ba94e6d9e45a47`;
    artifact SHA-256
    `87e42b8a657baed90edf445c57016c42b91d76871e422db36e52571cd649660b`.
  - `notifications.ios_payload_fast_path`: 7 assertions PASS on physical
    iPhone `00008110-00184D622289801E`;
    `build/sims/operator-inputs/wave4a-ios-final-pass-report.json`, SHA-256
    `29f4d86574a56de803058363a91d52613127c93d3d8c6a5929f915a2a62d5b46`;
    artifact SHA-256
    `9ac71646c8aa8eb2edf952b1a7a7276a7eca6eff1147dae9478329160fec5b1b`.
    The redacted NSE diagnostic SHA-256 is
    `a1344995874123fdbc8a78c6566727a16cfbfade4b140dbf5d12e05f9d6533dc`;
    cleanup receipt SHA-256 is
    `df5052cc52eb2c27047d46a1a19151957fe1b66a31f850e0639334aefe59c1c3`.
    Retained causal failures are the missing-identity report SHA-256
    `54be15da5b9b55c1fd1d18fc07d0e5b15a020de37796f8fbc505db28b3f52b9e`
    and zero-marker NSE-timeout report SHA-256
    `41d10ea64aee5c6a9157b2acb55676854604b822de8824258c9a7f8572a863a9`.
- Affected exact/curated/family gate results:
  - focused causal/preservation: wake 140/140 across five commands; intro
    budget/runner 8/8; intro resolver/open-flow/wiring 13/13; group
    fixture/criteria/FAB 57/57; iOS cleanup selector 1/1 and full contract
    8/8; all exact shell/standalone bootstrap, sender-projection, profile,
    entrypoint, and adapter contracts PASS;
  - `./scripts/run_test_gates.sh 1to1`: 2,441 Flutter tests plus relay Go
    gates, exit 0;
  - `./scripts/run_test_gates.sh intro`: 300 tests, exit 0;
  - `./scripts/run_test_gates.sh groups`: 3,239 Flutter tests, 13 focused Go
    tests, and relay toolchain contract PASS, exit 0;
  - `./scripts/run_test_gates.sh sims-contracts`: 38/38 components, exit 0;
  - `./scripts/run_test_gates.sh runtime-roots`: 20/20 tests over 1,026 files,
    trustworthy/no drift, exit 0;
  - `./scripts/run_test_gates.sh completeness-check`: 1,346/1,346 classified,
    exit 0;
  - `./scripts/run_test_gates.sh architecture-boundaries`: 6/6 tests,
    1,026 sources, 182 dependency and 24 placement exceptions, zero issues,
    exit 0;
  - `./scripts/check_flutter_analyze_strict.sh`: zero errors, warnings, or
    infos in 405.8 s; three reviewed suppression occurrences across three
    package roots unchanged; exit 0;
  - `core-host-all` and final hygiene: **running/pending**.
  The closure receipt must name these exact commands:
  `flutter test --no-pub test/integration/ios_notification_payload_xcui_contract_test.dart --plain-name 'cleanup verifies devicectl result apps rather than echoed arguments'`;
  `flutter test --no-pub test/integration/ios_notification_payload_xcui_contract_test.dart`;
  `bash scripts/test/intro_accept_notification_sims_adapter_contract_test.sh`;
  `./scripts/run_test_gates.sh 1to1`;
  `./scripts/run_test_gates.sh intro`;
  `./scripts/run_test_gates.sh groups`;
  `./scripts/run_test_gates.sh sims-contracts`;
  `./scripts/run_test_gates.sh runtime-roots`;
  `./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --reporter failures-only`;
  `./scripts/run_test_gates.sh completeness-check`;
  `./scripts/run_test_gates.sh architecture-boundaries`;
  `./scripts/check_flutter_analyze_strict.sh`; and `git diff --check`.
- The original reviewed TC-DTR13-11 discovery and eleven-row live receipt
  remains historical evidence: group/intro discovery, the seven already-green
  affected rows, and their exact profile/command availability are not erased
  or relabelled by the four-row blocker replay. The replay adds final
  current-source receipts for wake, iOS payload, intro accept, and group
  reaction only; it does not replace or silently re-run the full eleven-row
  inventory.
- Final `./graphify-arch/refresh_arch_graph.sh --incremental` result /
  fingerprint: **pending**.
- Full Wave 4A aggregate command:
  `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only`.
  Planned inventory, Flutter pass/skip/fail counts, all Go-tail results,
  retained log/archive path, and SHA-256: **pending**.

## Reviewer Findings

Initial verdict: `plan-fixes-required`.

- `High` — root activation did not prove independent component construction
  and file-only auto-setup conflicted with a nullable root. Applied: an exact
  per-component truth table plus a static same-phase auto-setup handoff that
  works with a null controller root.
- `High` — the proposed neutral port was broader than DTR-13 and ambiguous
  against the scope guard. Applied: retain the concrete private-media
  `MyApp`/`ConversationWired` port and permit only the three exact nullable
  overlay/start/runtime-ready handoffs.
- `High` — lifecycle and async proof was too coarse. Applied: an ordered trace
  for reset, joined probes, controller phases, auto-setup, `runApp`, sender,
  cold recovery/reconcile, poller, and runtime-ready receiver publication;
  exactly-once/no-dispose/no-duplicate requirements preserve process lifetime.
- `High` — the profile/headless inventory omitted hardcoded/default-main
  owners and one notification contract would fail after the move. Applied:
  exact command/metadata owner table and explicit migration of private-media,
  voice, notification, reaction, group-media, and lifecycle ownership locks.
- `Medium` — effective build contracts omitted relay injection, iOS simulator
  grace, disposable Gradle flags, and physical-iOS target/define/native
  settings. Applied: exact effective/build-only columns and TC-DTR13-06.
- `Medium` — standalone iOS receiver/sender Dart contracts were not registered
  under the claimed family. Applied: exact direct commands and explicit
  discoverability wording.
- `Medium` — affected live commands mixed Android and iOS scenarios and did
  not cover every main-app Sims action. Applied: exact filtered Sims capability
  rows, an Android-qualified group scenario, Android typed intro default, and a
  separate four-simulator legacy iOS leg only when available.
- `Medium` — rollback was not the exact inverse. Applied: restore every
  migrated contract/evidence/status file, delete every new artifact, rerun only
  surviving pre-DTR-13 contracts, refresh Graphify, and retain the historical
  owner receipt.

Graph review used `--profile review --budget 800`. The first query was broad
and was refined once with the exact poller/sender/receiver symbols, yielding
anchored context at fingerprint `332fe23f228dfb75`.

Five-lens closer: behavior and independent activation, architecture/API scope,
lifecycle/async ownership, TDD/proof depth, preservation/gate discovery, and
rollback are coherent and source-backed. Final verdict: `ready`.
