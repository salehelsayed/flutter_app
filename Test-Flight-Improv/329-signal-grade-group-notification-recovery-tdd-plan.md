# 329 - Signal-Informed Group Notification Wake-Recovery P0

Status: implemented and source-closed; current-source host/native/Graphify evidence complete; fresh paired-Android real-FCM proof and separate media-copy proof green; production rollout not performed
Type: bug + reliability hardening
Spec: make group text/image/video/voice/reaction notifications materially more reliable, using Signal Android's current design as primary-source guidance
Baseline: checkpoint commit `20900477c` (`pre-ultra-faix`)
Closure tier: Go host + Dart host + Android native + paired Android proof
Release note: relay production rollout remains owned by plan 324; iPhone is manual and non-gating by user direction

## Outcome And Priority Order

This plan implements the smallest feasible Signal-informed P0 slice. It does
not claim complete Signal parity or guarantee one visible card per dropped FCM
event. Canonical encrypted inbox state remains authoritative; FCM is a wake
hint and a dropped batch leaves a durable, privacy-safe recovery affordance.

The verified missing work, in priority order, is:

1. **P0 — fail closed when encrypted push preview extraction fails.** Ordinary
   direct and group relay builders currently ignore the extraction result and
   can emit a blank, unrenderable payload. Absorb plan 328's guarded
   `preview_unavailable` fallback for both siblings.
2. **P0 — recover Android FCM queue deletion without losing the recovery
   request.** Add an app-owned FlutterFire-compatible service that records a
   monotonic pending generation synchronously and posts one stable generic
   card. Cold start and every resume poll this state and run canonical direct
   plus group drains before compare-and-acknowledging that generation.
3. **P0 — never report a disabled relay push provider as success.** When both
   provider implementations are nil, record `provider_unavailable`, make zero
   send/retry attempts, do not evict the token, and do not increment success.
4. **P0 — make recovered reactions follow the canonical notification path and
   retain durable custody until application succeeds.** Offline group reactions
   must emit the listener reaction stream/contextual card, not only update the
   database plus generic recovery card. A buffered reaction is applied
   idempotently before its durable pending row is deleted; repository failure or
   process interruption leaves it retryable.
5. **P1 — preserve unrelated notification cards.** Remove blanket remote-open
   cancellation from both the warm `ApplicationRoot` route and cold
   `StartupRouter` route. Preserve exact cancellation for a selected local
   notification.
6. **P1 — preserve sender attribution in Android's trusted degraded group
   copy.** Use the already-decrypted `senderUsername` with localized generic
   copy, without adding plaintext media metadata.

One initial candidate is explicitly **refuted**: ordinary foreground group
replay already flows through `GroupMessageListener.handleReplayEnvelope`,
which persists and presents the canonical notification. Adding another
foreground presenter would create a double-presentation risk and is out of
scope.

## Online Research: Signal Practices Adopted

Primary Signal Android sources inspected on 2026-08-02, pinned to revision
`2578e8c7ee3a421220906346d7d84240f0894de5`:

