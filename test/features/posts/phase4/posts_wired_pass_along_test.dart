import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
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
  late Directory documentsDir;

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
    documentsDir = Directory.systemTemp.createTempSync(
      'posts-wired-pass-along-avatars-',
    );
    final avatarsDir = Directory('${documentsDir.path}/media/avatars')
      ..createSync(recursive: true);
    File('${avatarsDir.path}/peer-alice.jpg').writeAsBytesSync(
      _testAvatarBytes(),
      flush: true,
    );
    UserAvatar.setDocumentsDir(documentsDir.path);
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    aliceService.dispose();
    caraService.dispose();
    documentsDir.deleteSync(recursive: true);
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

    final events = await _captureFlowEvents(() async {
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
      expect(find.text('Sending…'), findsOneWidget);
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 80; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final localPasses = await postRepository.loadPostPasses('post-1');
          if (localPasses.isNotEmpty) {
            return;
          }
        }
      });
      await tester.pump();
    });
    expect(await postRepository.loadPostPasses('post-1'), hasLength(1));
    expect(
      _flowEventDetails(events, 'POST_PASS_AVATAR_PATH_RESOLVED'),
      isNotEmpty,
    );
    expect(
      _flowEventDetails(events, 'POST_PASS_AVATAR_PATH_MISSING'),
      isNotEmpty,
    );
  });

  testWidgets(
    'starts pass delivery from the picker',
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
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.repeat));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Cara'));
      await tester.pump();
      await tester.tap(find.text('Send pass'));
      await tester.pump();

      expect(find.text('Sending…'), findsOneWidget);
    },
  );

}

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() body,
) async {
  final originalDebugPrint = debugPrint;
  final events = <Map<String, dynamic>>[];
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || !message.startsWith('[FLOW] ')) {
      return;
    }
    final decoded = jsonDecode(message.substring('[FLOW] '.length));
    if (decoded is Map<String, dynamic>) {
      events.add(decoded);
    }
  };
  try {
    await body();
  } finally {
    debugPrint = originalDebugPrint;
  }
  return events;
}

List<Map<String, dynamic>> _flowEventDetails(
  List<Map<String, dynamic>> events,
  String eventName,
) {
  return events
      .where((event) => event['event'] == eventName)
      .map((event) => event['details'] as Map<String, dynamic>)
      .toList(growable: false);
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

Uint8List _testAvatarBytes() {
  return Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x62,
    0x00,
    0x00,
    0x00,
    0x02,
    0x00,
    0x01,
    0xE5,
    0x27,
    0xDE,
    0xFC,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}
