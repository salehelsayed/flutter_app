import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/folded_introduction_response_use_case.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late _FoldedIntroHarness harness;

  setUp(() async {
    harness = _FoldedIntroHarness();
    await harness.seedMixedRoleIntroductions();
  });

  test(
    'folded accept applies across mixed recipient and introduced roles',
    () async {
      final foldedItem = await harness.loadSingleFoldedItem();

      final result = await acceptFoldedIntroduction(
        introRepo: harness.introRepo,
        contactRepo: harness.contactRepo,
        p2pService: harness.p2pService,
        bridge: harness.bridge,
        foldedIntroduction: foldedItem,
        ownPeerId: _FoldedIntroHarness.ownPeerId,
        ownUsername: _FoldedIntroHarness.ownUsername,
      );

      expect(result.results, hasLength(2));
      expect(
        result.results.map((entry) => entry.outcome),
        everyElement(FoldedIntroductionActionOutcome.applied),
      );
      expect(result.appliedResults, hasLength(2));
      expect(result.failedResults, isEmpty);
      expect(result.hasFailures, isFalse);

      final recipientIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.recipientRoleIntroId,
      );
      final introducedIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.introducedRoleIntroId,
      );

      expect(recipientIntro, isNotNull);
      expect(recipientIntro!.recipientStatus, IntroductionStatus.accepted);
      expect(recipientIntro.introducedStatus, IntroductionStatus.pending);
      expect(recipientIntro.status, IntroductionOverallStatus.pending);

      expect(introducedIntro, isNotNull);
      expect(introducedIntro!.recipientStatus, IntroductionStatus.pending);
      expect(introducedIntro.introducedStatus, IntroductionStatus.accepted);
      expect(introducedIntro.status, IntroductionOverallStatus.pending);

      expect(harness.network.deliverCallCount, 4);
    },
  );

  test(
    'folded pass applies across mixed recipient and introduced roles',
    () async {
      final foldedItem = await harness.loadSingleFoldedItem();

      final result = await passFoldedIntroduction(
        introRepo: harness.introRepo,
        contactRepo: harness.contactRepo,
        p2pService: harness.p2pService,
        bridge: harness.bridge,
        foldedIntroduction: foldedItem,
        ownPeerId: _FoldedIntroHarness.ownPeerId,
        ownUsername: _FoldedIntroHarness.ownUsername,
      );

      expect(result.results, hasLength(2));
      expect(
        result.results.map((entry) => entry.outcome),
        everyElement(FoldedIntroductionActionOutcome.applied),
      );
      expect(result.appliedResults, hasLength(2));
      expect(result.failedResults, isEmpty);
      expect(result.hasFailures, isFalse);

      final recipientIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.recipientRoleIntroId,
      );
      final introducedIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.introducedRoleIntroId,
      );

      expect(recipientIntro, isNotNull);
      expect(recipientIntro!.recipientStatus, IntroductionStatus.passed);
      expect(recipientIntro.introducedStatus, IntroductionStatus.pending);
      expect(recipientIntro.status, IntroductionOverallStatus.passed);

      expect(introducedIntro, isNotNull);
      expect(introducedIntro!.recipientStatus, IntroductionStatus.pending);
      expect(introducedIntro.introducedStatus, IntroductionStatus.passed);
      expect(introducedIntro.status, IntroductionOverallStatus.passed);

      expect(harness.network.deliverCallCount, 4);
    },
  );

  test('stale folded accept skips duplicate sends after first apply', () async {
    final foldedItem = await harness.loadSingleFoldedItem();

    await acceptFoldedIntroduction(
      introRepo: harness.introRepo,
      contactRepo: harness.contactRepo,
      p2pService: harness.p2pService,
      bridge: harness.bridge,
      foldedIntroduction: foldedItem,
      ownPeerId: _FoldedIntroHarness.ownPeerId,
      ownUsername: _FoldedIntroHarness.ownUsername,
    );
    final deliveryCountAfterFirstApply = harness.network.deliverCallCount;
    final outboxCountAfterFirstApply = harness.introRepo
        .allOutboxDeliveries()
        .length;

    final staleResult = await acceptFoldedIntroduction(
      introRepo: harness.introRepo,
      contactRepo: harness.contactRepo,
      p2pService: harness.p2pService,
      bridge: harness.bridge,
      foldedIntroduction: foldedItem,
      ownPeerId: _FoldedIntroHarness.ownPeerId,
      ownUsername: _FoldedIntroHarness.ownUsername,
    );

    expect(
      staleResult.results.map((entry) => entry.outcome),
      everyElement(FoldedIntroductionActionOutcome.skippedNotPending),
    );
    expect(staleResult.appliedResults, isEmpty);
    expect(staleResult.failedResults, isEmpty);
    expect(harness.network.deliverCallCount, deliveryCountAfterFirstApply);
    expect(
      harness.introRepo.allOutboxDeliveries().length,
      outboxCountAfterFirstApply,
    );
  });

  test('stale folded pass skips duplicate sends after first apply', () async {
    final foldedItem = await harness.loadSingleFoldedItem();

    await passFoldedIntroduction(
      introRepo: harness.introRepo,
      contactRepo: harness.contactRepo,
      p2pService: harness.p2pService,
      bridge: harness.bridge,
      foldedIntroduction: foldedItem,
      ownPeerId: _FoldedIntroHarness.ownPeerId,
      ownUsername: _FoldedIntroHarness.ownUsername,
    );
    final deliveryCountAfterFirstApply = harness.network.deliverCallCount;
    final outboxCountAfterFirstApply = harness.introRepo
        .allOutboxDeliveries()
        .length;

    final staleResult = await passFoldedIntroduction(
      introRepo: harness.introRepo,
      contactRepo: harness.contactRepo,
      p2pService: harness.p2pService,
      bridge: harness.bridge,
      foldedIntroduction: foldedItem,
      ownPeerId: _FoldedIntroHarness.ownPeerId,
      ownUsername: _FoldedIntroHarness.ownUsername,
    );

    expect(
      staleResult.results.map((entry) => entry.outcome),
      everyElement(FoldedIntroductionActionOutcome.skippedNotPending),
    );
    expect(staleResult.appliedResults, isEmpty);
    expect(staleResult.failedResults, isEmpty);
    expect(harness.network.deliverCallCount, deliveryCountAfterFirstApply);
    expect(
      harness.introRepo.allOutboxDeliveries().length,
      outboxCountAfterFirstApply,
    );
  });

  test(
    'non-party folded accept and pass fail without mutation or sends',
    () async {
      final foldedItem = await harness.loadSingleFoldedItem();

      final acceptResult = await acceptFoldedIntroduction(
        introRepo: harness.introRepo,
        contactRepo: harness.contactRepo,
        p2pService: harness.p2pService,
        bridge: harness.bridge,
        foldedIntroduction: foldedItem,
        ownPeerId: 'peer-X',
        ownUsername: 'Mallory',
      );

      expect(
        acceptResult.results.map((entry) => entry.outcome),
        everyElement(FoldedIntroductionActionOutcome.failed),
      );
      expect(acceptResult.appliedResults, isEmpty);
      expect(acceptResult.failedResults, hasLength(2));
      await harness.expectBothPending();
      expect(harness.network.deliverCallCount, 0);
      expect(harness.network.storeInInboxCallCount, 0);

      final passHarness = _FoldedIntroHarness();
      await passHarness.seedMixedRoleIntroductions();
      final passFoldedItem = await passHarness.loadSingleFoldedItem();

      final passResult = await passFoldedIntroduction(
        introRepo: passHarness.introRepo,
        contactRepo: passHarness.contactRepo,
        p2pService: passHarness.p2pService,
        bridge: passHarness.bridge,
        foldedIntroduction: passFoldedItem,
        ownPeerId: 'peer-X',
        ownUsername: 'Mallory',
      );

      expect(
        passResult.results.map((entry) => entry.outcome),
        everyElement(FoldedIntroductionActionOutcome.failed),
      );
      expect(passResult.appliedResults, isEmpty);
      expect(passResult.failedResults, hasLength(2));
      await passHarness.expectBothPending();
      expect(passHarness.network.deliverCallCount, 0);
      expect(passHarness.network.storeInInboxCallCount, 0);
    },
  );

  test(
    'ML-KEM mismatch returns failed results without hiding pending nulls',
    () async {
      await harness.makeRecipientRoleIntroTargetMlKemMismatched();
      final foldedItem = await harness.loadSingleFoldedItem();

      final acceptResult = await acceptFoldedIntroduction(
        introRepo: harness.introRepo,
        contactRepo: harness.contactRepo,
        p2pService: harness.p2pService,
        bridge: harness.bridge,
        foldedIntroduction: foldedItem,
        ownPeerId: _FoldedIntroHarness.ownPeerId,
        ownUsername: _FoldedIntroHarness.ownUsername,
      );

      final acceptById = _resultsById(acceptResult);
      expect(acceptResult.appliedResults, hasLength(1));
      expect(acceptResult.failedResults, hasLength(1));
      expect(acceptResult.hasFailures, isTrue);
      expect(
        acceptById[_FoldedIntroHarness.recipientRoleIntroId]!.outcome,
        FoldedIntroductionActionOutcome.failed,
      );
      expect(
        acceptById[_FoldedIntroHarness.recipientRoleIntroId]!.introduction,
        isNotNull,
      );
      expect(
        acceptById[_FoldedIntroHarness.introducedRoleIntroId]!.outcome,
        FoldedIntroductionActionOutcome.applied,
      );
      final failedAcceptIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.recipientRoleIntroId,
      );
      final appliedAcceptIntro = await harness.introRepo.getIntroduction(
        _FoldedIntroHarness.introducedRoleIntroId,
      );
      expect(failedAcceptIntro, isNotNull);
      expect(failedAcceptIntro!.recipientStatus, IntroductionStatus.pending);
      expect(failedAcceptIntro.introducedStatus, IntroductionStatus.pending);
      expect(failedAcceptIntro.status, IntroductionOverallStatus.pending);
      expect(appliedAcceptIntro, isNotNull);
      expect(appliedAcceptIntro!.introducedStatus, IntroductionStatus.accepted);
      expect(appliedAcceptIntro.recipientStatus, IntroductionStatus.pending);
      expect(appliedAcceptIntro.status, IntroductionOverallStatus.pending);
      expect(harness.network.deliverCallCount, 2);
      expect(harness.network.storeInInboxCallCount, 0);

      final passHarness = _FoldedIntroHarness();
      await passHarness.seedMixedRoleIntroductions();
      await passHarness.makeRecipientRoleIntroTargetMlKemMismatched();
      final passFoldedItem = await passHarness.loadSingleFoldedItem();

      final passResult = await passFoldedIntroduction(
        introRepo: passHarness.introRepo,
        contactRepo: passHarness.contactRepo,
        p2pService: passHarness.p2pService,
        bridge: passHarness.bridge,
        foldedIntroduction: passFoldedItem,
        ownPeerId: _FoldedIntroHarness.ownPeerId,
        ownUsername: _FoldedIntroHarness.ownUsername,
      );

      final passById = _resultsById(passResult);
      expect(passResult.appliedResults, hasLength(1));
      expect(passResult.failedResults, hasLength(1));
      expect(passResult.hasFailures, isTrue);
      expect(
        passById[_FoldedIntroHarness.recipientRoleIntroId]!.outcome,
        FoldedIntroductionActionOutcome.failed,
      );
      expect(
        passById[_FoldedIntroHarness.recipientRoleIntroId]!.introduction,
        isNotNull,
      );
      expect(
        passById[_FoldedIntroHarness.introducedRoleIntroId]!.outcome,
        FoldedIntroductionActionOutcome.applied,
      );
      final failedPassIntro = await passHarness.introRepo.getIntroduction(
        _FoldedIntroHarness.recipientRoleIntroId,
      );
      final appliedPassIntro = await passHarness.introRepo.getIntroduction(
        _FoldedIntroHarness.introducedRoleIntroId,
      );
      expect(failedPassIntro, isNotNull);
      expect(failedPassIntro!.recipientStatus, IntroductionStatus.pending);
      expect(failedPassIntro.introducedStatus, IntroductionStatus.pending);
      expect(failedPassIntro.status, IntroductionOverallStatus.pending);
      expect(appliedPassIntro, isNotNull);
      expect(appliedPassIntro!.introducedStatus, IntroductionStatus.passed);
      expect(appliedPassIntro.recipientStatus, IntroductionStatus.pending);
      expect(appliedPassIntro.status, IntroductionOverallStatus.passed);
      expect(passHarness.network.deliverCallCount, 2);
      expect(passHarness.network.storeInInboxCallCount, 0);
    },
  );
}

