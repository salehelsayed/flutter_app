import 'dart:async';

import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';

/// In-memory [MessageRepository] for integration tests.
class InMemoryMessageRepository
    implements
        MessageRepository,
        OutgoingTransportMutationRepository,
        ConversationThreadSummaryRepository,
        MessageRepositoryChangeSource,
        ConversationReadEventSource {
  final Map<String, ConversationMessage> _messages = {};
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();
  // 194: mirrors the impl — conversation-level read signal (peerId).
  final StreamController<String> _conversationReadController =
      StreamController<String>.broadcast();

  // 160 spy counters: distinguish the unbounded full-load path from the
  // batched-summary + bounded-page paths so widget tests can assert the feed
  // mount uses summaries + windowed pages, never per-contact full loads.
  int getMessagesForContactCallCount = 0;
  int getConversationThreadSummariesCallCount = 0;
  // 162 spy: total-unread recompute observability for the cross-source
  // (incoming refresh=true + outgoing refresh=false) coalesce test.
  int getTotalUnreadCountExcludingArchivedCallCount = 0;
  final List<(String, int)> getMessagesPageCalls = <(String, int)>[];

  void resetSpyCounters() {
    getMessagesForContactCallCount = 0;
    getConversationThreadSummariesCallCount = 0;
    getTotalUnreadCountExcludingArchivedCallCount = 0;
    getMessagesPageCalls.clear();
  }

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  Stream<String> get conversationReadStream =>
      _conversationReadController.stream;

  /// 162 test hook: emit an arbitrary message-change onto [messageChanges]
  /// WITHOUT persisting it, so a test can craft a clean `delete(X)` then
  /// `sent(Y)` burst or a hidden-vs-non-hidden tombstone that the
  /// persistence-coupled methods (`saveMessage`/`updateMessageStatus`) cannot.
  void debugEmitMessageChange(ConversationMessage message) {
    _messageChangeController.add(message);
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    _messages[message.id] = message;
    _messageChangeController.add(message);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    getMessagesForContactCallCount++;
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
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async {
    return _messages.values.any(
      (m) =>
          m.isIncoming &&
          m.contactPeerId == contactPeerId &&
          m.senderPeerId == senderPeerId &&
          m.text == text &&
          m.timestamp == timestamp,
    );
  }

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async {
    return _messages.values.any(
      (m) =>
          m.isIncoming &&
          m.contactPeerId == contactPeerId &&
          m.senderPeerId == senderPeerId &&
          m.dedupKey == dedupKey,
    );
  }

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
    // 194: fire the read-event only when a row actually flipped (INV-5).
    if (count > 0) {
      _conversationReadController.add(contactPeerId);
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
    getTotalUnreadCountExcludingArchivedCallCount++;
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
    getMessagesPageCalls.add((contactPeerId, limit));
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
    return _summaryForContact(contactPeerId);
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    getConversationThreadSummariesCallCount++;
    final summaries = <String, ConversationThreadSummary>{};
    for (final contactPeerId in contactPeerIds.toSet()) {
      summaries[contactPeerId] = _summaryForContact(contactPeerId);
    }
    return summaries;
  }

  /// Mirrors the real `dbLoadConversationThreadSummaries` convention (160 A0):
  /// counts exclude soft-deleted rows; `lastOutgoingAt` is the newest
  /// non-deleted outgoing timestamp.
  ConversationThreadSummary _summaryForContact(String contactPeerId) {
    final messages = _visibleMessagesForContact(contactPeerId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final visible = messages.where((m) => !m.isDeleted).toList();
    DateTime? lastOutgoingAt;
    for (final m in visible) {
      if (!m.isIncoming) {
        final ts = DateTime.tryParse(m.timestamp);
        if (ts != null &&
            (lastOutgoingAt == null || ts.isAfter(lastOutgoingAt))) {
          lastOutgoingAt = ts;
        }
      }
    }
    return ConversationThreadSummary(
      contactPeerId: contactPeerId,
      messageCount: visible.length,
      unreadCount: visible
          .where((message) => message.isIncoming && message.readAt == null)
          .length,
      lastOutgoingAt: lastOutgoingAt,
      latestMessage: messages.isEmpty ? null : messages.first,
    );
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

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final current = _messages[staged.id];
    if (kind == OutgoingOrdinaryAttemptKind.fresh) {
      if (expected != null || current != null) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.refused,
          current,
        );
      }
      return _applyOrdinary(staged);
    }
    if (expected == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (_sameMessageSnapshot(current, staged)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.idempotent,
        current,
      );
    }
    if (!_sameMessageSnapshot(current, expected)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      staged.copyWith(
        transport: null,
        relayExpiresAt: null,
        custodyCheckedAt: null,
      ),
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOutgoingOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: false,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => _settleOutgoingOrdinary(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
    tombstone: true,
  );

  Future<OutgoingOrdinaryMutationResult> _settleOutgoingOrdinary({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
    required bool tombstone,
  }) async {
    final current = _messages[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.isIncoming ||
        current.contactPeerId != expectedContactPeerId ||
        current.isDeleted != tombstone) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.status == 'delivered') {
      return _ordinaryResult(
        status == 'delivered'
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    if (current.status == status) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.idempotent,
        current,
      );
    }
    final predecessors = mode == OutgoingOrdinarySettlementMode.receipt
        ? const <String>{'inboxed', 'sent', 'failed'}
        : switch (status) {
            'delivered' => const <String>{
              'sending',
              'sent',
              'inboxed',
              'failed',
            },
            'inboxed' => const <String>{'sending', 'sent', 'failed'},
            'sent' => const <String>{'sending', 'failed'},
            'failed' => const <String>{'sending'},
            _ => const <String>{},
          };
    if (!predecessors.contains(current.status)) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      current.copyWith(
        status: status,
        transport: transport,
        wireEnvelope: status == 'delivered' ? null : expectedEnvelope,
        relayExpiresAt: relayExpiresAt,
        custodyCheckedAt: null,
        hiddenAt: tombstone && status == 'delivered' ? current.deletedAt : null,
      ),
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) async {
    final current = _messages[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.contactPeerId != expectedContactPeerId ||
        current.isIncoming ||
        current.isDeleted ||
        !const <String>{'sending', 'failed'}.contains(current.status)) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(current.copyWith(wireEnvelope: null));
  }

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) async {
    final current = _messages[messageId];
    if (current == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    if (current.contactPeerId != expectedContactPeerId ||
        current.isIncoming ||
        current.isDeleted != isDeleteTombstone ||
        current.status != 'sent') {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current.wireEnvelope != expectedEnvelope) {
      return _ordinaryResult(
        OutgoingOrdinaryMutationOutcome.preserved,
        current,
      );
    }
    return _applyOrdinary(
      current.copyWith(
        status: 'failed',
        transport: null,
        relayExpiresAt: null,
        custodyCheckedAt: null,
      ),
    );
  }

  Future<OutgoingOrdinaryMutationResult> _applyOrdinary(
    ConversationMessage message,
  ) async {
    _messages[message.id] = message;
    _messageChangeController.add(message);
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, message);
  }

  OutgoingOrdinaryMutationResult _ordinaryResult(
    OutgoingOrdinaryMutationOutcome outcome,
    ConversationMessage? message,
  ) => OutgoingOrdinaryMutationResult(outcome: outcome, message: message);

  int get count => _messages.length;

  Iterable<ConversationMessage> _visibleMessagesForContact(
    String contactPeerId,
  ) {
    return _messages.values.where(
      (message) => message.contactPeerId == contactPeerId && !message.isHidden,
    );
  }
}

bool _sameMessageSnapshot(ConversationMessage left, ConversationMessage right) {
  final leftMap = left.toMap();
  final rightMap = right.toMap();
  return leftMap.length == rightMap.length &&
      leftMap.entries.every((entry) => rightMap[entry.key] == entry.value);
}
