/// Simulator UI smoke test for the user-reported invariant:
/// when user-B deletes a group from Orbit (swipe-left -> Delete), only that
/// group is removed. B's friends list and 1:1 chat threads with each
/// friend must remain intact.
///
/// Runs the full OrbitWired widget on iOS simulator so the swipe gesture,
/// confirmation dialog, and the use-case wiring are all exercised against
/// a real Flutter binding. Mirrors the host widget test
/// (`test/features/orbit/.../orbit_wired_test.dart`) but uses
/// IntegrationTestWidgetsFlutterBinding so it runs on device.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/secure_storage/fake_secure_key_store.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'simulator: deleting one Orbit group preserves friends and 1:1 chat threads',
    (tester) async {
      // -- arrange: full OrbitWired stack with in-memory fakes.
      final identityRepo = FakeIdentityRepository();
      final contactRepo = FakeContactRepository();
      final contactRequestRepo = FakeContactRequestRepository();
      final messageRepo = InMemoryMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();
      final postsPrivacySettingsRepo = InMemoryPostsPrivacySettingsRepository();
      addTearDown(postsPrivacySettingsRepo.dispose);

      final bridge = FakeBridge();
      final p2pService = FakeP2PService();
      final secureKeyStore = FakeSecureKeyStore();
      final mediaFileManager = FakeMediaFileManager();
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

      // path_provider may not work cleanly in the integration_test harness
      // depending on plugin init order; mock it defensively.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getApplicationDocumentsDirectory') {
                return '/tmp/test_docs_simulator';
              }
              return null;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      });

      final identity = IdentityModel(
        peerId: 'bob-peer',
        publicKey: 'pk-bob',
        privateKey: 'sk-bob',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-bob',
        username: 'Bob',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      identityRepo.seed(identity);

      final friendA = ContactModel(
        peerId: 'alice-peer',
        publicKey: 'pk-alice',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-alice',
        scannedAt: '2026-04-01T00:00:00.000Z',
        mlKemPublicKey: 'mlkem-alice',
      );
      final friendC = ContactModel(
        peerId: 'charlie-peer',
        publicKey: 'pk-charlie',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Charlie',
        signature: 'sig-charlie',
        scannedAt: '2026-04-01T00:00:00.000Z',
        mlKemPublicKey: 'mlkem-charlie',
      );
      contactRepo.seed([friendA, friendC]);

      // 1:1 chat history with both friends — the invariant we are guarding.
      const aliceDmIds = ['sim-dm-a-1', 'sim-dm-a-2'];
      const charlieDmIds = ['sim-dm-c-1', 'sim-dm-c-2'];
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'sim-dm-a-1',
          contactPeerId: friendA.peerId,
          senderPeerId: identity.peerId,
          text: 'hey alice',
          timestamp: '2026-04-10T09:00:00.000Z',
          status: 'sent',
          isIncoming: false,
          createdAt: '2026-04-10T09:00:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'sim-dm-a-2',
          contactPeerId: friendA.peerId,
          senderPeerId: friendA.peerId,
          text: 'hi bob',
          timestamp: '2026-04-10T09:01:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-04-10T09:01:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'sim-dm-c-1',
          contactPeerId: friendC.peerId,
          senderPeerId: identity.peerId,
          text: 'yo charlie',
          timestamp: '2026-04-10T10:00:00.000Z',
          status: 'sent',
          isIncoming: false,
          createdAt: '2026-04-10T10:00:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'sim-dm-c-2',
          contactPeerId: friendC.peerId,
          senderPeerId: friendC.peerId,
          text: 'sup',
          timestamp: '2026-04-10T10:01:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-04-10T10:01:00.000Z',
        ),
      );

      final now = DateTime.utc(2026, 4, 11, 9);
      await groupRepo.saveGroup(
        GroupModel(
          id: 'sim-game-night',
          name: 'Game Night',
          type: GroupType.chat,
          topicName: 'topic-sim-game-night',
          createdAt: now,
          createdBy: friendA.peerId,
          myRole: GroupRole.member,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'sim-gm-1',
          groupId: 'sim-game-night',
          senderPeerId: friendA.peerId,
          senderUsername: friendA.username,
          text: 'who is in?',
          timestamp: now,
          isIncoming: true,
          createdAt: now,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'sim-gm-2',
          groupId: 'sim-game-night',
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          text: 'me',
          timestamp: now.add(const Duration(seconds: 30)),
          isIncoming: false,
          createdAt: now.add(const Duration(seconds: 30)),
        ),
      );

      final crListener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnPeerId: () => '',
      );
      final cmListener = ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      final gmListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        bridge: bridge,
      );

      final orbit = OrbitWired(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: gmListener,
        postsPrivacySettingsRepository: postsPrivacySettingsRepo,
      );

      // Suppress noisy overflow paint exceptions that appear on tiny
      // simulator surfaces; not relevant to the swipe-delete invariant.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final s = details.toString();
        if (s.contains('overflowed') ||
            s.contains('Unable to load asset') ||
            s.contains('SvgPicture')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: orbit,
        ),
      );

      // Let the orbit data stream populate (identity, contacts, groups).
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // -- sanity: orbit shows the friends and the group.
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Charlie'), findsWidgets);
      expect(find.text('Game Night'), findsOneWidget);

      // Snapshot 1:1 chat counts BEFORE deletion.
      final aliceMessagesBefore =
          await messageRepo.getMessagesForContact(friendA.peerId);
      final charlieMessagesBefore =
          await messageRepo.getMessagesForContact(friendC.peerId);
      expect(aliceMessagesBefore.map((m) => m.id).toList(), aliceDmIds);
      expect(charlieMessagesBefore.map((m) => m.id).toList(), charlieDmIds);

      // -- act: swipe-left on the group row, tap Delete, confirm dialog.
      final groupCenter = tester.getCenter(find.text('Game Night'));
      await tester.flingFrom(groupCenter, const Offset(-350, 0), 1000);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Delete').first);
      await tester.pump();
      // Confirmation dialog appears; tap its Delete action.
      await tester.tap(find.text('Delete').last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // -- assert UI: group is gone, friends still visible.
      expect(find.text('Game Night'), findsNothing);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Charlie'), findsWidgets);

      // -- assert state: contacts intact.
      final contactsAfter = await contactRepo.getActiveContacts();
      expect(contactsAfter.map((c) => c.peerId).toSet(),
          {friendA.peerId, friendC.peerId});

      // -- assert state: 1:1 chat threads with each friend are intact.
      final aliceMessagesAfter =
          await messageRepo.getMessagesForContact(friendA.peerId);
      expect(aliceMessagesAfter.map((m) => m.id).toList(), aliceDmIds,
          reason: 'group delete must not touch 1:1 messages with Alice');
      final charlieMessagesAfter =
          await messageRepo.getMessagesForContact(friendC.peerId);
      expect(charlieMessagesAfter.map((m) => m.id).toList(), charlieDmIds,
          reason: 'group delete must not touch 1:1 messages with Charlie');

      // -- assert state: group + group messages purged.
      expect(await groupRepo.getGroup('sim-game-night'), isNull);
      expect(await groupMsgRepo.getMessage('sim-gm-1'), isNull);
      expect(await groupMsgRepo.getMessage('sim-gm-2'), isNull);

      // -- assert wire: a single leave broadcast was issued.
      expect(
        bridge.commandLog.where((command) => command == 'group:leave'),
        hasLength(1),
      );

      // -- act+assert: open each 1:1 chat through the actual UI and confirm
      //    every previously-seeded message is rendered. This is the user's
      //    real-world check — repos can be intact while the UI fails to
      //    re-bind, so we drive the navigation, not just the assertions.
      Future<void> openFriendThreadAndExpectMessages({
        required String friendName,
        required List<String> expectedMessageTexts,
      }) async {
        // Tap the friend's row in Orbit. find.text(name) may match more than
        // one widget (avatar label + row text), so tap the first hit.
        await tester.tap(find.text(friendName).first);
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        for (final text in expectedMessageTexts) {
          expect(
            find.text(text),
            findsWidgets,
            reason:
                '$friendName conversation must still render "$text" after '
                'the unrelated group was deleted',
          );
        }

        // Pop the conversation route programmatically (no reliance on a
        // back-button finder that may move with redesigns).
        final navigator = Navigator.of(
          tester.element(find.byType(Navigator).last),
        );
        navigator.pop();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await openFriendThreadAndExpectMessages(
        friendName: 'Alice',
        expectedMessageTexts: ['hey alice', 'hi bob'],
      );
      await openFriendThreadAndExpectMessages(
        friendName: 'Charlie',
        expectedMessageTexts: ['yo charlie', 'sup'],
      );

      // After both round-trips, Orbit should still show both friends.
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Charlie'), findsWidgets);
    },
  );
}
