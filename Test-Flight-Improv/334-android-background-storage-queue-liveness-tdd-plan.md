# 334 - Android Background Storage Queue Liveness

Status: closed / plan-green / Android device-verified (2026-08-04); Pixel causal RED retained; current-source Pixel/emulator queue and handoff proof green; focused 335/335; bounded-notification adversarial 41/41; groups 4016/4016 plus four Go tails; core 3100/3100; feature 8777 pass/1 declared skip; completeness 1414/1414; full analyzer and diff hygiene clean; Graphify current at `dc4beab216d8c42b`; exact historical lock ownership remains unknowable
Type: Bug
Spec: free-text incident report supplied 2026-08-03
Classification: evidence-gated
Closure tier: host + native Android + real two-engine SQLCipher device
Baseline: `1c7540b17954a423264e23ecf3528d3c01beeb0a`

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-03 22:10 CEST | Evidence Collector | incident timeline; `background_message_handler.dart`; `encrypted_db_opener.dart`; sqflite_common 2.5.6; sqflite_sqlcipher 3.4.0 Android source; FlutterFire Messaging 15.2.10 Android source | Relay and FCM delivery were prompt; the delayed work is inside the Pixel app. Source permits a same-process SQLCipher queue inversion, but the rolled incident log does not retain the original lock owner. | Build a deterministic real-Android reproduction before production edits. |
| 2026-08-03 22:25 CEST | Evidence Collector | `group_message_listener.dart`; group notification outbox helper; notification tone/id registries; pending overlay; current H0 probe | A global listener `asyncMap` explains second-image head-of-line delay but not the first stall. Two synchronous blocking `flock` calls are independent callback-liveness hazards. Existing H0 does not hold `BEGIN EXCLUSIVE` around a background read. | Include exact queue-inversion and held-flock REDs. |
| 2026-08-03 22:35 CEST | Planner | Plan 331/331A artifacts; gate scripts; live device discovery | Reuse the disposable no-Activity H0 fixture. Run independently on Pixel `21071FDF600CSC` API36 and emulator `emulator-5554` API37; no peer, relay, FCM credential, or user tap is needed. | Save and index this evidence-gated plan, then run `$tdd-review`. |
| 2026-08-03 23:20 CEST | Reviewer | full Plan 334; current H0 runner/receiver; sqflite/sqflite_sqlcipher lifecycle; handler second-read/direct-post-show paths; Android/iOS lock callers | `$tdd-review` verdict `plan-fixes-required`. Core mechanism remains credible, but v1 overclaimed a real FlutterFire-service fixture, left native ownership/FAIL-artifact semantics unsafe, omitted repeated/direct reads and cumulative budget, and would have changed iOS lock behavior. | Apply verified v2 deltas, rerun all lenses, then execute the causal RED. |
| 2026-08-03 23:35 CEST | Arbiter | reviewer findings plus current plugin/H0 sequencing | Replace the broad per-connection fork with the smallest incident-causal boundary: every Flutter plugin instance owns one FIFO and all of its maps/locks/handles. Keep actual FlutterFire HOL proof in a serial host contract; use the device fixture only for real two-engine SQLCipher inversion. | Vendor pristine 3.4.0 for the RED, preserve evidence on expected failure, then patch only after reproduction. |
| 2026-08-04 01:35 CEST | Implementation audit | current notification ownership protocol; registry/native boundary; crash residues; Android/non-Android ordering | The first GREEN closed the original reclaim races but still released owners after an ambiguous platform error and allowed an aged audible crash residue to sound again. The plan is updated to a one-way Android `pending -> publishing -> committed/unknown-terminal` protocol and repair-time silent tone window. | Rerun focused tests, native/device proof, affected gates, and closure audit. |
| 2026-08-04 | Final implementation/device audit | current notification protocol; focused/adversarial tests; native contracts; Pixel/emulator queue and handoff artifacts; compatibility; curated/family gates; analyzer/diff; Graphify | Focused 335/335, adversarial 41/41, both native contracts, current-source queue/handoff device proof, completeness 1414/1414, ST-008, Pixel raw-key 8/8, rollback/restoration, serialized groups 4016/4016 plus four Go tails, core 3100/3100, feature 8777 pass/1 declared skip, full analysis, diff hygiene, and Graphify fingerprint `dc4beab216d8c42b` are green. | Closed / plan-green. Preserve the historical causal RED and the explicit unresolved historical-owner limit. |

## Problem And Evidence

- Behavior to improve: two group-image pushes reached the Pixel promptly, but
  the background callback and foreground canonical runtime could not complete
  private-storage work for about six and a half minutes. The chat stayed empty,
  neither notification arrived on time, and both images plus one sound appeared
  only when storage work finally resumed.
- Impact: an app-local liveness failure makes successfully delivered messages
  appear missing and serializes later pushes behind the first stalled callback.
  No message was lost because relay custody remained intact, but notification
  latency and chat truth were unacceptable.
- Confirmed incident boundary: the server stored both image envelopes and sent
  both pushes immediately; Pixel app-side broadcast/service dispatch occurred about
  1.2--1.3 seconds after each send. Canonical inbox/media processing occurred
  roughly 386.6 and 375.2 seconds later. Server Go 1.22.2 versus relay build Go
  1.25.0 is refuted as causal because all server-side storage and push work
  completed successfully.
- Confirmed root-cause mechanism, unresolved incident attribution:
  sqflite_sqlcipher 3.4.0 keeps a process-static Android `HandlerThread` and
  `Handler`, and posts open/query/execute work for all Flutter engines to that
  one FIFO. Engine A can complete `BEGIN EXCLUSIVE`, engine B can then block the
  FIFO in a read-only open/query, and A's next transaction statement/`COMMIT`
  can queue behind B. This is a self-sustaining queue inversion. The source
  permits it; the original rolled log cannot prove which exact operation owned
  the incident lock.
- Pre-fix app trigger: `firebaseMessagingBackgroundHandler` at
  `lib/features/push/application/background_message_handler.dart:415` awaits
  encrypted eligibility at `:471-472` before direct-envelope staging at `:489`.
  Group eligibility reaches `_resolveGroupMessageLocalStateFromEncryptedDb`
  through `:1323-1330`; the preview repeats that DB read at `:1427-1432`.
  Post-show group validation is also awaited at `:801-805` before the recent
  shown marker at `:888-899`.
- Pre-fix DB trigger: `openEncryptedDatabaseReadOnlyTolerant` at
  `lib/core/database/encrypted_db_opener.dart:55-79` is a non-singleton
  read-only open with neither `onConfigure` busy timeout nor an absolute
  completion bound. The canonical writer configures `busy_timeout=5000` at
  `:345-358`, which does not free a shared native FIFO blocked by another
  engine.
- Pre-fix independent callback hazards: `_PosixFlock.withExclusive` at
  `lib/core/notifications/durable_notification_tone_lease.dart:1025-1055` and
  `_NotificationIdFlock.withExclusive` at
  `lib/core/notifications/durable_conversation_notification_id_registry.dart:744-769`
  synchronously call `flock(fd, LOCK_EX)`. A Dart timeout cannot run while that
  FFI call blocks. The ID registry also holds the lock across active-card and
  show/cancel plugin awaits at `:150-193` and `:256-282`.
- Overlay clarification: `pending_conversation_notification_overlay.dart:443-452`
  uses Dart `FileLock.exclusive`, which the installed Dart SDK documents as
  nonblocking rather than `blockingExclusive`; it is therefore not the same
  timer-stopping hang. However, POSIX record locks are process-scoped and do not
  correctly serialize independent isolates in one process, so the overlay must
  reuse the bounded BSD-flock primitive or leave the background critical path.
