import 'package:flutter/foundation.dart';

/// Master switch for the Orbit2 visual prototype.
///
/// When enabled, a temporary 3rd "Orbit2" tab appears beside Feed / Orbit so the
/// floating-avatars prototype can be compared against the real Orbit screen.
///
/// Orbit2 is visuals-only: mock data, no DB/backend/real messages.
///
/// Gated on [kDebugMode] (156 QW-13): the heavy-blur prototype tab is reachable
/// in debug/profile/test but absent from release builds, so it never ships to
/// TestFlight / Play. `kDebugMode` is `true` under `flutter test`, so widget
/// tests still exercise the tab.
const bool kOrbit2PrototypeEnabled = kDebugMode;
