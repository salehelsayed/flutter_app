import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 194 — per-node unread "messenger orbit" indicator, wired-host tier.
///
/// Covers the live-appear paths, the per-surface CLEAR-on-read paths (the core
/// promise — TC-194-16 is PROD-CRITICAL: an external read with no orbit-owned
/// nav hook must still clear the node via the new `conversationReadStream`
/// seam), lifecycle durability, and the 193 surface-scoping regression. Lit
/// nodes host the ~9s repeat rotation which never settles, so every pump is
/// bounded (pumpOrbitFrames) — NEVER pumpAndSettle.
class _FakeChatMessageListener extends ChatMessageListener {
  final StreamController<ConversationMessage> _incomingController =
      StreamController.broadcast();
  final StreamController<ContactModel> _contactUpdateController =
      StreamController.broadcast();

  _FakeChatMessageListener({required super.messageRepo, required super.contactRepo})
    : super(chatMessageStream: const Stream.empty());

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdateController.stream;

  void emitIncomingMessage(ConversationMessage msg) =>
      _incomingController.add(msg);

  @override
  void emitContactUpdate(ContactModel contact) =>
      _contactUpdateController.add(contact);
}

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late List<Map<String, dynamic>> flowEvents;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-test-peer-id-12345',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  ContactModel contact(String peerId, String username) => ContactModel(
    peerId: peerId,
    publicKey: '$peerId-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig',
    scannedAt: '2026-01-0${1 + (peerId.hashCode % 8).abs()}T00:00:00Z',
    mlKemPublicKey: 'mlkem-$peerId',
  );

  final bob = contact('contact-peer-id', 'Bob');

  var seq = 0;
  ConversationMessage incoming(String peerId, {String? id}) {
    seq++;
    final ts = DateTime.now()
        .toUtc()
        .add(Duration(milliseconds: seq))
        .toIso8601String();
    return ConversationMessage(
      id: id ?? 'in-$peerId-$seq',
      contactPeerId: peerId,
      senderPeerId: peerId,
      text: 'ping $seq',
      timestamp: ts,
      status: 'delivered',
      isIncoming: true,
      createdAt: ts,
    );
  }

  setUp(() {
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    imageProcessor = ImageProcessor(
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
    seq = 0;
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    postsPrivacySettingsRepository.dispose();
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  void suppressNavAssetErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Widget buildOrbitWired({
    ChatMessageListener? chatMessageListener,
    AppShellController? appShellController,
    ValueNotifier<int>? feedUnreadCountListenable,
  }) {
    final crListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener =
        chatMessageListener ??
        ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

    final orbitWidget = OrbitWired(
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
      appShellController: appShellController,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      feedUnreadCountListenable: feedUnreadCountListenable,
    );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: orbitWidget,
    );
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 6}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> switchToAllChats(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
    await pumpOrbitFrames(tester);
  }

  int satelliteCount(WidgetTester tester) => tester
      .widgetList(
        find.byWidgetPredicate((w) {
          final key = w.key;
          return key is ValueKey<String> &&
              key.value.startsWith('unread-satellite-');
        }),
      )
      .length;

  bool sawReadRefresh(List<Map<String, dynamic>> events) =>
      events.any((e) => e['event'] == 'ORBIT_FL_READ_REFRESH');

  group('194 orbit per-node unread indicator (wired)', () {
    testWidgets('TC-194-10: incoming message lights the node live', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([bob]);

      final listener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      await tester.pumpWidget(buildOrbitWired(chatMessageListener: listener));
      await pumpOrbitFrames(tester, count: 8);
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(UnreadOrbitIndicator), findsNothing);

      final msg = incoming('contact-peer-id', id: 'm1');
      await messageRepo.saveMessage(msg);
      listener.emitIncomingMessage(msg);
      await pumpOrbitFrames(tester, count: 6);

      expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
    });

    testWidgets(
      'TC-194-11: second message increments satellites without node re-entrance',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);

        final listener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        await tester.pumpWidget(buildOrbitWired(chatMessageListener: listener));
        await pumpOrbitFrames(tester, count: 8);

        final first = incoming('contact-peer-id', id: 'm1');
        await messageRepo.saveMessage(first);
        listener.emitIncomingMessage(first);
        await pumpOrbitFrames(tester, count: 6);
        expect(satelliteCount(tester), 1);
        final stateBefore = tester.state(find.byType(OrbitalAvatar));

        final second = incoming('contact-peer-id', id: 'm2');
        await messageRepo.saveMessage(second);
        listener.emitIncomingMessage(second);
        await pumpOrbitFrames(tester, count: 6);

        expect(satelliteCount(tester), 2);
        // Same State object -> the node was not remounted (no entrance replay).
        final stateAfter = tester.state(find.byType(OrbitalAvatar));
        expect(identical(stateBefore, stateAfter), isTrue);
      },
    );

    testWidgets(
      'TC-194-12: message while Feed active lights node on Orbit entry '
      '(dirty replay)',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);

        // 214: this case ARRANGES a feed-active shell (orbit off-screen) so
        // the dirty replay fires on Orbit ENTRY; pin the start tab now that
        // the bare default is orbit.
        final shell = AppShellController(initialTab: AppShellTab.feed);
        final feedUnread = ValueNotifier<int>(0);
        addTearDown(feedUnread.dispose);
        final listener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: listener,
            appShellController: shell,
            feedUnreadCountListenable: feedUnread,
          ),
        );
        await pumpOrbitFrames(tester, count: 8);
        expect(shell.activeTab, AppShellTab.feed);

        // Message arrives while Orbit is off-screen -> dirty-buffered.
        final msg = incoming('contact-peer-id', id: 'm1');
        await messageRepo.saveMessage(msg);
        listener.emitIncomingMessage(msg);
        await pumpOrbitFrames(tester, count: 4);

        // Enter Orbit: the dirty replay lights the node on the inner-circle view.
        shell.switchTo(AppShellTab.orbit);
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(OrbitalVisualization), findsOneWidget);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      },
    );

    testWidgets('TC-194-13: overflow-hidden friend jumps visible and lit', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      // 14 friends -> one hidden beyond the visible 13. The 14th's incoming
      // message re-ranks it into the visible set (recency) and it arrives lit.
      final many = [
        for (var i = 0; i < 13; i++) contact('peer-$i', 'F$i'),
        bob,
      ];
      contactRepo.seed(many);
      // Give the first 13 PAST recency so bob (no messages) starts hidden at the
      // bottom; his incoming message below is "now" -> newest -> jumps visible.
      for (var i = 0; i < 13; i++) {
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'seed-$i',
            contactPeerId: 'peer-$i',
            senderPeerId: 'test-peer-id-12345',
            text: 'x',
            timestamp: DateTime.now()
                .toUtc()
                .subtract(Duration(minutes: 13 - i))
                .toIso8601String(),
            status: 'sent',
            isIncoming: false,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
      }

      final listener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      await tester.pumpWidget(buildOrbitWired(chatMessageListener: listener));
      await pumpOrbitFrames(tester, count: 10);

      final msg = incoming('contact-peer-id', id: 'm-bob');
      await messageRepo.saveMessage(msg);
      listener.emitIncomingMessage(msg);
      await pumpOrbitFrames(tester, count: 8);

      expect(find.byType(UnreadOrbitIndicator), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TC-194-16: externally-pushed conversation read clears the lit node '
      '(read event) [PROD-CRITICAL]',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);
        // Persisted unread -> node lit on load.
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm2'));

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);

        flowEvents.clear();
        // The read happens OUTSIDE any orbit-owned nav hook (mimics a
        // notification-tap route marking read while Orbit is the active tab).
        await messageRepo.markConversationAsRead('contact-peer-id');
        await pumpOrbitFrames(tester, count: 8);

        expect(
          find.byType(UnreadOrbitIndicator),
          findsNothing,
          reason: 'the read event must clear the node with no new message',
        );
        expect(
          sawReadRefresh(flowEvents),
          isTrue,
          reason: 'the clear must be driven by ORBIT_FL_READ_REFRESH',
        );
      },
    );

    testWidgets(
      'TC-194-17: feed-side read after active-arrival clears on tab return',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);

        final shell = AppShellController(initialTab: AppShellTab.orbit);
        final feedUnread = ValueNotifier<int>(0);
        addTearDown(feedUnread.dispose);
        final listener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: listener,
            appShellController: shell,
            feedUnreadCountListenable: feedUnread,
          ),
        );
        await pumpOrbitFrames(tester, count: 8);

        // Arrives while Orbit active -> lit (NOT dirty).
        final msg = incoming('contact-peer-id', id: 'm1');
        await messageRepo.saveMessage(msg);
        listener.emitIncomingMessage(msg);
        await pumpOrbitFrames(tester, count: 6);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);

        // Leave to Feed, read there, return -> the read event dirty-buffers
        // while inactive and replays on the rising edge.
        shell.switchTo(AppShellTab.feed);
        await pumpOrbitFrames(tester, count: 4);
        await messageRepo.markConversationAsRead('contact-peer-id');
        await pumpOrbitFrames(tester, count: 4);
        shell.switchTo(AppShellTab.orbit);
        await pumpOrbitFrames(tester, count: 8);

        expect(find.byType(UnreadOrbitIndicator), findsNothing);
      },
    );

    test(
      'INV-5: mark-read of an already-read conversation emits nothing',
      () async {
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));
        final reads = <String>[];
        final sub = messageRepo.conversationReadStream.listen(reads.add);
        addTearDown(sub.cancel);

        expect(await messageRepo.markConversationAsRead('contact-peer-id'), 1);
        await Future<void>.delayed(Duration.zero);
        expect(reads, ['contact-peer-id']);

        reads.clear();
        expect(await messageRepo.markConversationAsRead('contact-peer-id'), 0);
        await Future<void>.delayed(Duration.zero);
        expect(reads, isEmpty);
      },
    );

    testWidgets('TC-194-18: read during open conversation settles unlit', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([bob]);

      final listener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      await tester.pumpWidget(buildOrbitWired(chatMessageListener: listener));
      await pumpOrbitFrames(tester, count: 8);

      // Message arrives (lights) then is read while the conversation is open;
      // the read event post-dates the arrival refresh -> settles unlit.
      final msg = incoming('contact-peer-id', id: 'm1');
      await messageRepo.saveMessage(msg);
      listener.emitIncomingMessage(msg);
      await pumpOrbitFrames(tester, count: 4);
      await messageRepo.markConversationAsRead('contact-peer-id');
      await pumpOrbitFrames(tester, count: 8);

      expect(find.byType(UnreadOrbitIndicator), findsNothing);
    });

    testWidgets('TC-194-19: 3->0 transition clears with no artifacts', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([bob]);
      for (final id in ['m1', 'm2', 'm3']) {
        await messageRepo.saveMessage(incoming('contact-peer-id', id: id));
      }

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 8);
      expect(satelliteCount(tester), 3);

      await messageRepo.markConversationAsRead('contact-peer-id');
      await pumpOrbitFrames(tester, count: 8);

      expect(find.byType(UnreadOrbitIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TC-194-20: fresh mount from persisted counts is lit (durability)',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm2'));

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);

        // Full unmount then a brand-new mount reconstructs lit-ness from the DB,
        // not from having witnessed a message event.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'TC-194-23: lit indicator uses a live vsync controller (mutable by '
      'TickerMode)',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);

        final controllers = tester
            .widgetList<AnimatedBuilder>(
              find.descendant(
                of: find.byType(UnreadOrbitIndicator),
                matching: find.byType(AnimatedBuilder),
              ),
            )
            .map((ab) => ab.listenable)
            .whereType<AnimationController>()
            .toList();
        // A vsync'd AnimationController drives it (not a raw Timer), so the 163
        // host TickerMode mute applies off-screen (TC-163-08 sentinel).
        expect(controllers, isNotEmpty);
        expect(controllers.any((c) => c.isAnimating), isTrue);
      },
    );

    testWidgets(
      'TC-194-32: toggle round-trips keep pill and indicator surface-scoped',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);

        // Inner-circle: indicator, no list pill.
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        expect(find.byType(UnreadCountBadge), findsNothing);

        await switchToAllChats(tester);
        // All-chats: the list pill, no orbital indicator.
        expect(find.byType(FriendRow), findsWidgets);
        expect(find.byType(UnreadCountBadge), findsWidgets);
        expect(find.byType(UnreadOrbitIndicator), findsNothing);

        // Toggle back: indicator returns, pill gone. No leak either way.
        await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
        await pumpOrbitFrames(tester, count: 6);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        expect(find.byType(UnreadCountBadge), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'destructive: unmounting the orbit while a node is lit leaves no ticker '
      'leak',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([bob]);
        await messageRepo.saveMessage(incoming('contact-peer-id', id: 'm1'));

        await tester.pumpWidget(buildOrbitWired());
        await pumpOrbitFrames(tester, count: 8);
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);

        // Tear the whole tree down mid-rotation.
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
