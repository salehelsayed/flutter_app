# NSE/App-Group Push Spool Persistence - Analysis and Design

Date: 2026-06-23

Status: Analysis/design only. Do not implement this as a one-off patch.

Related work:

- `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md`
- `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`
- `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`
- `Test-Flight-Improv/142-relay-media-push-payload-too-large-tdd-plan.md`

## Executive Verdict

NSE/app-group push spool persistence is meaningful, but it is not the next lowest-risk fix.

The first three lower-risk items should land first:

1. Stop blocking notification route handling on pre-push `drainOfflineInbox()`.
2. Render a visible "catching up" state while the conversation drain is in flight.
3. Add telemetry from notification tap to stale render, drain, and live render.

If telemetry still shows a real user-visible delay after those changes, push spool persistence is a reasonable next project. It should be treated as a staged receive accelerator, not as a replacement for relay inbox drain.

The safe version is narrow:

- Store only the encrypted push envelope and routing metadata.
- Never store decrypted plaintext, preview body, usernames, group names, or media bytes in the app group.
- Replay the stored envelope through the existing message ingestion pipeline.
- Keep relay drain as the source of truth for server custody and ACK.
- Scope v1 to compact 1:1 encrypted text pushes.

Android is not currently at parity with iOS. Android has a privacy-safe fallback path and a tested decrypt-preview helper, but production background handling does not wire decrypt callbacks or a native spool. If this becomes a product plan, Android needs an explicit design instead of being assumed covered.

## What This Means In Plain English

"Push spool persistence" means:

1. A push arrives while the app is closed or backgrounded.
2. The push already contains encrypted message data for small messages.
3. Before the user opens the app, the notification extension/background handler saves a small encrypted copy into local device storage.
4. When the user taps the notification, the main app reads that local encrypted copy and processes it immediately.
5. The normal relay inbox drain still runs afterward to verify, catch up, and ACK the server copy.

It does not mean:

- Store message plaintext on disk.
- Store the notification preview text on disk.
- Store images, videos, or voice files in the push.
- Skip relay inbox drain.
- ACK relay messages from push data alone.

## Method

This review used graphify first, then source inspection, plus three delegated agent slices:

- iOS NSE/app-group feasibility.
- Android background push/decrypt/spool parity.
- Shared Dart ingestion, dedupe, replay, and ACK semantics.

The graphify queries focused on notification service extension decrypt, Android background push handling, encrypted push payload fields, relay payload size behavior, local dedupe, and inbox staging.

## Source Evidence Map

Key source anchors:

- iOS app group/keychain entitlements: `ios/Runner/Runner.entitlements:9`, `ios/NotificationService/NotificationService.entitlements:9`, `ios/NotificationService/NotificationService.entitlements:13`.
- iOS app-group path bridge: `ios/Runner/AppDelegate.swift:304`, `ios/Runner/AppDelegate.swift:311`.
- iOS shared key names: `ios/NotificationService/NotificationPreviewResolver.swift:14`, `ios/NotificationService/NotificationPreviewResolver.swift:17`, `ios/NotificationService/NotificationPreviewResolver.swift:23`.
- iOS 1:1 and group decrypt: `ios/NotificationService/NotificationPreviewResolver.swift:197`, `ios/NotificationService/NotificationPreviewResolver.swift:294`.
- iOS muted group short-circuit: `ios/NotificationService/NotificationPreviewResolver.swift:263`.
- iOS dedupe and recent remote sidecars: `ios/NotificationService/NotificationPreviewResolver.swift:430`, `ios/NotificationService/NotificationPreviewResolver.swift:475`, `ios/NotificationService/NotificationPreviewResolver.swift:485`.
- iOS bridge decrypt calls: `ios/NotificationService/NotificationPreviewResolver.swift:566`, `ios/NotificationService/NotificationPreviewResolver.swift:579`, `ios/NotificationService/NotificationPreviewResolver.swift:585`, `ios/NotificationService/NotificationPreviewResolver.swift:596`.
- Android background handler registration: `lib/main.dart:362`.
- iOS-only shared push key store construction: `lib/main.dart:422`.
- Android resolver injection point and default resolver: `lib/features/push/application/background_message_handler.dart:35`, `lib/features/push/application/background_message_handler.dart:52`, `lib/features/push/application/background_message_handler.dart:165`.
- Android local fallback notification show: `lib/features/push/application/background_message_handler.dart:183`.
- Android SQLCipher eligibility read: `lib/features/push/application/background_message_handler.dart:26`, `lib/features/push/application/background_message_handler.dart:298`.
- Android decrypt-preview helper optional callbacks: `lib/features/push/application/push_decrypt_preview.dart:23`, `lib/features/push/application/push_decrypt_preview.dart:54`, `lib/features/push/application/push_decrypt_preview.dart:111`.
- Relay push size cap and fallback: `go-relay-server/inbox.go:53`, `go-relay-server/inbox.go:284`, `go-relay-server/inbox.go:294`, `go-relay-server/inbox.go:407`, `go-relay-server/inbox.go:468`, `go-relay-server/inbox.go:536`.
- Shared identity/group key mirroring: `lib/features/identity/domain/repositories/identity_repository_impl.dart:177`, `lib/features/groups/domain/repositories/group_repository_impl.dart:13`, `lib/features/groups/domain/repositories/group_repository_impl.dart:537`, `lib/features/groups/domain/repositories/group_repository_impl.dart:562`.
- Canonical 1:1 receive/dedupe/persist path: `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:59`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:301`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:507`.
- Delivery receipt staging decision: `lib/features/conversation/application/send_delivery_receipt_use_case.dart:43`, `lib/features/conversation/application/send_delivery_receipt_use_case.dart:64`, `lib/features/conversation/application/send_delivery_receipt_use_case.dart:74`.
- Relay inbox replay and ACK boundary: `lib/core/services/p2p_service_impl.dart:960`, `lib/core/services/p2p_service_impl.dart:1024`, `lib/core/services/p2p_service_impl.dart:1493`.

