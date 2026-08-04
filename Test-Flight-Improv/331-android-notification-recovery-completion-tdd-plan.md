# 331 - Android Notification Recovery Completion

Status: **partially implemented / production-activation safety-gated
(2026-08-03)** — `$tdd-review` verdict on the submitted draft was `not-ready`;
the review fixes and all independently safe slices are implemented. Plan 331A's
real two-engine Go/SQLCipher H0 gate passes on both available Android targets,
but the production headless dependency graph is not yet safe to activate. The
AOT entry point therefore remains deliberately fail-closed with a truthful
`retry/headless_composition_unavailable` result and production account-binding
publication keeps recovery work disabled.
Type: Bug
Spec: user free-text intent (2026-08-03): finish headless recovery, direct-chat
notification durability, recoverable no-event-ID pushes, rich unread
history/count, durable registration-health UX, and recovery-card localization
using Android only
Classification: partially implemented / safety-gated — direct durability,
unread projection, registration health, scheduler/localization,
authenticated-inner-ID defense-in-depth, the native runtime broker, and the
abstract bounded recovery runtime are implemented. Production draining and
acknowledgement remain disabled until a UI-neutral production recovery graph,
invocation-bound identity authority, complete direct/group ingress wiring,
typed four-store projection settlement, and ordered Dart/native teardown exist;
truly identity-free legacy pushes retain a documented safe-only boundary
Closure tier: host + native Android + real SQLCipher + paired Android/real relay
Baseline: clean Plan-330 checkpoint `1c7540b17954a423264e23ecf3528d3c01beeb0a`
(`close signal-grade group notification durability gaps`)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-03 evidence pass | Evidence Collector | `MknoonFirebaseMessagingService.kt`, `DroppedPushRecoveryStore.kt`, `DroppedPushRecoveryBridge.kt`, `GoBridge.kt`, `MainActivity.kt`, background handler, production bootstrap, direct/group drains | Android records a deleted-push marker but only a live main Flutter runtime can run the full canonical recovery coordinator; adding WorkManager alone would create unsafe Go callback and SQLCipher-writer races | Make process-wide runtime ownership and a headless writable composition the blocking Gate H0 |
| 2026-08-03 evidence pass | Evidence Collector | direct message/reaction listeners, staged replay, background handler, direct read use case, Plan-330 group outbox/reconciler | Direct canonical writes can commit before native display and replay then skips presentation; reactions also use an unawaited display call; stable direct notification IDs already exist | Reserve DB v107 for direct display custody, exact read acknowledgement, and reconciliation |
| 2026-08-03 evidence pass | Evidence Collector | foreground fallback, background handler, push decrypt preview, relay payload-size tests | An authenticated decrypted inner message ID is already parsed but discarded when the outer ID is absent; a payload with no authenticated canonical identity cannot safely be invented into an exact event | Promote authenticated inner identity; retain silent generic behavior for irreducibly identity-free legacy payloads |
| 2026-08-03 evidence pass | Evidence Collector | canonical unread helpers, `NotificationService`, `FlutterNotificationService`, notification-details builder | Canonical unread rows/counts already exist, but only the newest item is projected and Android receives neither history style nor `number`; no schema migration is needed for this slice | Build a bounded canonical snapshot and keep one stable card per conversation |
| 2026-08-03 evidence pass | Evidence Collector | registration coordinator/use case/token store, lifecycle/startup wiring, Settings/Orbit surfaces, migration secure-storage registry | Registration retry health is process-memory-only; a stored token is not proof the relay registration is healthy | Add a device-local secure health record, persistent warning, settings action, and live recovery clearing |
| 2026-08-03 evidence pass | Evidence Collector | native recovery service/resources and Robolectric tests | Recovery channel/title/body are hard-coded English and the Android module has no default/de/ar string resources | Add native Android resources and locale/channel-refresh proof |
| 2026-08-03 online research | Evidence Collector | current Signal Android notification v2 source; Firebase and Android WorkManager documentation | Signal rebuilds cards from canonical unread state, carries per-conversation history/count, cleans orphaned cards, and separately uses OEM badge code; Firebase says `onDeletedMessages` should start a full sync; WorkManager persists across app/process restarts but has a bounded worker lifetime | Adopt canonical rebuild/history/count and persistent unique work; explicitly exclude OEM badge guarantees and user force-stop |
| 2026-08-03 graph pass | Planner | Graphify architecture graph plus targeted current source | Compact graph was current and anchored at `DroppedPushRecoveryCoordinator`; source search resolved native/headless and UI gaps the app-owned graph does not model | Freeze the six-slice contract and submit this artifact to `$tdd-review` after the daemon restart |
| 2026-08-03 13:13 CEST | Planner | `flutter devices --machine`, `adb devices -l`, current index/worktree | Allowed live pair is USB Pixel 6 `21071FDF600CSC` API36 plus Android emulator `emulator-5554` API37; the code baseline is the Plan-330 checkpoint, while the user-owned modified Index and untracked Plan-331 draft are preserved | Pin all device commands to those IDs; use no iOS command or target |
| 2026-08-03 13:30 CEST | Planner | `$tdd-plan` sufficiency checklist, 24-row Test Contract, literal gates, DB/device/relay registration | Pre-review assessment: structure was complete but H0 and producer identity remained evidence gates; the later critical pass superseded this assessment | Submit to the requested `$tdd-review` |
| 2026-08-03 critical review | `$tdd-review` factual/core | Index Reports 41/44/48, relay producers, live reaction/read/history/health composition | Added missing `baseline`/pinned `transport`/`feed` obligations; found unit-only proofs that could pass while production callers bypass the new seam; refuted missing outer ID as an ordinary current-producer defect | Tighten caller-level tests and recast inner-ID work as a test-only transport-mutation robustness slice |
| 2026-08-03 critical review | `$tdd-review` native/boundary | Go singleton/dispatcher/node lifecycle, SQLCipher plugin lifecycle, worker/marker/device/Sims boundaries, v106 reaction schema | Admission-only ownership is unsafe; foreground bypasses the proposed DB lease; fake tests cannot close H0; the marker is account-ambiguous; `KEEP` can strand a newer generation; shared reactions cannot satisfy the claimed collision proof | Split Plan 331A, choose generation-resnapshot semantics, add account binding, make v107 one-way, narrow TC-13, and mark real-relay credentials unresolved |

## Current Implementation And Remaining Safety Gate

The safe, independently testable surface is implemented:

- Plan 331A supplies the process-global `GoRuntimeHost`, canonical writable
  lease, explicit SQLCipher-close handoff, stale callback/result fencing, and
  real no-Activity recovery/foreground/process-death probes on the pinned Pixel
  and emulator. The H0 prerequisite is complete; it proves ownership safety,
  not inbox recovery behavior.
- Android now has durable account-bound immediate and periodic WorkManager
  requests, `APPEND_OR_REPLACE` generation resnapshot semantics, API24-30
  foreground-service support, exact nonce/binding/generation completion
  validation, main-thread cleanup, and retry-preserving timeout/stop behavior.
- DB v107, direct message/reaction display custody, exact read acknowledgement,
  reconciliation, one-way version-floor/import rules, authenticated inner-ID
  recovery, bounded canonical history/count, encrypted account-fenced pending
  overlay, durable registration health/settings UX, and default/de/ar native
  recovery resources are implemented.
- `CanonicalRecoveryRuntime` performs bounded direct-then-group pagination,
  never lets a periodic sweep consume a deleted-batch marker, and requires a
  typed projection outcome. A post-implementation counterexample showed that a
  completed projection call was not proof of durable convergence; the contract
  now retries without acknowledgement whenever projection custody is pending
  or settlement failed, while still running ordered cleanup.

Production activation remains intentionally disabled. An independent
post-implementation source audit found that the UI bootstrap cannot safely be
reused by the headless engine and that no production `CanonicalRecoverySession`
exists. Enabling the existing worker would risk acknowledging an invocation
whose marker changed, deleting direct staged data without typed handlers,
persisting group rows without notification custody, or closing SQLCipher while
Dart callback futures remain in flight. Before `activateRecoveryWork:true` can
be published, a follow-up implementation must provide all of these seams:

1. an exported UI-neutral `ProductionCanonicalRecoveryGraphFactory`;
2. exact invocation-bound binding/generation checks before acquire and ack;
3. passive secure-store/DB identity loading with binding-parity validation and
   the account-migration authority gate, without rebind side effects;
4. a direct recovery adapter with every typed replay handler plus an awaited
   Dart ingress/in-flight fence;
5. a fully wired group recovery listener or equivalent recovery-only adapter;
6. typed bounded settlement and total-pending checks across direct display,
   direct reconciliation, group display, and group reconciliation custody; and
7. teardown that stops Dart ingress, awaits admitted direct/group work,
   disposes projection owners, quiesces native Go, closes SQLCipher, and only
   then releases the lease.

Until those seams and their available-device proof land, the AOT-visible entry
point creates no database/session/lease, never drains or acknowledges, and
returns `retry` with `headless_composition_unavailable`. The native binding
publisher keeps recovery work disabled. This is a safety gate, not an H0
failure. TC-331-23 is independently open: the Sims row is registered but marked
`automationReady:false`, and the direct runner reports typed `credentials`
with zero assertions/artifact because relay/FCM credentials are absent.

## Outcome And Priority Order

1. **P0 — prove and build fully headless canonical recovery.** A killed Android
   process (not a user force-stopped app) must be able to start non-UI work,
   acquire sole Go/runtime/SQLCipher ownership, fetch direct and group inboxes
   to truthful exhaustion, settle notification custody, and acknowledge only
   the exact durable recovery generation. `onDeletedMessages` schedules
   immediate unique work; one unique connected-network sweep requested every
   six hours with a one-hour flex window covers losses for which FCM emits no
   deleted-batch callback, subject to normal Android scheduling.
