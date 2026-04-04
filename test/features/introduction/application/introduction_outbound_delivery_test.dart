import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late InMemoryIntroductionRepository introRepo;
  late IntroductionPayload payload;

  setUp(() {
    bridge = FakeBridge();
    p2pService = FakeP2PService(
      initialState: const NodeState(isStarted: true),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-B',
        addresses: ['/ip4/127.0.0.1/tcp/4001/p2p/peer-B'],
      ),
      dialPeerResult: true,
    );
    introRepo = InMemoryIntroductionRepository();
    payload = IntroductionPayload(
      action: 'send',
      introductionId: 'intro-1',
      introducerId: 'peer-A',
      introducerUsername: 'Alice',
      recipientId: 'peer-B',
      recipientUsername: 'Bob',
      introducedId: 'peer-C',
      introducedUsername: 'Charlie',
      timestamp: '2026-04-04T12:00:00.000Z',
    );
  });

  test('acked live send clears the staged outbox delivery', () async {
    p2pService.sendMessageWithReplyResult = const SendMessageResult(
      sent: true,
      acked: true,
      transport: 'relay',
    );

    await deliverIntroductionPayloadReliably(
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      senderPeerId: 'peer-A',
      targetPeerId: 'peer-B',
      targetMlKemPublicKey: null,
      payload: payload,
    );

    expect(introRepo.allOutboxDeliveries(), isEmpty);
    expect(p2pService.sendMessageWithReplyCallCount, 1);
    expect(p2pService.storeInInboxCallCount, 0);
  });

  test('unacked live send keeps a retryable sent outbox delivery', () async {
    p2pService.sendMessageWithReplyResult = const SendMessageResult(
      sent: true,
      acked: false,
      transport: 'relay',
    );

    await deliverIntroductionPayloadReliably(
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      senderPeerId: 'peer-A',
      targetPeerId: 'peer-B',
      targetMlKemPublicKey: null,
      payload: payload,
    );

    final deliveries = introRepo.allOutboxDeliveries();
    expect(deliveries, hasLength(1));
    expect(
      deliveries.single.deliveryStatus,
      IntroductionOutboxDeliveryStatus.sent,
    );
    expect(deliveries.single.deliveryPath, 'relay');
    expect(deliveries.single.rawEnvelope, isNotEmpty);
    expect(p2pService.storeInInboxCallCount, 0);
  });

  test('inbox fallback success clears the outbox delivery', () async {
    p2pService.sendMessageWithReplyResult = const SendMessageResult(
      sent: false,
    );
    p2pService.storeInInboxResult = true;

    await deliverIntroductionPayloadReliably(
      introRepo: introRepo,
      p2pService: p2pService,
      bridge: bridge,
      senderPeerId: 'peer-A',
      targetPeerId: 'peer-B',
      targetMlKemPublicKey: null,
      payload: payload,
    );

    expect(introRepo.allOutboxDeliveries(), isEmpty);
    expect(p2pService.storeInInboxCallCount, 1);
  });

  test(
    'failed live send and inbox fallback keeps a failed outbox delivery',
    () async {
      p2pService.sendMessageWithReplyResult = const SendMessageResult(
        sent: false,
      );
      p2pService.storeInInboxResult = false;

      await deliverIntroductionPayloadReliably(
        introRepo: introRepo,
        p2pService: p2pService,
        bridge: bridge,
        senderPeerId: 'peer-A',
        targetPeerId: 'peer-B',
        targetMlKemPublicKey: null,
        payload: payload,
      );

      final deliveries = introRepo.allOutboxDeliveries();
      expect(deliveries, hasLength(1));
      expect(
        deliveries.single.deliveryStatus,
        IntroductionOutboxDeliveryStatus.failed,
      );
      expect(deliveries.single.rawEnvelope, isNotEmpty);
    },
  );

  test(
    'retryPendingIntroductionDeliveries replays a sent row through inbox',
    () async {
      await introRepo.saveOutboxDelivery(
        IntroductionOutboxDelivery(
          deliveryId: 'delivery-1',
          introductionId: 'intro-1',
          action: 'send',
          targetPeerId: 'peer-B',
          senderPeerId: 'peer-A',
          rawEnvelope: payload.toJson(),
          deliveryStatus: IntroductionOutboxDeliveryStatus.sent,
          deliveryPath: 'relay',
          createdAt: '2025-04-04T12:00:00.000Z',
          updatedAt: '2025-04-04T12:00:00.000Z',
        ),
      );

      final delivered = await retryPendingIntroductionDeliveries(
        introRepo: introRepo,
        p2pService: p2pService,
      );

      expect(delivered, 1);
      expect(introRepo.allOutboxDeliveries(), isEmpty);
      expect(p2pService.storeInInboxCallCount, 1);
    },
  );
}
