import 'dart:async';

import 'package:flutter_app/core/debug/intro_e2e_runner.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_introduction_repository.dart';
import '../services/fake_p2p_service.dart';

const _ownPeerId = 'peer-responder';
const _introducerPeerId = 'peer-introducer';
const _otherPartyPeerId = 'peer-other-party';

void main() {
  late InMemoryIntroductionRepository introRepo;
  late FakeP2PService p2pService;

  setUp(() {
    introRepo = InMemoryIntroductionRepository();
    p2pService = FakeP2PService();
  });

  tearDown(() {
    p2pService.dispose();
  });

  test(
    'fresh sent accept row reaches introducer inbox without age wait',
    () async {
      const introductionId = 'intro-fresh-sent';
      final now = DateTime.now().toUtc();
      await _seedAcceptedIntroduction(introRepo, introductionId);
      await introRepo.saveOutboxDelivery(
        _acceptDelivery(
          deliveryId: 'delivery-fresh-sent',
          introductionId: introductionId,
          targetPeerId: _introducerPeerId,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(await introRepo.loadRetryableOutboxDeliveries(), isEmpty);

      final result = await awaitIntroducerAcceptanceCustodyForIntroE2E(
        introActionResult: const <String, dynamic>{
          'action': 'accept_all',
          'actedOn': <String>[introductionId],
        },
        ownPeerId: _ownPeerId,
        introRepo: introRepo,
        p2pService: p2pService,
        timeout: const Duration(seconds: 1),
        retryInterval: Duration.zero,
      );

      expect(result['status'], 'confirmed');
      expect(result['introductionCount'], 1);
      expect(result['retryPasses'], 1);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, _introducerPeerId);
      expect(
        await introRepo.loadOutboxDeliveriesForIntroduction(introductionId),
        isEmpty,
      );
    },
  );

  test(
    'other-party custody does not complete until introducer row clears',
    () async {
      const introductionId = 'intro-two-targets';
      final now = DateTime.now().toUtc();
      await _seedAcceptedIntroduction(introRepo, introductionId);
      await introRepo.saveOutboxDelivery(
        _acceptDelivery(
          deliveryId: 'delivery-other-party',
          introductionId: introductionId,
          targetPeerId: _otherPartyPeerId,
          createdAt: now.subtract(const Duration(milliseconds: 2)),
          updatedAt: now,
        ),
      );
      await introRepo.saveOutboxDelivery(
        _acceptDelivery(
          deliveryId: 'delivery-introducer',
          introductionId: introductionId,
          targetPeerId: _introducerPeerId,
          createdAt: now.subtract(const Duration(milliseconds: 1)),
          updatedAt: now,
        ),
      );

      final introducerStoreStarted = Completer<void>();
      final releaseIntroducerStore = Completer<bool>();
      p2pService.onStoreInInbox =
          (String toPeerId, String message, {int? timeoutMs}) async {
            if (toPeerId == _introducerPeerId) {
              introducerStoreStarted.complete();
              return releaseIntroducerStore.future;
            }
            return true;
          };

      var custodyCompleted = false;
      final custodyFuture = awaitIntroducerAcceptanceCustodyForIntroE2E(
        introActionResult: const <String, dynamic>{
          'action': 'accept_all',
          'actedOn': <String>[introductionId],
        },
        ownPeerId: _ownPeerId,
        introRepo: introRepo,
        p2pService: p2pService,
        timeout: const Duration(seconds: 1),
        retryInterval: Duration.zero,
      )..then((_) => custodyCompleted = true);

      await introducerStoreStarted.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(custodyCompleted, isFalse);
      final pending = await introRepo.loadOutboxDeliveriesForIntroduction(
        introductionId,
      );
      expect(pending.map((delivery) => delivery.deliveryId), <String>[
        'delivery-introducer',
      ]);

      releaseIntroducerStore.complete(true);
      final result = await custodyFuture;

      expect(result['status'], 'confirmed');
      expect(result['retryPasses'], 1);
      expect(
        p2pService.storeInInboxLog.map((entry) => entry.toPeerId),
        <String>[_otherPartyPeerId, _introducerPeerId],
      );
      expect(
        await introRepo.loadOutboxDeliveriesForIntroduction(introductionId),
        isEmpty,
      );
    },
  );

  test('empty actedOn is rejected', () async {
    await expectLater(
      awaitIntroducerAcceptanceCustodyForIntroE2E(
        introActionResult: const <String, dynamic>{
          'action': 'accept_all',
          'actedOn': <String>[],
        },
        ownPeerId: _ownPeerId,
        introRepo: introRepo,
        p2pService: p2pService,
        timeout: const Duration(seconds: 1),
        retryInterval: Duration.zero,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('at least one acted-on introduction'),
        ),
      ),
    );
  });
}

Future<void> _seedAcceptedIntroduction(
  InMemoryIntroductionRepository introRepo,
  String introductionId,
) {
  return introRepo.saveIntroduction(
    IntroductionModel(
      id: introductionId,
      introducerId: _introducerPeerId,
      recipientId: _ownPeerId,
      introducedId: _otherPartyPeerId,
      recipientStatus: IntroductionStatus.accepted,
      introducedStatus: IntroductionStatus.pending,
      status: IntroductionOverallStatus.pending,
      createdAt: '2026-07-15T00:00:00.000Z',
      recipientRespondedAt: '2026-07-15T00:01:00.000Z',
    ),
  );
}

IntroductionOutboxDelivery _acceptDelivery({
  required String deliveryId,
  required String introductionId,
  required String targetPeerId,
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  final timestamp = updatedAt.toIso8601String();
  return IntroductionOutboxDelivery(
    deliveryId: deliveryId,
    introductionId: introductionId,
    action: 'accept',
    targetPeerId: targetPeerId,
    senderPeerId: _ownPeerId,
    rawEnvelope: IntroductionPayload(
      action: 'accept',
      introductionId: introductionId,
      responderId: _ownPeerId,
      responderUsername: 'Responder',
      timestamp: timestamp,
    ).toJson(),
    deliveryStatus: IntroductionOutboxDeliveryStatus.sent,
    deliveryPath: IntroductionOutboxDeliveryPath.relay,
    createdAt: createdAt.toIso8601String(),
    updatedAt: timestamp,
  );
}
