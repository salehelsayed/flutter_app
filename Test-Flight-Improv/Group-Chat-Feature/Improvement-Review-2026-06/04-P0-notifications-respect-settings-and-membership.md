> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · [Findings appendix](./appendix-findings.md)

---

# Make notifications honor mute, membership, and one-per-message

**Priority: P0** &nbsp;|&nbsp; Theme: Notifications &nbsp;|&nbsp; Surfaces: iOS NSE, Android background isolate, Dart live/foreground, relay fanout

> **One-liner:** Enforce mute and removed-member suppression on *all* push paths, decrypt Android group previews, make NSE-vs-live dedupe authoritative, and stop dead taps. Mute has literally zero presence in the NSE/background paths today.

---

## Why this matters (user experience)

A messaging app is judged by whether it respects two promises: *"I muted this, stop buzzing me"* and *"I'm not in this group anymore, stop showing me its messages."* mknoon currently keeps both promises **only on the live in-app path** and breaks them on exactly the paths that matter most — when the recipient is backgrounded, offline, or terminated, which is *when notifications are the entire product*.

Concretely, today:

- A user who mutes a noisy group **still gets buzzed** for every relay-delivered message (iOS NSE shows a decrypted banner; Android shows a generic fallback). Mute appears broken.
- A removed member **can still get decrypted/visible group pushes** until the relay stops targeting them and their epoch key rotates out. Membership boundaries feel untrustworthy.
- **Android group pushes are always generic** ("New Message / You have a new message") even though the relay ships real ciphertext — Android group chat feels broken next to iOS.
- A single message can produce **two notifications** (NSE banner + later in-app replay) when iOS doesn't wake the Dart isolate, or when the OS purges the temp-dir dedupe gate.
- Tapping an unrecoverable group push is a **silent dead tap** — nothing navigates, nothing explains.

These are the precise symptoms the notification journey matrix flags as P0 (`Test-Flight-Improv/52-notification-journey-test-matrix.md`, lines 38, 64–66, 166: *"removed group members still receiving notifications they should no longer see"*, *"P0/P1 regressions because they make the app feel unreliable"*).

---

## Current behaviour & evidence

### 1. Mute is checked on exactly one of three producers

Mute lives in `group.isMuted` (SQLCipher, migration 050) and is consulted **only on the live GossipSub path**:

- `lib/features/groups/application/group_message_listener.dart:748-751` reads `group?.isMuted` and gates `maybeShowNotification`.
- `lib/features/groups/application/set_group_muted_use_case.dart:28-29` persists `isMuted` **only** to the SQLCipher DB via `groupRepo.updateGroup` — nothing is mirrored anywhere the NSE or background isolate can read.

The other two producers ignore mute entirely:

- **iOS NSE** — `ios/NotificationService/NotificationService.swift:14-39` always calls `contentHandler(bestAttemptContent)`. `NotificationPreviewResolver.swift` has no mute lookup, and `KeychainPushKeyReader` (`:332-363`) can structurally read *only* the app-group Keychain (it cannot open the encrypted DB).
- **Android / Dart background + foreground fallback** — `lib/features/push/application/background_message_handler.dart:96-133` shows unconditionally; `showForegroundPushFallbackNotificationIfNeeded` (`lib/features/push/application/background_push_notification_fallback.dart:48-68`) shows with no `isMuted` check.

### 2. No membership check on any push producer

Grep for `getMember`/`isMember` across `lib/features/push` finds membership consulted only in `resolveGroupNotificationRouteTarget` (`resolve_group_notification_route_target_use_case.dart:42`) — **tap-time routing only**, not notification production.

- iOS `resolveGroup()` (`NotificationPreviewResolver.swift:218-293`) only checks for a *group key*; no membership.
- Android/Dart background handler shows unconditionally.
- The relay decides recipients (`go-relay-server/inbox.go:910-938 fanOutPush`), so a stale recipient list or a retained epoch key surfaces a notification to a removed member.