- [`FcmReceiveService.onDeletedMessages`](https://github.com/signalapp/Signal-Android/blob/2578e8c7ee3a421220906346d7d84240f0894de5/app/src/main/java/org/thoughtcrime/securesms/gcm/FcmReceiveService.java) treats deleted FCM messages as a reason to enter the normal fetch path.
- [`FcmFetchManager`](https://github.com/signalapp/Signal-Android/blob/2578e8c7ee3a421220906346d7d84240f0894de5/app/src/main/java/org/thoughtcrime/securesms/gcm/FcmFetchManager.kt) coalesces fetch work, keeps it alive, schedules fallback work, and can show an honest generic recovery notification.
- [`MessageFetchJob`](https://github.com/signalapp/Signal-Android/blob/2578e8c7ee3a421220906346d7d84240f0894de5/app/src/main/java/org/thoughtcrime/securesms/jobs/MessageFetchJob.java) performs retryable, network-constrained canonical fetching.
- [`NotificationStateProvider`](https://github.com/signalapp/Signal-Android/blob/2578e8c7ee3a421220906346d7d84240f0894de5/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/NotificationStateProvider.kt) derives message/reaction presentation from canonical unread database state rather than trusting the wake payload as the final record.
- [`DefaultMessageNotifier`](https://github.com/signalapp/Signal-Android/blob/2578e8c7ee3a421220906346d7d84240f0894de5/app/src/main/java/org/thoughtcrime/securesms/notifications/v2/DefaultMessageNotifier.kt) owns stable conversation notification identity, history/counts, summaries, and policy-aware display.

Practices adopted now:

- treat push as a wake hint, not message custody;
- route dropped wakes back through canonical direct/group inbox drains;
- coalesce native recovery into one stable generic card that only alerts once
  while successive deleted batches update it;
- retain recovery state until the canonical drains return a verified success;
- use stable/exact notification identity and avoid blanket cancellation;
- derive normal message/media/reaction cards from the existing canonical app
  pipeline, not new plaintext hints.

Accepted differences in this slice:

- MKnoon's canonical P2P/Go runtime cannot safely be booted headlessly from a
  native Android service, so recovery starts when the Flutter application
  runtime is available.
- Pre-first-unlock/direct-boot recovery is not claimed: the marker uses normal
  credential-protected app preferences.
- The generic recovery card represents “messages may be waiting,” not a card
  for each lost event.

## Checkpoint Grounding And Baseline Source Evidence

The observations in this section describe checkpoint `20900477c`, before the
Plan 329 implementation. They are retained as causal planning evidence and are
not claims about the current working tree.

- Planning graph fingerprint: `b5e9eb73124c5630`; only an unrelated group system
  transition processor was stale.
- Final closure graph fingerprint: `46ce822a5402a539`; the anchored review query
  for `DroppedPushRecoveryCoordinator`, `handleReplayReaction`, and
  `GroupPendingReaction` reports `freshness=current`. The production refresh
  was followed by one final incremental refresh after the Android proof-harness
  race correction.
- TDD query: `python3 graphify-arch/tdd_context.py query "Signal-grade group notification reliability background_message_handler firebaseMessagingBackgroundHandler PushService.send sendWithRetry onDeletedMessages notification projection badge exact cancellation reaction target semantic copy policy parity QA group push registration Android device proof" --profile tdd --budget 700`.
- Review query: `python3 graphify-arch/tdd_context.py query "Plan 329 counterexamples: ordinary foreground group drain notificationNeeded canonical SQLCipher notification projection MknoonFirebaseMessagingService onDeletedMessages pending recovery marker ApplicationRoot remote notification clearDeliveredNotifications PushService nil provider preview_unavailable Android USB emulator proof" --profile review --budget 800`.
- Relay false success: `go-relay-server/inbox.go` returns nil when both push
  providers are absent, after which retry accounting records success.
- Envelope loss: ordinary direct/group builders discard the boolean return
  from `addChatEncryptedPushData` / `addGroupEncryptedPushData`; reaction
  builders already demonstrate the guarded pattern.
- Android fallback copy: `push_decrypt_preview.dart` has trusted sender data
  but currently renders only the generic body for degraded groups.
- Android service: resolved `firebase_messaging-15.2.10` exposes a public,
  subclassable `FlutterFirebaseMessagingService`; the plugin service does not
  override `onDeletedMessages`.
- Resume truth: `handleAppResumed` launches direct and continuation drains
  unawaited and returns bridge health, not convergence. It cannot be the
  acknowledgement boundary.
- Cold-start truth: `ApplicationRoot` deliberately receives no synthetic
  initial resumed transition, so an initialization poll is mandatory.
- Foreground refutation: `ApplicationRoot` supplies the real group listener;
  `DrainGroupOfflineInboxUseCase` routes ordinary replay through
  `handleReplayEnvelope`; `GroupMessageListener` persists and presents it.
- Blanket cancellation exists at both `application_root.dart:803` and
  `startup_router.dart:1099`.

## Scope Contract

### A. Relay envelope and provider truth

- Check ordinary direct/group encrypted-data extraction.
- On failure, emit the existing strict, routable `preview_unavailable`
  fallback; never emit a partially blank encrypted shape.
- Treat a missing, fractional, zero, negative, or non-canonical group
  `keyEpoch` as an unusable envelope rather than forwarding a shape Dart cannot
  decrypt.
- Preflight provider availability before retry accounting.
- A missing provider emits one `provider_unavailable` result, with no retry,
  success increment, or token eviction.
- Preserve permanent-provider-error token invalidation and bounded transient
  retry.

### B. Android dropped-wake ownership

- Remove only the exact FlutterFire service declaration using
  `tools:node="remove"` and register
  `MknoonFirebaseMessagingService : FlutterFirebaseMessagingService` at higher
  priority for `com.google.firebase.MESSAGING_EVENT`.
- Preserve the Firebase SDK fallback service at priority `-500`; the merged
  manifest assertion is **not** “exactly one service.” It asserts the
  FlutterFire service is absent, MKnoon is present/selected at higher priority,
  and the SDK fallback remains.
- Override `onDeletedMessages`, call `super.onDeletedMessages()` for forward
  compatibility, then synchronously persist:
  - `lastGeneration = lastGeneration + 1`;
  - `pendingGeneration = lastGeneration`;
  - using `SharedPreferences.commit()` before attempting notification display.
- Use a reserved recovery notification `(tag, id)` and reserved channel. API
  24/25 must not create a channel; API 26+ must. API 33 denied permission must
  still retain the generation.
- The card is non-auto-cancel, content-free, and `onlyAlertOnce`; a later
  generation updates the same reserved `(tag, id)` without repeatedly alerting.
  A tap may signal a warm Flutter engine, but it never consumes the marker.
- Native bridge methods:
  - `pendingGeneration()` reads without consuming;
  - `acknowledgeGeneration(expected)` clears/cancels only if pending still
    equals `expected`;
  - `lastGeneration` remains monotonic after acknowledgement, preventing ABA.

### C. Canonical recovery coordinator

- Add a Dart single-flight `DroppedPushRecoveryCoordinator`.
- Poll after application runtime/bootstrap readiness on cold initialization
  and after every resume; a warm native intent signal only accelerates polling.
- Give `P2PFullInboxDrain.drainOfflineInboxFully()` a structured result with at
  least `isSuccessful`, `hasMore`, and optional failure reason.
- Refactor the current full direct drain so first-page failure, continuation
  failure/exception, runtime/migration gate, or page-cap remainder cannot be
  mistaken for success. Existing callers may await and ignore the richer
  result.
- Await both:
  - direct full drain: `isSuccessful && !hasMore`;
  - group full drain: `isSuccessful && !hasMorePages`.
- Compare-and-ack only after both succeed. Direct failure, group failure,
  process interruption, or a newer generation retains the marker and card.
- Concurrent recovery calls coalesce. A second generation arriving during a
  drain defeats the stale acknowledgement and remains pending for the next
  poll. A resume or native signal that arrives during an active lifecycle pass
  latches one authoritative repoll instead of being dropped.
- Recovered group reactions use `GroupMessageListener` when its production
  reaction dependencies are present, preserving sender key/transport binding,
  UI stream emission, mute/archive/viewing policy, contextual notification
  copy, and durable event claims. Persistence/derivative exceptions rethrow to
  retain the page cursor and native generation.
- A pending reaction uses an in-process overlap claim, applies idempotently,
  and deletes its durable pending row only after terminal handling succeeds.
  Apply exceptions and crash windows retain the row for startup retry.

### D. Surgical notification opening and degraded copy

- Remove `clearDeliveredNotifications()` from warm remote-open routing and
  cold startup remote-open routing.
- Preserve route completion and exact local-notification `cancel(id)` behavior.
- In the trusted Android degraded group fallback, render localized
  `senderUsername: New message`; never use untrusted wake text or add plaintext
  media type.

### Must preserve

- FlutterFire token refresh and ordinary remote-message background handling;
- direct and group recovery, not group-only recovery;
- live/background group text/media/reaction presentation through current
  canonical listeners and repositories;
- mute/archive/viewing/reaction authorization and exact-once tone claims;
- token deletion only for typed permanent provider errors;
- strict oversize routing fallback and reaction envelope guards;
- exact local-notification cancellation.

### Hard exclusions

- No new foreground group presenter or duplicate notification projection.
- No plaintext media type, reaction target, sender content, or message body.
- No native Flutter-engine/SQLCipher/Go bootstrap and no speculative
  WorkManager job.
- No DB or wire migration.
- No separate production relay deployment; plan 324 owns v1.7.6 rollout.
- No automated iPhone leg; iPhone remains manual-only.

## Test Contract

| ID | Required behavior | Causal test / proof | HEAD to GREEN signal | Mutation / preservation |
|---|---|---|---|---|
| TC-329-01 | unusable group envelope, including invalid semantic epoch, becomes strict fallback | `push_envelope_guard_test.go::TestGroupPushFallsBackWhenEnvelopeUnusable` + `TestGroupPushFallsBackWhenKeyEpochUnusable` | blank/invalid shape -> `preview_unavailable` | discard boolean or accept fractional/zero epoch -> red |
| TC-329-02 | unusable direct envelope gets sibling guard | `push_envelope_guard_test.go::TestChatPushFallsBackWhenEnvelopeUnusable` | blank shape -> `preview_unavailable` | discard boolean -> red |
| TC-329-03 | nil provider is not success | `push_provider_availability_test.go::TestPushProviderUnavailableIsNotCountedAsSuccess` | success -> unavailable, zero attempts | restore nil success -> red; permanent-error sentinel green |
| TC-329-04 | deletion persists before display and coalesces an alert-once card | `MknoonFirebaseMessagingServiceTest` real `onDeletedMessages` call | no owner -> generation + reserved card + `FLAG_ONLY_ALERT_ONCE` | remove commit/notify/flag -> red |
| TC-329-05 | generation is crash-safe and ABA-safe | `DroppedPushRecoveryStoreTest` | absent API -> read is non-consuming; stale ack refuses newer generation | consume on read/reset last generation -> red |
| TC-329-06 | native API/permission matrix is correct | Robolectric API 24, 26, 33 granted/denied cases | service absent -> correct channel/card/retained marker | move persistence after notify -> denied branch red |
| TC-329-07 | manifest replaces plugin owner without removing SDK fallback | merged-manifest test/assertion | plugin owner present -> MKnoon selected, SDK fallback retained | remove tools removal/custom owner -> red |
| TC-329-08 | direct drain has truthful structured completion | `p2p_service_impl_test.dart` success/failure/page-cap cases | void/unawaited ambiguity -> explicit outcome | map page failure to success -> red |
| TC-329-09 | coordinator acknowledges only full direct+group success | `dropped_push_recovery_coordinator_test.dart` | no coordinator -> exact generation ack after both successes | acknowledge after either leg -> red |
| TC-329-10 | crash/read, second deletion, concurrency, repeat are safe | same coordinator/store suites | no seam -> retain/coalesce/idempotent | boolean marker or no single-flight -> red |
| TC-329-11 | cold initialization and ordinary resume poll without a tap | ApplicationRoot recovery wiring test | no initial-resume poll -> both paths invoke coordinator | rely only on native signal -> cold red |
| TC-329-12 | warm and cold remote opens never cancel all | existing app-root and startup-router notification-open tests | clear count 1 -> 0 while routing succeeds | restore either blanket clear -> red |
| TC-329-13 | local tap remains exact | existing `flutter_notification_service_test.dart` exact-ID cases | existing green | replace exact cancel with blanket/no cancel -> red |
| TC-329-14 | degraded trusted group copy retains sender | `push_decrypt_preview_test.dart` plan-329 case | `Message` -> `Alice: New message` | restore bare body -> red |
| TC-329-15 | ordinary FCM text/reaction delivery survives service replacement | `groups.reaction_notification_campaign` | current retained pass -> new build pass | real boundary preservation, not deleted-queue causality |
| TC-329-16 | group text/photo/video/voice OS cards retain correct copy on Android pair | `run_notification_sound_smoke.dart` rows S2/S8/S9/S10 | paired local P2P rows pass | Android OS presentation preservation |
| TC-329-17 | recovered group reaction emits canonical stream and contextual card | `drain_group_offline_inbox_use_case_test.dart::drained group reaction uses listener stream and contextual notification` | persistence-only replay -> one stream event/card | bypass listener -> red |
| TC-329-18 | buffered reaction is not deleted before successful apply | `group_message_listener_test.dart::pending reaction remains durable when apply fails and retries on restart` | delete-before-save loss -> retained row, restart apply/delete | restore pre-apply delete -> red |

Test design requirements:

- Native tests call the real service override and inspect
  `NotificationManager`; helper-only tests are insufficient.
- Manifest proof inspects the merged debug manifest or APK, not merely the
  source manifest or a successful `processDebugMainManifest` task.
- Recovery tests cover direct failure, group failure, page-cap remainder,
  crash after read, a second deletion during drain, concurrent calls,
  idempotent repeat, cold initialization, resume without a tap, a native signal
  during an active resume, and permission denied.
- Reaction recovery tests cover listener stream/contextual presentation,
  sender-key/transport preservation, listener-side persistence rethrow, and a
  failed buffered apply followed by successful startup retry.
- Cancellation tests cover both warm and cold remote-open paths and assert
  routing still completes with zero blanket clears.
- The real-FCM campaign proves service-replacement preservation only. FCM
  cannot be commanded to emit `onDeletedMessages`; TC-329-04..07 are its
  causal boundary.
- The media smoke is a separate fully automated paired-Android proof; do not
  represent its foreground/local P2P rows as real-FCM media delivery.

## TDD Implementation Order

1. Record the clean checkpoint/worktree state and add causal Go, native, and
   Dart tests before their production edits. Capture expected test/compile RED
   for the named missing behavior.
2. Implement relay envelope guards and provider-unavailable truth; run focused
   Go GREEN and permanent-error preservation.
3. Implement native generation store, stable card, FlutterFire subclass,
   manifest ownership, and bridge; run the full Robolectric API matrix and
   inspect the merged manifest.
4. Refactor the direct full-drain result, implement the Dart single-flight
   coordinator, then wire initialization/resume/native-signal polling. Run all
   failure/race cases before application-root integration.
5. Remove both blanket remote-open clears and implement trusted degraded group
   sender copy; keep exact local cancellation green.
6. Register new Dart tests in both affected curated lanes, grep-verify every
   path, then run focused/preservation/curated/family gates at the cadence
   below.
7. Refresh the app-owned Graphify graph once after coherent source changes.
8. Build current Android artifacts and run the two distinct automated paired
   Android proofs. Do not select an iPhone.

## Gate Cadence And Exact Commands

Per-plan closure uses focused causal tests, preservation sentinels, affected
`1to1` and `groups` gates, then justified `core-host-all` and
`feature-host-all`. Do **not** run full `host-all` for this plan; run it once at
the notification reliability wave boundary and again at final release closure.

```bash
# RED/GREEN Go package; keep cwd stable for following commands
(cd go-relay-server && go test ./... -run 'Test(Group|Chat)PushFallsBackWhenEnvelopeUnusable|TestPushProviderUnavailableIsNotCountedAsSuccess')

# Android causal/native matrix and merged artifact
(cd android && ./gradlew :app:testDebugUnitTest --tests '*DroppedPushRecovery*' --tests '*MknoonFirebaseMessagingService*')
./scripts/check_dropped_push_recovery_manifest_contract.sh

# Focused Dart causal + preservation
flutter test -d flutter-tester \
  test/core/notifications/dropped_push_recovery_bridge_test.dart \
  test/core/notifications/dropped_push_recovery_coordinator_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/core/notifications/local_notification_exact_cancellation_wiring_test.dart \
  test/features/identity/presentation/screens/startup_router_notification_open_test.dart \
  test/features/push/application/push_decrypt_preview_test.dart \
  test/core/notifications/flutter_notification_service_test.dart \
  test/features/groups/integration/group_reaction_notification_pipeline_test.dart

# Registration truth: every new shared recovery path must be in both lanes
rg -n 'dropped_push_recovery_(bridge|coordinator)_test.dart|p2p_service_impl_test.dart' scripts/run_test_gates.sh
./scripts/run_test_gates.sh completeness-check

# Affected curated/family gates; no per-plan full host-all
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only
./scripts/run_host_test_gates.sh feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene
flutter analyze
(cd go-relay-server && test -z "$(gofmt -l .)")
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

`push_decrypt_preview_test.dart` is already in `GROUP_TESTS`; it is not in the
1:1 array. `background_push_notification_fallback_test.dart` is currently
intro-only and is not changed by this revised scope. New shared recovery tests
must be deliberately registered in both affected lanes, then verified by grep
and completeness-check rather than assumed from host glob discovery.

## Paired Android Proof Profile

Live matrix on 2026-08-02:

- sender: Android emulator `emulator-5554`, API 37;
- receiver: USB Pixel 6 `21071FDF600CSC`, API 36;
- iPhone: manual-only, unused and non-gating.

First re-run discovery immediately before proof:

```bash
flutter devices --machine
adb devices -l
dart tool/sims/sims.dart major --list \
  --only groups.reaction_notification_campaign --format tsv
```

Real relay/FCM preservation for group text + reactions:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' \
SIMS_ANDROID_PHYSICAL_DEVICE_ID=21071FDF600CSC \
SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-5554 \
SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$PWD/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json" \
MKNOON_257_RELAY_TARGET=ubuntu@mknoun.xyz \
MKNOON_257_RELAY_KEY="$PWD/se.pem" \
MKNOON_257_STAGING_MANIFEST="$PWD/docker-ws/group-reaction-staging-manifest-315.json" \
dart tool/sims/sims.dart major --only groups.reaction_notification_campaign
```

Android OS group copy for text/photo/video/voice, fully automated:

```bash
dart run integration_test/scripts/run_notification_sound_smoke.dart \
  -d emulator-5554,21071FDF600CSC \
  --rows S2,S8,S9,S10 \
  --non-interactive \
  --artifact-dir build/sims/proofs/plan-329-group-media-current-final
```

Fresh current-source real-FCM closure:

- aggregate:
  `build/sims/proofs/groups.reaction_notification_campaign/groups.reaction_notification_campaign-1785703174982368-89327.json`
  (SHA-256 `648f4decd60a2ff831faef08efde96b57e3e595de6f717713c9af0c81eaa9ed7`);
- status: `passed`, all five scenarios: group and announcement message
  lifecycles, group and announcement reactions, and background-connected group
  reaction delivery;
- APK input digest:
  `ade0635cbbd6d32d298f0a8975dd3796f645dc57a0ca269d50b86512558d79d1`;
- prepared APK:
  `build/sims/cache/android.production_fcm/ade0635cbbd6d32d298f0a8975dd3796f645dc57a0ca269d50b86512558d79d1/artifact.apk`,
  SHA-256 `bd3ef2e1cfc97ba592d81195801e10a74cc6393f5770d07f8dcd59b6a2ae5ba2`;
- capture root:
  `build/sims/proofs/groups.reaction_notification_campaign/capture-1785701450952016-89327/`;
- build provenance: final invocation was one cache hit, zero misses/actual
  builds, and zero child builds against the centrally attested APK.

Fresh media-copy closure from the recorded Android-only, `--non-interactive`
runner invocation:

- summary:
  `build/sims/proofs/plan-329-group-media-current-final/notification_sound_smoke_summary.json`
  (SHA-256 `d84baae74275724b043ae5dd1c0dff03a30050d186e097d1d4d833f6af3f2e95`);
- S2 text, S8 photo, S9 video, and S10 voice all passed their programmatic and
  Android OS-card predicates in one run;
- all four observations used stable group notification ID `1259908906`, one
  active card, and zero duplicates;
- S9/S10 needed one non-destructive shade scroll each to expose the silent
  cards; this was a viewport attempt, not a scenario retry.

The media summary proves the four row outcomes, notification predicates, and
stable identity; it does not independently embed target IDs or APK/source
provenance. Those attestations belong only to the separate real-FCM aggregate
above and are not imputed to the media artifact.

Three pre-terminal capture roots remain as honest fixture diagnostics:
`capture-1785698843364906-77898` timed out during first group setup;
`capture-1785699315955235-80104` passed scenario one but exposed a periodic
group-recovery/create race in scenario two; and
`capture-1785700829246509-86699` proved the first wait marker was too narrow.
None reached a notification-delivery assertion failure. The final tested
harness waits for a newly completed `GROUP_DRAIN_OFFLINE_INBOX_TIMING` event
and a two-second settle before the create tap; all five clean setups and
scenarios then passed without manual input.

## Residual Reliability Ledger

These verified gaps are not hidden by the P0 label and remain separately owned:

1. **P1 — durable headless canonical fetch/outbox.** Native Android cannot
   instantiate the current Flutter/Go/P2P bootstrap safely; a separately
   designed background runtime/job is needed.
2. **P1 — durable notification display outbox.** A provider/local `show`
   failure can release the current claim without a durable display retry.
3. **P1 — one canonical notification policy.** Mute/archive/dissolved/type/QA
   eligibility differs across live, foreground, Android background, iOS NSE,
   direct, and reaction paths.
4. **P1 — registration readiness.** Direct projection backfill is awaited but
   group projection backfills are unawaited, so capability can be advertised
   before all projection state is ready.
5. **P1 — unread-derived badge/history/summary and iOS exact remote IDs.** The
   current permission `presentBadge` is not a numeric unread projection.
6. **P2 — reaction target semantics.** Signal can say reaction-to-photo/video/
   audio because it projects from canonical DB state; MKnoon's background
   path currently uses generic reaction copy and must not add plaintext hints.
7. **Privacy/release dependencies.** Plan 327 owns opaque wakes/privacy, plan
   311 owns QA deletion, plan 324 owns relay rollout, and plan 328's source
   fixes are absorbed here.
8. **P2 — native recovery-card localization.** The privacy-safe recovery
   channel/title/body are currently English-only because this native service
   cannot use Flutter localization state; Android string-resource translations
   remain follow-up UX work, not a delivery/acknowledgement dependency.

Plan 329 therefore closes implementation/source seams, not production rollout
or all Signal-grade notification behavior.

## Risks, Rollback, And Stop Conditions

- **FCM ownership risk:** a bad manifest replacement can disable all Android
  delivery. Stop unless subclass compilation, native behavior, merged-manifest
  assertions, and the real-FCM campaign pass.
- **False acknowledgement risk:** stop if either drain cannot expose truthful
  completion, or if a stale generation can clear a newer one.
- **Permission risk:** API 33 denial may prevent a visible card but must never
  prevent synchronous marker persistence.
- **Duplicate-presentation risk:** no new foreground presenter is allowed; the
  current listener remains the sole ordinary replay presenter.
- **Build provenance risk:** cached APK mtime is not proof; paired-device
  artifacts must identify the current build/source.

Rollback:

- App rollback requires a newly signed build restoring the FlutterFire
  manifest owner and removing the MKnoon service/channel usage; there is no
  runtime feature flag for manifest ownership.
- The content-free `lastGeneration`/`pendingGeneration` preferences are inert
  to an older client and require no database rollback. A future app may remove
  the reserved recovery card/channel after successful migration or uninstall.
- No SQLCipher schema or wire-format migration is introduced.
- Relay binary backup/restore and production rollback stay with plan 324; this
  plan does not deploy independently.

Stop and re-plan if FlutterFire becomes non-subclassable, merged-manifest
selection differs from the verified priority model, a complete direct/group
drain cannot return truthful state without broad transport redesign, or the
paired Android harness requires manual taps.

## Reviewer Findings

Initial `/tdd-review` verdict: **plan-fixes-required**.

Critical findings incorporated:

- refuted the proposed foreground presenter using the actual replay/listener
  call chain and removed three invalid test cases plus their production scope;
- replaced a lossy boolean marker with monotonic `lastGeneration` plus
  compare-and-acknowledged `pendingGeneration`;
- made cold initialization polling authoritative and native intent signaling
  optional acceleration;
- rejected `handleAppResumed` as an acknowledgement boundary and required
  structured direct/group convergence results;
- corrected the manifest oracle to retain the Firebase SDK fallback instead
  of asserting exactly one messaging service;
- added API 24/26/33 and permission-denied native branches;
- covered both warm and cold blanket cancellation sites;
- corrected gate registrations, cwd-safe commands, `gofmt` semantics, relay
  addresses, and the distinction between real-FCM reaction proof and local P2P
  media-copy proof;
- added rollback, rollout ownership, direct-boot limits, and the ranked
  residual reliability ledger.

Post-review implementation audit corrections:

- separated fallback-construction telemetry into
  `relay_push_fallback_total{reason}` so a routed fallback is not also counted
  as a final send result;
- made direct staging, group placeholder/decode handling, and group-reaction
  persistence fail closed, so a partial page cannot advance its cursor or
  acknowledge a dropped-wake generation;
- rejected fractional/native generation values, reconciled an orphaned
  reserved card only when no marker exists, and retained the marker when API
  33 notification permission is denied;
- added a lifecycle repoll latch for a second resume/native signal that arrives
  while the first resume is active;
- mapped the groups feature result into a feature-neutral core recovery type,
  removing an architecture-layer violation found by the broad core gate; and
- corrected the merged-manifest oracle to the generated debug artifact and
  hardened media shade capture with progressive scrolling rather than
  destructive notification clearing; and
- applied Signal's alert-once generic-card behavior and asserted the native
  notification flag, so successive deleted batches coalesce without repeated
  sound/vibration.

## Arbiter Decision

Revised verdict: **ready**.

The revised core bet is confirmed for its limited scope: durable generation
tracking plus canonical application-time drains closes the currently reachable
dropped-wake loss without inventing a native P2P runtime; guarded relay
fallbacks and truthful provider accounting close independent silent-loss and
false-success seams. Counterexample, lifecycle, sibling-surface, destructive
action, policy-invariant, registration, rollout, and device-proof lenses now
have explicit tests or honest deferrals. Disposition: execute this v2 plan.

## Execution Verdict

The historical arbiter decision above authorized v2. A separate critical
implementation review then found and corrected four material omissions before
closure: alert-once card updates, fail-closed native read errors, canonical
contextual presentation for offline reactions, and apply-before-delete custody
for buffered reactions. It also added semantic group `keyEpoch` validation and
a registered merged-manifest verifier. No reviewed blocking defect remains.

Plan 329 is an implementation/source closure, not a production rollout. The
current source has focused, Go, Android native, manifest, groups, and feature
family evidence, plus fresh paired-Android real-FCM closure and a separate
Android media-copy closure with the provenance boundary recorded above.
Broad-gate results are reported compositionally because checkpoint
`20900477c` already contains unrelated red tests:

- current-source `1to1` log
  `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/plan329_1to1_final.9K0hQLHtVf`:
  2,550 passed and four
  `full_migration_chain_test.dart` expectations still say schema 104 while the
  checkpoint already declares schema 105;
- current-source `core-host-all` log
  `/tmp/mknoon-plan329-core-final.hhgON9/core-host-all.log`:
  2,873 passed and seven checkpoint-existing failures comprising the same four
  migration expectations, one
  stale runtime-root schema-104 anchor, one DTR resume import-set expectation
  of 17 versus the checkpoint's 18, and one unchanged DTR placement SHA;
- none of those files/anchors were introduced by Plan 329, and the gate audit
  found zero Plan-329-owned failures.

## Done Criteria

- [ ] Every TC has recorded causal RED or an existing named preservation
      baseline, then focused GREEN.
- [x] Native service/store/bridge tests pass across the specified API and
      permission matrix; merged manifest selects MKnoon and retains SDK fallback.
- [x] Direct/group recovery returns truthful convergence and all generation,
      crash, retry, and concurrency cases pass.
- [x] Both remote-open paths route successfully with zero blanket clears;
      exact local cancellation remains green.
- [x] Go envelope/provider tests and permanent-error sentinels pass.
- [x] New tests are registered in both affected curated lanes and
      completeness-check passes.
- [x] Compositional source closure is recorded: focused, `groups`, and feature
      gates are green; `1to1` and core have zero Plan-329-owned failures after
      checkpoint-debt audit; analyzer, format, diff hygiene, and final Graphify
      freshness pass. No per-plan full `host-all` is run.
- [x] The fresh current-source paired-Android real-FCM aggregate passes all
      five scenarios. The separate media summary passes S2/S8/S9/S10 in one
      Android-only `--non-interactive` runner invocation; S9/S10 each used one
      non-destructive shade scroll. The media artifact is not represented as
      carrying APK/device provenance. Earlier fixture-only failed captures
      remain recorded. iPhone remains manual/non-gating.
- [x] Execution notes say “implementation/source closure” until the app release
      is separately authorized; plan 324 owns only the relay rollout.

The first criterion remains intentionally unchecked: every behavior now has a
named causal/preservation test and focused GREEN evidence, but a retained
per-test RED transcript was not produced for all 18 rows. This provenance gap
does not weaken the current GREEN behavior evidence and is not restated as a
completed RED ledger. The separate compositional source-closure criterion is
complete with current Graphify freshness and the checkpoint-debt audit above.

## Execution Progress

| Time | Phase | Evidence | Decision / next |
|---|---|---|---|
| 2026-08-02 | checkpoint | commit `20900477c` with message `pre-ultra-faix`; clean tree | plan from checkpoint |
| 2026-08-02 | research + v1 plan | Signal primary sources, graph fingerprint `b5e9eb73124c5630`, live Android pair | submit v1 to critical review |
| 2026-08-02 | `/tdd-review` | three independent review lenses plus source counterexample audit | `plan-fixes-required` |
| 2026-08-02 | v2 revision | foreground premise refuted; generation/race/cold/manifest/gate/proof/rollback corrections incorporated | arbiter `ready`; begin causal RED tests |
| 2026-08-02 | relay implementation | strict direct/group `preview_unavailable`; semantic positive-integer epoch guard; nil provider emits one unavailable result; fallback/result metrics separated | final `go test ./...` green; all four invalid-epoch mutations green; `gofmt` clean |
| 2026-08-02 | Android native implementation | app-owned FlutterFire service, durable monotonic store, bridge, alert-once reserved card, API/permission branches | 4 suites / 14 tests, zero failures/skips; registered merged-manifest gate: MKnoon 1 at 500, FlutterFire 0, SDK fallback 1 at -500 |
| 2026-08-02 | Dart implementation | truthful full direct/group drains, single-flight compare-and-ack coordinator, cold/resume/native repoll wiring, surgical opens, sender copy | focused recovery/preservation suites green; registration completeness 1371/1371 |
| 2026-08-02 | critical implementation review | traced native error semantics, offline reaction projection, pending-reaction crash window, epoch parsing, and merger regression coverage | all findings corrected; final five-file focused rerun 370/370 green |
| 2026-08-02 | curated group gate | canonical Dart group lane plus Go bridge/relay tails, current source | 3,517 Dart tests green; both Go tails green; log `plan329_groups_final.hcOWx9ajDV` |
| 2026-08-02 | feature family gate | exact current-source `feature-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only` | 819 paths; 8,543 passed, 1 intentional SQLCipher host skip, 0 failed |
| 2026-08-02 | core family audit | exact current-source core Dart family | 2,873 passed / 7 checkpoint-existing failures / 0 Plan-329 failures across 370 paths; log `/tmp/mknoon-plan329-core-final.hhgON9/core-host-all.log` |
| 2026-08-02 | curated 1:1 audit | exact current-source `./scripts/run_test_gates.sh 1to1` | 2,550 passed / 4 checkpoint-existing schema-104 failures / 0 Plan-329 failures; fail-fast stopped the redundant Go tail, already green in `groups` |
| 2026-08-02 | static/registration hygiene | `flutter analyze`; completeness; shell syntax; diff hygiene | analyzer clean; 1,371/1,371 test files classified; shell syntax and `git diff --check` green |
| 2026-08-02 | architecture closure | production incremental refresh, then one final harness-only incremental refresh and anchored review query | `freshness=current`; closure fingerprint `46ce822a5402a539` |
| 2026-08-02 | real-FCM Android pair | USB Pixel 6 `21071FDF600CSC` + emulator `emulator-5554`; attested current APK | five scenarios passed; aggregate `groups.reaction_notification_campaign-1785703174982368-89327.json`; APK SHA `bd3ef2e1cfc97ba592d81195801e10a74cc6393f5770d07f8dcd59b6a2ae5ba2`; zero child builds |
| 2026-08-02 | Android media-copy invocation | runner command pinned `emulator-5554,21071FDF600CSC` and `--non-interactive`; summary does not independently attest targets/build | all four S2/S8/S9/S10 OS-card rows passed; notification ID `1259908906` stable across 4/4 observations; zero duplicates; summary `plan-329-group-media-current-final/notification_sound_smoke_summary.json` |
