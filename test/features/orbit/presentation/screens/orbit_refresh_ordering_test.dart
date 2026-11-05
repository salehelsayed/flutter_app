import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/direct_contact_conversation_purge.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/repositories/orbit_call_activity_source.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

Future<void> _loadOrbitMenuFont() async {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(await config.readAsString())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'flutter',
  );
  final sdk = Directory.fromUri(
    config.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  await (FontLoader('Roboto')..addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      ))
      .load();
}

final _friend = ContactModel(
  peerId: 'friend',
  publicKey: 'pub',
  rendezvous: '/dns4/relay/tcp/443',
  username: 'Alice',
  signature: 'sig',
  scannedAt: '2026-09-10T10:00:00Z',
);
final _message = ConversationMessage(
  id: 'unread',
  contactPeerId: 'friend',
  senderPeerId: 'friend',
  text: 'Unseen message',
  timestamp: '2026-09-10T10:00:00Z',
  isIncoming: true,
  status: 'delivered',
  createdAt: '2026-09-10T10:00:00Z',
);

class _Listener extends ChatMessageListener {
  _Listener({required super.messageRepo, required super.contactRepo})
    : super(chatMessageStream: const Stream.empty());
  final incoming = StreamController<ConversationMessage>.broadcast();
  @override
  Stream<ConversationMessage> get incomingMessageStream => incoming.stream;
}

