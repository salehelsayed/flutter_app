# Dead Dependencies & Config Bloat Analysis

## Summary

The project is **very clean**. Only 1 dependency is clearly unused. Script/config bloat is low, and the optional script removal is not urgent.

---

## Dead Dependencies

### Confirmed UNUSED

| Package | Status | Impact | Action |
|---------|--------|--------|--------|
| **cupertino_icons** | DEAD | ~30KB | **REMOVE** from `pubspec.yaml` — no `CupertinoIcons` imports found in `lib/`, `test/`, or `integration_test/` |

### All Other Dependencies — CONFIRMED USED

| Package | Usage |
|---------|-------|
| intl | Localization (l10n) |
| sqflite_sqlcipher | Database encryption |
| sqlcipher_flutter_libs | Platform binaries |
| flutter_secure_storage | iOS Keychain / Android EncryptedSharedPreferences |
| qr_flutter | QR code generation |
| image_picker | Conversation, settings, FTE screens |
| path_provider | File path management |
| path | Path utilities |
| mobile_scanner | QR scanning |
| flutter_svg | SVG navigation icons |
| uuid | Message/group ID generation |
| just_audio | Audio playback |
| flutter_image_compress | Image compression + EXIF stripping |
| crypto | Local media server / sender logic |
| url_launcher | Linkable text widget |
| video_compress | Video compression |
| record | Voice message recording |
| firebase_core | Firebase init |
| firebase_messaging | Push notifications |
| flutter_local_notifications | Local notification display |
| receive_sharing_intent | iOS share extension |
| sqflite_common_ffi | SQLite FFI for tests/desktop |
| bonsoir | Bonjour / mDNS discovery |
| geolocator | Nearby-post location features |

### Dev Dependencies — All USED

| Package | Usage |
|---------|-------|
| flutter_test | Standard testing |
| integration_test | Device integration tests |
| fake_async | Async control in tests |
| just_audio_platform_interface | Conversation audio tests |
| flutter_lints | Linting |

### Dependency Overrides — All NECESSARY

| Override | Reason |
|----------|--------|
| `record_linux → ^1.3.0` | Package version conflict workaround; Linux is not a shipping target here |

---

## Duplicate/Overlap Check

| Group | Packages | Verdict |
|-------|----------|---------|
| Audio | `just_audio` + `record` | Complementary, not duplicates |
| Compression | `flutter_image_compress` + `video_compress` | Purpose-specific, not duplicates |
| Notifications | `firebase_messaging` + `flutter_local_notifications` | Complementary (remote + local) |
| Storage | `sqflite_sqlcipher` + `flutter_secure_storage` | Different layers (DB vs secrets) |
| Discovery | `bonsoir` + `geolocator` | Different purposes (WiFi vs location) |

**No obviously deprecated packages detected.**

---

## Scripts Audit

| Script | Status | Recommendation |
|--------|--------|---------------|
| `build_ios_appstore_ipa.sh` | ACTIVE | KEEP |
| `check_push_release_gate.sh` | ACTIVE | KEEP |
| `ensure_go_android_bindings.sh` | ACTIVE | KEEP |
| `ensure_go_ios_bindings.sh` | ACTIVE | KEEP |
| `ensure_go_macos_bindings.sh` | ACTIVE | KEEP |
| `ensure_xcode_project_pods.sh` | ACTIVE | KEEP |
| `reset_ios_native_assets_cache.sh` | ACTIVE (critical) | KEEP |
| `verify_gomobile_bindings.sh` | ACTIVE | KEEP |
| `launch_ios_device_console.sh` | Dev convenience only | OPTIONAL REMOVE |

---

## Config Audit

- **iOS Info.plist:** No obvious bloat found
- **Android build.gradle.kts:** No obvious config bloat found
- **Assets:** Current SVG/icon usage appears justified

---

## Action Items

| Priority | Item | Effort |
|----------|------|--------|
| **HIGH** | Remove `cupertino_icons` from `pubspec.yaml` | 1 min |
| LOW | Remove `launch_ios_device_console.sh` only if the team no longer wants the convenience script | 1 min |
