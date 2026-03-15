import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_route_target.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool blocked = false,
  bool archived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
    isArchived: archived,
  );
}

void main() {
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late InMemoryPostRepository postRepository;
  late PendingPostTargetStore pendingTargetStore;
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
    pendingTargetStore = PendingPostTargetStore();
    p2pService = FakeP2PService(peerId: 'peer-self', network: FakeP2PNetwork());
  });

  tearDown(() {
    postRepository.dispose();
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
      ),
    );
  }

  testWidgets('shows the caught-up empty state', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text("You're all caught up"), findsWidgets);
    expect(find.text('Create your first post'), findsOneWidget);
  });

  testWidgets('pick-people only lists active unblocked contacts', (
    tester,
  ) async {
    contactRepository.seed([
      _contact('peer-bob', 'Bob'),
      _contact('peer-cara', 'Cara', blocked: true),
      _contact('peer-dan', 'Dan', archived: true),
    ]);

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.text('Share something with your friends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Pick People'));
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsNothing);
    expect(find.text('Dan'), findsNothing);
  });

  testWidgets('focuses a pending target after the post is observed locally', (
    tester,
  ) async {
    pendingTargetStore.setTarget(const PostRouteTarget(postId: 'post-1'));
    await postRepository.savePost(_post(id: 'post-1', text: 'Focus me'));

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('Focus me'), findsOneWidget);
    expect(find.text('Finishing catch-up...'), findsNothing);
    expect(pendingTargetStore.target, isNull);
  });

  testWidgets('renders the pending-target fallback state supplied by the store', (
    tester,
  ) async {
    pendingTargetStore.setTarget(const PostRouteTarget(postId: 'missing-post'));
    pendingTargetStore.showStatus('Finishing catch-up...');

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    expect(find.text('Finishing catch-up...'), findsOneWidget);
    expect(pendingTargetStore.target?.postId, 'missing-post');
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