> **Correction vs. the original finding:** the *live* path is **not** membership-blind. `handle_incoming_group_message_use_case.dart:191-205` calls `groupRepo.getMember` for the local recipient and returns `null` (drops the message, no persist, no notification) when the local recipient is no longer a member for non-system messages, plus removed-interval-replay rejection at `:207-249`. The genuine gap is **only** the push/NSE/Android-background producers, plus reliance on the relay dropping removed peers and on epoch-key rotation. The matrix rows SM-004 / GMN-102 are honest about this: their "covered" evidence is the *live-listener* unit test, not the push/NSE paths.

### 3. Android group previews are dead code in production

- `background_message_handler.dart:21-22` defaults `_backgroundPushNotificationResolver` to `resolveBackgroundPushNotification`, invoked at `:105` with `decryptGroup`/`decryptOneToOne` **left null**.
- `push_decrypt_preview.dart:111-122` returns the generic fallback immediately when `decryptGroup == null` (emitting `missing_group_decrypt_input`).
- `debugSetBackgroundPushNotificationResolver` (defined `push_decrypt_preview.dart:25`) is **never called in production** — grep confirms it appears only as a definition. The background isolate only does `Firebase.initializeApp()` (`:55-65`); no Go bridge / SecureKeyStore init.
- No Android `FirebaseMessagingService`/`onMessageReceived` override exists (grep across `android/` found only `MainActivity.kt` and `GoBridge.kt`).
- Meanwhile the relay *does* ship ciphertext: `inbox.go:438-455 addGroupEncryptedPushData` populates `keyEpoch`/`ciphertext`/`nonce`.

Result: every Android group push renders generic via `_usesProtectedMessagePreview` (`background_push_notification_fallback.dart:139-143`), while the iOS NSE decrypts. Confirmed.

### 4. NSE-vs-live dedupe depends on the Dart isolate firing

The cross-process announcement marker is written **only** inside `firebaseMessagingBackgroundHandler`: `markVisibleRemoteAnnouncement` at `background_message_handler.dart:98` and `:133`, gated on `message.notification != null` (`:97`). The live path consumes it at `group_message_listener.dart:765-770`.

But the **visible iOS alert is produced by the NSE — a separate process** whose only dedupe store is `AppGroupPushDedupeStore` writing files under the app-group container `NotificationServiceDedupe` (`NotificationPreviewResolver.swift:365-401`). The NSE **never writes** the systemTemp gate file the Dart live path reads (`recent_remote_notification_gate.dart:33-35`). So suppression of the NSE-shown banner depends entirely on iOS scheduling the Dart isolate for that alert push — which iOS does not guarantee.

### 5. Dedupe gates live in OS-evictable systemTemp

`recent_remote_notification_gate.dart:33-35` and `recent_background_notification_gate.dart:32-34` both default `filePath` to `${Directory.systemTemp.path}/...json`. systemTemp is explicitly OS-evictable. `_loadEntries` swallows *all* errors and returns `{}` (`recent_remote_notification_gate.dart:135`), so a wiped or corrupt file silently disables dedupe — and the 12h redelivery guard (`recentRemoteNotificationMessageTtl = Duration(hours: 12)`, `:7`, the DM-102 guarantee) lapses with no telemetry.

### 6. Dead tap on unrecoverable group push

`main.dart:2737-2754`: when `resolution.group == null` and there is no pending invite, the code clears `_notificationTappedAt`, emits `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING`, and **returns with no navigation and no user feedback**. The pending-invite branch navigates via `_openIntroOrbitRoute` (`:2750-2751`); the plain "missing" branch is a no-op. Grep for `ScaffoldMessenger`/`SnackBar` in `main.dart` returns zero matches.

### 7. Live notification body uses raw, unsanitized wire fields