- Head-of-line amplification: FlutterFire Messaging 15.2.10 awaits the Dart
  callback on an unbounded `CountDownLatch`, while its `JobIntentService` uses a
  single-thread executor. `GroupMessageListener.start` independently uses
  global `.asyncMap(_handleLiveMessage)` at
  `lib/features/groups/application/group_message_listener.dart:1566-1584`.
  The former blocks later push callbacks; the latter makes image two wait behind
  image one after delivery. Per-group listener lanes would not fix this same-
  group incident and are not part of the causal repair.
- Existing coverage: Plan 331A's H0 proves one writable owner and a concurrent
  read-only FlutterFire peer on both available Android targets. It does not
  bracket the peer read between `BEGIN EXCLUSIVE` and the writer continuation.
  `ST-008 queued listener events persist after DB write contention releases`
  proves eventual same-group persistence only after a fake lock releases.
  Existing background-handler tests cover thrown post-show errors and sequential
  bursts, not never-completing phases or a real serialized callback queue.
- Planning-time coverage gap: exact two-engine native FIFO inversion, engine-worker
  teardown, no-late-effect phase deadlines, bounded cross-isolate file-lock
  failure, serialized second-push progress, and a post-recovery SQLCipher
  sentinel proving that no native operation remains wedged.
- Refuted findings: group-message push staging already protects the incident is
  false; `_stagedPushEnvelopeFromRemoteMessage` intentionally accepts direct
  `new_message`/`message_reaction` only. A Dart `Future.timeout` around the old
  whole handler is sufficient is false because native work is not cancelled and
  can resume side effects later. A read-only `PRAGMA busy_timeout` alone is
  sufficient is false because open can block before configuration and the
  process-static FIFO remains occupied. Per-group listener concurrency fixes
  this incident is false because both images belong to the same group.
- Unresolved historical finding: the exact production transaction that first
  held the lock is not recoverable from the rolled 256 KiB incident log. TC-
  334-01 subsequently reproduced the source-permitted inversion on the incident
  Pixel, authorizing the scheduler fork without claiming the missing historical
  owner as fact.
- Affected production, test, and gate files: a vendored
  `third_party/sqflite_sqlcipher` Android implementation plus `PATCH.md` and
  root dependency override; `encrypted_db_opener.dart`;
  `background_message_handler.dart`; one shared bounded BSD-flock helper and
  the tone/id/overlay callers; H0 Dart/Kotlin/source-test/script extensions;
  new focused Dart/native tests; `scripts/run_test_gates.sh` registration; and
  `analysis_options.yaml`, whose only new exclusion is the vendored upstream
  `third_party/sqflite_sqlcipher/example/**` package.

Quantitative liveness contract after review:

- One monotonic Android background-storage budget is 8 seconds from first
  staging attempt through the last storage-dependent bookkeeping step.
- A single read-only/idempotent storage phase receives at most 2 seconds and
  never more than the aggregate remainder.
- Android BSD-flock acquisition receives at most 1 second. The action after
  acquisition is not released by a Dart timeout; owner serialization remains
  intact until the real action settles.
- The causal device RED watchdog is 4 seconds and the mode-specific debug
  broadcast must write a terminal artifact and finish within 8 seconds, below
  the foreground-broadcast boundary. These are product constants, not host
  sleeps; host tests inject a fake monotonic clock.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `55638de8c282435f`; stale only at
  `ios/Flutter/flutter_export_environment.sh`, which is outside this Android
  plan.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Android FlutterFire background_message_handler SQLCipher process static HandlerThread BEGIN EXCLUSIVE group notification display custody unbounded callback head-of-line reproduction" --profile tdd --budget 700`.
- Anchors: `exclusive` ->
  `lib/core/media/media_attachment_lifecycle_lock.dart:206`; `begin` ->
  `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart:2370`.
- Surfaced proof/gate files: media lifecycle and repository tests only; no
  load-bearing background-handler or plugin seam was surfaced.
- Graph gaps requiring source search: FlutterFire background service, the
  cached sqflite_sqlcipher Android plugin, background read-only DB resolver,
  notification flock implementations, and H0 device harness. These were
  verified directly from current source and pinned package sources.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.
- Final closure refresh/query (2026-08-04):
  `./graphify-arch/refresh_arch_graph.sh --incremental` refreshed 16 changed
  code files and wrote 66,922 nodes / 99,995 edges. The required broad review
  query was refined once with the exact
  `background_message_handler.dart`, `durable_notification_tone_lease.dart`,
  and `encrypted_db_opener.dart` anchors; it returned
  `confidence=anchored`, `freshness=current`, fingerprint
  `dc4beab216d8c42b`, and surfaced the expected notification service/show path.

## Scope Contract And Guard

In scope:

- Reproduce the queue inversion in the disposable same-process two-Flutter-
  engine H0 app using real SQLCipher and real `BEGIN EXCLUSIVE`. Pre-open the
  read-only peer, acknowledge writer `BEGIN`, submit the peer query first, and
  use ordered method-channel messages to release the writer continuation only
  after the query platform message has been posted. This fixture proves the
  native queue inversion; it does not claim to run FlutterFire's service.
- Prove FlutterFire-style head-of-line release separately with a one-at-a-time
  host driver and a source/version sentinel for the pinned unbounded latch and
  single-thread executor. Registering `FlutterFirebaseMessagingPlugin` on a
  manually created H0 engine is not service-queue evidence.
- Vendor exactly sqflite_sqlcipher 3.4.0 and replace its process-static Android
  mutable state with plugin-instance-owned state: one FIFO worker, database-id
  map, singleton/opening-path registry, locks, options, and handles per Flutter
  engine. Preserve FIFO ordering within an engine while allowing the foreground
  owner engine to commit independently of the background read engine.
- Give the plugin an explicit engine lifecycle: `OPENING/OPEN/CLOSING` path
  state, coalesced within-engine singleton opens, close/reopen ordering,
  off-main-thread delete, detached-result suppression, close of only that
  engine's handles, and bounded worker termination acknowledgement. No engine
  may close or quit another engine's worker.
- Configure a short read-only SQLite busy timeout after keying and give
  background encrypted-open/query phases an absolute cooperative deadline with
  late-open close cleanup. A timeout wrapper must never be the only native
  liveness mechanism.
- Move existing direct encrypted-envelope staging ahead of encrypted
  eligibility. For group pushes, preserve relay inbox custody and return a
  redacted `storage_deferred` outcome when local authorization cannot be read;
  do not pretend the direct-envelope stager supports group payloads.
- Add one 8-second absolute storage deadline with 2-second phase caps for
  cancellable read-only or idempotent phases: direct staging, eligibility,
  repeated preview/local-state resolution, pending-overlay enrichment,
  group/direct post-show validation, and recent-gate bookkeeping. Custody,
  eligibility, or canonical-state expiry before ownership is fail-closed with
  no claim/show. Overlay enrichment is fail-open only after its bounded wait and
  runs before claims; its late completion cannot publish. Post-show expiry keeps
  the exact generation and acknowledged owners, records `shown_state_unknown`,
  and returns without later retirement. These bounds are not an end-to-end
  callback SLA and do not bound native show or an already-acquired mutating
  action.
- For managed Android notifications, stable-ID resolution and replacement
  preparation -- metadata preparation, prior-card retirement, and metadata
  activation -- finish before exact event ownership enters `publishing`.
  Pending owners may be CAS-released only while no owner has crossed into
  `publishing`. Immediately before platform show, the event enters durable
  `publishing`, followed by the audible tone owner when tone storage is
  available. If tone storage fails after event publication starts but before
  native entry, the event is not unwound: exactly one silent native show runs
  under that event owner. Once an owner has entered `publishing`, later failure
  is fail-closed. A thrown, lost, or indefinitely pending method-channel result
  after native entry is `publication_outcome_unknown`, not proof that Android
  rejected the card; neither owner may be released and post-show validators do
  not start.
