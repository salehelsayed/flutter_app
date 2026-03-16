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
    'pin remove retries unresolved recipients and clears the pinned section after recovery',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne, recipientTwo],
      );

      final (pinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );

      expect(pinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'first recipient to receive the initial pin',
      );
      await _waitForPinnedRecipientState(
        recipientTwo,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'second recipient to receive the initial pin',
      );

      recipientTwo.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (removeResult, pinState) = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(removeResult, RemovePinResult.partiallySettled);
      expect(pinState, isNotNull);
      expect(pinState!.state, 'removed');
      expect(
        (await author.postRepo.getPostPinState('post-1'))!.state,
        'removed',
      );
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'removed',
        expectedKeepAvailable: false,
        description: 'first recipient to receive the pin removal',
      );
      expect(
        (await recipientTwo.postRepo.getPostPinState('post-1'))!.state,
        'active',
      );

      final retryableJobs = await author.postRepo
          .loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>[recipientTwo.peerId],
      );

      recipientTwo.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(retried, 1);
      await _waitForPinnedRecipientState(
        recipientTwo,
        expectedState: 'removed',
        expectedKeepAvailable: false,
        description: 'second recipient to receive the retried pin removal',
      );
      expect(await author.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
    },
  );

  test(
    'a retried stale pin remove does not override a later re-pin for the same post',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne],
      );

      final (initialPinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );

      expect(initialPinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'recipient to receive the initial pin',
      );

      recipientOne.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (removeResult, _) = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(removeResult, RemovePinResult.queuedForRetry);

      recipientOne.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final (secondPinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:30:00.000Z'),
      );

      expect(secondPinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'recipient to receive the later replacement pin',
      );

      await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        (await recipientOne.postRepo.getPostPinState('post-1'))!.state,
        'active',
      );
      expect(
        (await recipientOne.postRepo.getPost('post-1'))!.keepAvailable,
        isTrue,
      );
      expect(
        (await author.postRepo.loadRetryableFollowOnOutboxJobs())
            .where((job) => job.event.eventType == 'post_pin_update')
            .toList(growable: false),
        isEmpty,
      );
    },
  );

  test(
    'a retried stale pin remove fanout preserves the later re-pin on all recipients',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostPinUser>[recipientOne, recipientTwo],
      );

      final (initialPinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );

      expect(initialPinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'first recipient to receive the initial pin',
      );
      await _waitForPinnedRecipientState(
        recipientTwo,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'second recipient to receive the initial pin',
      );

      recipientOne.p2pService.setOnline(false);
      recipientTwo.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (removeResult, _) = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(removeResult, RemovePinResult.queuedForRetry);

      recipientOne.p2pService.setOnline(true);
      recipientTwo.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final (secondPinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:30:00.000Z'),
      );

      expect(secondPinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipientOne,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'first recipient to receive the later replacement pin',
      );
      await _waitForPinnedRecipientState(
        recipientTwo,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'second recipient to receive the later replacement pin',
      );

      final retried = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(retried, 1);
      expect(
        (await recipientOne.postRepo.getPostPinState('post-1'))!.state,
        'active',
      );
      expect(
        (await recipientOne.postRepo.getPost('post-1'))!.keepAvailable,
        isTrue,
      );
      expect(
        (await recipientTwo.postRepo.getPostPinState('post-1'))!.state,
        'active',
      );
      expect(
        (await recipientTwo.postRepo.getPost('post-1'))!.keepAvailable,
        isTrue,
      );
      expect(await author.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);
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

Future<void> _waitForPinnedRecipientState(
  _PostPinUser user, {
  required String expectedState,
  required bool expectedKeepAvailable,
  required String description,
}) async {
  Future<bool> condition() async {
    final pinState = await user.postRepo.getPostPinState('post-1');
    final post = await user.postRepo.getPost('post-1');
    if (pinState == null || post == null) {
      return false;
    }
    return pinState.state == expectedState &&
        post.keepAvailable == expectedKeepAvailable;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for $description');
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
