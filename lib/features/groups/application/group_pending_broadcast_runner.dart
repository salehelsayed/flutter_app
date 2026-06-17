import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

String _safeId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Drains the durable [GroupPendingBroadcastRepository] queue by re-pushing each
/// stored (already-signed) broadcast through [rePush]. A row clears only on a
/// successful re-push; a failed re-push retains it for the next drain
/// (idempotent — the receive-side dedups by the broadcast's source message id).
class GroupPendingBroadcastRunner {
  final GroupPendingBroadcastRepository repository;

  /// Re-pushes a stored broadcast through the bridge; returns `true` on success.
  final Future<bool> Function(GroupPendingBroadcast broadcast) rePush;

  GroupPendingBroadcastRunner({required this.repository, required this.rePush});

  /// Drains every pending broadcast for [groupId]. Returns the count re-pushed.
  Future<int> drainForGroup(String groupId) =>
      _drain(() => repository.forGroup(groupId), scope: _safeId(groupId));

  /// Drains every pending broadcast across all groups (app-resume sweep).
  Future<int> drainAll() => _drain(repository.all, scope: 'all');

  Future<int> _drain(
    Future<List<GroupPendingBroadcast>> Function() load, {
    required String scope,
  }) async {
    final pending = await load();
    if (pending.isEmpty) {
      return 0;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_START',
      details: {'scope': scope, 'count': pending.length},
    );

    var drained = 0;
    for (final broadcast in pending) {
      bool pushed;
      try {
        pushed = await rePush(broadcast);
      } catch (e) {
        pushed = false;
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_PENDING_BROADCAST_REPUSH_ERROR',
          details: {
            'groupId': _safeId(broadcast.groupId),
            'error': e.toString(),
          },
        );
      }
      if (pushed) {
        await repository.remove(broadcast.id);
        drained++;
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PENDING_BROADCAST_DRAIN_DONE',
      details: {'scope': scope, 'drained': drained, 'total': pending.length},
    );
    return drained;
  }
}