- A fresh event `publishing` record is non-reclaimable and reports `pending`.
  On the first coordination pass at or after 60 seconds from `publishingAtMs`,
  it attempts an atomic replacement with tokenless `committedOrUnavailable`
  and `publicationOutcome=unknown`; replacement failure preserves the original
  `publishing` record and still returns unavailable. Tone `publishing`,
  `committed`, or malformed post-show residue is never reclaimed audibly. A
  successful repair atomically anchors a 30-second silent window at the maximum
  of observation time, an existing valid numeric lease, and the relevant
  post-show timestamp, then removes the sidecar; failed replacement/repair
  remains silent and retains the sidecar for a later attempt. Ordinary
  commit/post-show work
  begins only when the native callback returns successfully; callback
  completion is not claimed as proof that a card became visible.
- Do not apply a timeout wrapper to claim, tone, notification-ID replacement,
  native show/cancel, commit, or release actions. Android contender acquisition
  is bounded, and exact-event finalization after durable `publishing` may make a
  bounded lock attempt: failure returns `claimCommitted=false` and leaves a
  terminalizable fail-closed residue. A tone/registry owner already holding its
  lock remains serialized through its real mutating/native action.
- Extract a bounded nonblocking BSD-flock acquisition primitive and use it on
  Android for event claims, notification tone, notification-ID, and pending-
  overlay cross-isolate coordination. Failure is typed storage-unavailable; no
  contender enters its action after the 1-second bound. Preserve today's iOS/
  macOS blocking BSD-flock and record-lock semantics byte-for-behavior.
- Persist only rare terminal storage-timeout breadcrumbs in a bounded Android
  app-private journal: one complete atomic slot file per retained event, no
  shared journal lock, at most 32 fixed targets, and an allowlist of message
  kind, phase, terminal outcome,
  elapsed bucket, build mode, and engine role. Do not persist message content,
  group/peer/event identifiers, DB path, filenames supplied by payload, or key
  material. Journal failure is best effort and cannot delay the callback beyond
  200 ms; the underlying write may finish late but cannot trigger notification
  effects. The journal is diagnostic rather than an audit log: lock-free
  overlapping or very-late writers may replace a newer fixed slot, while every
  surviving slot must remain complete, parseable, and within the hard cap.

Must preserve:

- Relay remains authoritative custody for group pushes and foreground resume
  remains the canonical recovery path -> existing group inbox/drain and Plan
  331 recovery sentinels.
- Direct encrypted staging remains best effort and staging errors never suppress
  an otherwise eligible notification ->
  `background_message_handler_staging_test.dart`.
- Mute/archive/membership/account/role/key-epoch checks remain fail closed;
  storage timeout must not become a permissive notification path -> existing
  background display-policy tests plus TC-334-04.
- Android registry preparation precedes the one-way native publication
  boundary; an ambiguous native result retains `publishing` owners, while a
  callback success attempts commit before post-show validation -> TC-334-06/10/
  15.
- Same-connection SQL order, raw-key/legacy-passphrase compatibility, canonical
  writer `busy_timeout=5000`, one writable lease owner, and explicit close
  before engine destruction -> TC-334-01/02/08/12.
- Foreground and background plugin instances do not share database IDs/maps or
  singleton handles; within one engine singleton opens remain coalesced and
  same-engine FIFO behavior stays ordered -> TC-334-02.
- Same-group message ordering and eventual media recovery -> existing ST-008
  preservation sentinel; no listener concurrency rewrite.

Hard `Do not`:

- Do not change relay/server code, Go toolchains, message wire formats, DB
  schema/version, group listener ordering, iOS notification behavior, or Plan
  331's `activateRecoveryWork=false` safety gate.
- Do not fork FlutterFire merely to add a native latch timeout; that can overlap
  an uncancelled old Dart callback with the next callback.
- Do not implement one outer `Future.timeout` around the old handler, leave a
  timed-out database handle unclosed, change SQLCipher workers without the real
  causal RED, or serialize all app database access behind a new broad mutex.
- Do not release an event/tone owner after it enters Android `publishing`, even
  when failure occurs before native show (including event-published tone
  fallback). Later contenders fail closed or lazily terminalize/repair the
  unknown residue. Do not timeout-release a notification-ID owner or a mutating
  action after its lock was acquired.

Deferred / accepted difference:

- Cross-group listener isolation is deferred to a separate performance plan;
  it cannot repair two messages in the same group and widens ordering risk.
- Full operation-owner histories are deferred; the bounded terminal journal and
  native H0 worker-state artifact identify the timed-out phase/engine class but
  do not retroactively name the historical incident's foreground transaction.
- A locally persisted per-group push receipt is not added while Plan 331's
  production recovery worker remains safety-gated. Relay inbox custody plus
  existing foreground drain own message recovery; storage-timeout notification
  display is an explicitly fail-closed degraded outcome.

Dependencies:

- Builds on Plan 331A's proven single writable owner and read-only FlutterFire
  peer. It does not activate or complete Plan 331 headless recovery.
- Root package resolution must point to the vendored 3.4.0 fork and lockfile
  identity must prove that no cached upstream Android implementation ships.
- Vendor provenance pins hosted archive SHA-256
  `ba7733c5514cf0ccb0331997b771a890f73678bcd84cdfb5f7487a88a71f1738`.
  `PATCH.md` records this immutable input, an allowlisted Android/JUnit diff,
  and hashes of untouched Dart/iOS/macOS assets. Package config and Flutter
  plugin metadata must resolve the path fork before RED or GREEN proof.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-334-01 | The exact two-engine native queue inversion is reproduced before the scheduler edit | `scripts/run_android_canonical_runtime_h0_probe.sh <id> --sqlcipher-queue-inversion --expect-red` | device / disposable debug app, same PID, two manually created Flutter engines, real SQLCipher, no Activity | pristine vendored 3.4.0: reader is pre-opened; trace reaches `writer.begin_exclusive`, `reader.query_posted`, `writer.resume_requested`, then the 4 s watchdog with neither reader result nor writer commit; GREEN commits writer then completes reader | restore a process-static worker -> exact prefix and watchdog RED | Pixel before edit; Pixel+emulator after; outside Dart gate |
