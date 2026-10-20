import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/edit_pinned_post_use_case.dart';
import 'package:flutter_app/features/posts/application/load_pinned_posts_use_case.dart';
import 'package:flutter_app/features/posts/application/load_posts_feed_use_case.dart';
import 'package:flutter_app/features/posts/application/pin_post_use_case.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/remove_pin_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/shared/fakes/fake_p2p_network.dart';
import '../test/shared/fakes/fake_p2p_service_integration.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_post_repository.dart';
import '../test/features/posts/support/legacy_post_state.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

void main() {
  testWidgets(
    'pinning and editing a thought are rejected without changing either peer',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);
      bobService.connectedPeers.add('peer-cara');

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
        bridge: FakeBridge(),
        getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
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
        bridge: FakeBridge(),
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
      final senderBefore = await snapshotLegacyPostState(
        bobPosts,
        postId: postId,
      );
      final receiverBefore = await snapshotLegacyPostState(
        caraPosts,
        postId: postId,
      );
      final (pinResult, _) = await pinPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      expect(pinResult, PinPostResult.sendFailed);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        (await loadPinnedPosts(postRepo: caraPosts)).map((post) => post.id),
        isEmpty,
      );

      expect(await loadPinnedPosts(postRepo: caraPosts), isEmpty);

      final (editResult, _) = await editPinnedPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
        text: 'Fresh blankets and hot tea available.',
      );
      expect(editResult, EditPinnedPostResult.sendFailed);
      await tester.pump(const Duration(milliseconds: 50));

      final caraPinned = await loadPinnedPosts(postRepo: caraPosts);
      final caraFeed = await loadPostsFeed(postRepo: caraPosts);
      expect(caraPinned, isEmpty);
      expect(caraFeed.single.text, 'Original offer text.');
      expect(
        await snapshotLegacyPostState(bobPosts, postId: postId),
        senderBefore,
      );
      expect(
        await snapshotLegacyPostState(caraPosts, postId: postId),
        receiverBefore,
      );
    },
  );

  testWidgets(
    'pinning and removal are rejected while the 24-hour feed thought stays intact',
    (tester) async {
      final network = FakeP2PNetwork();
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
      final caraService = FakeP2PService(peerId: 'peer-cara', network: network);
      bobService.connectedPeers.add('peer-cara');

      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-cara', 'Cara'));
      final caraContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'));

      final bobPosts = InMemoryPostRepository();
      final caraPosts = InMemoryPostRepository();

      final caraRouter = IncomingMessageRouter(p2pService: caraService)
        ..start();
      final caraPostListener = PostListener(
        bridge: FakeBridge(),
        getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
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
        bridge: FakeBridge(),
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
      final senderBefore = await snapshotLegacyPostState(
        bobPosts,
        postId: postId,
      );
      final receiverBefore = await snapshotLegacyPostState(
        caraPosts,
        postId: postId,
      );
      await pinPost(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        (await loadPinnedPosts(postRepo: caraPosts)).map((post) => post.id),
        isEmpty,
      );

      final (removeResult, _) = await removePin(
        p2pService: bobService,
        postRepo: bobPosts,
        postId: postId,
        senderPeerId: 'peer-bob',
      );
      expect(removeResult, RemovePinResult.sendFailed);
      await tester.pump(const Duration(milliseconds: 50));

      final caraPinned = await loadPinnedPosts(postRepo: caraPosts);
      final caraFeed = await loadPostsFeed(postRepo: caraPosts);

      expect(caraPinned, isEmpty);
      expect(caraFeed.map((post) => post.id), contains(postId));
      expect(
        DateTime.parse(
          caraFeed.single.expiresAt,
        ).difference(DateTime.parse(caraFeed.single.createdAt)),
        const Duration(hours: 24),
      );
      expect(
        await snapshotLegacyPostState(bobPosts, postId: postId),
        senderBefore,
      );
      expect(
        await snapshotLegacyPostState(caraPosts, postId: postId),
        receiverBefore,
      );
    },
  );
}
