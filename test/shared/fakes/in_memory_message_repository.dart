import 'dart:async';

import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';

/// In-memory [MessageRepository] for integration tests.
class InMemoryMessageRepository
    implements
        MessageRepository,
        OutgoingTransportMutationRepository,
        OutgoingDirectTextInboxCustodyRepository,
        OutgoingDirectTextMutationInboxCustodyRepository,
        IncomingOrdinaryTextApplyRepository,
        ConversationThreadSummaryRepository,
        MessageRepositoryChangeSource,
        ConversationReadEventSource {
  final Map<String, ConversationMessage> _messages = {};
  final Map<String, DirectInboxCustodyOutboxEntry> directCustodyRows = {};
  final Map<String, DirectReactionInboxCustodyOutboxEntry>
  directMutationCustodyRows = {};
  int directInboxCustodyStageCallCount = 0;
  Future<void> Function(ConversationMessage staged)?
  afterDirectInboxCustodyStage;
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();
  // 194: mirrors the impl — conversation-level read signal (peerId).
  final StreamController<String> _conversationReadController =
      StreamController<String>.broadcast();

  @override
  bool get supportsDirectTextInboxCustody => true;

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
  Future<IncomingOrdinaryTextApplyResult> applyIncomingOrdinaryTextMutation({
    required ConversationMessage incoming,
    required IncomingOrdinaryTextMutationKind kind,
  }) async {
    final current = _messages[incoming.id];
    if (current == null) {
      await saveMessage(incoming);
      return IncomingOrdinaryTextApplyResult(
        outcome: IncomingOrdinaryTextMutationOutcome.inserted,
        message: incoming,
      );
    }
    if (!current.isIncoming ||
        current.contactPeerId != incoming.contactPeerId ||
        current.senderPeerId != incoming.senderPeerId) {
      return IncomingOrdinaryTextApplyResult(
        outcome: IncomingOrdinaryTextMutationOutcome.unauthorized,
        message: current,
      );
    }
    if (kind == IncomingOrdinaryTextMutationKind.deletion) {
      if (current.isDeleted) {
        return IncomingOrdinaryTextApplyResult(
          outcome: current.deletedAt == incoming.deletedAt
              ? IncomingOrdinaryTextMutationOutcome.exactReplay
              : IncomingOrdinaryTextMutationOutcome.superseded,
          message: current,
        );
      }
      await saveMessage(incoming);
      return IncomingOrdinaryTextApplyResult(
        outcome: IncomingOrdinaryTextMutationOutcome.updated,
        message: incoming,
      );
    }
    if (kind == IncomingOrdinaryTextMutationKind.initial) {
      if (current.isDeleted ||
          (current.editedAt != null && current.hiddenAt == null)) {
        return IncomingOrdinaryTextApplyResult(
          outcome: IncomingOrdinaryTextMutationOutcome.superseded,
          message: current,
        );
      }
      if (current.editedAt != null && current.hiddenAt != null) {
        final materialized = current.copyWith(
          timestamp: incoming.timestamp,
          status: incoming.status,
          quotedMessageId: current.quotedMessageId ?? incoming.quotedMessageId,
          dedupKey: incoming.dedupKey,
          isForwarded: incoming.isForwarded,
          transport: incoming.transport ?? current.transport,
          hiddenAt: null,
        );
        await saveMessage(materialized);
        return IncomingOrdinaryTextApplyResult(
          outcome: IncomingOrdinaryTextMutationOutcome.updated,
          message: materialized,
        );
      }
      return IncomingOrdinaryTextApplyResult(
        outcome: IncomingOrdinaryTextMutationOutcome.exactReplay,
        message: current,
      );
    }
    if (current.isDeleted) {
      return IncomingOrdinaryTextApplyResult(
        outcome: IncomingOrdinaryTextMutationOutcome.superseded,
        message: current,
      );
    }
    final incomingOrder = DateTime.tryParse(incoming.editedAt ?? '');
    final currentOrder = DateTime.tryParse(current.editedAt ?? '');
    if (incomingOrder == null ||
        (currentOrder != null && !incomingOrder.isAfter(currentOrder))) {
      return IncomingOrdinaryTextApplyResult(
        outcome:
            incomingOrder != null &&
                currentOrder != null &&
                incomingOrder.isAtSameMomentAs(currentOrder) &&
                incoming.text == current.text
            ? IncomingOrdinaryTextMutationOutcome.exactReplay
            : IncomingOrdinaryTextMutationOutcome.superseded,
        message: current,
      );
    }
    await saveMessage(incoming);
    return IncomingOrdinaryTextApplyResult(
      outcome: IncomingOrdinaryTextMutationOutcome.updated,
      message: incoming,
    );
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
  bool get supportsDirectTextMutationInboxCustody => true;

  @override
  Future<OutgoingDirectTextMutationCustodyStageResult>
  stageOutgoingDirectTextMutationInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String eventId,
    required String wireEnvelope,
  }) async {
    final key = _directMutationCustodyKey(recipientPeerId, eventId);
    final current = _messages[staged.id];
    final currentCustody = directMutationCustodyRows[key];
    if (currentCustody != null) {
      final exact =
          current != null &&
          _sameMessageSnapshot(current, staged) &&
          currentCustody.wireEnvelope == wireEnvelope;
      return OutgoingDirectTextMutationCustodyStageResult(
        outcome: exact
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.refused,
        message: current,
        custody: exact ? currentCustody : null,
      );
    }
    if (current == null || !_sameMessageSnapshot(current, expected)) {
      return OutgoingDirectTextMutationCustodyStageResult.refused(
        message: current,
      );
    }
    final validKind =
        (kind == OutgoingOrdinaryAttemptKind.edit && !staged.isDeleted) ||
        (kind == OutgoingOrdinaryAttemptKind.tombstoneInitial &&
            staged.isDeleted);
    if (!validKind ||
        staged.isIncoming ||
        staged.contactPeerId != recipientPeerId ||
        staged.wireEnvelope != wireEnvelope ||
        eventId.trim().isEmpty ||
        wireEnvelope.trim().isEmpty) {
      return OutgoingDirectTextMutationCustodyStageResult.refused(
        message: current,
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final custody = DirectReactionInboxCustodyOutboxEntry(
      recipientPeerId: recipientPeerId,
      eventId: eventId,
      wireEnvelope: wireEnvelope,
      retryCount: 0,
      lastAttemptAt: null,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
    );
    _messages[staged.id] = staged;
    directMutationCustodyRows[key] = custody;
    _messageChangeController.add(staged);
    return OutgoingDirectTextMutationCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      message: staged,
      custody: custody,
    );
  }

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) async =>
      directMutationCustodyRows[_directMutationCustodyKey(
        recipientPeerId,
        eventId,
      )];

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    if (!DirectReactionInboxCustodyErrorCode.values.contains(errorCode)) {
      return false;
    }
    final key = _directMutationCustodyKey(
      expected.recipientPeerId,
      expected.eventId,
    );
    final current = directMutationCustodyRows[key];
    if (current == null || current.wireEnvelope != expected.wireEnvelope) {
      return false;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    directMutationCustodyRows[key] = current.copyWith(
      retryCount: current.retryCount + 1,
      lastAttemptAt: now,
      lastErrorCode: errorCode,
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    final key = _directMutationCustodyKey(
      expected.recipientPeerId,
      expected.eventId,
    );
    final currentCustody = directMutationCustodyRows[key];
    if (currentCustody == null) {
      return DirectMutationInboxCustodyCompletionOutcome.absent;
    }
    if (currentCustody.wireEnvelope != expected.wireEnvelope ||
        relayExpiresAt == null ||
        relayExpiresAt <= 0) {
      return DirectMutationInboxCustodyCompletionOutcome.stale;
    }
    final parents = _messages.values
        .where(
          (message) =>
              !message.isIncoming &&
              message.contactPeerId == expected.recipientPeerId &&
              message.wireEnvelope == expected.wireEnvelope,
        )
        .take(2)
        .toList(growable: false);
    if (parents.length > 1) {
      return DirectMutationInboxCustodyCompletionOutcome.ambiguous;
    }
    if (parents case [final parent]) {
      if (!const <String>{
        'sending',
        'sent',
        'failed',
        'inboxed',
      }.contains(parent.status)) {
        return DirectMutationInboxCustodyCompletionOutcome.stale;
      }
      final projected = parent.copyWith(
        status: 'inboxed',
        transport: 'inbox',
        relayExpiresAt: relayExpiresAt,
        custodyCheckedAt: null,
      );
      _messages[parent.id] = projected;
      _messageChangeController.add(projected);
    }
    directMutationCustodyRows.remove(key);
    return DirectMutationInboxCustodyCompletionOutcome.completed;
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

  String _directCustodyKey(String recipientPeerId, String messageId) =>
      '$recipientPeerId\u0000$messageId';

  String _directMutationCustodyKey(String recipientPeerId, String eventId) =>
      '$recipientPeerId\u0000$eventId';

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingDirectTextInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String incarnationId,
    required String wireEnvelope,
  }) async {
    directInboxCustodyStageCallCount++;
    final key = _directCustodyKey(recipientPeerId, staged.id);
    final current = _messages[staged.id];
    final custody = directCustodyRows[key];
    final validFreshAuthority =
        kind == OutgoingOrdinaryAttemptKind.fresh &&
        expected == null &&
        staged.contactPeerId == recipientPeerId &&
        staged.wireEnvelope == wireEnvelope &&
        incarnationId.length == 32 &&
        wireEnvelope.isNotEmpty;
    if (!validFreshAuthority) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (current != null || custody != null) {
      final exact =
          current != null &&
          custody != null &&
          _sameMessageSnapshot(current, staged) &&
          custody.incarnationId == incarnationId &&
          custody.wireEnvelope == wireEnvelope;
      return _ordinaryResult(
        exact
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.refused,
        current,
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    _messages[staged.id] = staged;
    directCustodyRows[key] = DirectInboxCustodyOutboxEntry(
      recipientPeerId: recipientPeerId,
      messageId: staged.id,
      incarnationId: incarnationId,
      wireEnvelope: wireEnvelope,
      retryCount: 0,
      lastAttemptAt: null,
      lastErrorCode: null,
      createdAt: now,
      updatedAt: now,
    );
    await afterDirectInboxCustodyStage?.call(staged);
    _messageChangeController.add(staged);
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, staged);
  }

  @override
  Future<List<DirectInboxCustodyOutboxEntry>> loadDirectInboxCustody({
    int limit = 50,
  }) async {
    final rows = directCustodyRows.values.toList()
      ..sort((left, right) {
        if (left.lastAttemptAt == null && right.lastAttemptAt != null) {
          return -1;
        }
        if (left.lastAttemptAt != null && right.lastAttemptAt == null) {
          return 1;
        }
        final byAttempt = (left.lastAttemptAt ?? '').compareTo(
          right.lastAttemptAt ?? '',
        );
        if (byAttempt != 0) {
          return byAttempt;
        }
        final byCreated = left.createdAt.compareTo(right.createdAt);
        if (byCreated != 0) {
          return byCreated;
        }
        final byPeer = left.recipientPeerId.compareTo(right.recipientPeerId);
        return byPeer != 0 ? byPeer : left.messageId.compareTo(right.messageId);
      });
    final bounded = limit < 0 ? 0 : (limit > 50 ? 50 : limit);
    return rows.take(bounded).toList(growable: false);
  }

  @override
  Future<DirectInboxCustodyOutboxEntry?> loadDirectInboxCustodyForMessage({
    required String recipientPeerId,
    required String messageId,
  }) async => directCustodyRows[_directCustodyKey(recipientPeerId, messageId)];

  @override
  Future<DirectInboxCustodyOutboxEntry?>
  loadDirectInboxCustodyOwnerForMessageId({required String messageId}) async {
    final matches = directCustodyRows.values
        .where((entry) => entry.messageId == messageId)
        .take(2)
        .toList(growable: false);
    if (matches.length > 1) {
      throw StateError('Ambiguous direct inbox custody owner for message');
    }
    return matches.firstOrNull;
  }

  @override
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    if (!DirectInboxCustodyErrorCode.values.contains(errorCode)) return false;
    final key = _directCustodyKey(expected.recipientPeerId, expected.messageId);
    final current = directCustodyRows[key];
    if (current == null ||
        current.incarnationId != expected.incarnationId ||
        current.wireEnvelope != expected.wireEnvelope) {
      return false;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    directCustodyRows[key] = current.copyWith(
      retryCount: current.retryCount + 1,
      lastAttemptAt: now,
      lastErrorCode: errorCode,
      updatedAt: now,
    );
    return true;
  }

  @override
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    final key = _directCustodyKey(expected.recipientPeerId, expected.messageId);
    final custody = directCustodyRows[key];
    if (custody == null ||
        custody.incarnationId != expected.incarnationId ||
        custody.wireEnvelope != expected.wireEnvelope) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.stale,
        message: null,
      );
    }

    final current = _messages[expected.messageId];
    directCustodyRows.remove(key);
    if (current == null) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messageRemoved,
        message: null,
      );
    }
    if (!const <String>{
          'sending',
          'sent',
          'failed',
          'inboxed',
        }.contains(current.status) ||
        current.isDeleted ||
        current.hiddenAt != null) {
      return DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messagePreserved,
        message: current,
      );
    }
    if (current.status == 'inboxed' &&
        current.transport == 'inbox' &&
        (relayExpiresAt == null || current.relayExpiresAt == relayExpiresAt)) {
      return DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messagePreserved,
        message: current,
      );
    }

    final advanced = current.copyWith(
      status: 'inboxed',
      transport: 'inbox',
      relayExpiresAt: relayExpiresAt,
      custodyCheckedAt: null,
    );
    _messages[current.id] = advanced;
    _messageChangeController.add(advanced);
    return DirectInboxCustodyCompletionResult(
      outcome: DirectInboxCustodyCompletionOutcome.messageAdvanced,
      message: advanced,
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
