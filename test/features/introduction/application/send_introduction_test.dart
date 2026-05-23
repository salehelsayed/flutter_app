import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/introduction/application/send_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_outbox_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/pending_introduction_response.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_introduction_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _ControlledP2PService p2pServiceA;
  late PassthroughCryptoBridge bridge;
  late _TrackingContactRepository contactRepo;
  late InMemoryIntroductionRepository introRepo;

  late ContactModel contactB;
  late ContactModel contactC;
  late ContactModel contactD;

  setUp(() {
    network = FakeP2PNetwork();
    p2pServiceA = _ControlledP2PService(peerId: 'peer-A', network: network);
    // Register receivers on the network so delivery succeeds
    FakeP2PService(peerId: 'peer-B', network: network);
    FakeP2PService(peerId: 'peer-C', network: network);
    FakeP2PService(peerId: 'peer-D', network: network);
    bridge = PassthroughCryptoBridge();
    contactRepo = _TrackingContactRepository();
    introRepo = InMemoryIntroductionRepository();

    contactB = ContactModel(
      peerId: 'peer-B',
      publicKey: 'pk-peer-B',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Bob',
      signature: 'sig-peer-B',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-B',
    );

    contactC = ContactModel(
      peerId: 'peer-C',
      publicKey: 'pk-peer-C',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Charlie',
      signature: 'sig-peer-C',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-C',
    );

    contactD = ContactModel(
      peerId: 'peer-D',
      publicKey: 'pk-peer-D',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Diana',
      signature: 'sig-peer-D',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'test-mlkem-pk-peer-D',
    );

    contactRepo.addTestContact(contactB);
    contactRepo.addTestContact(contactC);
    contactRepo.addTestContact(contactD);
  });

  ContactModel createFriend(int index, {bool hasMlKemKey = true}) {
    final suffix = index.toString().padLeft(2, '0');
    final contact = ContactModel(
      peerId: 'peer-F$suffix',
      publicKey: 'pk-peer-F$suffix',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Friend $suffix',
      signature: 'sig-peer-F$suffix',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: hasMlKemKey ? 'test-mlkem-pk-peer-F$suffix' : null,
    );
    contactRepo.addTestContact(contact);
    FakeP2PService(peerId: contact.peerId, network: network);
    return contact;
  }

  List<ContactModel> createFriends(int count) =>
      List.generate(count, (index) => createFriend(index + 1));

  Future<List<IntroductionModel>> sendFriends(
    List<ContactModel> friends, {
    String? recipientMlKemPublicKey,
    void Function(int completed, int total)? onProgress,
  }) {
    return sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pServiceA,
      bridge: bridge,
      introducerPeerId: 'peer-A',
      introducerUsername: 'Alice',
      recipientPeerId: 'peer-B',
      recipientUsername: 'Bob',
      recipientMlKemPublicKey:
          recipientMlKemPublicKey ?? contactB.mlKemPublicKey,
      friendsToIntroduce: friends,
      onProgress: onProgress,
    );
  }

  Future<List<IntroductionModel>> sendTwoFriends() {
    return sendFriends([contactC, contactD]);
  }

  test('creates N introduction records for N selected friends', () async {
    final results = await sendTwoFriends();
    expect(results.length, 2);
  });

  test('each record has correct introducerId', () async {
    final results = await sendTwoFriends();
    for (final model in results) {
      expect(model.introducerId, 'peer-A');
    }
  });

  test('each record has correct recipientId and introducedId', () async {
    final results = await sendTwoFriends();
    expect(results[0].recipientId, 'peer-B');
    expect(results[0].introducedId, 'peer-C');
    expect(results[1].recipientId, 'peer-B');
    expect(results[1].introducedId, 'peer-D');
  });

  test('each record initializes with pending statuses', () async {
    final results = await sendTwoFriends();
    for (final model in results) {
      expect(model.recipientStatus, IntroductionStatus.pending);
      expect(model.introducedStatus, IntroductionStatus.pending);
      expect(model.status, IntroductionOverallStatus.pending);
    }
  });

  test('introsSentAt is set on the recipient contact', () async {
    await sendTwoFriends();
    final updatedContact = await contactRepo.getContact('peer-B');
    expect(updatedContact, isNotNull);
    expect(updatedContact!.introsSentAt, isNotNull);
  });

  test('payload sent to recipient via P2P', () async {
    await sendTwoFriends();
    // 2 friends x 2 messages each (one to recipient, one to friend) = 4 deliveries
    // At minimum, 2 messages go to the recipient (one per friend)
    expect(network.deliverCallCount, greaterThanOrEqualTo(2));
  });

  test('payload sent to introduced friend via P2P', () async {
    await sendTwoFriends();
    // 2 friends: each gets 1 message to recipient + 1 message to friend = 4 total
    expect(network.deliverCallCount, 4);
  });

  test('v2 encryption used when target has ML-KEM key', () async {
    await sendTwoFriends();
    // All 4 targets (recipient x2, friend-C, friend-D) have ML-KEM keys
    final encryptCalls = bridge.commandLog
        .where((cmd) => cmd == 'message.encrypt')
        .length;
    expect(encryptCalls, 4);
  });

  test(
    'uses the effective recipient ML-KEM key consistently for encryption and intro metadata',
    () async {
      contactRepo.addTestContact(
        contactB.copyWith(mlKemPublicKey: 'stale-repo-mlkem-peer-B'),
      );

      final results = await sendFriends([
        contactC,
      ], recipientMlKemPublicKey: 'fresh-argument-mlkem-peer-B');

      expect(
        results.single.recipientMlKemPublicKey,
        'fresh-argument-mlkem-peer-B',
      );

      final persisted = await introRepo.getIntroduction(results.single.id);
      expect(persisted, isNotNull);
      expect(persisted!.recipientMlKemPublicKey, 'fresh-argument-mlkem-peer-B');

      final encryptRequests = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((request) => request['cmd'] == 'message.encrypt')
          .toList(growable: false);
      expect(encryptRequests, hasLength(2));

      final encryptionTargetKeys = encryptRequests
          .map(
            (request) =>
                (request['payload']
                        as Map<String, dynamic>)['recipientPublicKey']
                    as String,
          )
          .toList(growable: false);
      expect(encryptionTargetKeys, contains('fresh-argument-mlkem-peer-B'));
      expect(encryptionTargetKeys, contains(contactC.mlKemPublicKey));

      final payloadRecipientKeys = encryptRequests
          .map(
            (request) =>
                jsonDecode(
                      (request['payload'] as Map<String, dynamic>)['plaintext']
                          as String,
                    )
                    as Map<String, dynamic>,
          )
          .map((payload) => payload['recipientMlKemPublicKey'])
          .toList(growable: false);
      expect(payloadRecipientKeys, everyElement('fresh-argument-mlkem-peer-B'));
    },
  );

  test('v1 plaintext used when target lacks ML-KEM key', () async {
    // Create a friend without ML-KEM key
    final contactNoMlKem = ContactModel(
      peerId: 'peer-E',
      publicKey: 'pk-peer-E',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Eve',
      signature: 'sig-peer-E',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: null,
    );
    contactRepo.addTestContact(contactNoMlKem);
    await contactRepo.deleteContact('peer-B');
    contactRepo.addTestContact(
      ContactModel(
        peerId: 'peer-B',
        publicKey: 'pk-peer-B',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob',
        signature: 'sig-peer-B',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    // Register receiver on network so delivery succeeds
    FakeP2PService(peerId: 'peer-E', network: network);

    bridge.commandLog.clear();

    await sendIntroductions(
      contactRepo: contactRepo,
      introRepo: introRepo,
      p2pService: p2pServiceA,
      bridge: bridge,
      introducerPeerId: 'peer-A',
      introducerUsername: 'Alice',
      recipientPeerId: 'peer-B',
      recipientUsername: 'Bob',
      recipientMlKemPublicKey: null, // No ML-KEM for recipient either
      friendsToIntroduce: [contactNoMlKem],
    );

    // Neither recipient nor introduced friend has ML-KEM key → no encrypt calls
    final encryptCalls = bridge.commandLog
        .where((cmd) => cmd == 'message.encrypt')
        .length;
    expect(encryptCalls, 0);
  });

  test('returns list of created IntroductionModels', () async {
    final results = await sendTwoFriends();
    expect(results, isList);
    expect(results.length, 2);
    // Each result should have a non-empty ID
    for (final model in results) {
      expect(model.id, isNotEmpty);
    }
  });

  test('records are persisted in introRepo', () async {
    final results = await sendTwoFriends();
    for (final model in results) {
      final persisted = await introRepo.getIntroduction(model.id);
      expect(persisted, isNotNull);
      expect(persisted!.id, model.id);
      expect(persisted.introducerId, 'peer-A');
      expect(persisted.recipientId, 'peer-B');
    }
  });

  test('re-sending the same pair replaces the older local intro row', () async {
    final firstRound = await sendFriends([contactC]);
    final firstIntro = firstRound.single;

    await introRepo.updateRecipientStatus(
      firstIntro.id,
      IntroductionStatus.passed,
    );
    await introRepo.updateOverallStatus(
      firstIntro.id,
      IntroductionOverallStatus.passed,
    );

    final secondRound = await sendFriends([contactC]);
    final secondIntro = secondRound.single;

    expect(secondIntro.id, isNot(firstIntro.id));
    expect(await introRepo.getIntroduction(firstIntro.id), isNull);

    final stored = await introRepo.getIntroductionsByIntroducer('peer-A');
    final pairRows = stored
        .where(
          (intro) =>
              intro.recipientId == 'peer-B' && intro.introducedId == 'peer-C',
        )
        .toList(growable: false);
    expect(pairRows, hasLength(1));
    expect(pairRows.single.id, secondIntro.id);
    expect(pairRows.single.status, IntroductionOverallStatus.pending);
    expect(pairRows.single.recipientStatus, IntroductionStatus.pending);
    expect(pairRows.single.introducedStatus, IntroductionStatus.pending);
  });

  test(
    're-sending the same pair rekeys pending responses from the replaced intro id',
    () async {
      final firstRound = await sendFriends([contactC]);
      final firstIntro = firstRound.single;
      await introRepo.savePendingResponse(
        PendingIntroductionResponse(
          responseKey: PendingIntroductionResponse.buildResponseKey(
            introductionId: firstIntro.id,
            responderId: 'peer-C',
            action: 'accept',
          ),
          introductionId: firstIntro.id,
          action: 'accept',
          responderId: 'peer-C',
          responderUsername: 'Charlie',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      final secondRound = await sendFriends([contactC]);
      final secondIntro = secondRound.single;

      expect(await introRepo.loadPendingResponses(firstIntro.id), isEmpty);
      final migratedResponses = await introRepo.loadPendingResponses(
        secondIntro.id,
      );
      expect(migratedResponses, hasLength(1));
      expect(
        migratedResponses.single.responseKey,
        PendingIntroductionResponse.buildResponseKey(
          introductionId: secondIntro.id,
          responderId: 'peer-C',
          action: 'accept',
        ),
      );
      expect(migratedResponses.single.responderId, 'peer-C');
      expect(migratedResponses.single.action, 'accept');
    },
  );

  test(
    're-sending the same pair after expiry replaces the expired local row with a fresh pending intro',
    () async {
      final firstRound = await sendFriends([contactC]);
      final firstIntro = firstRound.single;
      final thirtyOneDaysAgo = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 31))
          .toIso8601String();

      await introRepo.saveIntroduction(
        firstIntro.copyWith(
          createdAt: thirtyOneDaysAgo,
          status: IntroductionOverallStatus.expired,
        ),
      );

      expect(await introRepo.countPendingIntroductions('peer-B'), 0);

      final secondRound = await sendFriends([contactC]);
      final secondIntro = secondRound.single;

      expect(secondIntro.id, isNot(firstIntro.id));
      expect(await introRepo.getIntroduction(firstIntro.id), isNull);

      final stored = await introRepo.getIntroductionsByIntroducer('peer-A');
      final pairRows = stored
          .where(
            (intro) =>
                intro.recipientId == 'peer-B' && intro.introducedId == 'peer-C',
          )
          .toList(growable: false);
      expect(pairRows, hasLength(1));
      expect(pairRows.single.id, secondIntro.id);
      expect(pairRows.single.status, IntroductionOverallStatus.pending);
      expect(pairRows.single.recipientStatus, IntroductionStatus.pending);
      expect(pairRows.single.introducedStatus, IntroductionStatus.pending);
      expect(await introRepo.countPendingIntroductions('peer-B'), 1);
    },
  );

  test(
    'persists both outbound target rows before a delivery-stage crash',
    () async {
      final crashingRepo = _CrashAfterNthOutboxSaveIntroductionRepository(
        crashOnSaveNumber: 1,
      );
      introRepo = crashingRepo;

      await expectLater(
        sendFriends([contactC]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'simulated crash after first remote delivery',
          ),
        ),
      );

      final stored = await crashingRepo.getIntroductionsByIntroducer('peer-A');
      expect(stored, hasLength(1));
      expect(stored.single.recipientId, 'peer-B');
      expect(stored.single.introducedId, 'peer-C');
      expect(stored.single.status, IntroductionOverallStatus.pending);

      final deliveries = await crashingRepo.loadOutboxDeliveriesForIntroduction(
        stored.single.id,
      );
      expect(deliveries.map((delivery) => delivery.targetPeerId).toSet(), {
        'peer-B',
        'peer-C',
      });
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement(IntroductionOutboxDeliveryStatus.sending),
      );
      expect(network.deliverCallCount, 1);
    },
  );

  test(
    'caps active intro work at 10 and splits later friends into a second batch',
    () async {
      final friends = createFriends(15);
      p2pServiceA.blockMatcher = (targetPeerId, _) => targetPeerId != 'peer-B';

      final sendFuture = sendFriends(friends);

      await p2pServiceA.waitForBlockedSendCount(10);
      expect(p2pServiceA.activeBlockedSends, 10);
      expect(p2pServiceA.peakBlockedSends, 10);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(p2pServiceA.blockedSendCount, 10);

      p2pServiceA.releaseBlockedSendsThrough(10);

      await p2pServiceA.waitForBlockedSendCount(15);
      await p2pServiceA.waitForActiveBlockedSends(5);
      expect(p2pServiceA.peakBlockedSends, lessThanOrEqualTo(10));

      p2pServiceA.releaseAllBlockedSends();

      final results = await sendFuture;
      expect(
        results.map((model) => model.introducedId).toList(),
        friends.map((friend) => friend.peerId).toList(),
      );
    },
  );

  test(
    'continues across inbox fallback in the same and later batches',
    () async {
      final friends = createFriends(12);
      final fallbackTargets = {friends[2].peerId, friends[10].peerId};
      p2pServiceA.failMatcher = (targetPeerId, _) =>
          fallbackTargets.contains(targetPeerId);

      final results = await sendFriends(friends);

      expect(results.length, 12);
      expect(
        results.map((model) => model.introducedId).toList(),
        friends.map((friend) => friend.peerId).toList(),
      );
      expect(p2pServiceA.storeInInboxTargets.toSet(), fallbackTargets);
      expect(network.storeInInboxCallCount, 2);
    },
  );

  test(
    'returns results in input friend order instead of completion order',
    () async {
      final friends = createFriends(3);
      p2pServiceA.blockMatcher = (targetPeerId, _) => targetPeerId != 'peer-B';

      final sendFuture = sendFriends(friends);

      await p2pServiceA.waitForBlockedSendCount(3);

      p2pServiceA.releaseBlockedSendAt(2);
      p2pServiceA.releaseBlockedSendAt(1);
      p2pServiceA.releaseBlockedSendAt(0);

      final results = await sendFuture;

      expect(
        p2pServiceA.completedBlockedTargets,
        friends.reversed.map((friend) => friend.peerId).toList(),
      );
      expect(
        results.map((model) => model.introducedId).toList(),
        friends.map((friend) => friend.peerId).toList(),
      );
    },
  );

  test('sets introsSentAt once after all batches finish', () async {
    final friends = createFriends(12);
    p2pServiceA.blockMatcher = (targetPeerId, _) => targetPeerId != 'peer-B';

    final sendFuture = sendFriends(friends);

    await p2pServiceA.waitForBlockedSendCount(10);
    expect(contactRepo.setIntrosSentAtCallCount, 0);

    p2pServiceA.releaseBlockedSendsThrough(10);

    await p2pServiceA.waitForBlockedSendCount(12);
    expect(contactRepo.setIntrosSentAtCallCount, 0);

    p2pServiceA.releaseAllBlockedSends();

    await sendFuture;
    expect(contactRepo.setIntrosSentAtCallCount, 1);
  });

  test('reports truthful progress only when an intro chain settles', () async {
    final friends = createFriends(3);
    final progressUpdates = <String>[];
    p2pServiceA.blockMatcher = (targetPeerId, _) => targetPeerId != 'peer-B';

    final sendFuture = sendFriends(
      friends,
      onProgress: (completed, total) {
        progressUpdates.add('$completed/$total');
      },
    );

    await p2pServiceA.waitForBlockedSendCount(3);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(progressUpdates, ['0/3']);

    p2pServiceA.releaseBlockedSendAt(1);
    await _waitForCondition(() => progressUpdates.length == 2);
    expect(progressUpdates, ['0/3', '1/3']);

    p2pServiceA.releaseBlockedSendAt(0);
    await _waitForCondition(() => progressUpdates.length == 3);
    expect(progressUpdates, ['0/3', '1/3', '2/3']);

    p2pServiceA.releaseBlockedSendAt(2);

    final results = await sendFuture;
    expect(results.length, 3);
    expect(progressUpdates, ['0/3', '1/3', '2/3', '3/3']);
  });
}

