import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';

/// Loads active groups with their latest message and unread count,
/// sorted by most recent activity first.
///
/// This drives group rows in the Orbit screen alongside friend rows.
Future<List<OrbitGroup>> loadOrbitGroups({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_ORBIT_GROUPS_START',
    details: {},
  );

  try {
    final groups = await groupRepo.getActiveGroups();
    final orbitGroups = <OrbitGroup>[];

    for (final group in groups) {
      final latestMessage = await msgRepo.getLatestMessage(group.id);
      final unreadCount = await msgRepo.getUnreadCount(group.id);

      orbitGroups.add(OrbitGroup(
        group: group,
        latestMessage: latestMessage != null
            ? '${latestMessage.senderUsername ?? 'Unknown'}: ${latestMessage.text}'
            : null,
        unreadCount: unreadCount,
        lastActivityTimestamp: latestMessage?.timestamp ?? group.createdAt,
      ));
    }

    orbitGroups.sort((a, b) {
      final aTime =
          a.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      final bTime =
          b.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
      return bTime.compareTo(aTime);
    });

    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUPS_SUCCESS',
      details: {'count': orbitGroups.length},
    );

    return orbitGroups;
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUPS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
