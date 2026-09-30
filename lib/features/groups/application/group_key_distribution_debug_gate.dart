import 'package:flutter/foundation.dart';

/// Called before a rotated group key is sent to one recipient.
typedef GroupKeyDistributionDebugGate =
    Future<void> Function(String groupId, String recipientPeerId);

GroupKeyDistributionDebugGate? _gate;

/// Debug-build-only seam for production journeys that must interleave a
/// publish with a key distribution (catalog ST-006). It is only readable and
/// settable in debug builds, so release and profile builds never run a gate.
GroupKeyDistributionDebugGate? get debugGroupKeyDistributionGate =>
    kDebugMode ? _gate : null;

set debugGroupKeyDistributionGate(GroupKeyDistributionDebugGate? gate) {
  if (!kDebugMode) {
    throw StateError('group key distribution gate is debug-only');
  }
  _gate = gate;
}
