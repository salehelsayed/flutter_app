# 73 - Session 6 Plan: iOS NSE Decrypt, Render, And Dedupe

## Scope

Implement the iOS notification-service slice:

- add a pure Swift preview resolver shared by the Notification Service
  Extension and RunnerTests
- read the 1:1 ML-KEM secret and group message keys from the shared iOS
  Keychain access group
- decrypt supported `new_message` and `group_message` ciphertext payloads via
  the Go bridge when the extension target can import `GoMknoon`
- rewrite notification title, body, and thread identifier from decrypted
  plaintext only
- degrade to the existing static fallback alert on missing keys, corrupt
  payloads, unsupported kinds, duplicate message IDs, or unavailable bridge
  linkage
- mirror push-decrypt secrets from the app's existing secure store into the
  shared access group without moving the primary app keychain store
- add focused Swift and Dart tests for parity, fallback, and dedupe behavior

## Code Entry Points

- `ios/NotificationService/NotificationService.swift`
- `ios/NotificationService/NotificationPreviewResolver.swift`
- `ios/RunnerTests/NotificationPreviewResolverTests.swift`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Podfile`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/main.dart`
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `test/features/groups/domain/repositories/group_repository_impl_test.dart`

## Tests And Gates

Focused verification:

- `dart format` on touched Dart files and tests
- `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart`
- `plutil -lint ios/Runner.xcodeproj/project.pbxproj ios/NotificationService/Info.plist ios/NotificationService/NotificationService.entitlements`
- `cd ios && pod install`
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme NotificationService -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- focused RunnerTests Xcode run for `NotificationPreviewResolverTests`

## Done Criteria

- The extension decrypts committed 1:1 and group fixtures through an injected
  decryptor in tests and through `GoMknoon` in production builds where the pod
  is available.
- The extension reads only ciphertext route data from the APNs payload and
  renders plaintext previews only after decrypt succeeds.
- Missing keys, invalid plaintext, duplicate message IDs, and unsupported
  payloads preserve the static fallback copy without leaking route metadata.
- Shared key material is mirrored into the iOS App Group keychain for 1:1 and
  group pushes while the app's existing primary secure store remains unchanged.

## Closure Evidence

- `dart format` completed for touched Dart repositories and tests.
- `flutter test test/features/identity/domain/repositories/identity_repository_impl_test.dart test/features/groups/domain/repositories/group_repository_impl_test.dart`
  passed.
- Runner, NotificationService, and Xcode project plist lint passed.
- `cd ios && pod install` completed; the only remaining CocoaPods warning is
  the pre-existing Runner base-configuration warning.
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme NotificationService -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
  passed. The older project-only target build is no longer the correct gate
  because the extension now links `GoMknoon` through CocoaPods.
- Focused
  `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests`
  passed all five resolver tests.

## Scope Guard

- Do not implement dashboards or degrade-rate gates; those are Session 7.
- Do not broaden this session into full simulator smoke coverage; that is
  Session 8.
- Do not remove legacy compatibility paths; that is Session 9 after acceptance
  evidence exists.
