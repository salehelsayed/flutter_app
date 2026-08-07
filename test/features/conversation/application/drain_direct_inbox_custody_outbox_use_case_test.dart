import 'dart:async';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DirectInboxCustodyOutboxEntry _entry(
  String id, {
  String? lastAttemptAt,
  int retryCount = 0,
}) => DirectInboxCustodyOutboxEntry(
  recipientPeerId: 'peer-$id',
  messageId: id,
  incarnationId: id.padRight(32, '0').substring(0, 32),
  wireEnvelope: 'wire-$id',
  retryCount: retryCount,
  lastAttemptAt: lastAttemptAt,
  lastErrorCode: null,
  createdAt: '2026-08-06T10:00:00.000Z',
  updatedAt: '2026-08-06T10:00:00.000Z',
);

ConversationMessage _message(String id, {String status = 'failed'}) =>
    ConversationMessage(
      id: id,
      contactPeerId: 'peer-$id',
      senderPeerId: 'sender',
      text: 'text',
      timestamp: '2026-08-06T10:00:00.000Z',
      status: status,
      isIncoming: false,
      createdAt: '2026-08-06T10:00:00.000Z',
      wireEnvelope: 'message-wire-$id',
    );

final class _InMemoryCustodyRepository
    implements OutgoingDirectTextInboxCustodyRepository {
  final Map<String, DirectInboxCustodyOutboxEntry> rows = {};
  final Map<String, ConversationMessage> messages = {};
  final Set<String> throwCompletionOnce = {};

  @override
  bool get supportsDirectTextInboxCustody => true;

  String _key(String peerId, String messageId) => '$peerId\u0000$messageId';

  void seed(DirectInboxCustodyOutboxEntry entry, {String? messageStatus}) {
    rows[_key(entry.recipientPeerId, entry.messageId)] = entry;
    if (messageStatus != null) {
      messages[entry.messageId] = _message(
        entry.messageId,
        status: messageStatus,
      );
    }
  }

  @override
  Future<List<DirectInboxCustodyOutboxEntry>> loadDirectInboxCustody({
    int limit = 50,
  }) async {
    final ordered = rows.values.toList()
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
    return ordered.take(bounded).toList(growable: false);
  }

  @override
  Future<DirectInboxCustodyOutboxEntry?> loadDirectInboxCustodyForMessage({
    required String recipientPeerId,
    required String messageId,
  }) async => rows[_key(recipientPeerId, messageId)];

  @override
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    final key = _key(expected.recipientPeerId, expected.messageId);
    final current = rows[key];
    if (current == null || current.incarnationId != expected.incarnationId) {
      return false;
    }
    rows[key] = current.copyWith(
      retryCount: current.retryCount + 1,
      lastAttemptAt: '2026-08-06T12:00:00.000Z',
      lastErrorCode: errorCode,
      updatedAt: '2026-08-06T12:00:00.000Z',
    );
    return true;
  }

  @override
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    final key = _key(expected.recipientPeerId, expected.messageId);
    final currentEntry = rows[key];
    if (currentEntry == null ||
        currentEntry.incarnationId != expected.incarnationId) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.stale,
        message: null,
      );
    }
    if (throwCompletionOnce.remove(expected.messageId)) {
      throw StateError('injected local completion failure');
    }
    if (relayExpiresAt != null && relayExpiresAt <= 0) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.stale,
        message: null,
      );
    }

    rows.remove(key);
    final currentMessage = messages[expected.messageId];
    if (currentMessage == null) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messageRemoved,
        message: null,
      );
    }
    if (currentMessage.status == 'delivered' ||
        currentMessage.status == 'inboxed') {
      return DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.messagePreserved,
        message: currentMessage,
      );
    }
    final advanced = currentMessage.copyWith(
      status: 'inboxed',
      transport: 'inbox',
      relayExpiresAt: relayExpiresAt,
    );
    messages[expected.messageId] = advanced;
    return DirectInboxCustodyCompletionResult(
      outcome: DirectInboxCustodyCompletionOutcome.messageAdvanced,
      message: advanced,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'TC-342-04a exact at-least-once drain converges without poison starvation',
    () async {
      final repository = _InMemoryCustodyRepository();
      final poison = _entry('poison');
      final localFailure = _entry('local-failure');
      final stored = _entry('stored');
      final removed = _entry('removed');
      final rejected = _entry(
        'rejected',
        lastAttemptAt: '2026-08-06T10:30:00.000Z',
      );
      final failed = _entry(
        'failed',
        lastAttemptAt: '2026-08-06T11:00:00.000Z',
      );
      final duplicate = _entry(
        'duplicate',
        lastAttemptAt: '2026-08-06T11:30:00.000Z',
      );
      repository
        ..seed(poison, messageStatus: 'failed')
        ..seed(localFailure, messageStatus: 'failed')
        ..seed(stored, messageStatus: 'failed')
        ..seed(removed)
        ..seed(rejected, messageStatus: 'failed')
        ..seed(failed, messageStatus: 'failed')
        ..seed(duplicate, messageStatus: 'delivered')
        ..throwCompletionOnce.add(localFailure.messageId);

      final calls = <String>[];
      var localAttempts = 0;
      Future<InboxStoreOutcome> store(
        String peerId,
        String envelope, {
        int? timeoutMs,
      }) async {
        calls.add(envelope);
        if (envelope == poison.wireEnvelope) {
          throw StateError('poison store');
        }
        if (envelope == localFailure.wireEnvelope) {
          localAttempts++;
          return InboxStoreOutcome(
            status: localAttempts == 1
                ? InboxStoreStatus.stored
                : InboxStoreStatus.duplicate,
          );
        }
        if (envelope == rejected.wireEnvelope) {
          return const InboxStoreOutcome(status: InboxStoreStatus.rejectedFull);
        }
        if (envelope == failed.wireEnvelope) {
          return const InboxStoreOutcome(status: InboxStoreStatus.failed);
        }
        if (envelope == duplicate.wireEnvelope) {
          return InboxStoreOutcome.fromBridgeResponse(<String, dynamic>{
            'ok': true,
            'storeStatus': 'duplicate',
            'expiresAtMs': 0,
          });
        }
        return const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          expiresAtMs: 42,
        );
      }

      final completed = await drainDirectInboxCustodyOutbox(
        custodyRepository: repository,
        storeInInboxDetailed: store,
      );

      expect(completed, 3);
      expect(calls, hasLength(7));
      expect(calls.take(4), <String>[
        localFailure.wireEnvelope,
        poison.wireEnvelope,
        removed.wireEnvelope,
        stored.wireEnvelope,
      ]);
      expect(
        repository.rows.values
            .singleWhere((row) => row.messageId == poison.messageId)
            .lastErrorCode,
        DirectInboxCustodyErrorCode.storeThrew,
      );
      expect(
        repository.rows.values
            .singleWhere((row) => row.messageId == localFailure.messageId)
            .lastErrorCode,
        DirectInboxCustodyErrorCode.localCompletionFailed,
      );
      expect(
        repository.rows.values
            .singleWhere((row) => row.messageId == rejected.messageId)
            .lastErrorCode,
        DirectInboxCustodyErrorCode.storeRejectedFull,
      );
      expect(
        repository.rows.values
            .singleWhere((row) => row.messageId == failed.messageId)
            .lastErrorCode,
        DirectInboxCustodyErrorCode.storeFailed,
      );
      expect(repository.messages[stored.messageId]!.status, 'inboxed');
      expect(repository.messages[stored.messageId]!.relayExpiresAt, 42);
      expect(repository.messages[duplicate.messageId]!.status, 'delivered');
      expect(
        repository.rows.values.any(
          (row) => row.messageId == duplicate.messageId,
        ),
        isFalse,
        reason:
            'the production duplicate+zero bridge shape must retire custody',
      );
      expect(repository.messages.containsKey(removed.messageId), isFalse);

      final replay = await drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInInboxDetailed: store,
        recipientPeerId: localFailure.recipientPeerId,
        messageId: localFailure.messageId,
      );
      expect(replay.found, isTrue);
      expect(replay.completed, isTrue);
      expect(localAttempts, 2);
      expect(
        repository.rows.values.any(
          (row) => row.messageId == localFailure.messageId,
        ),
        isFalse,
      );
      expect(repository.messages[localFailure.messageId]!.status, 'inboxed');

      // The production repository caps each pass at 50. Retained failures get
      // an attempt timestamp, so the untouched 51st row must lead the next
      // pass instead of being starved by the first batch.
      final boundedRepository = _InMemoryCustodyRepository();
      final boundedEntries = List<DirectInboxCustodyOutboxEntry>.generate(
        51,
        (index) => _entry('batch-${index.toString().padLeft(2, '0')}'),
      );
      for (final entry in boundedEntries) {
        boundedRepository.seed(entry, messageStatus: 'failed');
      }
      final boundedCalls = <String>[];
      Future<InboxStoreOutcome> failStore(
        String peerId,
        String envelope, {
        int? timeoutMs,
      }) async {
        boundedCalls.add(envelope);
        return const InboxStoreOutcome(status: InboxStoreStatus.failed);
      }

      expect(
        await drainDirectInboxCustodyOutbox(
          custodyRepository: boundedRepository,
          storeInInboxDetailed: failStore,
        ),
        0,
      );
      expect(boundedCalls, hasLength(50));
      expect(boundedCalls, isNot(contains(boundedEntries.last.wireEnvelope)));
      final firstPassCalls = List<String>.of(boundedCalls);
      boundedCalls.clear();

      expect(
        await drainDirectInboxCustodyOutbox(
          custodyRepository: boundedRepository,
          storeInInboxDetailed: failStore,
        ),
        0,
      );
      expect(boundedCalls, hasLength(50));
      expect(boundedCalls.first, boundedEntries.last.wireEnvelope);
      expect(boundedCalls.skip(1), everyElement(isIn(firstPassCalls)));
      expect(
        boundedRepository.rows.values
            .singleWhere(
              (row) => row.messageId == boundedEntries.last.messageId,
            )
            .retryCount,
        1,
      );
    },
  );

  test(
    'concurrent exact drains converge through stored then duplicate',
    () async {
      final repository = _InMemoryCustodyRepository();
      final entry = _entry('concurrent');
      repository.seed(entry, messageStatus: 'failed');
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var calls = 0;

      Future<InboxStoreOutcome> store(
        String peerId,
        String envelope, {
        int? timeoutMs,
      }) async {
        calls++;
        if (calls == 1) {
          firstEntered.complete();
          await releaseFirst.future;
          return const InboxStoreOutcome(status: InboxStoreStatus.stored);
        }
        return const InboxStoreOutcome(status: InboxStoreStatus.duplicate);
      }

      final first = drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInInboxDetailed: store,
        recipientPeerId: entry.recipientPeerId,
        messageId: entry.messageId,
      );
      await firstEntered.future;
      final second = drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInInboxDetailed: store,
        recipientPeerId: entry.recipientPeerId,
        messageId: entry.messageId,
      );
      final secondResult = await second;
      releaseFirst.complete();
      final firstResult = await first;

      expect(calls, 2);
      expect(firstResult.completed, isTrue);
      expect(secondResult.completed, isTrue);
      expect(repository.rows, isEmpty);
      expect(repository.messages[entry.messageId]!.status, 'inboxed');
    },
  );
}
