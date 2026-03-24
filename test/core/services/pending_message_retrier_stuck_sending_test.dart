import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'fake_p2p_service.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';

ConversationMessage _makeStuckSendingMessage({
  String id = 'msg-stuck-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
}) {
  final oldTs = DateTime.now().toUtc()
      .subtract(const Duration(minutes: 5))
      .toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: oldTs,
    status: 'sending',
    isIncoming: false,
    createdAt: oldTs,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late PendingMessageRetrier retrier;

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge();
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
  });

  group('PendingMessageRetrier — stuck sending', () {
    test(
      'transitions stuck sending messages to failed then retries them on online transition',
      () async {
        final msg = _makeStuckSendingMessage();
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        int recoverCallCount = 0;

        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          recoverStuckSendingMessagesFn: () async {
            recoverCallCount++;
            return await messageRepo.recoverStuckSendingMessages(
              olderThan: const Duration(minutes: 2),
            );
          },
        );
        retrier.start();

        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        // recoverStuckSendingMessages must have been called via callback
        expect(recoverCallCount, greaterThanOrEqualTo(1));
        // retryFailedMessages (via identity load) must have run
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );

    test(
      'does not call recoverStuckSendingMessages when offline',
      () async {
        int recoverCallCount = 0;

        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          recoverStuckSendingMessagesFn: () async {
            recoverCallCount++;
            return 0;
          },
        );
        retrier.start();
        // Stays offline — never transitions to online
        await Future.delayed(const Duration(seconds: 6));
        expect(recoverCallCount, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'recovery error does not prevent retryFailedMessages from running',
      () async {
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          recoverStuckSendingMessagesFn: () async {
            throw Exception('FakeMessageRepository: recoverStuckSendingMessages error');
          },
        );
        retrier.start();

        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        // Even though recoverStuckSendingMessages threw, the retrier continued
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );
  });
}