`group_message_listener.dart:761-763` builds `messageText: '$senderUsername: ${notificationBodyForMessage(text, persistedAttachments)}'` from the unmodified `data['senderUsername']` (`:606`) and `data['text']` (`:608`). The persisted/timeline message instead uses `sanitizeMessageText(text)` and `resolveGroupSenderDisplayName(...)` (`handle_incoming_group_message_use_case.dart:54,599`, `group_sender_display_name.dart:4-25`). `sanitizeUsername` strips zero-width/bidi control chars and truncates to 30 chars; `sanitizeMessageText` strips control chars. So the **banner can show bidi/invisible/overlong content the timeline never renders**, and a different display name than the resolved member-bound name.

> Severity note: the timeline name stays bound to a validated member, so this is a *transient banner divergence / control-char surface*, not a true conversation-identity spoof.

### 8. Foreground drain failure → generic, mute-blind fallback

`handle_foreground_remote_message_use_case.dart:68-78` returns `notificationNeeded` only for group drain errors; `main.dart:3185` then calls `showForegroundPushFallbackNotificationIfNeeded`, which forces the generic title/body via `_usesProtectedMessagePreview` and performs **no decrypt and no mute check**. The degraded path is both contentless and mute-blind, and a later dead tap is possible.

---

## Root cause(s)

1. **Mute and membership live only in the encrypted DB**, which the out-of-process NSE and the not-fully-initialized Dart background isolate cannot read. There is no app-group-readable projection of "is this group muted?" or "am I still a member?".
2. **Three independent notification producers** (live listener, iOS NSE, Dart background/foreground fallback) each implement their own gating, and only the live one was ever taught about mute/membership.
3. **Android has no decrypt wiring at all** — the decrypt typedefs and `_resolveGroupPreview` exist and are unit-tested, but nothing constructs a bridge + key reader in the background isolate and injects the closures.
4. **Cross-process dedupe is one-directional**: only the Dart side writes the gate; the NSE (the actual producer on iOS) writes a *different* store, so "NSE showed it" is not authoritative for in-app suppression.
5. **Dedupe state is stored in volatile, error-swallowing temp files.**

The common theme: **the source of truth (mute, membership, "already shown") is not visible to every process that produces a notification.** The fix is to project these facts into the shared app-group store and make every producer consult them.

---

## Proposed improvements

The fixes split cleanly into **quick wins** (ship immediately, Dart-only, no native rebuild) and **structural** changes (new app-group projections + Android decrypt wiring + relay).

### Quick wins (P0, ship first)

#### QW-1 — Use sanitized/persisted fields in the live notification body
In `group_message_listener.dart:761-763`, build the banner from the persisted result rather than raw wire fields:

```dart
senderUsername: groupName, // unchanged: this is the group name (title)
messageText:
    '${result.senderUsername}: '
    '${notificationBodyForMessage(result.text, persistedAttachments)}',
```

Use `result.senderUsername` (resolved, member-bound, sanitized) and `result.text` (sanitized). This eliminates the bidi/control-char/overlong banner surface and makes the banner match the timeline. **No wire/DB change.**

#### QW-2 — Fix the dead tap on the group-missing branch
In `main.dart:2737-2754`, on the `resolution.group == null && !hasPendingInvite` branch, do not return silently. Instead:

1. Optionally retry `drainGroupOfflineInboxForGroup` **once** before giving up (the targeted drain inside `resolveGroupNotificationRouteTarget` already drains; if extending, add a single retry there).
2. Navigate somewhere sensible (group list / home) and show a transient `SnackBar` via a `ScaffoldMessenger` (e.g. *"Couldn't open this conversation — still catching up"* with a Retry action). Add the l10n string to `app_en.arb`/`app_ar.arb`/`app_de.arb` and regenerate `app_localizations*.dart`.
3. Keep the `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING` flow event for telemetry.

**No wire/DB change.**

