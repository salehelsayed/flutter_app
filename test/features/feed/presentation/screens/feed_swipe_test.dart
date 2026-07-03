import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_composer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_swipe_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_one_to_one.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 134-P6 swipe + Undo + gesture-arena tests (TC-23/24/25/26/33/35/37). Mounts
/// the REAL FeedWired so the Dismissible direction gates, store-driven removal,
/// the Undo SnackBar, and the Feed↔Orbit host-swipe arena are exercised
/// end-to-end (bounded pumps only — AmbientBackground.repeat() hangs
/// pumpAndSettle; use tester.drag/fling + pumpFrames).
void main() {
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;
  late List<Map<String, dynamic>> flowEvents;

  final testIdentity = IdentityModel(
    peerId: 'me-peer',
    publicKey: 'me-pk',
    privateKey: 'me-sk',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Me',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  ContactModel contact(String peerId, String name) => ContactModel(
    peerId: peerId,
    publicKey: '$peerId-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: name,
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: 'mlkem-$peerId',
  );

  setUp(() {
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    mediaFileManager = FakeMediaFileManager();
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
    flowEvents = [];
    debugSetFlowEventSink((payload) => flowEvents.add(payload));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp/test_docs';
            }
            return null;
          },
        );
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Future<void> seedPendingThread(
    String peerId,
    String body, {
    DateTime? at,
  }) async {
    final ts = (at ?? DateTime.now().toUtc()).toIso8601String();
    await messageRepo.saveMessage(
      ConversationMessage(
        id: 'in-$peerId',
        contactPeerId: peerId,
        text: body,
        senderPeerId: peerId,
        timestamp: ts,
        isIncoming: true,
        status: 'delivered',
        createdAt: ts,
      ),
    );
  }

  Widget buildWired({
    InMemoryFeedClearedRepository? feedClearedRepository,
  }) {
    final crListener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener = ChatMessageListener(
      chatMessageStream: const Stream.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FeedWired(
        repository: identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: messageRepo,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        feedClearedRepository:
            feedClearedRepository ?? InMemoryFeedClearedRepository(),
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void setWideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void setPhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  bool flowEmitted(String event) =>
      flowEvents.any((e) => e['event'] == event);

  void suppressFeedNavErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (details.toString().contains('overflowed') ||
          message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Finder feedOrbitSwipeHost() =>
      find.byKey(const ValueKey<String>('feed-orbit-swipe-host'));

  // The FeedSwipeCard hosting a given message text (a contact with a pending
  // thread also renders a system "connection" card, so byType is ambiguous).
  Finder swipeCardFor(String text) => find.ancestor(
    of: find.text(text),
    matching: find.byType(FeedSwipeCard),
  );

  // A Dismissible nested in a vertical scrollable does not reliably claim the
  // horizontal gesture from a single-step tester.drag, so swipe with a manual
  // gesture: a small slop-clearing first move, then a large move PAST the ~0.25
  // threshold, then release. [dx] sign picks the direction (>0 right / <0 left).
  Future<void> swipeCardPastThreshold(
    WidgetTester tester,
    Finder card,
    double dx, {
    bool release = true,
  }) async {
    final g = await tester.startGesture(tester.getCenter(card));
    await g.moveBy(Offset(dx.sign * 24, 0));
    await tester.pump();
    await g.moveBy(Offset(dx - dx.sign * 24, 0));
    await tester.pump();
    if (release) {
      await g.up();
    }
    await pumpFrames(tester);
  }

  // Seeds a live connection to [peerId] so a composer send SUCCEEDS (records a
  // reply in the focus session → a subsequent leave commits).
  void seedLiveConnection(String peerId) {
    p2pService.emitState(
      NodeState(
        isStarted: true,
        connections: [
          p2p.ConnectionState(
            peerId: peerId,
            multiaddrs: const ['/dns4/relay/tcp/443'],
            direction: 'outbound',
            status: 'connected',
          ),
        ],
      ),
    );
  }

  // ── B4/TC-7 (revises 134 TC-23): no-reply right-swipe = go BACK, keep card ──
  testWidgets(
    'B4/TC-7: swipe-right on a FOCUSED card with NO reply returns to Feed and '
    'KEEPS the card (no commit) — revises 134 TC-23',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      expect(find.byType(LetterCardOneToOne), findsOneWidget);

      // Focus the card (right-swipe is focus-gated).
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);
      expect(find.byType(FeedComposer), findsOneWidget);

      // Begin a swipe-right; the commit indicator still shows during the drag.
      final gesture = await tester.startGesture(
        tester.getCenter(swipeCardFor('hi from ann')),
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('feed-swipe-commit-indicator')),
        findsOneWidget,
      );

      // Cross the threshold and release WITHOUT having sent a reply.
      await gesture.moveBy(const Offset(220, 0));
      await tester.pump();
      await gesture.up();
      await pumpFrames(tester);

      // Returned to the feed: the card STAYS, focus cleared (composer gone), and
      // nothing was committed (no markCleared, no FEED_CLEAR_COMMIT). On HEAD
      // (unconditional commit) the card is removed → red.
      expect(find.text('hi from ann'), findsOneWidget);
      expect(find.byType(LetterCardOneToOne), findsOneWidget);
      expect(find.byType(FeedComposer), findsNothing);
      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  // ── B4/TC-8: right-swipe AFTER sending a reply commits and removes the card ─
  testWidgets(
    'B4/TC-8: swipe-right on a FOCUSED card AFTER sending a reply commits and '
    'removes the card (markCleared read=true, FEED_CLEAR_COMMIT)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // Seed a live connection so the reply send SUCCEEDS.
      seedLiveConnection('p1');
      await pumpFrames(tester);

      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Send a reply (recorded in the focus session).
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on my way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);

      // Now swipe-right → leave-with-reply commits and removes the card.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), 320);
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsNothing);
      expect(find.byType(LetterCardOneToOne), findsNothing);
      expect(clearedRepo.markCalls, hasLength(1));
      expect(clearedRepo.markCalls.single.markRead, isTrue);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isTrue);
    },
  );

  testWidgets(
    'TC-23b: under-threshold swipe-right springs back, no removal, no commit',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Claim the horizontal recognizer (past slop) but stay WELL under the
      // ~0.25 dismiss threshold, then release → springs back, no commit.
      final gesture = await tester.startGesture(
        tester.getCenter(swipeCardFor('hi from ann')),
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsOneWidget);
      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  // ── REG-INV3 (reframed for B4 as reply-then-leave): leave-WITH-reply marks
  //    the underlying conversation READ ───────────────────────────────────────
  testWidgets(
    'REG-INV3: a reply-then-leave (swipe-RIGHT) on a focused 1:1 card commits '
    'and marks the conversation READ (unread count → 0); locks the read-mark '
    'block in the leave-with-reply path',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      // An UNREAD incoming message (readAt == null after seed).
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // Precondition: the conversation is genuinely UNREAD before the commit.
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);

      // Seed a live connection so the reply send SUCCEEDS, then focus + reply.
      seedLiveConnection('p1');
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Sending alone must NOT read-mark (B5) — the conversation stays unread.
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'on my way',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await pumpFrames(tester);
      expect(await messageRepo.getUnreadCountForContact('p1'), 1);

      // Now LEAVE the replied thread by swiping right → commit + read-mark.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), 320);
      await pumpFrames(tester);

      // The leave-with-reply removed the card AND read-marked the conversation:
      // unread count drops to 0 (mutation-falsifiable — deleting the read-mark
      // block in the leave path leaves readAt == null → count 1).
      expect(find.text('hi from ann'), findsNothing);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isTrue);
      expect(
        await messageRepo.getUnreadCountForContact('p1'),
        0,
        reason: 'leave-with-reply must mark the underlying conversation read',
      );
    },
  );

  // ── REG-CONN-FOCUS (reframed for B4): a no-reply leave on a focused
  //    CONNECTION/system card DEFOCUSES it (card stays); still locks the
  //    connection: prefix strip in _endFocusSessionForThread ─────────────────
  testWidgets(
    'REG-CONN-FOCUS: focusing a connection (system) card then a no-reply '
    'swipe-RIGHT returns to the feed and KEEPS the card (defocus, no commit); '
    'locks the connection: prefix strip in _endFocusSessionForThread',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      // A fresh connection: a seeded contact with NO messages → ConnectionFeed
      // item → LetterCardSystem ("tap to say hi"), NOT a 1:1 thread card.
      contactRepo.seed([contact('p1', 'Ann')]);
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // A pure connection card (no 1:1 thread) is present.
      expect(find.byType(LetterCardSystem), findsOneWidget);
      expect(find.byType(LetterCardOneToOne), findsNothing);
      expect(find.byType(FeedComposer), findsNothing);

      // Focus by tapping the card BODY (the avatar — NOT the green "tap to say
      // hi" bubble, which would invoke onSendMessage instead of focus).
      await tester.tap(
        find.descendant(
          of: find.byType(LetterCardSystem),
          matching: find.byType(UserAvatar),
        ),
      );
      await pumpFrames(tester);

      // Focused: the shared composer appears.
      expect(find.byType(FeedComposer), findsOneWidget);

      // Swipe-RIGHT commit on the now-focused connection card.
      await swipeCardPastThreshold(
        tester,
        find.ancestor(
          of: find.byType(LetterCardSystem),
          matching: find.byType(FeedSwipeCard),
        ),
        320,
      );
      await pumpFrames(tester);

      // No reply was sent, so the leave DEFOCUSES: the card STAYS and focus is
      // cleared (composer retracted), with NO commit.
      // Mutation-falsifiable: without the prefix strip, _endFocusSessionForThread
      // compares 'connection:p1' != focused 'p1' → bails → focus never clears →
      // the composer stays mounted.
      expect(find.byType(LetterCardSystem), findsOneWidget);
      expect(find.byType(FeedComposer), findsNothing);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  // ── TC-24 swipe-left dismiss on a resting card ────────────────────────────
  testWidgets(
    'TC-24: swipe-left on a RESTING card dismisses — removed, red indicator, '
    'NO SnackBar (silent), markCleared(read=false), FEED_CLEAR_DISMISS '
    '(NOT COMMIT)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // RESTING (not focused). Begin a swipe-left → red dismiss indicator shows.
      final gesture = await tester.startGesture(
        tester.getCenter(swipeCardFor('hi from ann')),
      );
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('feed-swipe-dismiss-indicator')),
        findsOneWidget,
      );

      await gesture.moveBy(const Offset(-220, 0));
      await tester.pump();
      await gesture.up();
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsNothing);
      // Dismiss is SILENT — no "Removed …" Undo SnackBar (the user removed it).
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Removed'), findsNothing);
      expect(find.text('Undo'), findsNothing);

      expect(clearedRepo.markCalls, hasLength(1));
      expect(clearedRepo.markCalls.single.markRead, isFalse);
      // Discriminator: dismiss ≠ commit.
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isTrue);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  // ── TC-25 dismiss targets only the swiped card (silent) ───────────────────
  // (Store-level Undo re-insertion is covered by feed_store_test
  // 'markClearedLocally hides; clearClearedLocally re-surfaces in slot'; there
  // is no longer an Undo SnackBar to tap.)
  testWidgets(
    'TC-25: dismissing the MIDDLE of 3 cards removes ONLY it (no SnackBar, no '
    'Undo); the other two keep their order; markCleared(p2)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([
        contact('p1', 'Ann'),
        contact('p2', 'Ben'),
        contact('p3', 'Cara'),
      ]);
      // Newest → oldest so feed order is [Ann(top), Ben(mid), Cara(bottom)].
      final base = DateTime.utc(2026, 6, 1, 12);
      await seedPendingThread('p1', 'msg from ann', at: base);
      await seedPendingThread('p2', 'msg from ben',
          at: base.subtract(const Duration(minutes: 1)));
      await seedPendingThread('p3', 'msg from cara',
          at: base.subtract(const Duration(minutes: 2)));
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      expect(find.byType(LetterCardOneToOne), findsNWidgets(3));

      List<String> orderedTexts() {
        final cards = find.byType(LetterCardOneToOne);
        final bens = <(double, String)>[];
        for (final label in ['msg from ann', 'msg from ben', 'msg from cara']) {
          final f = find.text(label);
          if (f.evaluate().isNotEmpty) {
            bens.add((tester.getTopLeft(f).dy, label));
          }
        }
        bens.sort((a, b) => a.$1.compareTo(b.$1));
        expect(cards, findsWidgets);
        return bens.map((e) => e.$2).toList();
      }

      expect(orderedTexts(), ['msg from ann', 'msg from ben', 'msg from cara']);

      // Dismiss the MIDDLE card (Ben, index 1).
      final benCard = find.ancestor(
        of: find.text('msg from ben'),
        matching: find.byType(FeedSwipeCard),
      );
      await swipeCardPastThreshold(tester, benCard, -320);
      await pumpFrames(tester);

      // Only Ben (the swiped middle card) is gone; Ann + Cara keep their order.
      expect(find.text('msg from ben'), findsNothing);
      expect(orderedTexts(), ['msg from ann', 'msg from cara']);

      // Dismiss is silent — no SnackBar / Undo affordance.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Undo'), findsNothing);

      // Exactly the swiped thread was cleared (read-state untouched).
      expect(clearedRepo.markCalls, hasLength(1));
      expect(clearedRepo.markCalls.single.id, 'p2');
      expect(clearedRepo.markCalls.single.markRead, isFalse);
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isTrue);
    },
  );

  // ── TC-26 gesture gating + dominant-axis + tap-suppression ────────────────
  testWidgets(
    'TC-26a: right-swipe is DISABLED while resting (no commit, no removal)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // Resting (not focused) — swipe RIGHT past threshold should do nothing.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), 320);
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsOneWidget);
      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  testWidgets(
    'TC-26b (revised): left-swipe while focused with NO reply LEAVES the thread '
    '(go back — card stays, focus cleared, no commit/dismiss)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);
      // Focused: the composer is up.
      expect(find.byKey(const ValueKey('feed-composer')), findsOneWidget);

      // Swipe LEFT past threshold WITHOUT sending a reply → go back. The card
      // stays (nothing cleared/marked); focus is released (composer gone).
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), -320);
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsOneWidget);
      expect(find.byKey(const ValueKey('feed-composer')), findsNothing);
      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isFalse);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  testWidgets(
    'TC-26c: a primarily-VERTICAL drag scrolls the list (no commit/dismiss)',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      final base = DateTime.utc(2026, 6, 1, 12);
      final contacts = List.generate(
        20,
        (i) => contact('pv$i', 'User $i'),
      );
      contactRepo.seed(contacts);
      for (var i = 0; i < contacts.length; i++) {
        await seedPendingThread(
          'pv$i',
          'vmsg $i',
          at: base.subtract(Duration(minutes: i)),
        );
      }
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // Vertical drag on a card scrolls; never dismisses/commits.
      await tester.drag(
        find.byType(FeedSwipeCard).first,
        const Offset(0, -300),
      );
      await pumpFrames(tester);

      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isFalse);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  testWidgets(
    'TC-26d: a horizontal drag SUPPRESSES the focus tap (no focus toggle)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann'), contact('p2', 'Ben')]);
      await seedPendingThread('p1', 'hi from ann');
      await seedPendingThread('p2', 'hi from ben');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      expect(find.byType(LetterCardOneToOne), findsNWidgets(2));

      // Horizontal drag on a RESTING card → dismiss path, NOT a focus tap. If
      // the tap fired instead, the card would focus and the sibling collapse →
      // only one card would remain. Drag left (resting dismiss is allowed) and
      // confirm the OTHER card never collapsed from a stray focus.
      final annCard = find.ancestor(
        of: find.text('hi from ann'),
        matching: find.byType(FeedSwipeCard),
      );
      await swipeCardPastThreshold(tester, annCard, -320);
      await pumpFrames(tester);

      // Ann dismissed; Ben remains; Ben never got collapsed by a focus tap.
      expect(find.text('hi from ann'), findsNothing);
      expect(find.text('hi from ben'), findsOneWidget);
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isTrue);
    },
  );

  // ── TC-33 dismiss isolation: unread badge / Orbit unchanged ───────────────
  testWidgets(
    'TC-33: a dismiss leaves the unread badge unchanged (markRead=false)',
    (tester) async {
      setWideViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // Dismiss the resting card.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), -320);
      await pumpFrames(tester);

      expect(find.text('hi from ann'), findsNothing);
      // Dismiss must NOT mark read → repo call carries markRead:false (INV-2).
      expect(clearedRepo.markCalls.single.markRead, isFalse);
      // And the incoming message was never flipped to read (badge math is
      // read-state-driven; a dismiss leaving it unread proves badge isolation).
      final messages = await messageRepo.getMessagesForContact('p1');
      expect(
        messages.where((m) => m.isIncoming).every((m) => m.status != 'read'),
        isTrue,
        reason: 'dismiss must not flip incoming messages to read',
      );
    },
  );

  // ── TC-35 gesture arena: card commit vs Feed↔Orbit host swipe ─────────────
  testWidgets(
    'TC-35a: a horizontal drag starting on a FOCUSED card is CLAIMED by the '
    'card (returns to Feed, no commit on a no-reply leave) and does NOT switch '
    'Feed↔Orbit',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);
      await tester.tap(find.text('hi from ann'));
      await pumpFrames(tester);

      // Right-drag on the focused card → the card claims the gesture (the host
      // stays on Feed, never Orbit). No reply was sent, so it defocuses without
      // committing — the arena gate (card wins over host swipe) is the point.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), 320);
      await pumpFrames(tester);

      expect(appShellController.activeTab, 'feed');
      expect(find.byType(OrbitWired), findsNothing);
      expect(find.byType(FeedComposer), findsNothing);
      expect(clearedRepo.markCalls, isEmpty);
      expect(flowEmitted('FEED_CLEAR_COMMIT'), isFalse);
    },
  );

  testWidgets(
    'TC-35a2: a LEFT swipe on a RESTING card DISMISSES it and the arena gate '
    'keeps the host from switching Feed→Orbit (the load-bearing conflict)',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([contact('p1', 'Ann')]);
      await seedPendingThread('p1', 'hi from ann');
      final clearedRepo = InMemoryFeedClearedRepository();

      await tester.pumpWidget(buildWired(feedClearedRepository: clearedRepo));
      await pumpFrames(tester);

      // A LEFT swipe on the card is BOTH the dismiss direction AND the host's
      // swipe-to-Orbit direction — the arena gate must give it to the card.
      await swipeCardPastThreshold(tester, swipeCardFor('hi from ann'), -320);
      await pumpFrames(tester);

      // Stayed on Feed (host yielded) AND the card was dismissed.
      expect(appShellController.activeTab, 'feed');
      expect(find.byType(OrbitWired), findsNothing);
      expect(find.text('hi from ann'), findsNothing);
      expect(clearedRepo.markCalls, hasLength(1));
      expect(clearedRepo.markCalls.single.markRead, isFalse);
      expect(flowEmitted('FEED_CLEAR_DISMISS'), isTrue);
    },
  );

  testWidgets(
    'TC-35b: a horizontal drag on the background/list gap still switches '
    'Feed↔Orbit (host swipe wins where no card swipe is live)',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      // No pending threads → the list area is mostly empty background, so the
      // host swipe at the host center is not on a card.
      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      expect(find.byType(FeedSwipeCard), findsNothing);
      await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
      await pumpFrames(tester);

      expect(appShellController.activeTab, 'orbit');
      expect(find.byType(OrbitWired), findsOneWidget);
    },
  );

  testWidgets('swipe entry lands on the Inner-Circle view', (tester) async {
    setPhoneViewport(tester);
    suppressFeedNavErrors();
    identityRepo.seed(testIdentity);

    await tester.pumpWidget(buildWired());
    await pumpFrames(tester);

    await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
    await pumpFrames(tester);

    expect(appShellController.activeTab, 'orbit');
    expect(find.byType(OrbitWired), findsOneWidget);
    // Edge-swipe entry lands on the Inner-Circle view — no all-chats affordance.
    expect(find.byType(OrbitalVisualization), findsOneWidget);
    expect(find.byType(OrbitSearchTrigger), findsNothing);
  });

  testWidgets('toggle tap does not move the Feed↔Orbit pane', (tester) async {
    setPhoneViewport(tester);
    suppressFeedNavErrors();
    identityRepo.seed(testIdentity);

    await tester.pumpWidget(buildWired());
    await pumpFrames(tester);

    await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
    await pumpFrames(tester);
    expect(appShellController.activeTab, 'orbit');

    final hostBefore = tester.getTopLeft(feedOrbitSwipeHost());

    // A tap on the toggle flips the view but must NOT translate the host pane
    // (the gesture arena distinguishes a tap from a horizontal host drag).
    await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
    await pumpFrames(tester);

    expect(appShellController.activeTab, 'orbit');
    expect(tester.getTopLeft(feedOrbitSwipeHost()), hostBefore);
    // ... and the view actually flipped to all-chats.
    expect(find.byType(OrbitSearchTrigger), findsOneWidget);
    expect(find.byType(OrbitalVisualization), findsNothing);
  });

  // (TC-37 removed: it exercised the Undo SnackBar vs live re-surface race. The
  // swipe-dismiss Undo SnackBar was removed, so there is no UI undo to tap; the
  // store single-source-of-truth / re-surface invariant is covered by
  // feed_store_test and feed_pending_projection_test.)

  // ── 198 F9 (INV-8): an active Orbit sculpt edit session yields the host swipe.
  // Empty background point ABOVE the circle column (on a phone the 320px viz
  // nearly fills the width, so a side point lands inside the viz box).
  Offset orbitBgPoint(WidgetTester tester) {
    final viz = tester.getRect(find.byType(OrbitalVisualization));
    // Just left of the 320px viz box — the background sibling receives it (a
    // point INSIDE the viz box is absorbed by the centering Center).
    return Offset(viz.left - 6, viz.center.dy);
  }

  Future<void> enterOrbitAndEdit(WidgetTester tester) async {
    await tester.drag(feedOrbitSwipeHost(), const Offset(-170, 0));
    await pumpFrames(tester);
    expect(appShellController.activeTab, 'orbit');
    expect(find.byType(OrbitalVisualization), findsOneWidget);

    // Long-press empty orbit canvas → enter edit.
    final g = await tester.startGesture(orbitBgPoint(tester));
    await tester.pump(const Duration(milliseconds: 620));
    await g.up();
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
  }

  testWidgets(
    'YIELD-1: an active Orbit edit session suppresses the feed↔orbit host swipe',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await enterOrbitAndEdit(tester);

      // A rightward host drag (orbit→feed) must NOT slide to Feed mid-sculpt.
      await tester.drag(feedOrbitSwipeHost(), const Offset(170, 0));
      await pumpFrames(tester);
      expect(appShellController.activeTab, 'orbit',
          reason: 'the edit session yields the host swipe (INV-8)');
    },
  );

  testWidgets(
    'YIELD-2: the host swipe restores after the edit session exits',
    (tester) async {
      setPhoneViewport(tester);
      suppressFeedNavErrors();
      identityRepo.seed(testIdentity);
      await tester.pumpWidget(buildWired());
      await pumpFrames(tester);

      await enterOrbitAndEdit(tester);

      // Tap-away to exit the edit session.
      await tester.tapAt(orbitBgPoint(tester));
      await tester.pump(const Duration(milliseconds: 350));
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);

      // Now a rightward host drag switches back to Feed.
      await tester.drag(feedOrbitSwipeHost(), const Offset(170, 0));
      await pumpFrames(tester);
      expect(appShellController.activeTab, 'feed');
    },
  );
}
