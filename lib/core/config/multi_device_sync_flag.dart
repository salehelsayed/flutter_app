/// Build-time feature flag gating the same-user multi-device group convergence
/// build (Part B of `Test-Flight-Improv/.../12-P2-multi-device-honesty.md`).
///
/// Default-OFF. Enable in a build with
/// `--dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true`.
///
/// Until this flag is on AND the convergence build (sibling-device admission,
/// restore-time key continuity, peer hydration) is verified on a real device
/// matrix, the group multi-device contract is *device-local only*: a freshly
/// restored second device does not hydrate group state or keys. The policy
/// `isGroupMultiDeviceImplemented` helper and the policy contract test key off
/// this flag so the UX-013 matrix claim cannot be re-closed ahead of runtime
/// reality.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern (see
/// `lib/core/debug/e2e_test_mode.dart`). Omitting `defaultValue` yields `false`.
const bool kMultiDeviceSyncEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_MULTI_DEVICE_SYNC',
);
