import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
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
    'live delivery and offline replay converge into the same post repo',
    (tester) async {
      final network = FakeP2PNetwork();
      final aliceService = FakeP2PService(
        peerId: 'peer-alice',
        network: network,
      );
      final bobService = FakeP2PService(peerId: 'peer-bob', network: network);

      final aliceContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-bob', 'Bob'));
      final bobContacts = InMemoryContactRepository()
        ..addTestContact(_contact('peer-alice', 'Alice'));

      final alicePosts = InMemoryPostRepository();
      final bobPosts = InMemoryPostRepository();
      final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
      final bobListener = PostListener(
        postCreateStream: bobRouter.postCreateStream,
        postRepo: bobPosts,
        contactRepo: bobContacts,
      )..start();

      final liveResult = await sendPost(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Live post',
        audience: PostAudience.allFriends(),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(liveResult.$1, SendPostResult.success);
      expect((await bobPosts.loadFeed()), hasLength(1));

      bobService.setOnline(false);
      await sendPost(
        p2pService: aliceService,
        postRepo: alicePosts,
        contactRepo: aliceContacts,
        senderPeerId: 'peer-alice',
        senderUsername: 'Alice',
        text: 'Replay post',
        audience: PostAudience.allFriends(),
      );

      expect((await bobPosts.loadFeed()), hasLength(1));
      expect(network.inboxCount('peer-bob'), 1);

      bobService.setOnline(true);
      await bobService.drainOfflineInbox();
      await tester.pump(const Duration(milliseconds: 50));

      expect((await bobPosts.loadFeed()), hasLength(2));

      bobListener.dispose();
      bobRouter.dispose();
      alicePosts.dispose();
      bobPosts.dispose();
    },
  );
}