2. **P0 — give direct chats Plan-330-grade display custody.** Direct text,
   photo, video, voice-message, and fresh reaction ADD events acquire an
   identifier-only marker before their canonical mutation, retry native display
   after throw/process death, and reconcile read/delete/archive/block/reaction
   REMOVE with generation-CAS cancellation. Exact unread recovered relay rows
   become notification-capable; the old unconditional replay silence remains
   only for already-read, already-presented, viewed, blocked, or archived rows.
3. **P1 — harden exact identity recovery when a test/legacy transport omits the
   outer push event ID.** Current production relay producers preserve outer IDs
   for every decryptable message/reaction; this is defense-in-depth, not an
   ordinary real-relay reproduction. Use
   the authenticated/decrypted inner canonical message or reaction-transition
   ID after conversation/sender/target/action checks, then acquire the normal
   exact claim, route metadata, read fence, and display custody. Never
   substitute the FCM transport ID, collapse key, timestamp, or a guessed hash
   for canonical identity. If no authenticated message identity exists, keep
   the current private, silent, generic, stable conversation card and
   generation-cancellable behavior; an identity-free reaction does not create
   a new reaction alert and waits for canonical catch-up/reconciliation.
4. **P1 — project rich unread history and total count.** Rebuild one stable
   card per direct/group conversation from the current canonical state, include
   at most the five newest eligible privacy-normalized unread message lines,
   and carry the uncapped total unread-message count in Android `number`.
   Reactions may be the latest headline but do not invent an unread-message
   count.
5. **P1 — make registration health durable and visible.** Persist only safe
   device-local status/timestamps/counters, not tokens or raw errors. Permission
   denial is immediately actionable; transient token/relay failures show a
   persistent warning after three consecutive terminal attempts, or 24 hours
   after the first unresolved failure (measured from last success when one
   exists). A successful retry clears the warning live. Account migration
   blocking is neutral, not an unhealthy registration result.
6. **P2 — localize the native recovery card.** Move the recovery channel name,
   description, card title, and body into complete default/en, German, and
   Arabic Android resources; refresh an existing channel after locale changes
   without replacing its stable ID or user settings.

Execution dependency is not identical to priority: Plan 331A/Gate H0 comes first, DB
v107/direct custody lands before the headless runtime consumes it, then the
headless worker can prove full direct+group convergence. The remaining P1/P2
slices may be developed independently after causal REDs, but Plan 331 cannot
close until the full ordered campaign passes.

## Signal And Platform Research Grounding

Research was refreshed on 2026-08-03 against primary sources:

- Signal's current
  [`NotificationStateProvider`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationStateProvider.kt)
  reads unread rows from its canonical database, applies message/reaction
  eligibility, groups them into conversations, and returns one notification
  state.
- Signal's
  [`NotificationFactory`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationFactory.kt)
  adds the conversation's message history and sets the conversation and summary
  `number` from the full message count.
- Signal's
  [`DefaultMessageNotifier`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/DefaultMessageNotifier.kt)
  publishes the rebuilt state, cancels orphaned cards, updates the count, and
  checks which expected cards are actually displayed.
