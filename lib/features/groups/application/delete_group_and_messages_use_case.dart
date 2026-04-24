import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Deletes all messages for a group and then leaves it.
Future<void> deleteGroupAndMessages({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMessageRepo,
  required String groupId,
  bool deleteLocallyIfDissolved = false,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'DELETE_GROUP_AND_MESSAGES_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final deletedCount = await groupMessageRepo.deleteMessagesForGroup(groupId);
    final group = await groupRepo.getGroup(groupId);
    final shouldDeleteLocallyOnly =
        deleteLocallyIfDissolved && group?.isDissolved == true;

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_MESSAGES_PURGED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'deletedMessages': deletedCount,
        'cleanupMode': shouldDeleteLocallyOnly ? 'local_only' : 'leave',
      },
    );

    if (shouldDeleteLocallyOnly) {
      await groupRepo.removeAllMembers(groupId);
      await groupRepo.removeAllKeys(groupId);
      await groupRepo.deleteGroup(groupId);
    } else {
      await leaveGroup(bridge: bridge, groupRepo: groupRepo, groupId: groupId);
    }

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'cleanupMode': shouldDeleteLocallyOnly ? 'local_only' : 'leave',
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_GROUP_AND_MESSAGES_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
