# Migrate SIMS journeys to production bootstrap and reusable builds

Status: **WAVE 1 COMPLETE (2026-09-30):** the foreground group-push pilot re-ran on USB Pixel `21071FDF600CSC` and `emulator-5554` and passed S1–S3 with exact cleanup; see the [Wave 1 closure record](production-bootstrap-migration-crosswalk.md#2026-09-30-wave-1-device-rerun-and-closure). Wave 2 continued on 2026-09-28 by explicit user instruction. Shared prerequisite registrations, the architecture Git-path correction and the additive provider/device journeys are integrated into main. All four Wave 2 Android campaigns passed with independent report verification and exact cleanup on one final detached-candidate source `48f5fd4fcbc941d838f0a63da638c6d3bf110efae447661e8a2b6671cb9dd18e`. The first integrated-main `host-all` failure is retained; after the reviewed test/inventory and beta source repairs, a full `host-all` passed 18,333 Flutter tests (two skips) and every Go, relay and native leg. On 2026-09-29, all four integrated-main Android campaigns also passed their original device assertions with empty oracles and exact cleanup on the USB Pixel and `emulator-5554`. Their SIMS reports share exact source digest `82d32bb186b69fea5fe9b77dbf811ca997a47afaa629ff19a2f3e058f43a94fc` and compatible APK digests; the broader wrapper fingerprints differ because they include non-campaign checkout inputs. The additive notification-open and sound journeys claim the FCM token after deliberate reopen so bootstrap token rotation cannot invalidate provider delivery. The first two integrated-main sound attempts remain retained as no-step Maestro failures with exact cleanup; the third passed all 17 cases. S16 had an unmuted Android notification MediaPlayer event routed to the emulator speaker at volume 5/7, but no acoustic waveform or hearing observation was attributable to that arrival. A bounded scrcpy capture control also failed to capture a known Settings preview. The fresh focused host checks passed. The later full `host-all` first attempt passed 18,333 Flutter tests with two skips but failed one original group notification assertion in the batch; the exact case and full 91-test file passed separately, then a complete Dart `host-all` rerun passed 18,334 tests with two skips. Its iOS-specific native legs stopped before tests because the invocation omitted the simulator ID; Go/relay and Android native passed. The user allowed available iOS simulators other than iPhone 15, or connected iPhones, for those separate native checks, of which Plan 371 passed on iPhone 17 Pro. The earlier Plan 373 attempt remains retained as interrupted by the requested reboot. A fresh pinned iPhone 17 Pro run on 2026-09-30 passed its Go and native host contract: three named mutations failed as expected, the restored control passed, and the exact 28-method XCTest set passed with zero skips; the original Swift source hash was restored. One bounded repeat sound campaign stopped at S7 on a 110-second no-step Maestro timeout with exact two-device cleanup, before its planned S16 audio capture. A successful system-audio positive control captured known Settings previews, but no acoustic waveform or human hearing is attributable to S16. The scoped preservation audit confirms all 282 baseline `integration_test` files, including 42 harnesses and the five Wave 2 originals, are unchanged; it separately records 38 changed protected test files in the wider dirty tree. **WAVE 2 COMPLETE (2026-09-30):** the user accepted S16's unmuted native SystemUI playback on the emulator speaker as sufficient audible-device evidence for this wave, while direct acoustic hearing remains unverified. The four integrated-main Android receipts, iOS Plan 373 native result, applicable host checks, build reuse and scoped original-file preservation audit close the Wave 2 boundary. The first UP-012 batch failure and bounded sound repeat failure remain documented; the broader dirty-tree affected selection is not a Wave 2 pass. Waves 3–5 remain paused except shared registrations or infrastructure required for Wave 2 gates. See the [Wave 2 continuation evidence](production-bootstrap-migration-crosswalk.md#wave-2-continuation--verified-device-evidence) and [final bounded audit](production-bootstrap-migration-crosswalk.md#2026-09-30-bounded-wave-2-closure-audit).

## 1. Objective and boundaries

Make application journeys execute the real production entrypoint and service composition, while retaining their existing assertions. Reduce repeated builds by supplying scenario data at runtime and sharing verified artifacts.

Cover the complete migration incrementally. The planning snapshot contained 40 top-level `integration_test/*harness.dart` files and 75,883 lines. Refresh this inventory at implementation start; these counts are source declarations, not executed test counts.

### Original-test preservation

Keep all original tests and harnesses unchanged while adding replacements alongside them. Do not delete, disable, exclude, redirect, or change the assertions of original tests without separate explicit user approval. Verified replacement coverage makes retirement reviewable; it does not itself authorize retirement.

The user separately approved two exact Wave 2 registration exceptions after shadow-copy verification: three production-journey callers in `production_application_bootstrap_phase_contract_test.dart`, and two already-passing call-wake methods plus the 73-to-75 manifest count in `run_android_headless_recovery_native_374.sh`. Neither patch changes an assertion. Other original tests and harnesses retain their approved or original bytes; these approvals do not authorize further edits.
The user later separately approved two more exact original-test repairs after
shadow-copy passes: update only the two reviewed bootstrap fingerprints in
`dtr18_layering_relocation_contract_test.dart`, and register the Git-visible
`third_party/video_compress` root in
`analyzer_suppression_ratchet_test.dart`. No assertion logic changed. All
three affected original test files passed 29 tests together after the missing
beta video-compress source companion was restored.

This constraint supersedes automatic retirement and ownership-switch steps in the earlier conversational plan. Additive migration and verification may proceed independently. Duplicate executions can remain until the user approves a concrete retirement proposal.

Classify existing tests by their assertion boundary:

- **Application journeys:** migrate to production startup and production-created services.
- **Background/native proofs:** execute the relevant production headless or native entrypoint without initializing the foreground application first.
- **Component tests and benchmarks:** retain focused setup where isolation is part of the measurement or assertion.
- **Dispatchers and helpers:** retain where they provide routing, fixtures, observations or cleanup without duplicating application composition.

Use Appium MCP for exploration, OS interaction, reproduction and visual evidence. Use Maestro for stable repeatable UI journeys. Keep existing native/protocol campaigns for assertions those UI tools cannot establish. No skill is implicitly invoked by this plan.

## 2. Shared architecture and interfaces

### Production composition and scenario controls

Keep `ProductionApplicationBootstrap` as the owner of foreground service construction. Extend the existing `DebugE2ECompositionRoot` with small feature-specific controls and observers bound to the services production creates.

Replacement tests must not construct replacement listeners, repositories, routing graphs or application roots to claim an application journey passed. Do not use the bootstrap's preparation override to substitute a test graph.

Reuse the existing SIMS invocation identity: profile, scenario, role, run ID and nonce. Preserve its acknowledgement and stale-invocation rejection. Share protocol definitions through an application-safe module rather than importing integration-test libraries into production. Preserve compatibility for existing callers and wire formats.

Separate three responsibilities:

- **Fixture preparation:** establish isolated accounts and initial state before the measured operation.
- **Actions and fault injection:** invoke the real UI or production boundary; intercept only the explicitly tested failure boundary.
- **Observation:** read results from the production instance without synthesizing success or changing its decisions.

Expose readiness milestones for fixture acceptance, production runtime readiness and scenario-specific readiness. Retain existing deadlines; never treat readiness as scenario completion.

Controls remain inactive for ordinary production launches. Preserve the current profile-specific activation rules, including existing signed/native proof exceptions.

### Builds and runtime configuration

Reuse `android.e2e.main` for compatible foreground journeys. Add an additive `ios.simulator.app` profile targeting `lib/main.dart`; retain the existing harness-based simulator profile and its consumers.

Move roles, run IDs, fixture references and scenario selection into runtime configuration for replacement journeys where they do not represent production configuration. Preserve separate variants for meaningful compile flags, provider configuration, application identity, architecture, signing and build mode.

Extend central build preparation to replacement adapters. Require verified artifact and input digests; prohibit fallback child builds when an artifact is missing or incompatible.

Prepare all peer artifacts before starting timed scenarios. Install and reset independently of compilation. Preserve scenario isolation even when artifacts are shared.

### Inventory and UI execution

Keep executable ownership in `tool/testing/selection.json` and build profiles/capabilities in `tool/sims/critical_features.json`.

Add Maestro execution through the existing wrapper and device leases. Discover its flows, map them to obligations, and require matching per-flow results. A missing, skipped or duplicate result cannot satisfy an obligation.

Declare Maestro explicitly in driver metadata without weakening existing campaign justification requirements. Appium MCP sessions remain explicit and must end before handing a device to Maestro or instrumentation. Supplemental exploration does not silently satisfy automated coverage.

Use stable Flutter semantics identifiers. Give each new journey one primary automated owner; combine UI evidence with native/protocol receipts when the obligation requires both. During migration, label old/new comparison runs separately and do not sum overlapping assertions as additional coverage.

Keep scenario modules independent. Adding an ordinary journey should require scenario setup, actions, assertions, cleanup and inventory registration, without changing production service construction. External UI-flow and runtime-data changes should reuse compatible builds; new compiled controls or test logic may require rebuilding the affected profile.

## 3. Ordered migration

### Wave 0 — Freeze and reconcile the baseline

Preserve current local changes in an isolated candidate before implementation or long campaigns. Resolve an explicit baseline SHA and record candidate/configuration fingerprints. Do not discard or commit user changes to obtain that candidate.

Run inventory validation, discovery and full planning. Produce an assertion-level migration crosswalk containing:

- Existing scenario, selector, variant and owning runner.
- Assertion boundary and required platform/configuration.
- Current build profile and duplicate service construction.
- Migration wave and replacement owner, or a reason to retain focused setup.
- Original-route preservation status and any separately approved retirement decision.

Keep the crosswalk and durable migration decisions in this document or a directly linked canonical supporting document. Keep run receipts and timings in ignored artifacts; do not create session diaries or a second executable inventory.

Capture build counts, cache outcomes, setup duration and scenario duration separately. Reconcile newly discovered obligations throughout migration.

**Exit:** every discovered harness obligation has a disposition; existing gaps and failures remain visible.

### Wave 1 — Shared controls and foreground group-push pilot

Add a production-bootstrap replacement for `foreground_group_push_simulator_harness.dart`. Replace its manually assembled group listener, visibility dependencies and notification service in the new path with production-owned instances. Leave the original harness unchanged.

Preserve all existing assertions:

- **S1:** live delivery is demonstrably missed; injected foreground push recovers the exact message once and produces one notification request with the correct route payload.
- **S2:** live delivery followed by push leaves one stored message and one notification request.
- **S3:** the controlled missing-group drain fails once; production eligibility handling suppresses the fallback notification.

Observe notification requests at the production notification boundary without replacing the notification implementation. Keep OS presentation and actual provider delivery as separate proofs. Inject S3's failure narrowly; do not bypass the production fallback/eligibility chain.

Use runtime roles and fixture identifiers so both peers consume the same compatible artifact. Drive ordinary user actions through the agreed UI tools; retain a narrow campaign adapter for precise injected-push and internal assertions, with its concrete non-UI proof reason registered.

Run the new Android proof on the default physical/emulator pair. Preserve and compare the existing iOS simulator evidence; do not remove or redirect that route without separate approval.

**Exit:** all three scenarios retain equivalent assertions, relevant negative probes fail correctly, runtime role changes cause no rebuild, and the new pilot constructs no application service graph.

### Wave 2 — Routing, notifications and private-media journeys

Add production-bootstrap replacements for routing smoke, notification-open-during-chat, notification sound, payload persistence and private-media user journeys.

Use production navigation, lifecycle, visibility and notification handling. Preserve cold/warm, foreground/background, unread, route-payload and privacy distinctions.

Retain database, crypto, media and native assertions alongside UI flows. Direct fixture seeding may establish unrelated prerequisites, but must not bypass the operation under test.

Provider probes remain narrowly scoped provider tests unless their assertion explicitly includes application startup.

**Exit:** each replacement journey has production startup evidence, its original assertion coverage and isolated cleanup. Original tests remain intact.

### Wave 3 — Shared group stack and large group campaign

Add production-composed replacements for consumers of `setupGroupMultiDeviceStack` incrementally. Cover group smoke, invite/status and lifecycle journeys before the large multi-party campaign.

Organize scenario modules by existing catalog family. Keep production composition shared; keep scenario orchestration outside bootstrap.

Preserve all 109 required multi-party catalog cases recorded at planning time, plus any subsequently discovered obligations, role/topology requirements, intermediate assertions and terminal receipts. Preserve direct callers' existing selection behavior; full mode must continue selecting the complete catalog.

Do not replace the shared test stack with a differently named test service container. Keep the old construction available for original callers until retirement is separately approved.

**Exit:** the complete catalog is accounted for and replacement application journeys no longer depend on the duplicated group graph.

### Wave 4 — Remaining transport and performance harnesses

Apply the baseline classification to transport census, inbox replay, reconnect diagnostics and benchmarks.

Add production-entrypoint replacements for measurements claiming application startup, resume, routing or end-user latency. Preserve thresholds and define the measured interval explicitly.

Retain isolated crypto, bridge and algorithm benchmarks. Where a production-entrypoint measurement changes what is measured, retain the original benchmark as component evidence and add a separately named application measurement.

Implement an additive adapter for sharing compatible XCTest build products across selectors using attested bundles and `test-without-building`. Require explicit provenance validation and independent per-selector fixtures/results. Keep original fresh-build routes unchanged until an ownership switch is approved.

**Exit:** every remaining harness has either a verified replacement or a documented, accurately scoped retained purpose.

### Wave 5 — Reviewable retirement proposal and full closure

Prepare a concrete retirement proposal identifying each original route or file, its replacement, preserved assertions/variants/platforms, comparative evidence and expected reduction in builds or executions.

Do not execute that proposal without separate explicit user approval. If approval is deferred, complete additive migration reporting with original routes retained and duplicate execution costs stated.

After approval, switch the approved canonical owners and remove only approved orphan entrypoints, duplicated composition, obsolete build profiles and stale selectors. Update runtime-root ownership and source fingerprints. Keep retained original evidence immutable.

Add a focused regression guard preventing replacement journey modules from reconstructing application graphs or importing legacy stacks. Do not impose this restriction on intentionally isolated component tests or preserved original harnesses.

## 4. Validation and retirement gates

Before selecting checks for each code-changing slice, read the relevant testing knowledge and manifest entries. For each migration slice:

1. Validate inventory metadata with `python3 scripts/mknoon_checks.py validate`.
2. Preview and execute affected selection with a verified explicit `--base` and `--local`.
3. Run focused causal tests, preservation sentinels and the affected curated gate.
4. Execute the replacement scenarios with per-case receipts.
5. Update verified testing knowledge in `docs/testing/TESTING.md`.

Required cross-cutting cases:

- Wrong profile, role, nonce and missing runtime configuration are rejected.
- Bootstrap/readiness failure cannot become a passing scenario.
- Scenario cleanup prevents order dependence and restores only owned state.
- Runtime parameter changes reuse artifacts; relevant source/configuration changes invalidate them.
- Missing artifacts cannot trigger hidden builds.
- Missing, duplicate or skipped child receipts leave coverage incomplete.
- Normal production activation retains no new test controllers.
- Headless proofs do not depend on prior foreground startup.
- Relevant fault injections demonstrate that replacement assertions detect the intended failure.
- Original tests, selectors and assertion expectations remain unchanged before an approved ownership switch.

Run full `host-all` at completed dependency-wave boundaries and final closure, not after every slice. Finish with one canonical full run on the stable candidate without `--only`; mixed-candidate diagnostic results cannot certify completion. Use a fresh ignored output directory for every wrapper invocation.

A route is eligible for retirement review only when its assertions, variants and platforms have replacement evidence, or an explicit retained owner. Preserve first-attempt failures and required device cleanup review. Do not automatically retry device campaigns, extend deadlines or weaken assertions.

## 5. Defaults and completion criteria

Rediscover targets before execution and verify ownership and reservations. Planning discovery found the following default candidates; this table is historical availability evidence, not a lease or a permanent device requirement:

| Purpose | Candidate |
|---|---|
| Ordinary two-peer Android proofs | `21071FDF600CSC` + `emulator-5554` |
| Additional Android peer when required | `emulator-5556` |
| Existing iOS simulator comparison | `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` + `6597ECAD-38EE-49AF-9A08-B1B0CA4BDD76` |

Use `flutter devices --machine`, `adb devices` and `xcrun simctl list devices available` as applicable. Pin every device command to a discovered target. Use physical iOS only for existing iOS-specific/provider/native obligations; verify USB availability when executing. Unavailable targets are `N/A (target unavailable by project policy)`. Missing fixtures, failed discovery or unavailable access on an otherwise available target remain explicit blockers.

Maestro was not found on the planning shell's PATH. Establish and record its supported toolchain during setup; do not assume it is already usable. Respect the checkout's Flutter configuration and existing dependency locks.

Additive migration completion requires:

- Every original and newly discovered obligation accounted for.
- Replacement journeys executing production composition.
- No duplicated application graph in replacement modules.
- One cold build per required compatible input identity and zero warm rebuilds for unchanged replacement artifacts.
- No undeclared child builds in replacement execution.
- Original tests and harnesses preserved unless their specific retirement was approved.
- Complete applicable scenario evidence, with unavailable hardware and unresolved manual requirements reported separately.

Full retirement completion additionally requires approval and execution of the concrete retirement proposal, followed by stable-candidate full closure. Report aggregate build totals honestly while both old and new routes remain active; the replacement build target does not imply zero legacy builds.

The first implementation deliverable is Wave 0 plus Wave 1. Later waves depend on that pilot's accepted runtime controls, evidence binding and build-reuse contract.

## Planning provenance

This plan was derived from repository inspection and the migration discussion on 2026-09-27. Key inspected sources were the production bootstrap and debug composition root, SIMS manifests/build cache/runtime protocol, the full-inventory wrapper/adapters, the foreground group-push harness, and the setup/full-regression entries in `docs/testing/TESTING.md`.

No migration builds or tests were executed while preparing or saving this plan. Inventory counts and device availability must be refreshed before implementation.
