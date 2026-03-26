import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/dismiss_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/edit_pinned_post_use_case.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
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
    'fresh sender edit clears the receiver dismissal and updates the feed snapshot',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'));

      final bobPosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();

      final bobPostPinListener = PostPinListener(
        postPinUpdateStream: bobRouter.postPinUpdateStream,
        postPinRemoveStream: bobRouter.postPinRemoveStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();
      final caraPostListener = PostListener(
        postCreateStream: caraRouter.postCreateStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();
      final caraPostPinListener = PostPinListener(
        postPinUpdateStream: caraRouter.postPinUpdateStream,
        postPinRemoveStream: caraRouter.postPinRemoveStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();

      addTearDown(() {
        bobPostPinListener.dispose();
        caraPostListener.dispose();
        caraPostPinListener.dispose();
        bobRouter.dispose();
        caraRouter.dispose();
        bobPosts.dispose();
        caraPosts.dispose();
        bobService.dispose();
        caraService.dispose();
      });

      final (sendResult, createdPost) = await sendPost(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        text: 'Original offer text.',
        audience: PostAudience.allFriends(),
      );
      expect(sendResult, SendPostResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      final postId = createdPost!.id;
      final (pinResult, _) = await pinPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      expect(pinResult, PinPostResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        (await loadPinnedPosts(postRepo: caraPosts)).map((post) => post.id),
        <String>[postId],
      );

      await dismissPin(postRepo: caraPosts, postId: postId);
      expect(await loadPinnedPosts(postRepo: caraPosts), isEmpty);

      final (editResult, _) = await editPinnedPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
        text: 'Fresh blankets and hot tea available.',
      );
      expect(editResult, EditPinnedPostResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      final caraPinned = await loadPinnedPosts(postRepo: caraPosts);
      final caraFeed = await loadPostsFeed(postRepo: caraPosts);
      expect(caraPinned.map((post) => post.id), <String>[postId]);
      expect(caraPinned.single.text, 'Fresh blankets and hot tea available.');
      expect(caraFeed.single.text, 'Fresh blankets and hot tea available.');
    },
  );

  testWidgets(
    'sender remove clears the receiver pinned section but keeps the 24-hour feed card',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);

      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'));

      final bobPosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();
      final caraPostListener = PostListener(
        postCreateStream: caraRouter.postCreateStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();
      final caraPostPinListener = PostPinListener(
        postPinUpdateStream: caraRouter.postPinUpdateStream,
        postPinRemoveStream: caraRouter.postPinRemoveStream,
        postRepo: caraPosts,
        contactRepo: caraContacts,
      )..start();

      addTearDown(() {
        caraPostListener.dispose();
        caraPostPinListener.dispose();
        caraRouter.dispose();
        bobPosts.dispose();
        caraPosts.dispose();
        bobService.dispose();
        caraService.dispose();
      });

      final (sendResult, createdPost) = await sendPost(
        p2pService: bobService,
        postRepo: bobPosts,
        contactRepo: bobContacts,
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        text: 'Original offer text.',
        audience: PostAudience.allFriends(),
      );
      expect(sendResult, SendPostResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      final postId = createdPost!.id;
      await pinPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        (await loadPinnedPosts(postRepo: caraPosts)).map((post) => post.id),
        <String>[postId],
      );

      final (removeResult, _) = await removePin(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      expect(removeResult, RemovePinResult.success);
      await tester.pump(const Duration(milliseconds: 50));

      final caraPinned = await loadPinnedPosts(postRepo: caraPosts);
      final caraFeed = await loadPostsFeed(
        postRepo: caraPosts,
        nowProvider: () => DateTime.parse('2026-03-15T12:00:00.000Z'),
      );

      expect(caraPinned, isEmpty);
      expect(caraFeed.map((post) => post.id), contains(postId));
    },
  );
}
