import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/utils/group_key_rotation_leader.dart';

/// Re-keys groups whose latest key is older than a member removal in their
/// timeline. The key rotation leader (the creator while eligible, see
/// [groupKeyRotationLeaderPeerId]) does it; if the leader stays offline, the
/// next member allowed to rotate takes over after [takeoverStep], and so on.
///
/// Go refuses a new key while the previous one is in its grace window
/// (`GROUP_KEY_GRACE_ACTIVE`, 10 minutes), so a removal inside that window is
/// applied without a rotation and the removed member keeps the key in use; the
/// app may also stop before a removal's rotation. The owed state is derived
/// from stored rows, so it survives restarts, and one rotation covers every
/// removal since the latest key. A rotation still inside the grace window is
/// refused and retried on the next sweep.
class GroupOwedKeyRotationSweeper {
  GroupOwedKeyRotationSweeper({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    required Future<String?> Function() resolveSelfPeerId,
    required Future<bool> Function(String groupId) rotate,
    required Future<bool> Function({
      required String operation,
      Map<String, dynamic>? data,
    })
    allowsSideEffects,
    DateTime Function()? now,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _resolveSelfPeerId = resolveSelfPeerId,
       _rotate = rotate,
       _allowsSideEffects = allowsSideEffects,
       _now = now ?? DateTime.now;

  static const interval = Duration(minutes: 1);

  /// A removal younger than this is still being re-keyed by its own flow;
  /// judging it now would race that rotation and rotate twice.
  static const removalSettle = Duration(minutes: 1);

  /// How long each member in the rotation order waits for the ones before it
  /// (the leader first) before it takes over an owed rotation. Longer than
  /// Go's 10-minute key grace window, so an online leader whose rotation is
  /// still refused by that window rotates before anyone takes over.
  static const takeoverStep = Duration(minutes: 15);

  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final Future<String?> Function() _resolveSelfPeerId;
  final Future<bool> Function(String groupId) _rotate;
  final Future<bool> Function({
    required String operation,
    Map<String, dynamic>? data,
  })
  _allowsSideEffects;
  final DateTime Function() _now;
  Timer? _timer;
  bool _running = false;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _timer ??= Timer.periodic(interval, (_) => unawaited(sweep()));
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> sweep() async {
    if (_running || _stopped) return;
    _running = true;
    try {
      final selfPeerId = await _resolveSelfPeerId();
      if (selfPeerId == null) return;
      final now = _now().toUtc();
      for (final group in await _groupRepo.getAllGroups()) {
        if (_stopped) return;
        if (group.isDissolved) continue;
        final members = await _groupRepo.getMembers(group.id);
        // 0 = the leader; a later position takes over only after the members
        // before it had their turns (they stayed offline).
        final position = groupKeyRotationOrderPeerIds(
          group: group,
          members: members,
        ).indexOf(selfPeerId);
        if (position < 0) continue;
        if (!members.any((m) => m.peerId == selfPeerId) ||
            !members.any((m) => m.peerId != selfPeerId)) {
          continue;
        }
        final latestKey = await _groupRepo.getLatestKey(group.id);
        if (latestKey == null) continue;
        final keyAt = latestKey.createdAt.toUtc();
        final removalPrefix = 'sys-member_removed:${group.id}:';
        // A removal is judged once it has settled (its own rotation had time
        // to run), and a removal stamped later than this device's clock not
        // until the clock passes it, so a skewed remote stamp can cost at
        // most one extra rotation.
        final settledBefore = now.subtract(
          removalSettle + takeoverStep * position,
        );
        final owed = (await _msgRepo.getMessagesPage(group.id, limit: 200)).any(
          (m) =>
              m.id.startsWith(removalPrefix) &&
              m.timestamp.toUtc().isAfter(keyAt) &&
              !m.timestamp.toUtc().isAfter(settledBefore),
        );
        if (!owed) continue;
        if (!await _allowsSideEffects(
          operation: 'group_creator_owed_rekey',
          data: {'groupId': group.id},
        )) {
          continue;
        }
        if (position > 0) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_KEY_ROTATION_TAKEOVER',
            details: {
              'groupId': group.id.length > 8
                  ? group.id.substring(0, 8)
                  : group.id,
              'position': position,
              'keyGeneration': latestKey.keyGeneration,
            },
          );
        }
        final rotated = position == 0
            ? await _rotate(group.id)
            : await runZoned(
                () => _rotate(group.id),
                zoneValues: {groupKeyRotationTakeoverZoneKey: group.id},
              );
        emitFlowEvent(
          layer: 'FL',
          event: rotated
              ? 'GROUP_CREATOR_OWED_REKEY_ROTATED'
              : 'GROUP_CREATOR_OWED_REKEY_DEFERRED',
          details: {
            'groupId': group.id.length > 8
                ? group.id.substring(0, 8)
                : group.id,
            'keyGeneration': latestKey.keyGeneration,
          },
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CREATOR_OWED_REKEY_ERROR',
        details: {'error': error.toString()},
      );
    } finally {
      _running = false;
    }
  }
}
