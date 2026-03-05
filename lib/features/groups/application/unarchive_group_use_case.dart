import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Unarchives a group, restoring it to the active groups list.
Future<void> unarchiveGroup({
  required GroupRepository groupRepo,
  required String groupId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'UNARCHIVE_GROUP_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await groupRepo.unarchiveGroup(groupId);

    emitFlowEvent(
      layer: 'UC',
      event: 'UNARCHIVE_GROUP_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'UNARCHIVE_GROUP_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
