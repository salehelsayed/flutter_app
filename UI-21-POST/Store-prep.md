  Critical Blockers

  Android (Google Play)

  1. Signing keystore — android/key.properties is missing. You need to:
    - Generate a release keystore: keytool -genkey -v -keystore upload-keystore.jks -keyalg
   RSA -keysize 2048 -validity 10000 -alias upload
    - Create android/key.properties with storeFile, storePassword, keyAlias, keyPassword
  2. Firebase config — android/app/google-services.json is missing. Download it from
  Firebase Console.
  3. ProGuard rules — No proguard-rules.pro exists. Recommended for release builds (code
  shrinking/obfuscation).

  iOS (App Store)

  4. Development Team ID — DEVELOPMENT_TEAM is empty ("") in the Xcode project. Set it to
  your Apple Developer Team ID.
  5. Provisioning profiles — Set up App Store distribution profiles in your Apple Developer
   account.

  ---
  High Priority

  6. Privacy Policy — Both stores require a published privacy policy URL. You have draft
  questions in Privacy-Policy/ but no final document.
  7. Terms of Service — Not found. Apple requires this for many app types.
  8. pubspec.yaml — Name is still flutter_app and description is "A new Flutter project." —
   update both.

  ---
  Store Listing Assets Needed

  9. App Store screenshots — You have 16 screenshots in UI-21-POST/screenshots/ but verify
  they meet size requirements:
    - Google Play: 16:9 or 9:16, min 320px, max 3840px
    - App Store: exact pixel sizes per device (6.7", 6.5", 5.5" iPhones, iPad)
  10. Store descriptions — Short description, full description, keywords, category
  11. Feature graphic (Android) — 1024x500 banner required for Play Store
  12. App Store metadata — Support URL, marketing URL, age rating questionnaire

  ---
  Already Done (good shape)

  - App ID: com.mknoon.app on both platforms
  - App icons: complete sets for all Android densities and iOS sizes
  - Launch screen configured (iOS)
  - Permissions with privacy descriptions (camera, mic, photos, location)
  - Version: 1.0.0+1
  - Share extension (iOS) with entitlements
  - Firebase integration (code-side)

  ---
  Would you like help with any specific item — like generating the keystore, creating
  proguard rules, writing the privacy policy, or setting up the Xcode signing?