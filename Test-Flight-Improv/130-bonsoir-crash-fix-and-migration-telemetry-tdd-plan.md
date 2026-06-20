# 130 — Bonsoir (mDNS) iOS crash fixes + Account-Migration assembly telemetry

Status: **PARTIALLY IMPLEMENTED** (2026-06-19, host-green, uncommitted). TDD-first. **No DB migration.**

Implementation progress:
- **Part A (A1+A2+A3) — DONE, host-green.** New `migration_breadcrumb.dart` (sanitized, sink-seam,
  `kAccountMigrationTelemetry`) + 6 unit tests; per-phase `ASSEMBLY_PHASE` via an `enterPhase` helper,
  `ASSEMBLY_OK` on success, and the A0 catch now routes through the primitive as `ASSEMBLY_FAIL`
  (phase+type+reason+redacted detail) — 2 new tests in `account_migration_bundle_transfer_test.dart`
  asserting the ordered phase sequence + the failure phase/reason. `flutter test
  test/features/account_migration/` = 275 green; analyze 0 new.
- **Part B1 (B1.1/B1.2/B1.4 + B1.3 via `_stopping`) — DONE, host-green.** `bonsoir_discovery_service.dart`:
  skip resolving our own service, single-flight `_resolvingPeerIds`, `_stopping` guard on
  `resolvePeer`/`_issueResolve`, cleared on resolved/lost. 3 new contract tests; the old chatty
  "nudges a re-resolve" test was updated to the single-flight contract (peer SET unchanged — INV-B1).
  17 bonsoir tests green; analyze 0 new. (B1.3 realized as `_stopping` + existing sub-cancel-before-stop
  ordering rather than a timed drain — the actual UAF is closed by the B2 native patch.)
- **Sims gate hygiene — DONE.** Classified the pre-existing unclassified
  `sender_media_unavailable_fallback_proof_test.dart` (1:1 + group) in
  `check_reliability_simulation_discovery.sh`; `reliability-sim move-feature --list` now passes.
- **OQ-1 RESOLVED (decisive):** Upgrading bonsoir 5→7 does **NOT** fix either vector — verified by
  reading bonsoir_darwin **7.1.0** source: broadcast still calls `DNSServiceProcessResult` on the main
  thread; `dispose()` still never cancels `pendingDispatchSources`; resolve still uses
  `Unmanaged.passUnretained(self)` — and 7.x ADDS a *second* unretained `DNSServiceGetAddrInfo`
  (`resolveAddress`) path (LARGER UAF surface). 7.x also changes the API (`service.host` →
  `hostAddresses`/`hostname`, `discoveryServiceUpdated` event). ⇒ a native patch is required on EITHER
  version, so the vendored-patch of the current 5.1.3 is the lower-risk path (no API migration). The
  pubspec bump to ^7.1.0 was applied to fetch+inspect 7.x, then reverted to ^5.1.0.
- **A-SIM-1/A-SIM-2 — DONE + sim-verified.** Added to `account_migration_group_media_durability_simulator_test.dart`;
  `reliability-sim move-feature --only 1` **PASSED on the iPhone 17 Pro simulator** (real device build):
  the failing case emits `ASSEMBLY_FAIL phase=buildFilePayload reason=fileManifestBlockingIssues`; the
  success case the ordered `ASSEMBLY_PHASE…ASSEMBLY_OK` sequence.
- **Part B2 — chosen path: vendored patch ON TOP OF 7.x** (per owner). API migration mapped:
  discovery event model enum→**sealed classes** (`BonsoirDiscoveryServiceFoundEvent`/`ResolvedEvent`/
  `LostEvent`, switch on subtype); `ResolvedBonsoirService.host` → `BonsoirService.hostAddress`
  (firstOrNull of `hostAddresses`); `resolve`/`serviceResolver`/`eventStream`/`ready`/`start`/`stop`
  unchanged. NOT yet executed — it is a large **app-wide** local-discovery migration (affects everyday
  messaging discovery, not just Move) + a native fork of 7.x (broadcast off-main-thread; cancel
  `pendingDispatchSources` incl. the NEW `resolveAddress` source; retain self). Native verification is
  device-build-gated (pod install + Xcode).
