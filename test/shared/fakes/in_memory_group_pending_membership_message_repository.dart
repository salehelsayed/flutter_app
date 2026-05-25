import 'package:flutter_app/features/groups/domain/models/group_pending_membership_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_membership_message_repository.dart';

class InMemoryGroupPendingMembershipMessageRepository
    implements GroupPendingMembershipMessageRepository {
  final Map<String, GroupPendingMembershipMessage> _messages = {};

  List<GroupPendingMembershipMessage> get messages {
    final rows = _messages.values.toList()
      ..sort((a, b) {
        final byReceivedAt = a.receivedAt.compareTo(b.receivedAt);
        return byReceivedAt != 0 ? byReceivedAt : a.id.compareTo(b.id);
      });
    return rows;
  }

  @override
  Future<GroupPendingMembershipMessage> savePendingMessage(
    GroupPendingMembershipMessage message,
  ) async {
    GroupPendingMembershipMessage? existing;
    for (final row in _messages.values) {
      if (row.groupId == message.groupId &&
          row.messageId != null &&
          row.messageId!.isNotEmpty &&
          row.messageId == message.messageId) {
        existing = row;
        break;
      }
    }
    if (existing != null) {
      final merged = existing.copyWith(
        senderPeerId: message.senderPeerId,
        messageId: message.messageId,
        payloadJson: message.payloadJson,
        receivedAt: message.receivedAt,
        updatedAt: message.updatedAt,
      );
      _messages[existing.id] = merged;
      return merged;
    }
    _messages[message.id] = message;
    return message;
  }

  @override
  Future<List<GroupPendingMembershipMessage>> getPendingMessages({
    int limit = 200,
  }) async {
    return messages.take(limit).toList(growable: false);
  }

  @override
  Future<List<GroupPendingMembershipMessage>>
  getPendingMessagesForGroupAndSenders({
    required String groupId,
    required Iterable<String> senderPeerIds,
    int limit = 50,
  }) async {
    final senders = senderPeerIds.toSet();
    return messages
        .where(
          (row) => row.groupId == groupId && senders.contains(row.senderPeerId),
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> deletePendingMessage(String id) async {
    _messages.remove(id);
  }

  @override
  Future<void> deletePendingMessageByGroupAndMessageId({
    required String groupId,
    required String messageId,
  }) async {
    _messages.removeWhere(
      (_, row) => row.groupId == groupId && row.messageId == messageId,
    );
  }

  @override
  Future<void> pruneGroup(String groupId, {required int maxRows}) async {
    final groupRows = messages
        .where((row) => row.groupId == groupId)
        .toList(growable: false);
    if (groupRows.length <= maxRows) return;
    for (final row in groupRows.take(groupRows.length - maxRows)) {
      _messages.remove(row.id);
    }
  }
}
