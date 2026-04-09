import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
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

  test(
    'transport envelope ids stay distinct for send and accept on the same introduction',
    () async {
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

      await deliverIntroductionPayloadReliably(
        introRepo: introRepo,
        p2pService: p2pService,
        bridge: bridge,
        senderPeerId: 'peer-B',
        targetPeerId: 'peer-C',
        targetMlKemPublicKey: null,
        payload: IntroductionPayload(
          action: 'accept',
          introductionId: payload.introductionId,
          responderId: 'peer-B',
          responderUsername: 'Bob',
          timestamp: '2026-04-04T12:00:01.000Z',
        ),
      );

      final deliveries = introRepo.allOutboxDeliveries();
      expect(deliveries, hasLength(2));

      final messageIds = deliveries
          .map((delivery) => delivery.rawEnvelope)
          .map((rawEnvelope) => rawEnvelope.contains('intro-1::'))
          .toList(growable: false);
      expect(messageIds, everyElement(isTrue));
      expect(
        deliveries.first.rawEnvelope,
        isNot(contains('"messageId":"intro-1"')),
      );
      expect(
        deliveries.last.rawEnvelope,
        isNot(contains('"messageId":"intro-1"')),
      );
      expect(deliveries.first.rawEnvelope, isNot(deliveries.last.rawEnvelope));
    },
  );

  test('relay-probe fallback delivers after the direct path fails', () async {
    final relayProbeService = _RelayProbeFakeP2PService(
      initialState: const NodeState(isStarted: true),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-B',
        addresses: ['/ip4/127.0.0.1/tcp/4001/p2p/peer-B'],
      ),
      dialPeerResult: false,
      sendMessageWithReplyResult: const SendMessageResult(
        sent: true,
        acked: true,
        transport: 'relay',
      ),
      relayProbeResult: RelayProbeResult.connected,
    );
    p2pService = relayProbeService;

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
    expect(p2pService.discoverPeerCallCount, 1);
    expect(p2pService.dialPeerCallCount, 2);
    expect(p2pService.sendMessageWithReplyCallCount, 1);
    expect(relayProbeService.probeRelayCallCount, 1);
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

  test(
    'retryPendingIntroductionDeliveries processes multiple stalled and failed rows and cleans delivered inbox rows',
    () async {
      await introRepo.saveOutboxDelivery(
        IntroductionOutboxDelivery(
          deliveryId: 'delivery-failed',
          introductionId: 'intro-failed',
          action: 'send',
          targetPeerId: 'peer-B',
          senderPeerId: 'peer-A',
          rawEnvelope: payload.toJson(),
          deliveryStatus: IntroductionOutboxDeliveryStatus.failed,
          deliveryPath: IntroductionOutboxDeliveryPath.pending,
          createdAt: '2025-04-04T12:00:00.000Z',
          updatedAt: '2025-04-04T12:00:00.000Z',
        ),
      );
      await introRepo.saveOutboxDelivery(
        IntroductionOutboxDelivery(
          deliveryId: 'delivery-sent',
          introductionId: 'intro-sent',
          action: 'send',
          targetPeerId: 'peer-C',
          senderPeerId: 'peer-A',
          rawEnvelope: payload.toJson(),
          deliveryStatus: IntroductionOutboxDeliveryStatus.sent,
          deliveryPath: IntroductionOutboxDeliveryPath.relay,
          createdAt: '2025-04-04T12:00:00.000Z',
          updatedAt: '2025-04-04T12:00:00.000Z',
        ),
      );
      await introRepo.saveOutboxDelivery(
        IntroductionOutboxDelivery(
          deliveryId: 'delivery-inbox',
          introductionId: 'intro-inbox',
          action: 'send',
          targetPeerId: 'peer-D',
          senderPeerId: 'peer-A',
          rawEnvelope: payload.toJson(),
          deliveryStatus: IntroductionOutboxDeliveryStatus.delivered,
          deliveryPath: IntroductionOutboxDeliveryPath.inbox,
          createdAt: '2025-04-04T12:00:00.000Z',
          updatedAt: '2025-04-04T12:00:00.000Z',
        ),
      );

      final delivered = await retryPendingIntroductionDeliveries(
        introRepo: introRepo,
        p2pService: p2pService,
      );

      expect(delivered, 3);
      expect(introRepo.allOutboxDeliveries(), isEmpty);
      expect(p2pService.storeInInboxCallCount, 2);
      expect(p2pService.lastStoreInInboxPeerId, 'peer-C');
    },
  );

  test(
    'handleAppResumed replays a sent intro row through inbox-only retry',
    () async {
      await introRepo.saveOutboxDelivery(
        IntroductionOutboxDelivery(
          deliveryId: 'delivery-2',
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

      final bridgeHealthy = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        retryPendingIntroductionDeliveriesFn: () =>
            retryPendingIntroductionDeliveries(
              introRepo: introRepo,
              p2pService: p2pService,
            ),
      );

      expect(bridgeHealthy, isTrue);
      expect(introRepo.allOutboxDeliveries(), isEmpty);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, 'peer-B');
      expect(p2pService.sendMessageWithReplyCallCount, 0);
    },
  );
}

class _RelayProbeFakeP2PService extends FakeP2PService {
  final RelayProbeResult relayProbeResult;
  int probeRelayCallCount = 0;

  _RelayProbeFakeP2PService({
    super.initialState,
    super.startNodeResult,
    super.stopNodeResult,
    super.sendMessageResult,
    super.sendMessageWithReplyResult,
    super.discoverPeerResult,
    super.dialPeerResult,
    super.storeInInboxResult,
    super.retrieveInboxResult,
    super.registerPushTokenResult,
    super.throwOnHealthCheck,
    super.throwOnDrainInbox,
    super.recoveryMethod,
    required this.relayProbeResult,
  });

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async {
    probeRelayCallCount++;
    return relayProbeResult;
  }
}
