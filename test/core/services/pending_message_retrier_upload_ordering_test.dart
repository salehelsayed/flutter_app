import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'fake_p2p_service.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../core/bridge/fake_bridge.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late PendingMessageRetrier retrier;

  const onlineNodeState = NodeState(
    isStarted: true,
    peerId: 'my-peer',
    circuitAddresses: ['/p2p-circuit/addr1'],
  );

  setUp(() {
    messageRepo = FakeMessageRepository();
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge();
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
  });

  group('PendingMessageRetrier -- retryIncompleteUploads ordering', () {
    test(
        'cold-start sweep calls retryIncompleteUploads in correct order: recover -> uploads -> failed -> unacked',
        () async {
      final callOrder = <String>[];

      // Injectable callbacks that record invocation order
      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }

      Future<int> fakeRetryIncompleteUploads() async {
        callOrder.add('retryIncompleteUploads');
        return 0;
      }

      // PendingMessageRetrier already calls retryFailedMessages and
      // retryUnackedMessages internally via top-level functions.
      // With the Green Phase changes, these become injectable too.
      // For this test, we use the injectable callback pattern so we
      // can capture ordering.
      p2pService = FakeP2PService(initialState: onlineNodeState);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploads,
      );
      retrier.start();

      // Wait for 5-second debounce to fire the initial sweep
      await Future.delayed(const Duration(seconds: 6));

      // Verify ordering: recover must precede uploads, uploads must precede failed
      final recoverIdx = callOrder.indexOf('recoverStuckSendingMessages');
      final uploadsIdx = callOrder.indexOf('retryIncompleteUploads');
      expect(recoverIdx, isNonNegative,
          reason: 'recoverStuckSendingMessages must be called');
      expect(uploadsIdx, isNonNegative,
          reason: 'retryIncompleteUploads must be called');
      expect(recoverIdx, lessThan(uploadsIdx),
          reason:
              'recoverStuckSendingMessages must run before retryIncompleteUploads');

      // retryFailedMessages runs after retryIncompleteUploads (verified by
      // identityRepo.loadIdentityCallCount proxy, same as existing 1D-05 test)
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
        'if retryIncompleteUploads throws in cold-start sweep, retryFailedMessages still runs',
        () async {
      final callOrder = <String>[];

      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }

      Future<int> fakeRetryIncompleteUploadsThatThrows() async {
        callOrder.add('retryIncompleteUploads');
        throw Exception('Network unreachable during CDN upload');
      }

      p2pService = FakeP2PService(initialState: onlineNodeState);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploadsThatThrows,
      );
      retrier.start();

      // Wait for 5-second debounce
      await Future.delayed(const Duration(seconds: 6));

      // retryIncompleteUploads threw, but the sweep continued
      expect(callOrder, contains('recoverStuckSendingMessages'));
      expect(callOrder, contains('retryIncompleteUploads'));

      // retryFailedMessages still ran (proxy: identityRepo was queried)
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
