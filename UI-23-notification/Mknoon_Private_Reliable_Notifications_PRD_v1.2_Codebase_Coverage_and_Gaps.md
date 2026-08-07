# Private and Reliable Notifications: Codebase Coverage and Gap Assessment

- **Assessed PRD:** [Mknoon Private Reliable Notifications PRD v1.2](./Mknoon_Private_Reliable_Notifications_PRD_v1.2.md)
- **Assessment date:** 7 August 2026
- **Repository baseline:** Branch `protected-view`, HEAD `007c1e2d577c226aee2a94e2050f3a19e4812775`, clean immediately before Plan 343 planning
- **Assessment scope:** Committed implementation through Plan 342. The reviewed Plan 343 TDD artifact, index entry, and this report refresh are planning/documentation changes and are excluded from the current-code score.
- **Purpose:** Durable input for later product decisions, implementation planning, story creation, and acceptance-test design

**Document status:** Codebase assessment; not an implementation plan and not evidence that the PRD has been accepted

**Adopted test-sequencing guidance:** Implement GAP-N01 through GAP-N11 first and satisfy their deterministic host/native tests and continuous Android device proof. Keep touched iOS code compiling and covered by focused Swift tests, but defer iPhone/iOS device acceptance and harness expansion to one bounded, consolidated iOS closure phase owned by GAP-N12 after the implementation gaps are code-complete. Apple-dependent gaps remain evidence-deferred, not PRD-compliant, until that phase passes. See §9.1 and §10.

## 1. Executive finding

Mknoon's notification code contains substantial durability, deduplication, stable-ID, cancellation, native-extension, and recovery machinery. It does **not**, however, implement the central architecture proposed by PRD v1.2.

The current implementation is primarily a **rich encrypted push delivery model**:

- fresh ordinary direct text now retains sender-owned exact-envelope custody independently of live ACK, but reactions, media, edits/deletes, group ordering, device fanout, and relay-overflow retention still lack the universal PRD contract;
- the relay builds APNs/FCM payloads from message envelopes;
- provider payloads contain routing/event identifiers and encrypted preview material;
- iOS and Android locally decrypt or project that provider-carried material;
- foreground, background, native, and reconciliation paths coordinate through several specialized stores and decision paths.

The PRD requires an **inbox-first opaque-wake model**:

- every notification-worthy event is first committed to the recipient device inbox;
- direct/pubsub delivery is only a fast path for the same authenticated event;
- APNs/FCM receives one fixed generic wake with no sender, conversation, event, or media metadata;
- native processing fetches the inbox and then decrypts, persists, deduplicates, applies policy, and renders locally;
- every entry point uses one fresh lifecycle source, one decision engine, and one atomic notification ledger;
- a transport or persistence acknowledgement cannot cancel the wake without a completed local outcome.

Using the PRD's bounded A-01 through A-30 audit checklist and strict scoring (`Compliant = 1`, `Partial = 0.5`, `Missing/Risky = 0`), current coverage is:

| Result | Count | Weighted points |
|---|---:|---:|
| Compliant | 2 | 2.0 |
| Partial | 19 | 9.5 |
| Missing or core condition failed | 9 | 0.0 |
| **Total** | **30** | **11.5 / 30 = 38.3%** |

This percentage describes alignment with the proposed PRD architecture. It is not a general quality score for the existing notification code.

Plan 342 materially narrows GAP-N01 for fresh ordinary direct text, but no bounded A-control is fully closed by that slice. Plan 343 is reviewed planning only, not implementation evidence. The strict count therefore remains 2 Compliant, 19 Partial, 9 Missing, or **38.3%**.

Implementation status and proof status are kept conceptually separate throughout this assessment. A mechanism can exist but lack required runtime/device proof, or a test can pass while locking behavior that contradicts the PRD. `Partial` therefore never means accepted or release-ready.

Resolving an OQ changes PRD scope, decision wording, and proof obligations; it does not by itself change this current-code score. Re-score an A-control only after implementation/proof changes or an explicit PRD exception changes that control's required condition.

## 2. Scoring by PRD area

| PRD area | Controls | Weighted coverage | Assessment |
|---|---|---:|---|
| Architecture | A-01, A-05, A-17, A-25 | 1.5 / 4 = 37.5% | Event identity and Flutter convergence exist in part; opaque wake and universal normalization do not. |
| Delivery | A-02, A-03, A-04, A-08, A-15, A-18, A-26 | 3.5 / 7 = 50.0% | Strong inbox/push ordering and recovery pieces exist, but inbox custody is not universal and there is no outcome acknowledgement. |
| Privacy | A-06, A-07, A-16 | 0.5 / 3 = 16.7% | Provider payload shape directly conflicts with the PRD. |
| Decision behavior | A-21, A-22, A-23, A-24, A-28, A-29 | 2.0 / 6 = 33.3% | Exact-chat suppression exists; fresh lifecycle authority and the final decision gate do not. |
| iOS | A-09, A-10, A-11 | 2.0 / 3 = 66.7% | A real NSE and strong App Group primitives exist, but the NSE decrypts push content instead of fetching the inbox. |
| Android | A-12 | 0.5 / 1 = 50.0% | High-priority data delivery exists, but not the fixed wake/native inbox-processing contract. |
| Native conversation presentation | A-14 | 0 / 1 | Neither iOS communication notifications nor Android MessagingStyle is implemented. |
| Shared data contract | A-27 | 0 / 1 | Several durable stores exist, but not one cross-owner `LocalNotificationRecord` ledger. |
| Observability | A-13, A-19 | 0.5 / 2 = 25.0% | Many outcomes are instrumented, but there is no complete per-wake outcome record and private identifiers remain in logs. |
| Test evidence | A-20, A-30 | 1.0 / 2 = 50.0% | Deterministic and Android device subsets exist; the required platform/race matrix is incomplete. |

## 3. Gap catalog, with P0 architectural contradictions first

### GAP-N01: The encrypted inbox is not the universal source of truth

**Priority:** P0 reliability and recovery invariant

**PRD connection**

- Executive summary responsibility 1 and core invariant 1
- Goals G-01, G-04, G-06
- Target architecture requirements 1, 3, and 6
- Delivery acknowledgement section 5.1
- A-01, A-02, A-03, A-17, A-18, A-24, A-26
- AC-04, AC-05, AC-10, AC-12

**Current behavior and bounded progress**

- Plan 342 closed the live-ACK cancellation window for newly authored ordinary direct text to the current target peer. Eligible sends fail closed without the custody capability (`lib/features/conversation/application/send_chat_message_use_case.dart:540-573`), then atomically stage the message and exact encrypted envelope before transport (`:830-881`). DB v108 owns the status-independent row, and only a typed `stored` or `duplicate` completion retires it (`:1021-1068`; `lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart`). Startup/reconnect/network-restored/periodic/resume reuse one production drain (`lib/app/bootstrap/production_application_bootstrap.dart:5761-5771`, `:5975`, `:6419`).
- Plan 342 also cryptographically binds current edit identity and namespaces relay target/edit dedupe keys, but this prevents a collision with retained initial text; it does **not** put edits into the custody outbox (`go-relay-server/inbox.go:1310-1335`).
- Direct reaction ADD/REMOVE still author local state only after network success, skip inbox on connected live success, and return before authorship when the node is stopped (`lib/features/conversation/application/send_reaction_use_case.dart:49-57`, `:107-186`; `remove_reaction_use_case.dart:41-49`, `:99-172`). Plan 343 is reviewed and execution-ready for this bounded sender-custody slice, but no Plan 343 production code exists yet.
- Direct media/voice/private/disappearing sends, edit/delete custody, every-device fanout, and the group inbox-first/truthful-order contract remain open. Group pubsub and inbox work still launch concurrently rather than establishing inbox custody first: `go-mknoon/node/pubsub.go:367-453`.
- When a direct inbox path is used, the relay stores before push generation (`go-relay-server/inbox.go:1405-1486`). However, a full direct inbox evicts the oldest unacknowledged event and returns `stored` (`go-relay-server/backend_memory.go:114-153`; `backend_redis.go:263-321`), which still conflicts with PRD §5 removal only after recipient ACK or expiry.

**Risk**

For fresh ordinary direct text, the sender-held persistence-only window is now closed through relay acceptance. Equivalent windows remain for reactions and other event lanes, and current relay overflow can still discard an older unacknowledged event after a sender has transferred custody. None of this supplies the completed local notification outcome required by GAP-N03, so a recipient can still persist an event and suspend before presentation ownership is established.

**Required target change**

- Define one authenticated event envelope and commit it to the recipient-device inbox for every notification-worthy direct and group event.
- Treat direct/pubsub success as latency optimization, not authorization to cancel inbox custody or wake ownership.
- Preserve per-device expiry and acknowledgement semantics.
- Replace oldest-unacknowledged direct-inbox eviction with a compatible non-destructive capacity contract before claiming PRD ACK-or-expiry custody; this requires an explicit mixed-version/capability rollout because installed clients currently rely on the full-inbox `OK` response.
- Decide whether sender latency waits for inbox commit or whether a separate durable coordinator owns asynchronous commit completion, but do not let direct acknowledgement erase the obligation.

**Acceptance evidence required**

- Direct success followed by recipient background/suspend/crash still leaves recoverable inbox custody.
- Group pubsub success with inbox delay/failure cannot be reported as fully durable.
- Launch/resume/reconnect/push receipt reconcile all retained events exactly once.
- AC-04, AC-05, AC-10, and AC-12 pass for implemented text, media, reaction, direct, and group events. A first-class mention event is `N/A` unless separately approved and introduced.

### GAP-N02: APNs/FCM payloads violate the fixed opaque wake privacy contract

**Priority:** P0 provider-privacy invariant

**PRD connection**

- Goal G-02
- Privacy contract section 4
- Target architecture requirements 4 and 5
- Platform payloads sections 7.1 and 7.2
- A-05, A-06, A-07, A-12, A-16
- AC-11
- Immediate red flag: sender/chat/group/message/event/media metadata in push

**Current behavior**

