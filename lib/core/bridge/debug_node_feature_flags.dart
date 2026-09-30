import 'package:flutter/foundation.dart';

Map<String, bool> _overrides = const {};

/// Debug-build-only node feature-flag overrides for production journeys that
/// need a controlled network precondition (catalog NW-002 relay-only Bob).
/// Always empty in release and profile builds.
Map<String, bool> get debugNodeFeatureFlagOverrides =>
    kDebugMode ? _overrides : const {};

set debugNodeFeatureFlagOverrides(Map<String, bool> overrides) {
  if (!kDebugMode) {
    throw StateError('node feature-flag overrides are debug-only');
  }
  _overrides = Map.unmodifiable(overrides);
}
