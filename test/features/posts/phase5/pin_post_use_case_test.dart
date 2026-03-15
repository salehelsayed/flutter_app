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

  Future<void> seedSentPost({bool keepAvailable = false}) async {
    await posts.savePost(
      postPinBasePost(
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        keepAvailable: keepAvailable,
      ).copyWith(keepAvailable: keepAvailable),
    );
    await posts.saveRecipientDelivery(
      const PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: 'peer-cara',
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:16:00.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:16:00.000Z',
        updatedAt: '2026-03-15T10:16:00.000Z',
      ),
    );
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

  test('edits an active pin and reuses post_pin_update replace semantics', () async {
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
  });

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
  });
}