Map<String, FoldedIntroductionActionResult> _resultsById(
  FoldedIntroductionActionBatchResult result,
) {
  return {for (final entry in result.results) entry.introductionId: entry};
}

class _FoldedIntroHarness {
  static const ownPeerId = 'peer-B';
  static const ownUsername = 'Bob';
  static const targetPeerId = 'peer-C';
  static const targetUsername = 'Charlie';
  static const firstIntroducerId = 'peer-A';
  static const secondIntroducerId = 'peer-D';
  static const recipientRoleIntroId = 'intro-recipient-role';
  static const introducedRoleIntroId = 'intro-introduced-role';

  final FakeP2PNetwork network = FakeP2PNetwork();
  late final FakeP2PService p2pService;
  final PassthroughCryptoBridge bridge = PassthroughCryptoBridge();
  final InMemoryContactRepository contactRepo = InMemoryContactRepository();
  final InMemoryIntroductionRepository introRepo =
      InMemoryIntroductionRepository();

  _FoldedIntroHarness() {
    p2pService = FakeP2PService(peerId: ownPeerId, network: network);
    FakeP2PService(peerId: firstIntroducerId, network: network);
    FakeP2PService(peerId: secondIntroducerId, network: network);
    FakeP2PService(peerId: targetPeerId, network: network);
    contactRepo.addTestContact(_contact(firstIntroducerId, 'Alice'));
    contactRepo.addTestContact(_contact(secondIntroducerId, 'Diana'));
    contactRepo.addTestContact(_contact(ownPeerId, ownUsername));
    contactRepo.addTestContact(_contact(targetPeerId, targetUsername));
  }

