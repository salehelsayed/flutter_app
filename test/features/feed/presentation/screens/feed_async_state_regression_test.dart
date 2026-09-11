import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
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
import '../../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../../features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../../features/identity/domain/repositories/fake_identity_repository.dart';

class DelayedMediaFileManager extends FakeMediaFileManager {
  bool holdNext = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.contains('outgoing') && holdNext) {
      holdNext = false;
      started.complete();
      await release.future;
    }
    return super.resolveStoredPath(storedPath);
  }
}

class DelayedPageMessageRepository extends InMemoryMessageRepository {
  bool holdNextPage = false;
  final pageStarted = Completer<void>();
  final releasePage = Completer<void>();

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final page = await super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
    if (holdNextPage) {
      holdNextPage = false;
      pageStarted.complete();
      await releasePage.future;
    }
    return page;
  }
}

class Fixture {
  final identity = FakeIdentityRepository();
  final contacts = FakeContactRepository();
  final requests = FakeContactRequestRepository();
  final messages = DelayedPageMessageRepository();
  final media = InMemoryMediaAttachmentRepository();
  final files = DelayedMediaFileManager();
  final bridge = FakeBridge();
  final p2p = FakeP2PService();
  final posts = InMemoryPostRepository();
  final privacy = InMemoryPostsPrivacySettingsRepository();
  final shell = AppShellController(initialTab: AppShellTab.feed);
  late final ChatMessageListener chat = ChatMessageListener(
    chatMessageStream: const Stream.empty(),
    messageRepo: messages,
    contactRepo: contacts,
  );
  late final ContactRequestListener requestListener = ContactRequestListener(
    contactRequestStream: const Stream.empty(),
    requestRepo: requests,
    contactRepo: contacts,
    bridge: bridge,
    getOwnPeerId: () => 'self',
  );

  Future<void> seed() async {
    identity.seed(
      IdentityModel(
        peerId: 'self',
        publicKey: 'pk',
        privateKey: 'sk',
        mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
        username: 'Me',
        createdAt: '2026-09-10T10:00:00Z',
        updatedAt: '2026-09-10T10:00:00Z',
      ),
    );
    contacts.seed([
      ContactModel(
        peerId: 'friend',
        publicKey: 'pk',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig',
        scannedAt: '2026-01-01T10:00:00Z',
        mlKemPublicKey: 'kem',
      ),
    ]);
    await media.saveAttachment(
      const MediaAttachment(
        id: 'outgoing-file',
        messageId: 'outgoing',
        mime: 'application/pdf',
        size: 12,
        mediaType: 'file',
        localPath: 'media/friend/outgoing.pdf',
        downloadStatus: 'done',
        createdAt: '2026-09-10T10:00:00Z',
      ),
      owner: MediaOwnerLane.direct,
    );
    await messages.saveMessage(outgoing);
    await messages.saveMessage(
      const ConversationMessage(
        id: 'incoming',
        contactPeerId: 'friend',
        senderPeerId: 'friend',
        text: 'Unread later reply',
        timestamp: '2026-09-10T10:01:00Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-09-10T10:01:00Z',
      ),
    );
  }

  static const outgoing = ConversationMessage(
    id: 'outgoing',
    contactPeerId: 'friend',
    senderPeerId: 'self',
    text: 'Old outgoing row',
    timestamp: '2026-09-10T10:00:00Z',
    isIncoming: false,
    status: 'sent',
    createdAt: '2026-09-10T10:00:00Z',
  );