| TC-334-02 | Every Flutter engine owns one SQLCipher FIFO and all mutable plugin state; same-engine order/singleton behavior survives detach/close/reopen and distinct-path delete | vendored Java `EngineWorkerIsolationTest` (`differentPluginInstancesOwnDistinctWorkersAndMaps`, `sameEngineOperationsRemainFifo`, `concurrentSingletonOpensCoalesceWhileOpening`, `detachClosesOnlyOwnedHandlesAndSuppressesLateResults`, `closeThenImmediateReopenKeepsNewOpen`, `deleteADoesNotStopEngineB`) | Android JVM / pure worker/state fakes plus JUnit 4.13.2; delete test uses different paths | static state and absent lifecycle seams RED -> deterministic engine ownership and termination acknowledgements; no app-owned production delete caller exists | make worker/map static or deliver a detached result -> RED | `./android/gradlew -p android :sqflite_sqlcipher:testDebugUnitTest --tests '*EngineWorkerIsolationTest'`; cross-engine same-path delete requires exclusive external ownership and is not claimed |
| TC-334-03 | Read-only SQLCipher uses the same absolute deadline across raw/fallback attempts, sets `busy_timeout=1000`, and closes a late handle exactly once | `test/core/database/encrypted_db_read_only_liveness_test.dart` (`raw timeout never starts legacy fallback`, `quick raw rejection gives legacy only remaining budget`, `late open closes once`) | core host / injected opener+clock; Pixel raw/legacy proof | no bound/config/late close and catch-all fallback -> typed timeout, no overlapping fallback, exact remaining budget and close | catch timeout as wrong-key or delete late close -> RED | direct core test; AUTO core-host-all; Pixel exact device proof |
| TC-334-04 | Direct staging starts before eligibility; held eligibility returns fail-closed with no notification effects; group timeout records relay-deferred and never claims local staging | `test/features/push/application/background_storage_deadline_test.dart` (`direct staging precedes held eligibility with no late notification effects`, `group eligibility timeout is relay-deferred without false stage`) | host / fake monotonic clock, completers, exact effect ledger | HEAD blocks before staging -> direct stage first, terminal by 2 s phase/8 s aggregate, zero show/claim/tone/id/overlay/gate after resolver release | restore staging order or whole-body timeout -> RED | direct file; add to `GROUP_TESTS`; AUTO feature-host-all |
| TC-334-05 | Eligibility success cannot hide a second encrypted preview/local-state stall | `background_storage_deadline_test.dart::second local-state read is bounded and cannot show late` | host / first resolver succeeds, second resolver held, distinct event ledger | HEAD wedges at repeated read -> terminal timeout, callback two starts, zero late first-event effects after release | cap only eligibility -> RED | same focused command and registration |
| TC-334-06 | After the native callback completes, group/direct post-show storage stalls keep the exact generation and non-releasable owners, record `shown_state_unknown`, and never retire late; publication-unknown paths never enter validators | `background_storage_deadline_test.dart` (`group post-show stall keeps committed generation`, `direct post-show stall keeps committed generation`) plus ambiguous-error handler tests | host / acknowledged native callback, held validators, exact effect ledger | HEAD group/direct awaits never return -> exact keep/unknown, no release/cancel after late completion; ambiguous native error stops before validators | bound only group, release owner on expiry, or validate after ambiguous callback -> RED | same focused command and registration |
| TC-334-07 | One absolute 8 s budget, not a fresh timeout per await, lets a serialized second event start; exact event identity prevents a wrong callback from satisfying the proof | `background_storage_deadline_test.dart::cumulative storage phases consume one budget and second event progresses`; `test/core/bootstrap/flutterfire_background_queue_contract_test.dart` | host / fake monotonic multi-phase consumption and one-at-a-time driver; pinned FlutterFire source/version sentinel | phase-local-only implementation exceeds aggregate/second never starts -> later phase gets remainder, first terminates, exact second event displays | reset deadline at each phase or use first event ID -> RED | push file in groups; source sentinel direct/shared exact command |
| TC-334-08 | GREEN is not a Dart-timeout illusion: a fresh real write/read/close succeeds, native census reaches zero handles/queued/running operations, and each destroyed engine acknowledges worker termination | queue-inversion artifact final sentinel plus plugin debug census; native `EngineWorkerIsolationTest` owns literal path-state transitions | device / real SQLCipher and retained plugin-instance diagnostics | static worker remains wedged or Dart close hides native residue -> ordered open/close/destroy phases, zero handles, and terminated destroyed-engine workers; literal `OPENING/OPEN/CLOSING` is native-unit evidence rather than an overclaim about artifact labels | suppress close error or report zero on map removal -> RED | Pixel + emulator queue scripts |
| TC-334-09 | Android contender acquisition is finite; after durable event `publishing`, callback-success finalization is also bounded and leaves a terminalizable residue if the event lock is unavailable; a tone owner remains serialized through audible show+commit | `test/core/notifications/bounded_posix_flock_test.dart` (`event claim contender times out`, `tone contender times out`, `shown tone owner waits for the real lock owner`, `successful native event show has bounded fail-closed finalization`, `aged Android publishing event residue is terminal fail-closed`) plus exact claim regressions | core host / literal held flocks, owner handshake, 1 s acquisition, fake clock past publication TTL | contenders enter no action; event finalization returns `claimCommitted=false` instead of retaining the callback and later terminalizes; tone ownership stays exact through show/commit | make contender blocking, make event finalization unbounded, or reclaim publishing token -> RED | direct core tests; AUTO core-host-all |
| TC-334-10 | Android stable-ID resolution/metadata preparation/prior retirement/activation precede `event_publishing -> tone_publishing -> native_show`; an ID contender times out with no effect, while an acquired registry owner remains serialized through native callback completion | `bounded_posix_flock_test.dart` (`notification-id contender fails closed with no prepared or plugin effect`, `acquired notification-id owner is not timeout-released and newer generation survives`); `durable_conversation_notification_id_registry_test.dart::replacement proves metadata storage before retiring or showing a card`; `flutter_notification_service_test.dart::Android native boundary runs after registry retirement and directly wraps show`; `background_storage_deadline_test.dart::registry retirement remains pre-publication and stale claim is reclaimable` | core/feature host / held real flock plus composed registry-preflight, native-boundary, and handler-state ledgers | registry failure produces no publishing owner/show; metadata storage precedes retirement; the exact boundary is invoked after cancel and directly around show; stale pre-publication claims remain reclaimable; newer generations survive | enter publishing/show before registry prep, timeout-release acquired ID owner, retire before metadata storage, or prepare before acquire -> RED | direct focused tests; AUTO core/feature families |
| TC-334-11 | Android overlay uses bounded BSD flock; iOS/macOS keeps current record-lock behavior | `bounded_posix_flock_test.dart::android overlay contender is bounded and owner state survives`; source sentinel for platform branch | core host / injected platform, two isolates and fake secure store | current Android process-scoped record lock overlaps -> one owner and later valid state; non-Android branch unchanged | use record lock on Android or bounded BSD flock on iOS -> RED | direct core test; AUTO core-host-all |
| TC-334-12 | Vendored resolution/provenance and rollback are exact; untouched Dart/iOS/macOS assets hash-match hosted 3.4.0; both key modes survive fork and hosted rollback | `test/core/database/sqflite_sqlcipher_fork_contract_test.dart`; existing SC-B | host hash/package-config/plugin-metadata sentinel + Pixel real SQLCipher | cached upstream selected or unpinned fork -> exact archive/diff hashes and path resolution; rollback drill reselects hosted digest and reopens/writes/reads, then restores fork | remove override, alter untouched file, or omit restore -> RED | direct host test; Pixel SC-B; rollback drill before final closure |
| TC-334-13 | Existing H0 ownership, direct staging failure isolation, policy, post-show generation safety, same-group ordering, and iOS/macOS lock, parser, timestamp, and in-place-write behavior remain unchanged | existing H0 scripts; staging/handler/tone/id/overlay tests; parameterized iOS/macOS legacy reclaim-byte, historical committed-repair, and blocking/inode sentinels in `bounded_posix_flock_test.dart`; `ST-008 queued listener events persist after DB write contention releases` | host + Pixel/emulator preservation | existing GREEN -> remains GREEN; Android strict-shape/atomic-replacement semantics remain platform-gated while Apple keeps legacy bytes, historical repair timestamps, and in-place writes | route Android parser/rename semantics through Apple or alter same-group ordering -> RED | exact focused tests, H0 scripts, `groups`, core/feature families |
| TC-334-14 | Rare timeout journal is atomic, bounded to 32, release-enabled, redacted, and cannot add more than 200 ms to callback completion | `test/features/push/application/background_storage_liveness_journal_test.dart`; handler effect-ledger assertion; H0 artifact schema test | host / temp directory, fake clock/random, stalled writer | debug-only rolled log -> 32 fixed complete atomic slots, per-operation unique same-directory temps, exact allowlist, stale-temp cleanup, and bounded prune; failed journal-slot publication preserves the previous valid slot and journal failure still returns | persist forbidden identifier, share one locked file, replace a valid slot before publication, or await beyond 200 ms -> RED | direct push test + `GROUP_TESTS`; Kotlin source test |
| TC-334-15 | Android publication is one-way after event `publishing`: pre-native tone-storage failure produces one silent show without unwinding the event; plugin error and same in-memory owner replay never repeat or release an ambiguous native attempt; event unknown terminalizes atomically at 60 s; only exact pending shapes may publish; tone publishing/committed/malformed residue repairs atomically into a max-preserving 30 s silent window | `bounded_posix_flock_test.dart` (`pre-native tone storage failure falls back silent without poisoning event`, same event/tone owner replay sentinels, pending-event post-show-field rejection, `invalid Android tone state shapes repair silently`, failed atomic pending-to-publishing transition, `aged Android publishing event residue is terminal fail-closed`, failed atomic event/tone commit, malformed/unknown/post-show tone residue, observation/future timestamp maxima, failed atomic numeric repair); `show_notification_use_case_test.dart::reaction native-attempt error preserves fail-closed exact ownership`; `background_message_handler_test.dart::native-attempt error keeps exact event fail-closed on redelivery` | core/feature host / tone failure after event publishing but before native entry; callback throw after entry and same-owner retry; fake clock event +59,999 ms/+1 ms and tone +61 s/+29 s/+1 s; injected failed atomic replacements, malformed/invalid JSON shapes, future timestamps, repair failure, and exact sidecar assertions | pre-fix replayed native callbacks, accepted impossible shapes, overwrote in place, deleted residue, shortened future leases, or granted audio -> one native attempt; publishing records remain non-releasable; successful event terminalization removes the token while failed replacement preserves publishing/unavailable; all tone repair paths remain silent and successful repair preserves the greatest trustworthy timestamp | release/replay after publishing, accept a pending record with post-show fields, suppress the silent fallback, make Android state/numeric replacement in-place, propagate event repair failure, delete malformed/failed-repair tone state, shorten a future lease, or allow audio at +29 s/after failed repair -> RED | direct focused tests; AUTO core/feature families |