Future<void> _waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for test condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _ControlledP2PService extends FakeP2PService {
  _ControlledP2PService({required super.peerId, required super.network});

  bool Function(String targetPeerId, String message)? blockMatcher;
  bool Function(String targetPeerId, String message)? failMatcher;

  final List<String> storeInInboxTargets = [];
  final List<String> completedBlockedTargets = [];
  final List<Completer<void>> _blockedSendCompleters = [];

  int blockedSendCount = 0;
  int activeBlockedSends = 0;
  int peakBlockedSends = 0;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final shouldBlock = blockMatcher?.call(targetPeerId, message) ?? false;
    if (shouldBlock) {
      final completer = Completer<void>();
      _blockedSendCompleters.add(completer);
      blockedSendCount++;
      activeBlockedSends++;
      peakBlockedSends = peakBlockedSends > activeBlockedSends
          ? peakBlockedSends
          : activeBlockedSends;
      try {
        await completer.future;
      } finally {
        activeBlockedSends--;
      }
    }

    if (failMatcher?.call(targetPeerId, message) ?? false) {
      return const SendMessageResult(sent: false);
    }

    final sendResult = await super.sendMessageWithReply(
      targetPeerId,
      message,
      timeoutMs: timeoutMs,
    );
    if (shouldBlock) {
      completedBlockedTargets.add(targetPeerId);
    }
    return sendResult;
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxTargets.add(toPeerId);
    return super.storeInInbox(toPeerId, message);
  }

  void releaseBlockedSendAt(int index) {
    final completer = _blockedSendCompleters[index];
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  void releaseBlockedSendsThrough(int count) {
    for (
      var index = 0;
      index < count && index < _blockedSendCompleters.length;
      index++
    ) {
      releaseBlockedSendAt(index);
    }
  }

  void releaseAllBlockedSends() {
    for (var index = 0; index < _blockedSendCompleters.length; index++) {
      releaseBlockedSendAt(index);
    }
  }

  Future<void> waitForBlockedSendCount(int count) {
    return _waitForCondition(() => blockedSendCount >= count);
  }

  Future<void> waitForActiveBlockedSends(int count) {
    return _waitForCondition(() => activeBlockedSends == count);
  }
}

class _TrackingContactRepository extends InMemoryContactRepository {
  int setIntrosSentAtCallCount = 0;

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {
    setIntrosSentAtCallCount++;
    await super.setIntrosSentAt(peerId, timestamp);
  }
}

class _CrashAfterNthOutboxSaveIntroductionRepository
    extends InMemoryIntroductionRepository {
  _CrashAfterNthOutboxSaveIntroductionRepository({
    required this.crashOnSaveNumber,
  });

  final int crashOnSaveNumber;
  int _saveOutboxDeliveryCalls = 0;

  @override
  Future<void> saveOutboxDelivery(IntroductionOutboxDelivery delivery) async {
    _saveOutboxDeliveryCalls++;
    if (_saveOutboxDeliveryCalls == crashOnSaveNumber) {
      throw StateError('simulated crash after first remote delivery');
    }
    await super.saveOutboxDelivery(delivery);
  }
}