  Widget build() => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FeedWired(
      repository: identity,
      contactRepository: contacts,
      contactRequestRepository: requests,
      contactRequestListener: requestListener,
      messageRepository: messages,
      postRepository: posts,
      mediaAttachmentRepository: media,
      chatMessageListener: chat,
      bridge: bridge,
      p2pService: p2p,
      mediaFileManager: files,
      secureKeyStore: FakeSecureKeyStore(),
      imageProcessor: ImageProcessor(
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
      ),
      appShellController: shell,
      pendingPostTargetStore: PendingPostTargetStore(),
      postsPrivacySettingsRepository: privacy,
      feedClearedRepository: InMemoryFeedClearedRepository(),
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    if (files.started.isCompleted && !files.release.isCompleted) {
      files.release.complete();
    }
    if (messages.pageStarted.isCompleted && !messages.releasePage.isCompleted) {
      messages.releasePage.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    posts.dispose();
    privacy.dispose();
    shell.dispose();
  }
}

Future<void> frames(WidgetTester tester, {int count = 6}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ThreadFeedItem thread(WidgetTester tester) => tester
    .widget<FeedScreen>(find.byType(FeedScreen))
    .feedItemsListenable!
    .value
    .whereType<ThreadFeedItem>()
    .single;

void main() {
  setUp(() => flowEventLoggingEnabled = false);
  tearDown(() => flowEventLoggingEnabled = true);
  testWidgets('older in-flight feed update must not resurrect a hidden row', (
    tester,
  ) async {
    final f = Fixture();
    await f.seed();
    try {
      await tester.pumpWidget(f.build());
      await frames(tester);
      expect(thread(tester).messages.any((m) => m.id == 'outgoing'), isTrue);
      f.files.holdNext = true;
      await f.messages.saveMessage(
        Fixture.outgoing.copyWith(status: 'delivered'),
      );
      await tester.pump();
      await frames(tester, count: 1);
      expect(f.files.started.isCompleted, isTrue);

      await f.messages.saveMessage(
        Fixture.outgoing.copyWith(
          status: 'delivered',
          hiddenAt: '2026-09-10T10:02:00Z',
        ),
      );
      await tester.pump();
      await frames(tester, count: 2);
      expect(thread(tester).messages.any((m) => m.id == 'outgoing'), isFalse);

      f.files.release.complete();
      await frames(tester, count: 2);
      expect((await f.messages.getMessage('outgoing'))!.isHidden, isTrue);
      expect(
        thread(tester).messages.any((m) => m.id == 'outgoing'),
        isFalse,
        reason: 'a stale async completion must not put the hidden row back',
      );
    } finally {
      await f.dispose(tester);
    }
  });

  testWidgets('feed draft survives closing and reopening its reply card', (
    tester,
  ) async {
    final f = Fixture();
    await f.seed();
    try {
      await tester.pumpWidget(f.build());
      await frames(tester);
      tester.widget<FeedScreen>(find.byType(FeedScreen)).onFocusCard!('friend');
      await frames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('feed-composer-field')),
        'Unsaved reply',
      );
      tester.widget<FeedScreen>(find.byType(FeedScreen)).onClearFocus!();
      await frames(tester);
      expect(find.byKey(const ValueKey('feed-composer-field')), findsNothing);
      tester.widget<FeedScreen>(find.byType(FeedScreen)).onFocusCard!('friend');
      await frames(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('feed-composer-field')),
            )
            .controller!
            .text,
        'Unsaved reply',
      );
    } finally {
      await f.dispose(tester);
    }
  });

  for (final sameMessage in [true, false]) {
    testWidgets(
      sameMessage
          ? 'later status wins over an older hydrated update for the same row'
          : 'independent message updates both survive overlapping hydration',
      (tester) async {
        final f = Fixture();
        await f.seed();
        try {
          await tester.pumpWidget(f.build());
          await frames(tester);
          f.files.holdNext = true;
          await f.messages.saveMessage(Fixture.outgoing);
          await tester.pump();
          await frames(tester, count: 1);
          expect(f.files.started.isCompleted, isTrue);
          final next = Fixture.outgoing.copyWith(
            id: sameMessage ? 'outgoing' : 'independent',
            text: sameMessage ? 'Old outgoing row' : 'Independent row',
            status: 'delivered',
            timestamp: '2026-09-10T10:00:30Z',
          );
          await f.messages.saveMessage(next);
          await tester.pump();
          await frames(tester, count: 2);
          expect(
            thread(tester).messages.singleWhere((m) => m.id == next.id).status,
            'delivered',
          );
          f.files.release.complete();
          await frames(tester, count: 2);
          expect(
            thread(tester).messages.singleWhere((m) => m.id == next.id).status,
            'delivered',
          );
          expect(
            thread(tester).messages.any((m) => m.id == 'outgoing'),
            isTrue,
          );
        } finally {
          await f.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'contact hydration retries a snapshot invalidated by a newer row',
    (tester) async {
      final f = Fixture();
      await f.seed();
      try {
        await tester.pumpWidget(f.build());
        await frames(tester);
        f.messages.holdNextPage = true;
        tester.widget<FeedScreen>(find.byType(FeedScreen)).onFocusCard!(
          'friend',
        );
        await tester.pump();
        expect(f.messages.pageStarted.isCompleted, isTrue);
        final next = Fixture.outgoing.copyWith(
          id: 'new-during-hydration',
          text: 'Latest row',
          status: 'delivered',
          timestamp: '2026-09-10T10:00:30Z',
        );
        await f.messages.saveMessage(next);
        await tester.pump();
        await frames(tester, count: 2);
        expect(thread(tester).messages.any((m) => m.id == next.id), isTrue);
        f.messages.releasePage.complete();
        await frames(tester, count: 3);
        expect(thread(tester).messages.any((m) => m.id == next.id), isTrue);
      } finally {
        await f.dispose(tester);
      }
    },
  );

  testWidgets('contact metadata stays current after older media hydration', (
    tester,
  ) async {
    final f = Fixture();
    await f.seed();
    try {
      await tester.pumpWidget(f.build());
      await frames(tester);
      f.files.holdNext = true;
      await f.messages.saveMessage(
        Fixture.outgoing.copyWith(status: 'delivered'),
      );
      await tester.pump();
      await frames(tester, count: 1);
      expect(f.files.started.isCompleted, isTrue);
      final updated = (await f.contacts.getContact(
        'friend',
      ))!.copyWith(username: 'Updated Alice', isBlocked: true);
      f.contacts.seed([updated]);
      f.chat.emitContactUpdate(updated);
      await frames(tester, count: 1);
      expect(thread(tester).contactUsername, 'Updated Alice');
      expect(thread(tester).isBlocked, isTrue);
      f.files.release.complete();
      await frames(tester, count: 2);
      expect(thread(tester).contactUsername, 'Updated Alice');
      expect(thread(tester).isBlocked, isTrue);
      expect(
        thread(tester).messages.singleWhere((m) => m.id == 'outgoing').status,
        'delivered',
      );
    } finally {
      await f.dispose(tester);
    }
  });

  testWidgets(
    'newer contacts-section reload supersedes an older full-feed read',
    (tester) async {
      final f = Fixture();
      await f.seed();
      f.messages.holdNextPage = true;
      try {
        await tester.pumpWidget(f.build());
        await frames(tester, count: 2);
        expect(f.messages.pageStarted.isCompleted, isTrue);
        f.shell.switchTo('orbit');
        await frames(tester);
        f.contacts.seed([]);
        final orbit = tester.widget<OrbitWired>(find.byType(OrbitWired));
        f.shell.switchTo('feed');
        orbit.onEmbeddedExit!(const FeedRouteChanges(reloadAllContacts: true));
        await frames(tester);
        final feed = tester.widget<FeedScreen>(find.byType(FeedScreen));
        expect(
          feed.feedItemsListenable!.value.whereType<ThreadFeedItem>(),
          isEmpty,
        );
        f.messages.releasePage.complete();
        await frames(tester);
        expect(
          feed.feedItemsListenable!.value.whereType<ThreadFeedItem>(),
          isEmpty,
          reason: 'the old full read must not restore the removed contact',
        );
      } finally {
        await f.dispose(tester);
      }
    },
  );

  testWidgets('drafts are isolated when the focused card changes', (
    tester,
  ) async {
    final f = Fixture();
    await f.seed();
    final alice = (await f.contacts.getContact('friend'))!;
    f.contacts.seed([alice, alice.copyWith(peerId: 'other', username: 'Bob')]);
    await f.messages.saveMessage(
      const ConversationMessage(
        id: 'other-incoming',
        contactPeerId: 'other',
        senderPeerId: 'other',
        text: 'Other unread',
        timestamp: '2026-09-10T10:01:00Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-09-10T10:01:00Z',
      ),
    );
    try {
      await tester.pumpWidget(f.build());
      await frames(tester);
      final field = find.byKey(const ValueKey('feed-composer-field'));
      void focus(String id) =>
          tester.widget<FeedScreen>(find.byType(FeedScreen)).onFocusCard!(id);
      focus('friend');
      await frames(tester);
      await tester.enterText(field, 'For Alice');
      focus('other');
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, 'For Bob');
      focus('friend');
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, 'For Alice');
      focus('other');
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, 'For Bob');
      await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      focus('friend');
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, 'For Alice');
      focus('other');
      await frames(tester);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    } finally {
      await f.dispose(tester);
    }
  });

  testWidgets(
    'finishing a send attempt preserves the new draft typed while it waited',
    (tester) async {
      final f = Fixture();
      await f.seed();
      final sendStarted = Completer<void>();
      final releaseSend = Completer<void>();
      f.p2p.emitState(const NodeState(isStarted: true, peerId: 'self'));
      f.messages.afterDirectInboxCustodyStage = (message) async {
        if (!sendStarted.isCompleted) sendStarted.complete();
        await releaseSend.future;
      };
      try {
        await tester.pumpWidget(f.build());
        await frames(tester);
        tester.widget<FeedScreen>(find.byType(FeedScreen)).onFocusCard!(
          'friend',
        );
        await frames(tester);
        final field = find.byKey(const ValueKey('feed-composer-field'));
        await tester.enterText(field, 'Send this');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
        await frames(tester, count: 2);
        expect(sendStarted.isCompleted, isTrue);
        expect(tester.widget<TextField>(field).controller!.text, isEmpty);
        await tester.enterText(field, 'Next unsent draft');
        releaseSend.complete();
        await frames(tester);
        expect(
          tester.widget<TextField>(field).controller!.text,
          'Next unsent draft',
        );
        final sent = (await f.messages.getMessagesForContact(
          'friend',
        )).singleWhere((m) => m.text == 'Send this');
        expect(sent.status, isNot(anyOf('queued', 'sending')));
      } finally {
        if (!releaseSend.isCompleted) releaseSend.complete();
        await f.dispose(tester);
      }
    },
  );
}
