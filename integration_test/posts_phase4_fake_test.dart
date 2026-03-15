import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pass_post_along_use_case.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

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
}
