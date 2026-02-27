import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// In-memory [MessageRepository] for tests.
///
/// Stores messages in a list, configurable return values, tracks call counts.
class FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> _messages = [];

  // Call tracking
  int saveMessageCallCount = 0;
  int markConversationAsReadCallCount = 0;
  int getFailedOutgoingCallCount = 0;
  int deleteMessagesCallCount = 0;

  // Last arguments
  String? lastMarkReadContactPeerId;
  ConversationMessage? lastSavedMessage;

  // Configurable
  int markAsReadReturnValue = 0;
  List<ConversationMessage>? failedOutgoingOverride;
  List<ConversationMessage>? unackedOutgoingOverride;
  bool throwOnUpdateStatus = false;

  /// Seed messages for testing.
  void seed(List<ConversationMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages);
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saveMessageCallCount++;
    lastSavedMessage = message;
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      _messages[idx] = message;
    } else {
      _messages.add(message);
    }
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async {
    return _messages
        .where((m) => m.contactPeerId == contactPeerId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async {
    final msgs = _messages
        .where((m) => m.contactPeerId == contactPeerId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return msgs.isNotEmpty ? msgs.first : null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    if (throwOnUpdateStatus) {
      throw Exception('FakeMessageRepository: updateMessageStatus error');
    }
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(status: status);
    }
  }

  @override
  Future<bool> messageExists(String id) async {
    return _messages.any((m) => m.id == id);
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return _messages.where((m) => m.contactPeerId == contactPeerId).length;
  }

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    markConversationAsReadCallCount++;
    lastMarkReadContactPeerId = contactPeerId;
    return markAsReadReturnValue;
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return _messages
        .where((m) =>
            m.contactPeerId == contactPeerId &&
            m.isIncoming &&
            m.readAt == null)
        .length;
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return _messages.where((m) => m.isIncoming && m.readAt == null).length;
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    return getTotalUnreadCount();
  }

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    deleteMessagesCallCount++;
    final before = _messages.length;
    _messages.removeWhere((m) => m.contactPeerId == contactPeerId);
    return before - _messages.length;
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    getFailedOutgoingCallCount++;
    if (failedOutgoingOverride != null) return failedOutgoingOverride!;
    return _messages
        .where((m) => m.status == 'failed' && !m.isIncoming)
        .toList();
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    var msgs =
        _messages.where((m) => m.contactPeerId == contactPeerId).toList();
    if (beforeTimestamp != null) {
      msgs = msgs.where((m) => m.timestamp.compareTo(beforeTimestamp) < 0).toList();
    }
    msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (msgs.length > limit) msgs = msgs.sublist(0, limit);
    return msgs.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    if (unackedOutgoingOverride != null) return unackedOutgoingOverride!;
    return _messages
        .where((m) =>
            m.status == 'sent' &&
            !m.isIncoming &&
            m.wireEnvelope != null &&
            m.wireEnvelope!.isNotEmpty)
        .toList();
  }
}