## Current Code Reality

### iOS Is Close To Having The Right Primitives

iOS already has the strongest foundation:

- Runner and NotificationService share the same app group and keychain access group in `ios/Runner/Runner.entitlements` and `ios/NotificationService/NotificationService.entitlements`.
- `ios/NotificationService/NotificationService.swift` calls the preview resolver and rewrites notification title/body inside the app's notification service extension.
- `ios/NotificationService/NotificationPreviewResolver.swift` decrypts 1:1 pushes from `kem`, `ciphertext`, and `nonce` using the shared `identity_ml_kem_secret_key`.
- The same resolver decrypts group pushes using `group_key:<groupId>:<keyEpoch>`.
- Muted groups short-circuit before decrypting and keep generic fallback behavior.
- The NSE already writes app-group sidecar files for dedupe:
  - `NotificationServiceDedupe` for first-wins push dedupe.
  - `RecentRemoteShown` for Dart-side duplicate banner suppression.
- Dart already consumes app-group sidecars through `lib/core/notifications/recent_remote_notification_gate.dart`.
- `lib/core/notifications/recent_remote_gate_ios_wiring.dart` persists the app-group path because background isolates may not be able to call the platform channel.

What is missing:

- No `PushSpool/` directory exists today.
- No NSE code persists the encrypted push envelope for later main-app ingestion.
- No shared Dart spool reader/replayer exists.

Critical privacy point: the NSE currently decrypts only to render the notification preview. That plaintext is ephemeral process memory. Adding a spool would increase the privacy surface only if we save more data. The proposed safe design saves the encrypted envelope, not the decrypted preview.

### Android Is Safe But Not At iOS Parity

Android currently handles generic fallback notifications reasonably, but it is not equivalent to the iOS NSE path.

Evidence:

- `lib/main.dart` registers `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`.
- `lib/features/push/application/background_message_handler.dart` initializes the background handler, resolves the route, checks display eligibility, and shows a local notification.
- The background handler explicitly says inbox drain happens on resume, not inside the background isolate.
- `lib/features/push/application/background_push_notification_fallback.dart` suppresses local fallback when FCM already delivered a visible notification.
- For protected message pushes, fallback copy is generic unless decrypt succeeds.
- `lib/features/push/application/push_decrypt_preview.dart` has tested support for decrypting 1:1 and group previews, but decrypt callbacks are optional.
- Production background handling calls the default resolver without wiring `decryptOneToOne` or `decryptGroup`.
- Android reads SQLCipher state for group eligibility/mute decisions, but that is display eligibility, not preview decrypt or spool ingestion.
- The shared push key store is constructed only on iOS in `lib/main.dart`.

So Android today should be described as:

- Privacy-safe generic fallback: yes.
- Data-only route notification support: yes.
- Production decrypt-preview parity with iOS: no.
- Durable push spool parity: no.

This matters because an iOS-only spool would create platform behavior skew: iOS notification taps could render the pushed message before relay drain, while Android would still wait for relay resume/drain.

### Push Payload Reality

The push does not carry raw media bytes.

Relay push construction in `go-relay-server/inbox.go` builds encrypted push data for small payloads:

- 1:1 push data can include `kem`, `ciphertext`, and `nonce`.
- Group push data can include `keyEpoch`, `ciphertext`, and `nonce`.
- Routing fields such as type, sender/group id, and message id are included.
- There is a push data size cap around FCM/APNs limits.
- Oversized payloads fall back to a generic notification with no encrypted message fields.

For small text messages, the encrypted `ciphertext` can contain the message payload needed to render the preview after local decrypt.

For media messages:

- The push should not contain the image, video, file, or voice bytes.
- It may contain encrypted metadata if the payload is small enough.
- If the encrypted payload is too large, relay sends generic fallback and the app must fetch/drain normally.

Therefore spool v1 should not promise instant media availability. At most it can accelerate text and small metadata-only previews.

### Shared Ingestion Reality

The repo already has a canonical receive pipeline. Push spool should reuse it.

Important existing behavior:

- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` owns decrypt, sender validation, duplicate checks, contact/message persistence, media metadata handling, and delivery receipts.
- `lib/core/inbox/inbox_staging_repository_impl.dart` stages relay inbox entries before replay.
- `lib/core/services/p2p_service_impl.dart` ACKs relay entries only after relay `retrieve_pending` returns an entry id and local staging succeeds.
- Push payloads have a message id, but they do not have the relay inbox entry id.

That means push spool must not call relay ACK. The relay drain still has to run.

Push spool should behave like a local staged receive source:

1. Read encrypted push spool entry.
2. Convert it to a `ChatMessage` with content equal to the encrypted envelope.
3. Replay through existing incoming-message handling.
4. Delete the spool entry only after committed/duplicate/rejected terminal outcomes.
5. Keep or quarantine retryable failures.

## What "Encrypted Envelope" Means Here

The "encrypted envelope" is the encrypted push payload fields that already arrive on the device, before local decrypt.

For a 1:1 push, that means fields like:

- `type = new_message`
- `sender_id`
- `message_id`
- `kem`
- `ciphertext`
- `nonce`

For a group push, that means fields like:

- `type = group_message`
- `groupId`
- `message_id`
- `keyEpoch`
- `ciphertext`
- `nonce`

The envelope is not the plaintext message text. It is the sealed data needed by the local device to decrypt later using local keys.

Safe spool persistence saves that sealed data. It does not save the decrypted result.

## Design Goals

- Reduce notification tap to visible-message delay when the push already carried a compact encrypted message.
- Preserve notification previews.
- Preserve end-to-end privacy properties: relay/APNs/FCM do not learn plaintext.
- Avoid writing plaintext to app-group storage.
- Avoid bypassing existing sender validation, dedupe, message persistence, and receipt logic.
- Keep relay inbox drain and ACK as authoritative server-custody behavior.
- Make iOS and Android behavior explicit rather than accidentally divergent.

## Non-Goals

- No direct writes from NSE/background handler into the `messages` table.
- No plaintext spool.
- No media-byte spool.
- No relay ACK from push-only data.
- No group spool in v1 unless a separate group-specific design is accepted.
- No attempt to make all notification taps instant under all conditions.

## Proposed Architecture

### 1. Versioned Spool Entry

Define a small versioned JSON entry.

Suggested fields:

```json
{
  "schemaVersion": 1,
  "platform": "ios",
  "type": "new_message",
  "messageId": "...",
  "senderId": "...",
  "receivedAtMs": 1782200000000,
  "expiresAtMs": 1782200600000,
  "providerMessageId": "...",
  "kem": "...",
  "ciphertext": "...",
  "nonce": "...",
  "routePayload": {
    "type": "new_message",
    "sender_id": "...",
    "message_id": "..."
  }
}
```

Rules:

- Do not include plaintext `text`.
- Do not include notification `title` or `body`.
- Do not include `senderUsername`, `groupName`, or preview strings.
- Do not include media bytes.
- Consider excluding media metadata from v1 to reduce privacy and compatibility risk.
- File name should be deterministic but non-revealing, for example SHA-256 of owner/sender/message id.

### 2. iOS NSE Writer

Add a native `PushSpoolStore` under `ios/NotificationService/`.

Behavior:

- Use the existing app group container.
- Write under `PushSpool/v1/`.
- Accept only valid compact encrypted entries.
- Use atomic temp-file plus rename.
- Use first-wins semantics for duplicate message ids.
- Mark files as excluded from backup.
- Use an aggressive TTL, for example 10 minutes for normal consumption and hard prune around 12 hours.
- Prune stale files opportunistically on write.
- Do not spool if the push is oversized fallback and lacks encrypted fields.
- Do not spool muted/suppressed groups.
- For v1, spool only 1:1 `new_message` entries.

Where to write:

- After the NSE has enough data to know the push is valid and decryptable.
- Store the original encrypted fields, not the decrypted preview.

Why after validation:

- It avoids creating garbage spool entries for malformed pushes.
- It keeps spoofed or incomplete data out of the main-app replay path.
- It does not require saving plaintext.

### 3. Android Writer

Android needs an explicit decision.

Minimum parity option:

- In `firebaseMessagingBackgroundHandler`, when a data-only encrypted `new_message` arrives, write the encrypted envelope into app-private spool storage.
- Do not require background decrypt just to spool.
- Foreground/main app later reads and replays the encrypted envelope.
- Notification preview may remain generic until Android decrypt-preview wiring is implemented.

Full parity option:

- Add an Android-native `FirebaseMessagingService` or WorkManager-backed receiver.
- Wire native access to Android Keystore/EncryptedSharedPreferences and the Go decrypt bridge.
- Decrypt preview in the background handler equivalent to iOS NSE.
- Write encrypted spool entries with native durable dedupe.
- Test behavior when the Flutter background isolate is not scheduled.

Recommendation:

- Start with the minimum parity option only if telemetry proves message-load delay still matters after the first three fixes.
- Do not claim Android preview parity until production decrypt callbacks or native decrypt are wired.
- Keep Android generic fallback as acceptable privacy-safe behavior until that work is scheduled.

### 4. Shared Dart Reader And Replayer

Add shared Dart code to read and replay spool entries.

Suggested components:

- `PushSpoolEntry`
- `PushSpoolRepository`
- `DrainPushSpoolUseCase`
- `ReplayPushSpoolEntryUseCase`

Responsibilities:

- Read platform spool directory.
- Validate schema version and required fields.
- Enforce TTL.
- Claim entries to avoid parallel replay.
- Convert entries to `ChatMessage`.
- Replay through the existing incoming-message pipeline.
- Delete entries on committed, duplicate, or rejected terminal outcomes.
- Keep retryable entries for a short time.
- Quarantine invalid entries without logging sensitive data.

The replayed `ChatMessage` should preserve the encrypted envelope as `content`.

Suggested transport/origin:

- `transport = push_spool`
- staged id like `push:<stable-id>`

Receipt behavior needs to be pinned in tests. The current delivery receipt logic can mint receipts for staged entries. That may be acceptable after successful local commit, but it must be intentional and documented.

### 5. Route Integration

Spool drain should be fast and local.

For notification tap:

1. Parse route target.
2. Start route handling immediately.
3. Run targeted spool replay for the sender/thread if available.
4. Render conversation with catching-up state if relay drain is still running.
5. Run normal relay `drainOfflineInbox()`.
6. Let relay replay dedupe against any message already committed from push spool.

Do not block route handling on a full spool sweep.

### 6. Dedupe And Ordering

Dedupe layers:

- Native first-wins file creation by stable id.
- Dart claim marker or atomic move to an in-flight state.
- Existing message id, dedup key, and content duplicate handling in `handleIncomingChatMessage`.
- Relay drain replay later should be duplicate-safe.

Ordering:

- Use spool receipt time only for processing order.
- Preserve payload timestamp for message display order.
- Do not make push receipt time override sender payload time.

### 7. Privacy And Security Contract

Hard requirements:

- No plaintext body in spool.
- No preview title/body in spool.
- No usernames/group names in spool.
- No media bytes in spool.
- Exclude spool files from backup.
- Short TTL.
- Sanitized logs and telemetry.
- Size caps.
- Schema versioning.
- Per-entry validation before replay.
- Do not use spool to bypass mute/suppress rules.

This does not make the existing notification preview less useful. The NSE/background handler can still decrypt in memory to show the preview. The spool only changes what is saved for later.

Important distinction:

- Preview: decrypted locally and shown by OS notification UI according to device notification settings.
- Spool: encrypted local copy saved briefly so the app can process faster after tap.

## Android Parity Decision

Android is the main product decision.

If we implement only iOS app-group spool:

- iOS gets faster notification-open message visibility.
- Android remains generic-preview/fallback and relay-drain dependent.
- Metrics and user experience become platform-skewed.
- Support/debugging gets harder.

If we implement shared spool with Android minimum parity:

- Both platforms can accelerate main-app render from encrypted push data.
- Android preview may still be generic until decrypt-preview wiring is complete.
- We avoid blocking the whole feature on Android native decrypt complexity.

If we implement full Android parity:

- Best user experience.
- Highest complexity.
- Requires native/background reliability testing beyond the current Flutter isolate path.

Recommendation:

1. Do not implement iOS-only spool as the default.
2. If moving forward, build shared Dart replay first.
3. Add iOS NSE writer.
4. Add Android encrypted-envelope writer at minimum.
5. Treat Android decrypt-preview parity as a separate follow-up unless product requires preview parity immediately.

## Rollout Plan

### Phase 0 - Evidence Gate

Ship the first three lower-risk notification-open fixes and collect telemetry.

Proceed only if telemetry shows real residual delay where:

- Push arrived with compact encrypted data.
- User tapped notification.
- Route rendered stale or empty conversation.
- Relay drain delay caused visible message-load lag.

Stop if the first three fixes make the issue acceptable.

### Phase 1 - Shared Spool Contract

Add schema, repository, TTL, privacy canary tests, and replay mapping.

No native writers yet.

Acceptance:

- Encrypted entry can be read and replayed.
- Plaintext fields are rejected or absent.
- Duplicate spool entries do not duplicate messages.
- Expired entries are pruned.
- Invalid entries are quarantined or deleted safely.

### Phase 2 - iOS NSE Writer

Add app-group `PushSpool/v1` writer in the NSE.

Acceptance:

- Valid 1:1 encrypted push writes one spool entry.
- Oversized fallback writes nothing.
- Malformed push writes nothing.
- No plaintext appears in the spool file.
- Duplicate push creates one entry.
- Main app drains and deletes terminal entries.

### Phase 3 - Android Minimum Writer

Add encrypted-envelope spool writing from Android background push handling.

Acceptance:

- Data-only encrypted 1:1 push writes one spool entry.
- Visible FCM notification fallback does not create unsafe duplicate behavior.
- Oversized fallback writes nothing.
- Foreground replay path is shared with iOS.
- Android remains privacy-safe even without background decrypt callbacks.

### Phase 4 - Notification Tap Integration

Wire targeted spool replay into notification-open routing.

Acceptance:

- Route is not blocked by full relay drain.
- Conversation shows pushed message from spool when available.
- Catching-up state remains visible while relay drain runs.
- Relay drain later does not duplicate the message.
- Delivery receipt behavior is pinned by tests.

### Phase 5 - Android Preview Parity Decision

Only if required:

- Wire production Android decrypt callbacks, or
- Move to a native `FirebaseMessagingService`/WorkManager design with Go bridge access.

This should be planned as a separate Android background reliability project.

## Test Contract

High-value tests before implementation is accepted:

- Swift NSE tests:
  - valid 1:1 encrypted push writes encrypted spool.
  - no plaintext fields in file.
  - duplicate push is first-wins.
  - malformed/oversized push does not spool.
  - stale files prune.

- Dart repository tests:
  - read/write/claim/delete lifecycle.
  - TTL expiry.
  - schema rejection.
  - no plaintext canary.

- Dart replay tests:
  - spool entry commits through `handleIncomingChatMessage`.
  - duplicate relay drain does not duplicate UI.
  - invalid sender/contact behavior is unchanged.
  - transient decrypt failure remains retryable.
  - terminal duplicate/invalid outcomes delete or quarantine correctly.
  - delivery receipt behavior is explicit.

- Android tests:
  - background encrypted data push writes spool entry.
  - generic visible fallback does not write unsafe spool.
  - missing encrypted fields do not spool.
  - no plaintext route fields leak into spool.

- Integration tests:
  - notification tap opens conversation immediately.
  - spool-replayed message appears before slow relay drain completes.
  - catching-up state remains until relay drain finishes.
  - relay replay dedupes.

## Risks

- Platform skew if iOS ships without Android parity.
- More local persistence of sensitive encrypted material.
- Duplicate delivery receipts if push replay and relay replay both mint.
- Race between targeted spool replay and relay drain.
- Background isolate reliability on Android.
- Keychain/access-group behavior must be verified on real TestFlight devices.
- Media expectations may be misunderstood if product expects images/videos to appear from push alone.

## Final Recommendation

Turn this into an implementation plan only after the first three lower-risk notification-open changes are measured.

If the delay remains meaningful, implement a narrow v1:

- 1:1 only.
- Compact encrypted push envelope only.
- Shared Dart replay through the existing receive pipeline.
- iOS NSE app-group writer.
- Android encrypted-envelope writer or an explicit product decision that Android remains generic fallback.
- No plaintext spool.
- No direct DB message writes.
- No relay ACK from push data.

Do not implement group spool, media spool, or full Android native decrypt parity in the first version. Those are separate projects with different privacy and lifecycle risks.