- Direct push data includes `type`, `sender_id`, optional `message_id`, and KEM/ciphertext/nonce fields: `go-relay-server/inbox.go:426-460`, `:902-920`.
- Group push data includes `type`, `groupId`, `sender_transport_peer_id`, optional `message_id`, key epoch, ciphertext, and nonce: `go-relay-server/inbox.go:555-599`, `:922-956`.
- APNs copies the data into custom payload fields and may also use the conversation identifier as `thread-id`: `go-relay-server/inbox.go:602-632`, `:894-899`.
- Oversized fallbacks deliberately preserve routing identifiers: `go-relay-server/inbox.go:693-842`.
- The physical APNs adapter requires the rich route fields and stages them for proof: `integration_test/scripts/ios_notification_provider_adapter.py:449-521`.
- The iOS NSE branches on event type and consumes sender/group/message identifiers plus encrypted fields: `ios/NotificationService/NotificationPreviewResolver.swift:350-427`, `:435-570`, and `:1023-1135`.
- Push tokens are stored in a separate backend, but the backend is directly keyed by stable peer identity and stores provider-token material rather than using an opaque push handle: `go-relay-server/push_token_store.go:10-53` and `go-relay-server/backend_redis.go:951-1005`.

**Risk**

Apple/Google can observe social-graph and event-routing metadata. Payload shape varies by event type. Current tests positively enforce the behavior the PRD forbids, so implementation and tests must migrate together.

**Required target change**

- Introduce the PRD's opaque push-handle boundary between message code and the provider gateway.
- Make message code emit only a mailbox-dirty command, not an APNs/FCM message derived from event content.
- Use one fixed versioned provider payload for every event kind.
- Remove provider-visible thread, sender, group, message, reaction, media, deep-link, relay, and event-type fields.
- Define provider TTL, priority, topic, expiry, and collapse semantics exactly once.
- Encrypt provider tokens at rest and separate the opaque handle lookup from social/conversation data.

**Acceptance evidence required**

- Byte-level forbidden-field and fixed-shape tests across every implemented producer: text, image, voice, reaction, direct, group, and oversized events. A first-class mention fixture is `N/A` unless that event lane is separately approved and introduced.
- Captured APNs and FCM requests match the PRD examples, including `collapse-id/collapse_key = mailbox` and bounded expiry/TTL.
- Old rich-payload fixtures are removed or explicitly retained only for a time-bounded compatibility path.
- AC-11 passes against actual provider-bound requests.

### GAP-N03: There is no completed local outcome protocol

**Priority:** P0 delivery/presentation ownership invariant

**PRD connection**

- Target architecture section 5.1
- Decision matrix and sections 6.1 through 6.3
- Device-local `WakeOutcomeAck` contract in section 8
- A-13, A-24, A-26
- AC-04 and AC-05

**Current behavior**

- No production `WakeOutcomeAck`, `wake_not_required`, or equivalent opaque outcome contract exists.
- Plan 342 prevents direct/authenticated delivery from cancelling the sender-owned custody row for fresh ordinary direct text, but it does not record a completed recipient-side policy/presentation outcome. Reactions and the remaining GAP-N01 lanes still retain their older reachability-dependent custody behavior.
- Relay inbox store normally starts push immediately after commit; it has no bounded coordinator debounce waiting for a completed local outcome.
- Background and foreground handlers emit many diagnostic outcomes, but those logs are not a durable sender/gateway decision protocol.

**Risk**

Transport success, durable persistence, local suppression, local notification publication, and provider presentation ownership remain different facts without one explicit state machine. Later changes could accidentally suppress recovery from a transport acknowledgement or generate duplicate alerts from competing owners.

**Required target change**

- Define the opaque correlation/generation used by the wake coordinator.
- Record a completed outcome only after one of the PRD-approved terminal results: in-chat completion, local OS publication/update, or intentional local policy suppression.
- Ensure inactivity, background transition, suspension, timeout, or crash before completion leaves the wake required.
- Keep private UI context and detailed suppression reasons off the wire.

**Acceptance evidence required**

- Delivery ACK without outcome still produces/retains the generic wake.
- Every legitimate high-priority wake reaches visible, intentionally suppressed, or failed/retryable state.
- Crash-after-persistence-before-outcome recovers from inbox plus generic wake.
- Duplicate/out-of-order outcome acknowledgements are idempotent.

### GAP-N04: No single fresh lifecycle and visible-conversation authority exists

**Priority:** P0 lifecycle and suppression safety

**PRD connection**

- Core invariant 5
- Target architecture requirements 8 and 9
- Decision matrix section 6
- Foreground/background transition section 6.3
- `AppVisibilitySnapshot` contract in section 8
- A-21, A-22, A-23, A-24, A-28
- AC-01 through AC-04 and AC-07

**Current behavior**

- `ActiveConversationTracker` stores only an in-memory normalized conversation key: `lib/core/notifications/active_conversation_tracker.dart:5-49`.
- It has no lifecycle enum, freshness timestamp, process-sharing mechanism, or App Group/native projection.
- Several production lifecycle getters treat `WidgetsBinding.instance.lifecycleState == null` as `resumed`: `lib/app/bootstrap/production_application_bootstrap.dart:4567-4573`, `:4630-4636`, and `:4692-4696`.
- The foreground decision correctly suppresses only `resumed + exact conversation`: `lib/features/push/application/show_notification_use_case.dart:111-128`.
- iOS NSE, Android background handling, and reconcilers use separate state and policy paths rather than one authoritative snapshot.

**Risk**

An unknown or stale state may fail toward suppression instead of notification. The direct conversation remains marked active until disposal and does not clear the tracker on pause, so a still-mounted screen can be treated as visible after the app has left the foreground.

**Required target change**

- Define the authoritative lifecycle owner and monotonic freshness bound.
- Persist/project `FOREGROUND_ACTIVE`, `INACTIVE`, and `BACKGROUND` plus the local visible-conversation key to native-shared state.
- Write the snapshot on active, visible-chat change, resign-active/onPause, background, and route changes.
- Make unknown/stale state fail toward notification.
- Make all owners consume the same decision input contract.

**Acceptance evidence required**

- Same-chat suppression only under a fresh foreground-active exact match.
- Chat B and non-chat screens still notify for A.
- Resign-active/onPause immediately invalidates suppression.
- Unknown/stale snapshot tests fail toward notification.
- iOS NSE, Android service, main app, and reconciler use the same snapshot semantics.

### GAP-N05: The immediate pre-effect lifecycle/read gate is missing

**Priority:** P0 race and stale-notification safety

**PRD connection**

- Target architecture requirement 9
- Transition/race rules section 9
- A-28 and A-30
- AC-06, AC-07, and AC-08

**Current behavior**

- `maybeShowNotification` captures lifecycle and visible conversation once, then awaits remote-announcement gates, durable claims, tone ownership, and snapshot loading before invoking the native show boundary: `lib/features/push/application/show_notification_use_case.dart:111-203`, `:269-360`.
- It does not re-read lifecycle, visible conversation, or canonical read state immediately before publication.
- The Android background path has useful post-show exact-generation retirement fences: `lib/features/push/application/background_message_handler.dart:1069-1200`. A post-show cleanup is not the same as preventing the stale alert or sound.
- Stable per-conversation notification IDs and generation-safe cancellation exist: `lib/core/notifications/flutter_notification_service.dart:305-385`, `:432-565`.

**Risk**

Opening a chat or backgrounding the app while notification construction is in flight can produce a stale card, a brief incorrect alert, or a missed notification depending on which stale state wins.

**Required target change**

- Put the final check inside the serialized native publication/update/cancel boundary.
- Re-read fresh lifecycle, visible conversation, verified read/deleted state, policy, and current ledger revision.
- Use compare-and-swap/generation semantics so an older owner cannot overwrite a newer read or notification generation.

**Acceptance evidence required**

- Deterministic open-during-build and background-during-build barrier tests.
- No stale audible alert when A becomes visible before post.
- Background transition between initial decision and post still produces an OS notification or preserves confirmed provider ownership.
- Late wake after read/delete/expiry cannot recreate a card.

### GAP-N06: Notification state is split across multiple stores instead of one atomic ledger

**Priority:** P0 cross-owner convergence architecture

**PRD connection**

- Core invariant 7
- Target architecture requirement 7
- Platform sections 7.1 and 7.2
- `LocalNotificationRecord` and concurrency contract in section 8
- A-15, A-25, A-27, A-28
- AC-10

**Current behavior**

Strong but separate mechanisms exist:

- durable event and tone claims: `lib/core/notifications/durable_notification_tone_lease.dart`;
- stable conversation ID and content-generation registry: `lib/core/notifications/flutter_notification_service.dart` and related durable registry classes;
- direct/group SQLCipher display, read, and reconciliation outboxes;
- iOS App Group recovery and Apple request custody: `ios/NotificationService/IosNotificationRecovery.swift`;
- Android dropped-push recovery state;
- recent remote/background announcement gates.

No one record atomically contains authenticated event identity, conversation key, read state, presentation state, owner, stable notification key, last lifecycle, and revision across main app, NSE, Android receiver, and reconciler.

**Risk**

Each subsystem can be internally correct while cross-owner state diverges. This complicates duplicate prevention, read cancellation, crash recovery, migration, and proof of exactly one current card/normal alert.

**Required target change**

- Specify one logical ledger schema and state machine before choosing storage implementations.
- Define which fields must be shared across processes and which can remain platform-local projections.
- Define atomic claim, publish, suppress, cancel, read, retry, and reconciliation transitions.
- Migrate existing claims/registries/outboxes without losing current generation safety.

**Acceptance evidence required**

- Main app, NSE/FCM receiver, WorkManager, and reconciler race on one event without duplicate alert or lost notification.
- Crash at every transition has a deterministic recovery owner.
- Read/cancel of one conversation cannot clear another or a newer generation.
- Ledger migration and rollback tests cover old persisted state.

### GAP-N07: iOS NSE processes rich push content rather than syncing the inbox

**Priority:** P0 iOS dependency of the provider-privacy migration

**PRD connection**

- Platform section 7.1
- A-09, A-10, A-11, A-15, A-20
- AC-10, AC-11, AC-12

**Current behavior**

- A real `UNNotificationServiceExtension` is configured and does not start Flutter UI: `ios/NotificationService/NotificationService.swift:4-84`.
- It reads shared Keychain/App Group projections and decrypts provider-carried ciphertext through the native Go bridge.
- It has no relay/inbox fetch client under `ios/NotificationService/`.
- On unresolved expiry, content is cleared and made passive instead of preserving the required generic fallback: `ios/NotificationService/NotificationPreviewResolver.swift:148-172` and `ios/NotificationService/NotificationService.swift:86-93`.
- App Group recovery uses atomic locks, fsync/rename, generation fencing, and exact removal; these are strong reusable primitives: `ios/NotificationService/IosNotificationRecovery.swift` and `ios/Runner/IosNotificationRecoveryCoordinator.swift:166-250`.