#### QW-3 — Observe dedupe-gate decode failures
In `_loadEntries` of both `recent_remote_notification_gate.dart:135` and `recent_background_notification_gate.dart:96`, distinguish a clean miss (file absent / empty) from a decode error, and emit a flow event (e.g. `RECENT_NOTIFICATION_GATE_DECODE_ERROR`) on the latter so silent dedupe loss becomes observable. **No wire/DB change.** (Pairs with the storage relocation in SI-4.)

### Structural improvements

#### SI-1 — App-group "muted" projection consulted by every producer
Mirror mute into a store the NSE and background isolate can read, reusing the **exact same `pushSharedKeyStore` mechanism already used for group keys** (`group_repository_impl.dart:463-490 _mirrorGroupKeyForPush` writes `group_key:<groupId>:<gen>` to the app-group Keychain via `pushSharedKeyStore.write`).

1. Add a key name helper, e.g. `sharedGroupMutedKeyName(groupId) => 'group_muted:$groupId'`, alongside `sharedGroupPushKeyName` (`group_repository_impl.dart:11-12`).
2. In `set_group_muted_use_case.dart`, after `groupRepo.updateGroup(updated)`, write/delete the app-group flag (write `"1"` on mute, delete on unmute). Inject `pushSharedKeyStore` or expose a repo method so the use case can mirror; the repo already holds `pushSharedKeyStore`.
3. **iOS NSE:** in `NotificationPreviewResolver.resolveGroup()` (after `groupId` is parsed, `:224`), call `keyReader.readString(key: "group_muted:\(groupId)")`. If present, return a *suppressing* result. (See SI-5 for how the NSE suppresses.)
4. **Android/Dart background:** in `background_message_handler.dart` before `_backgroundNotificationsPlugin.show` (`:123`), read the same flag from a SecureKeyStore pointed at the app-group and skip if muted. Same check in `showForegroundPushFallbackNotificationIfNeeded`.

> **Backfill:** on first launch after this ships, run a one-time reconciliation that iterates active groups and writes the `group_muted:*` flags from DB `isMuted` (mirrors the existing `_mirrorGroupKeyForPush` reconciliation pattern), so already-muted groups are honored without a re-toggle. **No DB migration; new app-group Keychain entries only.**

#### SI-2 — App-group "removed/not-a-member" projection (membership on push paths)
Treat removal like mute for the notification surface:

1. **Delete the epoch group key from the app-group Keychain on removal/leave** so the NSE can no longer decrypt — `_deleteGroupKeyMirror` (`group_repository_impl.dart:492-514`) already exists; ensure it is invoked on the remove/leave paths. With the key gone, the NSE falls back to generic (and, per SI-5, can suppress).
2. **Persist a membership sentinel** (e.g. `group_membership:<groupId>` = `"member"` / absent) updated whenever local membership changes, that the NSE and Dart background handler consult to **suppress entirely** (not just degrade to generic). This closes the retained-epoch-key window.
3. **Relay:** ensure `fanOutPush` (`go-relay-server/inbox.go:910-938`) drops removed peers from the recipient list promptly — this is the authoritative gate. Verify the recipient list passed into `AddGroupMessage`/`fanOutPush` is recomputed from current membership at send/fanout time, not a stale snapshot.

> **Reframe vs. original finding:** the live path already enforces local membership; this work is specifically about the **push/NSE/Android-background producers** plus relay fanout correctness and key-rotation timeliness. **No DB migration; new app-group entries + relay logic.**

#### SI-3 — Wire a real Android background decryptor
The decrypt closures and `_resolveGroupPreview` already exist and are unit-tested (`push_decrypt_preview.dart`). Make them live in production:

1. In `firebaseMessagingBackgroundHandler` (`background_message_handler.dart`), after `Firebase.initializeApp()`, construct a **minimal headless `GoBridge`** (the same Go decrypt the iOS `BridgePushDecryptor` uses) plus a Keychain/secure-store reader pointed at the app-group, and inject `decryptGroup: callGroupDecrypt` and `decryptOneToOne: callDecryptMessage` into `resolveBackgroundPushNotification` (instead of leaving them null at `:105`).
2. The group key is read by epoch from `group_key:<groupId>:<keyEpoch>` (already mirrored by `_mirrorGroupKeyForPush`), exactly as the NSE does.
3. **Alternative / complementary:** implement an Android `FirebaseMessagingService` (`android/app/src/main/kotlin/com/mknoon/app/`) that decrypts before display, mirroring the iOS NSE architecture. The Dart-isolate route is lower-effort and reuses tested code; the native service is the stronger long-term parity match.

This delivers `senderUsername: text` previews on Android (with media-type fallback already in `pushPreviewBody`). **No wire/DB change** (ciphertext already shipped per `inbox.go:438-455`).

#### SI-4 — Move dedupe gates out of systemTemp
In both gates' constructors, default `filePath` to `getApplicationSupportDirectory()` rather than `Directory.systemTemp`. On iOS, prefer the **shared app-group container** so the NSE and Dart can agree (required for SI-5). Combine with QW-3's decode-error telemetry. **No wire/DB change.**

#### SI-5 — Make "NSE showed it" authoritative for in-app suppression
Have the NSE record the visible announcement into a store the Dart live path reads:

1. In `NotificationService.didReceive` (after `contentHandler(bestAttemptContent)` when the result is a real, non-suppressed alert), write a recent-remote marker into the shared app-group container keyed by `payload + messageId` (the same key shape `markAnnouncement` uses: `message:<payload>|<messageId>`). The NSE already computes a dedupe identity in `AppGroupPushDedupeStore`.
2. Make `RecentRemoteNotificationGate` (now living in the app-group container per SI-4) read that location on iOS, so `consumeIfRecentAnnouncement` (`group_message_listener.dart:765-770`) returns `true` regardless of whether the Dart background isolate ran.

This removes the dependency on iOS scheduling the Dart isolate for every alert push — the exact one-per-message guarantee in DM-101/GMN-101/DM-102.

#### SI-6 — Foreground drain-failure fallback: decrypt + respect mute
On foreground group drain failure (`handle_foreground_remote_message_use_case.dart:68-78` → `main.dart:3185`):

1. Retry the targeted drain once; if it still fails, **decrypt the preview in-process** (the app is foregrounded, bridge + keys available) so the fallback shows `sender: text` instead of generic.
2. Apply the SI-1 mute check before showing.
3. Tie the shown notification's `messageId` into the dedupe gate so a later successful drain doesn't double-notify.

> Optional server-side hardening (SI-1 Option B): sync mute state to the relay and gate `SendGroupNotification`/`SendNotification` (`inbox.go:124`, `:930`) so muted groups never push a *visible alert* at all (data-only). Higher effort and a new sync channel; the app-group projection above is the recommended primary fix because it works even when the relay is unaware.

### New wire / DB / migration impact summary

| Change | Wire | DB / migration | App-group Keychain |
|---|---|---|---|
| QW-1, QW-2, QW-3 | none | none (QW-2 adds l10n strings only) | none |
| SI-1 muted projection | none | none | new `group_muted:<groupId>` |
| SI-2 membership projection | none (relay logic only) | none | new `group_membership:<groupId>`; reuse key delete |
| SI-3 Android decrypt | none (ciphertext already sent) | none | reuse `group_key:*` |
| SI-4 gate storage | none | none | gate files move into app-group container (iOS) |
| SI-5 NSE marker | none | none | new recent-remote marker in app-group |
| SI-6 foreground fallback | none | none | reuse SI-1 |

No SQLCipher schema migration is required for any item.

---

## Affected files & components

**Dart (quick wins):**
- `lib/features/groups/application/group_message_listener.dart` (QW-1 sanitized body)
- `lib/main.dart` (QW-2 dead-tap fix; SI-6 wiring)
- `lib/core/notifications/recent_remote_notification_gate.dart`, `lib/core/notifications/recent_background_notification_gate.dart` (QW-3, SI-4)
- `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb` + generated `app_localizations*.dart` (QW-2 string)

