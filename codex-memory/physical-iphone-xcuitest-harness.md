# Reusable physical-iPhone XCUITest harness

## Memory status

- Canonical reusable record for physical-iPhone permission and notification UI automation.
- Last physically verified on 2026-08-23 with an iPhone 13 running iOS 26.5.
- The Local Network authorization was reset, the real system alert appeared, and XCUITest tapped the alert-scoped `Allow` action without a user tap.
- The proof passed with `MKNOON_IOS_PERMISSION_AUTOMATED permission=local_network action=allow`.
- Device IDs, build products, DerivedData, and `.xcresult` bundles are intentionally not canonical. Rediscover the live target and produce fresh evidence on every run.

## Where the harness lives

The harness is source-controlled in layers; it is not a prebuilt binary.

1. `ios/RunnerUITests/NotificationTapUITests.swift`
   - `testAutomateLocalNetworkPermission` is the smallest physical-device permission proof.
   - `allowLocalNetworkPromptIfPresent` and `allowNotificationPromptIfPresent` classify the prompt.
   - `allowPermissionPromptIfPresent` performs the shared alert-scoped `Allow` interaction and emits the audit marker.
   - Plan 397 composes the helper through `testCreateChatGroupNotificationFixture`, `testAuthorChatGroupReactionTarget`, `testPrepareWarmNotificationTap`, and `testChatGroupNotificationTap`.
2. `integration_test/scripts/physical_device_capture_harness.dart`
   - Cross-plan capture core.
   - `PhysicalDeviceCaptureAdapter` pins the capture driver, scenario, sender, recipient, artifact directory, environment, and plan-specific arguments.
   - `runPhysicalDeviceCapture` owns subprocess launch and the developer-facing versus Sims-safe output policy.
   - Shared helpers purge every stale success/failure layout and resolve the authoritative direct/nested artifact.
   - Plan arguments cannot override `--scenario`, `--sender`, `--recipient`, or `--artifact-dir`.
3. `integration_test/scripts/run_group_reaction_notification_device.dart`
   - Public fail-closed orchestration entry point.
   - Scenario: `ios_chat_group_message_and_reaction_recipient`.
   - Creates a `PhysicalDeviceCaptureAdapter`; it no longer launches the capture child directly.
4. `integration_test/scripts/capture_group_reaction_notification_device.dart`
   - Internal capture implementation used by the public runner.
   - Builds/installs the candidates, stages fixtures, invokes the pinned XCUITest selectors, captures logs, and writes evidence.
5. `scripts/test/group_reaction_notification_device_contract_test.sh`
   - Static regression contract for runner discovery and the permission seam.
   - It requires reset -> launch -> identified alert -> alert-scoped `Allow`, and rejects global `Allow` matching.
6. `scripts/test/physical_device_capture_harness_contract_test.sh` and `test/integration/physical_device_capture_harness_test.dart`
   - Require the existing Plan 257/397, 330, 379, and 393 runners to use the shared adapter.
   - Pin routing precedence, stale-evidence removal, and authoritative artifact lookup.

Generated build products and result bundles normally live in a fresh `/tmp` directory or an explicitly supplied artifact directory. They are evidence, not the reusable harness.

## Smallest physical Local Network proof

Resolve the current device matrix first. Never reuse an old UDID merely because it appears in prior evidence.

```sh
flutter devices --machine
```

Pin the discovered physical iPhone and create fresh DerivedData. The Release configuration is deliberate: this Flutter app's Debug build expects a live debug service when launched standalone on a phone. `ENABLE_TESTABILITY=YES` lets the scheme's native tests compile while the app remains a Release-mode Flutter build.

```sh
IPHONE_DEVICE_ID='<physical-iphone-udid-from-live-inventory>'
IOS_PERMISSION_EVIDENCE_DIR="$(mktemp -d /tmp/mknoon-ios-permission.XXXXXX)"

xcodebuild -quiet \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination "platform=iOS,id=$IPHONE_DEVICE_ID" \
  -derivedDataPath "$IOS_PERMISSION_EVIDENCE_DIR/DerivedData" \
  -resultBundlePath "$IOS_PERMISSION_EVIDENCE_DIR/Result.xcresult" \
  -only-testing:RunnerUITests/NotificationTapUITests/testAutomateLocalNetworkPermission \
  ENABLE_TESTABILITY=YES \
  test
```

