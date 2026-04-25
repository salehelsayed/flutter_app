# 73 - On-Device Push Decrypt (NSE + FCM Data) — Privacy-Preserving Preview Plan

## 1. Title and Type

- Title: On-device push decrypt so notification previews render content without the relay ever seeing plaintext
- Issue type: `feature` (privacy hardening + UX parity)
- Output doc path: `Test-Flight-Improv/73-on-device-push-decrypt-plan.md`
- Session classification: `multi-session, cross-platform`

## 2. Final Verdict

`implementation-ready, multi-phase`

Today the group send path ships a client-built plaintext preview alongside the
encrypted envelope (`send_group_message_use_case.dart:34-57` + `:384-390`), and
the relay forwards that preview verbatim into APNs/FCM alert fields
(`go-relay-server/inbox.go:359-414`). The 1:1 send path never sends a preview,
and the relay cannot decrypt v2 envelopes, so 1:1 falls back to the hardcoded
`"You have a new message"` (`go-relay-server/inbox.go:33`, `:303`). Closing the
1:1 gap by mirroring the group approach would buy UX parity but widen the
privacy leak — the relay would see every 1:1 preview in the clear.

The goal of this plan is the Signal/WhatsApp/iMessage posture: the relay
forwards only ciphertext and routing metadata, the device decrypts the payload
in a notification-time handler (iOS Notification Service Extension, Android
FCM data-only background isolate), rewrites the notification body with the
decrypted content, and the OS renders the full preview. On failure (missing
key, timeout, extension crash) the user sees `"New message"` — graceful
degrade, not a leak.

Feasibility is high because the needed primitives already exist in this repo:

- `GoMknoon.xcframework` builds already (`go-mknoon/` + `gomobile bind`)
- `message.decrypt` / `group.decrypt` bridge commands exist
  (`bridge.dart:566-583`, `bridge_group_helpers.dart:949-963`)
- A second iOS target already lives in the Xcode project (`Share Extension`)
  with its own `.entitlements` and App Group membership — proof the plumbing
  works in this project
- FCM background handler is already wired (`background_message_handler.dart`)
  and the `@pragma('vm:entry-point')` contract is in place

The hard parts are the new ones:

- sharing key material across the main app and the iOS NSE (App Group +
  Keychain access group + `flutter_secure_storage` accessGroup param)
- embedding a decrypt-capable binary in the NSE without exceeding its ~24 MB /
  30 s budget
- making Android data-only FCM deliverable on OEMs that throttle background
  work (Xiaomi/Huawei/Oppo/Samsung)
- rewriting the relay push contract symmetrically for 1:1 and group so both
  paths are ciphertext-only

**Product decision (2026-04-24):** old builds in the field will degrade to
the static `"New message"` placeholder for group pushes the moment the
relay flips, until their users update. Privacy over transitional UX. This
decision removes the need to wait for client adoption before shipping
the relay change — Phase 1 can ship independently and immediately. See
Section 9.8 for details.

## 3. Real Scope

This plan changes:

- **relay push payload shape**: strip `pushBody` / `pushTitle` for message
  pushes, send `mutable-content: 1` (iOS) + data-only FCM (Android), include
  ciphertext + `keyEpoch` + `messageId` + minimal routing metadata in the
  `data` block
- **send-path envelope**: 1:1 and group senders stop computing
  `pushBody` / `pushTitle`; on 1:1, **the outer envelope drops its
  plaintext `senderUsername` field — the username moves inside the
  encrypted block** so the relay never stores or forwards it (see
  9.1.29 for the envelope shape change and back-compat handling);
  the push data block is compatible with `callDecryptMessage`;
  on group, emit the v3 replay envelope already produced by
  `buildGroupOfflineReplayEnvelope` (group path already keeps
  username inside the encrypted payload, no change needed)
- **iOS NSE target**: new `NotificationService` target with App Group +
  Keychain access group, embedding a trimmed Go xcframework (or a thin Swift
  reimplementation of `message.decrypt` / `group.decrypt`), reading keys from
  shared keychain
- **Android background handler**: upgrade `background_message_handler.dart`
  to decrypt and replace the fallback body when push data is ciphertext-only
- **shared key access layer**: `SecureKeyStore` gains an iOS `accessGroup`
  param so the NSE reads the same `identity_ml_kem_secret_key` /
  `group_key_<groupId>_<epoch>` entries as the main app
- **observability**: new flow events
  `PUSH_NSE_DECRYPT_OK` / `PUSH_NSE_DECRYPT_FAIL` / `PUSH_NSE_TIMEOUT` /
  `PUSH_ANDROID_DATA_DECRYPT_OK` / `_FAIL`, plus counters so degrade rate is
  measurable in TestFlight telemetry

This plan does NOT:

- change contact-request, group-invite, or announcement push copy — those are
  relay-authored, not message content, and the existing static strings stay
  (`contactRequestPushBody`, `groupInvitePushBody` at `inbox.go:36-38`)
- change in-app local notification generation for the foreground path —
  `notificationBodyForMessage` and `maybeShowNotification` stay as-is
- rework the inbox store-and-forward contract or gossipsub routing
- change reaction / delete-for-everyone / edit push behavior — those route
  through the same pipe and will inherit the new ciphertext-only contract
  without per-feature work
- add new crypto primitives — decryption reuses the existing
  `message.decrypt` and `group.decrypt` bridge commands

## 4. Closure Bar

This area is good enough for the current architecture when all of the
following are true at the same time:

- a lock-screen notification for a received 1:1 message on iOS shows the
  sender's display name as the title and the message text (or a typed
  descriptor for media-only) as the body, and the relay operator observing
  the push payload sees only ciphertext + routing metadata in `data`
- the equivalent is true for group messages on iOS (title = group name,
  body = `"<sender>: <text>"`)
- Android foreground + background delivery shows the same rewritten preview
  for both 1:1 and group, with no plaintext in the FCM payload
- when the NSE cannot decrypt (key missing, timeout, extension crash, or
  ciphertext older than the retained key epoch) the user sees a degraded
  fallback (`"New message"` or group name only) rather than a leaked
  plaintext
- notification tap still routes correctly through the existing
  `NotificationRouteTarget.fromRemoteMessageData` path
- the existing foreground drain / duplicate-notification suppression logic
  (plan 71) keeps working for the ciphertext payloads
- the relay's `inbox_test.go` APNS / FCM contract tests assert the new
  ciphertext-only shape for message pushes and the unchanged shape for
  contact-request / invite pushes
- degrade rate (NSE timeout + key miss) observed in TestFlight is below a
  stated threshold (e.g. < 3 % of message pushes show the fallback)

## 5. Source Of Truth

Primary repo evidence — current state:

- `go-relay-server/inbox.go` — lines `33` (generic fallback), `36-38`
  (other static strings), `279-305` (title/body selection), `359-414`
  (`buildGroupPushMessage`), `760-777` (`StoreWithPushMetadata`),
  `910-911` (request struct)
- `go-relay-server/inbox_test.go:1062-1063` — current group push contract
  expectation with plaintext `pushTitle` / `pushBody`
- `lib/features/groups/application/send_group_message_use_case.dart:34-57,
  338-390` — client-side plaintext preview construction
- `lib/features/groups/application/group_offline_replay_envelope.dart:12-52`
  — v3 replay envelope used as the ciphertext payload
- `lib/features/groups/application/group_message_listener.dart:264-266` —
  in-app (foreground) preview formatter
- `lib/features/conversation/application/chat_message_listener.dart:454` —
  1:1 foreground preview formatter
- `lib/features/push/application/show_notification_use_case.dart:17-33` —
  `notificationBodyForMessage` (caption-first + typed media descriptors)
- `lib/features/push/application/background_push_notification_fallback.dart`
  — background fallback with the same `"You have a new message"` constant
- `lib/features/push/application/background_message_handler.dart` — current
  FCM background handler (the surface we will extend)
- `lib/core/bridge/bridge.dart:566-583` — `callDecryptMessage` (1:1)
- `lib/core/bridge/bridge_group_helpers.dart:949-963` — `callGroupDecrypt`
- `lib/core/secure_storage/flutter_secure_key_store.dart` — the backing
  store that will need `accessGroup` on iOS
- `lib/core/secure_storage/secure_key_store.dart` — abstract interface to
  extend
- `ios/Runner/Runner.entitlements` — already has
  `com.apple.security.application-groups` = `group.com.mknoon.app.share`
- `ios/Share Extension/` — precedent for a second iOS target sharing the
  App Group with the main app

Related prior work:

- `Test-Flight-Improv/52-notification-journey-test-matrix.md` — documents
  the DM-001 / GMN-001 "named copy" requirement that motivates this plan
- `Test-Flight-Improv/53-notification-background-delivery-reliability-plan.md`
  — complementary reliability plan; must keep its closure bar green
- `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md` — the
  foreground drain behavior this plan must preserve
- `test/core/notifications/notification_route_contract_matrix_test.dart`,
  `test/core/notifications/notification_route_target_test.dart` — the
  routing contract the new payload shape must satisfy

Disagreement rule:

- the relay's `go-relay-server/inbox_test.go` is the authoritative contract
  for push payload shape — any prose here that disagrees with those tests
  after this plan ships is stale
- `test-gate-definitions.md` decides what counts as a passing gate

## 6. Threat Model and Trust Boundary

**Who we are protecting the user from:** the relay operator (us, a future
acquirer, a legal compelled-disclosure request), anyone with ambient access
to relay disk / logs / TLS termination / cloud provider memory, and APNs /
FCM providers that see the push payload in transit.

**What stays visible after this plan:**

- sender and recipient peer IDs (routing metadata — unavoidable on the
  store-and-forward inbox)
- group IDs (routing metadata)
- `messageId` (needed for dedupe and tap-open routing)
- `keyEpoch` (needed so the device can look up the right group key)
- push timing (message rate is observable from traffic)
- ciphertext length (approximates plaintext length within AES-GCM padding)

**What stops being visible — the four forbidden preview-derived
categories (spec 74 contract):**

1. **Message text content** — 1:1 and group plaintext bodies
2. **Sender display name / username** in any relay-visible or
   push-provider-visible field. This has THREE distinct leak sources
   on the current code — all three must be closed:
   - (a) group path: the `pushBody` `"<username>: <text>"` prefix
     (closed by Phase 2 removing `pushBody`)
   - (b) 1:1 path outbound: `metadata.Title = senderUsername` is set
     in `extractChatPushMetadata` and ends up in `aps.alert.title`
     (closed by Phase 1 ciphertext-only + explicit 9.1.1 assertions
     that `aps.alert.title` is empty/default and `data.senderUsername`
     is absent)
   - (c) **1:1 path envelope-level leak**: the v2 envelope at
     `lib/features/conversation/domain/models/message_payload.dart`
     puts `senderUsername` in the outer cleartext alongside
     `senderPeerId`. The relay reads this field AND stores the
     whole envelope in its inbox DB, so every 1:1 message leaks the
     sender's display name to relay disk / TLS termination /
     operator-readable backups — even after Phases 1 and 2 ship.
     (Closed by 9.1.29 moving `senderUsername` inside the encrypted
     block; group path is already clean on this axis —
     `send_group_message_use_case.dart:362` seals username inside
     the v3 encrypted payload)
3. **Group name** in any push-visible field (was in `pushTitle`)
4. **Media descriptor preview copy** — e.g. the relay used to know
   `"alice sent a photo"` vs `"alice sent a voice message"`; under
   this plan even the static strings `"Photo"`, `"Voice message"`,
   `"Video"`, `"File"`, `"Media"`, `"GIF"` must never appear in any
   relay/push-visible field (they are content metadata — they reveal
   the attachment type beyond what ciphertext length alone reveals)

These four categories are the enforceable contract. Plan 73's
forbidden-field classifier test (9.7.1) parameterizes over them.
Any future code that needs to emit *any* preview-derived data to a
push-visible surface must either (a) encrypt it inside the envelope
the NSE / Android handler decrypts, or (b) extend the forbidden-field
classifier test to add the new category — tests fail loudly before
the leak reaches production.

**Explicit non-goals:**

- hiding *that* a push happened (traffic analysis is out of scope)
- hiding group membership from the relay (we still send recipient peer IDs)
- protecting against a compromised device — if the OS keychain is
  exfiltrated, previews are decryptable, but so is the whole message store

## 7. Key Material Sharing — The Hard Part

The NSE and the Android background isolate must read the same keys the main
app uses, or decryption fails. Three secrets are in play:

| Key | Stored under | Used for |
| --- | --- | --- |
| `identity_ml_kem_secret_key` | `SecureKeyStore` (iOS Keychain / Android EncryptedSharedPreferences) | 1:1 `message.decrypt` |
| `identity_private_key` (Ed25519) | same | envelope signature verify |
| `group_key_<groupId>_<epoch>` | `groups` repo DB (SQLCipher) | `group.decrypt` |

iOS approach:

- add a new App Group `group.com.mknoon.app.push` (or reuse the existing
  `group.com.mknoon.app.share` if we accept widening its access footprint)
- set `kSecAttrAccessGroup` on every keychain write in
  `FlutterSecureKeyStore` so both the main app and the NSE resolve the same
  keychain item — this requires a small patch to either
  `flutter_secure_storage` options (`IOSOptions(accessGroup: ...)`) or a
  wrapper
- access a shared SQLCipher DB in the App Group container for group keys,
  or mirror the per-epoch group key into the keychain (smaller dataset, fits
  keychain, simpler to share)
- recommended: mirror the group key into keychain under
  `group_key_<groupId>_<epoch>` on write and read it from the NSE — keeps
  SQLCipher single-owner

Android approach:

- `flutter_secure_storage` → EncryptedSharedPreferences lives in the app's
  data dir, already accessible to the FCM background isolate because
  `onBackgroundMessage` runs inside the same app process (not a separate
  process, different from iOS NSE)
- no App Group analogue needed; the isolate can reach the Flutter DI chain
  after `Firebase.initializeApp` via the existing
  `firebaseMessagingBackgroundHandler` entrypoint
- caveat: the background isolate must spin up a minimal DI chain
  (SecureKeyStore + group key repo) on each invocation — this is the single
  biggest Android cost

## 8. Implementation Phases (TDD-ordered)

### Phase 1 — Relay ciphertext-only payload contract (server)

**Goal:** the relay stops emitting plaintext `pushTitle` / `pushBody` for
message pushes and starts shipping a decrypt-ready data block.

1. Add a new test in `go-relay-server/inbox_test.go`:
   - asserts that for a `new_message` route type, the APNs payload has
     `mutable-content: 1`, an alert body of `"New message"` (static
     placeholder), and a `data.ciphertext` / `data.nonce` / `data.keyEpoch`
     block
   - asserts that the FCM payload has no top-level `notification` key
     (data-only), and the same `ciphertext` / `nonce` / `keyEpoch` fields
     in `data`
   - asserts unchanged shape for `contact_request` and `group_invite`
2. Implement the contract change in `buildGroupPushMessage` and its 1:1
   sibling path. Keep contact-request / invite unchanged.
3. Delete the client-side `pushTitle` / `pushBody` reads in the relay
   message-push path — do not delete the struct fields yet (so old clients
   still parse; see Phase 6 migration).
4. Extend `extractChatPushMetadata` (`inbox.go:273`) so the ciphertext
   envelope's routing metadata (sender peer ID, group ID, messageId)
   survives into `data`.

**Exit criteria:** the new test passes; all existing relay tests pass with
updates to the expected shape for message pushes only.

### Phase 2 — Client send-path ceases shipping plaintext previews

**Goal:** client stops computing `pushTitle` / `pushBody` for message pushes.

1. Add a failing test in
   `test/features/groups/application/send_group_message_use_case_test.dart`
   asserting the inbox payload has no `pushTitle` / `pushBody` keys.
2. Remove `_buildGroupPushTitle` / `_buildGroupPushBody` from
   `send_group_message_use_case.dart`. Keep the call signatures that accept
   `pushTitle` / `pushBody` on `_tryInboxStore` for now (Phase 6 cleanup)
   and pass `null`.
3. **Touch `dissolve_group_use_case.dart:133-134`** — remove the
   `pushTitle: group.name` and `pushBody: buildGroupDissolvedTimelineText(actorUsername)`
   fields from the inbox-store request. Dissolve is now a
   ciphertext-only envelope kind `group_dissolved`; the actor username,
   group name, and dissolution timestamp move inside the encrypted
   payload. See 9.1.1.1 for the full design (resolved 2026-04-24,
   Option B). The decrypt path on NSE / Android handler renders
   `"Group dissolved by <actor>"` after successful decrypt, or
   `"New message"` on fallback. Regression guard:
   `test/features/groups/application/dissolve_group_use_case_test.dart`
   `dissolve inbox request omits plaintext pushTitle and pushBody`.
