import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
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
          peerId: 'peer-cara',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Cara',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    contactRepository = FakeContactRepository()
      ..seed([postPinContact('peer-bob', 'Bob')]);
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    p2pService = FakeP2PService(peerId: 'peer-cara', network: FakeP2PNetwork());
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
    'renders pinned section, expands it, and dismisses locally without removing the feed card',
    (tester) async {
      await postRepository.savePost(
        postPinBasePost(text: 'Need a ladder', keepAvailable: true),
      );
      await postRepository.savePostPinState(
        const PostPinStateModel(
          postId: 'post-1',
          eventId: 'evt-pin-1',
          pinEventId: 'pin-evt-1',
          senderPeerId: 'peer-bob',
          state: 'active',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          createdAt: '2026-03-15T11:20:00.000Z',
        ),
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Pinned posts'), findsOneWidget);
      expect(find.text('Need a ladder'), findsOneWidget);

      await tester.tap(find.text('Pinned posts'));
      await tester.pump();

      expect(find.byType(UserAvatar), findsNWidgets(3));
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Message Bob'), findsNothing);
      expect(find.text('Need a ladder'), findsNWidgets(2));

      await tester.tap(find.text('Dismiss'));
      await tester.pump();

      expect(find.text('Pinned posts'), findsNothing);
      expect(find.text('Need a ladder'), findsOneWidget);
    },
  );

  testWidgets(
    'removes a recipient pinned section when the author unpins remotely',
    (tester) async {
      await postRepository.savePost(
        postPinBasePost(text: 'Need a ladder', keepAvailable: true),
      );
      await postRepository.savePostPinState(
        const PostPinStateModel(
          postId: 'post-1',
          eventId: 'evt-pin-1',
          pinEventId: 'pin-evt-1',
          senderPeerId: 'peer-bob',
          state: 'active',
          effectiveAt: '2026-03-15T11:20:00.000Z',
          pinnedAt: '2026-03-15T11:20:00.000Z',
          createdAt: '2026-03-15T11:20:00.000Z',
        ),
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Pinned posts'), findsOneWidget);
      expect(find.text('Need a ladder'), findsOneWidget);

      await postRepository.savePost(
        postPinBasePost(text: 'Need a ladder', keepAvailable: false),
      );
      await postRepository.savePostPinState(
        const PostPinStateModel(
          postId: 'post-1',
          eventId: 'evt-pin-remove-1',
          pinEventId: 'pin-remove-1',
          senderPeerId: 'peer-bob',
          state: 'removed',
          effectiveAt: '2026-03-15T11:25:00.000Z',
          removedAt: '2026-03-15T11:25:00.000Z',
          reason: 'removed',
          createdAt: '2026-03-15T11:25:00.000Z',
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Pinned posts'), findsNothing);
      expect(find.text('Need a ladder'), findsOneWidget);
      expect(find.byType(UserAvatar), findsOneWidget);
    },
  );
}
