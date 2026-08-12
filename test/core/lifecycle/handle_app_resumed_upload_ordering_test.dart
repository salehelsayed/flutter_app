import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/app/bootstrap/direct_blob_free_linked_services.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_blob_free_linked_event_fanout_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';

Future<int> _drainBothDirectCustodyFamilies(
  List<String> calls, {
  String? throwingFamily,
}) async {
  var completed = 0;
  try {
    calls.add('drainDirectTextInboxCustody');
    if (throwingFamily == 'text') {
      throw StateError('forced text custody drain failure');
    }
    completed++;
  } catch (_) {
    // Mirrors the production composite's per-family error boundary.
  }
  try {
    calls.add('drainDirectReactionInboxCustody');
    if (throwingFamily == 'reaction') {
      throw StateError('forced reaction custody drain failure');
    }
    completed++;
  } catch (_) {
    // Mirrors the production composite's per-family error boundary.
  }
  return completed;
}

// Helpers to track call ordering across all four recovery steps.
// Each callback appends its name to the shared `callOrder` list
// so we can assert exact sequential ordering.

/// 361: records completions/failures so the linked-drain row can prove which
/// custody tuples were touched at all.
final class _LinkedFanoutTextCustodyRepository
    implements OutgoingDirectTextInboxCustodyRepository {
  final List<String> completedMessageIds = [];
  final List<String> failureMessageIds = [];

  @override
  bool get supportsDirectTextInboxCustody => true;

  @override
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    completedMessageIds.add(expected.messageId);
    return const DirectInboxCustodyCompletionResult(
      outcome: DirectInboxCustodyCompletionOutcome.messageAdvanced,
      message: null,
    );
  }

  @override
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    failureMessageIds.add(expected.messageId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LinkedFanoutReactionCustodyRepository
    implements OutgoingDirectReactionInboxCustodyRepository {
  final List<String> completedEventIds = [];
  final List<String> failureEventIds = [];

  @override
  bool get supportsDirectReactionInboxCustody => true;

  @override
  Future<DirectReactionInboxCustodyCompletionOutcome>
  completeAcceptedDirectReactionInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
  }) async {
    completedEventIds.add(expected.eventId);
    return DirectReactionInboxCustodyCompletionOutcome.completed;
  }

  @override
  Future<bool> recordDirectReactionInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) async {
    failureEventIds.add(expected.eventId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _linkedTextFanoutRow(
  String messageId, {
  String? contactAccountPeerId,
  String? mediaBlobManifestHash,
  int? mediaBlobExpiresAtMs,
}) => <String, Object?>{
  'recipient_peer_id': 'transport-$messageId',
  'message_id': messageId,
  'incarnation_id': messageId.padRight(32, '0').substring(0, 32),
  'wire_envelope': 'wire-$messageId',
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'media_blob_manifest_hash': mediaBlobManifestHash,
  'media_blob_expires_at_ms': mediaBlobExpiresAtMs,
  'contact_account_peer_id': contactAccountPeerId,
  'created_at': '2026-08-10T10:00:00.000Z',
  'updated_at': '2026-08-10T10:00:00.000Z',
};

Map<String, Object?> _linkedEventFanoutRow(
  String eventId, {
  String? contactAccountPeerId,
  String? wireEnvelope,
}) => <String, Object?>{
  'recipient_peer_id': 'transport-$eventId',
  'event_id': eventId,
  'wire_envelope':
      wireEnvelope ??
      jsonEncode({
        'type': 'message_reaction',
        'version': '2',
        'eventId': eventId,
        'action': 'add',
        'targetMessageId': 'parent-$eventId',
        'senderPeerId': 'transport-$eventId',
        'encrypted': {'kem': 'k', 'ciphertext': 'c', 'nonce': 'n'},
      }),
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'contact_account_peer_id': contactAccountPeerId,
  'parent_message_id': 'parent-$eventId',
  'created_at': '2026-08-10T10:00:00.000Z',
  'updated_at': '2026-08-10T10:00:00.000Z',
};

void main() {
  late FakeBridge fakeBridge;
  late FakeP2PService fakeP2PService;

  setUp(() {
    fakeBridge = FakeBridge();
    fakeP2PService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'my-peer',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
    );
  });

  tearDown(() {
    fakeP2PService.dispose();
  });

  group('handleAppResumed -- retryIncompleteUploads ordering', () {
    test(
      'TC-347-07c resume orders blob recovery before mutable upload retry',
      () async {
        final callOrder = <String>[];

        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          directMediaBlobLocalCleanupFn: () async {
            callOrder.add('directMediaBlobLocalCleanup');
            return 1;
          },
          recoverStuckSendingMessagesFn: () async {
            callOrder.add('recoverStuckSendingMessages');
            return 0;
          },
          drainDirectMediaBlobCustodyFn: () async {
            callOrder.add('drainDirectMediaBlobCustody');
            return 2;
          },
          retryIncompleteUploadsFn: () async {
            callOrder.add('retryIncompleteUploads');
            return 0;
          },
          drainDirectInboxCustodyOutboxFn: () async {
            callOrder.add('drainDirectInboxCustodyOutbox');
            return 0;
          },
          retryFailedMessagesFn: () async {
            callOrder.add('retryFailedMessages');
            return 0;
          },
        );

        expect(callOrder, <String>[
          'directMediaBlobLocalCleanup',
          'recoverStuckSendingMessages',
          'drainDirectMediaBlobCustody',
          'retryIncompleteUploads',
          'drainDirectInboxCustodyOutbox',
          'retryFailedMessages',
        ]);
      },
    );

    test(
      'TC-343-05 resume drains both direct custody families before failed and unacked rebuild',
      () async {
        for (final throwingFamily in const <String>['text', 'reaction']) {
          final callOrder = <String>[];

          await handleAppResumed(
            bridge: fakeBridge,
            p2pService: fakeP2PService,
            recoverStuckSendingMessagesFn: () async {
              callOrder.add('recoverStuckSendingMessages');
              return 0;
            },
            retryIncompleteUploadsFn: () async {
              callOrder.add('retryIncompleteUploads');
              return 0;
            },
            drainDirectInboxCustodyOutboxFn: () =>
                _drainBothDirectCustodyFamilies(
                  callOrder,
                  throwingFamily: throwingFamily,
                ),
            retryFailedMessagesFn: () async {
              callOrder.add('retryFailedMessages');
              return 0;
            },
            retryUnackedMessagesFn: () async {
              callOrder.add('retryUnackedMessages');
              return 0;
            },
          );

          expect(callOrder, <String>[
            'recoverStuckSendingMessages',
            'retryIncompleteUploads',
            'drainDirectTextInboxCustody',
            'drainDirectReactionInboxCustody',
            'retryFailedMessages',
            'retryUnackedMessages',
          ]);
        }
      },
    );

    test(
      'resume isolates key exchange and post retry throws before custody and message recovery',
      () async {
        final callOrder = <String>[];

        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          contactRepo: FakeContactRepository(),
          identityRepo: FakeIdentityRepository(),
          retryIncompleteKeyExchangesFn: () async {
            callOrder.add('retryIncompleteKeyExchanges');
            throw StateError('forced key exchange failure');
          },
          retryPendingPostMediaUploads: () async {
            callOrder.add('retryPendingPostMediaUploads');
            throw StateError('forced post media failure');
          },
          retryPendingPostDeliveries: () async {
            callOrder.add('retryPendingPostDeliveries');
            throw StateError('forced post delivery failure');
          },
          drainDirectInboxCustodyOutboxFn: () async {
            callOrder.add('drainDirectInboxCustodyOutbox');
            return 0;
          },
          retryFailedMessagesFn: () async {
            callOrder.add('retryFailedMessages');
            return 0;
          },
          retryUnackedMessagesFn: () async {
            callOrder.add('retryUnackedMessages');
            return 0;
          },
        );

        expect(callOrder, <String>[
          'retryIncompleteKeyExchanges',
          'retryPendingPostMediaUploads',
          'retryPendingPostDeliveries',
          'drainDirectInboxCustodyOutbox',
          'retryFailedMessages',
          'retryUnackedMessages',
        ]);
      },
    );

    test(
      'calls custody verification after retryUnackedMessages and before introduction retry',
      () async {
        final callOrder = <String>[];

        Future<int> fakeRecoverStuck() async {
          callOrder.add('recoverStuckSendingMessages');
          return 0;
        }

        Future<int> fakeRetryIncompleteUploads() async {
          callOrder.add('retryIncompleteUploads');
          return 0;
        }

        Future<int> fakeRetryFailed() async {
          callOrder.add('retryFailedMessages');
          return 0;
        }

        Future<int> fakeRetryUnacked() async {
          callOrder.add('retryUnackedMessages');
          return 0;
        }

        Future<int> fakeVerifyInboxCustody() async {
          callOrder.add('verifyInboxCustody');
          return 0;
        }

        Future<int> fakeRetryPendingIntroductions() async {
          callOrder.add('retryPendingIntroductionDeliveries');
          return 0;
        }

        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          recoverStuckSendingMessagesFn: fakeRecoverStuck, // Part A
          retryIncompleteUploadsFn: fakeRetryIncompleteUploads, // Part G -- NEW
          retryFailedMessagesFn: fakeRetryFailed, // Parts B/C
          retryUnackedMessagesFn: fakeRetryUnacked, // existing
          verifyInboxCustodyFn: fakeVerifyInboxCustody,
          retryPendingIntroductionDeliveriesFn: fakeRetryPendingIntroductions,
        );

        expect(callOrder, [
          'recoverStuckSendingMessages',
          'retryIncompleteUploads',
          'retryFailedMessages',
          'retryUnackedMessages',
          'verifyInboxCustody',
          'retryPendingIntroductionDeliveries',
        ]);
      },
    );

    test(
      'if retryIncompleteUploads throws, retryFailedMessages still runs (fault isolation)',
      () async {
        final callOrder = <String>[];

        Future<int> fakeRecoverStuck() async {
          callOrder.add('recoverStuckSendingMessages');
          return 0;
        }

        Future<int> fakeRetryIncompleteUploadsThatThrows() async {
          callOrder.add('retryIncompleteUploads');
          throw Exception('CDN upload timeout');
        }

        Future<int> fakeRetryFailed() async {
          callOrder.add('retryFailedMessages');
          return 0;
        }

        Future<int> fakeRetryUnacked() async {
          callOrder.add('retryUnackedMessages');
          return 0;
        }

        Future<int> fakeVerifyInboxCustody() async {
          callOrder.add('verifyInboxCustody');
          return 0;
        }

        Future<int> fakeRetryPendingIntroductions() async {
          callOrder.add('retryPendingIntroductionDeliveries');
          return 0;
        }

        // Must not throw -- handleAppResumed swallows individual step errors
        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          recoverStuckSendingMessagesFn: fakeRecoverStuck,
          retryIncompleteUploadsFn: fakeRetryIncompleteUploadsThatThrows,
          retryFailedMessagesFn: fakeRetryFailed,
          retryUnackedMessagesFn: fakeRetryUnacked,
          verifyInboxCustodyFn: fakeVerifyInboxCustody,
          retryPendingIntroductionDeliveriesFn: fakeRetryPendingIntroductions,
        );

        // retryIncompleteUploads threw, but retryFailedMessages and
        // retryUnackedMessages still executed
        expect(callOrder, [
          'recoverStuckSendingMessages',
          'retryIncompleteUploads',
          'retryFailedMessages',
          'retryUnackedMessages',
          'verifyInboxCustody',
          'retryPendingIntroductionDeliveries',
        ]);
      },
    );

    test(
      'if retryPendingIntroductionDeliveries throws, later recovery steps still run',
      () async {
        final callOrder = <String>[];

        Future<int> fakeRetryFailed() async {
          callOrder.add('retryFailedMessages');
          return 0;
        }

        Future<int> fakeRetryUnacked() async {
          callOrder.add('retryUnackedMessages');
          return 0;
        }

        Future<int> fakeVerifyInboxCustody() async {
          callOrder.add('verifyInboxCustody');
          return 0;
        }

        Future<int> fakeRetryPendingIntroductionsThatThrows() async {
          callOrder.add('retryPendingIntroductionDeliveries');
          throw Exception('intro inbox unavailable');
        }

        Future<int> fakeRetryFailedGroupInboxStores() async {
          callOrder.add('retryFailedGroupInboxStores');
          return 0;
        }

        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          retryFailedMessagesFn: fakeRetryFailed,
          retryUnackedMessagesFn: fakeRetryUnacked,
          verifyInboxCustodyFn: fakeVerifyInboxCustody,
          retryPendingIntroductionDeliveriesFn:
              fakeRetryPendingIntroductionsThatThrows,
          retryFailedGroupInboxStoresFn: fakeRetryFailedGroupInboxStores,
        );

        expect(callOrder, [
          'retryFailedMessages',
          'retryUnackedMessages',
          'verifyInboxCustody',
          'retryPendingIntroductionDeliveries',
          'retryFailedGroupInboxStores',
        ]);
      },
    );

    test(
      'retryIncompleteUploadsFn callback signature matches Future<int> Function() pattern',
      () async {
        // Validates the callback type is identical to the other retry callbacks,
        // ensuring uniform DI wiring in main.dart
        int callCount = 0;
        Future<int> fakeRetryIncompleteUploads() async {
          callCount++;
          return 3; // e.g., re-uploaded 3 attachments
        }

        await handleAppResumed(
          bridge: fakeBridge,
          p2pService: fakeP2PService,
          retryIncompleteUploadsFn: fakeRetryIncompleteUploads,
        );

        expect(callCount, 1);
      },
    );
  });

  group('TC-361-03b restricted linked resume drain', () {
    test(
      'TC-361-03b linked runtime starts only direct blob-free event owners — '
      'the exact v113 drain completes only nonnull blob-free rows and leaves '
      'historical, media and unclassifiable rows byte-untouched with the '
      'authoring selector OFF',
      () async {
        // The restricted drain consults no authoring selector at all; the
        // build-default selector stays OFF while durable rows still drain.
        expect(
          const DirectLinkedEventFanoutSelector()
              .allowsDirectLinkedEventFanoutAuthoring,
          isFalse,
        );

        final textRepo = _LinkedFanoutTextCustodyRepository();
        final reactionRepo = _LinkedFanoutReactionCustodyRepository();
        final storedEnvelopes = <String>[];

        final completed = await drainDirectBlobFreeLinkedEventFanout(
          // A wrongly-broad loader result: the drain itself must still refuse
          // the historical (NULL-contact) and media rows before any store or
          // repository touch.
          loadExactTextFanoutRows: () async => <Map<String, Object?>>[
            _linkedTextFanoutRow('ok-1', contactAccountPeerId: 'contact-a'),
            _linkedTextFanoutRow('hist-1'),
            _linkedTextFanoutRow(
              'med-1',
              contactAccountPeerId: 'contact-a',
              mediaBlobManifestHash: 'a' * 64,
              mediaBlobExpiresAtMs: 1999999999000,
            ),
          ],
          loadExactEventFanoutRows: () async => <Map<String, Object?>>[
            _linkedEventFanoutRow('evt-ok', contactAccountPeerId: 'contact-a'),
            _linkedEventFanoutRow('evt-hist'),
            _linkedEventFanoutRow(
              'evt-junk',
              contactAccountPeerId: 'contact-a',
              wireEnvelope: 'not-a-classifiable-envelope',
            ),
          ],
          custodyRepository: textRepo,
          storeInAckCustodyInboxDetailed:
              (
                toPeerId,
                message, {
                required custodyKind,
                int? timeoutMs,
              }) async {
                storedEnvelopes.add(message);
                return const InboxStoreOutcome(
                  status: InboxStoreStatus.stored,
                  storeStatus: 'stored',
                  custodyContract: ackOrExpiryInboxCustodyContract,
                );
              },
          mutationCustodyRepository: null,
          reactionCustodyRepository: reactionRepo,
        );

        expect(completed, 2);
        expect(textRepo.completedMessageIds, ['ok-1']);
        expect(reactionRepo.completedEventIds, ['evt-ok']);
        expect(
          storedEnvelopes,
          hasLength(2),
          reason: 'only the two exact blob-free rows may reach the relay store',
        );
        expect(storedEnvelopes.first, 'wire-ok-1');
        expect(
          textRepo.failureMessageIds,
          isEmpty,
          reason:
              'refused rows are skipped without recording custody failures — '
              'their tuples stay byte-identical',
        );
        expect(reactionRepo.failureEventIds, isEmpty);
      },
    );

    test(
      'TC-362-04a linked resume drains only the exact strict-media convergers',
      () async {
        // 362: the restricted linked runtime (the same composition the app
        // root's linked resume branch drains) gains ONLY the target-qualified
        // strict-media custody convergers, AWAITED after the exact blob-free
        // outbox drain. Every recorder suspends on a real timer first, so a
        // dropped `await` would resolve start() before the hook appended and
        // the exhaustive ordering assertion below would catch it.
        final callOrder = <String>[];
        Future<void> recordAwaited(String name) async {
          await Future<void>.delayed(Duration.zero);
          callOrder.add(name);
        }

        final services = DirectBlobFreeLinkedServices(
          initializeBridge: () => recordAwaited('initializeBridge'),
          startMessageRouter: () => callOrder.add('startMessageRouter'),
          startChatMessageListener: () =>
              callOrder.add('startChatMessageListener'),
          startReactionListener: () => callOrder.add('startReactionListener'),
          startMessageDeletionListener: () =>
              callOrder.add('startMessageDeletionListener'),
          startDeliveryReceiptListener: () =>
              callOrder.add('startDeliveryReceiptListener'),
          drainOfflineInbox: () => recordAwaited('drainOfflineInbox'),
          drainExactBlobFreeFanoutOutboxes: () async {
            await Future<void>.delayed(Duration.zero);
            callOrder.add('drainDirectBlobFreeLinkedOutboxes');
            return 2;
          },
          cleanupLinkedDirectMediaBlobCustodyLocally: () =>
              recordAwaited('cleanupLinkedDirectMediaBlobCustodyLocally'),
          drainLinkedDirectMediaBlobCustody: () =>
              recordAwaited('drainLinkedDirectMediaBlobCustody'),
        );

        expect(await services.start(), isTrue);
        expect(
          callOrder,
          <String>[
            'initializeBridge',
            'startMessageRouter',
            'startChatMessageListener',
            'startReactionListener',
            'startMessageDeletionListener',
            'startDeliveryReceiptListener',
            'drainOfflineInbox',
            'drainDirectBlobFreeLinkedOutboxes',
            'cleanupLinkedDirectMediaBlobCustodyLocally',
            'drainLinkedDirectMediaBlobCustody',
          ],
          reason:
              'the strict-media convergers run LAST and are awaited after '
              'drainDirectBlobFreeLinkedOutboxes; the exhaustive owner list '
              'proves NO broad retry family (recoverStuckSendingMessages, '
              'retryIncompleteUploads, retryFailedMessages, '
              'retryUnackedMessages, private-media recovery or generic '
              'push/upload owners) has any seat in the restricted call shape',
        );

        // Absent 362 hooks keep the Plan-361 blob-free composition
        // byte-identical: nothing extra runs and nothing awaits a null hook.
        final baselineOrder = <String>[];
        final baseline = DirectBlobFreeLinkedServices(
          initializeBridge: () async => baselineOrder.add('initializeBridge'),
          startMessageRouter: () => baselineOrder.add('startMessageRouter'),
          startChatMessageListener: () =>
              baselineOrder.add('startChatMessageListener'),
          startReactionListener: () =>
              baselineOrder.add('startReactionListener'),
          startMessageDeletionListener: () =>
              baselineOrder.add('startMessageDeletionListener'),
          startDeliveryReceiptListener: () =>
              baselineOrder.add('startDeliveryReceiptListener'),
          drainOfflineInbox: () async => baselineOrder.add('drainOfflineInbox'),
          drainExactBlobFreeFanoutOutboxes: () async {
            baselineOrder.add('drainDirectBlobFreeLinkedOutboxes');
            return 0;
          },
        );
        expect(await baseline.start(), isTrue);
        expect(
          baselineOrder.last,
          'drainDirectBlobFreeLinkedOutboxes',
          reason: 'without the 362 convergers the 361 drain stays terminal',
        );
      },
    );
  });
}