- **PENDING:** Part B2 execution (7.x wrapper migration + test-fake migration + vendored native patch
  + device build); **Part B3** device repro on the two iPhones.

This plan covers the two follow-ups from the 2026-06-19 "Move Account / could not assemble the
account bundle" investigation:

- **Part A** — keep + expand the release-visible migration telemetry breadcrumbs so the *next*
  "could not assemble" (for this user or any beta tester) prints the exact failing **phase + reason**
  to the device console. Low risk, pure Dart, strict TDD.
- **Part B** — fix the two real `bonsoir_darwin` (mDNS/Bonjour local-discovery) iOS crash vectors that
  SIGKILL the app during local discovery (including mid-Move). Two layers: deterministic Dart-wrapper
  hardening (strict TDD) + a vendored native Swift patch (test-assisted + device-verified).

---

## Background — what the investigation established (evidence, not speculation)

Source: live device debug on the reporter's two phones (iPhone 11 `00008030-001A6D2801BB802E`,
iPhone 17 Pro Max `00008150-001C3C6A3684401C`), read-only via `libimobiledevice`. Artifacts saved
under `/tmp/mknoon_migration_debug/` (crash reports + syslogs of the failing 12:07 run and the
successful run). Full write-up in auto-memory `project_account_migration_assemble_failure_debug`.

1. **"Could not assemble the account bundle" is a source-side, destination-blind assembly exception.**
   `_runOldPhoneExportAndHandoff` (`lib/features/account_migration/application/account_migration_local_transfer_runtime.dart:608-635`)
   builds the *entire* bundle via `source(request)` (line 620) **before** the new phone is ever
   contacted (`_postJson` at 640+). The `catch` (621-635) maps any assembly throw to
   `bundleExporterUnavailable` + `accountMigrationBundleSourceFailedSafeMessage`
   (`account_migration_transfer_flow.dart:104`). The reporter's working "iPhone↔Pixel" test had the
   **Pixel as source**, so the iPhone-as-source assembly path had simply never been exercised.

2. **Release builds emit no migration diagnostics.** `flowEventLoggingEnabled = kDebugMode`
   (`lib/core/utils/flow_event_emitter.dart:217-218`) gates `emitFlowEvent`'s `debugPrint` off in
   release/TestFlight, and the migration code logs *only* via `emitFlowEvent`. Confirmed in syslog:
   the failing run produced no migration reason, only `<private>` os_log. **However**, plain Flutter
   `print`/`debugPrint` *is* visible in TestFlight syslog as
   `Runner(Flutter)[pid] <Notice>: flutter: …` (240 such lines captured) — so a targeted, sanitized
   `debugPrint` is a viable release telemetry channel. This is the basis for Part A.

3. **The failure was transient / process-state, not a code bug that got fixed.** Assembly code
   (`account_migration_bundle_transfer.dart`) is **byte-identical between the failing build 104 and
   the working build 106** (`git log` shows only `lib/core/local_discovery/*` changed between them,
   which runs *after* assembly). The export dir is under **Documents**
   (`main.dart:1894` → `${appDocDir}/account_migration/export`), which survives reinstall, so the
   reinstall didn't clear file wreckage — it cleared **process/in-memory state** (fresh pid). The
   exact phase/reason was never captured (the instrumented run succeeded). **This is why Part A
   matters: we still don't have a confirmed root cause for the assembly failure.**

