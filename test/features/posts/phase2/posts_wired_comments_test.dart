import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

void main() {
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late PendingPostTargetStore pendingTargetStore;
  late FakeP2PNetwork network;
  late FakeP2PService p2pService;

  setUp(() {
    identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-self',
          publicKey: 'pk-self',
          privateKey: 'sk-self',
          mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
          username: 'Alice',
          createdAt: '2026-03-15T10:00:00.000Z',
          updatedAt: '2026-03-15T10:00:00.000Z',
        ),
      );
    contactRepository = FakeContactRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    pendingTargetStore = PendingPostTargetStore();
    network = FakeP2PNetwork();
    p2pService = FakeP2PService(peerId: 'peer-self', network: network);
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
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

  testWidgets('opens persisted comments from a post card', (tester) async {
    await postRepository.savePost(_post(id: 'post-1', text: 'Need a ladder'));
    await postRepository.saveComment(
      const PostCommentModel(
        id: 'comment-1',
        eventId: 'evt-comment-1',
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        authorUsername: 'Bob',
        body: 'I can lend one.',
        commentedAt: '2026-03-15T11:00:00.000Z',
      ),
    );

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1 comments'), findsOneWidget);
    expect(find.text('I can lend one.'), findsOneWidget);
  });

  testWidgets('submits comments from the sheet and extends the post expiry', (
    tester,
  ) async {
    contactRepository.seed([_contact('peer-bob', 'Bob')]);
    FakeP2PService(peerId: 'peer-bob', network: network);
    await postRepository.savePost(_post(id: 'post-1', text: 'Need a ladder'));
    await postRepository.saveRecipientDelivery(
      _delivery(postId: 'post-1', recipientPeerId: 'peer-self'),
    );

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.mode_comment_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'I can lend one.');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final comments = await postRepository.loadComments('post-1');
    expect(comments, hasLength(1));
    expect(comments.single.body, 'I can lend one.');
    expect(
      (await postRepository.getPost('post-1'))?.lastEngagementAt,
      isNotNull,
    );
  });
}

PostModel _post({required String id, required String text}) {
  return PostModel(
    id: id,
    eventId: 'evt-$id',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: text,
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
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

PostRecipientDelivery _delivery({
  required String postId,
  required String recipientPeerId,
}) {
  return PostRecipientDelivery(
    postId: postId,
    recipientPeerId: recipientPeerId,
    deliveryStatus: 'delivered',
    lastAttemptAt: '2026-03-15T10:15:31.000Z',
    deliveryPath: 'direct',
    createdAt: '2026-03-15T10:15:31.000Z',
    updatedAt: '2026-03-15T10:15:31.000Z',
  );
}
