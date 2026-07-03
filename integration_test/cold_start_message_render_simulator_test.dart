/// Simulator UI smoke test for the user-reported bug:
/// after closing and re-opening the application, opening any old message
/// thread shows empty message bubbles (no body text).
///
/// Drives the actual OrbitWired widget on iOS simulator across two
/// "sessions". Pre-seeds 1:1 and group messages with known plaintext bodies
/// in the in-memory repos (the repos themselves persist across both
/// sessions, mirroring what SQLite would do across a real cold restart),
/// then:
///   1. Session 1: pumps OrbitWired, opens both threads, asserts bodies render.
///   2. Tears the widget tree down.
///   3. Session 2: pumps a FRESH OrbitWired with the SAME repos, opens both
///      threads again, asserts bodies still render (this is the regression
///      the user is hitting).
///
/// If session 2 shows empty bubbles, that is the reproduction — the bug is
/// in the render layer's reload path. If session 2 also passes, the
/// production bug is upstream of the screen render and most likely lives in
/// one of:
///   - ChatMessageListener.handleIncomingChatMessage decrypt/store path:
///     v2 envelope decrypt failed (e.g. ML-KEM secret key not loaded yet)
///     and `text` was persisted as an empty string instead of the plaintext.
///   - GroupMessageListener equivalent for group ciphertext.
///   - Cold-start race: messages received during the previous session
///     while identity/secrets were still loading.
/// In that case, extend this test by routing an *encrypted* chat/group
/// envelope through the real listener path between sessions 1 and 2, so the
/// receive-time decrypt is exercised on a fresh, cold-loaded identity.