### Test Notes

- TC-334-01 pre-opens the read-only peer before `BEGIN EXCLUSIVE`. After writer
  BEGIN succeeds, the reader creates its `rawQuery` future, then sends a second
  method-channel message. Platform-message order means the SQLCipher query has
  been posted before native receives `reader.query_posted`; only that callback
  releases the writer continuation. A delay or generic simultaneous open is
  not an acceptable ordering barrier.
- The retained causal RED artifact
  `queue-inversion-b197a89d074548c7ad04d9410246172e.json` predates the expanded
  GREEN schema. It is grandfathered only as the immutable causal prefix/
  watchdog/no-COMMIT proof; every current-source GREEN artifact must satisfy the
  expanded fields below.
- TC-334-01/08 GREEN artifact must include current source digest, APK digest,
  device serial/API, PID, exact ordered phase list, elapsed milliseconds,
  worker/handle high-water marks, Activity/ApplicationRoot counts, cleanup
  outcome, journal mode, run nonce, terminal cleanup, and ordered
  open/close/destroy lifecycle transitions. The runner must pull/finalize PASS
  or expected FAIL before semantic validation, process kill, or uninstall. A
  watchdog without durable FAIL is harness failure, not causal RED evidence.
- TC-334-04/05 releases the originally stalled resolver after the handler returns
  and advances fake time. Any show, claim, tone, overlay, registry, or gate
  mutation after release fails the test.
- TC-334-09/10/11 use two independently opened descriptors and a literal held
  lock, not an injected fake `Future`. Owner handshake precedes contender; the
  owner self-releases after the 1-second acquisition budget, and an outer
  watchdog cleans both isolates so the RED cannot hang the test runner.
- TC-334-15 exact-event publishing JSON carries `state`, `token`,
  `createdAtMs`, and `publishingAtMs`; successful atomic terminalization writes
  a tombstone with only `state=committed`, `committedAtMs`, and
  `publicationOutcome=unknown`. Failed atomic replacement leaves the original
  publishing JSON intact and reports unavailable. Tone publishing carries
  token/reservation/creation/publication timestamps. Publishing, committed, or
  malformed or invalid-shape residue is always observed silently: successful
  atomic repair writes the numeric lease at the maximum of observation time,
  the existing valid numeric lease, and the relevant post-show timestamp before
  removing the sidecar; failed replacement or lease repair retains the sidecar
  for a later silent attempt. The same in-memory owner cannot re-enter native
  publication after an ambiguous first attempt.
- TC-334-07 advances several individually successful phases across the same
  fake monotonic clock. A fresh 2-second budget per phase is explicitly RED.
- Production callback constants recorded and source-attested by H0/device proof
  are 8 s aggregate / 2 s phase / 1 s Android acquisition / 200 ms journal.
  Host fake-clock publication tests separately prove the exact 60-second event
  terminalization boundary and repair-time 30-second tone window; H0 neither
  exercises nor records those 60/30-second recovery intervals.
- Current-source queue GREEN artifacts are
  `build/h0-probe/21071FDF600CSC/queue-inversion-9e6e6771a00041f6a89bd2a8ac19f9e9.json`
  and
  `build/h0-probe/emulator-5554/queue-inversion-f5077200df9c431e831c4344a353f994.json`;
  both attest source digest
  `23435fd8bffcfbe96e185fb32926ca83c5bd67a1b29979f13947920a164b41ad`.

## Implementation Steps

1. Snapshot `git status --short` and record overlapping Plan 331 changes. Copy
   the hosted 3.4.0 package only after verifying archive digest
   `ba7733c...f1738`; add provenance/JUnit plus the path override and run
   `flutter pub get`. Prove package config and Flutter plugin metadata select
   the pristine scheduler before changing its behavior.
2. Add the nonce-bound TC-334-01 H0 mode. It pre-opens the peer, uses ordered
   method-channel submission (never sleeps) and a 4-second causal watchdog,
   atomically checkpoints device state, always finalizes the host artifact
   before verdict/cleanup, includes dependency/plugin/build inputs in its
   digest, and verifies PID/package removal. Run the Pixel expected RED. Stop-if:
   the exact ordered RED does not reproduce on the Pixel; preserve artifacts,
   do not patch the scheduler, and replan attribution. The emulator is a GREEN
   target, not a prerequisite causal-RED target.
3. Add TC-334-02 engine-ownership REDs and native census. Make all plugin state
   engine-owned, coalesce within-engine opening singletons, run every DB action
   on that engine's FIFO, fence close/reopen/delete, and on detach close only
   owned handles, suppress results, quit safely, and acknowledge termination.
4. Add TC-334-03 opener REDs. Apply `busy_timeout=1000`, share one absolute
   deadline across raw/fallback, never treat timeout as wrong key, and attach an
   exactly-once close to a late handle. Keep canonical writable 5 seconds.
5. Add TC-334-04..07 handler REDs, including held eligibility, held second
   resolver, pre-claim overlay, group/direct post-show, cumulative budget, exact
   second identity, and late release. Implement only read/idempotent phase caps;
   never timeout-release registry/native mutating work. Put Android registry
   preparation before the exact native boundary and preserve non-Android
   ordering.
6. Extract the BSD-flock helper and add finite literal-lock REDs. On Android use
   `LOCK_EX|LOCK_NB` retry for event claims, tones, notification IDs, and
   overlay; on iOS/macOS retain current behavior. Add TC-334-15: event/tone move
   through one-way `publishing` transitions immediately before native show;
   tone-storage failure after event publishing falls back to exactly one silent
   show without unwinding the event; ambiguous callback errors are typed and
   non-releasable. Use atomic replacement for event terminalization and tone
   publishing/commit/repair. Failed event finalization preserves publishing and
   returns unavailable; malformed or failed tone repair remains silent and
   retains its sidecar until a successful repair anchors the max-preserving
   observation window. Reject impossible pending/post-show state shapes and
   prevent the same in-memory owner from replaying an ambiguous native attempt.
   Event finalization is bounded only after the durable publishing
   transition; tone/registry actions remain held through their actual
   mutation/native callback.
7. Add the fixed-slot terminal journal and exact allowlist/bound/prune tests.
   Register all three Plan-334 push files in `GROUP_TESTS`. Run focused GREEN and one
   representative mutation re-red for engine state, repeated-read deadline,
   and Android flock, restoring each immediately.