**Risk**

The NSE depends on the rich payload contract that the PRD removes. A payload migration without an inbox-fetch replacement would eliminate private preview resolution and could yield blank/passive or generic notifications.

**Required target change**

- Give the NSE a bounded inbox reconciliation/decryption path that does not start Flutter UI.
- Preserve generic localized content when inbox/key/policy work cannot finish.
- Use the shared visibility snapshot and ledger for policy, ownership, dedupe, and exact replacement.
- Prove Keychain and file-protection behavior for locked and before-first-unlock states.

**Acceptance evidence required**

- Actual APNs requests use only the generic shape.
- NSE success enriches from inbox; NSE timeout/failure leaves generic content intact.
- Foreground, inactive, background-running, suspended, terminated, locked, before-first-unlock, and force-quit cases are recorded on an available iPhone target during the consolidated iOS closure phase in GAP-N12, not as a per-gap implementation gate.
- Deterministic Swift/native tests prove concurrent main-app/NSE claim semantics during implementation; one real main-app/NSE realization in the consolidated iOS closure phase produces one alert and one ledger record.

### GAP-N08: Android does not implement the PRD's native inbox-processing service contract

**Priority:** P0 Android background-reliability dependency

**PRD connection**

- Platform section 7.2
- A-12, A-13, A-14, A-15, A-20, A-27, A-28
- AC-04, AC-07, AC-10, AC-11, AC-12

**Current behavior**

- The manifest replaces FlutterFire's declared service with an app-owned subclass: `android/app/src/main/AndroidManifest.xml:110-119`.
- `MknoonFirebaseMessagingService` only overrides `onDeletedMessages`; ordinary message delivery remains FlutterFire/background-Dart driven: `android/app/src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt:13-71`.
- WorkManager continuation exists for dropped-batch recovery, not as the normal continuation for inbox sync/private rendering: `android/app/src/main/kotlin/com/mknoon/app/HeadlessCanonicalRecoveryWorker.kt:323-440`.
- The Dart background handler has extensive local decryption, policy, claims, stable IDs, native show, and post-show fences: `lib/features/push/application/background_message_handler.dart`.
- Android renders conversation history with `InboxStyleInformation`, not `NotificationCompat.MessagingStyle`: `lib/core/notifications/local_notification_support.dart:69-110`.

**Risk**

The current background path depends on rich FCM routing/ciphertext and a Flutter background isolate. It does not satisfy the fixed-wake, native inbox-sync, bounded processing-window, or native conversation-style contract.

**Required target change**

- Decide the native/FVM boundary for generic wake receipt, inbox fetch, decryption, policy, ledger mutation, and rendering.
- Add expedited WorkManager continuation for work that exceeds the initial FCM window.
- Post a generic local fallback when private resolution cannot finish, then replace the same stable conversation notification ID.
- Adopt `MessagingStyle` and privacy-sensitive lock-screen configuration.

**Acceptance evidence required**

- Fixed `{w:"1",v:"1"}` high-priority data payload, 300-second TTL, and `mailbox` collapse key.
- Normal FCM receive, WorkManager continuation, retry, permission denied, disabled channel, Doze, token refresh, and OEM-restriction cases.
- Direct, FCM, WorkManager, and reconciler share ledger and final lifecycle gates.

### GAP-N09: Native conversation presentation is absent

**Priority:** P1 user experience after local-private rendering is stable

**PRD connection**

- Goal G-03
- Platform sections 7.1 and 7.2
- A-14

**Current behavior**

- Android uses category `message` with `InboxStyleInformation`, not `NotificationCompat.MessagingStyle`.
- No iOS `INSendMessageIntent`/communication-notification implementation was found.

**Required target change**

- Define the local identity/person/conversation projection needed by both platforms without exposing it to the provider.
- Add iOS communication notifications and Android MessagingStyle only after the generic-wake/private-local-render boundary exists.
- Preserve stable conversation replacement and exact generation cancellation.

**Acceptance evidence required**

- Native style construction/identity tests run for both platforms during implementation, with Android device screenshots/notification assertions collected continuously.
- iOS Notification Center, communication presentation, and lock-screen privacy assertions are deferred to the consolidated GAP-N12 iOS closure phase.
- Text/media/reaction/group cards update the same conversation card without duplicate sound; host/native tests prove the modality matrix and the final device campaigns prove each platform-owned presentation seam.

### GAP-N10: Logging and analytics still expose private or social-graph identifiers

**Priority:** P0 diagnostic privacy

**PRD connection**

- Goal G-07
- Privacy contract section 4
- A-13 and A-19

**Current behavior**

- Relay logs include truncated stable recipient/sender/group identifiers: `go-relay-server/inbox.go:151-165`, `:285-316`, `:1405-1484`, and `:1631-1695`.
- Debug chat logging includes message text previews, message IDs, and peer-ID prefixes: `lib/core/utils/chat_console_logger.dart:13-63`.
- Some Flutter notification events include contact prefixes, sender names, and route payloads: `lib/core/notifications/flutter_notification_service.dart:370-380`.
- The flow-event sanitizer protects many secret/plaintext keys, but intentionally leaves short peer prefixes intact: `lib/core/utils/flow_event_emitter.dart:140-149`.
- The NSE has a public allowlisted log, but also writes the full event details dictionary through `NSLog`; some events include raw push ID/type: `ios/NotificationService/NotificationPreviewResolver.swift:174-239`, `:358-380`.

**Risk**

Production or captured diagnostic logs can reveal stable social-graph correlations even when payload content is encrypted.

**Required target change**

- Establish one privacy-safe diagnostic schema using opaque per-attempt/generation correlations and coarse outcome enums.
- Remove tokens, plaintext, stable IDs, sender/group names, route payloads, and deterministic prefixes from logs and analytics.
- Separate temporary debug/device-proof instrumentation from production logging with explicit compile/runtime gates and retention rules.

**Acceptance evidence required**

- Static forbidden-key/value tests across Go, Dart, Swift, and Kotlin emitters.
- Runtime captured-log canaries prove no token, plaintext, peer/group/message ID, or social-graph prefix escapes. Collect Android captures during implementation and the minimum iOS capture in the consolidated GAP-N12 phase.
- Every legitimate wake remains diagnosable through privacy-safe outcome correlation.

### GAP-N11: Cleanup and read targets remain undecided; device-local linked-read and group-mute baselines need PRD adoption

**Priority:** P0 incorrect-read/stale-notification risk; OQ-02/OQ-03 decisions and OQ-04/OQ-05 adoption/proof required

**PRD connection**

- Decision sections 6.1 and 6.4
- Transition rules section 9
- A-18, A-28, A-29, A-30
- AC-01, AC-06, AC-08, AC-09
- OQ-02/OQ-03 target decisions
- OQ-04 negative device-local answer and OQ-05 group-only baseline

**Current behavior**

- Notification suppression returns without directly marking read.
- Exact read-driven cancellation is strong: `lib/core/notifications/direct_notification_read_projector.dart:20-56` and related group projectors capture a generation, commit read state, then cancel only that generation.
- Direct conversation UI marks the conversation read on initial load and on new incoming rows while the widget remains mounted: `lib/features/conversation/presentation/screens/conversation_wired.dart:1139-1152`, `:2164-2200`, and `:2275-2299`.
- Direct lifecycle handling does not gate those calls or clear active-conversation state on pause: `lib/features/conversation/presentation/screens/conversation_wired.dart:6539-6551`.
- Group conversation read handling requires resumed lifecycle and exact tracked group: `lib/features/groups/presentation/screens/group_conversation_wired.dart:695-709`, `:1119-1133`.
- iOS reconciliation distinguishes user dismissal from canonical retirement and removes exact identifiers: `ios/Runner/IosNotificationRecoveryCoordinator.swift:219-250`.
- Linked-device clearing has a negative current answer: group unread and local-notification state are explicitly device-local, and sibling-device tests preserve independent unread state. A limited inbound group read-receipt parser is not an end-to-end same-account clearing protocol. No direct linked-device read path exists.
- Group-only, installation-local mute exists in UI/SQL. Flutter and Android prevent the local `.show`; the iOS NSE sanitizes muted content to empty/passive/silent, but absence of a blank passive item still requires available-iPhone proof. The canonical app-icon badge projection excludes muted groups while in-app unread remains unchanged; no independent Android app-badge counter is claimed. No direct/global/timed mute exists, and there is no first-class mention semantic or override.

**Risk**

The direct and group products currently implement different read predicates. A mounted background direct chat can potentially mark new events read. Later notification work cannot safely implement delayed-wake suppression until the authoritative local predicate is decided. Cross-device clearing should remain out of scope under the current device-local contract.

**Required target change**

- Resolve the OQ-02 cleanup and OQ-03 read decisions; adopt OQ-04's negative device-local answer and OQ-05's existing group-only scope. Track platform presentation proof under GAP-N12.
- Keep read, dismiss, notification cleanup, and local mute as separate state transitions. Any future linked-device control remains a separately approved state transition and protocol.
- Reuse exact generation cancellation while moving ownership into the shared ledger.
- Scope mute to the existing group behavior unless a separate product decision introduces direct/global mute.

**Acceptance evidence required**

- Dismiss never marks read.
- Every retained local read trigger follows the approved predicate; unapproved scroll-to-latest and OS `Mark Read` behavior remain absent.
- Read cancels only the intended conversation generation.
- Delayed wake after verified read/delete does not recreate a card.
- Preserve sibling-device unread/notification independence. Linked-device clearing tests are required only if a future separately approved protocol adds that behavior.
- Group mute semantics are tested separately for sound, vibration, banner/card, app-icon badge versus in-app unread, reactions, existing-card retirement, and device locality. Host/Swift tests cover the policy and sanitizer during implementation, while GAP-N12's consolidated iOS phase must prove no blank passive item or receive an explicit design resolution. A static scope sentinel plus ordinary `@`-text parity replaces a nonexistent first-class mention test.

### GAP-N12: Required cross-path and real-device proof is incomplete

**Priority:** Final P0 release-evidence gate after GAP-N01 through GAP-N11 are code-complete and their deterministic/native/Android gates pass

**PRD connection**

