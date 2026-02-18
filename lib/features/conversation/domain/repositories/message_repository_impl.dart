import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/conversation_message.dart';
import 'message_repository.dart';

/// Implementation of MessageRepository using database helper functions.
class MessageRepositoryImpl implements MessageRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertMessage;
  final Future<List<Map<String, Object?>>> Function(String contactPeerId)
      dbLoadMessagesForContact;
  final Future<Map<String, Object?>?> Function(String contactPeerId)
      dbLoadLatestMessageForContact;
  final Future<void> Function(String id, String status) dbUpdateMessageStatus;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMessage;
  final Future<int> Function(String contactPeerId) dbCountMessagesForContact;
  final Future<int> Function(String contactPeerId) dbMarkConversationAsRead;
  final Future<int> Function(String contactPeerId) dbCountUnreadForContact;
  final Future<int> Function() dbCountTotalUnread;
  final Future<int> Function() dbCountTotalUnreadExcludingArchived;
  final Future<int> Function(String contactPeerId) dbDeleteMessagesForContact;
  final Future<List<Map<String, Object?>>> Function(
    String contactPeerId, {
    int limit,
    String? beforeTimestamp,
  }) dbLoadMessagesPage;

  MessageRepositoryImpl({
    required this.dbInsertMessage,
    required this.dbLoadMessagesForContact,
    required this.dbLoadLatestMessageForContact,
    required this.dbUpdateMessageStatus,
    required this.dbLoadMessage,
    required this.dbCountMessagesForContact,
    required this.dbMarkConversationAsRead,
    required this.dbCountUnreadForContact,
    required this.dbCountTotalUnread,
    required this.dbCountTotalUnreadExcludingArchived,
    required this.dbDeleteMessagesForContact,
    required this.dbLoadMessagesPage,
  });

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_SAVE_START',
      details: {'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id},
    );

    try {
      await dbInsertMessage(message.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_SAVE_SUCCESS',
        details: {'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final rows = await dbLoadMessagesForContact(contactPeerId);
    return rows.map((row) => ConversationMessage.fromMap(row)).toList();
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final row = await dbLoadLatestMessageForContact(contactPeerId);
    if (row == null) return null;
    return ConversationMessage.fromMap(row);
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    await dbUpdateMessageStatus(id, status);
  }

  @override
  Future<bool> messageExists(String id) async {
    final row = await dbLoadMessage(id);
    return row != null;
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return dbCountMessagesForContact(contactPeerId);
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_MARK_READ_START',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    return dbMarkConversationAsRead(contactPeerId);
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return dbCountUnreadForContact(contactPeerId);
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return dbCountTotalUnread();
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    return dbCountTotalUnreadExcludingArchived();
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final rows = await dbLoadMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
    return rows.map((row) => ConversationMessage.fromMap(row)).toList();
  }

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_START',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );

    try {
      final count = await dbDeleteMessagesForContact(contactPeerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }
}
