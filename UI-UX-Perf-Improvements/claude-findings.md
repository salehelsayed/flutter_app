 Additional findings from deep research

  Two more CRITICAL items:

  iOS bundle ID is also placeholder:
  com.example.makerGenerated — same problem as Android. Both
  platforms need real bundle IDs.

  Firebase config files missing: No GoogleService-Info.plist
  (iOS) or google-services.json (Android) found in the repo.
  Push notifications (which you already have
  firebase_messaging wired up for) won't work without these.

  Additional HIGH items:

  No getInitialMessage() for cold-start notification taps: If
   a user taps a notification while the app is killed, the
  notification payload is lost. You need
  FirebaseMessaging.instance.getInitialMessage() at startup.

  iOS Privacy Manifest missing: iOS 17+ requires
  PrivacyInfo.xcprivacy declaring which privacy APIs you use.
   Apple will reject without it.

  ---
  Revised consolidated priority list

  ┌──────────┬───────────────────────────────────┬────────┐
  │ Priority │               Item                │ Effort │
  ├──────────┼───────────────────────────────────┼────────┤
  │ BLOCKER  │ Custom app icon (both platforms — │ 2-3h   │
  │          │  still default Flutter "F")       │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │          │ Real bundle IDs (iOS:             │        │
  │ BLOCKER  │ com.example.makerGenerated,       │ 5 min  │
  │          │ Android: com.example.flutter_app) │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ BLOCKER  │ Android release signing           │ 30 min │
  │          │ (currently debug keys)            │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │          │ Launch screen: black bg + logo    │        │
  │ BLOCKER  │ (currently white bg + 1x1px       │ 1h     │
  │          │ transparent image)                │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ BLOCKER  │ Privacy policy URL (required by   │ 1-2h   │
  │          │ both stores)                      │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │          │ Firebase config files             │        │
  │ BLOCKER  │ (GoogleService-Info.plist +       │ 15 min │
  │          │ google-services.json)             │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ iOS Privacy Manifest              │ 30 min │
  │          │ (PrivacyInfo.xcprivacy)           │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ Fix or remove dead "Remember" nav │ 15 min │
  │          │  tab                              │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ Consistent display name (mknoon   │ 5 min  │
  │          │ vs MKnoon)                        │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ Add crash reporting (Crashlytics  │ 1h     │
  │          │ — you already have firebase_core) │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ Branded startup/loading screen    │ 30 min │
  │          │ (currently generic lock icon)     │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ HIGH     │ Handle cold-start notification    │ 15 min │
  │          │ (getInitialMessage())             │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ MEDIUM   │ Haptic feedback on key actions    │ 1h     │
  ├──────────┼───────────────────────────────────┼────────┤
  │          │ User-friendly error messages      │        │
  │ MEDIUM   │ (hide stack traces from           │ 1h     │
  │          │ SnackBars)                        │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ MEDIUM   │ Camera permission check before QR │ 15 min │
  │          │  scanner opens                    │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ MEDIUM   │ Send button debounce (prevent     │ 15 min │
  │          │ duplicate messages)               │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ MEDIUM   │ Clean dead TODOs in               │ 10 min │
  │          │ core/services/ stubs              │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ LOW      │ Accessibility (Semantics on       │ 2-3h   │
  │          │ interactive elements)             │        │
  ├──────────┼───────────────────────────────────┼────────┤
  │ LOW      │ Connection count hidden from      │ 5 min  │
  │          │ users ("Online (3)" → "Online")   │        │
  └──────────┴───────────────────────────────────┴────────┘