library;

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
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '_support/fake_secure_key_store.dart';
import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/fake_media_file_manager.dart';
import '../test/shared/fakes/in_memory_feed_cleared_repository.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';
import '../test/shared/fakes/in_memory_message_repository.dart';
import '../test/shared/fakes/in_memory_posts_privacy_settings_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'simulator: after a cold restart, opening previously-received 1:1 and '
    'group threads still renders message bodies (not empty bubbles)',
    (tester) async {
      // -- arrange: persistent state (repos survive the simulated restart).
      final identityRepo = FakeIdentityRepository();
      final contactRepo = FakeContactRepository();
      final messageRepo = InMemoryMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      // path_provider mock for the integration_test harness.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getApplicationDocumentsDirectory') {
                return '/tmp/test_docs_cold_start_render_sim';
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

      final bob = IdentityModel(
        peerId: 'bob-peer',
        publicKey: 'pk-bob',
        privateKey: 'sk-bob',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-bob',
        username: 'Bob',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      identityRepo.seed(bob);

      const alice = ContactModel(
        peerId: 'alice-peer',
        publicKey: 'pk-alice',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-alice',
        scannedAt: '2026-04-01T00:00:00.000Z',
        mlKemPublicKey: 'mlkem-alice',
      );
      contactRepo.seed([alice]);

      // 1:1 history Bob received from Alice — these are the "old messages"
      // the user says go empty after relaunch.
      const dmIncomingText = 'message-from-alice-before-restart';
      const dmOutgoingText = 'reply-from-bob-before-restart';
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'cs-dm-1',
          contactPeerId: alice.peerId,
          senderPeerId: alice.peerId,
          text: dmIncomingText,
          timestamp: '2026-05-01T09:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-05-01T09:00:00.000Z',
        ),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'cs-dm-2',
          contactPeerId: alice.peerId,
          senderPeerId: bob.peerId,
          text: dmOutgoingText,
          timestamp: '2026-05-01T09:01:00.000Z',
          status: 'sent',
          isIncoming: false,
          createdAt: '2026-05-01T09:01:00.000Z',
        ),
      );

      // Group Bob is already a member of, with prior received messages.
      final groupCreatedAt = DateTime.utc(2026, 4, 30, 9);
      const groupName = 'Pre-Restart Group';
      const groupId = 'cs-grp-1';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: groupName,
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          createdAt: groupCreatedAt,
          createdBy: alice.peerId,
          myRole: GroupRole.member,
        ),
      );
      const groupIncomingText = 'group-message-from-alice-before-restart';
      const groupOutgoingText = 'group-reply-from-bob-before-restart';
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'cs-gm-1',
          groupId: groupId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: groupIncomingText,
          timestamp: groupCreatedAt.add(const Duration(minutes: 1)),
          isIncoming: true,
          createdAt: groupCreatedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'cs-gm-2',
          groupId: groupId,
          senderPeerId: bob.peerId,
          senderUsername: bob.username,
          text: groupOutgoingText,
          timestamp: groupCreatedAt.add(const Duration(minutes: 2)),
          isIncoming: false,
          createdAt: groupCreatedAt.add(const Duration(minutes: 2)),
        ),
      );

      // Suppress noisy paint exceptions on tiny simulator surfaces.
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

      // -- session 1: open the app the first time. Confirm bodies render.
      await _runOrbitSessionAndOpenThreads(
        tester: tester,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: FakeContactRequestRepository(),
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        sessionLabel: 'session-1',
        aliceContactName: alice.username,
        groupName: groupName,
        expectDmTexts: const [dmIncomingText, dmOutgoingText],
        expectGroupTexts: const [groupIncomingText, groupOutgoingText],
      );

      // -- simulate the user closing the app: dispose the entire widget
      //    tree. The repos remain (in-memory persistence stand-in for
      //    SQLite across a real process restart).
      await tester.pumpWidget(const SizedBox.shrink());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // -- session 2: cold restart. Build a FRESH OrbitWired with the SAME
      //    repos and verify the previously-received bodies still render.
      //    If they don't, this is the reproduction.
      await _runOrbitSessionAndOpenThreads(
        tester: tester,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: FakeContactRequestRepository(),
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        sessionLabel: 'session-2-cold-restart',
        aliceContactName: alice.username,
        groupName: groupName,
        expectDmTexts: const [dmIncomingText, dmOutgoingText],
        expectGroupTexts: const [groupIncomingText, groupOutgoingText],
      );
    },
  );

  // 198 F12 (SIM-PC) — the real render/gesture/route pipeline for Sculpt &
  // Summon: the overflow badge expands the arcs, an overflow chat opens, and the
  // find pill chips a group so its conversation opens.
  testWidgets(
    'simulator: 198 orbit overflow — badge expands arcs, an overflow chat '
    'opens, find chips a hidden group',
    (tester) async {
      final identityRepo = FakeIdentityRepository();
      final contactRepo = FakeContactRepository();
      final messageRepo = InMemoryMessageRepository();
      final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      final groupRepo = InMemoryGroupRepository();
      final groupMsgRepo = InMemoryGroupMessageRepository();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (methodCall) async =>
                methodCall.method == 'getApplicationDocumentsDirectory'
                    ? '/tmp/test_docs_198_orbit_sim'
                    : null,
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
      });

      identityRepo.seed(IdentityModel(
        peerId: 'me-peer',
        publicKey: 'pk-me',
        privateKey: 'sk-me',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        mlKemPublicKey: 'mlkem-me',
        username: 'Me',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // 14 friends, friend0 newest .. friend13 oldest (→ overflow). One DM each
      // sets recency; the overflow friend's body is what must render.
      final base = DateTime.utc(2026, 5, 1, 9);
      contactRepo.seed([
        for (var i = 0; i < 14; i++)
          ContactModel(
            peerId: 'f$i-peer',
            publicKey: 'pk-f$i',
            rendezvous: '/dns4/relay/tcp/443',
            username: 'friend$i',
            signature: 'sig-f$i',
            scannedAt: base.subtract(Duration(minutes: i)).toIso8601String(),
            mlKemPublicKey: 'mlkem-f$i',
          ),
      ]);
      for (var i = 0; i < 14; i++) {
        final ts = base.subtract(Duration(minutes: i)).toIso8601String();
        await messageRepo.saveMessage(ConversationMessage(
          id: 'dm-$i',
          contactPeerId: 'f$i-peer',
          senderPeerId: 'f$i-peer',
          text: 'hi from friend$i',
          timestamp: ts,
          status: 'delivered',
          isIncoming: true,
          createdAt: ts,
        ));
      }

      // A group (newest → seated on a ring, but findable regardless).
      await groupRepo.saveGroup(GroupModel(
        id: 'find-grp',
        name: 'FindMe Group',
        type: GroupType.chat,
        topicName: 'topic-find-grp',
        createdAt: base.add(const Duration(minutes: 30)),
        createdBy: 'f0-peer',
        myRole: GroupRole.member,
      ));
      await groupMsgRepo.saveMessage(GroupMessage(
        id: 'gm-1',
        groupId: 'find-grp',
        senderPeerId: 'f0-peer',
        senderUsername: 'friend0',
        text: 'group hello there',
        timestamp: base.add(const Duration(minutes: 31)),
        isIncoming: true,
        createdAt: base.add(const Duration(minutes: 31)),
      ));

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

      final bridge = FakeBridge();
      final gmListener = GroupMessageListener(
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        bridge: bridge,
      );
      final postsPrivacy = InMemoryPostsPrivacySettingsRepository();
      addTearDown(postsPrivacy.dispose);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OrbitWired(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          contactRequestRepo: FakeContactRequestRepository(),
          contactRequestListener: ContactRequestListener(
            contactRequestStream: const Stream<ChatMessage>.empty(),
            requestRepo: FakeContactRequestRepository(),
            contactRepo: contactRepo,
            bridge: bridge,
            getOwnPeerId: () => '',
          ),
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream<ChatMessage>.empty(),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          ),
          bridge: bridge,
          p2pService: FakeP2PService(),
          mediaFileManager: FakeMediaFileManager(),
          secureKeyStore: FakeSecureKeyStore(),
          imageProcessor: ImageProcessor(
            compressFile: ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
            compressVideo: ({required path, required compress, onProgress}) async => null,
          ),
          feedClearedRepository: InMemoryFeedClearedRepository(),
          groupRepository: groupRepo,
          groupMessageRepository: groupMsgRepo,
          groupMessageListener: gmListener,
          postsPrivacySettingsRepository: postsPrivacy,
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Inner-Circle default view: 15 items ⇒ 2 overflow ⇒ badge "+2".
      expect(find.byType(OverflowBadge), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      // The overflow friend is not seated until the arcs expand.
      expect(find.bySemanticsLabel('Open chat with friend13'), findsNothing);

      await tester.tap(find.byType(OverflowBadge));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.bySemanticsLabel('Open chat with friend13'), findsOneWidget);

      // Open the overflow chat — its body renders.
      await tester.tap(find.bySemanticsLabel('Open chat with friend13'));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('hi from friend13'), findsWidgets);
      Navigator.of(tester.element(find.byType(Navigator).last)).pop();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Find pill → chip a group by name → its conversation opens.
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'FindMe');
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('FindMe Group'), findsWidgets);
      await tester.tap(find.text('FindMe Group').last);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('group hello there'), findsWidgets);
    },
  );
}

