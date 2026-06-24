import 'package:flutter/foundation.dart';

/// Master switch for the Orbit3 "One Circle" visual prototype.
///
/// When enabled, a temporary 4th "Orbit3" tab appears beside Feed / Orbit /
/// Orbit2. Orbit3 reproduces ONLY the One Circle view (no template selector,
/// Messages, Manage, or floating scatter) so the dense single-circle experience
/// can be iterated on without touching the shipped Orbit2 comparison.
///
/// Orbit3 is visuals-only: mock data, no DB/backend/real messages.
///
/// Gated on [kDebugMode] (156 QW-13): the experimental tab is reachable in
/// debug/profile/test but absent from release builds, so it never ships to
/// TestFlight / Play. `kDebugMode` is `true` under `flutter test`, so widget
/// tests still exercise the tab.
const bool kOrbit3PrototypeEnabled = kDebugMode;
