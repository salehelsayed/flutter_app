import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../phase5/support/post_pin_fixtures.dart';
import 'support/controlled_post_pin_delivery_harness.dart';

import '../support/legacy_post_state.dart';

void main() {
  late FakeP2PNetwork network;
  late _PostPinUser author;
  late _PostPinUser recipientOne;
  late _PostPinUser recipientTwo;

  setUp(() {
    network = FakeP2PNetwork();
    author = _PostPinUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipientOne = _PostPinUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );
    recipientTwo = _PostPinUser.create(
      peerId: 'peer-drew',
      username: 'Drew',
      network: network,
    );
    recipientOne.addContact(author);
    recipientTwo.addContact(author);
    recipientOne.start();
    recipientTwo.start();
  });

  tearDown(() {
    author.dispose();
    recipientOne.dispose();
    recipientTwo.dispose();
  });

  test(
    'retryPostPinFollowOnJob honors the 25 recipient default cap for unresolved pin recipients',
    () async {
      const createdAt = '2026-03-15T11:25:00.000Z';
      const eventId = 'evt-pin-retry-default-cap';
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${(index + 1).toString().padLeft(2, '0')}',
        growable: false,
      );
      final postRepo = InMemoryPostRepository();
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(postRepo.dispose);
      addTearDown(service.dispose);

      await postRepo.saveFollowOnOutboxEvent(
        const PostFollowOnOutboxEvent(
          eventId: eventId,
          eventType: postPinRemoveFollowOnEventType,
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          rawEnvelope: '{"type":"post_pin_remove"}',
          createdAt: createdAt,
        ),
      );
      for (final recipientPeerId in recipientPeerIds) {
        await postRepo.saveFollowOnOutboxRecipientDelivery(
          PostFollowOnOutboxRecipientDelivery(
            eventId: eventId,
            recipientPeerId: recipientPeerId,
            deliveryStatus: 'failed',
            deliveryPath: 'failed',
            lastError: 'direct_send_failed',
            lastAttemptAt: createdAt,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
      }

      final job = (await postRepo.loadRetryableFollowOnOutboxJobs()).single;
      final retryFuture = retryPostPinFollowOnJob(
        postRepo: postRepo,
        p2pService: service,
        job: job,
      );

      await service.waitForSendCount(25);
      await drainPostPinDeliveryMicrotasks(6);

      expect(service.maxInFlightSends, 25);
      expect(
        service.sendStartOrder.take(25).toList(growable: false),
        recipientPeerIds.take(25).toList(growable: false),
      );

      sendGates[recipientPeerIds[6]]!.complete();
      await service.waitForSendCount(26);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, hasLength(26));

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final result = await retryFuture;
      expect(result.settlement, PostFollowOnSettlement.fullySettled);
      expect(service.maxInFlightSends, 25);
    },
  );

  test(
    'disabled legacy feature produces no delivery or retry: pin remove retries unresolved recipients and clears the pinned section after recovery',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne, recipientTwo],
      );
      final before = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      final rejection = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      final removal = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(removal.$1, RemovePinResult.sendFailed);
      expect(removal.$2, isNull);
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      final after = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      expect(after, before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'disabled legacy feature produces no delivery or retry: a retried stale pin remove does not override a later re-pin for the same post',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne],
      );
      final before = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      final rejection = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      final removal = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(removal.$1, RemovePinResult.sendFailed);
      expect(removal.$2, isNull);
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      final after = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      expect(after, before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'disabled legacy feature produces no delivery or retry: a retried stale pin remove fanout preserves the later re-pin on all recipients',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne, recipientTwo],
      );
      final before = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      final rejection = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      final removal = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(removal.$1, RemovePinResult.sendFailed);
      expect(removal.$2, isNull);
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      expect(
        await retryPendingPostFollowOns(
          postRepo: author.postRepo,
          p2pService: author.p2pService,
        ),
        0,
      );
      final after = <Map<String, Object?>>[
        await snapshotLegacyPostState(author.postRepo),
        await snapshotLegacyPostState(recipientOne.postRepo),
        await snapshotLegacyPostState(recipientTwo.postRepo),
      ];
      expect(after, before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );
}

Future<void> _seedSharedPost({
  required _PostPinUser author,
  required List<_PostPinUser> recipients,
}) async {
  await author.postRepo.savePost(
    postPinBasePost(
      authorPeerId: author.peerId,
      authorUsername: author.username,
      keepAvailable: false,
    ),
  );
  for (final recipient in recipients) {
    await author.postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: recipient.peerId,
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:16:00.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:16:00.000Z',
        updatedAt: '2026-03-15T10:16:00.000Z',
      ),
    );
    await recipient.postRepo.savePost(
      postPinBasePost(
        authorPeerId: author.peerId,
        authorUsername: author.username,
        keepAvailable: false,
      ),
    );
  }
}

class _PostPinUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostPinListener pinListener;

  _PostPinUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.pinListener,
  });

  factory _PostPinUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final pinListener = PostPinListener(
      postPinUpdateStream: router.postPinUpdateStream,
      postPinRemoveStream: router.postPinRemoveStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    return _PostPinUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      pinListener: pinListener,
    );
  }

  void addContact(_PostPinUser other) {
    contactRepo.addTestContact(postPinContact(other.peerId, other.username));
  }

  void start() {
    router.start();
    pinListener.start();
  }

  void dispose() {
    pinListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}