  Future<void> seedMixedRoleIntroductions() async {
    final createdAt = DateTime.now().toUtc();
    await introRepo.saveIntroduction(
      IntroductionModel(
        id: recipientRoleIntroId,
        introducerId: firstIntroducerId,
        recipientId: ownPeerId,
        introducedId: targetPeerId,
        introducerUsername: 'Alice',
        recipientUsername: ownUsername,
        introducedUsername: targetUsername,
        recipientMlKemPublicKey: _mlKemKey(ownPeerId),
        introducedMlKemPublicKey: _mlKemKey(targetPeerId),
        createdAt: createdAt
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      ),
    );
    await introRepo.saveIntroduction(
      IntroductionModel(
        id: introducedRoleIntroId,
        introducerId: secondIntroducerId,
        recipientId: targetPeerId,
        introducedId: ownPeerId,
        introducerUsername: 'Diana',
        recipientUsername: targetUsername,
        introducedUsername: ownUsername,
        recipientMlKemPublicKey: _mlKemKey(targetPeerId),
        introducedMlKemPublicKey: _mlKemKey(ownPeerId),
        createdAt: createdAt.toIso8601String(),
      ),
    );
    network.resetCounters();
    bridge.commandLog.clear();
    bridge.sentMessages.clear();
  }

  Future<FoldedIntroductionReviewItem> loadSingleFoldedItem() async {
    final introductions = await introRepo.getPendingIntroductionsForUser(
      ownPeerId,
    );
    final foldedItems = foldIntroductionsForReview(
      introductions: introductions,
      ownPeerId: ownPeerId,
    );

    expect(foldedItems, hasLength(1));
    final foldedItem = foldedItems.single;
    expect(foldedItem.targetPeerId, targetPeerId);
    expect(
      foldedItem.pendingCurrentViewerDecisionIntroIds,
      unorderedEquals([recipientRoleIntroId, introducedRoleIntroId]),
    );
    return foldedItem;
  }

