import 'dart:async';

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

  /// Production re-pushes remove the exact row inside their membership phase,
  /// after the final inbox action. Tests and simple callers may retain the
  /// legacy runner-owned completion by leaving this false.
  final bool rePushFinalizesSuccess;

  /// One identity-safe serial tail per group. The map always points at the
  /// newest queued turn; an older completion may remove it only when it still
  /// owns that exact entry.
  final Map<String, Future<void>> _groupTails = <String, Future<void>>{};

  GroupPendingBroadcastRunner({
    required this.repository,
    required this.rePush,
    this.rePushFinalizesSuccess = false,
  });

  /// Drains every pending broadcast for [groupId]. Returns the count re-pushed.
  Future<int> drainForGroup(String groupId) => _enqueueGroupDrain(groupId);

  /// Drains every pending broadcast across all groups (app-resume sweep).
  ///
  /// The all-row read is discovery only. Every discovered group enters the
  /// same keyed path as a direct/manual drain and reloads inside its turn.
  Future<int> drainAll() async {
    final discovered = await repository.all();
    final groupIds = <String>{
      for (final broadcast in discovered) broadcast.groupId,
    };
    if (groupIds.isEmpty) return 0;
    final counts = await Future.wait(groupIds.map(_enqueueGroupDrain));
    return counts.fold<int>(0, (total, count) => total + count);
  }

  Future<int> _enqueueGroupDrain(String groupId) {
    final result = Completer<int>();
    final previous = _groupTails[groupId] ?? Future<void>.value();
    late final Future<void> current;
    current = previous.then((_) async {
      try {
        result.complete(
          await _drain(
            () => repository.forGroup(groupId),
            scope: _safeId(groupId),
          ),
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    }).whenComplete(() {
      if (identical(_groupTails[groupId], current)) {
        _groupTails.remove(groupId);
      }
    });
    _groupTails[groupId] = current;
    return result.future;
  }

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
      if (pushed && !rePushFinalizesSuccess) {
        pushed = await removeGroupPendingBroadcastIfExact(
          repository,
          broadcast,
        );
      }
      if (pushed) {
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
