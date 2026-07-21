import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/leave_group_and_delete_local_history_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Installs the old end-to-end exit implementation behind the new mandatory
/// coordinator boundary for UI preservation tests.
///
/// Production never uses this fixture. It lets pre-Plan-264 widget tests keep
/// proving signed prework, native failure, and cleanup outcomes without
/// granting the widget a raw/native fallback when the coordinator is absent.
void installLegacyGroupExitCoordinatorFixture({
  required Bridge bridge,
  required GroupRepository groupRepository,
  required GroupMessageRepository? messageRepository,
  required IdentityRepository identityRepository,
  Future<bool> Function(String peerId, String message)? sendP2PMessage,
  Future<bool> Function(String peerId, String message)? storeP2PMessageInInbox,
  Future<List<GroupPendingBroadcast>> Function(String groupId)?
  loadPendingBroadcasts,
}) {
  final action = LeaveGroupAndDeleteLocalHistoryUseCase(
    bridge: bridge,
    groupRepo: groupRepository,
    groupMessageRepo: messageRepository,
    identityRepo: identityRepository,
    sendP2PMessage: sendP2PMessage,
    storeP2PMessageInInbox: storeP2PMessageInInbox,
    loadPendingBroadcasts: loadPendingBroadcasts,
  );

  Future<GroupExitIntentRequestResult> run(String groupId) async {
    final result = await action.call(groupId);
    return switch (result.status) {
      LeaveGroupAndDeleteLocalHistoryStatus.blockedLastAdmin =>
        GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.blockedLastAdmin,
          cause: result.cause,
        ),
      LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed ||
      LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveFailed ||
      LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveUncertain =>
        GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.failed,
          cause: result.cause,
        ),
      LeaveGroupAndDeleteLocalHistoryStatus.left ||
      LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete =>
        GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.started,
          cause: result.cause,
        ),
    };
  }

  setGroupExitIntentActionSinks(
    requestLeave: run,
    queueLeaveWhenSyncCompletes: run,
    retry: run,
  );
}
