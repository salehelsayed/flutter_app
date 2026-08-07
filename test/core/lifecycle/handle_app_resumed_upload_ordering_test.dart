import 'package:flutter_test/flutter_test.dart';
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
}
