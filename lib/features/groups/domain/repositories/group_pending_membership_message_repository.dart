import '../models/group_pending_membership_message.dart';

abstract class GroupPendingMembershipMessageRepository {
  Future<GroupPendingMembershipMessage> savePendingMessage(
    GroupPendingMembershipMessage message,
  );

  Future<List<GroupPendingMembershipMessage>> getPendingMessages({
    int limit = 200,
  });

  Future<List<GroupPendingMembershipMessage>>
  getPendingMessagesForGroupAndSenders({
    required String groupId,
    required Iterable<String> senderPeerIds,
    int limit = 50,
  });

  Future<void> deletePendingMessage(String id);

  Future<void> deletePendingMessageByGroupAndMessageId({
    required String groupId,
    required String messageId,
  });

  Future<void> pruneGroup(String groupId, {required int maxRows});
}