4. **Two genuine `bonsoir_darwin` 5.1.3 native crash vectors on the iPhone 11 (build 104), confirmed
   from crash reports:**
   - **Vector 1 — Broadcast main-thread watchdog (`0x8BADF00D`, Jun 14):**
     `BonsoirServiceBroadcast.start()` calls **`DNSServiceProcessResult(sdRef)` synchronously on the
     calling (Flutter platform / main) thread**
     (`~/.pub-cache/.../bonsoir_darwin-5.1.3/darwin/Classes/Broadcast/BonsoirServiceBroadcast.swift:35`).
     Unlike the discovery side, it sets up **no** background `DispatchSource`. On a slow/contended
     mDNS environment (two iOS peers on AWDL) this blocks the main thread >10s → iOS scene-update
     watchdog SIGKILL. Crash stack: `recvfrom` → `DNSServiceProcessResult` → `BonsoirServiceBroadcast.start()`
     → `FlutterMethodChannel` → main dispatch queue.
   - **Vector 2 — Resolve use-after-free (`EXC_BAD_ACCESS` @ 0x0, Jun 15):**
     `resolveService` passes `Unmanaged.passUnretained(self)` as the C callback context
     (`Discovery/BonsoirServiceDiscovery.swift:125`), and `dispose()` (lines 190-200) deallocates
     `pendingResolution` sdRefs but **never cancels `pendingDispatchSources`** (lines 22-25, 173). A
     dispatch-source read handler / `resolveCallback` can therefore fire after the
     `BonsoirServiceDiscovery` is freed and dereference a dangling `self`/`sdRef` → jump to 0x0. Crash
     stack: `handle_resolve_response` → `closure #1 in BonsoirServiceDiscovery.resolveService` → 0x0.

5. The app already partially mitigated a *third* bonsoir iOS crash (log stringification) with
   `printLogs: false` (`lib/core/local_discovery/bonsoir_discovery_service.dart:22-23, 65-67`). The
   two vectors above are **not** covered by that mitigation.

6. The app's Dart wrapper (`BonsoirDiscoveryService`) currently amplifies Vector 2 exposure:
   - resolves on **every** `discoveryServiceFound` (`bonsoir_discovery_service.dart:122`) **including
     its own advertised service** (the `_ownPeerId` skip happens only in the *resolved* handler at
     line 127, after the resolve was already issued);
   - a **20s periodic timer** re-resolves all aging peers (lines 98-109) with no single-flight guard;
   - `resolvePeer` (line 280) issues yet another concurrent resolve;
   - `stopAdvertising`/`dispose` (187-210, 292-295) tear down discovery without draining in-flight
     resolves.
   More concurrent resolves + teardown-during-resolve = more UAF windows. These are all
   **deterministically testable in Dart** via the existing `BonsoirBroadcastFactory` /
   `BonsoirDiscoveryFactory` seams.

Existing test assets to extend: `test/core/local_discovery/bonsoir_discovery_service_contract_test.dart`
(325 lines), `test/core/local_discovery/bonsoir_discovery_getlocalpeer_eviction_test.dart` (133 lines).

---

## Guiding principles

- **TDD-first** for every Dart change: write the red test that asserts the missing behavior, watch it
  fail, implement, watch it pass. Mutation-verify the key guards (temporarily break the guard, prove
  a test goes red, revert).
- **No secrets in telemetry.** Every breadcrumb string runs through `sanitizeDiagnosticText`
  (`flow_event_emitter.dart`). A test asserts redaction.
- **Behavior-preserving where possible.** Part A adds logging only. Part B Dart hardening must not
  change *which* peers are discovered/resolved — only *how often / when* resolves are issued and how
  teardown is sequenced.
- **The native patch is the root fix; the Dart hardening is defense-in-depth.** Ship both. Even with
  a perfect Dart wrapper, Vector 1 (synchronous main-thread `DNSServiceProcessResult`) can only be
  fixed natively.

---

# PART A — Migration assembly telemetry (pure Dart, strict TDD, no migration)

Goal: any "could not assemble" — or any silent stall in assembly — prints a bounded, sanitized,
release-visible breadcrumb sequence to the device console so we can read the exact phase + reason via
`idevicesyslog -m MKNOON_MIG`.

### A0 — Keep the failure breadcrumb (ALREADY IN TREE, uncommitted)
`account_migration_bundle_transfer.dart` catch (~line 300) already emits:
`debugPrint('MKNOON_MIG_ASSEMBLY_FAIL phase=$phase type=… reason=… detail=${sanitizeDiagnosticText(error)}')`.
This plan formalizes it under a single primitive (A1) and adds tests (currently untested).

