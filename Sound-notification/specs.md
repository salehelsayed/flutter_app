You do NOT have custom notification sounds implemented. Here's what exists and what doesn't:

  What you have

  - firebase_messaging package (v15.1.6) in pubspec.yaml — this handles push notification permission requests and (potentially) receiving remote push notifications.
  - requestPushPermission() use case — requests notification permission with sound: true, meaning you ask iOS for permission to play sounds with notifications.

  What you don't have

  - No custom sound files — there are no .aiff, .caf, .wav, or .m4a files in the project (these are the formats iOS supports for custom notification sounds).
  - No flutter_local_notifications package — this is what you'd typically use to trigger local notifications (with sound) when a message arrives while the app is in the foreground/background.
  - No GoogleService-Info.plist — Firebase isn't fully configured for iOS, so remote push notifications via FCM aren't wired up either.
  - No notification presentation logic — the ChatMessageListener broadcasts messages to the UI via streams, but never triggers an OS-level notification.

  What would happen on iPhone today

  When the app is in the foreground, incoming messages update the UI via streams — no system notification, no sound. When the app is in the background or killed, there would be no notification at all because there's no push notification
   delivery pipeline configured.

  How notification sounds work on iOS (for context)

  - Default sound: If you send a push notification (via APNs/FCM) with "sound": "default", iOS plays the built-in tri-tone alert sound.
  - Custom sound: You bundle a sound file (.caf, .aiff, .wav, max 30 seconds) in your app bundle and reference it by filename in the notification payload. iOS plays that instead.
  - You decide: The sound is entirely your choice — Apple doesn't impose a specific sound. You'd pick or create one that fits your app's brand.

  What you'd need to implement

  1. A push notification backend (or configure FCM properly with GoogleService-Info.plist)
  2. flutter_local_notifications for foreground/local notifications
  3. Optionally, a custom .caf sound file bundled in ios/Runner/ if you want a branded sound instead of the iOS default

  ---

  I waill use the deafult:
  . When you trigger a notification on iOS, you can simply specify "default" as the sound, and iOS will play its built-in system notification sound (the standard tri-tone alert). Every iOS app that doesn't bundle a custom sound uses
  this.

  In practice, how you specify it depends on the notification path:

  - FCM payload: "sound": "default" in the notification body
  - flutter_local_notifications: DarwinNotificationDetails(sound: 'default') (or just leave it as the default — it plays the system sound automatically)
  - APNs directly: "sound": "default" in the aps dictionary

  No file to bundle, no configuration needed — iOS handles it. It's the same sound you hear from most apps (Messages, Mail, etc. all use variations of system sounds).

  So when you get to implementing local/push notifications, you can just use "default" and you're good. You can always swap in a custom .caf file later if you want a branded sound.

  ---
   Key Design Decisions
│
│ 1. No custom sound files — both platforms use system default sound (playSound: true / presentSound: true)
│ 2. FCM remains silent — setForegroundNotificationPresentationOptions stays false for all; FCM is inbox-wakeup only
│ 3. One notification per conversation — notificationId = contactPeerId.hashCode updates existing notification rather than stacking
│ 4. Optional params everywhere — backward compatible, existing tests untouched
│ 5. No iOS AppDelegate changes needed — FlutterAppDelegate already sets UNUserNotificationCenter.delegate