import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/edit_pinned_post_use_case.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../improvement/support/controlled_post_pin_delivery_harness.dart';
import 'support/post_pin_fixtures.dart';

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService authorService;
  late FakeP2PService receiverService;
  late InMemoryPostRepository posts;

  setUp(() {
    network = FakeP2PNetwork();
    authorService = FakeP2PService(peerId: 'peer-bob', network: network);
    receiverService = FakeP2PService(peerId: 'peer-cara', network: network);
    posts = InMemoryPostRepository();
  });

  tearDown(() {
    posts.dispose();
    authorService.dispose();
    receiverService.dispose();
  });

  Future<void> seedSentPost({
    bool keepAvailable = false,
    List<String> recipientPeerIds = const <String>['peer-cara'],
  }) async {
    await posts.savePost(
      postPinBasePost(
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        keepAvailable: keepAvailable,
      ).copyWith(keepAvailable: keepAvailable),
    );
    for (final recipientPeerId in recipientPeerIds) {
      await posts.saveRecipientDelivery(
        PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: recipientPeerId,
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:16:00.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:16:00.000Z',
          updatedAt: '2026-03-15T10:16:00.000Z',
        ),
      );
    }
  }

  test('pins an authored post locally and sends post_pin_update', () async {
    await seedSentPost();
    final received = receiverService.messageStream.first;

    final (result, pinState) = await pinPost(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
    );

    expect(result, PinPostResult.success);
    expect(pinState, isNotNull);

    final message = await received.timeout(const Duration(seconds: 1));
    final envelope = PostPinUpdateEnvelope.fromJson(message.content);
    final updatedPost = await posts.getPost('post-1');
    final storedPinState = await posts.getPostPinState('post-1');

    expect(envelope, isNotNull);
    expect(jsonDecode(message.content)['type'], 'post_pin_update');
    expect(envelope!.snapshot.text, 'Original offer text.');
    expect(updatedPost, isNotNull);
    expect(updatedPost!.keepAvailable, isTrue);
    expect(storedPinState, isNotNull);
    expect(storedPinState!.state, 'active');
  });

  test(
    'edits an active pin and reuses post_pin_update replace semantics',
    () async {
      await seedSentPost(keepAvailable: true);
      await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      final received = receiverService.messageStream.first;

      final (result, pinState) = await editPinnedPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        text: 'Fresh blankets and hot tea available.',
      );

      expect(result, EditPinnedPostResult.success);
      expect(pinState, isNotNull);

      final message = await received.timeout(const Duration(seconds: 1));
      final envelope = PostPinUpdateEnvelope.fromJson(message.content);
      final updatedPost = await posts.getPost('post-1');

      expect(envelope, isNotNull);
      expect(envelope!.snapshot.text, 'Fresh blankets and hot tea available.');
      expect(updatedPost, isNotNull);
      expect(updatedPost!.text, 'Fresh blankets and hot tea available.');
      expect(updatedPost.keepAvailable, isTrue);
    },
  );

  test('removes an active pin locally and sends post_pin_remove', () async {
    await seedSentPost(keepAvailable: true);
    await pinPost(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
    );
    final received = receiverService.messageStream.first;

    final (result, pinState) = await removePin(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
    );

    expect(result, RemovePinResult.success);
    expect(pinState, isNotNull);

    final message = await received.timeout(const Duration(seconds: 1));
    final envelope = PostPinRemoveEnvelope.fromJson(message.content);
    final storedPinState = await posts.getPostPinState('post-1');
    final post = await posts.getPost('post-1');

    expect(envelope, isNotNull);
    expect(envelope!.reason, 'removed');
    expect(storedPinState, isNotNull);
    expect(storedPinState!.state, 'removed');
    expect(post, isNotNull);
    expect(post!.id, 'post-1');
    expect(post.keepAvailable, isFalse);
  });

  test(
    'removePin keeps the local remove and leaves a retryable outbox job when direct send and inbox storage both fail',
    () async {
      await seedSentPost(keepAvailable: true);
      await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      network.deliveryFails = true;
      network.inboxDisabled = true;

      final (result, pinState) = await removePin(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
      );

      expect(result, RemovePinResult.queuedForRetry);
      expect(pinState, isNotNull);
      expect(pinState!.state, 'removed');

      final storedPinState = await posts.getPostPinState('post-1');
      final post = await posts.getPost('post-1');
      final retryableJobs = await posts.loadRetryableFollowOnOutboxJobs();

      expect(storedPinState, isNotNull);
      expect(storedPinState!.state, 'removed');
      expect(storedPinState.effectiveAt, '2026-03-15T11:25:00.000Z');
      expect(post, isNotNull);
      expect(post!.keepAvailable, isFalse);
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_pin_remove');
    },
  );

  test('supports repeated pin and remove cycles for the same post', () async {
    await seedSentPost();

    final firstPinReceived = receiverService.messageStream.first;
    final (firstPinResult, firstPinState) = await pinPost(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
    );
    final firstPinMessage = await firstPinReceived.timeout(
      const Duration(seconds: 1),
    );

    expect(firstPinResult, PinPostResult.success);
    expect(firstPinState, isNotNull);
    expect(jsonDecode(firstPinMessage.content)['type'], 'post_pin_update');
    expect((await posts.getPost('post-1'))!.keepAvailable, isTrue);
    expect((await posts.getPostPinState('post-1'))!.state, 'active');

    final firstRemoveReceived = receiverService.messageStream.first;
    final (firstRemoveResult, firstRemoveState) = await removePin(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      nowProvider: () => DateTime.parse('2026-03-15T11:25:00.000Z'),
    );
    final firstRemoveMessage = await firstRemoveReceived.timeout(
      const Duration(seconds: 1),
    );

    expect(firstRemoveResult, RemovePinResult.success);
    expect(firstRemoveState, isNotNull);
    expect(jsonDecode(firstRemoveMessage.content)['type'], 'post_pin_remove');
    expect((await posts.getPost('post-1'))!.keepAvailable, isFalse);
    expect((await posts.getPostPinState('post-1'))!.state, 'removed');

    final secondPinReceived = receiverService.messageStream.first;
    final (secondPinResult, secondPinState) = await pinPost(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      nowProvider: () => DateTime.parse('2026-03-15T11:40:00.000Z'),
    );
    final secondPinMessage = await secondPinReceived.timeout(
      const Duration(seconds: 1),
    );

    expect(secondPinResult, PinPostResult.success);
    expect(secondPinState, isNotNull);
    expect(jsonDecode(secondPinMessage.content)['type'], 'post_pin_update');
    expect((await posts.getPost('post-1'))!.keepAvailable, isTrue);
    expect((await posts.getPostPinState('post-1'))!.state, 'active');
    expect(
      (await posts.getPostPinState('post-1'))!.effectiveAt,
      '2026-03-15T11:40:00.000Z',
    );

    final secondRemoveReceived = receiverService.messageStream.first;
    final (secondRemoveResult, secondRemoveState) = await removePin(
      p2pService: authorService,
      postRepo: posts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      nowProvider: () => DateTime.parse('2026-03-15T11:50:00.000Z'),
    );
    final secondRemoveMessage = await secondRemoveReceived.timeout(
      const Duration(seconds: 1),
    );

    expect(secondRemoveResult, RemovePinResult.success);
    expect(secondRemoveState, isNotNull);
    expect(jsonDecode(secondRemoveMessage.content)['type'], 'post_pin_remove');
    expect((await posts.getPost('post-1'))!.keepAvailable, isFalse);
    expect((await posts.getPostPinState('post-1'))!.state, 'removed');
    expect(
      (await posts.getPostPinState('post-1'))!.effectiveAt,
      '2026-03-15T11:50:00.000Z',
    );
  });

  test(
    'pinPost uses the 25 recipient default cap for follow-on delivery',
    () async {
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${(index + 1).toString().padLeft(2, '0')}',
        growable: false,
      );
      await seedSentPost(recipientPeerIds: recipientPeerIds);
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-bob',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      final pinFuture = pinPost(
        p2pService: service,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );

      await service.waitForSendCount(25);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(
        service.sendStartOrder.take(25).toList(growable: false),
        recipientPeerIds.take(25).toList(growable: false),
      );

      sendGates[recipientPeerIds.first]!.complete();
      await service.waitForSendCount(26);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, hasLength(26));

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final (result, pinState) = await pinFuture;
      expect(result, PinPostResult.success);
      expect(pinState, isNotNull);
    },
  );
}
