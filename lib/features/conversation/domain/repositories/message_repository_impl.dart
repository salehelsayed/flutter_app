import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/conversation_message.dart';
import '../models/conversation_thread_summary.dart';
import 'conversation_thread_summary_repository.dart';
import 'message_repository.dart';

/// Implementation of MessageRepository using database helper functions.
class MessageRepositoryImpl
    implements
        MessageRepository,
        ConversationThreadSummaryRepository,
        MessageRepositoryChangeSource {
  final Future<void> Function(Map<String, Object?> row) dbInsertMessage;
  final Future<List<Map<String, Object?>>> Function(String contactPeerId)
  dbLoadMessagesForContact;
  final Future<Map<String, Object?>?> Function(String contactPeerId)
  dbLoadLatestMessageForContact;
  final Future<int> Function(String id, String status) dbUpdateMessageStatus;
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
  })
  dbLoadMessagesPage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadFailedOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function({
    required DateTime olderThan,
    int limit,
  })
  dbLoadUnackedOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function(List<String> contactPeerIds)
  dbLoadConversationThreadSummaries;
  final Future<int> Function({required DateTime olderThan, int limit})
  dbRecoverStuckSendingMessages;
  final Future<void> Function(String id, String wireEnvelope)?
  dbUpdateWireEnvelope;
  final Future<List<Map<String, Object?>>> Function({
    required DateTime olderThan,
    int limit,
  })
  dbLoadStuckSendingOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadSendingOutgoingMessages;
  final Future<int> Function(String id,
      {required String fromStatus, required String toStatus})
  dbConditionalTransitionStatus;
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();
  final Map<String, ConversationMessage> _messageSnapshots = {};

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
    required this.dbLoadFailedOutgoingMessages,
    required this.dbLoadUnackedOutgoingMessages,
    required this.dbLoadConversationThreadSummaries,
    required this.dbRecoverStuckSendingMessages,
    this.dbUpdateWireEnvelope,
    required this.dbLoadStuckSendingOutgoingMessages,
    required this.dbLoadSendingOutgoingMessages,
    required this.dbConditionalTransitionStatus,
  });

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_SAVE_START',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
      },
    );

    try {
      await dbInsertMessage(message.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_SAVE_SUCCESS',
        details: {
          'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        },
      );
      final saved = _rememberMessage(message);
      _messageChangeController.add(saved);
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
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final row = await dbLoadLatestMessageForContact(contactPeerId);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final updatedCount = await dbUpdateMessageStatus(id, status);
    if (updatedCount <= 0) return;
    final updated = _updatedMessageSnapshot(id, status) ??
        await _loadAndRememberMessage(id);
    if (updated != null) {
      _messageChangeController.add(updated);
    }
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async {
    final row = await dbLoadMessage(id);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_UPDATE_WIRE_ENVELOPE',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
    if (dbUpdateWireEnvelope != null) {
      await dbUpdateWireEnvelope!(id, envelope);
      final cached = _messageSnapshots[id];
      if (cached != null) {
        _rememberMessage(cached.copyWith(wireEnvelope: envelope));
      }
    }
  }

  @override
  Future<bool> messageExists(String id) async {
    final row = await dbLoadMessage(id);
    if (row != null) {
      _rememberMessage(ConversationMessage.fromMap(row));
    }
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
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
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

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    final rows = await dbLoadFailedOutgoingMessages();
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final rows = await dbLoadUnackedOutgoingMessages(olderThan: cutoff);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    return dbRecoverStuckSendingMessages(olderThan: cutoff);
  }

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final rows = await dbLoadStuckSendingOutgoingMessages(olderThan: cutoff);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
    final rows = await dbLoadSendingOutgoingMessages();
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    final count = await dbConditionalTransitionStatus(
      id,
      fromStatus: fromStatus,
      toStatus: toStatus,
    );
    if (count > 0) {
      final updated = _updatedMessageSnapshot(id, toStatus) ??
          await _loadAndRememberMessage(id);
      if (updated != null) {
        _messageChangeController.add(updated);
      }
    }
    return count;
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) async {
    final summaries = await getConversationThreadSummaries([contactPeerId]);
    return summaries[contactPeerId] ??
        ConversationThreadSummary(contactPeerId: contactPeerId);
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    final ids = contactPeerIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, ConversationThreadSummary>{};

    final rows = await dbLoadConversationThreadSummaries(ids);
    final summaries = <String, ConversationThreadSummary>{};
    for (final row in rows) {
      final contactPeerId = row['contact_peer_id'] as String;
      summaries[contactPeerId] = ConversationThreadSummary(
        contactPeerId: contactPeerId,
        messageCount: row['message_count'] as int? ?? 0,
        unreadCount: row['unread_count'] as int? ?? 0,
        latestMessage: row['latest_id'] == null
            ? null
            : _rememberMessage(
                ConversationMessage.fromMap({
                  'id': row['latest_id'],
                  'contact_peer_id': row['latest_contact_peer_id'],
                  'sender_peer_id': row['latest_sender_peer_id'],
                  'text': row['latest_text'],
                  'timestamp': row['latest_timestamp'],
                  'status': row['latest_status'],
                  'is_incoming': row['latest_is_incoming'],
                  'created_at': row['latest_created_at'],
                  'read_at': row['latest_read_at'],
                  'quoted_message_id': row['latest_quoted_message_id'],
                  'transport': row['latest_transport'],
                  'wire_envelope': row['latest_wire_envelope'],
                }),
              ),
      );
    }
    for (final contactPeerId in ids) {
      summaries.putIfAbsent(
        contactPeerId,
        () => ConversationThreadSummary(contactPeerId: contactPeerId),
      );
    }
    return summaries;
  }

  ConversationMessage _rememberMessage(ConversationMessage message) {
    _messageSnapshots[message.id] = message;
    return message;
  }

  List<ConversationMessage> _rememberMessages(
    Iterable<ConversationMessage> messages,
  ) {
    return messages.map(_rememberMessage).toList();
  }

  ConversationMessage? _updatedMessageSnapshot(String id, String status) {
    final cached = _messageSnapshots[id];
    if (cached == null) return null;
    return _rememberMessage(cached.copyWith(status: status));
  }

  Future<ConversationMessage?> _loadAndRememberMessage(String id) async {
    final row = await dbLoadMessage(id);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }
}
