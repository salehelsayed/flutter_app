import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';

/// Process-wide hooks for the durable group-broadcast queue, wired by main.dart
/// to the repository/runner. No-ops until wired (and in tests that don't opt
/// in), mirroring the deferred-key-distribution sink pattern. This keeps the
/// metadata-edit producer and the banner UI from threading the repository
/// through the whole wired-widget DI chain.

Future<void> Function(GroupPendingBroadcast broadcast)? _enqueueSink;
Future<int> Function(String groupId)? _drainForGroupSink;
Future<int> Function()? _drainAllSink;
Future<int> Function(String groupId)? _countForGroupSink;

void setGroupPendingBroadcastEnqueueSink(
  Future<void> Function(GroupPendingBroadcast broadcast)? sink,
) => _enqueueSink = sink;

void setGroupPendingBroadcastDrainSinks({
  Future<int> Function(String groupId)? forGroup,
  Future<int> Function()? all,
}) {
  _drainForGroupSink = forGroup;
  _drainAllSink = all;
}

void setGroupPendingBroadcastCountSink(
  Future<int> Function(String groupId)? sink,
) => _countForGroupSink = sink;

/// Whether a durable-enqueue path is wired. The metadata-edit producer uses
/// this to choose keep-and-retry over the (S2a) revert fallback.
bool get hasGroupPendingBroadcastEnqueueSink => _enqueueSink != null;

Future<void> enqueueGroupPendingBroadcast(GroupPendingBroadcast broadcast) async {
  final sink = _enqueueSink;
  if (sink == null) return;
  await sink(broadcast);
}

/// Fire-and-forget drain of a single group's queue (e.g. on rejoin). Never
/// throws.
Future<void> triggerGroupPendingBroadcastDrainForGroup(String groupId) async {
  final sink = _drainForGroupSink;
  if (sink == null) return;
  try {
    await sink(groupId);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_TRIGGER_ERROR',
      details: {'scope': 'group', 'error': e.toString()},
    );
  }
}

/// Fire-and-forget drain across all groups (e.g. on app resume). Never throws.
Future<void> triggerGroupPendingBroadcastDrainAll() async {
  final sink = _drainAllSink;
  if (sink == null) return;
  try {
    await sink();
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_TRIGGER_ERROR',
      details: {'scope': 'all', 'error': e.toString()},
    );
  }
}

/// Count of pending broadcasts for a group, for the "changes not yet sent"
/// banner. Returns 0 when no sink is wired.
Future<int> groupPendingBroadcastCount(String groupId) async {
  final sink = _countForGroupSink;
  if (sink == null) return 0;
  return sink(groupId);
}
