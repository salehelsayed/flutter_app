import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';

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
      'calls retryIncompleteUploads AFTER recoverStuckSendingMessages but BEFORE retryFailedMessages',
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
          retryPendingIntroductionDeliveriesFn: fakeRetryPendingIntroductions,
        );

        expect(callOrder, [
          'recoverStuckSendingMessages',
          'retryIncompleteUploads',
          'retryFailedMessages',
          'retryUnackedMessages',
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
          retryPendingIntroductionDeliveriesFn: fakeRetryPendingIntroductions,
        );

        // retryIncompleteUploads threw, but retryFailedMessages and
        // retryUnackedMessages still executed
        expect(callOrder, [
          'recoverStuckSendingMessages',
          'retryIncompleteUploads',
          'retryFailedMessages',
          'retryUnackedMessages',
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
          retryPendingIntroductionDeliveriesFn:
              fakeRetryPendingIntroductionsThatThrows,
          retryFailedGroupInboxStoresFn: fakeRetryFailedGroupInboxStores,
        );

        expect(callOrder, [
          'retryFailedMessages',
          'retryUnackedMessages',
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