- A-20 and A-30
- Core acceptance criteria AC-01 through AC-12
- Required tests section 13
- OQ evidence requirements

**Current evidence**

- Deterministic Dart, Go, Swift, Kotlin, SQLCipher, and integration fixtures are extensive.
- Fresh host verification on 6 August 2026 passed:
  - `flutter test test/features/push/application/show_notification_use_case_test.dart` — 54 tests passed.
  - `cd go-relay-server && go test ./... -run '^TestRelayNotificationClosure_'` — passed.
- Persisted Android subset proof exists in:
  - `build/sims/latest/plan330-reaction-campaign-report.json` — five group message/reaction scenarios passed on physical Android `21071FDF600CSC` plus emulator `emulator-5554`.
  - `build/sims/latest/plan330-projection-report.json` — exact read-zero cancellation and media-reaction projection passed on the same pair.
- Both reports are filtered and explicitly not release eligible.
- `build/sims/latest/report.json` records Android recovery-completion as blocked because the registered automated proof driver is not implemented.
- Android and iOS payload campaigns are registered in `tool/sims/critical_features.json`, but no persisted local PASS report was found for the full payload campaigns.
- A real-SQLCipher group-mute device test exists and is registered: `integration_test/group_mute_notification_db_proof_test.dart:1-16`, `:73-115` and `scripts/check_reliability_simulation_discovery.sh:635`. No retained current-matrix artifact was found proving the full Android mute effect, and no retained iPhone artifact proves absence of a blank passive muted item.
- No persisted complete iPhone foreground/inactive/background/suspended/terminated/locked/before-first-unlock/force-quit matrix was found.
- No persisted complete Android Doze/permission/channel/token-refresh/OEM matrix was found.

**Required target change**

- Replace current rich-payload closure tests with target fixed-shape/privacy tests as the architecture migrates.
- Add deterministic barriers around every final-gate and cross-owner race.
- Use two explicit proof phases: finish GAP-N01 through GAP-N11 with deterministic host/native tests and continuous Android device proof, then run the necessary simulator/physical-iPhone evidence once as a consolidated iOS closure phase.
- Keep Swift/NSE/Runner code compile-clean and run focused native unit tests whenever it changes; only Apple-owned device/OS evidence is deferred.
- Reuse bounded pieces of the existing signed-app/APNs/XCUITest machinery after the fixed-wake contract stabilizes. Do not turn per-gap work into a generic multi-payload, multi-iPhone, or device-lab harness project.
- Complete only availability-bounded device legs under the repository's device policy; unavailable versions remain `N/A (target unavailable by project policy)`.
- Separate filtered diagnostic campaigns from release-eligible closure runs.

**Acceptance evidence required**

- All ten PRD test families have a named host/native/device proof boundary.
- GAP-N01 through GAP-N11 have green focused host/native gates and retained Android proof before the consolidated iOS phase begins.
- Required device campaigns produce persisted, provenance-bound verdict artifacts.
- One bounded iOS closure campaign covers only claims that Android, host tests, and native tests cannot prove: real APNs/NSE execution, Apple lifecycle/lock states, native presentation, main-app/NSE ownership, delivered-card/badge cleanup, privacy-safe device logs, and no blank/passive muted item.
- A wave-level full `host-all` runs after the implementation dependency wave; after any iOS-found fixes, the affected gates and consolidated iOS campaign rerun, followed by final rollout/release closure.

## 4. A-01 through A-30 traceability matrix

Legend:

- **Compliant:** The current implementation satisfies the control's core condition.
- **Partial:** Useful implementation exists, but at least one required path, invariant, or proof is absent.
- **Missing:** The defining target mechanism is absent or current behavior directly contradicts it.

| ID | Status | Current coverage and exact evidence | Gap to close before PRD compliance |
|---|---|---|---|
| A-01 | Partial | Sender-generated identities are reused and receiver persistence deduplicates them. Plan 342 binds fresh ordinary direct text to one immutable envelope/outbox incarnation and gives current edits matching authenticated outer/inner `eventId` plus a separate relay namespace. Direct reactions already enforce outer/inner event, action, and target parity. Group pubsub and inbox reuse one envelope: `go-mknoon/node/pubsub.go:388-453`. | Extend one authenticated `event_id` and content hash contract across every direct/group event, recipient device, relay entry, replay, and notification ledger; Plan 343 is planning only and does not supply universal identity/custody. |
| A-02 | Partial | Relay inbox paths commit before push (`go-relay-server/inbox.go:1405-1486`, group `:1645-1707`), and Plan 342 makes fresh ordinary direct-text sender custody independent of live ACK through DB v108. | Extend sender/inbox custody to reaction, media, edit/delete, group, and every-device lanes; make relay capacity non-destructive for unacknowledged rows and group durability independent of concurrent pubsub. |
| A-03 | Partial | Non-destructive pending retrieval and explicit stable-entry ACK exist (`go-relay-server/inbox_store.go:17-29`, `go-relay-server/inbox.go:1526-1545`); Plan 342 stages exact text custody before transport and retires the sender row only on typed relay acceptance. | Retire the legacy destructive retrieve API, eliminate oldest-unacknowledged relay eviction, extend exact sender custody beyond bounded text, and decide whether encrypted staging before successful decrypt/canonical persistence meets the final durable-ack contract. |
| A-04 | **Compliant** | Group reliable send stores to group inbox independently of pubsub: `go-mknoon/node/pubsub.go:367-453`; relay group inbox is non-destructive. | Preserve this property while moving to inbox-first custody and generic wake. |
| A-05 | **Missing** | Relay message code builds provider payloads from message envelopes: `go-relay-server/inbox.go:426-632`. | Introduce `mailbox_dirty(push_handle)` and a provider gateway that knows no message/conversation data. |
| A-06 | **Missing** | Payload builders include forbidden sender/group/message/event routing fields. | Replace with one fixed generic payload and byte-level privacy tests. |
| A-07 | Partial | Push tokens have a separate backend and authenticated registration, but storage is keyed by stable peer ID. | Add opaque handles, encrypted token storage, data separation, rotation, and least-privilege lookup. |
| A-08 | Partial | Startup and `onTokenRefresh` registration, authenticated unregister, invalid-provider-token eviction, and migration cleanup exist. | Prove logout/account removal, APNs/FCM environment separation, stale-token cleanup, retry, and multi-device token lifecycle end to end. |
| A-09 | **Compliant** | APNs uses visible alert delivery with mutable-content and a real NSE: `go-relay-server/inbox.go:602-632`, `ios/NotificationService/NotificationService.swift:4-84`. | Preserve alert-class delivery while replacing rich custom data with the generic payload. |
| A-10 | Partial | NSE decrypts without Flutter UI startup using shared keys/native bridge. | Fetch/reconcile the durable inbox instead of decrypting provider-carried event material; preserve generic fallback on timeout/failure. |
| A-11 | Partial | App Group locks, atomic fsync/rename, generation fencing, Keychain projections, and native concurrency tests exist. | Prove the target shared ledger, SQLCipher/file protection boundary, locked/before-first-unlock behavior, and main-app/NSE concurrency. |
| A-12 | Partial | Ordinary Android notifications use high-priority data delivery and local private rendering. | Adopt exact `{w,v}` fixed shape, TTL/collapse contract, native inbox sync, normal WorkManager continuation, and remove rich route/ciphertext dependence. |
| A-13 | Partial | Background and relay paths record many success/suppression/failure outcomes. | Define one durable per-wake visible/suppressed/failed outcome state and opaque completion protocol. |
| A-14 | **Missing** | Android uses InboxStyle; no iOS communication-intent implementation was found. | Add Android MessagingStyle and iOS communication notifications from locally resolved identities. |
| A-15 | Partial | Durable event/tone claims, recent-remote gates, stable IDs, and generation CAS substantially reduce duplicate alerts. | Unify all owners in one ledger; preserve generic fallback; prove one alert across main/background/NSE/reconciler and crash boundaries. |
| A-16 | **Missing** | Clear event types/identifiers and encrypted event material are provider-visible; tests require them. | Remove event/media/routing metadata from all provider shapes, including fallbacks and reactions. |
| A-17 | Partial | Reactions have stable event identity, receiver parity checks, LWW/tombstone dedupe, display outboxes, and local rendering. Unknown-presence sends start an inbox copy, but connected live success, node-stopped, and connected-throw paths have no durable sender obligation; local ADD/REMOVE commits after transport. Plan 343 is reviewed planning only. | Implement the reviewed direct ADD/REMOVE custody slice, then remove specialized rich reaction push lanes and normalize reactions into the generic-wake/inbox/ledger/decision pipeline without losing ordering or silent REMOVE behavior. |
| A-18 | Partial | Direct inbox addressing and ACK are per transport/device peer; Plan 342's durable text slice still targets only the current peer. Group tests explicitly keep unread and notifications device-local across siblings. | Specify and prove independent per-device event fanout, inbox cursors, and ACKs while preserving the resolved rule that a sibling read does not clear this device. |
| A-19 | **Missing** | Relay, Flutter debug, notification, and NSE logs can include stable ID prefixes, route data, or plaintext previews. | Implement one privacy-safe diagnostic schema and forbidden-data tests across all languages/build modes. |
| A-20 | Partial | Deterministic fixtures and extensive native/platform harnesses exist. Plan 342 adds current host, relay, discovery, and physical-Android SQLCipher migration/reopen receipts for its bounded text-storage boundary; broader Android/platform and presentation evidence is still incomplete. | After GAP-N01 through GAP-N11 pass their host/native and Android gates, produce current, provenance-bound real-iPhone APNs evidence in the consolidated GAP-N12 closure phase and complete the availability-bounded platform state matrix. |
| A-21 | **Missing** | Only in-memory active-chat tracking and ad hoc lifecycle reads exist; null may default to resumed. | Implement one authoritative fresh `AppVisibilitySnapshot` shared with native owners. |
| A-22 | Partial | Flutter suppresses only `resumed + exact conversation`; focused tests pass. | Apply the same fresh exact-thread rule to every native/background owner and invalidate it immediately on pause/resign-active. |
| A-23 | Partial | Flutter tests prove another chat/non-chat screen still notifies, and direct/group/reaction live projections use the same helper substantially. | Prove platform parity for implemented text, media, reaction, direct, and group paths across foreground and native owners. A first-class mention lane is `N/A` unless separately introduced. |
| A-24 | Partial | If Flutter is still executing with a correct lifecycle value, background state leads to local notification. Plan 342 removes the sender persistence-only window for fresh ordinary direct text through relay acceptance, but no completed recipient presentation outcome exists and other lanes remain reachability-dependent. | Extend custody across GAP-N01, then require confirmed local/provider presentation ownership before wake suppression. |
| A-25 | Partial | Most live Flutter direct/group/reaction paths call `maybeShowNotification`. | Normalize FCM background, iOS NSE, WorkManager, inbox replay, and reconciliation through one decision contract/state machine. |
| A-26 | **Missing** | No outcome ACK exists. Plan 342 prevents live delivery from cancelling fresh ordinary text sender custody, but neither that row nor any current protocol proves a completed local notification outcome, and the rule is not universal across event lanes. | Implement bounded debounce plus opaque `wake_not_required` only after a completed approved outcome. |
| A-27 | **Missing** | Several durable registries/outboxes exist, but no one cross-owner `LocalNotificationRecord`. | Define, persist, atomically mutate, migrate, and reconcile the PRD ledger across all owners. |
| A-28 | **Missing** | Stable IDs and post-show cleanup exist, but the defining immediate pre-post lifecycle/read check does not. | Put a fresh lifecycle/read/policy/revision check at every serialized post/update/cancel boundary. |
| A-29 | Partial | Suppression and user dismissal do not directly mark read, but ordinary direct/group chat-entry cleanup is currently achieved through read projection; generation-safe cancellation exists. | Separate activation cleanup from the approved read predicate, resolve the direct/group inconsistency, and prove a mounted background conversation cannot auto-read. |
| A-30 | Partial | Dedupe, claim, CAS, and some direct/FCM order tests exist. Plan 342 adds atomic stage/drain, relay namespace, lifecycle, account-transfer, migration, and real Android SQLCipher reopen/rollback tests for fresh text only. | Complete direct→push, push→direct, open-during-build, background-during-build, late-wake-after-read, relay-overflow, and crash-after-persistence tests across event kinds and owners. |