  Future<void> makeRecipientRoleIntroTargetMlKemMismatched() async {
    final intro = await introRepo.getIntroduction(recipientRoleIntroId);
    await introRepo.saveIntroduction(
      intro!.copyWith(introducedMlKemPublicKey: 'stale-target-key'),
    );
    network.resetCounters();
    bridge.commandLog.clear();
    bridge.sentMessages.clear();
  }

  Future<void> expectBothPending() async {
    final recipientIntro = await introRepo.getIntroduction(
      recipientRoleIntroId,
    );
    final introducedIntro = await introRepo.getIntroduction(
      introducedRoleIntroId,
    );

    expect(recipientIntro, isNotNull);
    expect(recipientIntro!.recipientStatus, IntroductionStatus.pending);
    expect(recipientIntro.introducedStatus, IntroductionStatus.pending);
    expect(recipientIntro.status, IntroductionOverallStatus.pending);

    expect(introducedIntro, isNotNull);
    expect(introducedIntro!.recipientStatus, IntroductionStatus.pending);
    expect(introducedIntro.introducedStatus, IntroductionStatus.pending);
    expect(introducedIntro.status, IntroductionOverallStatus.pending);
  }

  static ContactModel _contact(
    String peerId,
    String username, {
    String? mlKemPublicKey,
  }) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: username,
      signature: 'sig-$peerId',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: mlKemPublicKey ?? _mlKemKey(peerId),
    );
  }

  static String _mlKemKey(String peerId) => 'mlkem-$peerId';
}
