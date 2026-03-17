import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

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

  testWidgets('shows share counts on the original author card only', (
    tester,
  ) async {
    identityRepository.seed(_identity('peer-bob', 'Bob'));
    contactRepository.seed([_contact('peer-alice', 'Alice')]);
    await postRepository.savePost(
      _post(authorPeerId: 'peer-bob', authorUsername: 'Bob'),
    );
    await postRepository.savePostPass(_pass('pass-1', 'peer-alice', 'Alice'));
    await postRepository.savePostPass(_pass('pass-2', 'peer-james', 'James'));

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('post-share-count')),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('keeps share counts hidden on receiver cards', (tester) async {
    identityRepository.seed(_identity('peer-cara', 'Cara'));
    contactRepository.seed([_contact('peer-bob', 'Bob')]);
    await postRepository.savePost(
      _post(authorPeerId: 'peer-bob', authorUsername: 'Bob'),
    );
    await postRepository.savePostPass(_pass('pass-1', 'peer-alice', 'Alice'));
    await postRepository.savePostPass(_pass('pass-2', 'peer-james', 'James'));

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('post-share-count')),
      findsNothing,
    );
  });

  testWidgets(
    'keeps receiver resurfacing attribution visible while leaving share counts hidden',
    (tester) async {
      identityRepository.seed(_identity('peer-cara', 'Cara'));
      contactRepository.seed([
        _contact('peer-bob', 'Bob'),
        _contact('peer-james', 'James'),
      ]);
      await postRepository.savePost(
        _post(authorPeerId: 'peer-bob', authorUsername: 'Bob'),
      );
      await postRepository.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.direct,
          passId: 'pass-2',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await postRepository.savePostPass(_pass('pass-1', 'peer-alice', 'Alice'));
      await postRepository.savePostPass(_pass('pass-2', 'peer-james', 'James'));

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('James passed this along'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsNothing,
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
  required String authorPeerId,
  required String authorUsername,
}) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: authorPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}

PostPassModel _pass(String passId, String passerPeerId, String passerUsername) {
  return PostPassModel(
    passId: passId,
    eventId: 'evt-$passId',
    postId: 'post-1',
    senderPeerId: passerPeerId,
    passerPeerId: passerPeerId,
    passerUsername: passerUsername,
    passedAt: '2026-03-15T11:15:00.000Z',
    createdAt: '2026-03-15T11:15:00.000Z',
  );
}
