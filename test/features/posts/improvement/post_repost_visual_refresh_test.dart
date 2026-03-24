import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late PendingPostTargetStore pendingTargetStore;
  late FakeP2PService p2pService;

  setUp(() {
    identityRepository = FakeIdentityRepository();
    contactRepository = FakeContactRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    p2pService = FakeP2PService(peerId: 'peer-self', network: FakeP2PNetwork());
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

  testWidgets(
    'refreshes the original author card to the summed repost total after later repost notifications arrive',
    (tester) async {
      identityRepository.seed(_identity('peer-bob', 'Bob'));
      contactRepository.seed([
        _contact('peer-alice', 'Alice'),
        _contact('peer-james', 'James'),
      ]);
      await postRepository.savePost(
        _post(
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      await postRepository.savePostPass(
        _pass('pass-1', 'peer-alice', 'Alice', recipientCount: 2),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color,
        const Color(0xFF1DB954),
      );

      await postRepository.savePostPass(
        _pass('pass-2', 'peer-james', 'James', recipientCount: 3),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('5'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color,
        const Color(0xFF1DB954),
      );
    },
  );

  testWidgets(
    'keeps carried-baseline repost totals visible on passive receiver cards when later repost events arrive',
    (tester) async {
      identityRepository.seed(_identity('peer-cara', 'Cara'));
      contactRepository.seed([
        _contact('peer-bob', 'Bob'),
        _contact('peer-james', 'James'),
        _contact('peer-maria', 'Maria'),
      ]);
      await postRepository.savePost(
        _post(
          senderPeerId: 'peer-james',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );
      await postRepository.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-1',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await postRepository.savePostPass(
        _pass('pass-1', 'peer-james', 'James', recipientCount: 1),
      );
      await postRepository.seedRepostSharedToBaseline(
        postId: 'post-1',
        sharedToCountBaseline: 3,
        existingLocalSharedToCount: 1,
        currentPassRecipientCount: 1,
        createdAt: '2026-03-15T11:15:00.000Z',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      expect(find.text('James passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color?.a,
        closeTo(0.35, 0.01),
      );

      await postRepository.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-2',
          passerPeerId: 'peer-maria',
          passerUsername: 'Maria',
          passCreatedAt: '2026-03-15T11:25:00.000Z',
        ),
      );
      await postRepository.savePostPass(
        _pass('pass-2', 'peer-maria', 'Maria', recipientCount: 2),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Maria passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('6'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color?.a,
        closeTo(0.35, 0.01),
      );
    },
  );

  testWidgets(
    'keeps legacy fallback shared-to totals visible and neutrally styled after repository-driven refresh',
    (tester) async {
      identityRepository.seed(_identity('peer-cara', 'Cara'));
      contactRepository.seed([
        _contact('peer-bob', 'Bob'),
        _contact('peer-james', 'James'),
        _contact('peer-maria', 'Maria'),
      ]);
      await postRepository.savePost(
        _post(
          senderPeerId: 'peer-james',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );
      await postRepository.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-1',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await postRepository.savePostPass(_pass('pass-1', 'peer-james', 'James'));
      await postRepository.seedRepostSharedToBaseline(
        postId: 'post-1',
        sharedToCountBaseline: 3,
        existingLocalSharedToCount: 1,
        currentPassRecipientCount: 1,
        createdAt: '2026-03-15T11:15:00.000Z',
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();
      await tester.pump();

      expect(find.text('James passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('4'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color?.a,
        closeTo(0.35, 0.01),
      );

      await postRepository.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-2',
          passerPeerId: 'peer-maria',
          passerUsername: 'Maria',
          passCreatedAt: '2026-03-15T11:25:00.000Z',
        ),
      );
      await postRepository.savePostPass(
        _pass('pass-2', 'peer-maria', 'Maria', recipientCount: 2),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Maria passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      expect(find.text('6'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.repeat)).color?.a,
        closeTo(0.35, 0.01),
      );
    },
  );
}

IdentityModel _identity(String peerId, String username) {
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: username,
    createdAt: '2026-03-15T10:00:00.000Z',
    updatedAt: '2026-03-15T10:00:00.000Z',
  );
}

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

PostModel _post({
  String senderPeerId = 'peer-bob',
  String authorPeerId = 'peer-bob',
  String authorUsername = 'Bob',
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: senderPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}

PostPassModel _pass(
  String passId,
  String passerPeerId,
  String passerUsername, {
  int? recipientCount,
}) {
  return PostPassModel(
    passId: passId,
    eventId: 'evt-$passId',
    postId: 'post-1',
    senderPeerId: passerPeerId,
    passerPeerId: passerPeerId,
    passerUsername: passerUsername,
    passedAt: '2026-03-15T11:15:00.000Z',
    createdAt: '2026-03-15T11:15:00.000Z',
    recipientCount: recipientCount,
  );
}
