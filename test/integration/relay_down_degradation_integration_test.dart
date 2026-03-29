import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
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
  group('Relay-down degradation', () {
    late FakeBridge bridge;
    late FakeMessageRepository messageRepo;
    late FakeIdentityRepository identityRepo;
    late FakeContactRepository contactRepo;

    const onlineState = NodeState(
      isStarted: true,
      peerId: 'peer-alice',
      circuitAddresses: ['/p2p-circuit/relay'],
    );

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
      messageRepo = FakeMessageRepository();
      identityRepo = FakeIdentityRepository()..seed(makeAliceIdentity());
      contactRepo = FakeContactRepository()..seed([makeBobContact()]);
    });

    test(
      '1. both inbox and direct fail -> message persists as failed and pause does not duplicate rows',
      () async {
        final p2pService = FakeP2PService(
          initialState: onlineState,
          storeInInboxResult: false,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          discoverPeerResult: null,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'peer-bob',
          text: 'This will fail',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          bridge: bridge,
          recipientMlKemPublicKey: 'bob-mlkem-pk',
        );

        expect(
          result,
          anyOf(
            SendChatMessageResult.sendFailed,
            SendChatMessageResult.peerNotFound,
            SendChatMessageResult.dialFailed,
          ),
        );
        expect(message, isNotNull);
        expect(message!.status, 'failed');

        final pauseResult = await simulateAppPaused(messageRepo: messageRepo);
        expect(
          pauseResult.transitionedCount,
          0,
          reason: 'Failed rows must not be touched by the pause handler',
        );

        final stored = await messageRepo.getMessagesForContact('peer-bob');
        expect(stored, hasLength(1));
        expect(stored.single.id, message.id);
        expect(stored.single.status, 'failed');
        expect(p2pService.storeInInboxCallCount, 1);

        p2pService.dispose();
      },
    );

    test(
      '1b. active send fails during transport loss, then online transition retrier heals the same row once',
      () async {
        final p2pService = FakeP2PService(
          initialState: onlineState,
          storeInInboxResult: false,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          discoverPeerResult: null,
        );

        final (result, message) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'peer-bob',
          text: 'Heal me after switch',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          bridge: bridge,
          recipientMlKemPublicKey: 'bob-mlkem-pk',
        );

        expect(
          result,
          anyOf(
            SendChatMessageResult.sendFailed,
            SendChatMessageResult.peerNotFound,
            SendChatMessageResult.dialFailed,
          ),
        );
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(message.wireEnvelope, isNotNull);

        final failedId = message.id;
        final failedRows = await messageRepo.getMessagesForContact('peer-bob');
        expect(failedRows, hasLength(1));
        expect(failedRows.single.id, failedId);
        expect(failedRows.single.status, 'failed');

        p2pService.emitState(NodeState.stopped);

        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        p2pService.storeInInboxResult = true;
        retrier.start();
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        final recoveredRows = await messageRepo.getMessagesForContact('peer-bob');
        expect(recoveredRows, hasLength(1));
        expect(recoveredRows.single.id, failedId);
        expect(recoveredRows.single.status, 'delivered');
        expect(recoveredRows.single.transport, 'inbox');
        expect(
          p2pService.storeInInboxCallCount,
          2,
          reason: 'One failed initial inbox handoff plus one successful retry',
        );

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      '2. pause -> reconnect -> retrier delivers the original row exactly once',
      () async {
        messageRepo.seed([
          makeSendingMessage(
            id: 'relay-down-001',
            contactPeerId: 'peer-bob',
            text: 'Recover me',
          ),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: false, peerId: 'peer-alice'),
          storeInInboxResult: true,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
        );
        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        final pauseResult = await simulateAppPaused(messageRepo: messageRepo);
        expect(pauseResult.transitionedCount, 1);
        expect(
          (await messageRepo.getMessage('relay-down-001'))?.status,
          'failed',
        );

        retrier.start();
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'relay-down-001');
        expect(messages.single.status, 'delivered');
        expect(messages.single.transport, 'inbox');
        expect(p2pService.storeInInboxCallCount, 1);

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      '3. pause -> reconnect while both paths stay down leaves the original row failed',
      () async {
        messageRepo.seed([
          makeSendingMessage(
            id: 'relay-down-002',
            contactPeerId: 'peer-bob',
            text: 'Still failing',
          ),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: false, peerId: 'peer-alice'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          discoverPeerResult: null,
        );
        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        await simulateAppPaused(messageRepo: messageRepo);
        retrier.start();
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        final messages = await messageRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'relay-down-002');
        expect(messages.single.status, 'failed');
        expect(p2pService.storeInInboxCallCount, greaterThanOrEqualTo(1));

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      '4. cold-start already online sweeps immediately and still preserves exact-once delivery',
      () async {
        final p2pService = FakeP2PService(
          initialState: onlineState,
          storeInInboxResult: true,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
        );
        final coldRepo = FakeMessageRepository()
          ..seed([makeFailedMessageWithEnvelope(id: 'relay-down-003')]);
        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: coldRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        retrier.start();
        await Future.delayed(const Duration(seconds: 6));

        final messages = await coldRepo.getMessagesForContact('peer-bob');
        expect(messages, hasLength(1));
        expect(messages.single.id, 'relay-down-003');
        expect(messages.single.status, 'delivered');
        expect(messages.single.transport, 'inbox');
        expect(p2pService.storeInInboxCallCount, 1);

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