### A1 — Breadcrumb primitive + test seam (RED→GREEN)
- New tiny module `lib/features/account_migration/application/migration_breadcrumb.dart`:
  ```
  const bool kAccountMigrationTelemetry = true; // beta diagnostic; flip off for GA
  typedef MigrationBreadcrumbSink = void Function(String line);
  MigrationBreadcrumbSink? _testSink;
  @visibleForTesting void debugSetMigrationBreadcrumbSink(MigrationBreadcrumbSink? s);
  void migrationBreadcrumb(String event, {Map<String,Object?> fields = const {}}) { … }
  ```
  - Always builds a single line `MKNOON_MIG <event> k=v k=v …`, with every value passed through
    `sanitizeDiagnosticText`.
  - Calls `_testSink` if set (for assertions); otherwise `if (kAccountMigrationTelemetry) debugPrint(line)`.
  - **No `sessionId` in cleartext** beyond a short prefix (reuse the peer-id length gate convention).
- **Tests** (`test/features/account_migration/migration_breadcrumb_test.dart`, NEW):
  1. `migrationBreadcrumb('X', fields: {'phase':'p'})` → sink receives `MKNOON_MIG X phase=p`. (RED first.)
  2. A field containing a fake secret (e.g. `privateKeyHex: 'deadbeef…'`) is redacted to `[redacted]`.
  3. With `kAccountMigrationTelemetry` semantics: when no sink is set the call does not throw.

### A2 — Per-phase milestones on the source assembly path (RED→GREEN)
- In `account_migration_bundle_transfer.dart` `call()`, after each existing `phase = '…'` assignment
  (validateConfiguration → prepareExportDirectory → readDatabaseKey → loadDatabaseRows →
  collectSecureStorage → buildFilePayload → applyFilePathRepairs → exportDatabaseSnapshot →
  writeMetadataBlob → buildEntryStream), emit `migrationBreadcrumb('ASSEMBLY_PHASE', fields:{'phase':phase})`
  **once at phase entry** (bounded: ~10 lines per run). Update A0's catch to call
  `migrationBreadcrumb('ASSEMBLY_FAIL', fields:{'phase':phase,'type':…,'reason':…,'detail':error})`.
- Rationale: a watchdog/SIGKILL (no exception) leaves the **last phase breadcrumb** as the smoking
  gun even when the catch never runs — this is what distinguishes a hang (e.g. exportDatabaseSnapshot
  on a huge DB) from a thrown reason.
- **Tests** (extend the existing bundle-source contract test, or NEW
  `account_migration_bundle_transfer_breadcrumb_test.dart`):
  1. A successful assemble emits `ASSEMBLY_PHASE` breadcrumbs in the exact documented order. (RED first.)
  2. An injected failure at `collectSecureStorage` emits phases up to and including `collectSecureStorage`
     then `ASSEMBLY_FAIL phase=collectSecureStorage reason=missingCriticalSecureValue`.
  3. Mutation check: remove the `buildFilePayload` breadcrumb → test 1 goes red.
- Use the existing fake `SecureKeyStore` / source-DB fixtures already used by the migration suite;
  inject the breadcrumb sink via `debugSetMigrationBreadcrumbSink` in `setUp`/`tearDown`
  (**synchronous** teardown — see `feedback_testwidgets_sync_io_only`).

### A3 — Success + receiver milestones (optional, same pattern)
- Source: `migrationBreadcrumb('ASSEMBLY_OK', fields:{'segments':…})` at the end of `call()`, and
  one breadcrumb at the runtime transfer milestones (manifest posted, segments sent, handoff done) in
  `account_migration_local_transfer_runtime.dart`.
- Receiver (new phone): breadcrumbs at importingBundle / importVerified / activated / failed.
- **Tests**: assert OK breadcrumb on success; assert receiver failure breadcrumb carries the reject
  reason. Defer if scope-limited; A1+A2 already close the reported gap.

### Part A invariants
- INV-A1: no breadcrumb value escapes `sanitizeDiagnosticText` (test-asserted on a secret-bearing field).
- INV-A2: bounded volume — ≤ ~12 source breadcrumbs per Move attempt (no per-segment, per-row, or
  per-file logging).
