# Push Notifications Phase 6 Hardening Gate

Prepared on: 2026-03-22  
Plan reference: `Network-Arch/Push-Notifications-1to1-Group-TDD-Plan.md`

## Repo-Locked Values

- Firebase iOS project: `mknoon-c6e62`
- iOS bundle id: `com.mknoon.app`
- Required iOS background modes:
  - `fetch`
  - `remote-notification`
- Required APNs entitlement:
  - `aps-environment = production`

These values come from:

- `ios/Runner/GoogleService-Info.plist`
- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`

## Automated Gate

Prior phases must already be green. Phase 6 adds the release-config checks:

```bash
flutter test --no-pub test/features/push/application/ios_push_project_config_test.dart
./scripts/check_push_release_gate.sh
```

If you have the deployment service account locally or on the relay host:

```bash
FIREBASE_SERVICE_ACCOUNT=/etc/mknoon/firebase-service-account.json \
  ./scripts/check_push_release_gate.sh --require-service-account
```

Expected result:

- repo config checks pass
- service account `project_id` matches `mknoon-c6e62`

## Firebase Console Checklist

- Open Firebase Console for project `mknoon-c6e62`.
- Confirm the iOS app bundle is `com.mknoon.app`.
- Confirm an APNs auth key is uploaded under Cloud Messaging for the iOS app.
- Do not ship if the APNs key is missing or belongs to a different Firebase project.

## Relay Deployment Checklist

- `FIREBASE_SERVICE_ACCOUNT` is set for the relay service.
- The JSON at that path contains `"project_id": "mknoon-c6e62"`.
- Relay startup log shows push is enabled.

Expected relay log markers during smoke:

- startup: `Push:       enabled`
- token registration: `[PUSH] Token registered for ... (ios)`
- 1:1 delivery: `[PUSH] Notification sent to ...`
- group delivery: `[PUSH] Group notification sent to ...`

Useful commands on the relay host:

```bash
echo "$FIREBASE_SERVICE_ACCOUNT"
grep -n '"project_id"' "$FIREBASE_SERVICE_ACCOUNT"
sudo journalctl -u relay-server -n 200 | rg 'Push:|\\[PUSH\\]'
sudo journalctl -u relay-server -f
```

## Xcode / Apple Checklist

- Push Notifications capability enabled for `Runner`
- Background Modes enabled for `Runner`
- `fetch` present in `UIBackgroundModes`
- `remote-notification` present in `UIBackgroundModes`
- TestFlight archive signed with production APNs entitlement

Repo-side files to verify:

- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`

## Manual Smoke Matrix

Run on at least one physical iPhone with the TestFlight build installed.

1. Firebase console direct send to the device FCM token
   - Expected: visible notification while the app is backgrounded.
2. 1:1 message with recipient app backgrounded
   - Expected: relay logs iOS token registration and push send success.
   - Expected: visible push.
   - Expected: tap opens the correct conversation with the new message visible.
3. 1:1 message with recipient app terminated but not force-quit
   - Expected: same as step 2.
4. Group message with one member backgrounded
   - Expected: relay stores group inbox once and sends group push to that member.
   - Expected: visible push.
   - Expected: tap opens the correct group with the new message visible.
5. Group message with one member terminated but not force-quit
   - Expected: same as step 4.
6. Resume after successful token registration
   - Expected: no duplicate token-refresh listener behavior.

## Release Blockers

Do not ship if any of these are true:

- Firebase project does not match `mknoon-c6e62`
- APNs auth key is missing in Firebase Console
- relay service account project does not match the app Firebase project
- startup logs do not show push enabled
- TestFlight smoke fails for either 1:1 or group push open

## iOS Caveat

If the user force-quits or swipes the app away from the iOS app switcher,
background delivery will not resume until the app is opened again. QA should
treat that as a platform constraint, not a product bug.