8. Run queue-inversion GREEN on Pixel/emulator, existing H0 handoff/process-
   death, Pixel raw+legacy compatibility, and the hosted rollback drill. Restore
   fork resolution, then run curated/family gates, analyzer, diff hygiene, and
   incremental Graphify refresh.

## Risks And Blind Spots

- A Dart timeout can hide rather than release native blockage -> TC-334-01/08
  requires a post-callback native SQLCipher sentinel and zero handle/worker
  residue.
- Engine-owned workers can leak handles/results on detach or violate singleton
  close/reopen ordering -> TC-334-02 plus device native census.
- Two connections to one SQLCipher file still contend at SQLite -> native
  worker isolation permits the owner to commit; read-only busy timeout bounds
  genuine external contention without changing canonical writer semantics.
- Late async work can show or retire after callback return -> TC-334-04/05/06
  explicitly releases stalled read futures after terminal outcome; mutating
  ownership/native operations are never detached by timeout.
- File-lock timeout can weaken exact notification identity/generation safety ->
  TC-334-09/10/11 assert owner integrity and zero contender side effects.
- Lifecycle / derived-state durability: only failures before any owner crosses
  `publishing` may release pending ownership. Event publishing followed by a
  pre-native tone-storage failure performs one silent show and does not unwind
  the exact event. Native entry makes the outcome ambiguous; callback success
  performs bounded atomic event finalization before validators, with failed
  replacement preserving publishing/unavailable. Tone publishing, committed,
  and malformed repair paths stay silent on repair failure and retain their
  sidecar. Covered by TC-334-04/06/09/10/15.
- Sibling-surface consistency: direct/group messages and reactions share the
  deadline abstraction; tests cover first and repeated pre-show reads plus both
  direct/group post-show. Native scheduling and bounded acquisition are Android-
  only; TC-334-11/12 freeze iOS/macOS lock and vendored source behavior.
- Destructive-action side effects: device harness uses disposable application
  id/database, finalizes evidence before cleanup, and verifies PID death plus
  uninstall/`pm path` absence. No production DB is removed.
- Invariant re-verification under new transitions: registry/canonical failure
  before event publishing creates no publication ownership; after event
  publishing, tone preflight failure keeps the event and invokes one silent
  native show; native entry makes ownership non-releasable even without a
  trustworthy callback result; only a callback-success path enters post-show
  validation. Atomic finalization/repair failure never reopens audio or event
  ownership. TC-334-04/06/09/10/15 recheck these branches.
- Native show itself is an OS/method-channel boundary and has no 8 s, 2 s, or
  1 s deadline. A callback can remain pending indefinitely; the durable
  `publishing` records are the only same-process/process-death evidence until a
  later coordination observer terminalizes or repairs them.
- Original incident owner remains unknowable -> causality claim is limited to a
  reproduced mechanism matching the symptoms; diagnostics improve future
  attribution but do not retroactively name the owner.

## Gate Cadence

- Per-plan closure: focused handler/opener/flock/plugin tests; exact staging,
  post-show, listener-order, raw-key, and H0 preservation sentinels; affected
  `groups` curated lane; justified `core-host-all` for shared core lock/opener
  changes and `feature-host-all` for the push handler; real device probe on both
  currently available Android targets.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Android notification
  recovery dependency wave containing Plans 330/331/332/334, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs: vendored Kotlin unit tests, Kotlin H0
  source tests, the two exact H0 device scripts, and the exact Pixel raw-key
  integration test are run directly.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated/user-owned changes.
git status --short

# Device discovery; every device command below is pinned.
flutter devices --machine
adb devices -l

# Vendor pristine pinned code and prove resolution before scheduler edits.
flutter pub get
flutter test test/core/database/sqflite_sqlcipher_fork_contract_test.dart

# First causal RED before scheduler production edits; command returns zero only
# when a durable expected-RED artifact has the exact prefix/no-COMMIT shape and
# cleanup succeeded.
./scripts/run_android_canonical_runtime_h0_probe.sh \
  21071FDF600CSC --sqlcipher-queue-inversion --expect-red

# Host RED/GREEN slices.
flutter test test/features/push/application/background_storage_deadline_test.dart
flutter test test/features/push/application/background_storage_liveness_journal_test.dart
flutter test test/features/push/application/background_message_handler_staging_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/core/database/encrypted_db_read_only_liveness_test.dart
flutter test test/core/database/sqflite_sqlcipher_fork_contract_test.dart
flutter test test/core/bootstrap/flutterfire_background_queue_contract_test.dart
flutter test test/core/notifications/bounded_posix_flock_test.dart
flutter test test/core/notifications/durable_notification_tone_lease_test.dart
flutter test test/core/notifications/durable_conversation_notification_id_registry_test.dart
flutter test test/core/notifications/flutter_notification_service_test.dart

# Native/plugin contracts.
./android/gradlew -p android :sqflite_sqlcipher:testDebugUnitTest \
  --tests '*EngineWorkerIsolationTest'
./android/gradlew -p android :app:testDebugUnitTest \
  --tests 'com.mknoon.app.CanonicalRuntimeH0ProbeSourceTest'

# Real Android GREEN and non-orphaned native sentinels.
./scripts/run_android_canonical_runtime_h0_probe.sh \
  21071FDF600CSC --sqlcipher-queue-inversion
./scripts/run_android_canonical_runtime_h0_probe.sh \
  emulator-5554 --sqlcipher-queue-inversion

# Existing ownership and key-mode preservation.
./scripts/run_android_canonical_runtime_h0_probe.sh \
  21071FDF600CSC --handoff --process-death
./scripts/run_android_canonical_runtime_h0_probe.sh \
  emulator-5554 --handoff --process-death
flutter test -d 21071FDF600CSC \
  integration_test/db_raw_key_migration_proof_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'ST-008 queued listener events persist after DB write contention releases'

# Registration and affected gates.
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 1 --reporter failures-only
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 1 --reporter failures-only

# Hygiene and graph refresh.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Rollback drill, executed once before final closure and then restored to the
fork before the remaining gates:

```bash
# Temporarily remove only the sqflite_sqlcipher path override with apply_patch.
flutter pub get
flutter test test/core/database/sqflite_sqlcipher_fork_contract_test.dart \
  --dart-define=EXPECT_HOSTED_SQLCIPHER=true
flutter test -d 21071FDF600CSC \
  integration_test/db_raw_key_migration_proof_test.dart
# Restore the path override with apply_patch, then `flutter pub get` and rerun
# the normal fork contract. Hosted rollback must resolve version 3.4.0 and the
# recorded archive identity; any failure restores the fork and blocks closure.
flutter pub get
flutter test test/core/database/sqflite_sqlcipher_fork_contract_test.dart
```

## Device/Relay Proof Profile

- Profile: single-device real Android, run independently on two available
  targets.
- Boundary being proven: same-process multi-engine native SQLCipher worker
  liveness, engine-owned thread/handle teardown, and post-recovery DB usability.
  FlutterFire-style serialized callback progress is a separate host/source
  contract; the device fixture does not claim actual FCM service delivery.
- Live availability check: `flutter devices --machine; adb devices -l` on
  2026-08-04 -> USB Pixel 6 `21071FDF600CSC` Android 16/API36 and Android
  emulator `emulator-5554` Android 17/API37 are online.
- Required setup: one target at a time, disposable `com.mknoon.app.h0probe`,
  source-built debug APK, existing H0 broadcast receiver, two Flutter engines,
  real SQLCipher DB, nonce-bound machine-readable artifact. No relay, FCM credential,
  second account/device, network, Activity, ApplicationRoot, or manual tap.
- Two-peer default: N/A — this proof is one process with two Flutter engines,
  not a messaging exchange. Run first on the incident-class USB Android and
  repeat on the available Android emulator for parity.
