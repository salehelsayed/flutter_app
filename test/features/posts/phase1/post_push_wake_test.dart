import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_notification_open_coordinator.dart';
import 'package:flutter_app/features/posts/application/send_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

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
  testWidgets('simulated push wake drains inbox into the same post ingest path', (
    tester,
  ) async {
    final network = FakeP2PNetwork();
    final aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    final bobService = FakeP2PService(peerId: 'peer-bob', network: network);
    final aliceContacts = InMemoryContactRepository()
      ..addTestContact(_contact('peer-bob', 'Bob'));
    final bobContacts = InMemoryContactRepository()
      ..addTestContact(_contact('peer-alice', 'Alice'));
    final bobPosts = InMemoryPostRepository();
    final alicePosts = InMemoryPostRepository();
    final bobRouter = IncomingMessageRouter(p2pService: bobService)..start();
    final bobListener = PostListener(
      postCreateStream: bobRouter.postCreateStream,
      postRepo: bobPosts,
      contactRepo: bobContacts,
    )..start();
    final pendingTargetStore = PendingPostTargetStore();
    final appShellController = AppShellController();
    final coordinator = PostNotificationOpenCoordinator(
      pendingTargetStore: pendingTargetStore,
      postRepository: bobPosts,
      appShellController: appShellController,
      revealPostsSurface: () {},
      waitBudget: const Duration(milliseconds: 20),
      expiryBudget: const Duration(seconds: 1),
    );
    addTearDown(() {
      coordinator.dispose();
      bobListener.dispose();
      bobRouter.dispose();
      alicePosts.dispose();
      bobPosts.dispose();
    });

    bobService.setOnline(false);
    final (_, post) = await sendPost(
      p2pService: aliceService,
      postRepo: alicePosts,
      contactRepo: aliceContacts,
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      text: 'Wake me up',
      audience: PostAudience.allFriends(),
    );
    final sentPost = post!;

    expect(network.inboxCount('peer-bob'), 1);
    expect((await bobPosts.loadFeed()), isEmpty);

    bobService.setOnline(true);
    await routeRemoteNotificationOpen(
      data: <String, dynamic>{'type': 'post_create', 'post_id': sentPost.id},
      onRouteTarget: (routeTarget) => coordinator.handleRouteTarget(
        routeTarget: routeTarget,
        drainOfflineInbox: bobService.drainOfflineInbox,
      ),
      onMissingRouteTarget: bobService.drainOfflineInbox,
    );
    await tester.pump(const Duration(milliseconds: 60));

    final feed = await bobPosts.loadFeed();
    expect(feed, hasLength(1));
    expect(feed.single.id, sentPost.id);
    expect(appShellController.activeTab, AppShellTab.posts);
    expect(pendingTargetStore.target?.postId, sentPost.id);
  });
}