/// Builds a fresh OrbitWired with the supplied (persistent) repos, pumps
/// the widget tree, opens the 1:1 thread with [aliceContactName], asserts
/// every text in [expectDmTexts] renders, pops back to orbit, opens the
/// group [groupName], asserts every text in [expectGroupTexts] renders,
/// then pops back to orbit.
///
/// [sessionLabel] is purely for readable failure messages.
Future<void> _runOrbitSessionAndOpenThreads({
  required WidgetTester tester,
  required FakeIdentityRepository identityRepo,
  required FakeContactRepository contactRepo,
  required FakeContactRequestRepository contactRequestRepo,
  required InMemoryMessageRepository messageRepo,
  required InMemoryMediaAttachmentRepository mediaAttachmentRepo,
  required InMemoryGroupRepository groupRepo,
  required InMemoryGroupMessageRepository groupMsgRepo,
  required String sessionLabel,
  required String aliceContactName,
  required String groupName,
  required List<String> expectDmTexts,
  required List<String> expectGroupTexts,
}) async {
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
  final postsPrivacySettingsRepo = InMemoryPostsPrivacySettingsRepository();

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
    feedClearedRepository: InMemoryFeedClearedRepository(),
    groupRepository: groupRepo,
    groupMessageRepository: groupMsgRepo,
    groupMessageListener: gmListener,
    postsPrivacySettingsRepository: postsPrivacySettingsRepo,
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: orbit,
    ),
  );

  // Allow the orbit data stream to populate (identity, contacts, groups).
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  // 193: default entry is the Inner-Circle view — the all-chats list (and its
  // contact/group name text) only renders after the top-left toggle is tapped.
  // This helper opens threads via the LIST (by name text), so the toggle is
  // mandatory. (197: the viz does render group avatars; the 198 F12 case above
  // exercises the Inner-Circle/arc/find path directly instead.)
  expect(
    find.text(aliceContactName),
    findsNothing,
    reason: '$sessionLabel: default entry must be the Inner-Circle view',
  );
  await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    find.text(aliceContactName),
    findsWidgets,
    reason: '$sessionLabel: contact must be visible in orbit list',
  );
  expect(
    find.text(groupName),
    findsOneWidget,
    reason: '$sessionLabel: group must be visible in orbit list',
  );

  // -- open the 1:1 thread.
  await tester.tap(find.text(aliceContactName).first);
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (final body in expectDmTexts) {
    expect(
      find.text(body),
      findsWidgets,
      reason:
          '$sessionLabel: 1:1 message bubble for "$body" must render with '
          'its body text. Empty bubbles indicate the cold-start render bug.',
    );
  }

  // Pop back to orbit.
  Navigator.of(tester.element(find.byType(Navigator).last)).pop();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  // -- open the group thread.
  await tester.tap(find.text(groupName));
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (final body in expectGroupTexts) {
    expect(
      find.text(body),
      findsWidgets,
      reason:
          '$sessionLabel: group message bubble for "$body" must render '
          'with its body text. Empty bubbles indicate the cold-start '
          'render bug for groups (no 1:1 coverage exists for this scenario '
          'in notification_open_ui_smoke_test.dart).',
    );
  }

  // Pop back to orbit so the next session starts from a clean tree.
  Navigator.of(tester.element(find.byType(Navigator).last)).pop();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  postsPrivacySettingsRepo.dispose();
}