4. Verify in-app preview formatters (`chat_message_listener.dart:454`,
   `group_message_listener.dart:264-266`) are untouched — they still need
   the plaintext they produce locally.

**Exit criteria:** the test passes; relay unit tests from Phase 1 still
pass with the new client output; manual wire-capture confirms no plaintext
preview in push traffic.

### Phase 3 — Android data-only decrypt-and-replace handler

**Goal:** on Android, the FCM background isolate decrypts ciphertext and
shows a rewritten local notification in place of the static fallback.

1. Add a failing test in
   `test/features/push/application/background_message_handler_test.dart`
   that fakes a data-only FCM message with `ciphertext` + `nonce` +
   `messageId` + `senderPeerId` for 1:1, asserts the local notification
   body equals `"<senderUsername>: <plaintext>"`.
2. Extend `background_message_handler.dart`:
   - detect ciphertext-only push via the presence of `ciphertext` in
     `message.data`
   - construct a minimal DI chain (SecureKeyStore, IdentityRepository,
     GroupRepository) — wrap in a factory so the main app and background
     isolate share one constructor
   - for 1:1: call `callDecryptMessage` via a Bridge instance — requires
     `Bridge` to be initializable in a background isolate (today it's a
     singleton constructed in `main.dart`). Add a background-friendly
     constructor that starts the Go node in "decrypt-only" mode (no
     network).
   - for group: resolve the group key by `(groupId, keyEpoch)` and call
     `callGroupDecrypt`
   - on success, rewrite the body via `pushPreviewBody`
     (new wrapper in `lib/features/push/application/push_preview_body.dart`;
     delegates to `notificationBodyForMessage` at
     `show_notification_use_case.dart:17-33` and applies the
     140-grapheme cap — see 9.1.21 for the scope rationale) and
     surface it via `flutter_local_notifications.show` exactly like
     today's fallback
   - on failure, keep the existing fallback path
   - emit `PUSH_ANDROID_DATA_DECRYPT_OK` / `_FAIL` with
     `{ messageId, kind, error? }`