Primary control-to-gap index for later decomposition:

| Gap | Primary A-controls |
|---|---|
| GAP-N01 Universal inbox custody | A-01, A-02, A-03, A-04, A-17, A-18, A-24, A-26 |
| GAP-N02 Opaque fixed wake and token separation | A-05, A-06, A-07, A-08, A-12, A-16 |
| GAP-N03 Completed outcome protocol | A-13, A-24, A-26 |
| GAP-N04 Fresh lifecycle/visible conversation | A-21, A-22, A-23, A-24, A-28 |
| GAP-N05 Immediate final effect gate | A-28, A-30 |
| GAP-N06 Shared ledger and decision engine | A-15, A-25, A-27, A-28 |
| GAP-N07 iOS inbox-based NSE | A-09, A-10, A-11, A-15, A-20 |
| GAP-N08 Android native/background contract | A-12, A-13, A-14, A-15, A-20, A-27, A-28 |
| GAP-N09 Native conversation presentation | A-14 |
| GAP-N10 Privacy-safe observability | A-13, A-19 |
| GAP-N11 Cleanup/read decisions and device-local linked/mute baselines | A-18, A-28, A-29, A-30 |
| GAP-N12 Complete proof matrix | A-20, A-30 |

## 5. AC-01 through AC-12 traceability

| Acceptance criterion | Current result | Blocking gaps | Closure proof needed |
|---|---|---|---|
| AC-01: same-chat A while foreground-active | Partial | GAP-N04, GAP-N05, GAP-N11, GAP-N12; OQ-01 evidence and OQ-03 decision | Prove that an exact active chat updates its timeline and emits no card, sound, vibration, or app haptic on available iOS/Android for implemented direct/group text, media, and reaction paths. Record first-class mention as `N/A` under the approved absence decision. |
| AC-02: chat B still notifies for A | Partial | GAP-N04, GAP-N06, GAP-N12 | Cross-platform direct/group/text/media/reaction proof that B remains open and only A's stable card/unread state changes. |
| AC-03: non-chat screens still notify for A | Partial | GAP-N04, GAP-N06, GAP-N12 | Chat-list/settings/media-viewer tests across live, inbox, and provider-wake entry points. |
| AC-04: direct event after background cannot end persistence-only | Missing/Risky | GAP-N01, GAP-N03, GAP-N04, GAP-N05 | Plan 342 closes only the fresh ordinary-text sender-custody window. Add deterministic pause/background barriers plus suspend/crash recovery proving OS notification or confirmed provider ownership for every required event lane. |
| AC-05: delivery ACK without outcome does not suppress wake | Missing | GAP-N01, GAP-N03 | Plan 342 keeps fresh text custody after live delivery, but no recipient outcome exists. Add sender/recipient/gateway proof that transport and persistence ACKs leave wake required until an opaque completed outcome. |
| AC-06: open-during-build prevents stale A notification only | Missing | GAP-N04, GAP-N05, GAP-N06, GAP-N11; OQ-02 | Barrier test opening A between decision and post; A must not publish or alert. If A was already delivered, cleanup must be generation-exact and must not affect B or a newer A generation. Post-then-cancel is not success. |
| AC-07: background-during-build produces notification | Missing | GAP-N04, GAP-N05 | Barrier test transitioning inactive/background between initial decision and final effect; final recheck must post or retain provider owner. |
| AC-08: delayed wake after verified handled/read state does not recreate alert | Partial | GAP-N05, GAP-N06, GAP-N11; OQ-03 | Local read/delete/activation and delayed/out-of-order wake tests must not replace a newer/read generation. Preserve sibling-device unread/notification independence; cross-device clearing is outside this PRD unless separately approved. |
| AC-09: dismiss is not read; approved local triggers govern read | Partial | GAP-N11; OQ-02 and OQ-03 | Prove dismissal, activation cleanup, and every retained local read trigger against the approved predicate. Remove OS `Mark Read` from the PRD unless separately approved and implemented; prove a mounted background direct chat cannot auto-read. |
| AC-10: all path orders converge to one event/unread/card/normal alert | Partial | GAP-N01, GAP-N03, GAP-N05, GAP-N06, GAP-N12 | Preserve Plan 342's bounded text stage/drain and identity tests, then complete the arrival-order and crash matrix over event kinds, direct, pubsub, inbox, NSE/FCM, WorkManager, and reconciler. |
| AC-11: provider requests have no forbidden fields and one shape | Missing/Contradicted | GAP-N02, GAP-N10 | Captured APNs/FCM byte-shape assertions for all event kinds; current rich-route closure tests replaced or bounded to compatibility. |
| AC-12: launch after missed pushes synchronizes retained inbox exactly once | Partial | GAP-N01, GAP-N06, GAP-N12 | Plan 342 proves lifecycle retry for a bounded sender text outbox, not recipient launch reconciliation. Add a cold-launch retained-inbox campaign with multiple pages/event kinds, local dedupe, per-device ACK, and no duplicate card/unread/tone. |

## 6. Codebase answers to OQ-01 through OQ-05

The codebase provides a defensible **current-state answer to all five open questions**. That is not the same as satisfying the PRD's full closure bar: OQ-01 and OQ-05 still lack retained available-device evidence, while OQ-02 and OQ-03 expose target behavior that product must choose. OQ-04 has a clear negative answer and should no longer be described as unknown.

| OQ | Does the code answer current behavior? | Codebase answer | Ready to close in the PRD? |
|---|---|---|---|
| OQ-01 Same-chat cue | **Yes, intended code path** | Exact active chat while resumed takes the suppression path before tone reservation/native show, and the app adds no incoming-message haptic. The intended result is a visual timeline update without an OS card, sound, or vibration; physical output remains device-evidence debt. There is no mention-specific cue. | **Not evidence-closed.** Preserve this baseline unless product chooses a new cue. Collect Android traces during implementation and defer the minimum necessary iOS ringer/Focus evidence to the consolidated GAP-N12 closure phase. |
| OQ-02 Chat-open cleanup | **Yes, current mechanism** | A managed notification tap or a successful conversation read removes only the captured notification generation. Ordinary chat entry currently marks read, so open and cleanup are coupled. Open-during-build can post first and be cancelled afterward. | **No.** Keep the stable IDs and generation CAS, but decide an open/activation cleanup rule independent of OQ-03 and add the PRD's final pre-post gate. |
| OQ-03 Local read predicate | **Yes, but inconsistent** | Direct marks the whole conversation read on entry/load and on incoming rows while mounted, without lifecycle or scroll gating. Group requires resumed exact-group visibility, then marks the whole group read. | **No.** Product must approve these different rules or choose one shared predicate. |
| OQ-04 Linked-device read | **Yes: no** | Unread counters and local notification state are installation-local. Reading on a sibling device does not clear this device. No complete direct or group linked-device clearing protocol exists. | **Yes, if product accepts current scope.** Remove/narrow linked-device clearing requirements and tests; treat any future account-wide control event as separately approved work. |
| OQ-05 Existing mute | **Yes, for group scope** | Mknoon has indefinite, installation-local, per-group mute. Flutter/Android prevent local presentation; iOS sanitizes to empty/passive/silent, with blank-item visibility not yet device-proven. Delivery, persistence, and in-app unread remain. There is no direct/global/timed mute or first-class mention override. | **Not evidence-closed.** Preserve the scope; collect retained Android proof during implementation and defer iPhone blank-item/presentation proof to the consolidated GAP-N12 closure phase. If iOS surfaces a blank item, resolve the platform design before adopting “no visible notification” as PRD fact. |

### 6.1 OQ-01: same-chat sound and haptic

**Current answer.** The intended default is a silent visual update. When the process is `resumed` and the exact direct or group conversation is active, `maybeShowNotification` returns `terminalSuppressed` before reserving a tone or crossing the native show boundary: `lib/features/push/application/show_notification_use_case.dart:111-128` and `:269-359`. The direct timeline still inserts the incoming row, moves to the live edge when appropriate, and requests a read mark: `lib/features/conversation/presentation/screens/conversation_wired.dart:2188-2200` and `:2275-2299`.

Text and media use the same decision path; media only changes the notification copy: `lib/features/conversation/application/chat_message_listener.dart:674-705`. Direct reaction ADDs and group message/media/reaction paths also reuse this gate: `lib/features/conversation/application/handle_incoming_reaction_use_case.dart:376-413` and `lib/features/groups/application/group_message_listener.dart:1244-1275`, `:1364-1392`. No first-class mention notification path or incoming-message-specific `HapticFeedback`, system-sound, vibration, or in-chat cue setting was found. Existing haptics are interaction feedback; the 30-second `NotificationToneTracker` applies to notification cards, not an in-chat cue: `lib/core/notifications/notification_tone_tracker.dart:3-42`.