- INV-A3: zero behavior change — breadcrumbs are fire-and-forget; a sink/throw must never abort
  assembly (wrap the emit in a guard; test that a throwing sink doesn't break assemble).

### Part A gates
`flutter test test/features/account_migration/` green; `flutter analyze` 0 new issues; device check:
intentionally fail once (e.g. on a build pointed at a DB with a missing key) and confirm
`idevicesyslog -m MKNOON_MIG` prints the phase sequence + `ASSEMBLY_FAIL`.

---

# PART B — Bonsoir mDNS iOS crash fixes

Two independent fixes per vector × two layers (Dart hardening + native patch). Land Dart hardening
first (deterministic, low risk), then the native patch (root fix).

## B1 — Dart wrapper hardening (strict TDD, `bonsoir_discovery_service.dart`)

All testable against the existing `createBroadcast`/`createDiscovery` factory seams with fake bonsoir
objects (extend `bonsoir_discovery_service_contract_test.dart`).

### B1.1 — Don't resolve our own advertised service (RED→GREEN)
- In `_handleDiscoveryEvent` `discoveryServiceFound` (lines 114-123), **skip `service.resolve(...)`
  when `service.attributes['peerId'] == _ownPeerId`**. (Today the own-peer check is only in the
  *resolved* branch at line 127, so we still issue a resolve against our own broadcast — wasted
  resolve + extra UAF window, and on two iOS devices both advertising `_mknoon._tcp` this doubles
  resolve traffic.)
- **Test**: feed a `found` event whose `peerId == ownPeerId` → assert the fake resolver is **not**
  invoked; a foreign peer → resolver **is** invoked.

### B1.2 — Single-flight resolves per peer (RED→GREEN)
- Track in-flight resolves (`Set<String> _resolvingPeerIds` keyed by peerId, or by service). Skip
  issuing a new `service.resolve(...)` from the `found` handler, the 20s timer (98-109), and
  `resolvePeer` (276-289) when one is already in flight for that peer; clear on resolved/lost/timeout.
- **Test**: two rapid `found` events (or a `found` + timer tick) for the same peer → resolver invoked
  **once**; after the resolved event lands, a subsequent refresh resolves again.

### B1.3 — Teardown sequencing: cancel timer + drain before discovery teardown (RED→GREEN)
- In `stopAdvertising`/`dispose`: cancel `_refreshTimer` **before** stopping discovery (already cancels
  first — keep), and **await/await-best-effort in-flight resolves to settle (bounded) before
  `_discovery?.stop()`**, so we don't tear down the native discovery while a resolve dispatch source
  is live (the precondition for Vector 2). Complete `_pendingResolves` to null (already done, 203-206).
- **Test**: start a resolve (fake resolver that hasn't completed), call `stopAdvertising`, assert
  discovery `stop()` is **not** called until the pending resolve settles or a bounded timeout elapses;
  assert no resolve callback is delivered after `stop()`.

### B1.4 — No resolve after stop (RED→GREEN)
- Guard `resolvePeer` and the timer callback to no-op if `_discovery == null` (post-stop). (Timer is
  cancelled in stop, but harden against a queued tick.)
- **Test**: call `resolvePeer` after `stopAdvertising` → returns null, fake resolver not invoked.

### B1 invariants
- INV-B1: discovery set (which peers are surfaced on `discoveredPeersStream`) is unchanged vs today
  for any sequence of found/resolved/lost events — only resolve *frequency/timing* changes
  (regression-locked by reusing the existing contract test's discovery assertions).
- INV-B2: no `service.resolve(...)` is issued after `stopAdvertising` returns.

## B2 — Native patch: vendored `bonsoir_darwin` (root fix; test-assisted + device-verified)

**Delivery mechanism (recommended):** vendor a patched copy of `bonsoir_darwin 5.1.3` under
`third_party/bonsoir_darwin/` and pin it via `dependency_overrides` in `pubspec.yaml`:
```
dependency_overrides:
  bonsoir_darwin:
    path: third_party/bonsoir_darwin
```
- Self-contained, reviewable, survives `pub upgrade`, and matches the project's existing
  "maintain a local patch" philosophy (cf. the graphify dart-extractor patch). A `PATCH.md` in that
  dir documents the two diffs + the upstream issue/PR link.
- **Alternative:** `dependency_overrides` → a git fork ref. **Avoid** a Podfile `post_install` sed
  patch (fragile, unreviewable, breaks on clean checkouts).
- **In parallel:** open an upstream PR to `bonsoir` so we can drop the override on a future release.
  First check whether a `bonsoir_darwin > 5.1.3` already fixes either vector; if so, prefer the bump
  (one-line change) and keep the override only for whatever remains unfixed.

### B2.1 — Broadcast: stop blocking the main thread (Vector 1)
- In `Broadcast/BonsoirServiceBroadcast.swift`, replace the synchronous `DNSServiceProcessResult(sdRef)`
  at line 35 with the **same async dispatch-source pattern the discovery side already uses**
  (`DNSServiceRefSockFD` → `DispatchSource.makeReadSource(..., queue: .global(qos: .utility))` →
  `setEventHandler { DNSServiceProcessResult(sdRef) }` → `activate()`), and cancel that source in
  `dispose()`. Net effect: `start()` returns immediately; the registration result is processed off the
  main thread → no scene-update watchdog.

### B2.2 — Resolve: eliminate the use-after-free (Vector 2)
- In `Discovery/BonsoirServiceDiscovery.swift`:
  - Cancel **all `pendingDispatchSources`** in `dispose()` (currently only `pendingResolution` sdRefs
    are deallocated; the read sources can still fire) before `browser.cancel()`/`super.dispose()`.
  - Make the callback context lifetime-safe: either `Unmanaged.passRetained(self)` balanced by a
    release in the terminal `stopResolution`, or guard the callback to bail if the action has been
    disposed (a disposed flag checked at the top of the dispatch-source handler and `resolveCallback`).
  - Ensure `stopResolution` also removes/cancels the matching `DispatchSourceRead`.

### B2.3 — Native verification (test-assisted)
- Add `RunnerTests` (`com.mknoon.app.RunnerTests`, already in the Xcode project) or vendored-package
  XCTest cases where feasible:
  - **Broadcast**: assert `start()` returns within a tight time bound on the calling thread (i.e. does
    not block) — e.g. dispatch `start()` on a thread and assert it returns < N ms even when the daemon
    is slow (use a stubbed/served fake where possible; otherwise an instrumented timing assertion).
  - **Resolve UAF**: a stress test that issues a resolve then immediately disposes the discovery, run
    under Address Sanitizer / Thread Sanitizer; assert no crash / no ASan report across many iterations.
- If XCTest harnessing the C-DNS-SD APIs proves impractical, downgrade B2.3 to **device repro** (B3)
  + code review, and say so explicitly (no silent skip).

## B3 — Integration / device repro (the integration-level "red test")

> **Sims cannot cover the native bonsoir crashes — see the dedicated `/sims` section below.** The
> move-feature reliability sims use a **fake discovery** and never instantiate `BonsoirDiscoveryService`,
> and iOS-simulator/loopback mDNS does not reproduce device AWDL/watchdog/UAF behavior. B2 (native) is
> **device-only** verification; B1 (Dart wrapper) is gated by the **host** contract test.

- **Repro-first** on the two physical iPhones (reporter's devices) BEFORE the patch, using
  `idevicesyslog` + `idevicecrashreport`, to capture the watchdog/UAF on build 104/106 and establish a
  baseline. (Vector 1 repro: keep advertising while the network is busy with a second iOS peer; Vector
  2 repro: rapid app foreground/background + Move start/stop to force found→resolve→dispose churn.)
- Add a **local-discovery stress scenario** to the device/reliability harness (the `sims` skill /
  `scripts/run_test_gates.sh reliability-sim`): rapid `startAdvertising`/`found`/`resolve`/`stopAdvertising`
  cycles across 2 sims to exercise the teardown-during-resolve path. This is the closest we get to a
  failing integration test; it locks B1.3/B1.4 end-to-end and serves as the acceptance gate for the
  native patch.
- **Post-patch acceptance:** run the same repro on the two iPhones; assert **no** new `Runner`
  crash/watchdog reports across N Move attempts (pull with `idevicecrashreport -k`).

### Part B invariants
- INV-B3: with the patch, `BonsoirServiceBroadcast.start()` never executes `DNSServiceProcessResult`
  on the main thread (code review + timing test).
- INV-B4: no resolve callback/dispatch source fires against a disposed `BonsoirServiceDiscovery`
  (ASan/TSan clean across the stress scenario).
- INV-B5: discovery functional parity — peers are still found/resolved/lost correctly on real
  hardware after the patch (the harness scenario + a manual two-device Move).

---

## Reliability-sim (`/sims`) coverage — division of labor

The repo's reliability sims (`./scripts/run_test_gates.sh reliability-sim move-feature`, run via the
`/sims` skill / `.claude/skills/sims/scripts/run_with_devices.sh move-feature`) drive the **full
old-phone + new-phone `AccountMigrationLocalTransferRuntime` pair over real loopback HTTP** with a
real `LocalWsServer` — but with a **fake discovery (`_SharedFakeDiscovery`)**. They exercise real
assembly + transfer and assert on `emitFlowEvent` payloads. They do **NOT** instantiate
`BonsoirDiscoveryService`. Consequences for this plan:

| Work | Right gate | Why |
|---|---|---|
| **Part A** telemetry | **Reliability-sim (move-feature) + host unit** | sims drive the real assemble+transfer pair and already assert assembly failure modes |
| **Part B1** Dart wrapper hardening | **Host contract test** (`bonsoir_discovery_service_contract_test.dart`) | bonsoir is faked even in a sim → host test is the deterministic, equivalent gate |
| **Part B2** native Swift patch | **Device-only** (the two iPhones) | sims use fake discovery; iOS-sim mDNS ≠ device AWDL → the watchdog/UAF are not sim-reproducible |

### A-SIM (move-feature scope) — REQUIRED for Part A
Existing move-feature scenarios already drive var/failing assembly and assert FlowEvents — extend them
in place, don't duplicate. Confirmed scenarios (`reliability-sim move-feature --list`):
- `account_migration_group_media_durability_simulator_test.dart` → *"missing critical group media
  blocks old-phone bundle assembly"* (a real `fileManifestBlockingIssues`/missing-media failure) and
  *"relay-hash group media survives feed refresh and remains bundleable"*.
- `account_migration_local_transfer_timeout_simulator_test.dart` → near-budget completes; over-budget
  fails typed `localTransferTimedOut` + `POST_FAILED` diagnostics.
- `account_migration_scale_benchmark_test.dart`, `migration_database_sqlcipher_capability_test.dart`.

Tasks:
- **A-SIM-1 (REQUIRED):** in the durability sim's *failing* case, inject
  `debugSetMigrationBreadcrumbSink` and assert the breadcrumb
  `MKNOON_MIG … ASSEMBLY_FAIL phase=buildFilePayload reason=fileManifestBlockingIssues` — proves the
  release breadcrumb names the real reason on the real assemble path.
- **A-SIM-2 (REQUIRED):** in a *succeeding* scenario, assert the ordered `ASSEMBLY_PHASE …` sequence +
  `ASSEMBLY_OK` over the loopback pair (locks A2/A3 end-to-end, beyond the unit test).
- **A-SIM-3 (recommended):** add a NEW move-feature scenario injecting `missingCriticalSecureValue`
  and `databaseSnapshotExportFailed` (the two buckets most likely behind the field failure), asserting
  the matching breadcrumb `reason`. This is also the concrete reproduction harness for OQ-2.

### B-SIM (move-feature scope) — OPTIONAL defense for B1
- **B-SIM-1 (optional):** a scenario that drives the real `BonsoirDiscoveryService` (+ fake bonsoir
  factory) through found → resolve → `stopAdvertising` churn, asserting single-flight + no-resolve-
  after-stop at the integration level. Marginal value over the host contract test (bonsoir still
  faked); include only if cheap. **It does not and cannot cover the native UAF/watchdog.**

### Sims gate hygiene (REQUIRED — project-specific)
- Any NEW sim file MUST get a `classify_path` rule in
  `scripts/check_reliability_simulation_discovery.sh` (move-feature allow-list ~lines 279-282) or
  `reliability-sim move-feature --list` fails the discovery gate with "candidate(s) unclassified".
- **Pre-existing red (NOT introduced by this work):** `reliability-sim move-feature --list` currently
  **FAILS** — `integration_test/sender_media_unavailable_fallback_proof_test.dart` is unclassified.
  Classify it (or narrow the discovery pattern) before/alongside landing, else the sims gate stays red
  independent of this plan.
- Run order: `reliability-sim move-feature --list` (no devices) → `/sims move-feature` (2-sim) as the
  Part A acceptance gate.

## Landing order

1. **A1 → A2** (breadcrumb primitive + per-phase host tests) — ship first; gives us telemetry for any
   future recurrence regardless of the rest.
1b. **Sims gate hygiene + A-SIM-1/A-SIM-2** — classify the pre-existing unclassified candidate so
   `reliability-sim move-feature --list` is green, then extend the move-feature sims with the
   breadcrumb assertions (and A-SIM-3 if reproducing OQ-2).
2. **B1.1 → B1.2 → B1.4 → B1.3** (Dart hardening, host contract tests) — deterministic, low risk;
   reduces Vector 2 exposure immediately even before the native patch.
3. **B3 baseline repro** on the two iPhones (capture the crash pre-patch).
4. **B2.1 + B2.2** (native patch via `third_party/bonsoir_darwin` override) + B2.3 verification.
5. **B3 post-patch acceptance** + **A3** (optional success/receiver breadcrumbs) + upstream PR.

## Open questions
- **OQ-1:** Does `bonsoir_darwin > 5.1.3` (or a `bonsoir` 5.2+) already fix either vector? If yes,
  prefer a version bump over the vendored patch for the fixed vector(s). (Resolve before B2.)
- **OQ-2:** Is the reporter's "Move worked after reinstall" reproducible-to-fail again on the iPhone
  11 once it returns to the prior state (phone locking mid-Move / long-lived process)? If we can
  reproduce the assembly failure with A2 breadcrumbs live, we get the real reason and may spawn a
  Part C (the actual assembly fix). **A2 is the enabler; this plan does not assume the assembly bug is
  fixed.**
- **OQ-3:** Should `kAccountMigrationTelemetry` ship `true` for all of beta and flip to `false` for
  GA, or be wired to a remote/debug flag? Default: `true` through beta, code-comment to flip for GA.
- **OQ-4:** Native XCTest feasibility for the C DNS-SD paths (B2.3) — confirm during B2 or downgrade to
  device-verify with an explicit note.

## Acceptance / gates
- Host: `flutter test test/features/account_migration/ test/core/local_discovery/` green;
  `flutter analyze` 0 new issues; full host suite unaffected.
- **Sims (Part A gate):** `./scripts/run_test_gates.sh reliability-sim move-feature --list` passes the
  discovery gate (incl. the pre-existing unclassified fix + any new sim classified), then
  `/sims move-feature` (2-sim) green with A-SIM-1/A-SIM-2 (and A-SIM-3 if added) asserting the
  breadcrumb sequence/reason on the real assemble+transfer pair.
- Native: builds clean with the `bonsoir_darwin` override; (XCTest green if B2.3 lands); ASan/TSan
  clean on the native stress scenario if run.
- Device (Part B gate — the only real bonsoir-crash gate): on the two iPhones, N consecutive Moves and
  N discovery stress cycles produce **no** new `Runner` crash/watchdog reports
  (`idevicecrashreport -k` before/after); a deliberately-failed Move prints the
  `MKNOON_MIG … ASSEMBLY_FAIL phase=… reason=…` breadcrumb.

## Rollback
- Part A: set `kAccountMigrationTelemetry = false` (or revert the 2 files) — zero behavior risk.
- Part B Dart: revert `bonsoir_discovery_service.dart` (behavior-preserving changes only).
- Part B native: remove the `dependency_overrides` entry → falls back to pub `bonsoir_darwin 5.1.3`.

## Out of scope
- The actual account-bundle assembly root-cause fix (gated on OQ-2 / A2 telemetry capturing a live
  failure) — a separate Part C / plan if/when reproduced.
- Android (`bonsoir_android`) — the two vectors are iOS/`bonsoir_darwin`-specific.
- Replacing bonsoir with a custom `NWListener`/`NetService` advertiser (larger effort; only if the
  upstream/patch route proves unsustainable).
