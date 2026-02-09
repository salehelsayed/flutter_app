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

  MessageRepositoryImpl({
    required this.dbInsertMessage,
    required this.dbLoadMessagesForContact,
    required this.dbLoadLatestMessageForContact,
    required this.dbUpdateMessageStatus,
    required this.dbLoadMessage,
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
}