- Signal's official
  [notification troubleshooting guide](https://support.signal.org/hc/en-us/articles/360007318711-Troubleshooting-Notifications)
  directs Android users to notification permission and background-delivery
  settings. Plan 331 applies that idea only to states Mknoon can actually
  observe: permission and its own token/relay registration; it does not invent
  a battery/OEM diagnosis.
- Firebase's official
  [Android receive guide](https://firebase.google.com/docs/cloud-messaging/android/receive-messages)
  says `onDeletedMessages()` is emitted only for defined queue-loss conditions
  and should trigger a full app-server sync. It is not evidence for every
  possible silent loss.
- Android recommends
  [WorkManager for persistent work](https://developer.android.com/develop/background-work/background-tasks/persistent)
  across app exits/restarts and documents unique work, constraints, retry, and
  a normal worker execution budget. Plan 331 uses stable WorkManager `2.11.2`,
  the current stable release compatible with this app's minSdk 24, rather than
  an alpha.
- Android's
  [notification badge guidance](https://developer.android.com/develop/ui/views/notifications/badges)
  makes launcher presentation implementation-dependent. `number` is therefore
  card metadata in this plan, not a Samsung/Pixel/other-launcher badge promise.

Plan-331 inference: Mknoon should regenerate a bounded card from canonical
state, keep durable display/reconciliation custody, and let Android schedule a
full catch-up when its UI process is absent. The implementation is not a copy
of Signal's internals. Signal also calls `ShortcutBadger`; this plan deliberately
does not add or verify any OEM-specific badge API.

## Problem And Evidence

- Behavior to improve: every eligible Android direct/group text, photo, video,
  voice-message, and reaction notification must converge after display errors,
  process death, deleted FCM batches, read/policy races, and ordinary catch-up;
  users must also see canonical unread context and a durable registration
  warning.
- Impact: today canonical chat data can arrive while its alert is permanently
  lost; a completely dead UI process cannot fetch a dropped batch; users cannot
  tell that registration is persistently unhealthy; native recovery copy is
  English-only.
- Confirmed headless root cause: `MknoonFirebaseMessagingService.onDeletedMessages`
  at `android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt:33-43`
  commits a generation and posts a card only. `DroppedPushRecoveryCoordinator`
  at `lib/core/notifications/dropped_push_recovery_coordinator.dart:74-258`
  needs runtime readiness, transport health, full direct drain, and full group
  drain, but production constructs it only inside the live application at
  `lib/app/bootstrap/production_application_bootstrap.dart:5286-5330`.
- Confirmed runtime blocker: `GoBridge` calls the process-global
  `GoMknoon.initialize(this)` for one Flutter engine at
  `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:41-47`; Go's current
  initializer replaces the global callback. A second headless engine could
  steal callbacks from the foreground engine. The current FCM background
  handler opens SQLCipher read-only and explicitly defers canonical drains.
- Confirmed direct message root cause: `ChatMessageListener` persists a fresh
  message and then calls `maybeShowNotification` at
  `lib/features/conversation/application/chat_message_listener.dart:608-705`;
  a native throw is logged, while duplicate replay exits before display at
  `:567-579`.
- Confirmed direct reaction root cause: `HandleIncomingReactionUseCase`
  persists a fresh ADD and launches notification display with `unawaited` at
  `lib/features/conversation/application/handle_incoming_reaction_use_case.dart:294-355`.
  The live `ReactionListener` also lacks the display dependencies used by
  staged replay.
- Confirmed direct background gap: a background direct push stages and attempts
  display, but display failure only releases claims; staged canonical replay is
  unconditionally notification-suppressed. Direct cards have stable IDs but no
  typed event/generation metadata or generation-CAS cancellation.
- Confirmed defense-in-depth gap under an explicit outer-ID-removal transport
  mutation: `PushDecryptPreview` parses an authenticated inner
  group message ID at
  `lib/features/push/application/push_decrypt_preview.dart:920-934`, but creates
  a comparand only from the pre-decrypt outer expected ID at `:796-830`.
  Foreground/background fallbacks therefore publish a silent generic group card
  without exact claim/read fencing even when decryption recovered the ID.
  Direct/group reaction preview likewise parses a decrypted reaction payload
  but currently requires an outer event ID before decryption/parity, so a
  recoverable inner transition cannot become the exact notification owner.
  Current normal relay producers preserve the outer canonical ID whenever
  ciphertext remains decryptable; routing-only oversize fallback removes the
  ciphertext before removing the ID. Closure therefore uses a named test-only
  mutation plus relay producer-preservation tests, not a claimed real-relay
  reproduction.
- Confirmed unread gap: canonical group repositories already expose unread
  counts, but `GroupNotificationCanonicalStateDbHelpers` selects only one newest
  unread item; `NotificationService.showMessageNotification` and
  `FlutterNotificationService` carry only latest title/body. The Android
  details at `lib/core/notifications/local_notification_support.dart:71-98`
  set neither style history nor `number`.
- Confirmed registration gap: `PushRegistrationCoordinator` at
  `lib/features/push/application/push_registration_coordinator.dart:9-229`
  keeps permission, retry, and failure state only in memory. A successful raw
  token is durable, but no last success, consecutive failure, safe reason, or
  UI stream exists. Restart loses the health interpretation.
- Confirmed localization gap: recovery channel name/description and card
  title/body are hard-coded in `MknoonFirebaseMessagingService.kt:45-96`, and
  `android/app/src/main/res` has no `strings.xml` in default, German, or Arabic
  values directories.
- Existing coverage: Plan 330 proves group display custody, exact read and
  generation cancellation, foreground/background fences, real SQLCipher v106,
  and paired Android cards. Dropped-push store/bridge/coordinator tests prove
  marker ABA safety and main-runtime recovery. Direct listener/reaction tests
  prove current persistence and successful display paths. Registration tests
  prove process-local retry. Native service tests cover API24/26/33 card and
  permission behavior.
- Missing coverage: no worker/secondary-engine composition, no Go drain-state
  handoff, no writable headless SQLCipher proof, no direct outbox/read journal,
  no direct post-show fence, no authenticated-inner-ID promotion test, no
  canonical history/count projection, no durable registration state/UI, and no
  native locale test.
- Refuted findings: direct notification IDs are not unstable; unanchored group
  cards are already stable and can be cancelled when the conversation opens;
  WorkManager alone is not full recovery; history/count and registration health
  do not require a SQLCipher migration; Android `number` is not an OEM launcher
  badge guarantee.
- Unresolved findings: Plan 331A must establish safe sole ownership and a bounded
  page-continuation strategy; paired relay/FCM credentials are absent from the
  current shell and remain a closure preflight rather than a source defect; a
  product-level exact identity cannot exist for a
  legacy payload with neither outer nor authenticated inner ID. Those are
  explicit gates/boundaries, not hidden acceptance gaps.
- Affected production, test, and gate files: Android service/bridge/activity,
  new worker/runtime host and resources, canonical recovery composition,
  direct message/reaction/read/replay paths, DB v107 registry/helpers,
  decrypt/background/foreground presentation, notification descriptor/details,
  registration coordinator/store/Settings/Orbit/l10n, focused Kotlin/Dart/
  SQLCipher/integration tests, `run_test_gates.sh`, `run_host_test_gates.sh`,
  Sims manifest/binding, and reliability-simulation discovery.

## Graph Grounding Snapshot

- Final graph fingerprint / freshness: `55638de8c282435f`; `freshness=current`,
  `confidence=anchored`.
- Query / profile: initial broad query followed by the required exact-anchor
  refinement: `python3 graphify-arch/tdd_context.py query "conversation_notification_content_kind.dart Android notification recovery completion lifecycle callback exact callers tests gates" --profile tdd --budget 700`.
- Adversarial review query: `python3 graphify-arch/tdd_context.py query "Counterexamples to plan 331: DroppedPushRecoveryCoordinator GoBridge MknoonFirebaseMessagingService ChatMessageListener HandleIncomingReactionUseCase PushDecryptPreview NotificationService PushRegistrationCoordinator bypass callers migration and gate registration" --profile review --budget 800`; `confidence=anchored`, `freshness=current`.
- Final post-refresh query: `python3 graphify-arch/tdd_context.py query "CanonicalRecoveryRuntime HeadlessCanonicalRecoveryWorker production headless activation safety gate" --profile review --budget 800`; `confidence=anchored`, `freshness=current`; graph contains `66635` nodes / `99617` edges and the TDD overlay contains `1515` files / `14761` named tests / `1158` production targets.
- Anchors: `DroppedPushRecoveryCoordinator` ->
  `lib/core/notifications/dropped_push_recovery_coordinator.dart:74`; production
  bootstrap, startup router, native bridge, group repositories/listeners, and
  `test/core/notifications/dropped_push_recovery_coordinator_test.dart`.
- Surfaced proof/gate files: dropped-push coordinator/bridge tests, production
  bootstrap, startup router, group listener/repository paths, and Plan-330
  notification durability surfaces.
- Graph gaps requiring source search: native WorkManager absence and Go
  callback singleton, direct reaction/background replay details, Android
  resources, Settings/Orbit presentation, current Signal source, and live
  target availability.
- Reuse rule: these anchors may be handed to review/execution; all conclusions
  still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Android process-killed, non-UI canonical recovery scheduled from a durable
  deleted-batch marker and a bounded periodic sweep.
- The Plan-331A process-wide `GoRuntimeHost`/`CanonicalRuntimeLease`, a dedicated
  minimal-plugin headless Flutter entry point, foreground-priority cooperative
  drain/handoff, and one writable SQLCipher owner shared by foreground and
  worker; FlutterFire remains a read-only/no-Go third engine.
- DB v107 direct notification display custody, exact read acknowledgements,
  peer-keyed reconciliation, lifecycle cleanup/import, and restart retry.
- Exact authenticated-inner-ID promotion for outer-ID-missing group pushes;
  equivalent direct promotion only where the authenticated payload exposes its
  canonical ID without weakening sender/conversation checks.
- Bounded direct/group canonical history plus Android `number`, while keeping
  one stable card per conversation.
- Device-local registration health, centralized above every authenticated
  Feed/Orbit/Settings construction path, with retry/open-settings actions and
  en/de/ar Flutter localization. The installation binding is the existing
  device-local installation identity; account cutover clears/regenerates the
  record and rotates the native recovery binding.
- Native default/de/ar recovery strings and channel refresh.
- Automated host/native/real-SQLCipher/real-relay proof on the currently
  connected physical Android and Android emulator only.

Must preserve:

- Plan-330 group display custody, exact event acknowledgement, tri-state
  reconciliation, one keyed read/show lane, background post-show fence, and
  stable generation-CAS cancellation -> the focused Plan-330 suites plus
  `./scripts/run_test_gates.sh groups`.
- Stable per-conversation IDs, one card per conversation, viewing suppression,
  tone coalescing, private-media redaction, archived/blocked policy, and no
  `cancelAll` -> direct/group notification and registry suites.
- A reaction notification does not increment unread-message count; only current
  eligible unread incoming messages contribute to `number`.
- Outboxes contain identifiers/comparands only: no message body, reaction emoji,
  media path, key material, token, or raw registration exception.
- Account migration gates network/DB writes. Direct v107 rows transfer only
  through the existing encrypted database import; registration health is
  installation-local `clearRegenerate` state and is never exported.
- Provider data-only/privacy behavior and current crypto authorization checks.
- Notification permission denial cannot erase recovery work; worker failure or
  cancellation cannot acknowledge a pending generation.

Hard `Do not`:

- Do not edit Swift, iOS, APNs, iOS integration tests, or require any iPhone or
  iOS simulator command.
- Do not add `ShortcutBadger`, Samsung APIs, launcher-specific code, or claim
  that Android `number` guarantees a home-screen badge.
- Do not use an FCM transport ID, collapse key, receive time, sender-controlled
  timestamp, or unhasafely truncated digest as a canonical message/reaction ID.
- Do not make a generic identity-free fallback audible or expose decrypted/raw
  copy before canonical authorization.
- Do not construct two Go callback owners, two writable canonical database
  runtimes, or a UI `ApplicationRoot` inside the worker.
- Do not acknowledge after only one direct/group page, one lane, or native show
  attempt. Settle both drains and every ready display/reconciliation row first.
- Do not call a WorkManager scheduling test proof of the secure recovery engine.
- Do not force-stop the app for closure. A user force-stop is an Android OS
  stop state and is outside the process-death guarantee.
- Do not require manual taps, notification-card taps, or human locale changes.

Deferred / accepted difference:

- **OEM launcher badges** -> separate future OEM/device-lab plan. Plan 331
  implements Android notification `number` only.
- **iOS parity** -> separate future iOS plan, likely manually verified because
  iOS notification automation is painful. No iOS target blocks this plan.
- **Legacy truly identity-free payload** -> accepted safe difference: silent,
  generic, privacy-safe, one stable conversation card, and generation-cancellable
  for a message; no new reaction banner for an identity-free reaction. Exact
  event binding is impossible without an authenticated canonical identity.
- **Exact scheduling latency under Doze/vendor policy** -> Android controls the
  execution window. The plan proves persistent queued work and eventual
  execution when constraints are granted, not a wall-clock push SLA.

Dependencies:

- Gate H0 precedes headless production edits. DB v107/direct custody precedes
  final headless convergence because the worker must not recover direct data
  into the old display hole.
- Current identity database version is v106; Plan 331 exclusively reserves
  v107 for direct notification durability. Headless/history/health/localization
  introduce no additional SQLCipher version.
- WorkManager `2.11.2` plus its test artifact is added to the Android module;
  application minSdk 24 satisfies the library's API23 floor.
- Expedited execution on API24-30 supplies a stable worker `ForegroundInfo`,
  recovery channel, `dataSync` service type, and merged-manifest proof; failure
  to enter the foreground service retains work rather than crashing or acking.
- DB v107 is a one-way release floor. A v106 binary must continue to fail closed
  against v107; rollback means a forward v107-compatible fix or explicit
  profile reset/restore, never an old-binary downgrade. Account transfer is
  supported only v107-to-v107; cross-version manifests reject atomically and
  clean staging sidecars.
- The headless entry point must use production identity/key, account-migration,
  relay, direct drain, group drain, notification, and database factories without
  importing any UI composition.

## Evidence Gates Before Production Rollout

### Gate H0 — Plan 331A headless runtime ownership (blocking)

**Execution result:** passed on both pinned Android targets. This unblocks use
of the broker/lease foundation; it does not by itself make the production
recovery graph safe or activate recovery work.

Before changing the headless worker behavior, Plan 331A required all of these
on both Android targets. Independent scheduler/localization and non-headless
Dart slices did not satisfy or bypass this gate:

1. A secondary Flutter engine can register secure storage, SQLCipher, local
   notifications, Firebase core/messaging prerequisites, and the app-owned Go
   bridge without creating `MainActivity` or `ApplicationRoot`.
2. `GoRuntimeHost` initializes the Go singleton callback exactly once per
   process and issues generation/owner tokens. Ownership transitions
   `ACTIVE -> DRAINING -> RELEASED`; every MethodChannel admission **and** late
   result/callback is fenced, and transfer waits for in-flight JNI work and the
   callback queue to drain.
3. Foreground arrival asks the worker to yield, waits for a safe page/transaction
   boundary plus Go quiescence, then receives callback ownership exactly once.
   Long `StartNode`, Stop-during-Start, callback-at-transfer, result-at-transfer,
   and DB-close failure are causal tests. Timeout never forces transfer.
4. Only the lease owner may open the production database writable, including
   the foreground open currently performed before Go startup. FlutterFire is
   concurrent but read-only/no-Go. Worker stop,
   timeout, account migration, transport failure, or foreground takeover closes
   DB/node/plugins and retains the native generation for retry.
5. One worker run either exhausts both inboxes inside the Android budget or
   records restart-safe page continuation and returns retry. It never reports
   success after a partial drain.

Plan 331A is the dedicated runtime prerequisite and is now device-verified.
Production activation is separately held by the composition seams in “Current
Implementation And Remaining Safety Gate”; do not substitute WorkManager
plumbing for that graph.

### Gate I0 — producer preservation and event-identity honesty

- First prove current relay group/direct message and reaction producers retain
  outer canonical IDs for every decryptable ciphertext, using a
  `TestRelayNotificationClosure_...` test or an exact Go command that the
  curated lane actually runs.
- Then use an explicit test-only transport interceptor that removes only the
  outer ID while retaining authentic ciphertext. Prove production-format
  group/direct encrypted fixtures expose the canonical
  inner ID after authentication when the outer ID is removed. Promote only that
  exact value after conversation/sender parity checks.
- If a current non-legacy producer can emit neither outer nor authenticated
  inner ID, stop and return that producer to `$tdd-review` for an authenticated
  protocol field. Do not invent a relay-only identity in execution.
- Existing intentionally oversize relay fixtures must demonstrate either inner
  identity recovery or the documented silent generic terminal. The plan does
  not claim the latter is exact.

## Test Contract

Use zero empty cells. Every causal test is written and observed red for its
named reason before its production seam is added; TC-331-15/24 are explicit
GREEN preservation sentinels.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-331-01 | `onDeletedMessages` commits account-bound generation before enqueueing one connected-network unique recovery job; denied notification permission still schedules; expedited API24/30 work supplies valid `ForegroundInfo`/`dataSync` merged service | `DroppedPushRecoveryWorkSchedulerTest::deleted batch commits then enqueues unique connected work` and `::expedited work has pre Android 12 foreground contract`, plus `MknoonFirebaseMessagingServiceTest` | Kotlin/Robolectric API24/30/34 + WorkManager test driver | HEAD has no work request/foreground contract -> one coalesced request references committed binding/generation | enqueue before commit, skip when permission denied, omit foreground info/service type, or use non-unique work -> red | exact Gradle command; AUTO under `native.android.unit` |
| TC-331-02 | Plan 331A process-global Go callback and writable DB broker drain in-flight work, fence stale admission/result/callback, and transfer only after explicit DB close | Plan 331A H0-01..08, including real `scripts/run_android_canonical_runtime_h0_probe.sh` on both Android IDs | Kotlin/Go/Dart host plus real two-engine Go AAR/SQLCipher/no-Activity probe | HEAD initializes per engine and foreground DB bypasses lease -> one `ACTIVE -> DRAINING -> RELEASED` owner | force transfer, miss late result/callback, Stop-during-Start, destroy before DB close, or let FlutterFire own Go/write -> red and Plan 331 remains blocked | Plan 331A exact gates; mandatory prerequisite, never conditional |
| TC-331-03 | shared runtime order is lease -> migration gate -> identity/key load -> writable DB -> Go/node -> direct full drain -> group full drain -> display/reconciliation settlement -> exact ack -> close/release | `test/core/notifications/canonical_recovery_runtime_test.dart::full recovery acknowledges only after both canonical drains and projection settle` | Dart host call log with paged drains/failpoints | HEAD has only main-runtime coordinator -> exact ordered runtime with retained outcomes at every failpoint | acknowledge after direct only, before projection, or release lease before DB close -> red | focused new; AUTO core + explicit `1to1` and `groups` arrays |
| TC-331-04 | foreground arrival during every boundary yields only after Plan-331A quiescence; newer account-bound generation and unfinished pages survive stale completion | `headless_recovery_foreground_handoff_test.dart::foreground takeover preserves sole owner and newer work` plus `DroppedPushRecoveryWorkSchedulerTest::generation arriving during active work is resnapshotted` | Dart controlled completers + native broker fake | HEAD has no handoff/resnapshot -> no lost/duplicate events and newest work promptly reruns | swap without quiescence, keep stale WorkRequest input, stale-ack success, or strand B behind `KEEP` -> red | focused core + both curated lanes and Plan 331A |
| TC-331-05 | worker maps success/retry/cancel/timeout/migration outcomes truthfully; `doWork` `try/finally` owns bounded cleanup on main looper while `onStopped` only signals cancellation | `HeadlessCanonicalRecoveryWorkerTest::worker result cleanup and threading are truthful` | Kotlin worker harness + fake engine/runtime channel | HEAD has no worker -> success only for exact current binding/generation | map stop/timeout to success, destroy engine off main, perform async cleanup only in `onStopped`, or ack after cancel -> red | exact Gradle; AUTO `native.android.unit` |
| TC-331-06 | immediate and six-hour/one-hour-flex periodic work are installation-unique; each attempt resnapshots current binding/generation, loops within budget or retries on advance, and cutover retires A without touching B; periodic sweep fabricates no marker/ack | `DroppedPushRecoveryWorkSchedulerTest::periodic sweep is unique bounded and account gated`, `::new generation during active work is not stranded`, `DroppedPushRecoveryStoreTest::account rotation retires stale work`, and `canonical_recovery_runtime_test.dart::periodic reason drains without native acknowledgement` | Kotlin WorkManager fake clock/process-recreate + Dart call log | HEAD has no scheduling/binding -> bounded newest-generation semantics | plain `KEEP` with stale input, duplicate per resume, fabricate marker, or run/ack A under B -> red | exact Gradle/Dart + source/manifest; emulator reboot proof is device-only, not inferred from fake DB |
| TC-331-07 | DB v106 -> v107 adds direct identifier-only display/read/reconciliation plus a **separate typed direct reaction terminal/ack authority**; it never infers lane from shared `message_reactions`; fresh/upgrade/reopen/repair/run-twice/import/cleanup are exact | `107_direct_notification_durability_test.dart`, `full_migration_chain_test.dart`, `migration_database_schema_inventory_test.dart`, and migration import/cleanup suites | host migration DB + schema/trigger/import inventory | HEAD v106/tables absent -> v107 exact rows and one-way floor | reuse shared reaction terminal columns, omit registry/index/trigger/sidecar cleanup, add plaintext/FK, or make rerun diverge -> red | focused core + completeness + core family; real SQLCipher TC-331-22 |
| TC-331-08 | fresh direct message acquires not-ready custody before canonical save, promotes ready only after commit, keeps ready after display throw, and duplicate/restart retries exactly once from current state | `test/features/conversation/application/direct_notification_display_outbox_wiring_test.dart::message marker first survives display throw and duplicate replay` plus `chat_message_listener_test.dart` | host real DB/failpoints + throwing notification fake | HEAD save/show throw loses alert -> ready row and one retry | stage after save, clear on throw, or duplicate-return before reconciliation -> red | focused feature; AUTO + explicit `1to1` |
| TC-331-09 | fresh direct reaction ADD uses the same custody through the actual live `ReactionListener` stream and staged path; REMOVE/stale/replay do not alert | `handle_incoming_reaction_use_case_test.dart::fresh add custody survives show failure`, `reaction_listener_test.dart::live stream retains custody across throwing show and restart`, and a production bootstrap composition lock | host DB + real listener stream/LWW fixtures | HEAD live listener omits display deps/unawaited handler -> one owned retry | call handler directly in the only proof, retain `unawaited`, omit production deps, or alert REMOVE -> red | focused feature; manually register `reaction_listener_test.dart` in `ONE_TO_ONE_TESTS` |
| TC-331-10 | every production direct-read entry atomically marks canonical state, records exact push-before-inbox acknowledgements, and enqueues peer reconciliation; startup drains it; later B/unrelated peer/group survives | `direct_notification_read_projector_test.dart::read acknowledges exact generation and preserves later sibling`, a real-DB `mark_conversation_read_use_case_test.dart::production read journals and drains reconciliation`, and source/composition locks for Conversation/Feed/Orbit callers | host SQL transaction + real use case/keyed interleavings | HEAD callers use plain mark-read -> exact durable wired read/reopen/cancel | leave standalone projector unused, kind-wide ack, metadata outside lane, or stable-ID cancel without generation CAS -> red | focused core/feature; `1to1` + baseline/core family |
| TC-331-11 | direct delete/contact delete/block/archive/reaction REMOVE coalesces restart-safe reconciliation; projector chooses newest remaining eligible message/reaction or cancels exact generation; unknown materialization retries | `test/features/conversation/application/direct_notification_reconciliation_wiring_test.dart::all policy mutations rebuild one peer card` | host real DB triggers/repositories + generation registry | HEAD leaves unmanaged visible card -> tri-state rebuild/retire | treat absence as delete, omit one trigger, rebuild from snapshot copy, or cancel a colliding group card -> red | focused feature/core; explicit `1to1` |
| TC-331-12 | background direct pre-show and post-show checks bind exact canonical read/policy/current reaction; show failure transfers custody to staged replay; genuine unread relay recovery may notify while already handled/read/viewed rows stay silent | `background_message_handler_test.dart`, `background_message_handler_staging_test.dart`, and `live_direct_notification_integration_test.dart::recovered unread direct row consumes display custody` | host RemoteMessage + staged envelope + real DB/claims | HEAD releases display failure and suppresses all replay -> one canonical eligible alert, no duplicate/tone leak | keep unconditional `suppressNotification:true`, omit post-show fence, or notify read/claimed row -> red | focused push/integration; `1to1` + feature family |
| TC-331-13 | same message/event IDs cannot cross **notification** outbox, typed direct reaction terminal authority, acknowledgement, read, registry generation, or cancellation lanes; the pre-existing shared canonical reaction-key limitation is not mislabeled fixed | `direct_group_notification_lane_isolation_test.dart::same ids remain notification kind and peer scoped` plus a preservation test documenting the shared canonical limitation | host real DB with colliding identifiers/cards | HEAD direct has no typed lane -> independent notification outcomes | infer lane from shared `message_reactions`, omit peer/kind, or share reconciliation key -> red | exact shared test in both `1to1` and `groups`; canonical reaction re-key is deferred to a dedicated plan |
| TC-331-14 | an explicit test-only outer-ID-removal mutation promotes authenticated inner message/reaction identity after parity, stages/promotes durable custody **after decrypt**, and then uses exact claim/read/route/post-show fences; normal relay producers retain outer IDs | `push_decrypt_preview_test.dart::authenticated inner id anchors test-mutated missing outer id`, `background_message_handler_test.dart::inner identity reaches staged custody and post show fence`, and `TestRelayNotificationClosure_DecryptablePayloadRetainsCanonicalOuterIdentity` | production-format encrypted fixtures + transport interceptor + Go producer proof | HEAD stages/guards before decrypt and discards inner ID -> post-decrypt `ResolvedPushEventIdentity.authenticatedInner` | keep early staging return, trust mismatched fields, use FCM ID, or let relay drop ID while ciphertext remains -> red | focused push + exact relay Go; explicit `groups` and `1to1` |
| TC-331-15 | message payload with neither outer nor authenticated inner ID remains silent, generic, private, stable, unclaimed as exact, and current generation cancels on live open; equivalent reaction emits no new reaction banner and awaits canonical reconciliation | existing/extended `background_push_notification_fallback_test.dart::truly identity free fallback remains safe only`, `background_message_handler_test.dart::identity free reaction does not alert`, and `group_notification_read_projector_test.dart::live open cancels current unanchored generation` | host RemoteMessage + registry generation | GREEN safe message baseline/current reaction rejection -> unchanged while recoverable subset becomes exact | synthesize canonical ID, make audible, include preview copy, alert identity-free reaction, or prevent live cancel -> red | preservation exact + `groups`/`1to1` |
| TC-331-16 | one canonical snapshot returns newest five eligible unread lines plus uncapped total and is passed by actual direct/group listener/reconciler/background production paths | `conversation_notification_snapshot_test.dart::bounded direct and group unread projection` plus real-DB direct/group listener/reconciler-to-plugin tests and bootstrap resolver composition lock | host real DB + actual producers, privacy/text/media fixtures | HEAD loads newest only -> production plugin receives bounded history/full count | helper-only implementation, drop resolver in bootstrap, reverse/count-five/include raw copy -> red | focused core/feature; both curated lanes |
| TC-331-17 | notification service publishes one stable card with latest body, InboxStyle history and Android `number`; 0 cancels/omits, 1/N replace in place; reaction headline does not increment count | `flutter_notification_service_test.dart::android conversation card carries canonical history and number` plus the TC-16 end-to-end producer/reconciliation tests | mocked plugin MethodChannel + real registry/producer wiring | HEAD details/callers lack history/number -> exact platform map/stable ID | DTO-only change, per-message ID, cap number at five, or increment for reaction -> red | focused core; core family + both lanes |
| TC-331-18 | registration health secure record is versioned, installation/account bound, corrupt-safe, contains no token/raw exception, survives restart, and is `clearRegenerate`/non-exported | `test/features/push/infrastructure/push_registration_health_store_test.dart` and `migration_secure_storage_registry_test.dart` | host fake SecureKeyStore + restart/corrupt/registry fixtures | HEAD has no record -> safe normalized durable state | persist token/error, migrate it, trust corrupt version, or reuse another account's state -> red | focused feature/account migration; feature family + move preservation exact |
| TC-331-19 | coordinator persists checking/healthy/retrying/permissionDenied transitions; permission denial warns now; noToken/relay/exception warns after 3 failures or 24h from first unresolved failure/last success; migration-blocked is neutral; success clears live | extended `push_registration_coordinator_test.dart::durable health threshold and live recovery` | host fake clock/store/stream/concurrent attempts | HEAD state disappears on restart -> exact monotonic state/threshold | mark first transient failure unhealthy, count migration block, fail to clear, or let concurrent attempt regress success -> red | focused existing; feature family |
| TC-331-20 | one health surface centralized above all authenticated Feed/Orbit/Settings construction routes localizes action, retries/opens settings, clears live, and preserves short-screen reachability | `push_registration_health_surface_test.dart::all authenticated routes expose one live warning`, source/composition census for all Feed/Orbit/Settings constructors, `feed_wired_test.dart`, `orbit_wired_test.dart`, and Settings reachability tests | Flutter route/widget tests en/de/ar + live notifier/gateway + 390x844/390x667 | HEAD has no surface -> every production route shares one owner | standalone widget only, omit QR/FTE/intro/embedded/Posts route, duplicate banners, wrong action, or overflow -> red | register cross-surface test in `FEED_TESTS`; run `feed`, feature family, baseline |
| TC-331-21 | native recovery channel/title/body use complete default/de/ar resources; unsupported locale falls back; recreating same channel refreshes localized name/description while preserving ID/importance | extended `MknoonFirebaseMessagingServiceTest.kt::recovery copy follows locale and refreshes channel` plus `test/core/notifications/android_recovery_string_resources_test.dart` | Robolectric LocaleList/API24/26/33 + host XML key parity | HEAD hard-coded English/no XML -> exact localized card/channel | hard-code one phrase, omit default/key, allocate new channel ID, or skip channel refresh -> red | exact Gradle AUTO in `native.android.unit`; XML test AUTO core |
| TC-331-22 | real v106 -> v107 SQLCipher proves upgrade, partial repair, reopen/run-twice, wrong-key, refused downgrade with v107 data intact, v107->v107 export/stage/active import, success/failure/cancel sidecar cleanup, and direct/group notification isolation on each Android target | `direct_notification_durability_sqlcipher_proof_test.dart`, migration import/cleanup host suites, and Plan-331A two-engine SQLCipher probe | real `sqflite_sqlcipher` on USB API36/emulator API37 | HEAD v107 absent -> exact one-way/import/cleanup proof | host/plain SQLite, old-binary compatibility claim, cross-version import, omitted cleanup/reopen, or second writer -> red | direct both-ID commands; v106<->v107 manifest rejection is expected and data-preserving |
| TC-331-23 | paired Android/real-relay campaign covers real direct/group recovery, history/count, health, and en/de/ar; the missing-outer-ID row is a separately labeled test-only mutation, never an ordinary relay claim | `run_android_notification_recovery_completion.dart` + strict artifact validator | central production-FCM APK, USB Pixel + emulator, real relay, deterministic debug seams | source lacks scenario; current shell also lacks required relay/FCM sender credentials -> semantic artifact after preflight | accept shell exit only, relabel mutation as real relay, launch UI for headless row, force-stop, omit OS card, or use iOS -> red | `notifications.android_recovery_completion` Sims capability; closure blocked until credential preflight is provisioned |
| TC-331-24 | exclusions remain truthful: no Swift/APNs/iOS diff, no OEM badge dependency/claim, no plaintext outbox, no force-stop promise; Plan-330 group and existing direct privacy/tone/viewing behavior remain | `test/core/notifications/android_notification_completion_scope_contract_test.dart::plan 331 excludes ios oem plaintext and force stop` plus existing registry/tone/show/listener and Plan-330 focused suites | host source census + behavior sentinels | GREEN sentinel on HEAD -> remains green after every production wave | add iOS/OEM files, `ShortcutBadger`, plaintext column, blanket cancel, or force-stop criterion -> red | focused new AUTO core + `1to1`, `groups`, Sims manifest/binding |

### Test Notes

- TC-331-01/06 uses one install-scoped unique immediate chain, connected
  constraints, exponential backoff, and `ExistingWorkPolicy.APPEND_OR_REPLACE`.
  Each worker snapshots the latest account binding/generation only when it
  begins; stale queued successors become bounded no-ops. A generation arriving
  while A runs therefore always leaves a successor and cannot fall into the
  `KEEP` terminal race. The unique periodic request uses update semantics.
  Deleted-batch work requests expedited
  execution with `RUN_AS_NON_EXPEDITED_WORK_REQUEST` quota fallback. The
  periodic request is six hours with one-hour flex. Repeated deleted batches
  may append coalesced serial successors but never run parallel recovery owners.
- TC-331-02/04 is the non-negotiable Plan-331A discriminator: the stable Go
  callback belongs to the native host, while an engine receives an owner token.
  Admission, in-flight JNI completion, callback delivery, result delivery, DB
  close, and engine destruction all participate in the drain state machine.
- TC-331-03 acknowledges only after direct and group pagination both report
  truthful exhaustion and display plus reconciliation coordinators have no
  eligible ready work. Unknown canonical materialization returns retry. The
  runtime uses an eight-minute cooperative deadline inside WorkManager's normal
  ten-minute budget; unfinished cursor/outbox state remains durable for retry.
- TC-331-06 gives the worker an explicit reason: `deletedBatch(generation)`
  performs compare-and-ack, while `periodicSweep` performs the same canonical
  drains/settlement with no native generation and therefore no fabricated
  acknowledgement or recovery-card cancellation.
- TC-331-07 mirrors v106's identifier-only/no-FK design but scopes direct rows
  by `peer_id` and `event_kind`. Add
  `messages.notification_display_terminal_event_id` and a separate
  `direct_notification_reaction_terminal_events` identifier-only authority;
  never infer direct/group ownership from the untyped shared
  `message_reactions` row. Add
  `direct_notification_display_outbox`,
  `direct_notification_read_acknowledgements`, and
  `direct_notification_reconciliation_outbox` with bounded indexes/triggers.
- TC-331-08/09 marker acquisition occurs after authorization/policy but before
  canonical mutation. Marker failure leaves the relay/staged owner retryable;
  canonical failure leaves a not-ready marker; native failure leaves a ready
  marker. No plugin call occurs inside a SQL transaction.
- TC-331-10/12 intentionally changes one old boundary: genuine recovered
  direct rows are no longer blanket-silent. Exact event claims, canonical read,
  viewing, archive/block, and display custody decide whether they alert.
- TC-331-14 uses only authenticated plaintext and a named test-only transport
  mutation. Outer and inner IDs must match
  when both exist; mismatch is terminally rejected/fail-closed, not silently
  preferred.
- TC-331-16 history contains unread incoming **messages**. A current eligible
  reaction may replace the card's headline/body, while total and history remain
  derived from unread messages because reaction state has its own read policy.
- TC-331-18 stores a safe reason enum, schema version, account/install binding,
  consecutive failures, first failure, last attempt, and last success only.
  Secure-store write failure is logged but cannot change the real
  token-registration result.
- TC-331-20 uses one reusable durable warning view model owned above the route
  constructors, not optional parameters independently threaded through each
  Feed/Orbit/Settings caller. Permission denial's
  action opens Android app-notification settings through a testable gateway;
  relay/token failures call `retryNow`.
- TC-331-21 keeps `RECOVERY_CHANNEL_ID` stable. Recreating the same channel
  updates app-owned localized name/description while retaining Android's user
  channel preferences.
- TC-331-23 cannot make real FCM emit `onDeletedMessages` deterministically.
  Robolectric invokes the real override; the device campaign invokes a
  debug/instrumentation seam immediately after the same durable marker commit
  and then proves the real worker/runtime/relay/SQLCipher/card boundary. It may
  not relabel ordinary FCM delivery as a deleted-batch proof or relabel the
  outer-ID-removal interceptor as a normal relay payload. The campaign remains
  unclosed until relay/FCM sender credentials pass Sims preflight.

## Implementation Steps

1. Snapshot `git status --short`; preserve the user-owned Plan/Index changes,
   record the exact baseline and live Android IDs, and add causal scheduler,
   direct, projection, health, and localization REDs before their seams.
2. Execute Plan 331A exactly. Its real no-Activity/two-engine Go/SQLCipher probe
   on both Android IDs—not a Flutter integration-test Activity—is the only H0
   pass. Stop the headless worker if any drain/lease/plugin invariant fails;
   scheduler/localization and other independent slices may continue.
3. Add DB v107 migration/registry/schema inventory and TC-331-07/22 causal
   tests. Assert `PRAGMA user_version` 106 before and 107 after, exact table/
   index/trigger definitions, legacy sentinel preservation, fresh install,
   partial repair, upgrade/reopen, wrong-key refusal, run-twice idempotency,
   v107 data-preserving downgrade refusal, v107->v107 import, cross-version
   manifest rejection, and success/failure/cancel sidecar cleanup. Use separate
   typed direct reaction terminal facts; do not reuse untyped shared reaction
   authority.
4. Add direct marker/repository/retry/reconciliation/read projector. Stage
   messages and fresh reaction ADDs marker-first, promote after canonical
   commit, preserve ready custody after native error, bind every direct show/
   cancel to the per-peer keyed lane and typed registry generation, and wire
   cleanup/account import. Replace every Conversation/Feed/Orbit read caller
   through the atomic use-case/repository seam and add startup drain proof.
5. Replace blanket-silent direct staged recovery with current canonical policy:
   claimed/read/viewed/archived/blocked rows remain silent; genuinely unread
   eligible recovered rows retain display custody and alert once. Add direct
   background pre/post-show fences and actual live `ReactionListener`
   dependencies plus a production-composition lock.
6. **PARTIAL / SAFETY-GATED:** the abstract `CanonicalRecoveryRuntime`, native
   worker, scheduler, result protocol, and fail-closed AOT entry point are
   implemented; the production non-UI graph and activation are not. Build the
   production runtime from the seven seams listed in “Current Implementation
   And Remaining Safety Gate”. Add
   WorkManager `2.11.2`, serial `APPEND_OR_REPLACE` immediate work plus updated
   periodic scheduling, API24-30 `ForegroundInfo`, the
   dedicated `@pragma('vm:entry-point')` Dart entry point/worker result channel,
   process lease, foreground-priority yield, restart-safe continuation,
   reason-typed deleted-batch versus periodic execution, account-binding checks
   before acquire/ack, latest-generation resnapshot, and `doWork`-owned cleanup.
   Keep the native recovery card until full deleted-batch success; cancel it
   only after exact acknowledgement. Do not set `activateRecoveryWork:true`
   while the production session/ingress/projection graph is absent.
7. First add a relay closure-prefixed producer-ID preservation test. Then use a
   named test-only transport interceptor to remove only the outer ID; promote
   authenticated inner identity after decrypt/parity and move staging,
   eligibility, claim, route, post-show fencing, and custody after resolution.
   Preserve the truly identity-free silent generic fallback.
8. Add one direct/group `ConversationNotificationSnapshot` contract that loads
   total unread count and the latest five privacy-normalized lines. Extend
   notification descriptors/services/details with immutable history/count and
   Android InboxStyle/`number`; recompute after every read/delete/policy/
   reaction reconciliation rather than storing a second history copy. Prove
   real DB -> actual direct/group producer/reconciler -> plugin wiring.
9. Add `PushRegistrationHealthStore` and repository/stream; register its key as
   installation-local `clearRegenerate`. Persist coordinator terminal outcomes,
   threshold transient warnings, expose manual retry/settings action, and own
   one reusable localized warning above all authenticated Feed/Orbit/Settings
   construction routes without breaking viewport/reachability.
10. Add Android `values/strings.xml`, `values-de/strings.xml`, and
    `values-ar/strings.xml`; replace every recovery literal with `getString` and
    refresh the same channel on each recovery event.
11. Register all shared tests in affected curated arrays: live reaction in
    `ONE_TO_ONE_TESTS`, the cross-surface health proof in `FEED_TESTS`, and
    shared projection/lane tests in both 1:1/groups; confirm Kotlin
    tests auto-enter the existing `native.android.unit` Gradle capability and
    the resource test auto-enters core; register v107 integration paths in
    discovery and one
    strict `notifications.android_recovery_completion` Sims capability with
    proof binding. Do not add iOS or OEM rows.
12. Run focused GREEN and representative mutation/re-red per wave; then exact
    Report-41/48 sentinels, `1to1`, `groups`, `feed`, pinned `baseline` and
    `transport`, justified core/feature families, analyzer,
    diff hygiene, and incremental Graphify refresh. Do not run per-plan
    `host-all`.
13. Run real SQLCipher on each pinned Android. Build one central production-FCM
    APK and execute the fully automated paired campaign in both receiver roles
    where feasible. Record source/APK/device/relay/artifact digests and reject
    any result requiring UI launch in the headless row, manual taps, force-stop,
    iOS, or OEM badge inspection.

## Risks And Blind Spots

- Second Flutter engine steals Go callbacks or overlaps a DB writer -> Gate H0,
  TC-331-02/04/05/22.
- A late JNI result/callback crosses a nominal token handoff -> Plan 331A drains
  in-flight calls/results/callbacks and refuses forced transfer.
- FlutterFire's same-process background engine bypasses the ownership model ->
  explicit read-only/no-Go third-engine matrix in Plan 331A.
- Worker exceeds Android's normal execution budget during large inbox recovery
  -> bounded pages, restart-safe continuation, cooperative stop, TC-331-03/05.
- FCM never emits `onDeletedMessages` for a silent loss -> bounded periodic
  canonical sweep, TC-331-06; latency remains OS-controlled and explicit.
- A newer generation arrives after A starts/acks but before WorkManager marks A
  terminal -> serial `APPEND_OR_REPLACE` successor plus begin-time resnapshot,
  TC-331-04/06.
- Account cutover runs an old install-global marker under a new identity ->
  bound marker and pre-acquire/pre-ack checks, TC-331-06.
- Direct marker ordering repeats the pre-Plan-330 crash hole -> marker-first
  failpoints and mutation tests TC-331-08/09.
- Shared `message_reactions` cannot encode a direct/group lane -> never use it
  as direct notification terminal authority; keep separate typed direct facts
  and explicitly defer canonical reaction re-keying, TC-331-07/13.
- Replay change creates duplicate or stale direct banners -> exact claim/read/
  post-show fences and TC-331-10/12.
- Decrypted inner ID is trusted before authentication or mismatches outer data
  -> parity/fail-closed fixtures TC-331-14/15.
- History leaks private content or reports five instead of the full count ->
  canonical privacy/count matrix TC-331-16/17.
- Reaction headline incorrectly inflates unread count -> TC-331-16/17.
- Health warning nags on transient outage or migrates stale device state ->
  threshold/account binding/clearRegenerate TC-331-18/19/20.
- Secure-store failure changes actual registration semantics -> coordinator
  result/store-failure row in TC-331-19.
- Android channel keeps old language after locale change -> channel recreation
  with same ID and TC-331-21.
- API24-30 expedited work cannot enter its foreground service -> stable
  `ForegroundInfo`, dataSync merged-service proof, and retry/retain tests.
- v107 has no supported old-binary downgrade -> one-way floor, data-preserving
  refusal, v107->v107 import, and forward-fix/reset recovery contract.
- Device proof fakes provider deletion -> separate real override host proof and
  same-marker device seam, strict artifact vocabulary TC-331-01/23.
- Real relay/FCM credentials remain absent from this shell -> source/host/native/
  SQLCipher execution continues, but TC-331-23 and overall closure stay open
  until Sims preflight is provisioned.
- Lifecycle / derived-state durability: worker/foreground ownership, direct
  outbox, unread rebuild, and health restart are covered by TC-331-02..20.
- Sibling-surface consistency: direct/group share snapshot/details while their
  exact custody tables stay collision-isolated; TC-331-13/16/17.
- Destructive-action side effects: read/delete/block/archive cancels only exact
  typed generation and preserves unrelated conversations; TC-331-10/11/13.
- Invariant re-verification under new transitions: Plan-330 group sentinels,
  account migration, private media, tone/viewing, and exclusions are TC-331-24.

## Gate Cadence

- Per wave: causal focused tests, exact preservation sentinels, and only the
  affected curated lane. DB/runtime/shared projection waves run both `1to1` and
  `groups`; automatic direct-drain waves also run Report-41/48 sentinels plus
  pinned `baseline`/`transport`; registration/root-warning waves run `feed` and
  direct Feed/Orbit tests; localization runs focused native/core.
- Per-plan closure: all focused TCs, v107 migration chain, native Kotlin/
  resource tests, real SQLCipher on both Android targets, `1to1`, `groups`,
  `feed`, pinned `baseline`, pinned `transport`,
  justified `core-host-all --dart-only --batch-flutter --concurrency 4
  --reporter failures-only`, justified `feature-host-all --dart-only
  --batch-flutter --concurrency 4 --reporter failures-only`, and the registered
  paired Android Sims capability.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Plan-330/331 Android
  notification dependency wave is complete, and once at final rollout/release
  closure.
- Shared tests outside feature/core globs: exact Kotlin, Go-owner (if Go changes),
  resource parity, SQLCipher integration, Sims manifest/binding, discovery, and
  paired-device commands below. They remain registered for the later wave-level
  `host-all` where applicable.

## Acceptance Gates

```bash
git status --short

# Causal RED after adding tests but before each production seam; non-zero for
# the named missing scheduler/owner/runtime/migration/custody/projection/UX/copy.
./android/gradlew -p android :app:testDebugUnitTest --tests 'com.mknoon.app.DroppedPushRecoveryWorkSchedulerTest'
./android/gradlew -p android :app:testDebugUnitTest --tests 'com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest'
# Plan 331A owns the mandatory Go/DB broker RED/GREEN and real no-Activity H0
# commands; all of its acceptance gates must pass before worker production code.
flutter test test/core/notifications/canonical_recovery_runtime_test.dart
flutter test test/core/notifications/headless_recovery_foreground_handoff_test.dart
flutter test test/core/database/migrations/107_direct_notification_durability_test.dart
flutter test test/features/conversation/application/direct_notification_display_outbox_wiring_test.dart
flutter test test/features/conversation/application/reaction_listener_test.dart --plain-name 'live stream retains custody across throwing show and restart'
flutter test test/features/conversation/application/direct_notification_reconciliation_wiring_test.dart
flutter test test/core/notifications/direct_notification_read_projector_test.dart
flutter test test/core/notifications/direct_group_notification_lane_isolation_test.dart
flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'authenticated inner id anchors missing outer id'
flutter test test/core/notifications/conversation_notification_snapshot_test.dart
flutter test test/features/push/infrastructure/push_registration_health_store_test.dart
flutter test test/features/push/application/push_registration_coordinator_test.dart --plain-name 'durable health threshold and live recovery'
flutter test test/features/push/presentation/push_registration_health_surface_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test test/core/notifications/android_recovery_string_resources_test.dart

# Focused GREEN and exact preservation; exit 0, zero failed tests.
./android/gradlew -p android :app:testDebugUnitTest --tests 'com.mknoon.app.DroppedPushRecovery*Test' --tests 'com.mknoon.app.MknoonFirebaseMessagingServiceTest' --tests 'com.mknoon.app.GoRuntimeHostTest' --tests 'com.mknoon.app.HeadlessCanonicalRecoveryWorkerTest'
flutter test test/core/notifications/dropped_push_recovery_bridge_test.dart
flutter test test/core/notifications/dropped_push_recovery_coordinator_test.dart
flutter test test/core/notifications/canonical_recovery_runtime_test.dart
flutter test test/core/notifications/headless_recovery_foreground_handoff_test.dart
flutter test test/core/database/migrations/107_direct_notification_durability_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart
flutter test test/features/account_migration/application/migration_database_schema_inventory_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart
flutter test test/features/conversation/application/direct_notification_display_outbox_wiring_test.dart
flutter test test/features/conversation/application/direct_notification_display_retry_coordinator_test.dart
flutter test test/features/conversation/application/direct_notification_reconciliation_wiring_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart
flutter test test/features/conversation/application/reaction_listener_test.dart
flutter test test/core/notifications/direct_notification_read_projector_test.dart
flutter test test/core/notifications/direct_group_notification_lane_isolation_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
flutter test test/features/push/application/background_message_handler_staging_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
flutter test test/features/push/application/push_decrypt_preview_test.dart
flutter test test/integration/live_direct_notification_integration_test.dart
flutter test test/core/notifications/conversation_notification_snapshot_test.dart
flutter test test/core/notifications/flutter_notification_service_test.dart
flutter test test/features/groups/application/group_notification_reconciliation_wiring_test.dart
flutter test test/features/push/infrastructure/push_registration_health_store_test.dart
flutter test test/features/push/application/push_registration_coordinator_test.dart
flutter test test/features/push/presentation/push_registration_health_surface_test.dart
flutter test test/features/settings/presentation/screens/settings_screen_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_test.dart
flutter test test/features/settings/presentation/screens/settings_one_screen_layout_test.dart
flutter test test/core/notifications/android_recovery_string_resources_test.dart
flutter test test/l10n/l10n_integrity_test.dart

# Existing callback-steal characterization is unconditional; producer identity
# proof uses the exact closure prefix consumed by curated lanes.
GOTOOLCHAIN=go1.25.0 go -C go-mknoon test ./bridge -run 'TestBB001InitializeUpdatesExistingCallbackForFutureGroupEvents|Test.*CallbackAdapter' -count=1
GOTOOLCHAIN=go1.25.0 go -C go-relay-server test ./... -run '^TestRelayNotificationClosure_DecryptablePayloadRetainsCanonicalOuterIdentity$' -count=1

# Registration and curated/family gates. No per-plan full host-all.
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh runtime-roots
FLUTTER_DEVICE_ID=21071FDF600CSC ./scripts/run_test_gates.sh baseline
FLUTTER_DEVICE_ID=21071FDF600CSC ./scripts/run_test_gates.sh transport
./scripts/run_test_gates.sh core-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_test_gates.sh feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only
./scripts/check_dropped_push_recovery_manifest_contract.sh
flutter test test/tool/sims/sims_manifest_test.dart test/tool/sims/sims_proof_binding_registry_test.dart
./scripts/test/reliability_simulation_discovery_contract_test.sh
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental

# Live matrix must still list both exact Android targets. Do not run simctl or
# select any iOS ID.
flutter devices --machine
adb devices -l

# Plan 331A real no-Activity/two-engine boundary on both targets.
./scripts/run_android_canonical_runtime_h0_probe.sh 21071FDF600CSC --handoff --process-death
./scripts/run_android_canonical_runtime_h0_probe.sh emulator-5554 --handoff --process-death

# FUTURE ACTIVATION GATE (unimplemented; not execution evidence): periodic-work
# persistence across emulator reboot. The eventual script must schedule,
# reboot, wait for boot, and validate the same unique request/account binding.
# ./scripts/run_android_recovery_reboot_probe.sh emulator-5554

# Real SQLCipher v106 -> v107 proof on each allowed Android target. Each test
# asserts PRAGMA before/after, sentinel preservation, reopen, and run-twice.
flutter test --no-pub -d 21071FDF600CSC integration_test/direct_notification_durability_sqlcipher_proof_test.dart
flutter test --no-pub -d emulator-5554 integration_test/direct_notification_durability_sqlcipher_proof_test.dart
# FUTURE ACTIVATION GATE (unimplemented; not execution evidence): the full
# production headless graph must gain this real SQLCipher proof on both targets.
# flutter test --no-pub -d 21071FDF600CSC integration_test/headless_canonical_recovery_sqlcipher_proof_test.dart
# flutter test --no-pub -d emulator-5554 integration_test/headless_canonical_recovery_sqlcipher_proof_test.dart

# One central production-FCM APK; fully automated physical+emulator campaign.
# This command is N/A until the strict Sims credential/relay preflight is
# provisioned; absence keeps TC-331-23/open overall closure, not host work.
SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC \
SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
dart tool/sims/sims.dart major --only notifications.android_recovery_completion
```

## Device/Relay Proof Profile

- Profile: `os-notification-device-lab`, paired Android with real relay.
- Boundary being proven: after Plan 331A proves a killed/no-Activity recipient
  process can safely own the runtime, it can run full secure
  direct+group catch-up without UI; direct display custody survives first-show
  failure/restart; a test-mutated outer-ID-missing authenticated payload becomes exact; one
  stable card carries bounded history/full count; registration warning retries
  and clears; native recovery copy follows en/de/ar.
- Live availability check: `flutter devices --machine && adb devices -l` on
  2026-08-03 -> USB Pixel 6 `21071FDF600CSC` Android 16/API36 and emulator
  `emulator-5554` Android 17/API37. iOS devices were listed by Flutter but are
  deliberately not selected or used.
- Required setup: one centrally prepared `android.production_fcm` APK; explicit
  physical/emulator roles; staging relay/FCM credentials; deterministic
  debug-only fault, recovery-marker, locale, unread, and registration-health
  seams excluded from release behavior; automated permission/navigation/
  process/notification-shade/dumpsys/assertion/cleanup control. The two device
  targets are available, but relay address/key and FCM sender credentials are
  not provisioned in the current shell; strict preflight must fail closed
  without printing values.
- Two-peer default: USB physical Android `21071FDF600CSC` plus Android emulator
  `emulator-5554`; reverse receiver role where the scenario remains stable.
- Closure role: required closure evidence for runtime/plugin/SQLCipher/OS-card/
  real-relay behavior. Host tests remain causal authority for every injected
  crash interleaving and for the real `onDeletedMessages` override.
- `FLUTTER_DEVICE_ID`: host selector only; insufficient for paired proof. Both
  explicit Sims environment IDs and each explicit `-d` SQLCipher ID are
  mandatory.
- Registration: add `notifications.android_recovery_completion` to
  `tool/sims/critical_features.json` with dependencies on the central
  `build.android.production_fcm`, physical/emulator, FCM, and relay capabilities;
  exclusive device/relay locks; central-APK read and artifact write locks; exact
  runner/validator; and hardcoded proof binding. Classify runner/validator as
  support-only and device SQLCipher `_proof_test.dart` paths as their intentional
  manual/device owner to prevent duplicate discovery.
- Discovery command: `flutter devices --machine && adb devices -l` -> both
  exact Android IDs must report `device` before execution.
- Closure command:
  `SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 dart tool/sims/sims.dart major --only notifications.android_recovery_completion`
  -> all semantic assertions pass, `manualTaps=0`,
  `notificationCardTaps=0`, `childBuildCount=0`, zero duplicates, and a valid
  artifact digest.
- Headless row: use the existing honest HOME -> `am kill` -> bounded `pidof`
  algorithm with `cmd activity stop-app` fallback and never `force-stop`; prove no
  Flutter activity/root is launched; queue one direct and one group event on
  the real relay; commit/schedule the native recovery generation through the
  deterministic test seam; wait for worker completion; verify canonical rows,
  ready custody settlement, cards, and exact generation acknowledgement before
  any UI launch. Start the UI during a second run to prove cooperative handoff
  and a newer generation surviving stale completion.
- Direct row: send text/photo/video/voice and reaction ADD; fail the first
  native show, kill the process, restart recovery, and assert exactly one stable
  peer card, privacy copy, tone coalescing, and exact read cancellation that
  preserves later B, another peer, and a deliberately colliding group ID.
- Identity robustness row: a debug-only transport interceptor removes only the
  outer ID from an authentic encrypted payload; label it synthetic and assert
  post-decrypt staging plus inner exact identity/claim/read fence. Separate relay
  producer proof asserts this shape is not emitted normally. A fixture with no
  authenticated identity remains silent/generic and cancels on live open.
- History/health/locale row: seed N canonical unread direct/group messages;
  assert one card, ordered bounded lines, and total `number=N` through `dumpsys
  notification --noredact`; drive health healthy -> transient -> threshold/
  permission denied -> retry -> healthy and assert warning/action/live clear;
  set en/de/ar plus unsupported fallback automatically, assert card/channel
  copy, and restore the original locale/state in teardown.
- Deferred device work: OEM badge behavior belongs to a separate OEM plan; iOS
  parity belongs to a separate likely-manual iOS plan. Neither is a Plan-331
  environment blocker or evidence gap.

## Execution Interpretation And Done Criteria

- Expected RED: each new test fails because the named scheduler, runtime host,
  v107 table/helper, direct ownership, inner-ID promotion, history/count,
  registration store/UI, resource key, or device capability does not exist—not
  because of a missing fixture, wrong selector, or unavailable iOS target.
- Green sentinel: Plan-330 group durability plus direct stable-ID/tone/viewing/
  privacy tests remain green while new direct/headless behavior passes.
- Pre-existing worktree: the user-owned modified `00-INDEX.md` and untracked
  Plan-331 draft were present and preserved. The app-code baseline is commit
  `1c7540b17954a423264e23ecf3528d3c01beeb0a`; no known code-test failure was
  recorded at planning time.
- Environment state: both required Android targets are live, so host/native/
  SQLCipher work is unblocked. Real-relay/FCM closure credentials are absent
  from this shell, so TC-331-23 remains preflight-blocked until provisioned.
  An unavailable Android version outside the discovered matrix is
  `N/A (target unavailable by project policy)`, not a closure requirement.
- Scope drift: any Swift/APNs/iOS edit, OEM launcher dependency/claim, plaintext
  outbox, force-stop promise, UI-dependent headless proof, guessed event ID,
  second Go/SQLCipher owner, or unregistered proof blocks completion and returns
  the plan to review.

- [x] Plan 331A/Gate H0 passes on both Android targets before headless rollout, with sole
      Go callback and writable SQLCipher ownership proven.
- [x] Every behavior has a named causal test or an explicit impossible/safe
      boundary; no generic fallback is mislabeled exact.
- [x] DB v107 migration passes fresh, v106 upgrade, PRAGMA before/after, schema/
      trigger/index inventory, legacy sentinel, reopen, run-twice, wrong-key,
      downgrade, import, and cleanup assertions.
- [x] Direct message and reaction display custody survives every marker/save/
      show/replay crash point and read/policy/delete/REMOVE reconciliation.
- [ ] Headless recovery truthfully exhausts direct and group drains, settles
      display/reconciliation, and exact-acks only the completed generation.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded
      for every landed production slice; the unactivated graph remains future work.
- [x] Preservation, Report-41/48 sentinels, `1to1`, `groups`, `feed`, pinned
      `baseline`/`transport`, justified core/feature families, native, l10n,
      Sims registration, analyzer, and diff gates pass semantically.
- [x] Real SQLCipher passes on physical `21071FDF600CSC` and emulator
      `emulator-5554`.
- [ ] The registered real-relay campaign passes with one APK, exact Android
      targets, zero child builds, zero manual/card taps, zero duplicates, and
      content-addressed evidence.
- [x] OEM badge and iOS/manual follow-up remain explicitly separate; no claim
      in this plan implies either is closed.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean; Graphify
      incremental refresh completes after coherent app-owned edits.
- [x] Scope Contract And Guard is respected.

## Handoff

- First prerequisite causal RED command (owned by Plan 331A): after adding the test, run
  `./android/gradlew -p android :app:testDebugUnitTest --tests 'com.mknoon.app.GoRuntimeHostTest'`;
  it must fail because sole tokenized foreground/headless ownership does not
  exist, not because Gradle cannot discover the test.
- Preservation commands: `./scripts/run_test_gates.sh 1to1`, `groups`, and
  `feed`, then pinned physical-Android `baseline` and `transport`.
- Manual registration: new shared runtime/lane tests in both curated arrays,
  actual live reaction in `ONE_TO_ONE_TESTS`, and root health in `FEED_TESTS`;
  Kotlin files are auto-discovered by the existing `native.android.unit`
  Gradle capability; the Dart resource test is AUTO core; v107 SQLCipher paths
  enter reliability discovery; add the new Sims capability plus manifest/proof
  binding. No iOS row.
- Migration: DB v107 `direct_notification_durability`; exact host migration
  suite plus both-device `direct_notification_durability_sqlcipher_proof_test.dart`.
- Boundary closure: host + Kotlin/Go ownership + real SQLCipher on USB/emulator
  + paired Android/real relay/OS-card campaign.
- Unresolved implementation/evidence: the seven-seam UI-neutral production
  recovery graph, its reboot/full-headless SQLCipher proofs, and the absent
  real-relay/FCM credential preflight. Plan 331A ownership is complete. Gate I0
  has an exact producer-preservation test and explicitly synthetic mutation
  contract.
- Review handoff: do not activate the headless slice until the production graph
  closes every safety seam and passes both-device proof; do not close the
  overall plan until that work plus credential preflight and TC-331-23 pass.

## Reviewer Findings

Verdict on the submitted draft: **`not-ready`**. Disposition:
**revise in place and split the runtime prerequisite**. The review used one
factual/core verifier, one native/Go verifier, and one migration/device verifier;
material findings were independently checked against current source and the
index before incorporation.

Confirmed blockers and applied changes:

1. Admission-only Go tokens could pass fake tests while late JNI results or Go
   callbacks crossed handoff; foreground SQLCipher also opened before the
   proposed lease. Plan 331A now owns a drain-state broker and real two-engine,
   no-Activity SQLCipher proof, including the FlutterFire third engine.
2. The proposed “collision-safe join” over shared `message_reactions` was
   impossible because that table persists no conversation lane. V107 now uses
   separate typed direct notification reaction terminal authority, and Plan 331
   no longer claims the pre-existing canonical reaction key is repaired.
3. `KEEP` could ignore generation B while A was active and strand B after A's
   stale terminal race. The contract now requires a serial
   `APPEND_OR_REPLACE` chain, begin-time latest-generation resnapshot, and
   account-binding checks before acquire and acknowledgement.
4. Host/Flutter integration tests could not prove a WorkManager-started dead-UI
   process. Plan 331A names exact debug-only ADB probes on both available IDs;
   the device SQLCipher integration test is no longer mislabeled H0 proof.

Confirmed plan fixes and applied changes:

- Added index-mandated Report-41/48 sentinels, `feed`, pinned `baseline`, and
  pinned `transport`, plus exact curated registrations.
- Added production-bypass tests for the real `ReactionListener`, all direct-read
  callers, real snapshot producer/reconciler wiring, and every authenticated
  Feed/Orbit/Settings route.
- Expanded v107 to one-way rollback, v107->v107 import, cross-version rejection,
  partial repair, and sidecar cleanup.
- Added API24/30/34 foreground-service semantics and exact WorkManager/process/
  reboot/account-cutover tests.
- Made the missing relay/FCM credentials an honest closure preflight while
  keeping the available Android host/native/SQLCipher work executable.

Refuted/stale claim:

- Missing outer IDs are not an ordinary current relay defect: every decryptable
  current message/reaction producer retains its canonical outer ID. The slice
  remains useful defense-in-depth, now labeled as a test-only transport mutation
  with an exact relay producer-preservation gate and post-decrypt staging proof.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-03 | review complete / implementation starting | Plan 331, Plan 331A, Index | `$tdd-review`: `not-ready`; blockers independently verified | scope/gates/callers/migration/device truth repaired; both Android IDs live; relay credentials absent | execute Plan 331A causal REDs and independent Plan-331 waves; hold full closure on H0 + relay preflight |
| 2026-08-03 | H0 + native foundation GREEN | Go/runtime/lease/worker/scheduler/native resources | targeted Kotlin suite `BUILD SUCCESSFUL`; Go callback/producer proofs GREEN; four final H0 artifacts PASS | one Go initialization, one writable SQLCipher owner, no Activity/root, stale deliveries zero, close-failure retention, read-only FlutterFire peer, final `RELEASED`, activation false | H0 complete; production graph remains a separate gate |
| 2026-08-03 | independent slices GREEN | DB v107; direct custody/read/reconciliation; inner identity; snapshots/overlay; registration health/settings; l10n | 423 focused Dart tests plus migration/cutover families GREEN; representative mutations re-red; l10n/resource 7/7 | typed projection counterexample repaired: pending/failed custody retries without ack and still cleans up | retain all safe slices |
| 2026-08-03 | curated/family verification GREEN | gate registrations and affected app/runtime surfaces | `1to1`, `groups`, `feed`, `runtime-roots`, pinned Pixel `baseline` and full `transport` GREEN; `core-host-all` 3048/3048; `feature-host-all` 8754 passed + 1 capability skip; analyzer/format/diff clean | no full per-plan `host-all`; transport uses an explicit production lease around custom Android integration roots | proceed to final graph refresh |
| 2026-08-03 | real SQLCipher + H0 final GREEN | Pixel API36 + emulator API37 | direct v106->v107 proof PASS on both; H0 artifacts `b392c0d8...217ef`, `98582c60...bbff5`, `35b2dd0f...357a3`, `42a2bb94...61c7` | source `9c956aa4...d8a7d`, APK `26323df5...f4d36`; disposable package absent | ownership/direct durability device boundaries closed |
| 2026-08-03 | production composition audit | main/bootstrap, P2P/direct/group listeners, projection owners, identity/migration gates | no production `CanonicalRecoverySession`; seven required seams source-verified | activation could lose replay/custody or ack the wrong invocation; AOT entry point remains fail-closed | follow-up must extract the UI-neutral graph before activation |
| 2026-08-03 | TC-331-23 preflight | Sims capability + paired runner | Sims: `missingDriver`/dependency, zero assertions/artifact; direct runner: typed `credentials`, exit 78, zero assertions/artifact | `automationReady:false`; production graph/driver and relay/FCM credentials absent | overall Plan 331 stays open; never relabel host/H0 evidence as real-relay recovery |
