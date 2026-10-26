import 'package:flutter/foundation.dart';

/// Build-time switches for Thoughts and the 3D Orbit view (plan 407).
///
/// Both default OFF, so store builds ship without them. A dev build turns
/// them on with `--dart-define=MKNOON_ENABLE_THOUGHTS=true` and
/// `--dart-define=MKNOON_ENABLE_ORBIT_DEPTH=true`.
///
/// Thoughts off hides sharing and reading: no "+" on the own avatar, no notes,
/// no thought card, no thought notifications, and a reply to a thought reads
/// as a plain message. Friends' thoughts are still received and stored, so
/// turning the switch on later shows them.
const bool kThoughtsEnabled = bool.fromEnvironment('MKNOON_ENABLE_THOUGHTS');

/// 3D off keeps Orbit flat: nothing opens the depth view.
const bool kOrbitDepthEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_ORBIT_DEPTH',
);

/// Tests run with both on (test/flutter_test_config.dart) and switch them off
/// to prove the store build.
@visibleForTesting
bool? debugThoughtsEnabledOverride;

@visibleForTesting
bool? debugOrbitDepthEnabledOverride;

bool get thoughtsEnabled => debugThoughtsEnabledOverride ?? kThoughtsEnabled;

bool get orbitDepthEnabled =>
    debugOrbitDepthEnabledOverride ?? kOrbitDepthEnabled;
