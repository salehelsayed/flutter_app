# 73 - Session 5 Plan: iOS Key Access And NSE Foundation

## Scope

Implement the iOS prerequisite slice:

- make `FlutterSecureKeyStore` accept an optional Apple Keychain access group
- expose the shared group constant so Runner and the future NSE use one value
- add Notification Service Extension skeleton source, Info.plist, and
  entitlements files with App Group and Keychain sharing configured
- wire the NotificationService as a real Xcode app-extension target embedded
  by Runner
- add tests/lints that verify the Dart secure-store option and iOS plist
  artifacts

## Code Entry Points

- `lib/core/secure_storage/flutter_secure_key_store.dart`
- `test/core/secure_storage/flutter_secure_key_store_test.dart`
- `ios/Runner/Runner.entitlements`
- `ios/NotificationService/`
- `ios/RunnerTests/NotificationServiceConfigurationTests.swift`

## Tests And Gates

Focused verification:

- `flutter test test/core/secure_storage/flutter_secure_key_store_test.dart`
- `plutil -lint ios/Runner/Runner.entitlements ios/NotificationService/NotificationService.entitlements ios/NotificationService/Info.plist`
- `plutil -lint ios/Runner.xcodeproj/project.pbxproj`
- `xcodebuild -project ios/Runner.xcodeproj -target NotificationService -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationServiceConfigurationTests`

## Done Criteria

- Secure key storage can be constructed with the shared Apple access group.
- Runner and NotificationService entitlements include matching App Group and
  Keychain access group values.
- NotificationService has a minimal compilable app-extension target for
  Session 6 to fill in with decrypt/render logic.

## Closure Evidence

- `flutter test test/core/secure_storage/flutter_secure_key_store_test.dart`
  passed.
- Runner, NotificationService, and Xcode project plist lint passed.
- `xcodebuild -list -project ios/Runner.xcodeproj` lists
  `NotificationService` as a target and scheme.
- Standalone `NotificationService` simulator build passed with code signing
  disabled.
- Focused `NotificationServiceConfigurationTests` Xcode run passed on the
  booted iPhone 17 simulator.

## Scope Guard

- Do not implement NSE decrypt/render logic in this session.
- Do not wire telemetry or simulator smoke in this session.
