import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
  );
}

void main() {
  testWidgets(
    'three-device pass-along keeps one visible receiver card and updates the original author share count',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));
      final aliceContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'))
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));

      final bobPosts = InMemoryPostRepository();
      final alicePosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final aliceRouter = IncomingMessageRouter(p2pService: aliceService)
        ..start();
      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();

      final bobPostListener = PostListener(
        postCreateStream: bobRouter.postCreateStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final alicePostListener = PostListener(
        postCreateStream: aliceRouter.postCreateStream,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
      )..start();
      final bobPassListener = PostPassListener(
        postPassStream: bobRouter.postPassStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final caraPassListener = PostPassListener(
        postPassStream: caraRouter.postPassStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();

      addTearDown(() {
        bobPostListener.dispose();
        alicePostListener.dispose();
        bobPassListener.dispose();
        caraPassListener.dispose();
        bobRouter.dispose();
        aliceRouter.dispose();
        caraRouter.dispose();
        bobPosts.dispose();
        alicePosts.dispose();
        caraPosts.dispose();
        bobService.dispose();
        aliceService.dispose();
        caraService.dispose();
      });

      final (sendResult, createdPost) = await sendPost(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        text: 'Lost dog near Neckar bridge.',
        audience: PostAudience.allFriends(),
      );
      expect(sendResult, SendPostResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      final postId = createdPost!.id;
      final beforePass = await alicePosts.getPost(postId);
      expect(beforePass, isNotNull);

      await passPostAlong(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        postId: postId,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      await tester.pump(const Duration(milliseconds: 50));

      final caraFeed = await caraPosts.loadFeed();
      final bobPost = await bobPosts.getPost(postId);

      expect(caraFeed, hasLength(1));
      expect(caraFeed.single.authorUsername, 'Bob');
      expect(caraFeed.single.passedByUsername, 'Alice');
      expect(bobPost?.shareCount, 1);
    },
  );

  testWidgets(
    'three-device pass-along preserves a renderable media snapshot for the receiver',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));
      final aliceContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'))
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));

      final bobPosts = InMemoryPostRepository();
      final alicePosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final post = PostModel(
        id: 'post-1',
        eventId: 'evt-post-1',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Photo post',
        audience: PostAudience.allFriends(),
        createdAt: '2026-03-15T10:15:30.000Z',
        visibleAt: '2026-03-15T10:15:30.000Z',
        expiresAt: '2026-03-18T10:15:30.000Z',
        mediaKind: 'image',
      );
      const attachment = PostMediaAttachmentModel(
        mediaId: 'media-1',
        postId: 'post-1',
        blobId: 'blob-1',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 248120,
        width: 1440,
        height: 1080,
        localPath: 'post_media/post-1/blob-1.jpg',
        downloadStatus: 'done',
        createdAt: '2026-03-15T10:20:00.000Z',
      );
      await bobPosts.savePost(post);
      await bobPosts.savePostMediaAttachment(attachment);
      await alicePosts.savePost(post);
      await alicePosts.savePostMediaAttachment(attachment);

      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final aliceRouter = IncomingMessageRouter(p2pService: aliceService)
        ..start();
      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();

      final bobPassListener = PostPassListener(
        postPassStream: bobRouter.postPassStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final caraPassListener = PostPassListener(
        postPassStream: caraRouter.postPassStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();

      addTearDown(() {
        bobPassListener.dispose();
        caraPassListener.dispose();
        bobRouter.dispose();
        aliceRouter.dispose();
        caraRouter.dispose();
        bobPosts.dispose();
        alicePosts.dispose();
        caraPosts.dispose();
        bobService.dispose();
        aliceService.dispose();
        caraService.dispose();
      });

      final (result, pass) = await passPostAlong(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        postId: post.id,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        recipientPeerIds: const <String>['peer-cara'],
      );
      expect(result, PassPostAlongResult.success);
      expect(pass, isNotNull);

      await tester.pump(const Duration(milliseconds: 50));

      final caraPost = await caraPosts.getPost(post.id);
      final caraAttachments = await caraPosts.loadPostMediaAttachments(post.id);

      expect(caraPost, isNotNull);
      expect(caraPost!.passedByUsername, 'Alice');
      expect(caraPost.mediaKind, 'image');
      expect(caraAttachments, hasLength(1));
      expect(caraAttachments.single.blobId, 'blob-1');
    },
  );
}
