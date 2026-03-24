import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/conversation/domain/repositories/fake_message_repository.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fixtures/message_fixtures.dart';
import '../shared/helpers/lifecycle_helpers.dart';

void main() {
  group('Rapid lock-unlock integration', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late FakeMessageRepository messageRepo;
    late FakeIdentityRepository identityRepo;
    late FakeContactRepository contactRepo;
    late PendingMessageRetrier retrier;

    const onlineState = NodeState(
      isStarted: true,
      peerId: 'peer-alice',
      circuitAddresses: ['/p2p-circuit/relay'],
    );
    const offlineState = NodeState(isStarted: false, peerId: 'peer-alice');

    setUp(() {
      bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
      p2pService = FakeP2PService(
        initialState: onlineState,
        sendMessageWithReplyResult: const SendMessageResult(sent: false),
        storeInInboxResult: true,
      );
      messageRepo = FakeMessageRepository()
        ..seed([
          makeSendingMessage(
            id: 'msg-sending-001',
            ageOffset: const Duration(minutes: 5),
            relativeTo: DateTime(2026, 3, 23, 12, 10, 0).toUtc(),
          ),
        ]);
      identityRepo = FakeIdentityRepository()..seed(makeAliceIdentity());
      contactRepo = FakeContactRepository()..seed([makeBobContact()]);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );
      retrier.start();
    });

    tearDown(() {
      retrier.dispose();
      p2pService.dispose();
    });

    test(
      '1. three rapid pause-resume cycles deliver the message exactly once',
      () async {
        await simulateRapidLockUnlock(
          bridge: bridge,
          p2pService: p2pService,
          messageRepo: messageRepo,
          cycles: 3,
          afterPause: () async => p2pService.emitState(offlineState),
          afterResume: () async => p2pService.emitState(onlineState),
        );
        await Future.delayed(const Duration(seconds: 6));

        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-sending-001');
        expect(messages.single.status, 'delivered');
        expect(messages.single.transport, 'inbox');
        expect(p2pService.storeInInboxCallCount, 1);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      '2. concurrent pause calls are idempotent on the same sending row',
      () async {
        final results = await Future.wait([
          simulateAppPaused(messageRepo: messageRepo),
          simulateAppPaused(messageRepo: messageRepo),
        ]);

        final transitionedTotal = results
            .map((result) => result.transitionedCount)
            .reduce((a, b) => a + b);
        expect(transitionedTotal, lessThanOrEqualTo(1));

        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-sending-001');
        expect(messages.single.status, 'failed');
      },
    );

    test(
      '3. a delivered row survives pause/resume and is not re-delivered',
      () async {
        retrier.dispose();
        messageRepo = FakeMessageRepository()
          ..seed([
            makeFailedMessageWithEnvelope(
              id: 'msg-delivered-001',
            ).copyWith(status: 'delivered', transport: 'inbox'),
          ]);
        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );
        retrier.start();

        await simulateBackgroundForegroundCycle(
          bridge: bridge,
          p2pService: p2pService,
          messageRepo: messageRepo,
          afterPause: () async => p2pService.emitState(offlineState),
          afterResume: () async => p2pService.emitState(onlineState),
        );
        await Future.delayed(const Duration(seconds: 6));

        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'msg-delivered-001');
        expect(messages.single.status, 'delivered');
        expect(p2pService.storeInInboxCallCount, 0);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
