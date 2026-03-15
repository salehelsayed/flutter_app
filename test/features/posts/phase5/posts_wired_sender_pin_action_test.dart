import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'support/post_pin_fixtures.dart';

void main() {
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late PendingPostTargetStore pendingTargetStore;
  late FakeP2PService p2pService;

  setUp(() {
    identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-bob',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Bob',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    contactRepository = FakeContactRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    final network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-bob', network: network);
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    p2pService.dispose();
  });

  Widget buildWidget() {
    return MaterialApp(
      home: PostsWired(
        identityRepo: identityRepository,
        contactRepo: contactRepository,
        postRepo: postRepository,
        p2pService: p2pService,
        activeTab: 'posts',
        onSwitchView: (_) {},
        pendingTargetStore: pendingTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      ),
    );
  }

  testWidgets(
    'shows author pin action and adds the post to the pinned section',
    (tester) async {
      await postRepository.savePost(
        postPinBasePost(authorPeerId: 'peer-bob', authorUsername: 'Bob'),
      );
      await postRepository.saveRecipientDelivery(
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

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();

      expect(find.text('Pinned posts'), findsOneWidget);
    },
  );

  testWidgets(
    'supports repeated author pin and remove cycles in the wired screen',
    (tester) async {
      await postRepository.savePost(
        postPinBasePost(authorPeerId: 'peer-bob', authorUsername: 'Bob'),
      );
      await postRepository.saveRecipientDelivery(
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

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();

      expect(find.text('Pinned posts'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsNothing);

      await tester.tap(find.text('Pinned posts'));
      await tester.pump();
      await tester.tap(find.text('Remove'));
      await tester.pump();

      expect(find.text('Pinned posts'), findsNothing);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect((await postRepository.getPost('post-1'))!.keepAvailable, isFalse);
      expect(
        (await postRepository.getPostPinState('post-1'))!.state,
        'removed',
      );

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();

      expect(find.text('Pinned posts'), findsOneWidget);
      expect((await postRepository.getPost('post-1'))!.keepAvailable, isTrue);
      expect((await postRepository.getPostPinState('post-1'))!.state, 'active');

      await tester.tap(find.text('Pinned posts'));
      await tester.pump();
      await tester.tap(find.text('Remove'));
      await tester.pump();

      final finalPinState = await postRepository.getPostPinState('post-1');
      expect(find.text('Pinned posts'), findsNothing);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect((await postRepository.getPost('post-1'))!.keepAvailable, isFalse);
      expect(finalPinState, isNotNull);
      expect(finalPinState, isA<PostPinStateModel>());
      expect(finalPinState!.state, 'removed');
    },
  );
}