- Closure role: causal RED passed on the Pixel before native scheduler edits;
  current-source GREEN passed on the Pixel and emulator.
- Queue-inversion GREEN artifacts:
  `build/h0-probe/21071FDF600CSC/queue-inversion-9e6e6771a00041f6a89bd2a8ac19f9e9.json`
  and
  `build/h0-probe/emulator-5554/queue-inversion-f5077200df9c431e831c4344a353f994.json`,
  source digest
  `23435fd8bffcfbe96e185fb32926ca83c5bd67a1b29979f13947920a164b41ad`.
- Handoff/process-death preservation artifacts:
  `build/h0-probe/21071FDF600CSC/6e12ed46f4a74ca6c3ba21185d1916d04c5f2fc6b1ce1510c81c75d308276eca.json`
  and
  `build/h0-probe/emulator-5554/174eef0520f381baf422a57bfadab29f11c9a7e7887d95f96c7f58c9a0ceb3e6.json`,
  source digest
  `5f310722582b91cbaba6191a4d549a484c01620fa6371dff00480ace54649d56`.
- `FLUTTER_DEVICE_ID`: host selector only; scripts take the explicit Android ID.
- Registration: exact H0 script mode and Kotlin source test; no Sims scenario or
  integration-test proof registration.
- Discovery command: `flutter devices --machine; adb devices -l` -> target ID
  must be present and `device`.
- Closure command:
  `./scripts/run_android_canonical_runtime_h0_probe.sh <id> --sqlcipher-queue-inversion`
  -> ordered writer/read success, fresh DB sentinel, zero lingering handles or
  operations, destroyed-engine worker termination acknowledgements, same PID,
  zero Activity/ApplicationRoot, and recorded PID/package cleanup. The mode
  writes its terminal artifact within 8 seconds; no broadcast ANR/restart is
  accepted.
- Deferred device work: unavailable Android API/model bands are
  `N/A (target unavailable by project policy)`. No iOS proof applies to an
  Android plugin scheduler change.

## Execution Interpretation And Done Criteria

- Expected RED: TC-334-01's `--expect-red` succeeds only after proving
  `BEGIN EXCLUSIVE`, posted peer query, and writer-resume request in order, then
  observing no reader result/COMMIT at 4 seconds and finalizing cleanup. TC-
  334-04/05/06/07 expose first/second/direct/group/cumulative waits; TC-334-09/
  10/11 expose current Android lock behavior without hanging the runner.
- Green sentinel: the native device artifact completes writer commit, reader,
  and a fresh post-recovery SQLCipher write/read/close with zero handles/queued/
  running work and terminated destroyed-engine workers. The serial host test
  completes the exact second event. Existing staging, policy, ownership, H0,
  raw-key, and same-group ordering tests remain green.
- Pre-existing dirty tree / known failure: the repository contains extensive
  user-owned Plan 331/333 work. In-scope overlaps already modified before Plan
  334 include `background_message_handler.dart`,
  `encrypted_db_opener.dart`, `00-INDEX.md`, and the untracked H0 Dart/Kotlin/
  script files. Preserve and layer changes; do not reset or overwrite them.
- Environment blocker: none for host or Android proof at planning time. Relay
  inputs are intentionally unnecessary. If a listed target disconnects, only
  that live leg is availability-bounded; the connected target remains usable.
- Scope drift: any need to change server custody, DB schema, FlutterFire native
  latch semantics, group listener ordering, iOS behavior, or Plan 331 recovery
  activation stops implementation and requires a new plan decision.
- Current verification state (2026-08-04): closed / plan-green. Focused final
  335/335, adversarial notification 41/41, both native unit contracts,
  completeness 1414/1414, ST-008, Pixel raw-key 8/8, rollback/restoration,
  both current-source device families, serialized groups 4016/4016 plus four
  Go tails, core 3100/3100 across 392 paths, and feature 8777 pass/1 declared
  skip across 834 paths are green. Full `flutter analyze` reports no issues,
  `git diff --check` is clean, and the refreshed exact-anchor Graphify review is
  current at `dc4beab216d8c42b`.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative native/handler/flock
      mutation re-red are recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] All three Plan-334 push files have `GROUP_TESTS` registration and the H0
      exact mode is implemented and verified.
- [x] Pixel and emulator real-SQLCipher proof passes with post-timeout sentinel.
- [x] Raw-key/legacy-key compatibility and no non-Android plugin drift pass.
- [x] Full `flutter analyze` has no issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- Historical causal RED command/artifact:
  `./scripts/run_android_canonical_runtime_h0_probe.sh 21071FDF600CSC --sqlcipher-queue-inversion --expect-red`
  produced
  `build/h0-probe/21071FDF600CSC/queue-inversion-b197a89d074548c7ad04d9410246172e.json`.
- Preservation command:
  `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name 'ST-008 queued listener events persist after DB write contention releases'`.
- Registration verified: `background_storage_deadline_test.dart`,
  `background_storage_liveness_journal_test.dart`,
  `background_message_handler_staging_test.dart`,
  `background_message_handler_test.dart`,
  `background_push_notification_fallback_test.dart`,
  `flutterfire_background_queue_contract_test.dart`,
  `bounded_posix_flock_test.dart`,
  `durable_conversation_notification_id_registry_test.dart`,
  `durable_notification_tone_lease_test.dart`,
  `flutter_notification_service_test.dart`, and
  `show_notification_use_case_test.dart` are in `GROUP_TESTS`; Kotlin/device
  commands remain exact direct commands.
- Migration: none — no database schema or data rewrite.
- Boundary closure: causal RED passed on Pixel. Current-source queue GREEN
  passed on Pixel and emulator with source digest
  `23435fd8bffcfbe96e185fb32926ca83c5bd67a1b29979f13947920a164b41ad`;
  handoff/process-death passed on both with source digest
  `5f310722582b91cbaba6191a4d549a484c01620fa6371dff00480ace54649d56`;
  Pixel raw/legacy SQLCipher compatibility is 8/8.
- Unresolved evidence: exact historical lock owner remains unknowable; the
  source-permitted queue-inversion mechanism is deterministically reproduced
  without naming that historical owner.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-03 22:49 CEST | planning draft | plan + index | source and live-device grounding complete | mechanism source-confirmed; incident attribution unresolved | implementation gated on review and real Pixel RED | run `$tdd-review`, patch verified deltas, then reproduce |