/// All queued database-shaped operations complete in FIFO order. A newer
/// missing-contact snapshot can still overtake an older multi-query snapshot.
class _SerialQueries {
  bool enabled = false;
  final pending = <Future<void> Function()>[];
  Future<T> run<T>(Future<T> Function() action) {
    if (!enabled) return action();
    final result = Completer<T>();
    pending.add(() async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> step() async {
    expect(pending, isNotEmpty);
    await pending.removeAt(0)();
  }
}

class _Contacts extends FakeContactRepository {
  _Contacts(this.queries);
  final _SerialQueries queries;
  @override
  Future<ContactModel?> getContact(String peerId) =>
      queries.run(() => super.getContact(peerId));
}

class _PurgeContacts extends _Contacts
    implements DirectContactConversationPurgeCapability {
  _PurgeContacts(super.queries, this.messages);
  final _Messages messages;

  @override
  bool get supportsDirectContactConversationPurge => true;

  @override
  Future<DirectContactConversationPurgeSummary>
  purgeDirectContactConversationAndContact(String peerId) async {
    final existed = await contactExists(peerId);
    final deletedMessages = await messages.deleteMessagesForContact(peerId);
    await deleteContact(peerId);
    return DirectContactConversationPurgeSummary(
      deletedTextCustodyRows: 0,
      deletedEventCustodyRows: 0,
      deletedReactions: 0,
      deletedMessages: deletedMessages,
      deletedContact: existed,
    );
  }
}

class _Messages extends InMemoryMessageRepository
    implements
        MessageRepositoryRemovalSource,
        DirectContactPurgeReconciliation {
  _Messages(this.queries);
  final _SerialQueries queries;
  final removals = StreamController<DirectMessageRemoval>.broadcast();
  final publishedRemovals = <DirectMessageRemoval>[];

  @override
  Stream<DirectMessageRemoval> get messageRemovals => removals.stream;

  @override
  Future<void> reconcileDirectContactConversationPurge(String peerId) async {
    // The real use case calls this only after the final contact purge commits.
    final removal = DirectMessageRemoval(
      contactPeerId: peerId,
      messageId: null,
    );
    publishedRemovals.add(removal);
    removals.add(removal);
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String peerId,
  ) => queries.run(() => super.getConversationThreadSummary(peerId));
}

class _Calls implements OrbitCallActivitySource {
  _Calls(this.queries);
  final _SerialQueries queries;
  final events = StreamController<void>.broadcast();
  Completer<void>? _holdNext;
  Completer<void>? _started;
  Completer<void> holdNextLookup() {
    _started = Completer<void>();
    return _holdNext = Completer<void>();
  }

  bool get heldLookupStarted => _started?.isCompleted ?? false;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<Map<String, ConversationCallTimelineEntry>> latestCallsForContacts(
    Iterable<String> ids,
  ) async {
    final hold = _holdNext;
    _holdNext = null;
    if (hold != null) {
      _started!.complete();
      await hold.future;
    }
    return queries.run(() async => {});
  }

  @override
  Future<Map<String, int>> unreadCallCountsForContacts(Iterable<String> ids) =>
      queries.run(() async => {});
}

class _Harness {
  _Harness({this.finalContactPurge = false});

  final bool finalContactPurge;
  final queries = _SerialQueries();
  late final contacts =
      (finalContactPurge
            ? _PurgeContacts(queries, messages)
            : _Contacts(queries))
        ..seed([_friend]);
  late final messages = _Messages(queries);
  late final calls = _Calls(queries);
  late final listener = _Listener(messageRepo: messages, contactRepo: contacts);
  final bridge = FakeBridge();
  final p2p = FakeP2PService();
  final requests = FakeContactRequestRepository();
  late final requestListener = ContactRequestListener(
    contactRequestStream: const Stream.empty(),
    requestRepo: requests,
    contactRepo: contacts,
    bridge: bridge,
    getOwnPeerId: () => 'self',
  );

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => '/tmp/orbit-refresh-ordering',
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await messages.saveMessage(_message);
    final identity = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OrbitWired(
          identityRepo: identity,
          contactRepo: contacts,
          contactRequestRepo: requests,
          contactRequestListener: requestListener,
          messageRepo: messages,
          mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
          chatMessageListener: listener,
          bridge: bridge,
          p2pService: p2p,
          mediaFileManager: FakeMediaFileManager(),
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
            compressVideo:
                ({required path, required compress, onProgress}) async => null,
          ),
          feedClearedRepository: InMemoryFeedClearedRepository(),
          callActivitySource: calls,
        ),
      ),
    );
    await drain(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await listener.incoming.close();
      await messages.removals.close();
      await calls.events.close();
      listener.dispose();
      requestListener.dispose();
      bridge.dispose();
      p2p.dispose();
    });
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openExternalConversation(WidgetTester tester) async {
    final orbit = tester.widget<OrbitWired>(find.byType(OrbitWired));
    final navigator = Navigator.of(tester.element(find.byType(OrbitWired)));
    final contact = (await contacts.getContact('friend'))!;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ConversationWired(
            contact: contact,
            identityRepo: orbit.identityRepo,
            messageRepo: messages,
            chatMessageListener: listener,
            p2pService: p2p,
            bridge: bridge,
            contactRepo: contacts,
            mediaAttachmentRepo: orbit.mediaAttachmentRepo,
            mediaFileManager: orbit.mediaFileManager,
          ),
        ),
      ),
    );
    // Settle the route and its initial read events before deleting the chat.
    await drain(tester);
  }

  OrbitScreen screen(WidgetTester tester) =>
      tester.widget(find.byType(OrbitScreen));
  List<OrbitFriend> active(WidgetTester tester) =>
      screen(tester).headerProjectionListenable.value.allFriends;
  Set<String> circlePeers(WidgetTester tester) => screen(tester)
      .headerProjectionListenable
      .value
      .innerItems
      .whereType<OrbitFriendItem>()
      .map((item) => item.friend.peerId)
      .toSet();
  OrbitFriend friend(WidgetTester tester, [String peerId = 'friend']) =>
      active(tester).singleWhere((entry) => entry.peerId == peerId);
  void fullRefresh() => calls.events.add(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadOrbitMenuFont);

  for (final blocked in [false, true]) {
    testWidgets(
      'external conversation deletion removes ${blocked ? 'blocked control' : 'ordinary contact'} from retained Orbit projections',
      (tester) async {
        final h = _Harness(finalContactPurge: true);
        if (blocked) {
          await h.contacts.blockContact('friend');
        }
        await h.contacts.addContact(
          _friend.copyWith(peerId: 'other', username: 'Bob'),
        );
        await h.messages.saveMessage(
          _message.copyWith(
            id: 'other-message',
            contactPeerId: 'other',
            senderPeerId: 'other',
          ),
        );
        await h.open(tester);
        expect(h.circlePeers(tester), {if (!blocked) 'friend', 'other'});
        expect(h.active(tester).map((friend) => friend.peerId).toSet(), {
          'friend',
          'other',
        });

        // Notification/Feed-owned routes do not have Orbit's pop-refresh hook.
        await h.openExternalConversation(tester);
        expect(find.byType(ConversationWired), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_vert));
        await h.drain(tester);
        await tester.tap(find.text('Delete chat'));
        await h.drain(tester);
        await tester.tap(find.text('Delete'));
        await h.drain(tester);

        expect(await h.contacts.getContact('friend'), isNull);
        expect(await h.messages.getMessagesForContact('friend'), isEmpty);
        expect(h.messages.publishedRemovals, hasLength(1));
        expect(h.messages.publishedRemovals.single.contactPeerId, 'friend');
        expect(h.messages.publishedRemovals.single.messageId, isNull);
        expect(find.byType(ConversationWired), findsNothing);
        expect(await h.contacts.getContact('other'), isNotNull);
        expect(await h.messages.getMessagesForContact('other'), hasLength(1));
        expect(
          {
            'circle': h.circlePeers(tester),
            'allChats': h
                .screen(tester)
                .listProjectionListenable
                .value
                .allFriends
                .map((friend) => friend.peerId)
                .toSet(),
          },
          {
            'circle': {'other'},
            'allChats': {'other'},
          },
        );
      },
    );
  }

  testWidgets('FIFO completion cannot resurrect a deleted contact', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    h.queries.enabled = true;
    h.listener.incoming.add(_message);
    await h.drain(tester);
    await h.queries.step(); // Old contact read.
    await h.drain(tester);
    final deleted = h.queries.run(() => h.contacts.deleteContact('friend'));
    await h.queries.step(); // Old summary read.
    await h.drain(tester);
    await h.queries.step(); // Deletion commits in FIFO order.
    await deleted;
    h.listener.emitContactUpdate(_friend);
    await h.drain(tester);
    await h.queries.step(); // Old latest-call lookup.
    await h.drain(tester);
    await h.queries.step(); // New contact lookup returns null.
    await h.drain(tester);
    expect(h.active(tester), isEmpty);
    await h.queries.step(); // Old unread-call lookup completes last.
    await h.drain(tester);
    h.queries.enabled = false;
    expect(await h.contacts.getContact('friend'), isNull);
    expect(h.active(tester), isEmpty);
    expect(h.queries.pending, isEmpty);
  });

  testWidgets('an older unread snapshot cannot overwrite a read-clear', (
    tester,
  ) async {
    final h = _Harness();
    await h.open(tester);
    final old = h.calls.holdNextLookup();
    h.listener.incoming.add(_message);
    await h.drain(tester);
    expect(h.calls.heldLookupStarted, isTrue);
    await h.messages.markConversationAsRead('friend');
    await h.drain(tester);
    expect(h.friend(tester).unreadCount, 0);
    old.complete();
    await h.drain(tester);
    expect(h.friend(tester).unreadCount, 0);
  });

  for (final archive in [false, true]) {
    testWidgets(
      'older full load preserves ${archive ? 'archive' : 'deletion'} and still adds another contact',
      (tester) async {
        final h = _Harness();
        await h.open(tester);
        await h.contacts.addContact(
          _friend.copyWith(peerId: 'other', username: 'Bob'),
        );
        final old = h.calls.holdNextLookup();
        h.fullRefresh();
        await h.drain(tester);
        expect(h.calls.heldLookupStarted, isTrue);
        if (archive) {
          await h.contacts.addContact(_friend.copyWith(isArchived: true));
        } else {
          await h.contacts.deleteContact('friend');
        }
        h.listener.emitContactUpdate(_friend);
        await h.drain(tester);
        expect(h.active(tester), isEmpty);
        old.complete();
        await h.drain(tester);
        expect(h.active(tester).map((entry) => entry.peerId), ['other']);
        expect(
          h.screen(tester).listProjectionListenable.value.archivedCount,
          archive ? 1 : 0,
        );
      },
    );
  }

  for (final firstIsFull in [false, true]) {
    testWidgets(
      'new full roster supersedes older ${firstIsFull ? 'full' : 'single-contact'} snapshot',
      (tester) async {
        final h = _Harness();
        await h.open(tester);
        final old = h.calls.holdNextLookup();
        if (firstIsFull) {
          h.fullRefresh();
        } else {
          h.listener.incoming.add(_message);
        }
        await h.drain(tester);
        expect(h.calls.heldLookupStarted, isTrue);
        await h.contacts.addContact(_friend.copyWith(username: 'New name'));
        h.fullRefresh();
        await h.drain(tester);
        expect(h.friend(tester).username, 'New name');
        old.complete();
        await h.drain(tester);
        expect(h.friend(tester).username, 'New name');
      },
    );
  }

  testWidgets(
    'refreshing another peer does not discard a valid pending snapshot',
    (tester) async {
      final h = _Harness();
      await h.open(tester);
      final other = _friend.copyWith(peerId: 'other', username: 'Bob');
      await h.contacts.addContact(other);
      h.fullRefresh();
      await h.drain(tester);
      final secondMessage = _message.copyWith(id: 'second-unread');
      await h.messages.saveMessage(secondMessage);
      final old = h.calls.holdNextLookup();
      h.listener.incoming.add(secondMessage);
      await h.drain(tester);
      expect(h.calls.heldLookupStarted, isTrue);
      await h.contacts.addContact(other.copyWith(username: 'New Bob'));
      h.listener.emitContactUpdate(other);
      await h.drain(tester);
      expect(h.friend(tester, 'other').username, 'New Bob');
      old.complete();
      await h.drain(tester);
      expect(h.friend(tester).unreadCount, 2);
      expect(h.friend(tester, 'other').username, 'New Bob');
    },
  );
}
