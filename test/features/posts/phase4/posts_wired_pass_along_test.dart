import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/presentation/screens/posts_wired.dart';

import '../../../core/bridge/fake_bridge.dart';
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
  late FakeP2PService aliceService;
  late FakeP2PService caraService;
  late PassthroughCryptoBridge bridge;

  setUp(() {
    identityRepository = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-alice',
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
    aliceService = FakeP2PService(peerId: 'peer-alice', network: network);
    caraService = FakeP2PService(peerId: 'peer-cara', network: network);
    bridge = PassthroughCryptoBridge();
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    aliceService.dispose();
    caraService.dispose();
  });

  Widget buildWidget() {
    return MaterialApp(
      home: PostsWired(
        identityRepo: identityRepository,
        contactRepo: contactRepository,
        postRepo: postRepository,
        p2pService: aliceService,
        bridge: bridge,
        activeTab: 'posts',
        onSwitchView: (_) {},
        pendingTargetStore: pendingTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      ),
    );
  }

  testWidgets('opens an eligible-recipient picker and sends a pass envelope', (
    tester,
  ) async {
    contactRepository.seed([
      _contact('peer-bob', 'Bob', mlKemPublicKey: 'mlkem-peer-bob'),
      _contact('peer-cara', 'Cara', mlKemPublicKey: 'mlkem-peer-cara'),
      _contact(
        'peer-dan',
        'Dan',
        blocked: true,
        mlKemPublicKey: 'mlkem-peer-dan',
      ),
      _contact(
        'peer-eve',
        'Eve',
        archived: true,
        mlKemPublicKey: 'mlkem-peer-eve',
      ),
    ]);
    await postRepository.savePost(_post());

    final receivedByCara = caraService.messageStream.first;

    await tester.pumpWidget(buildWidget());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.widgetWithText(CheckboxListTile, 'Cara'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Bob'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'Dan'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'Eve'), findsNothing);

    await tester.tap(find.text('Cara'));
    await tester.pump();
    await tester.tap(find.text('Send pass'));
    await tester.pump();

    final message = await receivedByCara.timeout(const Duration(seconds: 1));
    final json = jsonDecode(message.content) as Map<String, dynamic>;
    final payload =
        jsonDecode(
              (json['encrypted'] as Map<String, dynamic>)['ciphertext']
                  as String,
            )
            as Map<String, dynamic>;

    expect(json['type'], 'post_pass');
    expect(json['version'], '2');
    expect(payload['post_id'], 'post-1');
    expect(payload['passer_peer_id'], 'peer-alice');
  });

  testWidgets(
    'closes the pass sheet after local persistence and refreshes sender-visible repost state while delivery is still in flight',
    (tester) async {
      contactRepository.seed([
        _contact('peer-bob', 'Bob', mlKemPublicKey: 'mlkem-peer-bob'),
        _contact('peer-cara', 'Cara', mlKemPublicKey: 'mlkem-peer-cara'),
      ]);
      await postRepository.savePost(
        _post(
          senderPeerId: 'peer-alice',
          authorPeerId: 'peer-alice',
          authorUsername: 'Alice',
        ),
      );
      network.deliveryDelay = const Duration(seconds: 1);

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cara'));
      await tester.pump();
      await tester.tap(find.text('Send pass'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final localPasses = await postRepository.loadPostPasses('post-1');
      expect(localPasses, hasLength(1));
      final deliveries = await postRepository.getPostPassRecipientDeliveries(
        localPasses.single.passId,
      );

      expect(find.text('Pass along'), findsNothing);
      expect(find.text('Sending…'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('post-share-count')),
        findsOneWidget,
      );
      final repeatIcon = tester.widget<Icon>(find.byIcon(Icons.repeat));
      expect(repeatIcon.color, const Color(0xFF1DB954));
      expect(find.text('1'), findsOneWidget);
      expect(deliveries.map((delivery) => delivery.recipientPeerId), <String>[
        'peer-cara',
      ]);
      expect(
        deliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      expect(localPasses.single.deliveryStatus, 'sending');
      expect(await postRepository.loadRetryableFollowOnOutboxJobs(), isEmpty);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}

ContactModel _contact(
  String peerId,
  String username, {
  bool blocked = false,
  bool archived = false,
  String? mlKemPublicKey,
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
    mlKemPublicKey: mlKemPublicKey,
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
    text: 'Lost dog near Neckar bridge.',
    audience: PostAudience.peopleNearby(radiusM: 2000),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}
