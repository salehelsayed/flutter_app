import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../improvement/support/controlled_post_pin_delivery_harness.dart';
import 'support/post_pin_fixtures.dart';

import '../support/legacy_post_state.dart';

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

  test(
    'rejects legacy pin: pins an authored post locally and sends post_pin_update',
    () async {
      await seedSentPost();

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pin: edits an active pin and reuses post_pin_update replace semantics',
    () async {
      await seedSentPost(keepAvailable: true);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pin: editPinnedPost strips dangerous bidi controls from updated text',
    () async {
      await seedSentPost(keepAvailable: true);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pin: removes an active pin locally and sends post_pin_remove',
    () async {
      await seedSentPost(keepAvailable: true);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pin: removePin keeps the local remove and leaves a retryable outbox job when direct send and inbox storage both fail',
    () async {
      await seedSentPost(keepAvailable: true);

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects legacy pin: supports repeated pin and remove cycles for the same post',
    () async {
      await seedSentPost();


      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      final repeated = await pinPost(
        p2pService: authorService,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        nowProvider: () => DateTime.parse('2026-03-15T11:20:00.000Z'),
      );
      expect(repeated.$1, PinPostResult.sendFailed);
      expect(await snapshotLegacyPostState(posts), before);
    },
  );

  test(
    'rejects legacy pin: pinPost uses the 25 recipient default cap for follow-on delivery',
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

      final before = await snapshotLegacyPostState(posts);
      final rejection = await pinPost(
        p2pService: service,
        postRepo: posts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
      );
      expect(rejection.$1, PinPostResult.sendFailed);
      expect(rejection.$2, isNull);
      expect(await snapshotLegacyPostState(posts), before);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );
}
