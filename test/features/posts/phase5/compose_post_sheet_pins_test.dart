import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
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
    p2pService = FakeP2PService(peerId: 'peer-bob', network: FakeP2PNetwork());
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    p2pService.dispose();
  });

  Widget buildWidget() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  testWidgets('shows the active-pins compose banner for authored active pins', (
    tester,
  ) async {
    await postRepository.savePost(
      postPinBasePost(
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        keepAvailable: true,
      ),
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

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('You already have 1 active pinned post'), findsOneWidget);
    expect(find.text('Manage'), findsOneWidget);
  });
}
