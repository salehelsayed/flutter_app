import 'package:flutter/foundation.dart';

/// Kill switch for the SE-41 update check.
///
/// `--dart-define=MKNOON_UPDATE_CHECK=on|off`. When unset: on in release and
/// profile builds, off in debug. Always off in E2E builds
/// (`E2E_TEST_MODE=true`) and SIMS builds (non-empty `SIMS_BUILD_PROFILE_ID`)
/// unless an approved debug fixture profile explicitly opts in.
/// Off means no network request AND no enforcement (decision none).
///
/// Store builds must not ship with it off: the release scripts refuse
/// `MKNOON_UPDATE_CHECK=off` (scripts/check_update_check_release_defines.py).
class UpdateCheckSwitch {
  const UpdateCheckSwitch({
    required this.mode,
    required this.isDebugBuild,
    required this.e2eTestMode,
    required this.simsBuildProfileId,
    this.testProfileOptIn = false,
  });

  factory UpdateCheckSwitch.fromEnvironment() => const UpdateCheckSwitch(
    mode: String.fromEnvironment('MKNOON_UPDATE_CHECK'),
    isDebugBuild: kDebugMode,
    e2eTestMode: bool.fromEnvironment('E2E_TEST_MODE'),
    simsBuildProfileId: String.fromEnvironment('SIMS_BUILD_PROFILE_ID'),
    testProfileOptIn: bool.fromEnvironment('MKNOON_SE41_TEST_PROFILE'),
  );

  final String mode;
  final bool isDebugBuild;
  final bool e2eTestMode;
  final String simsBuildProfileId;
  final bool testProfileOptIn;

  /// Validates the test source before either foreground or background uses it.
  bool get testProfileEnabled {
    if (testProfileOptIn) {
      if (!isDebugBuild ||
          !e2eTestMode ||
          !const {
            'android.e2e.production_call_local',
            'ios.simulator.app',
          }.contains(simsBuildProfileId)) {
        throw StateError(
          'SE41 fixture opt-in requires an approved debug E2E profile.',
        );
      }
      return true;
    }
    return false;
  }

  bool get enabled {
    if (testProfileEnabled) return mode.trim().toLowerCase() == 'on';
    if (e2eTestMode || simsBuildProfileId.isNotEmpty) return false;
    switch (mode.trim().toLowerCase()) {
      case 'on':
        return true;
      case 'off':
        return false;
      default:
        // Unset (or an unknown value): the build type decides.
        return !isDebugBuild;
    }
  }
}