**Dart (structural):**
- `lib/features/groups/application/set_group_muted_use_case.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart` (SI-1/SI-2 projections, reuse `pushSharedKeyStore` / `_mirrorGroupKeyForPush` / `_deleteGroupKeyMirror`)
- `lib/features/push/application/background_message_handler.dart` (SI-1 mute check, SI-3 decrypt wiring)
- `lib/features/push/application/push_decrypt_preview.dart` (SI-3 — already supports injection)
- `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/push/application/handle_foreground_remote_message_use_case.dart` (SI-1/SI-6)

**iOS (structural):**
- `ios/NotificationService/NotificationService.swift` (SI-5 marker on alert)
- `ios/NotificationService/NotificationPreviewResolver.swift` (SI-1 mute lookup, SI-2 membership lookup, SI-5)

**Android (structural):**
- `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt` (SI-3 headless decrypt entry) and/or a new `FirebaseMessagingService`

**Relay (structural):**
- `go-relay-server/inbox.go` (`fanOutPush` recipient gating SI-2; optional mute-gated `SendGroupNotification` SI-1 Option B)

---

## Test & verification strategy

### Unit (deterministic, gate every PR)
- **QW-1:** extend `test/features/groups/application/group_message_listener_test.dart` to assert the banner uses `result.senderUsername`/`result.text` and that bidi/control-char/overlong wire input is *not* present in the banner.
- **QW-2:** widget/route test asserting the group-missing branch navigates + shows a SnackBar (no silent return). Augments `test/features/push/application/chat_and_group_push_open_flow_test.dart`.
- **QW-3 / SI-4:** extend `test/core/notifications/recent_remote_notification_gate_test.dart` and `recent_background_notification_gate_test.dart` to assert decode-error telemetry and the new storage location.
- **SI-1/SI-2 (push paths):** new tests under `test/features/push/application/` asserting the background handler and the resolver suppress when the muted/removed app-group flag is set — covering the gap the matrix admits (SM-004/GMN-102 only cover the *live* listener today).
- **SI-3:** `test/features/push/application/push_decrypt_preview_test.dart` already exercises `_resolveGroupPreview` with injected closures; add a background-handler test that the closures are wired (non-null) in production config.
- **SI-1/SI-2 (iOS):** extend `ios/RunnerTests/NotificationPreviewResolverTests.swift` (already covers same-id/re-minted dedupe per GMN-001A) with mute-flag and missing-membership suppression cases.
- **SI-5:** test that an NSE-written marker is consumed by `consumeIfRecentAnnouncement`, proving suppression without the Dart isolate running.

### Integration harnesses (this repo's `integration_test/` + fake-network)
- `test/integration/group_notification_dedupe_integration_test.dart` and `chat_notification_dedupe_integration_test.dart` — extend for the NSE-authoritative path (DM-101/GMN-101/DM-102, matrix lines 242–243, 252).
- `integration_test/foreground_group_push_drain_test.dart` + `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart` — extend for SI-6 (decrypt + mute on foreground drain failure; JRN-FG-GRP-01, line 234).
- `test/features/groups/integration/group_membership_smoke_test.dart` — extend to assert removed-member **push** suppression, not just receive blocking (SM-004/GMN-102/RG-006, lines 205, 253, 269).
- `scripts/smoke_test_push_decrypt_simulator.sh` / RG-008 harness (S-And-1..S-And-19) — re-run to confirm Android now decrypts group previews (RG-007 telemetry, line 270).

