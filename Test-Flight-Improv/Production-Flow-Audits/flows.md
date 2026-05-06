# Flow Registry

One block per user-facing flow worth tracing through production code.
The auditor will only consider flows listed here. You curate this file by
hand. Order does not matter.

Each flow needs:
- A short slug (used as filename prefix and ledger key)
- A one-line description of what the user does and what they should see
- The **origin** — where the flow starts in the production code
- The **destination** — what the user-visible outcome is and which code
  produces it
- The **boundaries crossed** — every native/OS/external/process line the
  flow has to traverse (these are the high-suspicion zones)
- Optional **flow-files glob** — a hint about which paths the agent should
  consider "part of this flow" for the change-detection re-audit rule. If
  omitted the agent infers from origin + destination.

---

## notification-tap-to-route

**User does:** Receives a chat notification while the app is backgrounded,
taps it.

**User should see:** The tapped contact's conversation, OR the feed if the
contact has been deleted.

**Origin:** Incoming chat message arrives in
`lib/features/conversation/listeners/chat_message_listener.dart` (live)
or via the inbox-drain path when the app resumes. A local notification is
posted via `lib/core/notifications/flutter_notification_service.dart`.

**Destination:** `_handleNotificationRouteTarget` in `lib/main.dart` opens
the conversation via `_openConversationForContact`. User sees the
conversation screen for the sending peer.

**Boundaries crossed:**
- Android OS notification system → flutter_local_notifications PendingIntent
  → `MainActivity` (singleTask) → plugin's `onDidReceiveNotificationResponse`
  → Dart `_onNotificationResponse` → `onNotificationTap`
- iOS UNUserNotificationCenter → `AppDelegate` → plugin → Dart equivalent
- Plugin <-> MethodChannel(`dexterous.com/flutter/local_notifications`)

**Flow-files glob:**
- `lib/main.dart`
- `lib/core/notifications/**`
- `lib/features/push/**`
- `lib/features/conversation/listeners/chat_message_listener.dart`
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/AppDelegate.*`

---

## post-photo-upload-to-feed

**User does:** Picks a photo from the camera roll, attaches it to a post,
taps publish.

**User should see:** The post appears in the feed for nearby peers within
a few seconds, with the photo loading from the local file then from the
network for remote peers.

**Origin:** Photo picker invocation in the post-compose screen.

**Destination:** Post + photo become visible in the feed for both the
poster and remote peers.

**Boundaries crossed:**
- Native file picker (image_picker plugin) → Dart bytes/path
- `ImageProcessor.processImage()` → `flutter_image_compress` native channel
  → stripped/compressed bytes
- Local file write → DB row
- P2P broadcast / pubsub → remote peer's listener
- Remote peer: media fetch → file write → feed render

**Flow-files glob:**
- `lib/features/posts/**`
- `lib/core/media/**`
- `lib/features/feed/**`

---

## deep-link-share-receive

**User does:** Receives a shared link / image / file from another app via
the system share sheet.

**User should see:** The app opens to a screen that previews / handles the
shared content.

**Origin:** Android `intent.action.SEND` / `SEND_MULTIPLE` reaching
`MainActivity` via the manifest intent-filters; iOS share extension.

**Destination:** A handler screen in Dart that consumes the shared payload.

**Boundaries crossed:**
- Android SEND intent → MainActivity → share-handling plugin → Dart
- iOS share extension → app group → app launch / route

**Flow-files glob:**
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/mknoon/app/**`
- `ios/Share*/**`
- `lib/features/share/**` (if present)
- `lib/main.dart`
