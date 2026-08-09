import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DirectReactionInboxCustodyOutboxEntry _entry(
  String eventId, {
  String recipientPeerId = 'peer-target',
  String? lastAttemptAt,
  String? wireEnvelope,
}) => DirectReactionInboxCustodyOutboxEntry(
  recipientPeerId: recipientPeerId,
  eventId: eventId,
  wireEnvelope:
      wireEnvelope ??
      jsonEncode(<String, Object?>{
        'type': 'message_reaction',
        'version': '2',
        'eventId': eventId,
        'action': 'add',
        'targetMessageId': 'target-$eventId',
        'senderPeerId': 'self-peer',
        'encrypted': const <String, Object?>{
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      }),
  retryCount: 0,
  lastAttemptAt: lastAttemptAt,
  lastErrorCode: null,
  createdAt: '2026-08-07T10:00:00.000Z',
  updatedAt: '2026-08-07T10:00:00.000Z',
);

final class _InMemoryReactionCustodyRepository
    implements
        OutgoingDirectReactionInboxCustodyRepository,
        OutgoingDirectTextMutationInboxCustodyRepository {
  final Map<String, DirectReactionInboxCustodyOutboxEntry> rows = {};
  final Set<String> throwCompletionOnce = <String>{};
  final List<DirectReactionInboxCustodyOutboxEntry> completionExpected = [];
  final List<DirectReactionInboxCustodyOutboxEntry> failureExpected = [];
  final List<String> failureErrorCodes = [];

  String _key(String recipientPeerId, String eventId) =>
      '$recipientPeerId\u0000$eventId';

  void seed(DirectReactionInboxCustodyOutboxEntry entry) {
    rows[_key(entry.recipientPeerId, entry.eventId)] = entry;
  }

  void remove(DirectReactionInboxCustodyOutboxEntry entry) {
    rows.remove(_key(entry.recipientPeerId, entry.eventId));
  }

  @override
  bool get supportsDirectReactionInboxCustody => true;

  @override
  bool get supportsDirectTextMutationInboxCustody => true;

  @override
  bool get supportsDirectMutationInboxCustodyLifecycle => true;

  @override
  Future<List<DirectReactionInboxCustodyOutboxEntry>>
  loadDirectReactionInboxCustody({int limit = 50}) async {
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
        return byPeer != 0 ? byPeer : left.eventId.compareTo(right.eventId);
      });
    final bounded = limit < 0 ? 0 : (limit > 50 ? 50 : limit);
    return ordered.take(bounded).toList(growable: false);
  }

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectReactionInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) async => rows[_key(recipientPeerId, eventId)];

  @override
  Future<bool> recordDirectReactionInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    failureExpected.add(expected);
    failureErrorCodes.add(errorCode);
    final key = _key(expected.recipientPeerId, expected.eventId);
    final current = rows[key];
    if (current == null || current.wireEnvelope != expected.wireEnvelope) {
      return false;
    }
    rows[key] = current.copyWith(
      retryCount: current.retryCount + 1,
      lastAttemptAt: '2026-08-07T12:00:00.000Z',
      lastErrorCode: errorCode,
      updatedAt: '2026-08-07T12:00:00.000Z',
    );
    return true;
  }

  @override
  Future<DirectReactionInboxCustodyCompletionOutcome>
  completeAcceptedDirectReactionInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
  }) async {
    completionExpected.add(expected);
    final key = _key(expected.recipientPeerId, expected.eventId);
    final current = rows[key];
    if (current == null) {
      return DirectReactionInboxCustodyCompletionOutcome.absent;
    }
    if (current.wireEnvelope != expected.wireEnvelope) {
      return DirectReactionInboxCustodyCompletionOutcome.stale;
    }
    if (throwCompletionOnce.remove(expected.eventId)) {
      throw StateError('injected exact local completion failure');
    }
    rows.remove(key);
    return DirectReactionInboxCustodyCompletionOutcome.completed;
  }

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) => recordDirectReactionInboxCustodyFailureIfExact(
    expected: expected,
    errorCode: errorCode,
  );

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    completionExpected.add(expected);
    final key = _key(expected.recipientPeerId, expected.eventId);
    final current = rows[key];
    if (current == null) {
      return DirectMutationInboxCustodyCompletionOutcome.absent;
    }
    if (current.wireEnvelope != expected.wireEnvelope) {
      return DirectMutationInboxCustodyCompletionOutcome.stale;
    }
    rows.remove(key);
    return DirectMutationInboxCustodyCompletionOutcome.completed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'TC-349-04 one fair batch routes reaction edit and deletion kinds',
    () async {
      final repository = _InMemoryReactionCustodyRepository();
      final reaction = _entry('01-reaction');
      final edit = _entry('02-edit', wireEnvelope: _editEnvelope('02-edit'));
      final malformed = _entry('03-malformed', wireEnvelope: '{bad-json');
      final deletion = _entry(
        '04-deletion',
        wireEnvelope: _deletionEnvelope('04-deletion'),
      );
      for (final entry in <DirectReactionInboxCustodyOutboxEntry>[
        reaction,
        edit,
        malformed,
        deletion,
      ]) {
        repository.seed(entry);
      }

      final routedKinds = <AckCustodyKind>[];
      final completed = await drainDirectReactionInboxCustodyOutbox(
        custodyRepository: repository,
        mutationCustodyRepository: repository,
        storeInAckCustodyInboxDetailed:
            (
              recipientPeerId,
              wireEnvelope, {
              required custodyKind,
              timeoutMs,
            }) async {
              routedKinds.add(custodyKind);
              return const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                storeStatus: 'stored',
                custodyContract: ackOrExpiryInboxCustodyContract,
              );
            },
      );

      expect(completed, 3);
      expect(routedKinds, <AckCustodyKind>[
        AckCustodyKind.directReactionV109,
        AckCustodyKind.directMutationV109,
        AckCustodyKind.directMutationV109,
      ]);
      expect(repository.rows.values.single.eventId, malformed.eventId);
      expect(
        repository.rows.values.single.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.storeFailed,
      );
    },
  );

  test('Plan 344 v109 drain retains generic stored without proof', () async {
    final repository = _InMemoryReactionCustodyRepository();
    final pending = _entry('unproven');
    repository.seed(pending);

    final completed = await drainDirectReactionInboxCustodyOutbox(
      custodyRepository: repository,
      storeInAckCustodyInboxDetailed:
          (peerId, envelope, {required custodyKind, timeoutMs}) async {
            expect(custodyKind, AckCustodyKind.directReactionV109);
            return const InboxStoreOutcome(status: InboxStoreStatus.stored);
          },
    );

    expect(completed, 0);
    expect(repository.rows, hasLength(1));
    expect(repository.failureErrorCodes, <String>[
      DirectReactionInboxCustodyErrorCode.storeFailed,
    ]);
  });

  test(
    'TC-343-04 exact at-least-once reaction drain converges without poison starvation',
    () async {
      final repository = _InMemoryReactionCustodyRepository();
      final poison = _entry('00-poison', recipientPeerId: 'peer-poison');
      final localFailure = _entry(
        '01-local-failure',
        recipientPeerId: 'peer-local-failure',
      );
      final stored = _entry('02-stored', recipientPeerId: 'peer-stored');
      final absent = _entry('03-absent', recipientPeerId: 'peer-absent');
      final duplicate = _entry(
        '04-duplicate',
        recipientPeerId: 'peer-duplicate',
      );
      final rejected = _entry(
        '05-rejected',
        recipientPeerId: 'peer-rejected',
        lastAttemptAt: '2026-08-07T10:30:00.000Z',
      );
      final failed = _entry(
        '06-failed',
        recipientPeerId: 'peer-failed',
        lastAttemptAt: '2026-08-07T11:00:00.000Z',
      );
      for (final entry in <DirectReactionInboxCustodyOutboxEntry>[
        poison,
        localFailure,
        stored,
        absent,
        duplicate,
        rejected,
        failed,
      ]) {
        repository.seed(entry);
      }
      repository.throwCompletionOnce.add(localFailure.eventId);

      final eventByEnvelope = <String, String>{
        for (final entry in repository.rows.values)
          entry.wireEnvelope: entry.eventId,
      };
      final calls =
          <({String recipientPeerId, String eventId, String wireEnvelope})>[];
      var localAttempts = 0;
      Future<InboxStoreOutcome> store(
        String recipientPeerId,
        String wireEnvelope, {
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        expect(custodyKind, AckCustodyKind.directReactionV109);
        calls.add((
          recipientPeerId: recipientPeerId,
          eventId: eventByEnvelope[wireEnvelope]!,
          wireEnvelope: wireEnvelope,
        ));
        if (wireEnvelope == poison.wireEnvelope) {
          throw StateError('injected remote poison');
        }
        if (wireEnvelope == localFailure.wireEnvelope) {
          localAttempts++;
          return InboxStoreOutcome(
            status: localAttempts == 1
                ? InboxStoreStatus.stored
                : InboxStoreStatus.duplicate,
            storeStatus: localAttempts == 1 ? 'stored' : 'duplicate',
            custodyContract: ackOrExpiryInboxCustodyContract,
          );
        }
        if (wireEnvelope == absent.wireEnvelope) {
          repository.remove(absent);
          return const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          );
        }
        if (wireEnvelope == duplicate.wireEnvelope) {
          return const InboxStoreOutcome(
            status: InboxStoreStatus.duplicate,
            storeStatus: 'duplicate',
            custodyContract: ackOrExpiryInboxCustodyContract,
          );
        }
        if (wireEnvelope == rejected.wireEnvelope) {
          return const InboxStoreOutcome(status: InboxStoreStatus.rejectedFull);
        }
        if (wireEnvelope == failed.wireEnvelope) {
          return const InboxStoreOutcome(status: InboxStoreStatus.failed);
        }
        return const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          storeStatus: 'stored',
          custodyContract: ackOrExpiryInboxCustodyContract,
        );
      }

      expect(
        await drainDirectReactionInboxCustodyOutbox(
          custodyRepository: repository,
          storeInAckCustodyInboxDetailed: store,
        ),
        3,
      );
      expect(calls, hasLength(7));
      for (final call in calls) {
        final staged = <DirectReactionInboxCustodyOutboxEntry>[
          poison,
          localFailure,
          stored,
          absent,
          duplicate,
          rejected,
          failed,
        ].singleWhere((entry) => entry.eventId == call.eventId);
        expect(call.recipientPeerId, staged.recipientPeerId);
        expect(call.wireEnvelope, staged.wireEnvelope);
      }
      expect(repository.completionExpected.map(_exactTuple).toSet(), <String>{
        _exactTuple(localFailure),
        _exactTuple(stored),
        _exactTuple(absent),
        _exactTuple(duplicate),
      });
      expect(repository.failureExpected.map(_exactTuple).toSet(), <String>{
        _exactTuple(poison),
        _exactTuple(localFailure),
        _exactTuple(rejected),
        _exactTuple(failed),
      });
      expect(
        repository.failureErrorCodes,
        containsAll(<String>{
          DirectReactionInboxCustodyErrorCode.storeThrew,
          DirectReactionInboxCustodyErrorCode.localCompletionFailed,
          DirectReactionInboxCustodyErrorCode.storeRejectedFull,
          DirectReactionInboxCustodyErrorCode.storeFailed,
        }),
      );
      expect(
        repository.rows[_keyOf(localFailure)]!.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.localCompletionFailed,
      );
      expect(
        repository.rows[_keyOf(rejected)]!.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.storeRejectedFull,
      );
      expect(
        repository.rows[_keyOf(failed)]!.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.storeFailed,
      );
      expect(
        repository.rows[_keyOf(poison)]!.lastErrorCode,
        DirectReactionInboxCustodyErrorCode.storeThrew,
      );
      expect(repository.rows[_keyOf(poison)]!.retryCount, 1);
      expect(repository.rows.containsKey(_keyOf(stored)), isFalse);
      expect(repository.rows.containsKey(_keyOf(failed)), isTrue);
      expect(repository.rows.containsKey(_keyOf(absent)), isFalse);
      expect(repository.rows.containsKey(_keyOf(duplicate)), isFalse);

      // Duplicate replay retires the retained exact event after an accepted
      // store whose first local completion threw.
      repository
        ..remove(poison)
        ..remove(rejected)
        ..remove(failed);
      expect(
        await drainDirectReactionInboxCustodyOutbox(
          custodyRepository: repository,
          storeInAckCustodyInboxDetailed: store,
        ),
        1,
      );
      expect(localAttempts, 2);
      expect(repository.rows, isEmpty);

      // The repository batch is capped at 50 and retry timestamps move failed
      // rows behind the untouched 51st row on the next fair pass.
      final boundedRepository = _InMemoryReactionCustodyRepository();
      final boundedEntries =
          List<DirectReactionInboxCustodyOutboxEntry>.generate(
            51,
            (index) => _entry('batch-${index.toString().padLeft(2, '0')}'),
          );
      for (final entry in boundedEntries) {
        boundedRepository.seed(entry);
      }
      final boundedCalls = <String>[];
      Future<InboxStoreOutcome> failStore(
        String recipientPeerId,
        String wireEnvelope, {
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        boundedCalls.add(wireEnvelope);
        return const InboxStoreOutcome(status: InboxStoreStatus.failed);
      }

      expect(
        await drainDirectReactionInboxCustodyOutbox(
          custodyRepository: boundedRepository,
          storeInAckCustodyInboxDetailed: failStore,
        ),
        0,
      );
      expect(boundedCalls, hasLength(50));
      expect(boundedCalls, isNot(contains(boundedEntries.last.wireEnvelope)));
      boundedCalls.clear();
      expect(
        await drainDirectReactionInboxCustodyOutbox(
          custodyRepository: boundedRepository,
          storeInAckCustodyInboxDetailed: failStore,
        ),
        0,
      );
      expect(boundedCalls, hasLength(50));
      expect(boundedCalls.first, boundedEntries.last.wireEnvelope);

      // Overlapping accepted attempts converge: one exact delete wins and the
      // other observes `absent` without reconstructing or retaining the event.
      final overlapRepository = _InMemoryReactionCustodyRepository();
      final overlapEntry = _entry('overlap');
      overlapRepository.seed(overlapEntry);
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var overlapCalls = 0;
      Future<InboxStoreOutcome> overlappingStore(
        String recipientPeerId,
        String wireEnvelope, {
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        expect(custodyKind, AckCustodyKind.directReactionV109);
        expect(recipientPeerId, overlapEntry.recipientPeerId);
        expect(wireEnvelope, overlapEntry.wireEnvelope);
        overlapCalls++;
        if (overlapCalls == 1) {
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

      final first = drainDirectReactionInboxCustodyOutbox(
        custodyRepository: overlapRepository,
        storeInAckCustodyInboxDetailed: overlappingStore,
      );
      await firstEntered.future;
      final second = drainDirectReactionInboxCustodyOutbox(
        custodyRepository: overlapRepository,
        storeInAckCustodyInboxDetailed: overlappingStore,
      );
      expect(await second, 1);
      releaseFirst.complete();
      expect(await first, 1);
      expect(overlapCalls, 2);
      expect(overlapRepository.rows, isEmpty);
    },
  );
}

String _editEnvelope(String eventId) => jsonEncode(<String, Object?>{
  'type': 'chat_message',
  'version': '2',
  'id': 'target-edit',
  'eventId': eventId,
  'senderPeerId': 'self-peer',
  'encrypted': const <String, Object?>{
    'kem': 'kem',
    'ciphertext': 'ciphertext',
    'nonce': 'nonce',
  },
});

String _deletionEnvelope(String eventId) => jsonEncode(<String, Object?>{
  'type': 'message_deletion',
  'version': '2',
  'eventId': eventId,
  'senderPeerId': 'self-peer',
  'encrypted': const <String, Object?>{
    'kem': 'kem',
    'ciphertext': 'ciphertext',
    'nonce': 'nonce',
  },
});

String _keyOf(DirectReactionInboxCustodyOutboxEntry entry) =>
    '${entry.recipientPeerId}\u0000${entry.eventId}';

String _exactTuple(DirectReactionInboxCustodyOutboxEntry entry) =>
    '${entry.recipientPeerId}\u0000${entry.eventId}\u0000${entry.wireEnvelope}';