3. Update `background_push_notification_fallback.dart` to treat
   ciphertext-only data as non-renderable for the top-level fallback (so
   we don't flash the placeholder then re-render).

**Gotcha to test:**

- Doze mode: emulate with `adb shell dumpsys deviceidle force-idle` and
  confirm delivery still arrives (may be delayed, that's acceptable)
- cold-start isolate: kill the app, send a push, confirm the isolate boots
  the DI chain and decrypts within a reasonable budget (< 5 s target)

**Exit criteria:** test passes on Pixel emulator and at least one OEM
device; degrade path is hit when key is deliberately removed.

### Phase 4 — iOS Notification Service Extension target

**Goal:** iOS NSE receives the mutable push, decrypts, and replaces the
body in-place before the OS renders.

1. Xcode: create `NotificationService` target (Swift, iOS 15+ to match
   `Runner`).
2. Entitlements: add App Group + Keychain access group membership. Pattern
   this after `ios/Share Extension/Share Extension.entitlements`.
3. Patch `flutter_secure_storage` consumption — either:
   - fork/patch to accept `accessGroup` and set it in
     `FlutterSecureKeyStore`, or
   - bypass the Dart wrapper in the NSE and read via `Security.framework`
     directly in Swift with `kSecAttrAccessGroup`
   The second option is simpler and avoids Dart runtime in the NSE; taken
   as the default in this plan.
4. Group key sharing: main app writes every `(groupId, keyEpoch) → key`
   into the shared keychain on creation/rotation; NSE reads.
5. Decrypt surface in the NSE:
   - minimum: statically link a thin Swift `NoonDecrypt` library that wraps
     libsodium / CryptoKit for AES-GCM (group) and ML-KEM-768 (1:1). This
     avoids embedding `GoMknoon.xcframework` (~20 MB) which may exceed the
     NSE memory budget.
   - alternative: embed a stripped `GoMknoonDecrypt.xcframework` built with
     only `message.decrypt` / `group.decrypt` exported. Measure size first;
     if < 10 MB, acceptable.
   - use CryptoKit for AES-GCM on iOS 15+; use a vetted ML-KEM-768 Swift
     package (SwiftKyber or equivalent) — audit before taking a dep
6. NSE entry point (`NotificationService.didReceive`):
   - read ciphertext/nonce/kind from `request.content.userInfo`
   - resolve key via shared keychain
   - decrypt synchronously with a 20 s watchdog
   - on success, set `bestAttemptContent.title` = resolved title,
     `bestAttemptContent.body` = Swift `pushPreviewBody` equivalent
     (port BOTH layers to Swift: the inner formatter parity of
     `notificationBodyForMessage` AND the outer 140-grapheme cap
     from `pushPreviewBody` — see 9.1.21 for the scope rationale
     that keeps the inner formatter uncapped so in-app flows stay
     intact)
   - on failure, leave the placeholder body as-is
   - call `contentHandler(bestAttemptContent)`
7. `serviceExtensionTimeWillExpire`: call `contentHandler` with the
   placeholder so the user still sees something.
8. Add a RunnerTests xctest that loads the NSE bundle, feeds it a fixture
   ciphertext (generated from a matching Go test that seals with a known
   key), and asserts the rewritten body.

**Gotchas to confirm:**

- NSE runs in a sandboxed process — no URL session to the relay for
  missing-key fetch (we keep it pure-local)
- NSE only fires for pushes with `mutable-content: 1` AND a non-empty alert
  block; the Phase 1 relay change must satisfy both
- background permissions: `aps-environment` stays `production`; no new
  user-facing permission

**Exit criteria:** iPhone 17 + iPhone 17 Pro simulators show the
decrypted preview on lock screen for 1:1 and group via
`xcrun simctl push`; forcing the key out of keychain shows the
placeholder; the xctest passes in CI; 9.4.1.1 simulator scenarios
S-iOS-1 through S-iOS-19 all green. Physical-device verification
is deferred to a follow-up plan.

### Phase 5 — Observability, degrade rate, and degrade cap

1. New flow events:
   `PUSH_NSE_DECRYPT_OK`, `PUSH_NSE_DECRYPT_FAIL` (with `reason`),
   `PUSH_NSE_TIMEOUT`,
   `PUSH_ANDROID_DATA_DECRYPT_OK`, `PUSH_ANDROID_DATA_DECRYPT_FAIL`.
2. TestFlight telemetry dashboard slice: degrade rate =
   `(fail + timeout) / total` over 7 days, per platform.
3. Add regression gate in `test-gate-definitions.md`: "push preview degrade
   rate < 3 % on golden-path device matrix". If exceeded in beta, the gate
   fails.
4. Ensure no new flow event leaks plaintext — payload text must NOT appear
   in any emitted event.

**Exit criteria:** dashboard is live, gate wired, three consecutive green
runs in CI.

### Phase 6 — Cleanup and back-compat retirement

1. After ≥ 1 release with all clients on the new format, drop the now-dead
   `PushTitle` / `PushBody` fields from the relay request struct
   (`inbox.go:910-911`) and the Dart helper plumbing
   (`group_offline_replay_envelope.dart:63-65, 90-91, 112-113`, the
   `_tryInboxStore` signature, etc.).
2. Delete `backgroundPushDefaultBody` if unused after Phase 3.
3. Remove or simplify `extractChatPushMetadata` — it no longer needs to
   parse the v1 `"text"` field for preview purposes (keep whatever routing
   logic is still load-bearing).
4. Update `52-notification-journey-test-matrix.md` to describe the new
   rendering path; remove the DM-001 "known gap" note.

## 9. Test Plan

This section supersedes the earlier "test matrix" bullet list with named
test files, explicit assertions, and harness ownership. Every phase exit
criterion in Section 8 must point to at least one entry below.

### 9.1 Test file catalog (by layer)

#### 9.1.1 Relay contract (Go, `go-relay-server/`)

Add to `inbox_test.go`:

- `TestBuildNewMessagePush_EmitsMutableContentAndCiphertextOnly`
  — asserts `apns.aps["mutable-content"] == 1`, alert body == `"New message"`,
  **alert title == empty/default (NOT the sender's username, NOT the
  sender's display name, NOT any string derivable from the sender's
  profile)**, and `data.ciphertext` / `data.nonce` / `data.keyEpoch` /
  `data.messageId` / `data.senderPeerId` (opaque peer ID — NOT
  username) are present and non-empty for a 1:1 message push.
  **Also asserts ABSENT: `data.senderUsername`, `data.sender_username`,
  `data.username`, `data.displayName`, `data.sender_display_name`,
  `aps.alert.title`, `aps.alert.subtitle`, `aps.alert.title-loc-key`.**
  The assertion list enumerates every field name that has *ever*
  appeared in this codebase's push payloads (grep-verified) so the
  reviewer can see at a glance that each legacy leak surface is
  individually checked — not just implicitly covered by the classifier.
- `TestBuildGroupMessagePush_EmitsMutableContentAndCiphertextOnly`
  — same as above but with `data.groupId` (opaque group ID — NOT
  group name) additionally present, no `pushTitle` / `pushBody`
  anywhere in the payload.
  **Also asserts ABSENT: `data.groupName`, `data.group_name`,
  `aps.alert.title` (was formerly the group name), AND all the
  sender-identity fields listed above**
- `TestBuildReactionPush_EmitsCiphertextOnly`
  — asserts reaction push envelopes also ship ciphertext-only and carry
  the correct `kind=reaction` routing metadata
- `TestBuildEditPush_EmitsCiphertextOnly`
  — same for message edits
- `TestBuildDeleteForEveryonePush_EmitsCiphertextOnly`
  — same for `delete_for_everyone`
- `TestBuildContactRequestPush_UnchangedShape`
  — asserts contact-request pushes still emit the static
  `"New Contact Request"` title/body and do NOT have `mutable-content: 1`
  (unchanged contract)
- `TestBuildGroupInvitePush_UnchangedShape`
  — same for group-invite pushes
- `TestBuildIntroductionPush_UnchangedShape`
  — intros have their own relay push path at `inbox.go:39-40, 277-297, 438`
  with static `"New Introduction"` / `"Open Mknoon to review"`; assert
  this path stays exactly as the existing `inbox_test.go:710-730`
  coverage defines it, is NOT mutable, and is NOT routed through
  `buildGroupPushMessage`
- **Dissolve-group pushes:** see 9.1.1.1 below — there is no dedicated
  relay path for dissolve and the product choice is not simply "keep
  the old behavior"
- `TestInboxStore_AcceptsDualFormatDuringRollout`
  — old client sends both `pushTitle` + `ciphertext`; assert the relay
  emits ciphertext-only (new format wins); asserts the old plaintext is
  dropped and never appears in the outbound APNs/FCM payload (G-04)
- `TestInboxStore_RejectsPayloadWithoutCiphertextOrLegacyFields`
  — payload missing BOTH shapes returns a clear 4xx; no silent pass
- `TestBuildMessagePush_PayloadSizeWithinProviderBudgets`
  — parameterized over 1:1, group, reaction, edit, delete-for-everyone,
  and dissolve ciphertext-only payloads; serializes the exact APNs and
  FCM payloads the relay would send and asserts each stays below the
  configured provider payload-size budget. The test constants must be
  documented with their provider source and should include a safety
  margin so future routing metadata additions fail before deployment.
- `TestNoPlaintextInAuditLog` — capture stdout/logger during push
  construction for a known-plaintext message; assert plaintext string
  does not appear (G-06 relay side)

Update existing tests at `inbox_test.go:1062-1063` to match the new
ciphertext-only shape for message pushes.

#### 9.1.1.1 Dissolve-group push — resolved: Option B (2026-04-24)

Unlike contact-request, group-invite, and introduction, the
group-dissolve notification has **no dedicated relay path**. Dissolve
events currently flow through `buildGroupPushMessage` because
`dissolve_group_use_case.dart:133-134` attaches `pushTitle = group.name`
and `pushBody = buildGroupDissolvedTimelineText(actorUsername)` to the
same group inbox request as any other group message.

**Decision:** dissolve joins the ciphertext-only regime. Treated as
just another envelope kind the NSE / Android handler decrypts.
Consistent with every other message path, no special-case in the
relay, matches the product requirement that the relay never see
group-event plaintext. When decrypt fails (cold-boot keychain, key
missing, unknown envelope kind on an old client), the user sees the
static `"New message"` placeholder — acceptable because the dissolve
event is also persisted in the group's timeline and the user will
see it in-app the next time they open the group.

Implementation changes required:

- **`dissolve_group_use_case.dart:133-134`** — remove the
  `pushTitle: group.name` and `pushBody: buildGroupDissolvedTimelineText(actorUsername)`
  fields from the inbox-store request (Phase 2 task)
- encrypt `{actorUsername, dissolvedAt, groupName}` inside the
  dissolve envelope under a new envelope kind `group_dissolved`
  (already the logical kind; formalize it)
- NSE and Android decrypt paths recognize `kind: "group_dissolved"`
  and render `"Group dissolved by <actor>"` via a dedicated formatter
  sibling of `notificationBodyForMessage` — put it in the same
  file so Dart and Swift ports stay aligned

Required tests:

- `go-relay-server/inbox_test.go` —
  `TestBuildDissolvePush_FlowsThroughCiphertextOnlyPath`
  — feed a dissolve envelope to the relay; assert the outbound APNs
  payload is ciphertext-only and no plaintext actor/group name
  appears in `pushTitle`, `pushBody`, or the APNs alert body
- `test/features/groups/application/dissolve_group_use_case_test.dart` —
  `dissolve inbox request omits plaintext pushTitle and pushBody`
  — regression guard for the Phase 2 change
- `ios/RunnerTests/NotificationServiceTests.swift` —
  `test_dissolveEnvelope_rendersActorNamedBody`
  — decrypt succeeds; `bestAttemptContent.body == "Group dissolved by alice"`
- `test/features/push/application/background_message_handler_test.dart` —
  `dissolve envelope rendered with actor-named body on Android`
  — Android equivalent
- `ios/RunnerTests/NotificationServiceTests.swift` +
  Android counterpart —
  `test_dissolveEnvelope_keyMissing_showsPlaceholder`
  — decrypt fails; body == `"New message"`; in-app dissolve timeline
  still persists via the normal inbox drain (asserted by the existing
  drain gate)
- `test/security/no_plaintext_leak_test.dart` — extend the canary
  sweep to cover the dissolve path; asserts the actor username and
  group name never appear in a flow event or log for a dissolve push

Phase 2 step 3 directive is superseded — **dissolve IS touched in
Phase 2** (see the edit captured in Section 8 below).

#### 9.1.2 Client send path (Dart)

Add to `test/features/groups/application/send_group_message_use_case_test.dart`:

- `group inbox retry payload omits pushTitle and pushBody`
  — build a canonical send, assert the JSON has no `pushTitle` /
  `pushBody` keys
- `group inbox retry payload includes ciphertext routing metadata`
  — asserts `keyEpoch`, `messageId`, and the v3 envelope are present
- `no plaintext leaks into emitted flow events during send`
  — capture `emitFlowEvent` output, assert message text does not appear
  in any event body

Add new file
`test/features/conversation/application/send_chat_message_use_case_test.dart`
(or extend existing 1:1 send-path test — the plan's 1:1 send-path file
must be located during Phase 2):

- `1:1 inbox payload omits plaintext body fields`
- `1:1 inbox payload carries v2 envelope with ml-kem kem/ciphertext/nonce`
- `no plaintext leaks into flow events during 1:1 send`

Add to `test/features/groups/application/send_group_reaction_use_case_test.dart`
(already exists, modified in git):

- `reaction send envelope omits plaintext reaction character in push data`

#### 9.1.3 Android background decrypt (Dart)

Replace / extend
`test/features/push/application/background_message_handler_test.dart`:

- `decrypts 1:1 ciphertext-only data push and shows named preview`
  — inject a `FakeBridge` that returns `{"ok": true, "plaintext": "hello"}`
  for `callDecryptMessage`; inject a `FakeSecureKeyStore` with the ML-KEM
  secret key; feed a data-only `RemoteMessage` with `ciphertext`, `nonce`,
  `kem`, `messageId`, `senderPeerId`; assert `flutter_local_notifications`
  `show()` is called with body == `"alice: hello"`
- `decrypts group ciphertext-only data push and shows named preview`
  — same shape with `groupId` + `keyEpoch`; `FakeBridge` returns the
  decoded group inbox payload; body == `"alice: hello"` and title ==
  group name
- `renders typed media descriptor when plaintext body is empty`
  — plaintext has empty `text` and one image attachment; body ==
  `"alice: Photo"`
- `falls back to placeholder when key is missing`
  — `FakeSecureKeyStore` returns null; assert body == `"New message"`,
  assert `PUSH_ANDROID_DATA_DECRYPT_FAIL` event fires with
  `reason: "key_missing"`, assert no plaintext in the emitted event
- `falls back to placeholder when bridge throws`
  — `FakeBridge` throws `BridgeCommandException`; same fallback
  assertions as above; `reason: "decrypt_failed"`
- `falls back when keyEpoch does not match any stored group key`
  — asserts graceful degrade, `reason: "epoch_missing"`
- `falls back when ciphertext is corrupt`
  — mutate one byte; `reason: "mac_failed"`; no crash, no leak
- `dedupes duplicate ciphertext for same messageId`
  — feed the same push twice; assert `show()` called exactly once
  (prevents replay from producing N notifications)
- `does not emit plaintext anywhere in flow events`
  — capture every emitted event; assert plaintext string never appears
  (G-06 Android side)
- `Bridge background constructor starts in decrypt-only mode`
  — assert no libp2p node start, no network calls, no relay connection
  during the background decrypt path (this is the cold-start-cost gate)

Add benchmark test
`test/features/push/performance/background_decrypt_benchmark_test.dart`:

- `cold-start Android decrypt completes under 5 seconds on golden Pixel`
  — not a CI gate (emulator timing is noisy); produces a timing number
  that is recorded in the device-matrix release checklist (see 9.4)

#### 9.1.4 iOS Notification Service Extension (Swift, `ios/NotificationService/` + `RunnerTests/`)

Add `ios/RunnerTests/NotificationServiceTests.swift`:

- `test_decryptsOneToOneCiphertext_replacesBody`
  — load fixture from `ios/RunnerTests/Fixtures/push_1to1_fixture.json`
  (generated by Phase 1 Go test — see 9.2); seed shared keychain with the
  fixture's key; instantiate `NotificationService`; call `didReceive` with
  a constructed `UNNotificationRequest`; assert
  `bestAttemptContent.title == "alice"`, body == `"hello"`
- `test_decryptsGroupCiphertext_replacesTitleAndBody`
  — fixture `push_group_fixture.json`; assert title == group name,
  body == `"alice: hello"`
- `test_keyMissing_leavesPlaceholderBody`
  — do not seed keychain; call `didReceive`; assert body stays as the
  placeholder `"New message"`
- `test_corruptCiphertext_leavesPlaceholderBody`
  — mutate a byte in fixture ciphertext; same assertion
- `test_timeWillExpire_deliversPlaceholder`
  — override decrypt with a sleep exceeding the watchdog; trigger
  `serviceExtensionTimeWillExpire`; assert `contentHandler` is called
  with the placeholder (G-07 soft-verification: we test the handler
  contract, not the OS kill — memory pressure itself is covered by the
  bundle-size CI gate in 9.3)
- `test_mediaOnlyPlaintext_rendersTypedDescriptor`
  — plaintext body empty, media attachment type = audio; assert body
  == `"alice: Voice message"` (this is the Swift port parity anchor for
  G-11)
- `test_replayedMessageId_notShownTwice`
  — call `didReceive` twice with same messageId; assert second call
  leaves placeholder (NSE has no persistent store — dedupe uses the
  shared App Group container sentinel; document sentinel TTL and test
  it)

Add `ios/RunnerTests/SwiftNotificationBodyFormatterTests.swift`:

- covers every branch of the ported `notificationBodyForMessage` for
  parity with the Dart original — one test per media type plus the
  caption-first rule (G-11 systematic)

#### 9.1.5 Cross-platform decrypt parity (fixture-driven) — G-03 anchor

Shared-fixture approach:

- Add `go-relay-server/testfixtures/push_crypto_fixtures_test.go`:
  uses the project's existing Go crypto (`go-mknoon/crypto/`) to produce
  canonical ciphertexts for three cases (1:1 text, group text, group
  with media) using a fixed key and fixed nonce; writes
  `ios/RunnerTests/Fixtures/*.json` and
  `test/features/push/fixtures/*.json` as build-time artifacts
- `test/features/push/cross_platform_parity_test.dart`:
  feeds each Dart fixture into the background handler's decrypt path via
  the real `callDecryptMessage` on a `LocalGoBridge` (not a fake) and
  asserts the output equals the expected plaintext captured in the
  fixture JSON
- `ios/RunnerTests/CrossPlatformParityTests.swift`:
  feeds each Swift fixture into the Swift decrypt path and asserts the
  same plaintext
- `ios/RunnerTests/CryptoKnownAnswerTests.swift`:
  uses independent published/standard crypto known-answer vectors for
  every Swift-native primitive introduced by the NSE path, including
  AES-GCM and ML-KEM if Swift code performs those operations directly.
  These tests must not use fixtures generated by this repo; they catch
  a Swift crypto implementation that matches the repo's fixture bug but
  diverges from the standard.
- CI gate: both the Dart test and the Swift test MUST use the same
  fixture file hash; if `push_crypto_fixtures_test.go` regenerates a
  fixture, both platform tests rerun and must still pass
- This is the blocker that prevents CryptoKit-vs-Go GCM divergence from
  silently breaking iOS

#### 9.1.6 Routing-contract regression (Dart)

Update the two files already modified in git on this branch:

- `test/core/notifications/notification_route_contract_matrix_test.dart`:
  add rows for `{kind: "new_message", hasCiphertext: true}` and
  `{kind: "group_message", hasCiphertext: true}`; assert each routes to
  the correct `NotificationRouteTarget` and that the routing logic does
  NOT depend on the absence of `pushTitle` / `pushBody`
- `test/core/notifications/notification_route_target_test.dart`:
  add a test asserting `NotificationRouteTarget.fromRemoteMessageData`
  accepts the ciphertext-only shape as a valid route target (G-08)

#### 9.1.7 Keychain access group migration (iOS)

Add `ios/RunnerTests/KeychainAccessGroupMigrationTests.swift`:

- `test_legacyKeychainItem_migratedToAccessGroup_readableByNSE`
  — write a keychain item using the pre-migration path (no
  `kSecAttrAccessGroup`); run the migration; read via the NSE's Swift
  `Security.framework` path using the access group; assert the value
  matches (G-12)
- `test_migrationIsIdempotent`
  — run the migration twice; assert no duplicates, no data loss
- `test_freshInstall_usesAccessGroupFromFirstWrite`
  — write as a fresh install; assert the access group attribute is set

### 9.2 Fixture generation pipeline

The cross-platform parity plan (9.1.5) depends on a reproducible fixture
generator. Ownership:

- canonical generator lives in Go (`go-relay-server/testfixtures/`),
  reuses `go-mknoon/crypto/` so the fixtures reflect production crypto
- generator is invoked in `go test` pre-step during CI
- output files are checked into the repo under
  `ios/RunnerTests/Fixtures/` and `test/features/push/fixtures/`
- a CI check ensures generated fixtures have not drifted from checked-in
  copies (`git diff --exit-code` after regeneration)
- fixture schema documented in
  `test/features/push/fixtures/README.md` — fields: `keyHex`,
  `nonceHex`, `ciphertextHex`, `expectedPlaintextUtf8`,
  `expectedRenderedBody`, `expectedRenderedTitle`, `kind`, `mediaType`

### 9.3 CI gates (automated)

- `flutter test` — all Dart tests above
- `go test ./...` — all Go tests above
- `xcodebuild test -scheme RunnerTests` — all Swift tests above
- **`ios/NotificationService.appex` size budget**: a new CI step runs
  `xcodebuild archive` and asserts the compiled extension's Mach-O
  binary is under a configured cap. Suggested cap: 8 MB for the binary,
  12 MB for the full appex bundle. Exceeds cap → CI fails.
  (Replaces the ill-fated "test memory pressure" approach — addresses
  G-07 at build time instead of run time.)
- **Fixture drift check**: `go test ./go-relay-server/testfixtures/...`
  regenerates and diffs; non-zero diff → CI fails
- **Push payload-size budget check**: relay tests assert APNs and FCM
  ciphertext-only message payloads remain below configured provider
  limits with margin. Any payload-size regression blocks the PR because
  oversize pushes fail at delivery time, not at app runtime.
- **No-plaintext-in-flow-events gate**: a Dart test suite asserts every
  push-related flow event passes through a `LeakScanner` that fails if
  any event body contains a known plaintext canary string. Run on every
  PR.
- **Regression gates that must stay green** (from
  `test-gate-definitions.md`):
  - Group Messaging Gate — includes `group_messaging_smoke_test.dart`,
    `invite_round_trip_test.dart` (Phase 1 relay change risks this)
  - 1:1 Messaging Gate
  - Notification Gate — the already-modified
    `notification_route_contract_matrix_test.dart`,
    `notification_route_target_test.dart`
  - Foreground Drain Gate (plan 71) — asserts in-app foreground messages
    still drain and dedupe correctly for ciphertext pushes

### 9.4 Simulator matrix (the "device matrix" for this plan)

**Scope decision (2026-04-24):** plan 73 ships with simulator-only
coverage. Physical-device testing is deferred to a follow-up plan
(TBD). Simulators serve as the authoritative test targets for this
plan's release gates; TestFlight degrade-rate telemetry (9.6) is
the production backstop for anything simulators cannot catch (9.4.1.3
parity-gap table documents what those items are).

Mandatory simulator runs before each phase ships — using the team's
confirmed 2026-04-24 environment:

| Platform | Simulator | OS | Role |
| --- | --- | --- | --- |
| iOS | **iPhone 17** simulator | iOS latest | primary — sender, single-device scenarios |
| iOS | **iPhone 17 Pro** simulator | iOS latest | secondary — receiver for dual-sim scenarios (S-iOS-17/18/19) |
| Android | **Pixel 7 API 37** emulator | Android (API 37) | single Android target — sender AND receiver scenarios |

APNs delivery on iOS simulator works via
`xcrun simctl push <device> <bundle-id> <payload.json>` on Xcode 14+
— this DOES wake the NSE for payloads with `mutable-content: 1`
and is functionally equivalent to a real APNs delivery for
correctness (though not for timing / reliability — see 9.4.1.3).
`scripts/push_fixture_to_simulator.sh` is the primary harness.

FCM delivery on Android emulator uses `adb shell am broadcast` or a
local FCM stub wrapping `com.google.firebase.MESSAGING_EVENT`; the
emulator must be a Google Play Services image (not AOSP-only).

### 9.4.1 Simulator-based verification (authoritative for plan 73)

For plan 73 simulators ARE the test targets — there is no parallel
physical-device matrix that must also pass. Scenarios below are the
release gates.

**Team simulator environment (2026-04-24, as confirmed by the owner):**

- iOS: **iPhone 17 simulator** + **iPhone 17 Pro simulator** (two
  parallel simulators booted at once, used for sender/receiver
  scenarios that need a second device)
- Android: **Pixel 7 API 37 emulator** (single emulator)

All simulator scenarios below target this specific inventory. If a
new simulator is added or removed from the environment, update this
section and the device-matrix table in 9.4 together.

Known behaviors that simulators CANNOT reproduce (memory pressure,
Doze, OEM throttling, cold-boot keychain lock, real APNs/FCM network
delivery) are enumerated in 9.4.1.3. For plan 73 those items are
either covered by CI build gates (bundle-size, extracted sentinel),
by TestFlight production telemetry (degrade-rate gate 9.6), or
explicitly deferred to a future physical-device verification plan.

#### 9.4.1.1 iOS Simulator coverage (what it CAN verify)

iOS Simulator (Xcode 14.3+) supports a substantial slice of the
real push pipeline:

- `xcrun simctl push <device-id> <bundle-id> <payload.json>`
  delivers a constructed APNs payload to the simulator's push daemon,
  which wakes the NSE for payloads with `mutable-content: 1`
- NSE decrypt path runs normally — keychain, App Group container,
  shared ciphertext/nonce decode, `bestAttemptContent` rewrite all
  function at the API-contract level the same way they do on a real
  device (with the caveats in 9.4.1.3 — no memory cap, no cold-boot
  lock)
- Lock-screen notification renders through the real
  `UserNotifications.framework`; body/title/threadIdentifier are
  observable via `UNUserNotificationCenter`
- `UIApplicationState` transitions (background / foreground / active)
  work; active-conversation suppression gates fire correctly
- Keychain access group + App Group entitlements resolve correctly
  as long as the dev provisioning profile on the simulator matches

Scripted test runner (`scripts/push_fixture_to_simulator.sh`) steps:

1. `xcrun simctl boot "iPhone 17"` and
   `xcrun simctl boot "iPhone 17 Pro"` — start both simulators
   (matches the team's 2-iOS-simulator setup; the Pro role is used
   whenever a scenario needs a second receiver in parallel,
   e.g. multi-device smoke rows)
2. `flutter build ios --simulator --debug`, then install
   `build/ios/iphonesimulator/Runner.app` onto both iOS simulators
   with `xcrun simctl install`; verify
   `xcrun simctl get_app_container <device> com.mknoon.app` succeeds
   before any non-dry-run push delivery
3. launch the installed app on each simulator with
   `--dart-define=USE_TEST_RELAY=true` setup where the scenario
   needs live app state, following the existing memory-noted
   `reset_simulators.sh` auto-setup pattern
4. `xcrun simctl push "iPhone 17" <bundle-id> <fixture.json>` —
   deliver fixture from 9.2 fixture pipeline to the primary; or
   use the "iPhone 17 Pro" device-id for the secondary
5. capture `UNUserNotificationCenter.getDeliveredNotifications()`
   result via an XCUITest harness OR by log-scraping the NSE's
   emitted flow events
6. assert body, title, threadIdentifier match fixture expectations

Test scenarios that run automatically on iOS Simulator in CI:

| # | Scenario | Fixture |
| --- | --- | --- |
| S-iOS-1 | 1:1 text decrypted preview | `post_phase1_onetoone_text.json` |
| S-iOS-2 | 1:1 media voice-note descriptor | `post_phase1_onetoone_media_audio.json` |
| S-iOS-3 | Group text with decrypted sender prefix | `post_phase1_group_text.json` |
| S-iOS-4 | Group media "alice sent a photo" descriptor | `post_phase1_group_media_image.json` |
| S-iOS-5 | Key-missing → placeholder body | same as S-iOS-1 but with pre-test keychain clear |
| S-iOS-6 | Corrupt ciphertext → placeholder body | fixture with MAC-tampered byte |
| S-iOS-7 | Tampered signature → placeholder body | 9.1.18 fixture |
| S-iOS-8 | Unknown envelope kind → placeholder body | 9.1.22 fixture |
| S-iOS-9 | Dissolve envelope → "Group dissolved by alice" | 9.1.1.1 fixture |
| S-iOS-10 | 140-grapheme cap on long text | 9.1.21 fixture with 500-char text |
| S-iOS-11 | threadIdentifier on 1:1 = sender peer ID | any 1:1 fixture |
| S-iOS-12 | threadIdentifier on group = group ID | any group fixture |
| S-iOS-13 | Active-conversation suppression (1:1) | deliver while conversation screen is on top |
| S-iOS-14 | Active-conversation suppression (group) | deliver while group screen is on top |
| S-iOS-15 | Preview-length cap produces `…` suffix | long-text fixture |
| S-iOS-16 | Forbidden-field classifier canaries never appear in NSE logs | 9.7.1 canary fixtures |
| S-iOS-17 | **Dual-simulator**: iPhone 17 sender → iPhone 17 Pro receiver, full sender-to-lock-screen flow with both NSE decryptions live | any 1:1 fixture, both simulators booted |
| S-iOS-18 | **Dual-simulator**: same user signed in on iPhone 17 AND iPhone 17 Pro; one sender push delivers to both; assert each shows its own lock-screen notification (natural multi-device behavior per 9.1.17 scope guard) | any 1:1 fixture |
| S-iOS-19 | **Dual-simulator** group message fan-out: iPhone 17 as one group member, iPhone 17 Pro as another; sender triggers; both receive decrypted group preview | any group fixture |

#### 9.4.1.2 Android Emulator coverage (what it CAN verify)

Android Emulator with Google Play Services (Pixel emulator image,
not AOSP image) supports FCM delivery and the background isolate:

- `adb shell am broadcast -a com.google.android.c2dm.intent.RECEIVE`
  or use a local FCM-emulator harness to inject a data-only push
- Flutter `firebase_messaging` `onBackgroundMessage` handler fires
  with the injected payload
- `background_message_handler.dart` decrypt path runs at the
  API-contract level the same way it does on a real device (caveats
  in 9.4.1.3 — no Doze, no OEM throttling)
- `flutter_local_notifications.show` renders the rewritten
  notification; content observable via `UiAutomator` or log-scrape
- `ActiveConversationTracker` state reads/writes work normally

Scripted test runner (`scripts/push_fixture_to_android_emulator.sh`):

1. `emulator @Pixel_7_API_37 -no-snapshot -no-audio &` — boot the
   team's single Android emulator (Pixel 7, API 37)
2. `flutter build apk --debug`, then install
   `build/app/outputs/flutter-apk/app-debug.apk` onto the emulator
   with `adb -s emulator-5554 install -r`; verify
   `adb -s emulator-5554 shell pm path com.mknoon.app` succeeds
   before any non-dry-run push delivery
3. launch the installed app with `--dart-define=USE_TEST_RELAY=true`
   setup where the scenario needs live app state
4. inject fixture via `adb shell am broadcast` with
   `com.google.firebase.MESSAGING_EVENT` payload wrapping the
   fixture data block
5. capture notification output via `adb shell dumpsys notification`
6. assert body, title, group key match fixture expectations

Test scenarios that run automatically on Android Emulator in CI:

| # | Scenario | Fixture |
| --- | --- | --- |
| S-And-1 through S-And-16 | Mirror of S-iOS-1 through S-iOS-16 scenarios (single-emulator cases; S-iOS-17/18/19 dual-simulator rows have no Android equivalent because the team runs only one Android emulator) | same fixtures |
| S-And-17 | FCM data-only message (no top-level `notification` key) wakes isolate | any `post_phase1_*.json` |
| S-And-18 | Dual-tolerance: legacy plaintext `pushBody` path still renders pre-Phase-1 fixture | `pre_phase1_group_text.json` |
| S-And-19 | Background isolate cold-start boots DI chain and decrypts | app force-stopped, then push arrives |

**Known Android behaviors out of plan 73 scope** (cannot be
reproduced on emulator, explicitly deferred to a future
physical-device verification plan):

- Doze mode behavior (requires a physical device under real
  battery optimization policy — emulator Doze is not the same as
  production Doze)
- OEM-specific FCM throttling (Samsung/Xiaomi/Huawei/Oppo) —
  emulator is always stock AOSP + GMS
- Actual network round-trip latency from FCM production
- True memory pressure on the isolate

Production backstop for these items: the TestFlight degrade-rate
telemetry gate (9.6) will catch regressions once builds reach real
users. Plan 73 ships WITHOUT pre-release physical-device coverage
for these; the risk is accepted because the failure mode is a
degraded-notification UX (already covered by the placeholder
fallback), not a data-loss or security regression.

#### 9.4.1.3 What simulators CANNOT verify (parity gap — deferred or backstopped)

For plan 73 there is no physical-device matrix running in parallel,
so these gaps are closed by one of three mechanisms: a CI build
gate (enforces the constraint at compile time), TestFlight
production telemetry (catches the regression after it reaches
users), or explicit deferral to a follow-up physical-device
verification plan.

| Gap | Why simulators miss it | Coverage in plan 73 scope |
| --- | --- | --- |
| NSE 24 MB memory cap | Simulator runs with full host memory | **CI gate** — 9.3 NSE bundle-size check enforces ≤ 8 MB binary / 12 MB appex at build time. If the binary grows past budget, the cap might be exceeded at runtime; the build fails before reaching the simulator. |
| NSE 30 s wall-clock budget | Simulator CPU is faster than real iPhone | **TestFlight telemetry** — `PUSH_NSE_TIMEOUT` counter (9.5 flow events) catches it in production. Plan 73 does not pre-verify on device. |
| Cold-boot keychain unavailability (`kSecAttrAccessibleAfterFirstUnlock`) | Simulator keychain is always unlocked | **Simulated approximation** — 9.1.9 test uses a `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` attribute mismatch to force an unreadable keychain item; tests the code path without needing a real reboot. Real cold-boot behavior is deferred. |
| APNs delivery reliability under real network | `simctl push` is local-only, 100% delivery | **TestFlight telemetry** — 9.6 degrade-rate gate catches it in production. |
| Doze / battery optimization on Android | Emulator Doze is policy-stubbed | **Deferred** to future physical-device plan. Accepted: notification may be delayed; no data loss. |
| OEM FCM throttling | Emulator always uses stock GMS | **Deferred** to future physical-device plan (Samsung/Xiaomi/etc.). Accepted: notification may not arrive on throttled OEMs; degrades to in-app visibility on next app open. |
| Cross-process NSE race with real OS push daemon | Simulator spawns one NSE at a time | **CI gate** — 9.1.12 tests the extracted `NSEDedupeSentinel` class (pure logic, no OS spawning) exhaustively. Real cross-process race is deferred but the sentinel contract is proven. |
| Real push tap routing through SpringBoard / Launcher | Simulator launcher is simplified | **Simulator approximation** — simulator SpringBoard reproduces tap → app-open → `NotificationRouteTarget.fromRemoteMessageData` flow for the cases plan 73 changes (ciphertext payloads). Minor UI chrome differences not tested. |
| True terminated-app state (app swiped from switcher) | Simulator "terminate" via `xcrun simctl terminate` is close but not identical to user-swipe | **Simulator approximation** — 9.1.23 uses `xcrun simctl terminate` / `adb shell am force-stop` which exercise the same handler entry points; close enough for plan 73. |
| Production APNs certificate / FCM project configuration | Simulator uses dev-signed cert only | **TestFlight build smoke** before release. 9.1.16 entitlement test catches dev-vs-prod mismatches at build time. |

#### 9.4.1.4 CI wiring

- iOS Simulator tests: run via `xcodebuild test` on macOS CI runners
  using a headless simulator; part of the 10-minute PR budget
  (9.9). The full 16-scenario iOS Simulator suite must complete
  under 4 minutes — enforced by CI timing gate.
- Android Emulator tests: run via `flutter test integration_test`
  with a headless emulator on Linux CI runners. Firebase Test Lab
  is NOT used for PR gate (cost) — reserved for nightly
  cross-device runs.
- Fixture sharing: both simulator suites use the same
  `test/features/push/fixtures/*.json` set from 9.2, confirming
  cross-platform parity and avoiding fixture drift.
- Failure mode: if any simulator scenario fails, CI blocks merge
  with a pointer to the specific scenario ID (e.g., `S-iOS-5`)
  and the fixture file name.

#### 9.4.1.5 Scripts and automation

New files added to `scripts/`:

- `scripts/push_fixture_to_simulator.sh` — wrapper around
  `xcrun simctl push`; takes fixture-id, resolves to JSON path,
  looks up booted simulator device, delivers payload
- `scripts/push_fixture_to_android_emulator.sh` — adb-based
  equivalent; injects FCM data message via broadcast intent
- `scripts/smoke_test_push_decrypt_simulator.sh` — orchestrator;
  builds and installs the app when needed, boots both simulators and
  the Android emulator, verifies `com.mknoon.app` is installed,
  runs the scenario matrix, collects assertions, returns exit code
- extends the existing `reset_simulators.sh` (memory-noted pattern)
  so the same `--dart-define` auto-setup works with the
  push-decrypt scenarios without a separate build target

Current Session 8 local acceptance note:

- the repo now has fixture-injection wrappers and an app-installed local smoke
  runner that enumerates S-iOS-1..19 and S-And-1..19
- 2026-04-24 local evidence passed build/install/container/package preflight
  and non-dry-run smoke for all S-iOS-1..19 rows on iPhone 17 and iPhone 17 Pro
  plus all S-And-1..19 rows on Android `emulator-5554`
- Session 8 closure is recorded in
  `Test-Flight-Improv/73-on-device-push-decrypt-plan-session-breakdown.md`

#### 9.4.1.6 Phase-gate placement

- **Phase 3 exit** adds: iOS Simulator scenarios S-iOS-1 through
  S-iOS-19 pass on iPhone 17 + iPhone 17 Pro (incl. dual-simulator
  scenarios 17/18/19) AND Android Emulator scenarios S-And-1 through
  S-And-19 pass on Pixel 7 API 37 (where Phase 3 is Android, iOS
  scenarios can run in dual-tolerant mode pre-NSE)
- **Phase 4 exit** adds: iOS Simulator scenarios are the
  post-decrypt render contract for plan 73 — all 19 must pass;
  this IS the gate (no separate physical-device matrix runs
  afterward, per the 9.4 scope decision)

### 9.5 Smoke scripts

Add `scripts/smoke_test_push_decrypt.sh` modeled on
`smoke_test_friends.sh` (memory-noted pattern: auto-setup via
`--dart-define`, not separate integration-test builds):

- boots two simulators (A sender, B receiver) via `reset_simulators.sh`
- A sends a 1:1 text to B
- B is backgrounded; assert B's lock-screen notification body matches
  the plaintext
- captures relay access log; assert no plaintext substring present
- same sequence for a group message
- same sequence with a media-only message (typed descriptor render)
- failure injection: removes B's group key for one epoch, sends again,
  asserts B shows `"New message"` placeholder (graceful degrade path)

Exit code 0 only if every assertion passes. Runs in the
`Test-Flight-Improv/03-smoke-test-strategy.md` gate.

### 9.6 TestFlight degrade-rate telemetry gate

Per Phase 5:

- dashboard slice on `PUSH_NSE_DECRYPT_FAIL + PUSH_NSE_TIMEOUT +
  PUSH_ANDROID_DATA_DECRYPT_FAIL` divided by total push events
- per-platform, per-OS-major, per-OEM (Android) breakdown
- release-gate: a release is blocked if the 7-day trailing degrade rate
  exceeds 3 % on any platform/OEM slice with ≥ 500 samples
- explicit exemption list: slices with < 500 samples are information-only
- gate test: a deterministic telemetry-gate test feeds mixed events into
  the degrade-rate calculator and asserts `client_pre_decrypt`,
  `keychain_locked`, and `migration_pending` are excluded from the
  steady-state numerator/denominator, while real decrypt failures from
  updated clients still count.

### 9.7 Security-invariant tests (cross-cutting)

- `test/security/no_plaintext_leak_test.dart` — parameterized over every
  push-related code path (send, receive, decrypt, fallback, flow event);
  injects a unique plaintext canary; scans every log line, every
  emitted flow event, every stored DB row touched by the path, and
  every network write captured via an in-test HTTP recorder; fails if
  the canary appears anywhere off the expected decrypted-render path
- `test/security/ciphertext_length_leak_bounds_test.dart` — asserts
  that push ciphertext size for a range of plaintext lengths stays
  within AES-GCM block granularity (plaintext size + 28 bytes for
  nonce + tag, ± padding). Documents the known length-leak side channel
  called out in Section 6 and guards against accidentally widening it.
- `test/security/keychain_accessgroup_enforced_test.dart` — asserts
  every keychain write on iOS includes `kSecAttrAccessGroup`; fails if
  a new call site forgets it.
- `test/security/forbidden_field_classifier_test.dart` + Go + Swift
  counterparts — see 9.7.1 below. This is the enforceable contract
  for spec 74's four forbidden preview-derived categories across
  every push-visible surface.

### 9.7.1 Forbidden-field classifier — spec 74 contract enforcement

Spec 74 forbids four distinct categories of preview-derived metadata
in any relay/push-visible surface (Section 6 threat model). The
`no_plaintext_leak_test.dart` sweep (first bullet of 9.7) uses a
single message-body canary; that catches category 1 but is silent on
categories 2–4. A developer who accidentally sets
`data["sender_username"] = "alice"` in a new relay handler, or emits
`"Voice message"` in a metric label, would pass every current test
while violating the contract.

This section specifies a **unified classifier test** that injects
independent canaries for each forbidden category and asserts absence
across every push-visible surface, for every push kind. Run on every
PR; must never be skipped.

#### 9.7.1.1 Canary matrix

Four canary values, one per forbidden category, each a unique
high-entropy string so a single accidental substring match is
detectable:

| # | Category | Canary value (example) | Source of truth |
| --- | --- | --- | --- |
| 1 | Message text | `"CANARY_MSGTEXT_7f3a9c21_nightingale"` | plaintext `text` field |
| 2 | Sender display name / username | `"CANARY_USERNAME_b2e4d8f6_aardvark"` | `senderUsername` field |
| 3 | Group name | `"CANARY_GROUPNAME_1a5c7e93_obsidian"` | `group.name` field |
| 4 | Media descriptor copy | every one of `{"Photo", "Voice message", "Video", "File", "Media", "GIF"}` as a set — the test asserts none of these *literal strings* appear in any surface when the sent message has an attachment | `notificationBodyForMessage` output |

Canaries 1-3 are seeded at the sender side before the send flow runs.
Canary 4 is a reverse-assertion: rather than inject, the test runs
the send flow with an attachment of each `mediaType` and asserts the
corresponding static descriptor string does NOT appear in any
outbound surface.

#### 9.7.1.2 Surface matrix

Five push-visible surfaces. Each canary must be absent from each:

| # | Surface | Capture mechanism |
| --- | --- | --- |
| 1 | APNs payload (outbound) | in-test APNs client records every push before it leaves the relay |
| 2 | FCM payload (outbound) | in-test FCM client records every push before it leaves the relay |
| 3 | Logs | `os.Stdout` + `log.Logger` capture during the test; includes structured logs emitted by the relay or the Go bridge |
| 4 | Metrics | Prometheus registry snapshot after the test run — every metric name, help, label key, and label value is scanned |
| 5 | Flow events | `emitFlowEvent` test listener captures every event body and detail map |

#### 9.7.1.3 Kind matrix

The classifier runs for every push kind the plan changes or
preserves, because each kind has a distinct code path that could
leak:

- `new_message` (1:1 text)
- `new_message` (1:1 media, each `mediaType`)
- `group_message` (text)
- `group_message` (media, each `mediaType`)
- `reaction`
- `edit`
- `delete_for_everyone`
- `group_dissolved`
- `contact_request` (unchanged-contract baseline — asserts that
  canaries 1-4 are absent EXCEPT the relay-authored static strings
  `"New Contact Request"` / `"Open Mknoon to respond"`, which are
  NOT part of the forbidden categories)
- `group_invite` (same unchanged-contract logic)
- `introduction` (same)

#### 9.7.1.4 Positive assertions (allowed fields present)

A greedy "strip everything from the outbound payload" implementation
could pass all 20 absence assertions while breaking routing. The
classifier therefore also asserts the **allowed** set IS present
where expected:

| Allowed field | Expected in |
| --- | --- |
| `ciphertext` (non-empty) | APNs `data.ciphertext` + FCM `data.ciphertext` for message kinds |
| `nonce` (non-empty) | same |
| `messageId` (non-empty, matches expected) | APNs + FCM `data` |
| `senderPeerId` (opaque id, NOT username) | APNs + FCM `data` for message kinds |
| `groupId` (opaque id, NOT group name) | APNs + FCM `data` for group-kind |
| `keyEpoch` (integer) | APNs + FCM `data` for group-kind |
| `kind` (enum string) | APNs + FCM `data` |
| `mutable-content: 1` | APNs only, message kinds |
| static title/body strings | APNs + FCM for unchanged-contract kinds only |

If any allowed field is missing, the test fails — catches over-eager
stripping.

#### 9.7.1.5 Implementation

**Go classifier** — `go-relay-server/forbidden_field_classifier_test.go`:

- parameterized table test; outer loop = push kind, inner loops = canary × surface
- shared fixture builder `buildCanaryMessage(kind, mediaType)` that
  assembles an inbox payload with all canaries seeded at the right
  fields
- helper `scanSurfaceForCanaries(surface, canaries) error` that
  flattens any map/struct to a searchable string and asserts no
  canary substring match
- test helper for metrics: `promhttp` scrape → parse → sweep
- runs against the production `buildGroupPushMessage` and 1:1
  sibling — no stub

**Dart classifier** —
`test/security/forbidden_field_classifier_test.dart`:

- asserts the **client-side** surface: the inbox payload the client
  sends to the relay contains allowed fields only, none of the four
  canaries anywhere
- parameterized over all send use cases: `send_chat_message_use_case`,
  `send_group_message_use_case`, `send_group_reaction_use_case`,
  `edit_message_use_case`, `delete_for_everyone_use_case`,
  `dissolve_group_use_case`
- also asserts flow events emitted by the send path contain no
  canaries

**Swift classifier** —
`ios/RunnerTests/ForbiddenFieldClassifierTests.swift`:

- asserts NSE-emitted flow events and logs (OSLog, NSLog) contain
  no canaries when processing a decrypted push that contains all four
  canaries as plaintext
- this is the safety net: if the NSE accidentally logs the decrypted
  body or sender username (e.g. in a debug breadcrumb), it fails CI
  before the symbol reaches the App Store

#### 9.7.1.6 CI integration

- all three classifiers run on every PR — no nightly-only exception
- they count against the 10-minute PR budget (9.9); if combined
  runtime exceeds 45 seconds, split into per-surface suites
- drift protection: the list of forbidden categories is defined as
  a shared constant (`go-relay-server/contract/forbidden_categories.go`
  + Dart + Swift mirrors). The CI "fixture drift check" (9.2) also
  diffs the three mirror definitions; any divergence fails.

#### 9.7.1.7 Phase-gate placement

Every phase that touches a push-visible surface must run the
classifier. Updated in 9.11:

- **Phase 1** — relay changes outbound surfaces; classifier is a
  blocking gate
- **Phase 2** — sender changes inbox payload (source-side of what
  the relay will emit); classifier is blocking
- **Phase 3** — Android decrypt path emits new flow events /
  metrics; classifier is blocking for the Dart + the new event surface
- **Phase 4** — NSE emits new flow events / logs; classifier is
  blocking for Swift + NSE
- **Phase 5** — new telemetry metrics; classifier re-runs to ensure
  the new metric labels do not include any forbidden canary

### 9.8 Rollout ordering constraints

**Product decision (2026-04-24):** privacy takes precedence over
old-build notification UX. The relay MUST stop emitting plaintext
group previews for all clients as soon as Phase 1 is ready. Old
builds that cannot decrypt ciphertext acceptably degrade to the
static `"New message"` placeholder — this is an explicit, accepted
trade, not a regression to prevent.

Consequences of this decision:

- **Phase 1 (relay ciphertext-only) can ship independently and
  immediately** — no need to wait for any percentage of client
  adoption. Old clients in the field that receive ciphertext-only
  pushes fall through to the static fallback, which is the intended
  behavior.
- The only ordering constraint that remains is the one inside the
  client: **Phase 4 merge is blocked until the keychain migration in
  9.1.7 passes on a cold-boot device (see 9.1.9)** — this is purely
  to avoid shipping an NSE that cannot reach its keys on first-run.
- Phase 2 (sender stops attaching `pushBody`) can ship in the same
  release bundle as Phase 3 and Phase 4, or independently — the
  relay ignores `pushBody` after Phase 1 regardless.
- Client-side dual-tolerance tests in 9.1.8 remain valuable as
  regression guards against transitional relay states (partial
  rollout across relay instances, canary periods), but are not a
  correctness prerequisite anymore.

What this means for old users during the rollout window:

- **1:1 pushes:** no change visible — old relay already emits
  `"You have a new message"` for 1:1, new relay emits the same
  static text. Zero regression for old clients.
- **Group pushes:** old clients lose the rich preview (`"alice: <text>"`)
  the moment Phase 1 flips, and see `"New message"` instead until
  they update. This is the accepted trade.
- **In-app preview (when the app is foregrounded):** unchanged.
  `notificationBodyForMessage` and `maybeShowNotification` still
  render the full preview on-device because that path already has
  plaintext access post-decrypt. Old clients lose the lock-screen
  preview, not the in-app experience.

### 9.8.1 Old-build degradation messaging

When the relay flips, old builds will show `"New message"` for group
pushes. To avoid user confusion and pressure update adoption, add to
Phase 1 rollout playbook:

- an in-app banner for users on builds below the Phase 3/4 version
  floor: `"Update to see message previews on your lock screen."`
  — backed by the existing minimum-version check infrastructure (if
  present; confirm during Phase 1 planning)
- a TestFlight release note explaining the change
- monitoring: track the cohort of users on old builds that are still
  receiving pushes; their degrade rate will be 100 % by design and
  must NOT be counted in the `push_preview_degrade_rate_gate`
  (9.10) — the gate's `excluded_reasons` must add
  `client_pre_decrypt` to the exclusion list, and the client must
  NOT emit that reason (the relay tags it on the outbound based on
  the client's last-seen version)

### 9.1.8 Client dual-tolerance during rollout (Dart)

Add to
`test/features/push/application/background_message_handler_test.dart`:

- `handles legacy plaintext push correctly during rollout window`
  — feed a data payload with `pushBody: "alice: hello"` and no
  `ciphertext`; assert the old fallback path renders the plaintext
  preview; assert no crash
- `handles new-format ciphertext push correctly during rollout window`
  — feed a data payload with `ciphertext` and no `pushBody`; assert
  the new decrypt path renders the decrypted preview
- `does not double-notify when both legacy and new fields are present`
  — feed a payload carrying both `pushBody` AND `ciphertext` (can
  happen during transitional relay build); assert exactly one
  notification is shown; assert the new-format path wins (ciphertext
  decrypted, plaintext `pushBody` ignored and not rendered)
- `unchanged Android handler does not crash on ciphertext-only payload
  before Phase 3 ships`
  — regression guard for R-01: run this test on Phase 1 merge;
  asserts the pre-Phase-3 handler degrades gracefully to the static
  fallback without raising, without leaking, without producing two
  notifications

### 9.1.9 Cold-boot keychain availability (iOS)

Add `ios/RunnerTests/NSEColdBootTests.swift`:

- `test_coldBoot_deviceLocked_NSEDegradesGracefully`
  — iOS keychain items use `kSecAttrAccessibleAfterFirstUnlock`. After
  a reboot, before the user unlocks the device for the first time, the
  keychain is not readable even by an NSE in the correct access group.
  Simulate by setting the keychain item with
  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` attribute mismatch;
  assert NSE returns the placeholder body and emits
  `PUSH_NSE_DECRYPT_FAIL` with `reason: "keychain_locked"`
- `test_afterFirstUnlock_keychainAccessible_NSEDecrypts`
  — same setup but after unlock; asserts decrypt succeeds
- documents the expected behavior: **first push after cold boot before
  unlock will always show the placeholder**; this is not a bug

### 9.1.10 iOS notification threading (grouping) — R-04

Add to `ios/RunnerTests/NotificationServiceTests.swift`:

- `test_oneToOne_setsThreadIdentifierToContactPeerId`
  — assert `bestAttemptContent.threadIdentifier` equals the sender
  peer ID from the decrypted payload
- `test_group_setsThreadIdentifierToGroupId`
  — assert `threadIdentifier` equals `groupId` for a group push
- `test_threadIdentifier_matchesInAppLocalNotifications`
  — cross-check that the same thread identifier convention is used by
  `FlutterNotificationService` in-app (port the matching constant
  between Dart and Swift as a shared value; document in
  `lib/core/notifications/notification_thread_identifier.dart` + a
  corresponding Swift constant, both pointing at the same derivation
  rule)

Android equivalent in
`test/features/push/application/background_message_handler_test.dart`:

- `notification group key matches in-app conversation grouping`
  — assert the `AndroidNotificationDetails.groupKey` produced by the
  rewritten fallback matches what the main-app in-app path uses for
  the same conversation

### 9.1.11 Fixture generator determinism — R-02

Augment Section 9.2:

- the Go fixture generator MUST use a test-only deterministic nonce
  source (a fixed 12-byte value per fixture case), NOT the production
  `crypto/rand` reader
- implementation: add `go-mknoon/crypto/testhelpers/deterministic_nonce.go`
  exposing `NewDeterministicNoncer(seed []byte) NonceSource` that is
  NEVER imported by production `bridge/` code (enforced by a
  `go vet`-style custom linter or a grep gate in CI:
  `grep -rn "deterministic_nonce" go-mknoon/bridge/` must return zero
  matches)
- add `TestFixtureGeneratorIsIdempotent` in
  `go-relay-server/testfixtures/push_crypto_fixtures_test.go`:
  runs the generator twice in one process and one subprocess, asserts
  byte-equal outputs in both cases
- add `TestProductionCryptoPathUsesCryptoRand` in
  `go-mknoon/crypto/crypto_test.go`: uses a type assertion / interface
  check to assert that the production AES-GCM seal path pulls from
  `crypto/rand.Reader`, not from any test injection seam

### 9.1.12 NSE concurrent-write race on dedupe sentinel — R-07

The NSE dedupe sentinel lives in the shared App Group container. Two
NSE processes CAN run simultaneously (iOS invokes a fresh NSE per
push, and if two pushes arrive close together, two instances
concurrently access the sentinel file). The existing Dart
`RecentRemoteNotificationGate._writeEntries` uses unlocked
`file.writeAsString` — do NOT copy that pattern.

Implementation requirement (Phase 4):

- sentinel writes MUST use an atomic write: write to a temp file in
  the same directory, then `rename()` over the final path
- sentinel reads MUST tolerate a missing or partial file (treat as
  "no sentinel") rather than throwing
- the sentinel format SHOULD be append-only with a TTL-based compaction
  so concurrent appenders cannot corrupt shared state (compared to an
  overwrite of a JSON blob)
- **the sentinel is extracted from `NotificationService` into a pure
  Swift class `NSEDedupeSentinel` that takes a filesystem path and
  exposes `markShown(messageId:) -> Bool` (returns true iff this call
  won the race)** — this separation lets CI test the race without
  needing App Group entitlements, which are unavailable on hosted CI
  runners without a signing identity (Q-02 fix)

Tests in `ios/RunnerTests/NSEDedupeSentinelTests.swift`:

- `test_concurrentWrites_sentinelStaysValidJSON`
  — spawn 32 parallel writers via `DispatchQueue.concurrentPerform`
  against a temp-directory path (NOT the App Group path); assert the
  file is valid JSON after all complete
- `test_concurrentWrites_sameMessageId_exactlyOneWinner`
  — 16 parallel writers with same messageId; exactly one call returns
  `true`, all others return `false`
- `test_concurrentWrites_distinctMessageIds_allSucceed`
  — 16 parallel writers with 16 distinct ids; all return `true`;
  sentinel contains all 16 after
- `test_sentinelFileCorruption_isToleratedAsNoSentinel`
  — pre-corrupt the file with random bytes; assert the sentinel
  treats it as empty and proceeds
- `test_sentinelTTL_expiresOldEntries`
  — insert an entry with a backdated timestamp past TTL; insert a
  fresh entry; assert the old one is compacted out

Cross-process NSE race (actual two-NSE-processes scenario): NOT
in plan 73 scope. Simulator runs one NSE process at a time per
simulator. The logic race (sentinel read/write contention) IS
fully covered by the extracted-sentinel tests above against a
real filesystem; what simulators cannot exercise is two OS-spawned
NSE processes racing on the shared App Group container. Plan 73
accepts this gap; future physical-device plan can add a
release-checklist verification step (send two pushes within 100 ms
to the same physical device, observe exactly one notification is
shown). Plan 73 mitigation: if the `NSEDedupeSentinel` contract
holds against concurrent `DispatchQueue` writers in CI, the
cross-process behavior follows — the sentinel is filesystem-level,
not process-level.

### 9.1.18 Tampered Ed25519 signature (NSE + Android) — Q-05

The v3 group envelope is encrypted AND signed. AES-GCM MAC failure
is already tested (`test_corruptCiphertext_leavesPlaceholderBody`),
but that covers the ciphertext tamper case. A signature-only tamper —
an attacker modifies the Ed25519 signature bytes while leaving
ciphertext + nonce intact — can pass AES-GCM decryption and produce
a plaintext that looks valid, but must NOT be surfaced to the user as
an authenticated message.

Tests in `ios/RunnerTests/NotificationServiceTests.swift`:

- `test_tamperedGroupEnvelopeSignature_leavesPlaceholderBody`
  — fixture: valid v3 envelope; mutate one byte of the signature;
  assert NSE returns the placeholder; assert flow event
  `PUSH_NSE_DECRYPT_FAIL { reason: "signature_invalid" }`
- `test_missingEnvelopeSignature_leavesPlaceholderBody`
  — fixture: valid v3 envelope with signature field removed; same
  expected behavior

Android equivalents in
`test/features/push/application/background_message_handler_test.dart`:

- `tampered signature in group envelope is rejected`
- `missing signature in group envelope is rejected`

Add to Phase 4 exit criteria in 9.11.

### 9.1.19 Foreground-drain + active-conversation ciphertext no-duplicate (plan 71 integration) — Q-04

Plan 71's foreground drain gate and the existing
`maybeShowNotification` active-conversation suppression both assume
plaintext push payloads. Ciphertext pushes must pass the same
no-duplicate contract in BOTH directions:

- **Foreground drain path:** push arrives while app is backgrounded
  → NSE / Android handler decrypts and shows a lock-screen
  notification → user foregrounds the app → foreground drain
  recognizes the `messageId` is already shown (via
  `recentRemoteNotificationGate`) and suppresses the duplicate
  in-app local notification.
- **Active-conversation path:** user is already viewing the
  relevant conversation when the push arrives → the
  `ActiveConversationTracker` check at
  `show_notification_use_case.dart` (`isViewing(contactPeerId)` /
  the group equivalent) must suppress the in-app local
  notification that the Phase 3 decrypt path would otherwise emit.

Both paths apply to 1:1 and group. Prior draft named only the group
test file; this draft adds a 1:1 counterpart so each combination
(foreground-drain × 1:1, foreground-drain × group,
active-conversation × 1:1, active-conversation × group) has a named
assertion.

#### 9.1.19.1 Group integration tests

In `integration_test/foreground_group_push_drain_test.dart`:

- `ciphertext_group_push_followed_by_foreground_drain_shows_no_duplicate`
  — ciphertext push arrives backgrounded → Dart decrypt path runs
  (integration tests run in-Dart, simulating both NSE and Android
  handler behavior through `background_message_handler`) → app
  foregrounds → `recentRemoteNotificationGate` recognizes the
  messageId → no second local notification
- `ciphertext_group_push_while_foregrounded_decrypts_without_duplicate`
  — regression guard for the FCM `onMessage` path after Phase 3 —
  the decrypt happens once, the notification is shown once
- `ciphertext_group_push_while_viewing_target_group_is_suppressed_post_decrypt`
  — user is in the target group's conversation view; ciphertext
  push arrives; decrypt succeeds; `ActiveConversationTracker` reports
  the user IS viewing the group; assert NO local notification is
  shown (the active-conversation suppression gate fires AFTER
  decrypt, not before — this is the point where the existing
  suppression contract meets the new decrypt path)

#### 9.1.19.2 1:1 integration tests

Add new file
`integration_test/foreground_onetoone_push_drain_test.dart` (mirror
of the group file, same shape):

- `ciphertext_onetoone_push_followed_by_foreground_drain_shows_no_duplicate`
  — same scenario as the group version but on a 1:1 conversation;
  backgrounded receive → decrypt → foreground → no duplicate
- `ciphertext_onetoone_push_while_foregrounded_decrypts_without_duplicate`
  — FCM `onMessage` equivalent for 1:1
- `ciphertext_onetoone_push_while_viewing_sender_conversation_is_suppressed_post_decrypt`
  — user is in Alice's 1:1 conversation; ciphertext push from Alice
  arrives; decrypt succeeds; `ActiveConversationTracker.isViewing(alicePeerId)`
  returns true; assert NO local notification is shown. This is the
  spec 74 "Active conversation" edge case (spec line 77) explicitly
  named for 1:1, not just for groups.
- `ciphertext_onetoone_push_while_viewing_DIFFERENT_conversation_is_shown`
  — negative guard: user is in Bob's conversation; push arrives
  from Alice; notification IS shown (suppression is scoped to the
  sender peer ID, not globally gated by any active conversation)

#### 9.1.19.3 Unit coverage for the suppression gate

The integration tests above hit the full pipeline. Add unit
coverage where the suppression decision actually lives:

`test/features/push/application/show_notification_use_case_test.dart`
— extend with:

- `ciphertext-decrypted notification suppresses when viewing 1:1 sender`
  — feeds a post-decrypt plaintext through `maybeShowNotification`
  with `conversationTracker.isViewing(contactPeerId) == true` and
  `lifecycleState == resumed`; asserts no notification call
- `ciphertext-decrypted notification suppresses when viewing group`
  — group equivalent
- `ciphertext-decrypted notification fires when viewing different
  conversation`
  — negative guard

These are the tightest regression guards — if a future change to
`maybeShowNotification` breaks active-conversation suppression, the
integration tests will catch it but these fail first and point
directly at the broken unit.

#### 9.1.19.4 Phase-gate placement

Add to Phase 3 exit criteria in 9.11 — both the group and 1:1
integration files, plus the unit coverage.

### 9.1.13 Swift-side plaintext leak scanner — R-05

Add `ios/RunnerTests/SwiftLeakScannerTests.swift`:

- `test_decryptedPlaintext_neverAppearsInSwiftLogs`
  — install a log capture delegate for OSLog and NSLog during a
  decrypt-and-render call; assert the decrypted plaintext canary
  string does not appear in any captured line
- `test_decryptedPlaintext_neverAppearsInFlowEventsEmittedFromNSE`
  — install a flow-event test listener; assert no emitted event body
  contains the plaintext canary
- these tests must run as part of `xcodebuild test` on every PR;
  no nightly-only exception

Ownership of creation: **Phase 2** owns the `test/security/` directory
in Dart AND the Swift `SwiftLeakScannerTests.swift` file creation.
Phase 2 does not ship without both in place. Added to 9.8 checklist.

### 9.1.14 Mute/DND behavior (design decision + test) — R-03 (downgraded from cycle 2)

**Design decision:** the NSE and the Android background handler rewrite
the notification body unconditionally, regardless of in-app or
OS-layer mute state. Mute suppression happens at the OS layer via
iOS `UNNotificationCategory` / Focus filters / per-conversation
notification settings, and on Android via per-conversation
`NotificationChannel` importance. The NSE does NOT consult the in-app
mute table. Rationale: the NSE has no access to the SQLCipher DB
where in-app mute state lives; sharing that state would widen the
App Group footprint for marginal gain.

Tests that encode this decision:

- `ios/RunnerTests/NotificationServiceTests.swift` —
  `test_muteState_notConsultedByNSE`
  — even if a muted-conversations list were present in the shared
  container, the NSE would ignore it; this test asserts the NSE code
  path contains no read of any mute-state key (static analysis /
  grep-based assertion is acceptable here)
- `test/features/conversation/application/mute_behavior_test.dart` —
  `muting a conversation sets iOS notification category to muted`
  — asserts the main app correctly configures the OS-layer setting
  that will actually cause suppression

Note in `52-notification-journey-test-matrix.md`: add a row documenting
that muted conversations will be DECRYPTED by the NSE but SUPPRESSED
by the OS; battery and network-transfer cost of the decrypt is paid
even for muted conversations. Acceptable trade.

### 9.1.15 Push-permission-denied path (QA gap this cycle)

Add `test/features/push/permission_denied_test.dart`:

- `permission denied user does not invoke NSE / background handler`
  — assert APNs registration is skipped, no push token sent to the
  relay, degrade counters do not log spurious failures for this user
- `permission granted then revoked handles gracefully`
  — asserts the app detects revocation and stops expecting pushes

### 9.1.16 APNs environment build-config (QA gap this cycle)

Add `ios/RunnerTests/NSEEntitlementsTests.swift`:

- `test_NSEEntitlements_matchRunnerEnvironment`
  — reads the compiled NSE target's `aps-environment` value and
  asserts it matches `Runner`'s value (`production` for release
  builds, `development` for debug). A mismatch causes silent APNs
  failure in TestFlight; catching this at CI prevents a wasted
  release cycle.
- `test_NSEEntitlements_accessGroupMatchesMainApp`
  — assert the NSE and the main app are members of the same App
  Group and keychain access group

### 9.1.17 Scope guard: multi-device — R-08

Multi-device push receipt (same user signed in on two devices, both
decrypt independently) is inherited from plan 65
(`65-same-user-multi-device-group-convergence.md`) and is explicitly
NOT a testing scope of plan 73. The expected behavior — both devices
receive the push, both decrypt independently, both show the
notification — emerges naturally from plan 73's design because the
NSE sentinel is per-device. No cross-device dedup is attempted by
this plan. Plan 65 owns any future cross-device deduplication work.

Add one smoke-script assertion in 9.5 confirming the naturally-emerging
behavior: two simulators logged in as the same user, one sender
sending to them, both simulators show their own lock-screen
notification. This is a regression guard, not a feature test.

### 9.9 CI runtime budget (R-09)

The full Section 9.3 gate runs on every PR. Budget:

| Test group | Target (PR) | Nightly-only override |
| --- | --- | --- |
| `flutter test` (Dart unit + integration) | < 4 min | — |
| `go test ./...` | < 2 min | — |
| `xcodebuild test -scheme RunnerTests` (Swift unit, incl. NSE tests) | < 4 min on M-series runners | yes, if runner pool starves |
| Fixture drift check | < 30 s | — |
| NSE bundle-size check (`xcodebuild archive`) | < 3 min | yes, nightly + release builds only |
| No-plaintext gate (Dart + Swift) | subset of above | — |
| Simulator smoke (9.5 script — iPhone 17 + iPhone 17 Pro + Pixel 7 API 37) | < 8 min wall-clock | runs on PR for Phase 3/4 merges, nightly otherwise |
| Simulator matrix (9.4.1 full 19+19 scenarios) | nightly | always |

**Total PR blocking budget: 10 minutes on M-series CI runners.** If the
gate exceeds budget on three consecutive green runs, an owner must
either optimize or promote slow tests to nightly-only.

### 9.10 Degrade-rate gate soak window — R-06

Augment Section 9.6:

- the 3 % degrade-rate gate is **advisory-only** for the first 72
  hours after a new build reaches ≥ 100 unique devices, then becomes
  blocking
- the migration-period degrade is expected to spike on day 1 (cold-boot
  keychain + first-run migration); telemetry slices labeled
  `migration_period` are excluded from the steady-state counter
- label migration-period events by emitting
  `PUSH_NSE_DECRYPT_FAIL { reason: "keychain_locked" | "migration_pending" }`
  and counting them separately
- update `test-gate-definitions.md` with:
  ```
  push_preview_degrade_rate_gate:
    threshold_percent: 3
    window_days: 7
    min_samples: 500
    soak_window_hours: 72
    excluded_reasons: [client_pre_decrypt, keychain_locked, migration_pending]
  ```

### 9.10.5 Push-data schema versioning — Q-07

**Design decision:** the ciphertext push `data` block intentionally
does NOT carry a `schemaVersion` field. Schema evolution is handled
implicitly via two existing fields:

- `kind` distinguishes payload types (`new_message`, `group_message`,
  `reaction`, `edit`, `delete_for_everyone`) and gates which parser
  runs
- `keyEpoch` gates crypto algorithm — a future ML-KEM-1024 rollout
  would bump the epoch and the client selects the decrypt path by
  (groupId, keyEpoch) key lookup

Rationale: a version field would not be load-bearing until an actual
schema break occurs; adding it prophylactically is YAGNI. When a
break is actually needed (e.g., if we add `quotedMessageId` resolution
to the NSE), a new `kind` value handles it; if crypto changes, a new
`keyEpoch` handles it.

Add to `TestBuildNewMessagePush_EmitsMutableContentAndCiphertextOnly`:
an assertion that no `schemaVersion` / `version` / `v` key is present
in the `data` block. This freezes the decision as a contract.

Future-compatibility note in Section 6 (threat model): if a future
plan needs an explicit version field, that plan authors both the
field AND a migration test matrix for old-client-new-field-absent
and new-client-old-field-absent cases.

### 9.10.6 Test-gate-definitions.md deliverables — Q-01, Q-03, Q-06

The plan adds new Dart test files that must be classified in
`test-gate-definitions.md` or the project's `completeness-check`
script will fail on first land. The following PRs against
`test-gate-definitions.md` are named deliverables:

**Phase 2 deliverable (before merge):** add to the Optional/Manual
Direct Suites section:
- `test/security/no_plaintext_leak_test.dart` (security invariant)
- `test/security/ciphertext_length_leak_bounds_test.dart`
- `test/security/keychain_accessgroup_enforced_test.dart`

**Phase 3 deliverable (before merge):**
- `test/features/push/cross_platform_parity_test.dart` → Optional
  Direct Suite (runs on PR, independent gate)
- `test/features/push/permission_denied_test.dart` → implicit
  feature-local bucket (auto-classified, no action needed unless
  the script flags it)
- `test/features/push/fixtures/README.md` → not a test file; confirm
  the completeness-check script only scans `*_test.dart`

**Phase 3 deliverable, nightly-only:**
- `test/features/push/performance/background_decrypt_benchmark_test.dart`
  → Nightly Pool, marked with `@Skip` annotation in default
  `flutter test` runs so the benchmark cannot bleed into the PR
  timing budget

**Phase 4 deliverable:**
- `ios/RunnerTests/NotificationServiceTests.swift` → Swift tests are
  gated by `xcodebuild test -scheme RunnerTests`, not the Dart
  completeness check, but must be added to the release-checklist
  Swift test list
- all other `ios/RunnerTests/*.swift` files named in 9.1 are handled
  the same way

**Phase 5 deliverable (the critical one):** a PR to
`test-gate-definitions.md` adds a new `Runtime Telemetry Gates`
section and the block:

```yaml
push_preview_degrade_rate_gate:
  source: production telemetry (flow events)
  window_days: 7
  min_samples: 500
  threshold_percent: 3
  soak_window_hours: 72
  excluded_reasons: [client_pre_decrypt, keychain_locked, migration_pending]
  per_slice: [platform, os_major, oem]
  blocks_release: true_after_soak
  owner: <named engineer>
```

Phase 5 does not exit until this PR merges and the
`completeness-check` script remains green.
The same Phase 5 PR must include a gate test proving
`client_pre_decrypt` events are excluded from the steady-state
degrade-rate calculation and cannot be emitted by updated clients as a
generic failure reason.

### 9.1.20 Muted-group regression — spec 74 line 76

**Spec 74 requirement:** "A muted group does not start showing preview
notifications just because the payload shape changes."

Section 9.1.14 documents the design decision that mute is enforced at
the OS layer, not by the NSE. This section adds the behavioral
regression guard that proves muted groups do not start showing
content on the lock screen after the change.

Tests:

- `integration_test/muted_group_notification_behavior_test.dart` —
  `muted_group_before_and_after_plan_73_shows_no_additional_content_on_lock_screen`
  — seed a group and mute it via the plan 61 mute path; record the
  lock-screen notification behavior on an old build (baseline); upgrade
  to the new build; send the same message; assert the lock-screen
  behavior is identical or more private (never more content). If the
  baseline was "suppressed entirely," the new behavior must also be
  "suppressed entirely." If the baseline was "visible with generic
  body," the new behavior must be "visible with generic body" — NOT
  "visible with decrypted preview."
- `ios/RunnerTests/NotificationServiceTests.swift` —
  `test_mutedGroup_NSE_doesNotOverrideOSSuppression`
  — verify the NSE's `bestAttemptContent` write does not bypass
  iOS Focus / per-conversation notification settings (in practice:
  the NSE always rewrites `bestAttemptContent`, and the OS decides
  display based on category/interruption level; this test asserts the
  NSE never sets `interruptionLevel = .timeSensitive` or similar
  overrides that could escape OS-layer mute)

Add to Phase 4 exit criteria in 9.11.

### 9.1.21 Preview-length bound — spec 74 line 78

**Spec 74 requirement:** "Notification preview content is bounded to
a user-readable preview and does not expose more message content than
the product intends."

Plan 73 currently reuses `notificationBodyForMessage` verbatim with no
length cap. The function returns the full trimmed text. A 5 KB
plaintext would render 5 KB of text on the lock screen (up to the
APNs ~4 KB payload limit), which is neither user-readable nor
product-intended.

**Design decision:** cap preview text at **140 Unicode graphemes**,
append `"…"` (horizontal ellipsis, U+2026) when truncated. 140 is
the historical SMS / Twitter-era bound that is known readable on
every lock-screen width and is well below the APNs payload ceiling.
Apply the cap AFTER decryption, BEFORE assigning to
`bestAttemptContent.body` (iOS) or the local notification body
(Android). Apply symmetrically in the Swift port and the Dart path.

**Scope guard (resolves contradiction with Section 3):** the cap is
a *push-preview* concern, not a change to the shared formatter. The
Section 3 non-goal — `notificationBodyForMessage` and
`maybeShowNotification` stay as-is — is preserved. Rather than
modifying the existing function, introduce a new thin wrapper used
only by the push decrypt paths:

```dart
// lib/features/push/application/push_preview_body.dart
String pushPreviewBody(String text, List<MediaAttachment> media) {
  final raw = notificationBodyForMessage(text, media);
  return capPreviewGraphemes(raw, max: 140);
}
```

Callers:

- USES the wrapped, capped version: `background_message_handler.dart`
  (Phase 3 decrypt path), Swift NSE `pushPreviewBody` (Phase 4 port)
- CONTINUES using the uncapped `notificationBodyForMessage` direct:
  `chat_message_listener.dart:454` (foreground 1:1 in-app OS notification),
  `group_message_listener.dart:264-266` (foreground group in-app OS
  notification). These are in-app banner and foreground OS notification
  flows; per Section 3 scope they are not touched by this plan.

Tests — Dart:

- `test/features/push/application/push_preview_body_test.dart`:
  - `caps preview at 140 graphemes with ellipsis when plaintext is longer`
  - `does not cap when plaintext is 140 graphemes or shorter`
  - `grapheme cap is unicode-aware for emoji / ZWJ sequences / RTL`
    (e.g., a 10-family-emoji string is 10 graphemes, not 40 code
    units; a Hebrew message preserves right-to-left rendering)
  - `cap preserves caption-first rule — text takes priority over media descriptor`
  - `delegates formatting to notificationBodyForMessage` — assert the
    wrapper is the only layer that caps; the underlying formatter is
    called with the raw text and returns the uncapped result
- `test/features/push/application/show_notification_use_case_test.dart`
  (regression guard for the scope guard):
  - `notificationBodyForMessage does NOT cap at 140 graphemes`
    — explicit assertion that the shared formatter's behavior is
    unchanged after Phase 3 lands, so in-app foreground callers
    continue to receive the full text

Tests — Swift:

- `ios/RunnerTests/PushPreviewBodyTests.swift`:
  - `test_capsPreviewAt140Graphemes`
  - `test_capPreservesGraphemeClusterBoundaries` (no mid-emoji truncation)
  - parity test against the Dart `pushPreviewBody` behavior using the
    existing fixture pipeline (9.1.5)

Add to Phase 3 exit (Dart) and Phase 4 exit (Swift) in 9.11.

### 9.1.22 Unknown envelope kind — spec 74 line 79

**Spec 74 requirement:** "No malformed payload exposes plaintext
message content through relay-visible fields."

Plan 73 tests the corrupt-ciphertext and tampered-signature cases
(9.1.4, 9.1.18). It does not test the forward-compatibility case
where the client receives an envelope `kind` it does not recognize
(e.g., a future `kind: "reaction_v2"` or `kind: "system_event"`).

Tests:

- `ios/RunnerTests/NotificationServiceTests.swift` —
  `test_unknownEnvelopeKind_leavesPlaceholderBody_noCrash`
  — feed a push with `data.kind = "unknown_future_type_v9"`,
  otherwise valid ciphertext+nonce; assert NSE returns the
  placeholder `"New message"`, emits
  `PUSH_NSE_DECRYPT_FAIL { reason: "unknown_kind" }`, does not crash,
  does not emit any decrypted plaintext in logs or flow events
- `test/features/push/application/background_message_handler_test.dart` —
  `unknown envelope kind falls back without crash or plaintext leak`
  — same case on Android
- `go-relay-server/inbox_test.go` —
  `TestBuildPush_UnknownEnvelopeKind_StillShipsCiphertextOnly`
  — relay with an unknown `kind` should still build a ciphertext-only
  push (NEVER fall back to shipping legacy plaintext because it didn't
  know what to do)

Add to Phase 3 and Phase 4 exits in 9.11.

### 9.1.23 Terminated-app-state device coverage — spec 74 line 70

**Spec 74 requirement:** "Simulator evidence that background or
**terminated** notification delivery can show either a message-specific
recipient-visible preview or the generic fallback."

Plan 73's 9.4 device matrix and 9.5 smoke script cover "backgrounded"
but do not explicitly split out "terminated" (app swiped away /
force-quit). iOS NSE runs in both states; Android data-only FCM
delivery in a terminated-app state is distinct and more fragile
(Doze + OEM throttling hit harder).

Add to the 9.4 simulator matrix: every scenario row in 9.4.1.1 and
9.4.1.2 acquires a `{terminated: yes/no}` column. Mandatory
simulator runs:

| Simulator | OS | State | What to verify |
| --- | --- | --- | --- |
| iPhone 17 | iOS latest | terminated | NSE still wakes (via `simctl push` post-`simctl terminate`), decrypts, renders |
| iPhone 17 Pro | iOS latest | terminated | same on the secondary simulator — catches any simulator-specific quirk between the two |
| Pixel 7 API 37 | Android | terminated | data-only FCM wakes the Flutter background isolate from a force-stopped app state |

**Deferred to future physical-device plan:** OEM-specific
terminated-app behavior (Samsung/Xiaomi/Huawei) — emulator cannot
reproduce the OEM-level "force stop"-to-push-delivery rules.
TestFlight telemetry (9.6) is the production backstop.

Add to 9.5 smoke script: after each backgrounded scenario, repeat
with the receiver app force-terminated via
`xcrun simctl terminate <device-id> <bundle-id>` (iOS) or
`adb shell am force-stop <package>` (Android), and assert delivery
+ render outcome. Record delivery latency separately for
backgrounded vs terminated — Android terminated-state latency > 30 s
on the emulator is a finding worth tracking in telemetry even though
the "real" Android terminated-state throttling only reproduces on
physical OEM devices.

Update Phase 3 and Phase 4 exit criteria in 9.11 to reference the
terminated-state rows.

### 9.1.24 Group fanout regression guard — spec 74 line 95

**Spec 74 requirement:** "Group inbox fanout still excludes the
sender and avoids duplicate notification sends to repeated recipients."

Phase 1 modifies `buildGroupPushMessage`, which is downstream of
`SendGroupNotification` — the relay-side fanout. The fanout's
sender-exclusion and recipient-dedup logic is orthogonal to the
payload shape change, but a refactor touching the same file path
could accidentally disturb it.

Tests in `go-relay-server/inbox_test.go`:

- `TestGroupPushFanout_ExcludesSender_AfterCiphertextRefactor`
  — construct a group with members `{alice, bob, carol}`; alice sends;
  assert the fanout produces exactly two APNs/FCM pushes (bob, carol),
  zero for alice
- `TestGroupPushFanout_DeduplicatesRepeatedRecipients`
  — construct a group where `recipientPeerIds` contains duplicates
  (edge case seen during membership churn); assert exactly one push
  per unique recipient
- `TestGroupPushFanout_PreservesPeerIdOrder` (regression anchor) —
  asserts the output ordering matches today's baseline so downstream
  delivery-time telemetry stays comparable

Add to Phase 1 exit criteria in 9.11.

### 9.1.25 Post-push envelope retrieval — spec 74 line 96

**Spec 74 requirement:** "Relay-stored encrypted message envelopes
remain retrievable by the recipient after notification delivery."

Plan 73 assumes this is covered by the existing Group Messaging Gate
and 1:1 Messaging Gate. The refactor touches
`StoreWithPushMetadata` (`inbox.go:760-777`), which is the code that
writes to the inbox store and also triggers the push. A regression
that stops writing to inbox (because the `pushBody` field is no
longer present and the code path accidentally exits early) would
pass all push-shape tests while breaking retrieval.

Tests in `go-relay-server/inbox_test.go`:

- `TestStoreWithPushMetadata_WritesEnvelopeEvenWithoutPushBody`
  — new-format inbound with `ciphertext` + no `pushBody`; assert
  `GroupInboxRetrieve` returns the full encrypted envelope afterward
  byte-for-byte
- `TestStoreWithPushMetadata_WritesEnvelopeWithLegacyPushBody`
  — old-format inbound with `pushBody` + `ciphertext`; assert
  retrieval returns the same encrypted envelope (push-metadata-only
  change does not alter the stored bytes)

Add to Phase 1 exit criteria in 9.11.

### 9.1.26 Legacy cleartext exposure measurement — spec 74 line 55

**Spec 74 requirement:** "Privacy limitations from legacy cleartext
preview sends are **explicitly measured** rather than silently assumed
away."

The relay strips inbound `pushBody` on the outbound push after
Phase 1. Inbound `pushBody` from legacy senders is still received;
the spec asks that this legacy exposure is measured, not silently
discarded. This quantifies "how much cleartext did the relay still
see during the rollout window?" and informs the Phase 6 retirement
timeline.

Implementation:

- new relay metric `relay_inbound_legacy_pushbody_received_total`,
  labeled by `kind` (group / 1:1 / reaction / edit) — incremented
  every time an inbound inbox-store request contains a non-empty
  `pushBody`
- new relay metric `relay_inbound_legacy_pushbody_bytes_histogram`
  — size distribution of inbound legacy `pushBody` values; useful to
  characterize the exposure surface
- both metrics retire at Phase 6 (when minimum-client-version floor
  enforces that no legacy sender can send `pushBody` anymore)
- dashboard panel added alongside the Phase 5 degrade-rate panel:
  "Legacy cleartext exposure — legacy pushBody arrivals per day"
- documented in `52-notification-journey-test-matrix.md` as a
  time-bounded observability commitment

Tests in `go-relay-server/inbox_test.go`:

- `TestMetric_LegacyPushBody_IncrementedOnOldFormatInbound`
  — submit an old-format inbound with `pushBody` present; assert the
  counter ticked; assert the counter did NOT tick for a new-format
  inbound without `pushBody`
- `TestMetric_LegacyPushBody_DoesNotLeakPlaintextIntoMetricLabels`
  — assert the metric labels contain only `kind`, not any substring
  of the plaintext body (G-06 invariant re-asserted on telemetry)

Add to Phase 1 exit criteria in 9.11.

### 9.1.29 1:1 sender identity scrubbing — envelope-level fix

Spec 74 forbids sender display name / username in any
**relay-visible** field. The current 1:1 v2 envelope stores
`senderUsername` in the outer cleartext, which means:

- the relay's `extractChatPushMetadata` reads it and uses it as
  `aps.alert.title` for legacy pushes
- the relay's inbox store persists the full envelope to disk
  alongside the ciphertext — every unprocessed 1:1 message has the
  sender's display name sitting in plaintext on relay disk
- TLS termination, relay-disk backups, and any operator with
  inbox-read access can enumerate the sender-of-every-message graph
  without seeing message content

Phase 1 + Phase 2 as originally specified close leak source (b)
from Section 6 (the outbound push alert title), but NOT leak source
(c) (the stored envelope). This section closes (c).

#### 9.1.29.1 Envelope shape change

**Current 1:1 outer envelope** (`message_payload.dart`):
```json
{
  "id": "uuid",
  "senderPeerId": "12D3KooW...",
  "senderUsername": "alice",
  "encrypted": { "kem": "...", "ciphertext": "...", "nonce": "..." }
}
```

**New 1:1 outer envelope**:
```json
{
  "id": "uuid",
  "senderPeerId": "12D3KooW...",
  "encrypted": { "kem": "...", "ciphertext": "...", "nonce": "..." }
}
```

The inner plaintext (inside `encrypted`) gains a `senderUsername`
field so the recipient can decrypt and render it:

```json
{
  "text": "hello",
  "senderUsername": "alice",
  "media": [...],
  "quotedMessageId": "..."
}
```

Version bump: either roll to v3 envelope kind, or reuse v2 with a
dual-parsing receive path. The group side is already at v3 for
offline replay; aligning the 1:1 path with a v3-named envelope is
cleaner. Recommendation: **v3 1:1 envelope** with envelope kind
`chat_message_v3`.

#### 9.1.29.2 Send-path changes (Phase 2)

Files to change:

- `lib/features/conversation/domain/models/message_payload.dart` —
  stop including `senderUsername` in the outer envelope; add it to
  the inner plaintext before `callEncryptMessage`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
  — no API change; the envelope builder takes care of it

Tests:

- `test/features/conversation/domain/models/message_payload_test.dart`:
  - `v3 outer envelope omits senderUsername`
  - `v3 inner plaintext includes senderUsername`
  - `parsing a v3 envelope finds senderUsername only inside encrypted`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`:
  - `1:1 inbox-store request outer JSON contains no username field`
  — grep-style assertion that no key in the outer request resolves
  to `"alice"` even as a substring, given a seeded sender username
  canary

#### 9.1.29.3 Receive-path changes (Phase 3 Android + Phase 4 iOS)

The existing path reads `senderUsername` from the outer envelope
before decrypting. New path:

- decrypt first
- extract `senderUsername` from the decrypted inner plaintext
- pass it to the notification rendering step (`pushPreviewBody`)

Files to change:

- `lib/features/conversation/application/chat_message_listener.dart`
  — source of senderUsername shifts from outer field to decrypted
  inner field
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  — same
- Swift NSE — when decoding the decrypted payload, read
  `senderUsername` from the inner struct, not from the outer
  `request.content.userInfo`

Tests:

- `test/features/conversation/application/chat_message_listener_test.dart`
  — add `reads senderUsername from decrypted payload, not from outer
  envelope`
- `ios/RunnerTests/NotificationServiceTests.swift` —
  `test_oneToOne_readsSenderUsernameFromDecryptedPayload`

#### 9.1.29.4 Relay-side changes (Phase 1)

`go-relay-server/inbox.go`:

- `extractChatPushMetadata` (`inbox.go:273`) — REMOVE the
  `senderUsername` extraction. The function now returns only opaque
  routing fields: `senderPeerId`, `messageId`, `routeType`, `kind`
- any caller that used `metadata.SenderUsername` is updated to use
  only the opaque fields or derive nothing

Tests in `go-relay-server/inbox_test.go`:

- `TestExtractChatPushMetadata_DoesNotReadSenderUsername`
  — given a v3 envelope with no outer `senderUsername`, the
  extraction still succeeds; given a legacy v2 envelope WITH outer
  `senderUsername`, the extraction does NOT copy it into the
  returned metadata struct (even during the back-compat window)
- `TestRelayInboxStore_V3Envelope_StoresNoUsernameInOuterPlaintext`
  — submit a v3 inbox-store; read back the stored bytes; assert no
  outer key equals or contains the canary username

#### 9.1.29.5 Back-compat (rollout-window behavior)

During the staged rollout, old clients continue to send v2 envelopes
with outer `senderUsername`. The relay must:

- accept v2 inbox-stores (do not reject)
- NOT copy the outer `senderUsername` into any outbound push
- document that old clients' 1:1 messages sent during the window
  leaked the sender's display name to relay disk — that exposure
  cannot be retroactively unleaked but can be **measured** so we
  know its magnitude

Add a new relay metric `relay_inbound_legacy_v2_envelope_total`
(parallel to `relay_inbound_legacy_pushbody_received_total` from
9.1.26). Retire at Phase 6 when minimum-client-version floor is
enforced.

Tests:

- `go-relay-server/inbox_test.go`:
  - `TestLegacyV2Envelope_StillAcceptedButUsernameNotForwarded`
  — v2 envelope with outer `senderUsername = "alice"`; relay stores
  it (acceptable for the window), but outbound push has no `alice`
  anywhere in any surface (validated via the 9.7.1 forbidden-field
  classifier with the sender-username canary)
  - `TestMetric_LegacyV2Envelope_IncrementedOnV2Inbound`
  — counter ticks for v2 inbound, does NOT tick for v3 inbound

#### 9.1.29.6 Phase-gate placement

- **Phase 1 exit** adds: 9.1.29.4 relay-side tests + 9.1.29.5
  back-compat tests + the metric deliverable
- **Phase 2 exit** adds: 9.1.29.2 envelope builder tests
- **Phase 3 exit** adds: 9.1.29.3 Android receive-path test
- **Phase 4 exit** adds: 9.1.29.3 iOS receive-path test

### 9.1.28 Frozen-payload cross-version compatibility matrix

Plan 73 takes the product position that old group clients will degrade
to `"New message"` after the relay flips. That's an intentional trade
(Section 9.8). What's NOT obvious from the architecture alone is
whether, when the relay flips, old clients still behave *correctly* in
every other dimension: tap routing, inbox drain, deduplication,
crash-safety, no plaintext leak into logs, and no duplicate or orphaned
notifications. A single misbehavior in an unchanged handler could
regress delivery reliability for the entire pre-upgrade cohort.

These tests capture the wire-format of each rollout state as frozen
fixtures and verify every receiver build handles every payload shape
correctly. Fixtures are generated by the same deterministic Go pipeline
as 9.2, committed to the repo, and verified by drift checks.

Fixture set under `test/features/push/frozen_payloads/`:

| Fixture | Relay era | Shape |
| --- | --- | --- |
| `pre_phase1_group_text.json` | old relay | plaintext `pushTitle` / `pushBody` + ciphertext `message` |
| `pre_phase1_group_media.json` | old relay | plaintext `pushBody = "alice: Photo"` + ciphertext `message` |
| `pre_phase1_onetoone_text.json` | old relay | static `"You have a new message"` alert, no pushBody, ciphertext `message` |
| `pre_phase1_contact_request.json` | old relay | static title/body, unchanged-contract baseline |
| `pre_phase1_intro.json` | old relay | static intro title/body, unchanged-contract baseline |
| `post_phase1_group_text.json` | new relay | ciphertext-only data block + `mutable-content: 1` + placeholder alert |
| `post_phase1_onetoone_text.json` | new relay | ciphertext-only data block + `mutable-content: 1` + placeholder alert |
| `post_phase1_contact_request.json` | new relay | identical to `pre_phase1_contact_request.json` — relay contract for non-message pushes does NOT change |
| `post_phase1_intro.json` | new relay | identical to `pre_phase1_intro.json` |
| `post_phase1_dissolve.json` | new relay | ciphertext-only, envelope kind `group_dissolved` |
| `dual_format_transitional.json` | new relay receiving old-sender inbox | inbound has both `pushBody` AND ciphertext; outbound is ciphertext-only (pushBody dropped) |

#### 9.1.28.1 Relay contract over the fixture matrix

Tests in `go-relay-server/inbox_test.go`:

- `TestRelayEmitsFrozenPostPhase1Payload_ForEveryInboundShape`
  — parameterized over the inbound fixtures; asserts the relay's
  outbound wire format matches the corresponding `post_phase1_*.json`
  fixture byte-for-byte
- `TestRelayNeverEmitsPlaintextPushBody_AfterPhase1_EvenWithLegacyInbound`
  — specifically verifies the `dual_format_transitional` path drops
  plaintext `pushBody` in all outbound pushes

#### 9.1.28.2 Old-client (pre-Phase-3) behavior against frozen payloads

The critical regression guard: an old Android client with the
**unchanged `background_message_handler.dart`** must handle each
fixture without crashing, without double-notifying, without leaking
plaintext, and with correct tap routing.

Tests in
`test/features/push/old_handler_frozen_payload_compatibility_test.dart`:

- `old_handler_renders_pre_phase1_group_text_correctly`
  — feeds `pre_phase1_group_text.json`; asserts the local
  notification body equals the frozen `pushBody` (baseline, what
  users see today)
- `old_handler_renders_post_phase1_group_text_as_placeholder_without_crash`
  — feeds `post_phase1_group_text.json` (ciphertext-only);
  asserts exactly one notification is shown with body
  `"You have a new message"`, no crash, no double-notification,
  `NotificationRouteTarget.fromRemoteMessageData` resolves to a
  `group` target with the correct `groupId`, no plaintext leaks
  into any flow event
- `old_handler_renders_post_phase1_onetoone_text_unchanged`
  — 1:1 baseline: old handler already rendered
  `"You have a new message"` for encrypted 1:1; asserts the
  post-flip payload renders identically (this is the "1:1
  unchanged" claim from Section 9.8, made testable)
- `old_handler_renders_dissolve_as_placeholder_without_crash`
  — asserts the pre-Phase-3 handler does not mis-render the new
  `group_dissolved` envelope kind as a message
- `old_handler_passes_contact_request_and_intro_through_unchanged`
  — asserts non-message push types behave identically before and
  after the relay flip (no contract change, no collateral)

These tests MUST be pinned to the handler code as-of the commit
immediately prior to Phase 3 merging. Pin the tests to the frozen
handler by running them in a git worktree against the previous
release tag during Phase 1 release validation; document the
procedure in `scripts/run_old_handler_compatibility.sh`:

```bash
# Checks out the last released tag, runs the frozen-payload suite
# against the pre-Phase-3 handler, and reports pass/fail. Run this
# before flipping the production relay.
./scripts/run_old_handler_compatibility.sh v<last-released-version>
```

#### 9.1.28.3 iOS old-build behavior (no NSE installed)

iOS is structurally different — an old build has no Notification
Service Extension, so when a `mutable-content: 1` push arrives, iOS
displays the alert body the relay shipped (the `"New message"`
placeholder) with no decrypt attempt. This is handled by iOS itself,
not by app code, so the test is a simulator-matrix assertion rather
than an XCTest.

Add to 9.4 simulator matrix:

- install the last released build IPA (not a dev build) onto the
  iPhone 17 simulator via `xcrun simctl install` and launch; this
  gives us the pre-NSE app on a clean simulator — exactly the
  scenario old users will hit when the relay flips
- `xcrun simctl push "iPhone 17" <bundle-id>
  post_phase1_group_text.json`
  — assert: lock-screen shows `"New message"`; tapping routes to
  the correct group conversation; no crash
- same simulator receives `post_phase1_contact_request.json`;
  assert unchanged static body and correct tap route
- repeat on iPhone 17 Pro to catch any simulator-version-specific
  quirk between the two

#### 9.1.28.4 New client handling old-format pushes (late-upgrade scenarios)

During the staged rollout a new-build client can still receive
old-format pushes: the relay may not have flipped yet, or individual
relay replicas can lag during a rolling deploy, or a different
relay node serving a particular peer has old code.

Tests in
`test/features/push/application/background_message_handler_test.dart`
(extends 9.1.8):

- `new_handler_renders_pre_phase1_group_text_using_legacy_path`
  — feeds `pre_phase1_group_text.json`; asserts the legacy
  plaintext preview is rendered (the new handler is dual-tolerant
  per 9.1.8 and uses `pushBody` when `ciphertext` is absent)
- `new_handler_renders_post_phase1_group_text_via_decrypt`
  — feeds `post_phase1_group_text.json`; asserts the decrypt path
  runs and produces the correct rich preview
- `new_handler_prefers_ciphertext_when_both_present`
  — feeds `dual_format_transitional.json`; asserts exactly one
  notification is shown with the *decrypted* body, the legacy
  `pushBody` is ignored, no duplicate notification

iOS counterpart tests in
`ios/RunnerTests/NotificationServiceTests.swift`:

- `test_NSE_ignoresLegacyPushBody_andDecryptsCiphertext`
- `test_NSE_withoutCiphertext_leavesLegacyAlertBodyAlone`
  (the NSE is invoked only when `mutable-content: 1` is set;
  pre-Phase-1 pushes lack that flag, so NSE never fires —
  asserting this is a device-matrix check, not XCTest)

#### 9.1.28.5 Exit-criterion placement

- **Phase 1 exit** adds: 9.1.28.1 relay contract tests over the
  fixture matrix, and the completed
  `scripts/run_old_handler_compatibility.sh` against the last
  released tag returning zero failures
- **Phase 3 exit** adds: 9.1.28.4 new-handler dual-behavior tests
- **Phase 4 exit** adds: 9.1.28.3 iOS device-matrix rows for
  old-build-no-NSE behavior

### 9.1.27 Spec 74 ↔ plan 73 traceability

Explicit mapping so spec 74's test cases are each satisfied by a
named test in plan 73. Reviewers should check this table before
signing off each phase.

| Spec 74 case | Spec line | Plan 73 test location |
| --- | --- | --- |
| 1:1 encrypted message preview (happy) | 61 | 9.1.3, 9.1.4 |
| Group encrypted message preview (happy) | 62 | 9.1.3, 9.1.4 |
| Media-only message preview | 63 | 9.1.3 typed descriptor, 9.1.4 `test_mediaOnlyPlaintext` |
| Fallback preview | 64 | 9.1.3 key-missing, 9.1.4 `test_keyMissing` |
| Unit evidence — privacy classification | 68 | 9.3 no-plaintext gate, 9.7 security suite |
| Integration evidence — routing metadata | 69 | 9.1.6 routing regressions |
| Simulator evidence — background/terminated | 70 | 9.4 device matrix + 9.1.23 terminated rows |
| Missing key or stale key | 74 | 9.1.3, 9.1.4, 9.1.9 cold-boot |
| Duplicate push delivery | 75 | 9.1.12 dedupe sentinel |
| Muted group | 76 | 9.1.14 design + **9.1.20 behavioral** |
| Active conversation (1:1 AND group) | 77 | 9.1.19.1 group foreground-drain + active-conversation integration + 9.1.19.2 1:1 counterpart (new file `foreground_onetoone_push_drain_test.dart`) + 9.1.19.3 `show_notification_use_case_test.dart` unit coverage for post-decrypt suppression on both paths |
| Long text | 78 | **9.1.21 preview-length cap** |
| Unknown or malformed payload | 79 | 9.1.4 corrupt, 9.1.18 tampered sig, **9.1.22 unknown kind** |
| Old sender → old receiver, **old relay** (pre-Phase-1) | 83 | unchanged — baseline. `go-relay-server/inbox_test.go` historical assertions still pass |
| Old sender → old receiver, **new relay** (post-Phase-1) | 83 | **behavior changes** — 1:1 unchanged (still `"You have a new message"`); group previews degrade from `"alice: <text>"` to `"New message"`. Tests in 9.1.28 frozen-payload matrix |
| Old sender → new receiver | 84 | 9.1.8 dual-tolerance + **9.1.26 legacy measurement** |
| New sender → old receiver | 85 | 9.8 rollout ordering + product decision acknowledged |
| New sender → new receiver | 86 | target state — every Phase 3/4 test |
| Staged rollout | 87 | 9.8 + 9.1.8 |
| 1:1 tap routing preserved | 91 | 9.1.6 routing contract |
| 1:1 sender identity not in relay/push-visible fields | 49, 83 | 9.1.1 explicit `senderUsername` / `aps.alert.title` / `data.username` absence + **9.1.29 envelope-level scrub (send + relay + receive)** + 9.7.1 sender-username canary |
| Group tap routing preserved | 92 | 9.1.6 routing contract |
| Contact-request push untouched | 93 | 9.1.1 `TestBuildContactRequestPush_UnchangedShape` |
| Introduction push untouched | 93 | 9.1.1 `TestBuildIntroductionPush_UnchangedShape` (existing `inbox_test.go:710-730` baseline kept green) |
| Group-invite push untouched | 93 | 9.1.1 `TestBuildGroupInvitePush_UnchangedShape` |
| Group-dissolve push behavior | 93 | 9.1.1.1 resolved Option B (ciphertext-only); Phase 2 step 3 updated; tests in 9.1.1.1 cover relay shape, send-path redaction, decrypt render, and fallback |
| Post / post-comment / post-reaction notifications | 93 | **out of scope at the relay** — posts do not use a relay push path; they are local notifications generated by `post_listener.dart:85`, `post_comment_listener.dart:80`, `post_reaction_listener.dart:84` after P2P delivery. No plan 73 change touches this path. Covered by existing post-feature test suites, not by 9.1.1 |
| Foreground local notifications preserved | 94 | scope guard — Section 3, non-goal |
| **Group fanout excludes sender, dedupes recipients** | 95 | **9.1.24 fanout regression guard** |
| **Stored envelope retrievable post-push** | 96 | **9.1.25 post-push retrieval** |
| Old clients get visible fallback | 97 | 9.8 rollout decision |

### 9.11 Phase-to-test traceability (final)

Each phase exit criterion maps to named tests. Reviewers confirm every
line before merging a phase:

- **Phase 1 exit** → 9.1.1 relay tests (incl. introduction
  unchanged-shape) + **9.1.1.1 `TestBuildDissolvePush_FlowsThroughCiphertextOnlyPath`**
  + **9.1.1 `TestBuildMessagePush_PayloadSizeWithinProviderBudgets`**
  + 9.1.6 routing regressions + 9.1.8 `unchanged Android handler does
  not crash on ciphertext-only payload` + **9.1.24 group fanout
  regression** + **9.1.25 post-push envelope retrieval** +
  **9.1.26 legacy cleartext metric** + **9.1.28.1 relay contract over
  frozen-payload matrix** + **`scripts/run_old_handler_compatibility.sh`
  green against the last released tag** + **9.7.1 forbidden-field
  classifier (Go + Dart mirrors)** + **9.1.29.4 relay stops reading
  `senderUsername` from 1:1 envelope + 9.1.29.5 legacy-v2-envelope
  metric** + 9.3 Group Messaging Gate still green + 9.8 rollout
  ordering acknowledged
- **Phase 2 exit** → 9.1.2 client-send tests + **9.1.1.1 dissolve
  send-path test (`dissolve inbox request omits plaintext pushTitle
  and pushBody`)** + **9.1.29.2 v3 1:1 envelope omits outer
  `senderUsername`** + 9.7 Dart `no_plaintext_leak_test.dart` exists
  and passes + **9.7.1 forbidden-field classifier (Dart) passes
  across every send use case** + 9.3 no-plaintext-in-flow gate +
  `test/security/` directory created with owner assigned (R-05
  ownership)
- **Phase 3 exit** → 9.1.3 Android handler tests + 9.1.5 Dart parity
  test + 9.1.8 dual-tolerance tests + 9.1.10 Android grouping test +
  9.1.15 permission-denied test + 9.1.18 Android tampered-signature
  tests + **9.1.19.1 group foreground-drain + active-conversation
  integration tests** + **9.1.19.2 1:1 foreground-drain +
  active-conversation integration tests (new file
  `integration_test/foreground_onetoone_push_drain_test.dart`)** +
  **9.1.19.3 `show_notification_use_case_test.dart` unit coverage
  for post-decrypt suppression on both 1:1 and group paths** + **9.1.1.1 Android dissolve decrypt + fallback render** +
  **9.1.21 Dart preview-length cap** + **9.1.22 Android unknown
  envelope kind** + **9.1.23 Android terminated-app rows** +
  **9.1.28.4 new-handler dual-behavior tests (legacy / ciphertext /
  both-present)** + **9.7.1 forbidden-field classifier (Dart, extended
  to cover new decrypt-path flow events)** + **9.1.29.3 Android reads
  senderUsername from decrypted payload, not outer envelope** +
  **9.4.1.2 Android Emulator scenarios S-And-1 through S-And-19 pass
  on Pixel 7 API 37** + **9.4.1.1 iOS Simulator scenarios S-iOS-1
  through S-iOS-19 (incl. dual-simulator rows S-iOS-17/18/19 on
  iPhone 17 + iPhone 17 Pro) pass in dual-tolerant mode** + 9.5
  smoke script Android-only rows + 9.10.6 Phase 3
  `test-gate-definitions.md` deliverables merged
- **Phase 4 exit** → 9.1.4 Swift tests + 9.1.5 Swift parity test +
  **9.1.5 Swift crypto known-answer tests** + 9.1.7 keychain
  migration + 9.1.9 cold-boot keychain + 9.1.10 iOS
  threadIdentifier + 9.1.12 extracted-sentinel race tests (CI) +
  (cross-process race outside plan 73 scope; extracted-sentinel logic
  proven via 9.1.12 CI tests; real cross-process deferred to future
  physical-device plan) + 9.1.13 Swift
  leak scanner + 9.1.14 mute-state-not-consulted + 9.1.16
  entitlements match + 9.1.18 iOS tampered-signature tests +
  **9.1.1.1 iOS dissolve decrypt + fallback render** +
  **9.1.20 muted-group behavioral regression** + **9.1.21 Swift
  preview-length cap** + **9.1.22 iOS unknown envelope kind** +
  **9.1.23 iOS terminated-app rows** + **9.1.28.3 iOS old-build
  device-matrix rows (no NSE installed, static `"New message"`, tap
  still routes correctly)** + **9.7.1 forbidden-field classifier
  (Swift `ForbiddenFieldClassifierTests` — NSE logs and flow events
  contain no canaries)** + **9.1.29.3 iOS NSE reads senderUsername
  from decrypted payload, not outer envelope** + **9.4.1.1 iOS
  Simulator scenarios S-iOS-1 through S-iOS-19 all pass on CI on
  iPhone 17 + iPhone 17 Pro (incl. dual-simulator rows; this IS the
  release gate for plan 73 — no separate physical-device matrix)** +
  9.3 NSE bundle-size gate + 9.5 smoke script full pass + 9.8
  Phase 4 rollout-ordering constraint enforced
- **Phase 5 exit** → 9.6 telemetry dashboard live + 9.10 soak-window
  configured + 9.10.5 schema-version decision test
  (`TestBuildNewMessagePush...` asserts no version field) +
  **9.6 degrade-rate gate test proves `client_pre_decrypt` exclusion
  and updated-client failures still count** +
  **9.7.1 forbidden-field classifier re-run to confirm new metric
  labels contain no canaries** +
  **9.10.6 Phase 5 deliverable merged: `push_preview_degrade_rate_gate`
  block lands in `test-gate-definitions.md` and
  `completeness-check` stays green**
- **Phase 6 exit** → all of the above remain green after cleanup;
  9.1.1 dual-format back-compat test converted to assert the relay
  rejects the legacy shape once client version floor enforced

## 10. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| NSE memory blow-up from embedding Go xcframework | med | extension silently fails, user sees placeholder forever | Swift-native crypto path (CryptoKit + SwiftKyber); size-budget CI check |
| ML-KEM-768 Swift lib bitrot / supply chain | med | crypto regression | pin hash, audit before adopting, consider writing a minimal FIPS-203 Swift impl ourselves |
| Android OEM throttles data-only FCM | high | preview shows fallback, delivery also delayed | combine with existing foreground drain (plan 71); set FCM priority=high; measure degrade rate per OEM in telemetry |
| Keychain access group mismatch during first install after upgrade | med | legacy keys stored without accessGroup are invisible to NSE | on-upgrade migration: re-write every secret through the new `accessGroup`-aware writer; ship as part of Phase 4 rollout |
| Group key rotation race (push arrives before new epoch key is shared) | low | transient fallback for that one message | already acceptable per closure bar; measurable via degrade counters |
| Old builds in the field lose rich group previews when relay flips | certain | accepted — product decision (2026-04-24) prioritizes privacy over transitional UX | in-app upgrade banner for old-build cohort; relay continues to *accept* old-format inbound (ignores `pushBody`) until Phase 6 cleanup; relay never *emits* plaintext after Phase 1 |
| NSE tap routing regression | med | user taps notification and lands wrong place | Phase 4 checklist item: verify `NotificationRouteTarget.fromRemoteMessageData` still parses the new data block; add targeted contract test |

## 11. Sequencing and Rough Sizing

- Phase 1 (relay contract): 2-3 days, one engineer, pure Go
- Phase 2 (client send-path): 0.5 day, pairs with Phase 1
- Phase 3 (Android handler): 4-6 days, including OEM device testing
- Phase 4 (iOS NSE): 6-10 days — single biggest item; Swift crypto port
  and keychain sharing are where the time goes
- Phase 5 (telemetry + gates): 1-2 days
- Phase 6 (cleanup): 1 day, blocked on client version floor

Total: **roughly 3 weeks of focused engineering** for one engineer, or
~2 weeks with an iOS specialist paired in on Phase 4. Phases 1-3 can land
independently and give partial privacy wins immediately (Android users get
full content + no relay leak; iOS users see `"New message"` until Phase 4).

## 12. Decision Points Before Starting

These need an answer before Phase 1 branches:

1. **Accept the Swift-native crypto path?** (Pure-Swift ML-KEM has supply
   chain cost; embedded Go has size cost.) Recommendation: Swift-native,
   audit the lib, keep Go as fallback.
2. **New App Group `group.com.mknoon.app.push` or reuse the existing
   `group.com.mknoon.app.share`?** Recommendation: new group — smaller
   blast radius, clean separation from share-extension data.
3. **Mirror group keys into keychain, or share SQLCipher via App Group
   container?** Recommendation: mirror — SQLCipher stays single-owner,
   keychain entries per epoch are small.
4. **Staged rollout strategy: RESOLVED 2026-04-24.** Relay flips to
   ciphertext-only as soon as Phase 1 is ready — no waiting for client
   adoption. Old builds degrade to the static `"New message"` placeholder
   for group pushes (1:1 already shows that today, so no 1:1 regression).
   Privacy takes precedence over transitional preview UX. See Section
   9.8 for rollout ordering and user-facing messaging. Phase 6 cleanup
   still waits for minimum-client-version floor to retire the
   dual-format parsing paths.
5. **Degrade rate threshold** for the new gate (3 % suggested; acceptable
   window before blocking release TBD).