iOS foreground remote presentation is configured with alert, badge, and sound disabled, and `willPresent` forwards the event to Dart with those persisted zero-presentation options: `lib/app/bootstrap/production_application_bootstrap.dart:426-438` and `ios/Runner/AppDelegate.swift:230-266`. Deterministic tests prove exact direct/group suppression: `test/features/push/application/show_notification_use_case_test.dart:1153-1186`. The device harness only proves that no local `showMessageNotification` call occurred; it does not measure sound or haptic output: `integration_test/notification_sound_smoke_harness.dart:1067-1072`, `:1271-1305`.

**Remaining gap and PRD disposition.** There is no retained real-device matrix for text, media, reaction, ringer/Focus, Android channel settings, and group mute; mentions do not exist as a semantic event to test. Replace the provisional cue clause in the decision matrix, §6.1, A-22, AC-01, and §13 with the following if product approves the current behavior:

> When Mknoon is foreground-active in exact chat A, it updates A and emits no OS banner, notification sound, vibration, or app haptic. The visual timeline update is the only current cue. Mknoon has no in-chat cue setting and no mention-specific cue behavior.

Do not add a new haptic, sound, or setting as part of notification reliability work without a separate product decision.

Under the adopted sequencing in §9.1, deterministic and Android evidence for this behavior is collected while the gaps are implemented. The minimum Apple-owned sound/haptic and presentation observations are intentionally deferred to the final consolidated iOS closure campaign.

### 6.2 OQ-02: chat-open notification cleanup

**Current answer.** Two generation-safe cleanup triggers exist:

1. A managed local-notification tap decodes its typed payload and dismisses the captured generation. A warm tap starts dismissal before routing; cold local launch awaits it: `lib/core/notifications/flutter_notification_service.dart:115-230`. `ApplicationRoot` then routes direct notification targets to the ordinary `ConversationWired` screen: `lib/app/application_root.dart:1117-1119`, `:1706-1750`, and `:1816-1853`.
2. Opening a direct conversation sets the active peer and marks the whole conversation read after its initial page: `lib/features/conversation/presentation/screens/conversation_wired.dart:1103-1152`. The read projector snapshots the current card metadata, commits SQL read state, and cancels only that generation: `lib/core/notifications/direct_notification_read_projector.dart:20-56`. Group entry similarly projects cleanup after load, but only when resumed and viewing the exact group: `lib/features/groups/presentation/screens/group_conversation_wired.dart:695-709`, `:1888-1897`; its projector waits for zero unread and performs exact-generation cancellation: `lib/core/notifications/group_notification_read_projector.dart:261-327`.

Flutter local cards have one durable notification ID per normalized conversation and typed generation metadata: `lib/core/notifications/flutter_notification_service.dart:317-368`, `:432-565`. Direct show/read/reconcile mutations serialize per peer: `lib/core/notifications/direct_notification_presentation_coordinator.dart:3-35`. iOS separately records Apple request identifiers in an App Group recovery store and removes exact retired delivered requests: `ios/NotificationService/NotificationService.swift:115-194` and `ios/Runner/IosNotificationRecoveryCoordinator.swift:166-250`. No production pending-request removal path was found.

**Race gap.** The live show path checks lifecycle/active-chat state once, performs asynchronous work, and then posts without a final recheck: `lib/features/push/application/show_notification_use_case.dart:111-203`, `:269-359`. Serialization prevents an old cleanup from erasing a newer generation, but if the show owns the lane first, opening A waits behind it; the stale card can alert and then be exactly cancelled. The group regression test explicitly captures post-then-cancel behavior: `test/core/notifications/group_notification_read_projector_test.dart:61-109`. This is not AC-06's required prevention behavior.

**Recommended PRD wording.** Preserve the ID registry, typed generation CAS, exact sibling preservation, and iOS delivered-request custody. In §6.4, A-28, A-30, AC-06, AC-08, AC-09, and §13, define the target as:

> Chat-list, in-app-route, and notification-tap opens converge on exact-conversation activation. The notification owner cancels or updates only A's captured generation; opening does not itself define read. A final pre-publication lifecycle/activation/read gate prevents stale A without clearing B or a newer A generation.

That target requires a new cleanup trigger independent of the OQ-03 read decision and explicit main-app/Android-background/iOS-NSE/Runner ownership.

### 6.3 OQ-03: local read predicate

**Current answer.** There is no single predicate today:

- Direct unread state is `messages.read_at`. A read updates every visible incoming unread row for the peer, so text and media share the parent-message rule: `lib/core/database/helpers/messages_db_helpers.dart:466-485`.
- Direct marks on entry/load, recovery that surfaces an incoming row, and live incoming/repository rows while the widget remains mounted: `lib/features/conversation/presentation/screens/conversation_wired.dart:1139-1152`, `:1829-1853`, `:2162-2200`, and `:2275-2299`. `_markAsRead` has no lifecycle, exact-visibility, or scroll-position guard, and pausing only changes lifecycle state/recovery behavior: `:2072-2084` and `:6538-6551`.
- Group unread state is `group_messages.read_at`. A read updates all incoming unread rows in that group: `lib/core/database/helpers/group_messages_db_helpers.dart:864-893`. The UI requires resumed lifecycle and exact tracked group before marking after load, resume, or live update: `lib/features/groups/presentation/screens/group_conversation_wired.dart:695-709`, `:1119-1132`, `:1874-1897`, and `:4374-4407`.
- Reactions do not use ordinary message unread state. Conversation-level read acknowledges the current reaction card as notification state: `lib/core/database/helpers/direct_notification_read_projection_db_helpers.dart:71-118` and `lib/core/database/helpers/group_messages_db_helpers.dart:880-893`. No authoritative OS-notification `Mark Read` action was found.

**Remaining decision and PRD disposition.** The direct rule can mark a mounted but backgrounded conversation read and neither lane requires reaching the newest row. Replace generic “verified/explicit read predicate” language in the decision matrix, §§6.1 and 6.4, A-29/A-30, AC-01/AC-08/AC-09, and §13 only after product chooses either:

- one shared rule, preferably resumed exact-conversation visibility, with an explicit decision about scroll position; or
- deliberately different direct and group rules documented as above.

Keep read state separate from the OQ-02 activation cleanup trigger. Do not claim scroll-to-latest or an OS `Mark Read` action under current behavior.

### 6.4 OQ-04: linked-device read and clearing

**Current answer.** Linked-device clearing is not a current product behavior. The group contract explicitly classifies unread counters and local notifications as device-local, with each installation maintaining its own state: `lib/features/groups/domain/models/group_multi_device_policy.dart:3-40`, `:52-73`. The host convergence test proves that marking the phone read leaves the sibling tablet unread: `test/features/groups/integration/group_multi_device_convergence_test.dart:447-531`; the device harness carries the same assertion: `integration_test/group_multi_device_real_harness.dart:1644-1681`. No direct linked-device read path exists.