Pass criteria:

- exactly the pinned physical target is used;
- the test resets `.localNetwork` before launch;
- the real alert is identified by `Local Network` text;
- `Allow` is tapped inside that alert, never from a global button query;
- the alert dismisses;
- the audit marker names `permission=local_network` and `action=allow`;
- the result bundle reports the selector passed.

Run the source contract after any harness change:

```sh
bash scripts/test/group_reaction_notification_device_contract_test.sh
```

## Full Plan 397 orchestration

Use the public runner rather than invoking the capture implementation directly:

```sh
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient \
  --sender '<explicit-live-sender-device-id>' \
  --recipient '<explicit-live-iphone-udid>' \
  --artifact-dir '<fresh-durable-artifact-directory>' \
  --staging-manifest '<redacted-staging-manifest.json>'
```

The staging manifest and credentials remain external inputs and must not be copied into this memory record. The public runner owns validation and invokes the capture driver.

## How a new physical-device plan reuses the shared capture adapter

For another prompt or physical-iPhone flow, build on the existing layers instead of weakening them:

1. Keep `allowPermissionPromptIfPresent` alert-scoped.
2. Add a small permission-specific wrapper with identifying system copy and a stable marker name.
3. Add a dedicated selector that resets only that protected resource when Apple's XCTest API supports it.
4. Wire the wrapper before the first app action that can be blocked by the prompt.
5. Extend the shell contract to pin identification, ordering, and marker invariants.
6. Create a `PhysicalDeviceCaptureAdapter` in the plan runner; do not call `Process.start` or clone another runner's launch block.
7. Keep topology checks, evidence grammar, validation, and final verdicts in the plan adapter.
8. Add the selector to the capture driver's known-selector set only when the full orchestrator must invoke it.
9. Run the smallest physical proof first, then the affected end-to-end scenario.

Reuse policy:

- Reuse the shared capture core for device routing, child launch, output handling, stale-evidence purging, and artifact resolution.
- Reuse the XCUITest permission primitives for the same Apple UI boundary.
- Give each plan a thin adapter for topology, fixtures, evidence requirements, validator, and verdict vocabulary.
- Create a different capture engine only when the platform or evidence-production boundary is genuinely incompatible; even then, retain any applicable shared device and permission primitives.
- Never add a new plan by copying the entire capture harness or by adding an unbounded generic `Allow` interaction.

If a new permission uses different buttons, sheets, Settings redirection, localization, or lacks an XCTest reset API, fork the interaction rather than making the shared helper generic. Check current Apple documentation before implementing the new boundary.

## Non-negotiable safety rules

- Never query `application.buttons["Allow"]` or SpringBoard buttons globally.
- Identify the expected alert before tapping any action.
- Search both the app and SpringBoard because the visible system alert can be exposed through either automation tree.
- Fail if the identified alert appears without a hittable expected action.
- Preserve an auditable marker per permission.
- Keep Local Network handling before Notifications handling so one permission cannot be mistaken for the other.
- Treat prompt copy as localized. The verified device exposed English text; add explicit localized identification when another device language requires it.
- Use a physical device for the Local Network privacy proof. Simulator compilation is useful, but Simulator is not proof of this boundary.
- Leave the final authorization state explicit in the run report. The verified proof left Local Network access allowed.

## Apple primary references

- [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [`XCUIApplication.resetAuthorizationStatus(for:)`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/resetauthorizationstatus%28for%3A%29)
- [`XCUIProtectedResource.localNetwork`](https://developer.apple.com/documentation/xcuiautomation/xcuiprotectedresource/localnetwork)
- [Handling UI interruptions](https://developer.apple.com/documentation/xctest/handling-ui-interruptions)
- [Testing a release build](https://developer.apple.com/documentation/xcode/testing-a-release-build)