### Device matrix
- **iOS NSE:** TestFlight/device proof that muted and removed-member group pushes are suppressed at the banner, and Android-parity previews show. RG-007 (`push_preview_degrade_rate_gate`) production telemetry remains the residual gate.
- **Android background:** physical Pixel6 (`21071FDF600CSC`, per project memory) to confirm `sender: text` previews and mute/membership suppression in the background isolate.
- **One-per-message:** 2-party (DM) and 3-party (GMN) device runs under throttling/low-power to confirm SI-5 holds when iOS skips the Dart isolate.

Update the matrix at `Test-Flight-Improv/52-notification-journey-test-matrix.md` so SM-004/GMN-102/GMN-103/RG-006 cite the new **push/NSE** coverage rather than only the live-listener test.

---

## Risks, trade-offs & rollout

| Risk | Mitigation |
|---|---|
| **App-group Keychain write failures** silently leave mute/membership unprojected (NSE keeps notifying). | Reuse the existing `_mirrorGroupKeyForPush` error-event pattern (`GROUP_REPO_PUSH_KEY_MIRROR_ERROR`); add a launch-time reconciliation so the projection self-heals; emit telemetry on mirror failure. |
| **Stale projection** (muted in DB but not mirrored, or vice versa). | One-time backfill on first launch after ship; re-mirror on every toggle; treat DB as source of truth and reconcile on resume. |
| **Suppressing too aggressively** (false "removed"/"muted" → user misses real messages). | Membership sentinel should *fail open to generic*, not silently drop, until the relay/key-rotation gates are proven; ship suppression behind a flag and validate with RG-007 degrade-rate telemetry first. |
| **Android headless bridge cost/cold-start** in the background isolate. | Prefer the lightweight Dart-isolate decrypt (SI-3 option A) reusing tested code; keep the native `FirebaseMessagingService` as a follow-up. Time-box decrypt and fall back to generic on timeout (mirrors NSE `serviceExtensionTimeWillExpire`). |
| **SI-5 cross-process file contention** between NSE and Dart in the app-group container. | Use atomic create-exclusive writes (the NSE `AppGroupPushDedupeStore.claim` already uses `O_CREAT|O_EXCL`); keep per-message keys. |
| **Native rebuild required** for iOS/Android structural items. | Per project memory, iOS needs `flutter clean` + `make all` + `pod install`; sequence iOS before Android in release builds. |

**Rollout order:**
1. **Ship QW-1, QW-2, QW-3 immediately** — Dart-only, no native rebuild, fixes the dead tap, the banner-sanitization surface, and adds dedupe-loss observability.
2. **SI-1 (mute everywhere) + SI-4** behind a flag, with backfill — the highest-impact correctness fix.
3. **SI-3 (Android previews) + SI-5 (NSE-authoritative dedupe)** — UX parity and one-per-message.
4. **SI-2 (membership) + SI-6 (foreground fallback) + relay fanout hardening** — last, since they depend on the projection infra and relay correctness; validate with telemetry before enabling hard suppression.

---

## Effort estimate

| Item | Effort | Notes |
|---|---|---|
| QW-1 sanitized banner | **S** | One-line field swap + test |
| QW-2 dead-tap fix | **S** | SnackBar + nav + l10n string |
| QW-3 gate decode telemetry | **S** | Bundled with SI-4 |
| SI-4 gate storage relocation | **S–M** | `path_provider` + app-group on iOS |
| SI-1 mute projection (all paths) | **L** | Dart + Swift + Android + backfill + tests |
| SI-2 membership projection + relay | **L** | App-group sentinel + key delete + relay fanout + 3-party proof |
| SI-3 Android decrypt wiring | **L** | Headless bridge in isolate (or native service) |
| SI-5 NSE-authoritative dedupe | **M** | Swift marker write + Dart gate read |
| SI-6 foreground fallback decrypt+mute | **M** | Depends on SI-1 |

**Theme total: Large**, but front-loaded with **three Small quick wins that ship the same day** (QW-1/2/3) and one Small–Medium follow-up (SI-4). The remaining Large items (full mute-everywhere, Android previews, membership) are the structural P0 closure and should land behind flags with the telemetry gates above.
