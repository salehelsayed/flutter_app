import 'dart:async';

import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';

/// In-memory [MessageRepository] for integration tests.
class InMemoryMessageRepository
    implements
        MessageRepository,
        ConversationThreadSummaryRepository,
        MessageRepositoryChangeSource {
  final Map<String, ConversationMessage> _messages = {};
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    _messages[message.id] = message;
    _messageChangeController.add(message);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final list = _visibleMessagesForContact(contactPeerId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return list;
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final list = await getMessagesForContact(contactPeerId);
    return list.isNotEmpty ? list.last : null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final msg = _messages[id];
    if (msg != null) {
      final updated = msg.copyWith(status: status);
      _messages[id] = updated;
      _messageChangeController.add(updated);
    }
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async => _messages[id];

  @override
  Future<bool> messageExists(String id) async => _messages.containsKey(id);

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return _visibleMessagesForContact(contactPeerId).length;
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    var count = 0;
    for (final entry in _messages.entries.toList()) {
      final m = entry.value;
      if (m.contactPeerId == contactPeerId &&
          !m.isHidden &&
          m.isIncoming &&
          m.readAt == null) {
        _messages[entry.key] = m.copyWith(readAt: now);
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return _messages.values
        .where(
          (m) =>
              m.contactPeerId == contactPeerId &&
              !m.isHidden &&
              m.isIncoming &&
              m.readAt == null,
        )
        .length;
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return _messages.values
        .where((m) => !m.isHidden && m.isIncoming && m.readAt == null)
        .length;
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    return getTotalUnreadCount();
  }

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    final keysToRemove = _messages.entries
        .where((e) => e.value.contactPeerId == contactPeerId)
        .map((e) => e.key)
        .toList();
    for (final key in keysToRemove) {
      _messages.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<int> deleteMessage(String id) async {
    return _messages.remove(id) == null ? 0 : 1;
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    var messages = _visibleMessagesForContact(contactPeerId).toList();
    if (beforeTimestamp != null) {
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = messages.take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    return _messages.values
        .where((m) => m.status == 'failed' && !m.isIncoming)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    return _messages.values
        .where(
          (m) =>
              m.status == 'sent' &&
              !m.isIncoming &&
              m.wireEnvelope != null &&
              m.wireEnvelope!.isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) async {
    final messages = _visibleMessagesForContact(contactPeerId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return ConversationThreadSummary(
      contactPeerId: contactPeerId,
      messageCount: messages.length,
      unreadCount: messages
          .where((message) => message.isIncoming && message.readAt == null)
          .length,
      latestMessage: messages.isEmpty ? null : messages.first,
    );
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    final summaries = <String, ConversationThreadSummary>{};
    for (final contactPeerId in contactPeerIds.toSet()) {
      final messages = _visibleMessagesForContact(contactPeerId).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      summaries[contactPeerId] = ConversationThreadSummary(
        contactPeerId: contactPeerId,
        messageCount: messages.length,
        unreadCount: messages
            .where((message) => message.isIncoming && message.readAt == null)
            .length,
        latestMessage: messages.isEmpty ? null : messages.first,
      );
    }
    return summaries;
  }

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
    return _messages.values
        .where((m) => m.status == 'sending' && !m.isIncoming)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    final msg = _messages[id];
    if (msg != null && msg.status == fromStatus) {
      final updated = msg.copyWith(status: toStatus);
      _messages[id] = updated;
      _messageChangeController.add(updated);
      return 1;
    }
    return 0;
  }

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    return _messages.values
        .where(
          (m) =>
              m.status == 'sending' &&
              !m.isIncoming &&
              DateTime.parse(m.timestamp).toUtc().isBefore(cutoff),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    int count = 0;
    for (final entry in _messages.entries.toList()) {
      final m = entry.value;
      if (m.status == 'sending' &&
          !m.isIncoming &&
          DateTime.parse(m.timestamp).toUtc().isBefore(cutoff)) {
        _messages[entry.key] = m.copyWith(status: 'failed');
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    final msg = _messages[id];
    if (msg != null) {
      _messages[id] = msg.copyWith(wireEnvelope: envelope);
    }
  }

  int get count => _messages.length;

  Iterable<ConversationMessage> _visibleMessagesForContact(
    String contactPeerId,
  ) {
    return _messages.values.where(
      (message) => message.contactPeerId == contactPeerId && !message.isHidden,
    );
  }
}