| 2026-08-03 23:20 CEST | review v1 | plan, native plugin, H0, handler, lock callers | `$tdd-review`: `plan-fixes-required`; core bet source-confirmed but device service claim, per-connection lifecycle, FAIL evidence, repeated/direct reads, cumulative budget, acquired-owner, and iOS boundaries were unsafe | no production execution on v1 | v1 blocked | apply verified v2 deltas |
| 2026-08-03 23:35 CEST | reviewed v2 | Plan 334 | five lenses rerun: L1 clear with attribution gate; L2/L3/L4/L5 clear after named deltas; evergreen B-1/B-5/B-7/B-8/B-9/B-10 have explicit rollback/concurrency/boundary/preservation rows | verdict `ready` for causal RED; production scheduler remains conditional on RED | no blocker to the causal RED; production fork remains evidence-gated | vendor pristine 3.4.0, run Pixel expected RED |
| 2026-08-03 23:42 CEST | execution snapshot | 187-path dirty tree; Plan 334 overlaps listed in Execution Interpretation | `git status --short` captured to `/tmp/plan334-pre-execution-status.txt`; existing modified/untracked Plan 331/H0/handler/opener/gate files confirmed | preserve all existing work; no reset/checkout | dirty tree expected and not a blocker | prepare pristine vendor, H0 fixture, and host REDs only |
| 2026-08-03 23:52 CEST | causal RED | Pixel 6 `21071FDF600CSC`; pristine vendored scheduler SHA `92f89e…8014`; nonce `b197a89d074548c7ad04d9410246172e` | expected-RED H0 command passed and retained `build/h0-probe/21071FDF600CSC/queue-inversion-b197a89d074548c7ad04d9410246172e.json` | real SQLCipher reached the exact five-phase prefix, then the 4 s watchdog fired at 7384 ms with no writer COMMIT/reader result; Activity count stayed zero and PID/package cleanup completed | causal device RED satisfied; native scheduler production edits authorized by reviewed v2 | implement and prove engine-owned scheduler GREEN |
| 2026-08-03 23:53 CEST | handler RED | six-case `background_storage_deadline_test.dart`; pinned FlutterFire source contract | missing deadline hook gave the compile RED; a temporary no-op hook (removed) produced six semantic failures; FlutterFire source sentinel passed | late direct staging, held first/repeated reads, held direct/group post-show, and serialized second-event starvation reproduced | handler causal RED satisfied | implement one cumulative deadline with read-only phase bounds and stage direct custody first |
| 2026-08-04 | focused + adversarial GREEN | background deadline/handler/show plus event/tone/registry/native-boundary protocol | closure-audited focused set 335/335; adversarial `bounded_posix_flock_test.dart` 41/41 | one-way event publication, same-owner replay denial, strict state shapes, silent pre-native tone fallback, bounded atomic event finalization, atomic/max-preserving tone repair, and iOS/macOS preservation are green; each added closure defect was observed RED before its production fix | focused/adversarial blocker none | run native/unit, current-source device, and affected-gate closure |
| 2026-08-04 | native + queue device GREEN | vendored plugin; H0 source contract; Pixel/emulator queue mode | `EngineWorkerIsolationTest` PASS; `CanonicalRuntimeH0ProbeSourceTest` PASS; Pixel `queue-inversion-9e6e6771a00041f6a89bd2a8ac19f9e9.json` PASS; emulator `queue-inversion-f5077200df9c431e831c4344a353f994.json` PASS | both current artifacts attest source digest `23435fd8bffcfbe96e185fb32926ca83c5bd67a1b29979f13947920a164b41ad`; historical causal RED `queue-inversion-b197a89d074548c7ad04d9410246172e.json` retained | native/device queue boundary closed | run handoff, key-mode, and rollback preservation |
| 2026-08-04 | handoff + compatibility GREEN | Pixel/emulator process-death mode; Pixel key proof; dependency rollback | Pixel `6e12ed46f4a74ca6c3ba21185d1916d04c5f2fc6b1ce1510c81c75d308276eca.json` PASS; emulator `174eef0520f381baf422a57bfadab29f11c9a7e7887d95f96c7f58c9a0ceb3e6.json` PASS; Pixel raw-key 8/8; rollback drill passed and fork restored | handoff artifacts attest source digest `5f310722582b91cbaba6191a4d549a484c01620fa6371dff00480ace54649d56` | compatibility/device preservation closed; affected gates remain | run registration, curated/family gates, analysis, and graph refresh |
| 2026-08-04 | affected-gate stabilization | gate registration; listener sentinel; groups manifest and Go tails | completeness 1414/1414 PASS; ST-008 PASS; the initial groups 3996/1 stale exception-shape expectation was corrected test-only and its exact file passed 58/58; a later default-parallel full run overloaded the host, accumulated six contention failures, and froze after +3941; the exact `GROUP_TESTS` manifest then passed serialized 4016/4016 followed by all four Go tails, exit 0 | the clean serialized full-manifest run is the governing groups receipt; no Plan-334 product failure remains | blocker none | run both justified family gates, full analysis, diff hygiene, and graph refresh |
| 2026-08-04 | final family/analyzer/graph closure | 392-path core family; 834-path feature family; whole-tree analyzer; Graphify architecture graph; Plan 334 + index | `core-host-all --batch-flutter --concurrency 1 --reporter failures-only`: 3100/3100 plus both contract tails; `feature-host-all` with the same serialized shape: 8777 pass/1 declared capability skip; full `flutter analyze`: no issues; `git diff --check`: clean; incremental Graphify refresh + exact-anchor review: current fingerprint `dc4beab216d8c42b` | a prior concurrent feature attempt's exact 48-path bracket passed serialized 409/409, classifying host starvation but not substituting for this complete family receipt; all required closure gates are now green | closed / plan-green; exact historical lock owner remains the only intentionally unresolved evidence | preserve retained artifacts and hand off |

## Historical Reviewer Findings (v1/v2; superseded by execution evidence)

Verdict on v1: **plan-fixes-required**. Plan classification remains
`evidence-gated`; core bet is **confirmed as a current source-permitted
mechanism, with historical incident attribution unresolved**. Disposition:
**apply-plan-fixes**, then execute the causal evidence gate.

Required deltas applied in v2:

1. **Native lifecycle/ownership:** per-connection workers lacked safe cross-
   engine singleton/refcount/detach semantics. The target is now engine-owned
   plugin state with within-engine FIFO/singleton lifecycle, detached-result
   suppression, and native termination census (TC-334-02/08).
2. **Boundary truth:** current H0 manually constructs a plugin-bearing engine;
   it is not FlutterFire's service. TC-334-01 now claims only real two-engine
   SQLCipher inversion; TC-334-07 separately owns serialized callback progress.
3. **Evidence survival:** expected FAIL is finalized before assertions/cleanup,
   nonce-bound, source/dependency-bound, and records PID/uninstall outcome. The
   new 4 s/8 s bounds avoid the v1 12-second foreground-broadcast overrun.
4. **Cancellation safety:** read/idempotent phases alone use the absolute
   deadline. Acquired claim/tone/ID/native owners are never released by timeout;
   contender failure and late owner completion are explicit in TC-334-09/10.
5. **Bypass coverage:** v2 adds the repeated preview/local-state read, direct
   post-show validator, event-claim lock, raw-timeout fallback discriminator,
   and cumulative-deadline cases (TC-334-03/05/06/07/09).
6. **Platform guard:** bounded lock acquisition and overlay flock migration are
   Android-gated; iOS/macOS behavior is a preservation contract.
7. **Provenance/rollback:** the hosted archive digest, package-resolution proof,
   allowlisted fork diff, untouched platform hashes, and hosted rollback drill
   are literal TC-334-12 obligations.

Non-blocking note: the 8 s / 2 s / 1 s / 200 ms bounds are conservative initial
constants selected below the platform callback boundary. Device artifacts must
record them; changing them after RED requires rerunning TC-334-01/07/09/10.

Blind-spot sweep after v2: B-1 reversible path-only dependency rollback is
covered by TC-334-12; B-2 first/repeated/direct/group and lock callers are
enumerated; B-3 historical attribution remains explicitly unresolved; B-4
exact identities, mutations, cumulative time, and expected-RED prefix prevent
vacuity; B-5 lifecycle/concurrency/delete/late completion is TC-334-02/03/08-
11; B-6 claims/generations/journal lifecycle is explicit; B-7 native bet is
stop-gated by Pixel RED; B-8 is real two-engine SQLCipher on both available
Android targets; B-9 sentinels cover staging/policy/H0/same-group/iOS; B-10
Android-only behavior and untouched non-Android hashes are explicit.

## Historical v2 Arbiter Decision

The causal RED subsequently passed, followed by current-source Pixel/emulator
GREEN. The status, Device/Relay Proof Profile, and Execution Progress above are
the governing implementation evidence; every formerly remaining affected gate
subsequently passed and the plan is closed.

The historical v2 decision was **ready to execute its causal RED** and withheld
permission to patch the native fork until the exact ordered inversion
reproduced. That evidence gate was satisfied on the Pixel. The implemented
production direction remains the reviewed minimum: engine-owned Android plugin
state plus read/idempotent storage deadlines and Android-only bounded
acquisition; server, schema, FlutterFire service, group-listener ordering, iOS
behavior, and Plan 331 activation stayed out of scope.
