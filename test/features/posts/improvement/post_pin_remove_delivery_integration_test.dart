import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../phase5/support/post_pin_fixtures.dart';

void main() {
  late FakeP2PNetwork network;
  late _PostPinUser author;
  late _PostPinUser recipient;

  setUp(() {
    network = FakeP2PNetwork();
    author = _PostPinUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipient = _PostPinUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );
    recipient.addContact(author);
    recipient.start();
  });

  tearDown(() {
    author.dispose();
    recipient.dispose();
  });

  test(
    'author pin and remove travel through router and listener to update recipient pinned state',
    () async {
      await _seedSharedPost(author: author, recipient: recipient);

      final (pinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );

      expect(pinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipient,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'recipient to receive the pin update',
      );
      expect(
        (await loadPinnedPosts(
          postRepo: recipient.postRepo,
        )).map((post) => post.id),
        <String>['post-1'],
      );

      final (removeResult, _) = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(removeResult, RemovePinResult.success);
      await _waitForPinnedRecipientState(
        recipient,
        expectedState: 'removed',
        expectedKeepAvailable: false,
        description: 'recipient to receive the pin removal',
      );
      expect(await loadPinnedPosts(postRepo: recipient.postRepo), isEmpty);
    },
  );

  test(
    'full remove delivery failure leaves a queued sender remove and retryable outbox state',
    () async {
      await _seedSharedPost(author: author, recipient: recipient);
      final (pinResult, _) = await pinPost(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );

      expect(pinResult, PinPostResult.success);
      await _waitForPinnedRecipientState(
        recipient,
        expectedState: 'active',
        expectedKeepAvailable: true,
        description: 'recipient to receive the initial pin update',
      );

      network.deliveryFails = true;
      network.inboxDisabled = true;

      final (removeResult, pinState) = await removePin(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(removeResult, RemovePinResult.queuedForRetry);
      expect(pinState, isNotNull);
      expect(pinState!.state, 'removed');
      expect((await author.postRepo.getPost('post-1'))!.keepAvailable, isFalse);
      expect(
        (await author.postRepo.getPostPinState('post-1'))!.state,
        'removed',
      );
      expect(
        (await loadPinnedPosts(
          postRepo: recipient.postRepo,
        )).map((post) => post.id),
        <String>['post-1'],
      );
      expect(
        (await recipient.postRepo.getPostPinState('post-1'))!.state,
        'active',
      );
      expect(network.inboxCount(recipient.peerId), 0);
      final retryableJobs = await author.postRepo
          .loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_pin_remove');
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>[recipient.peerId],
      );
    },
  );
}

Future<void> _seedSharedPost({
  required _PostPinUser author,
  required _PostPinUser recipient,
}) async {
  await author.postRepo.savePost(
    postPinBasePost(
      authorPeerId: author.peerId,
      authorUsername: author.username,
      keepAvailable: false,
    ),
  );
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