There is limited group inbox parsing for authenticated participant `read` receipts: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart:2462-2535`, `:2569-2583`. The database can apply a receipt attributed to the local peer and enqueue reconciliation: `lib/core/database/helpers/group_sync_receipts_db_helpers.dart:127-131`. No production outbound read-receipt emitter or end-to-end same-account control mapping was found, so this latent/participant receipt plumbing must not be mistaken for linked-device notification clearing.

**Recommended PRD wording.** Resolve OQ-04 negatively and narrow §6.4, A-18/A-30, AC-08, and §13 to:

> Read state, unread counters, badge contribution, and OS notification cleanup are installation-local. Reading on one linked device does not clear another device. Cross-device notification clearing is outside this PRD unless a separately approved authenticated control protocol defines offline delivery, ordering, and exact local generation mapping.

Remove linked-device clearing as a required acceptance leg. A test that sibling state remains independent is the preservation sentinel.

### 6.5 OQ-05: existing mute behavior

**Current answer.** Mknoon has one mute feature: an indefinite, installation-local, per-group preference.

- Group Info exposes the adaptive `Mute Notifications` switch: `lib/features/groups/presentation/screens/group_info_screen.dart:481-544`; the handler invokes `setGroupMuted`: `lib/features/groups/presentation/screens/group_info_wired.dart:822-846`.
- `GroupModel.isMuted` persists to SQLCipher `groups.is_muted`, defaulting to false: `lib/features/groups/domain/models/group_model.dart:83-84` and `lib/core/database/migrations/050_groups_mute_column.dart:6-32`. The use case and multi-device policy explicitly make it installation-local: `lib/features/groups/application/set_group_muted_use_case.dart:6-45` and `lib/features/groups/domain/models/group_multi_device_policy.dart:27-40`, `:52-73`.
- The shared Flutter policy rejects muted group display before posting; Android background processing reads the same database field: `lib/features/push/application/group_notification_display_policy.dart:88-116` and `lib/features/push/application/background_message_handler.dart:2991-3037`, `:3073-3137`. Host tests prove persisted/unread delivery without a Flutter card and no Android-background `.show`: `test/features/groups/application/group_message_listener_test.dart:14639-14721` and `test/features/push/application/background_message_handler_test.dart:3863-3923`.
- iOS notification projection includes the mute flag, and the NSE rejects ordinary messages and group reactions before decrypt/render: `lib/core/notifications/group_reaction_notification_projection.dart:141-184` and `ios/NotificationService/NotificationPreviewResolver.swift:786-815`, `:1023-1052`. Rejected content is cleared, made soundless/passive, and handed back to iOS: `ios/NotificationService/NotificationPreviewResolver.swift:148-172`, `:300-315`, `:1326-1365`. Native unit tests cover ordinary and reaction mute gates: `ios/RunnerTests/NotificationPreviewResolverTests.swift:292-335`, `:2810-2815`.
- Muted group rows remain delivered, persisted, and unread. The canonical app-icon badge projection excludes them: `lib/core/database/helpers/canonical_notification_badge_state_db_helpers.dart:99-142`; its fixture excludes the muted group at `test/core/database/helpers/canonical_notification_badge_state_db_helpers_test.dart:186-239`. This does not claim a separate Android app-badge writer; in-app unread remains present.
- Eligible group reactions use the same mute gate: `test/features/groups/application/group_message_listener_test.dart:15178-15215`. No mention model/notification lane exists, so mention-like `@` text follows ordinary group-message policy and has no independent bypass. No direct-chat, app-global, timed, or scheduled mute exists.
- Android uses shared audible and silent message channels rather than per-group channels; mute prevents posting: `lib/core/notifications/local_notification_support.dart:4-30`, `:72-110`. Muting also reconciles and retires the current managed group card: `lib/features/groups/data/repositories/group_repository_impl.dart:377-387` and `lib/core/notifications/group_notification_canonical_reconciler.dart:83-121`; the exact-card regression is `test/features/groups/application/group_notification_reconciliation_wiring_test.dart:171-197`.
- Device locality is an explicit preservation property: one sibling can be muted while the other remains unmuted, both retain unread, and only the unmuted sibling presents in the host convergence test: `test/features/groups/integration/group_multi_device_convergence_test.dart:447-525`.

The group repository also writes a `group_muted:<groupId>` Keychain sentinel: `lib/features/groups/data/repositories/group_repository_impl.dart:2201-2233`. The corresponding Swift key name is declared but not read; current NSE enforcement comes through the shared group notification projection. Treat the standalone sentinel as redundant/dead-projection risk, not a second mute owner.

**Confirmed scope to adopt in the PRD now:**

> Mknoon mute is an indefinite installation-local per-group preference. It does not suppress delivery, persistence, or in-app unread state and does not sync to sibling devices. Direct chats have no mute. Mknoon has no global or timed mute and no first-class mention semantic or override; mention-like text follows ordinary group-message policy.

**Target presentation effect, subject to platform evidence:**

> Muting a group must produce no visible or audible OS notification for group text, media, announcement messages, or eligible group reactions on that installation; it must retire the current managed group card and exclude muted group events from the applicable canonical app-icon badge state.

This is not evidence-closed. During implementation, run a retained available-Android campaign covering ordinary/reaction delivery, no card/sound/vibration, existing-card retirement, channel/app-badge observation, and preserved unread state. Because the iOS NSE cannot cancel the Apple notification in this path, it sanitizes content and still calls the content handler; defer the available-iPhone ordinary/reaction, badge, and background/terminated/locked proof to the consolidated GAP-N12 iOS closure phase. If iOS surfaces a blank passive item, that is a platform design blocker requiring an ownership/entitlement/presentation decision, not a passing mute result.

## 7. Reusable components to preserve

Later planning should avoid discarding these proven mechanisms merely because the top-level architecture changes:

1. Relay store-before-push ordering and duplicate suppression on actual inbox paths.
2. Non-destructive pending retrieval, stable relay entry ACK, paging, and expiry.
3. Local SQLCipher inbox staging and replay/quarantine ownership.
4. Plan 342's DB v108 immutable fresh-direct-text custody row, atomic local-message/envelope staging, typed relay completion, compare-and-delete retirement, and shared lifecycle drain cadence.
5. Sender-generated message/reaction identities and local database deduplication.
6. Plan 342's authenticated edit identity parity and cross-type-safe relay target/edit namespaces; these are identity primitives, not evidence that edit custody exists.
7. Direct-reaction outer/inner event, action, and target parity plus LWW/tombstone convergence; Plan 343 may extend these mechanisms but is not yet implementation evidence.
8. Durable event claims and per-conversation tone leases using file locking.
9. Stable conversation notification IDs and exact generation-safe replace/cancel.
10. Direct/group display, read, and reconciliation outboxes.
11. Exact frontmost-conversation suppression in the Flutter live path.
12. iOS App Group atomic file primitives, Apple request custody, badge serialization, and exact delivered-notification retirement.
13. Android dropped-FCM-batch durable marker and WorkManager recovery scaffolding.
14. Group mute UI/model/SQL state, shared display policy, iOS group-context projection, Android encrypted-database enforcement, and exact-card reconciliation. The standalone unused mute Keychain sentinel is excluded unless a consumer is explicitly assigned.
15. Existing deterministic fixtures, platform harnesses, and pinned device orchestration.

These components should be mapped into the new contracts rather than independently extended in ways that increase the number of notification owners.

## 8. Migration and compatibility hazards for later plans

### 8.1 Relay/client version skew

Current iOS NSE and Android background processing require rich provider fields. Switching the relay to a generic wake before compatible inbox-fetch clients ship would remove notification resolution for older clients. Plan 342 also introduced distinct current text/edit relay dedupe namespaces, so its relay behavior must precede dependent client activation. Plan 343 proposes a stricter reaction namespace but has not implemented it. Later planning needs explicit version/capability negotiation, staged relay-first rollout, machine-checkable activation, and a rollback boundary.

### 8.2 Current tests lock the old contract

Go and provider-adapter closure tests assert that routing fields survive platform projection and oversized fallback. These are not merely missing target tests; they will actively fail once the PRD privacy contract is implemented. Plans must name which tests are replaced, which remain as compatibility tests, and when legacy fixtures are deleted.

### 8.3 Persisted-state migration

Existing tone claims, recent-remote gates, conversation ID registries, iOS recovery JSON, Android recovery state, and SQLCipher outboxes now include Plan 342's DB v108 direct-text custody table. They may coexist with the new ledger during rollout. Owner precedence, one-time migration, rollback, account-transfer inventory, and garbage-collection rules need explicit design; future schema plans must preserve pending v108 text custody rather than silently recreating or omitting it.

### 8.4 Event-identity compatibility

Relay entry IDs, outer routing IDs, decrypted message IDs, reaction transition IDs, and notification event identities are not one uniform authenticated contract today. Plan 342 closes target/edit raw-ID collision for its current text/edit relay paths and authenticates current edit outer/inner identity; direct reactions already validate event/action/target parity. Those bounded improvements do not establish one universal identity/hash. A ledger migration must not merge distinct events or split one event into multiple alert identities.

### 8.5 Generic fallback ownership

iOS currently sanitizes some unresolved notifications and Android often creates a rich local card from pushed ciphertext. The target requires a generic visible fallback that is retained or updated safely. The transition must prevent both blank notifications and generic-plus-rich double alerts.

### 8.6 Token and environment migration

Moving from peer-keyed provider tokens to opaque handles requires issuance, rotation, revocation, environment binding, multi-device separation, stale-entry cleanup, and compatibility with existing authenticated registration.

### 8.7 Group-mute policy continuity

Rich-payload and future generic-inbox clients must consult the same installation-local group policy during migration. The rollout must not sync mute to sibling devices, widen it to direct/global/timed scope, lose app-icon badge recalculation, resurrect a retired group card, or couple mute to read state. The unused standalone `group_muted:<groupId>` Keychain sentinel needs one explicit disposition: remove/migrate it, or assign and test a single consumer without creating a second mute owner.

### 8.8 PRD rollout gap

PRD v1.2 does not yet define a feature flag, capability negotiation, mixed-version behavior, canary population, success/error thresholds, kill switch, rollback, or legacy cleanup point. These are required planning inputs before the provider contract changes.

### 8.9 Direct-inbox overflow contradicts ACK-or-expiry custody

Both current relay backends evict the oldest unacknowledged direct-inbox row at capacity and still report `stored`. Plan 342's sender may therefore retire exact text custody after the relay has discarded a different older event. Plan 343 intentionally preserves that installed-client behavior as a compatibility sentinel instead of expanding a bounded reaction slice into a relay migration. A later GAP-N01 dependency-wave plan must introduce non-destructive capacity semantics and machine-checkable mixed-version activation before any full PRD custody or release claim.

## 9. Recommended future work-package boundaries

This is dependency guidance for later planning, not an authorized implementation sequence.

| Boundary | PRD controls primarily addressed | Exit condition before dependent work |
|---|---|---|
| WP-00: Product and PRD closure | OQ-01 through OQ-05; PRD cross-reference repair | OQ-01 silent visual cue and OQ-02 activation cleanup approved; OQ-03 predicate chosen; OQ-04 installation-local/no-cross-device-clearing and OQ-05 indefinite installation-local group-only mute adopted; iOS mute caveat disposition and broken references recorded. |
| WP-01: Authenticated event and durable custody contract | A-01 through A-04, A-17, A-18, A-24, A-26 | Preserve Plan 342's implemented fresh-text slice, execute/review Plan 343's bounded reaction slice, then close media/edit/delete/group/device-fanout and non-destructive relay-capacity work so every notification-worthy event has one authenticated identity/hash and per-device inbox custody independent of fast path. |
| WP-02: Opaque wake gateway and privacy boundary | A-05 through A-08, A-12, A-16, A-19; AC-11 | Fixed provider shapes, opaque/encrypted token lookup, migration strategy, and captured-request privacy tests. |
| WP-03: Shared lifecycle, ledger, decision, and outcome state machine | A-13, A-15, A-21 through A-29 | One logical ledger/snapshot/outcome contract with atomic transitions and final effect gate. |
| WP-04: iOS generic wake and inbox enrichment | A-09 through A-11, A-14, A-15, A-20 | NSE fetches inbox without Flutter, retains generic fallback, and uses shared state. Touched iOS code compiles and focused Swift/native tests pass; required iPhone scenarios are registered for WP-07/GAP-N12 and are not a WP-04 exit gate. |
| WP-05: Android generic wake and native/background continuation | A-12 through A-15, A-20, A-27, A-28 | FCM service/WorkManager reconcile inbox, use shared state, render MessagingStyle, and prove muted ordinary/reaction events do not post or alert while unread persists on available Android targets. |
| WP-06: Generic reaction presentation, read, cleanup, mute, and multi-device independence | A-17, A-18, A-28 through A-30 | After WP-01 owns reaction sender custody, remove specialized rich reaction push/presentation paths so all event kinds use the same generic pipeline; approved local read/mute behavior passes deterministic and Android delayed-wake/order tests; mute preserves delivery/unread, retires the current card, and respects applicable badge policy; sibling independence passes its preservation sentinel. Apple-owned presentation cases remain registered for WP-07/GAP-N12. |
| WP-07: Mixed-version rollout and consolidated iOS/release closure | A-20, A-30; AC-01 through AC-12 | Begins after GAP-N01 through GAP-N11 are code-complete and their focused host/native, Android, and wave-level `host-all` gates pass. Runs one bounded availability-based iOS closure phase, fixes and reruns affected failures, then records compatibility rollout, kill switch, telemetry, release-eligible platform proof, and final release closure. |

Important dependency rules for later planning:

- Do not implement native styles before local private resolution and stable ledger ownership are defined.
- Do not remove rich push fields before compatible inbox-fetch clients and mixed-version behavior exist.
- Do not implement `wake_not_required` before the completed local outcome state machine is durable and crash-safe.
- Do not make delayed-wake/read assertions until OQ-02/OQ-03 are decided and the OQ-04 device-local answer is accepted into the PRD.
- Do not generalize group mute into direct/global mute without a separate product decision.

### 9.1 Adopted test sequencing: Android-first, consolidated iOS closure

Later implementation plans should use this default order:

1. **Implementation phase — GAP-N01 through GAP-N11.** Run focused Go/Dart/SQL/native tests, exact preservation sentinels, affected curated gates, and continuous Android device proof. Use the available physical Android plus emulator for non-iOS two-peer flows. An individual gap does not require an iPhone, iOS UI campaign, or expansion of the physical-iPhone harness as an exit gate.
2. **iOS compile/unit safety during implementation.** Any touched Runner, NSE, App Group, Keychain, or UserNotifications code must compile and pass its focused Swift/native tests before that gap's implementation gate is green. This catches contract and concurrency regressions early without starting the device campaign. It is not a waiver to leave iOS code unbuildable until the end.
3. **Consolidated iOS closure — GAP-N12/WP-07 only.** After GAP-N01 through GAP-N11 are code-complete and their deterministic/native/Android gates are green, resolve the live device matrix and run only the necessary targeted simulator checks plus one bounded physical-iPhone campaign. That campaign owns real APNs-to-NSE behavior, hard Apple lifecycle states, main-app/NSE ledger ownership, communication presentation, device-log privacy, exact delivered-card/badge cleanup, and blank/passive muted-item proof.
4. **Failure loop and final closure.** An iOS failure is a product/test failure, not a reason to broaden the harness by default. Make the smallest production or test correction, rerun the affected focused gates and the bounded iOS scenario, then run final closure. GAP-N12 remains open until this evidence exists or a target is explicitly `N/A (target unavailable by project policy)`.

For this sequencing, “all gaps implemented” means the target production changes for GAP-N01 through GAP-N11 are code-complete and their non-iOS gates are green. GAP-N12 is the proof-closure gap and therefore intentionally remains open while the consolidated iOS phase runs.

This order deliberately defers iOS device integration risk; it does not remove the PRD's iOS obligations. GAP-N01, GAP-N02, GAP-N03, and GAP-N05 normally need no device-specific per-gap gate; GAP-N08 is Android-specific. GAP-N04, GAP-N06, GAP-N07, GAP-N09, GAP-N10, and GAP-N11 may be marked **implementation-complete, iOS evidence-deferred**, but they are not accepted or PRD-compliant until their registered Apple-owned assertions pass in the consolidated GAP-N12 phase.

The existing physical provider adapter should remain a bounded fixture rather than becoming a general framework: it is explicitly a one-payload lifecycle and is coupled to the current rich-payload contract. Reuse its signing, APNs submission, device selection, cleanup, and evidence-receipt pieces only after the target fixed-wake/inbox contract is stable. Prefer one pinned disposable iPhone and one build/install for the final campaign; do not create a multi-iPhone or state-by-modality matrix when host/native tests already prove the permutations. Automate public, observable seams. For actual sound/haptic or OS UI absence that cannot be measured without private APIs or new hardware instrumentation, require a bounded, provenance-recorded real-device observation and decide its release eligibility explicitly instead of silently creating an open-ended harness project.

## 10. Acceptance-evidence index for future plans

Every implementation plan should select the smallest relevant subset during development and preserve registration for the later wave/final closure. The execution point below is normative planning guidance: Android evidence is collected continuously, while iOS device evidence is consolidated after the implementation gaps are complete.

| Evidence family | Minimum proof boundary | Default execution point |
|---|---|---|
| Payload privacy and fixed shape | Go/provider serialization tests plus captured APNs/FCM requests for every event kind and fallback. | Implementation phase; no phone is required to prove provider-bound bytes. |
| Event identity/idempotency | Exact event/hash assertions across direct, pubsub, inbox, push wake, replay, and ledger. | Implementation phase in host/native tests, with Android path confirmation where needed. |
| Visible-thread isolation | Same chat, chat B, and non-chat screen for implemented text, media, reaction, direct, and group paths. First-class mention is `N/A` unless separately approved and introduced. | Deterministic and Android proof during implementation; minimum Apple presentation parity in consolidated iOS closure. |
| Lifecycle transition | Deliver immediately before/after resign-active, onPause, inactive, and background. | Deterministic barriers and Android during implementation; Apple lifecycle states in consolidated iOS closure. |
| Final effect gate | Deterministic barriers for open-during-build, background-during-build, read/delete-during-build. | Implementation phase in host/native tests and Android; only the irreducible UserNotifications/NSE seam waits for iOS closure. |
| ACK/outcome separation | Delivery ACK without outcome; completed local outcome; timeout/crash before outcome. | Implementation phase in host/integration tests and Android; no routine iPhone gate. |
| Shared-ledger concurrency | Main app versus NSE/FCM service/WorkManager/reconciler on the same event and generation. | Host/native and Android races during implementation; one main-app/NSE realization in consolidated iOS closure. |
| Read/dismiss/cancel | Dismissal, exact-conversation activation, the approved local read predicate, exact generation cancellation, delayed wake after local read/delete, and a sibling-device independence preservation sentinel. Cross-device clearing is tested only under a separately approved future protocol. | Host/native and Android during implementation; actual Apple delivered-request cleanup in consolidated iOS closure. |
| Group mute preservation | UI to SQL to shared/native policy; ordinary text/media/announcement and eligible reactions; no local card/sound/vibration; existing-card retirement; app-icon badge versus in-app unread distinction; sibling locality; Android channel observation; and iOS blank/passive-item proof. Mention-like text follows the ordinary group policy because no first-class mention lane exists. | Host/native and Android during implementation; blank/passive item, actual sound/haptic, and Apple badge behavior in consolidated iOS closure. |
| iOS device matrix | Available iPhone/simulator targets for foreground, inactive, background, suspended/terminated, locked, first-unlock, force-quit as technically applicable. | Consolidated GAP-N12/WP-07 closure only, after GAP-N01 through GAP-N11 non-iOS gates pass. |
| Android device matrix | Available physical Android plus emulator for Doze, continuation, permission/channel states, token refresh, and available OEM behavior. | Continuous implementation and dependency-wave evidence; do not wait until final closure. |

Per repository policy, unavailable OS/hardware versions are `N/A (target unavailable by project policy)`, not blockers. Individual plans should run focused causal tests, preservation sentinels, the affected curated lane, and only justified family sweeps. Physical-iPhone or iOS UI acceptance is not a per-gap gate, but touched iOS code still has compile and focused native-test gates. Full `host-all` belongs after the implementation dependency wave and again at final rollout/release closure.

## 11. PRD defects to repair before deriving stories

The OQ table in PRD v1.2 references identifiers and sections that do not exist in the actual 470-line document:

- `FR-*` identifiers;
- `D-*` identifiers;
- “Matrix A”;
- sections such as 7.4, 9.7, 11.4, 12.1 through 12.3, and 15.2 through 15.3;
- acceptance criteria such as AC-16, AC-18, and AC-19.

OQ-01 also points to AC-11 even though the actual AC-11 is payload privacy, not same-chat cue behavior.

Until those references are repaired, later plans should use the valid anchors in this document:

- PRD goals G-01 through G-07;
- actual sections 4 through 9;
- A-01 through A-30;
- AC-01 through AC-12;
- OQ-01 through OQ-05;
- the ten required test families in PRD section 13.

Do not invent the missing FR/D/AC definitions while planning.

## 12. Definition of PRD-aligned closure

The notification initiative should not be described as PRD v1.2 compliant until all of the following are true:

1. The codebase answers are converted into approved PRD decisions: OQ-01 cue and OQ-02 cleanup are selected, OQ-03 is unified or deliberately split, OQ-04 explicitly remains installation-local, OQ-05 remains indefinite installation-local group-only mute with its platform caveat resolved, and broken references are corrected.
2. Every notification-worthy event has per-device durable inbox custody before wake generation.
3. Direct/pubsub delivery acknowledgement cannot independently remove custody or wake ownership.
4. APNs/FCM receives one fixed generic shape with no forbidden metadata for all event kinds.
5. Native processing fetches/reconciles the inbox and does not rely on provider-carried event routing/content.
6. Main app, iOS NSE, Android receiver/WorkManager, and reconciler share one logical atomic notification ledger and fresh visibility contract.
7. Lifecycle/read/policy state is checked immediately before every post, suppress, update, or cancel effect.
8. Read, dismiss, exact-conversation activation cleanup, group mute, and installation-local sibling independence match those approved decisions.
9. Native conversation presentation is implemented without weakening provider privacy.
10. Logs and analytics contain no tokens, plaintext, stable social-graph IDs, or deterministic ID prefixes.
11. All A-01 through A-30 controls are compliant or have an explicitly approved PRD exception.
12. After GAP-N01 through GAP-N11 pass their deterministic/native and Android gates, the consolidated GAP-N12 iOS phase completes; AC-01 through AC-12 and the required availability-bounded device/race matrix then have current, persisted, provenance-bound evidence.

## 13. Assessment limitations

- This refresh is source-, plan-, and repository-evidence-based; it did not execute a new full device campaign.
- The repository baseline was clean at committed HEAD `007c1e2d577c226aee2a94e2050f3a19e4812775` immediately before Plan 343 planning. The only current workspace changes in scope are the Plan 343 artifact, its index row, and this report refresh.
- Plan 342's recorded host/relay/discovery and Pixel 6 SQLCipher receipts support only its bounded fresh-direct-text storage claim. They do not close universal GAP-N01, recipient outcome, presentation, or release eligibility.
- Plan 343 is reviewed planning evidence only. None of its proposed DB v109, reaction custody, UI-generation, relay-namespace, account-transfer, or Android proof work contributes to the current score until implemented and verified.
- Absence of a persisted iOS/device artifact is reported as evidence debt, not proof that a behavior fails at runtime.
- Composite A-controls receive full credit only when their defining target condition and required paths are covered. Strong supporting primitives remain documented even when the strict status is Missing.
