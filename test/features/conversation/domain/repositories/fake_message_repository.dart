import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// In-memory [MessageRepository] for tests.
///
/// Stores messages in a list, configurable return values, tracks call counts.
class FakeMessageRepository
    implements
        MessageRepository,
        OutgoingTransportMutationRepository,
        OutgoingDirectTextInboxCustodyRepository {
  final List<ConversationMessage> _messages = [];
  final Map<String, DirectInboxCustodyOutboxEntry> directCustodyRows = {};

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

  @override
  bool get supportsDirectTextInboxCustody => true;

  /// Seed messages for testing.
  void seed(List<ConversationMessage> messages) {
    _messages
      ..clear()
      ..addAll(messages);
  }

  void seedDirectInboxCustody(DirectInboxCustodyOutboxEntry entry) {
    directCustodyRows[_directCustodyKey(
          entry.recipientPeerId,
          entry.messageId,
        )] =
        entry;
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
    String contactPeerId,
  ) async {
    return _visibleMessagesForContact(contactPeerId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final msgs = _visibleMessagesForContact(contactPeerId).toList()
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
  Future<ConversationMessage?> getMessage(String id) async {
    final idx = _messages.indexWhere((m) => m.id == id);
    return idx >= 0 ? _messages[idx] : null;
  }

  @override
  Future<bool> messageExists(String id) async {
    return _messages.any((m) => m.id == id);
  }

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async {
    return _messages.any(
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
    return _messages.any(
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
    markConversationAsReadCallCount++;
    lastMarkReadContactPeerId = contactPeerId;
    return markAsReadReturnValue;
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return _messages
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
    return _messages
        .where((m) => !m.isHidden && m.isIncoming && m.readAt == null)
        .length;
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
  Future<int> deleteMessage(String id) async {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == id);
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
    var msgs = _visibleMessagesForContact(contactPeerId).toList();
    if (beforeTimestamp != null) {
      msgs = msgs
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    msgs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (msgs.length > limit) msgs = msgs.sublist(0, limit);
    return msgs.reversed.toList();
  }

  /// 186: records the `olderThan` last passed to [getUnackedOutgoingMessages]
  /// so tests can assert the reconnect pass drops the 60s age gate (passes 0)
  /// while the periodic pass keeps it.
  Duration? lastUnackedOlderThan;

  /// 195: counts [getUnackedOutgoingMessages] queries so tests can assert the
  /// network-restored flush coalesces (debounce) to exactly one pass.
  int unackedQueryCount = 0;

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    lastUnackedOlderThan = olderThan;
    unackedQueryCount++;
    if (unackedOutgoingOverride != null) return unackedOutgoingOverride!;
    return _messages
        .where(
          (m) =>
              m.status == 'sent' &&
              !m.isIncoming &&
              m.wireEnvelope != null &&
              m.wireEnvelope!.isNotEmpty,
        )
        .toList();
  }

  int getSendingOutgoingCallCount = 0;

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
    getSendingOutgoingCallCount++;
    return _messages
        .where((m) => m.status == 'sending' && !m.isIncoming)
        .toList();
  }

  int conditionalTransitionCallCount = 0;

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    conditionalTransitionCallCount++;
    final idx = _messages.indexWhere(
      (m) => m.id == id && m.status == fromStatus,
    );
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(status: toStatus);
      return 1;
    }
    return 0;
  }

  // Stuck-sending query
  List<ConversationMessage>? stuckSendingOutgoingOverride;

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async {
    if (stuckSendingOutgoingOverride != null) {
      return stuckSendingOutgoingOverride!;
    }
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    return _messages
        .where(
          (m) =>
              m.status == 'sending' &&
              !m.isIncoming &&
              DateTime.parse(m.timestamp).toUtc().isBefore(cutoff),
        )
        .toList();
  }

  // Stuck-sending recovery
  int recoverStuckSendingCallCount = 0;
  Duration? lastRecoverStuckSendingThreshold;
  bool throwOnRecoverStuckSending = false;
  void Function()? onRecoverStuckSending;
  int? recoverStuckSendingReturnValue;

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    recoverStuckSendingCallCount++;
    lastRecoverStuckSendingThreshold = olderThan;
    onRecoverStuckSending?.call();
    if (throwOnRecoverStuckSending) {
      throw Exception(
        'FakeMessageRepository: recoverStuckSendingMessages error',
      );
    }
    if (recoverStuckSendingReturnValue != null) {
      return recoverStuckSendingReturnValue!;
    }
    // Actually transition matching messages in _messages, mirroring real DB behavior.
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    int count = 0;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.status == 'sending' &&
          !m.isIncoming &&
          DateTime.parse(m.timestamp).toUtc().isBefore(cutoff)) {
        _messages[i] = m.copyWith(status: 'failed');
        count++;
      }
    }
    return count;
  }

  // Wire envelope updates
  List<({String id, String envelope})> wireEnvelopeUpdates = [];
  String? lastWireEnvelopeValue;
  void Function()? onUpdateWireEnvelope;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    wireEnvelopeUpdates.add((id: id, envelope: envelope));
    lastWireEnvelopeValue = envelope;
    onUpdateWireEnvelope?.call();
  }

  int ordinaryMutationCallCount = 0;
  final List<ConversationMessage> ordinaryAttemptStages = [];

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    ordinaryMutationCallCount++;
    ordinaryAttemptStages.add(staged);
    final index = _messages.indexWhere((message) => message.id == staged.id);
    if (kind == OutgoingOrdinaryAttemptKind.fresh) {
      if (expected != null || index >= 0) {
        return _ordinaryResult(
          OutgoingOrdinaryMutationOutcome.refused,
          index < 0 ? null : _messages[index],
        );
      }
      _messages.add(staged);
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, staged);
    }
    if (expected == null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, null);
    }
    if (index < 0) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    final current = _messages[index];
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
    _messages[index] = staged.copyWith(
      transport: null,
      relayExpiresAt: null,
      custodyCheckedAt: null,
    );
    return _ordinaryResult(
      OutgoingOrdinaryMutationOutcome.applied,
      _messages[index],
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
    ordinaryMutationCallCount++;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    final current = _messages[index];
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
    final updated = current.copyWith(
      status: status,
      transport: transport,
      wireEnvelope: status == 'delivered' ? null : expectedEnvelope,
      relayExpiresAt: relayExpiresAt,
      custodyCheckedAt: null,
      hiddenAt: tombstone && status == 'delivered' ? current.deletedAt : null,
    );
    _messages[index] = updated;
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, updated);
  }

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) async {
    ordinaryMutationCallCount++;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    final current = _messages[index];
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
    final updated = current.copyWith(wireEnvelope: null);
    _messages[index] = updated;
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, updated);
  }

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) async {
    ordinaryMutationCallCount++;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.removed, null);
    }
    final current = _messages[index];
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
    final updated = current.copyWith(
      status: 'failed',
      transport: null,
      relayExpiresAt: null,
      custodyCheckedAt: null,
    );
    _messages[index] = updated;
    return _ordinaryResult(OutgoingOrdinaryMutationOutcome.applied, updated);
  }

  String _directCustodyKey(String recipientPeerId, String messageId) =>
      '$recipientPeerId\u0000$messageId';

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingDirectTextInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String incarnationId,
    required String wireEnvelope,
  }) async {
    ordinaryMutationCallCount++;
    final key = _directCustodyKey(recipientPeerId, staged.id);
    final custody = directCustodyRows[key];
    final index = _messages.indexWhere((message) => message.id == staged.id);
    final current = index < 0 ? null : _messages[index];
    if (kind != OutgoingOrdinaryAttemptKind.fresh || expected != null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    if (custody != null) {
      final exact =
          custody.incarnationId == incarnationId &&
          custody.wireEnvelope == wireEnvelope &&
          current != null &&
          _sameMessageSnapshot(current, staged);
      return _ordinaryResult(
        exact
            ? OutgoingOrdinaryMutationOutcome.idempotent
            : OutgoingOrdinaryMutationOutcome.refused,
        current,
      );
    }
    if (current != null) {
      return _ordinaryResult(OutgoingOrdinaryMutationOutcome.refused, current);
    }
    final now = DateTime.now().toUtc().toIso8601String();
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
    _messages.add(staged);
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
        if (byAttempt != 0) return byAttempt;
        final byCreated = left.createdAt.compareTo(right.createdAt);
        if (byCreated != 0) return byCreated;
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
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    final key = _directCustodyKey(expected.recipientPeerId, expected.messageId);
    final current = directCustodyRows[key];
    if (current == null || current.incarnationId != expected.incarnationId) {
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
    if (custody == null || custody.incarnationId != expected.incarnationId) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.stale,
        message: null,
      );
    }
    directCustodyRows.remove(key);
    final index = _messages.indexWhere(
      (message) => message.id == expected.messageId,
    );
    if (index < 0) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messageRemoved,
        message: null,
      );
    }
    final current = _messages[index];
    if (current.status == 'delivered' ||
        current.status == 'inboxed' ||
        current.isDeleted ||
        current.hiddenAt != null) {
      return DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messagePreserved,
        message: current,
      );
    }
    final advanced = current.copyWith(
      status: 'inboxed',
      transport: 'inbox',
      relayExpiresAt: relayExpiresAt,
    );
    _messages[index] = advanced;
    return DirectInboxCustodyCompletionResult(
      outcome: DirectInboxCustodyCompletionOutcome.messageAdvanced,
      message: advanced,
    );
  }

  OutgoingOrdinaryMutationResult _ordinaryResult(
    OutgoingOrdinaryMutationOutcome outcome,
    ConversationMessage? message,
  ) {
    // Keep the fixture's historical "last durable message" inspection seam
    // useful without pretending the typed mutation called saveMessage.
    if (message != null &&
        (outcome == OutgoingOrdinaryMutationOutcome.applied ||
            outcome == OutgoingOrdinaryMutationOutcome.idempotent)) {
      lastSavedMessage = message;
    }
    return OutgoingOrdinaryMutationResult(outcome: outcome, message: message);
  }

  Iterable<ConversationMessage> _visibleMessagesForContact(
    String contactPeerId,
  ) {
    return _messages.where(
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
