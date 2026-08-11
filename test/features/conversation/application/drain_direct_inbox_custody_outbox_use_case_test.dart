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
  String? mediaBlobManifestHash,
  int? mediaBlobExpiresAtMs,
}) => DirectInboxCustodyOutboxEntry(
  recipientPeerId: 'peer-$id',
  messageId: id,
  incarnationId: id.padRight(32, '0').substring(0, 32),
  wireEnvelope: 'wire-$id',
  retryCount: retryCount,
  lastAttemptAt: lastAttemptAt,
  lastErrorCode: null,
  mediaBlobManifestHash: mediaBlobManifestHash,
  mediaBlobExpiresAtMs: mediaBlobExpiresAtMs,
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
  Future<DirectInboxCustodyOutboxEntry?>
  loadDirectInboxCustodyOwnerForMessageId({required String messageId}) async {
    final matches = rows.values
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
    final siblingSurvives = rows.values.any(
      (entry) => entry.messageId == expected.messageId,
    );
    if (siblingSurvives ||
        currentMessage.status == 'delivered' ||
        currentMessage.status == 'inboxed') {
      // 361: only the FINAL surviving sibling of a fanout generation may
      // project the canonical transition — mirrors the v113 DB owner.
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
    'TC-347-05b media v108 retires only on envelope expiry at or before blob bound',
    () async {
      const manifestHash =
          '3473473473473473473473473473473473473473473473473473473473473473';
      const blobExpiry = 1999999999000;
      final repository = _InMemoryCustodyRepository();
      final exact = _entry(
        'strict-exact',
        mediaBlobManifestHash: manifestHash,
        mediaBlobExpiresAtMs: blobExpiry,
      );
      repository.seed(exact, messageStatus: 'failed');
      var legacyCalls = 0;
      var boundedCalls = 0;

      final completed = await drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInAckCustodyInboxDetailed:
            (peerId, envelope, {required custodyKind, timeoutMs}) async {
              legacyCalls++;
              return const InboxStoreOutcome(status: InboxStoreStatus.stored);
            },
        storeInMediaExpiryBoundedInboxDetailed:
            (
              peerId,
              envelope, {
              required custodyExpiresAtOrBeforeMs,
              timeoutMs,
            }) async {
              boundedCalls++;
              expect(peerId, exact.recipientPeerId);
              expect(envelope, exact.wireEnvelope);
              expect(custodyExpiresAtOrBeforeMs, blobExpiry);
              return const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                storeStatus: 'stored',
                custodyContract: ackOrExpiryInboxCustodyContract,
                expiresAtMs: blobExpiry,
              );
            },
        recipientPeerId: exact.recipientPeerId,
        messageId: exact.messageId,
      );
      expect(completed.completed, isTrue);
      expect(repository.rows, isEmpty);
      expect(repository.messages[exact.messageId]!.relayExpiresAt, blobExpiry);
      expect(boundedCalls, 1);
      expect(legacyCalls, 0);

      for (final invalid in <({String id, int? expiry})>[
        (id: 'strict-missing-proof', expiry: null),
        (id: 'strict-later-proof', expiry: blobExpiry + 1),
      ]) {
        final retained = _entry(
          invalid.id,
          mediaBlobManifestHash: manifestHash,
          mediaBlobExpiresAtMs: blobExpiry,
        );
        repository.seed(retained, messageStatus: 'failed');
        final attempt = await drainDirectInboxCustodyOutboxForMessage(
          custodyRepository: repository,
          storeInAckCustodyInboxDetailed:
              (peerId, envelope, {required custodyKind, timeoutMs}) async {
                legacyCalls++;
                return const InboxStoreOutcome(status: InboxStoreStatus.stored);
              },
          storeInMediaExpiryBoundedInboxDetailed:
              (
                peerId,
                envelope, {
                required custodyExpiresAtOrBeforeMs,
                timeoutMs,
              }) async => InboxStoreOutcome(
                status: InboxStoreStatus.duplicate,
                storeStatus: 'duplicate',
                custodyContract: ackOrExpiryInboxCustodyContract,
                expiresAtMs: invalid.expiry,
              ),
          recipientPeerId: retained.recipientPeerId,
          messageId: retained.messageId,
        );
        expect(attempt.completed, isFalse, reason: invalid.id);
        expect(
          repository.rows.values.any(
            (entry) => entry.messageId == retained.messageId,
          ),
          isTrue,
          reason: invalid.id,
        );
      }

      final noCapability = _entry(
        'strict-no-capability',
        mediaBlobManifestHash: manifestHash,
        mediaBlobExpiresAtMs: blobExpiry,
      );
      repository.seed(noCapability, messageStatus: 'failed');
      final absentSibling = await drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInAckCustodyInboxDetailed:
            (peerId, envelope, {required custodyKind, timeoutMs}) async {
              legacyCalls++;
              return const InboxStoreOutcome(status: InboxStoreStatus.stored);
            },
        recipientPeerId: noCapability.recipientPeerId,
        messageId: noCapability.messageId,
      );
      expect(absentSibling.completed, isFalse);
      expect(legacyCalls, 0, reason: 'strict rows must never fall back');
      expect(
        repository.rows.values.any(
          (entry) => entry.messageId == noCapability.messageId,
        ),
        isTrue,
      );
    },
  );

  test('Plan 344 v108 drain retains generic stored without proof', () async {
    final repository = _InMemoryCustodyRepository();
    final pending = _entry('unproven');
    repository.seed(pending, messageStatus: 'failed');

    final completed = await drainDirectInboxCustodyOutbox(
      custodyRepository: repository,
      storeInAckCustodyInboxDetailed:
          (peerId, envelope, {required custodyKind, timeoutMs}) async {
            expect(custodyKind, AckCustodyKind.directTextV108);
            return const InboxStoreOutcome(status: InboxStoreStatus.stored);
          },
    );

    expect(completed, 0);
    expect(repository.rows, hasLength(1));
    expect(
      repository.rows.values.single.lastErrorCode,
      DirectInboxCustodyErrorCode.storeFailed,
    );
  });

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
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        expect(custodyKind, AckCustodyKind.directTextV108);
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
            storeStatus: localAttempts == 1 ? 'stored' : 'duplicate',
            custodyContract: ackOrExpiryInboxCustodyContract,
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
            'custodyContract': ackOrExpiryInboxCustodyContract,
          });
        }
        return const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          storeStatus: 'stored',
          expiresAtMs: 42,
          custodyContract: ackOrExpiryInboxCustodyContract,
        );
      }

      final completed = await drainDirectInboxCustodyOutbox(
        custodyRepository: repository,
        storeInAckCustodyInboxDetailed: store,
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
        storeInAckCustodyInboxDetailed: store,
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
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        boundedCalls.add(envelope);
        return const InboxStoreOutcome(status: InboxStoreStatus.failed);
      }

      expect(
        await drainDirectInboxCustodyOutbox(
          custodyRepository: boundedRepository,
          storeInAckCustodyInboxDetailed: failStore,
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
          storeInAckCustodyInboxDetailed: failStore,
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
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        expect(custodyKind, AckCustodyKind.directTextV108);
        calls++;
        if (calls == 1) {
          firstEntered.complete();
          await releaseFirst.future;
          return const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          );
        }
        return const InboxStoreOutcome(
          status: InboxStoreStatus.duplicate,
          storeStatus: 'duplicate',
          custodyContract: ackOrExpiryInboxCustodyContract,
        );
      }

      final first = drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInAckCustodyInboxDetailed: store,
        recipientPeerId: entry.recipientPeerId,
        messageId: entry.messageId,
      );
      await firstEntered.future;
      final second = drainDirectInboxCustodyOutboxForMessage(
        custodyRepository: repository,
        storeInAckCustodyInboxDetailed: store,
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

  test('TC-361-01b fanout siblings drain independently: one acceptance never '
      'cancels or downgrades the other row', () async {
    final repository = _InMemoryCustodyRepository();
    final siblingA = _entry('fanout-message').copyWith(
      recipientPeerId: 'peer-device-a',
      incarnationId: 'aaaa0000aaaa0000aaaa0000aaaa0000',
      wireEnvelope: 'wire-fanout-device-a',
      contactAccountPeerId: 'peer-contact-account',
    );
    final siblingB = _entry('fanout-message').copyWith(
      recipientPeerId: 'peer-device-b',
      incarnationId: 'bbbb0000bbbb0000bbbb0000bbbb0000',
      wireEnvelope: 'wire-fanout-device-b',
      contactAccountPeerId: 'peer-contact-account',
    );
    repository.seed(siblingA, messageStatus: 'sending');
    repository.seed(siblingB);

    final storedPayloads = <String, String>{};
    Future<InboxStoreOutcome> store(
      String toPeerId,
      String message, {
      required AckCustodyKind custodyKind,
      int? timeoutMs,
    }) async {
      storedPayloads[toPeerId] = message;
      expect(custodyKind, AckCustodyKind.directTextV108);
      if (toPeerId == 'peer-device-b') {
        return const InboxStoreOutcome(status: InboxStoreStatus.failed);
      }
      return const InboxStoreOutcome(
        status: InboxStoreStatus.stored,
        storeStatus: 'stored',
        custodyContract: ackOrExpiryInboxCustodyContract,
        expiresAtMs: 1900000060000,
      );
    }

    final completed = await drainDirectInboxCustodyOutbox(
      custodyRepository: repository,
      storeInAckCustodyInboxDetailed: store,
    );

    expect(completed, 1);
    expect(storedPayloads, {
      'peer-device-a': 'wire-fanout-device-a',
      'peer-device-b': 'wire-fanout-device-b',
    }, reason: 'each sibling replays its own exact immutable bytes');
    expect(
      repository.rows.values.single.recipientPeerId,
      'peer-device-b',
      reason: 'the accepted sibling retires alone; the failed one survives',
    );
    expect(repository.rows.values.single.retryCount, 1);
    expect(
      repository.messages['fanout-message']!.status,
      'sending',
      reason:
          'a non-final sibling acceptance never projects the canonical '
          'message',
    );
  });
}
