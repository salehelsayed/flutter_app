import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_controller.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../domain/repositories/strict_direct_media_library_repository.dart';

const String kContactPeerId = '12D3KooWLibraryContactPeer';
const String kOwnPeerId = '12D3KooWLibraryOwnPeer';

class _FakeIdentityRepository implements IdentityRepository {
  _FakeIdentityRepository(this.identity);

  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: kOwnPeerId);

  @override
  void dispose() {}

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;
}

void main() {
  ContactModel makeContact() => ContactModel(
    peerId: kContactPeerId,
    publicKey: 'pub',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-02-11T10:00:00.000Z',
  );

  IdentityModel makeIdentity() => IdentityModel(
    peerId: kOwnPeerId,
    publicKey: 'pub',
    privateKey: 'priv',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: 'Me',
    createdAt: '2026-02-11T09:00:00.000Z',
    updatedAt: '2026-02-11T09:00:00.000Z',
  );

  MediaLibraryEntry makeEntry(
    String attachmentId, {
    String? messageId,
    String parentTimestamp = '2026-02-11T10:00:00.000Z',
    String mediaType = 'image',
    String? localPath,
    String downloadStatus = 'done',
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
    bool bookmarked = false,
  }) {
    return makeDirectLibraryEntry(
      attachmentId,
      contactPeerId: kContactPeerId,
      messageId: messageId,
      parentTimestamp: parentTimestamp,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      ownerLane: ownerLane,
      bookmarked: bookmarked,
    );
  }

  Finder tile(String attachmentId) =>
      find.byKey(ValueKey('shared-media-tile-$attachmentId'));

  List<String> builtTileIds(WidgetTester tester) {
    return tester
        .widgetList(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'shared-media-tile-',
                ),
          ),
        )
        .map(
          (w) => (w.key as ValueKey<String>).value.substring(
            'shared-media-tile-'.length,
          ),
        )
        .toList();
  }

  Widget buildLibraryApp(StrictDirectMediaLibraryRepository repo) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DirectSharedMediaLibraryScreen(
        contactPeerId: kContactPeerId,
        contactUsername: 'Alice',
        libraryRepository: repo,
        stateRepository: repo,
        fileExists: (_) => true,
        resolveStoredPath: (storedPath) => storedPath,
      ),
    );
  }

  testWidgets(
    'direct chat opens one strict contact scoped shared media library',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The factory is strict: a non-direct lane, an own-peer/wrong-contact
      // scope id, a non-50 limit, or a foreign cursor throws instead of
      // returning rows.
      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      repo.seedPage(entries: [makeEntry('att-open-1')]);

      final messageRepo = InMemoryMessageRepository();
      final contactRepo = InMemoryContactRepository();
      contactRepo.addTestContact(makeContact());

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: makeContact(),
            identityRepo: _FakeIdentityRepository(makeIdentity()),
            messageRepo: messageRepo,
            chatMessageListener: ChatMessageListener(
              chatMessageStream: const Stream.empty(),
              messageRepo: messageRepo,
              contactRepo: contactRepo,
            ),
            p2pService: _FakeP2PService(),
            contactRepo: contactRepo,
            mediaAttachmentRepo: repo,
            micPermissionGateway: FakeMicPermissionGateway(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // No library query may run from merely opening the chat.
      expect(repo.pageCalls, isEmpty);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Exactly one localized Shared Media entry.
      const menuKey = ValueKey('conversation-shared-media-action');
      expect(find.byKey(menuKey), findsOneWidget);
      expect(find.text('Shared media'), findsOneWidget);

      await tester.tap(find.byKey(menuKey));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The library route is open and issued exactly one strict direct-scoped
      // request for THIS contact (the strict factory throws on any sibling
      // owner, own-peer id, or defaulted scope).
      expect(find.byType(DirectSharedMediaLibraryScreen), findsOneWidget);
      expect(repo.pageCalls, hasLength(1));
      final call = repo.pageCalls.single;
      expect(call.scope.lane, MediaOwnerLane.direct);
      expect(call.scope.id, kContactPeerId);
      expect(call.limit, kDirectMediaLibraryPageSize);
      expect(call.cursor, isNull);
      expect(tile('att-open-1'), findsOneWidget);
    },
  );

  testWidgets(
    'filters bind direct scope cursor signature and preserve stable paged order',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );

      // Page 0 of All: 30 rows, with a tied-timestamp pair (e02/e03 — the
      // repository's order must be retained verbatim) and a same-path pair
      // (e04/e05 — identity is the attachment ID, never the path).
      const tiedTs = '2026-02-11T10:00:02.000Z';
      final allPage0 = <MediaLibraryEntry>[
        makeEntry('e01', parentTimestamp: '2026-02-11T10:00:03.000Z'),
        makeEntry('e02', parentTimestamp: tiedTs),
        makeEntry('e03', parentTimestamp: tiedTs),
        makeEntry(
          'e04',
          parentTimestamp: '2026-02-11T10:00:01.000Z',
          localPath: 'media/shared-path.jpg',
        ),
        makeEntry(
          'e05',
          parentTimestamp: '2026-02-11T10:00:01.000Z',
          localPath: 'media/shared-path.jpg',
        ),
        for (var i = 6; i <= 30; i++)
          makeEntry(
            'e${i.toString().padLeft(2, '0')}',
            parentTimestamp: '2026-02-11T10:00:00.${(100 - i)}Z',
          ),
      ];
      repo.seedPage(entries: allPage0, nextCursor: 'all-c1');
      // Page 1 of All re-serves e01 (a repository overlap): it must appear
      // exactly once after the append.
      repo.seedPage(
        cursor: 'all-c1',
        entries: [makeEntry('e31'), makeEntry('e01'), makeEntry('e32')],
        nextCursor: null,
      );

      const photosFilter = MediaLibraryFilter(kind: MediaLibraryKind.image);
      const videosFilter = MediaLibraryFilter(kind: MediaLibraryKind.video);
      repo.seedPage(
        filter: photosFilter,
        entries: [makeEntry('stale-photo')],
        nextCursor: null,
      );
      repo.seedPage(
        filter: videosFilter,
        entries: [
          for (var i = 1; i <= 30; i++)
            makeEntry('v${i.toString().padLeft(2, '0')}', mediaType: 'video'),
        ],
        nextCursor: 'vid-c1',
      );
      repo.seedPage(
        filter: videosFilter,
        cursor: 'vid-c1',
        entries: [makeEntry('v31', mediaType: 'video')],
        nextCursor: null,
      );

      await tester.pumpWidget(buildLibraryApp(repo));
      await tester.pump(const Duration(milliseconds: 300));

      // Exactly ONE page was requested — no eager exhaustion of the cursor
      // chain — with the complete default filter signature.
      expect(repo.pageCalls, hasLength(1));
      expect(repo.pageCalls.single.filter, const MediaLibraryFilter());
      expect(repo.pageCalls.single.cursor, isNull);

      // The repository's newest-first order (including the tied pair) is
      // retained verbatim; both same-path tiles render (ID identity).
      final initialOrder = builtTileIds(tester);
      expect(initialOrder.length, greaterThanOrEqualTo(5));
      expect(initialOrder.sublist(0, 5), ['e01', 'e02', 'e03', 'e04', 'e05']);

      // Two filter changes while the All cursor ('all-c1') is still live,
      // with the first (Photos) response arriving AFTER the second (Videos)
      // request: each first page of a filter must start from a null cursor
      // (retaining 'all-c1' across the change throws in the strict repo),
      // and the stale photos page must be discarded, never appended.
      repo.gateRequests = true;
      await tester.tap(
        find.byKey(const ValueKey('shared-media-filter-photos')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('shared-media-filter-videos')),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.pageCalls, hasLength(3));
      expect(repo.pageCalls[1].filter, photosFilter);
      expect(repo.pageCalls[1].cursor, isNull);
      expect(repo.pageCalls[2].filter, videosFilter);
      expect(repo.pageCalls[2].cursor, isNull);

      // Release the STALE photos response first.
      repo.gates[0].complete();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tile('stale-photo'),
        findsNothing,
        reason: 'a response from a superseded filter must be dropped',
      );

      // Release the current videos response.
      repo.gates[1].complete();
      repo.gateRequests = false;
      await tester.pump(const Duration(milliseconds: 200));
      expect(builtTileIds(tester).first, 'v01');
      expect(tile('stale-photo'), findsNothing);

      // Continued paging under the new filter carries the VIDEOS-minted
      // cursor: the strict repository throws if the old all-filter cursor
      // (or any fabricated cursor) is replayed here.
      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, -3000),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.pageCalls, hasLength(4));
      expect(repo.pageCalls.last.filter, videosFilter);
      expect(repo.pageCalls.last.cursor, 'vid-c1');

      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, -600),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tile('v31'), findsOneWidget);
      expect(repo.pageCalls, hasLength(4));

      // Back to All: a fresh null-cursor first page, then a boundary scroll
      // appends exactly the next cursor-bound page without duplicating the
      // overlapping id.
      await tester.tap(find.byKey(const ValueKey('shared-media-filter-all')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.pageCalls, hasLength(5));
      expect(repo.pageCalls.last.filter, const MediaLibraryFilter());
      expect(repo.pageCalls.last.cursor, isNull);

      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, -3000),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.pageCalls, hasLength(6));
      expect(repo.pageCalls.last.cursor, 'all-c1');
      expect(repo.pageCalls.last.filter, const MediaLibraryFilter());

      // Reveal the appended row: the cursor-bound page landed after the drag
      // clamped at the pre-append extent.
      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, -600),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tile('e31'), findsOneWidget);
      expect(tile('e32'), findsOneWidget);
      expect(
        repo.pageCalls,
        hasLength(6),
        reason: 'an exhausted cursor chain must not re-request',
      );

      // The overlapping id from page 1 appears exactly once after the append.
      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, 3000),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tile('e01'), findsOneWidget);
      expect(builtTileIds(tester).sublist(0, 5), [
        'e01',
        'e02',
        'e03',
        'e04',
        'e05',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bookmark uses only current direct page ids and re-reads repository state',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      // The malformed sibling/unresolved rows are leaked by the fake ON
      // PURPOSE: they must fail closed at the controller boundary — never
      // rendered, never selectable, never bookmarked.
      repo.seedPage(
        entries: [
          makeEntry('b1'),
          makeEntry('b2', bookmarked: true),
          makeEntry('g1', ownerLane: MediaOwnerLane.group),
          makeEntry('u1', ownerLane: null),
        ],
        nextCursor: null,
      );

      await tester.pumpWidget(buildLibraryApp(repo));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tile('b1'), findsOneWidget);
      expect(tile('b2'), findsOneWidget);
      expect(tile('g1'), findsNothing);
      expect(tile('u1'), findsNothing);

      // Toggling b1 calls the real ID-based state API exactly once and
      // reconciles the tile in place.
      await tester.tap(find.byKey(const ValueKey('shared-media-bookmark-b1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.bookmarkCalls, [(id: 'b1', bookmarked: true)]);
      expect(
        find.descendant(of: tile('b1'), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget,
      );

      // Out-of-page / malformed provenance fails closed with ZERO writes: an
      // id that never came from this scope's pages and a leaked group row.
      final foreignRepo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      foreignRepo.seedPage(
        entries: [makeEntry('g-leak', ownerLane: MediaOwnerLane.group)],
        nextCursor: null,
      );
      final controller = DirectMediaLibraryController(
        libraryRepository: foreignRepo,
        stateRepository: foreignRepo,
        contactPeerId: kContactPeerId,
      );
      await controller.loadNextPage();
      expect(controller.entries, isEmpty);
      expect(await controller.toggleBookmark('never-on-a-page'), isFalse);
      expect(await controller.toggleBookmark('g-leak'), isFalse);
      expect(foreignRepo.bookmarkCalls, isEmpty);

      // Recreation reads DURABLE state (the repository row), not a
      // controller cache: a fresh screen over the updated rows shows b1
      // bookmarked without any new write.
      repo.seedPage(
        entries: [
          makeEntry('b1', bookmarked: true),
          makeEntry('b2', bookmarked: true),
        ],
        nextCursor: null,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildLibraryApp(repo));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.bookmarkCalls, hasLength(1));
      expect(
        find.descendant(of: tile('b1'), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget,
      );

      // Under the Bookmarked filter, un-bookmarking b1 removes it from the
      // visible list by local reconcile (no refetch) and does NOT disturb
      // the unrelated selection of b2.
      repo.seedPage(
        filter: const MediaLibraryFilter(bookmarkedOnly: true),
        entries: [
          makeEntry('b1', bookmarked: true),
          makeEntry('b2', bookmarked: true),
        ],
        nextCursor: null,
      );
      await tester.tap(
        find.byKey(const ValueKey('shared-media-filter-bookmarked')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tile('b1'), findsOneWidget);

      await tester.longPress(tile('b2'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('shared-media-selected-b2')),
        findsOneWidget,
      );

      final callsBeforeReconcile = repo.pageCalls.length;
      await tester.tap(find.byKey(const ValueKey('shared-media-bookmark-b1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(repo.bookmarkCalls.last, (id: 'b1', bookmarked: false));
      expect(tile('b1'), findsNothing);
      expect(tile('b2'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('shared-media-selected-b2')),
        findsOneWidget,
        reason: 'unrelated selection must survive the bookmark reconcile',
      );
      expect(
        repo.pageCalls.length,
        callsBeforeReconcile,
        reason: 'the active filter reconciles locally, not by refetch',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable direct media is truthful and unresolved never crosses the boundary',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      repo.seedPage(
        entries: [
          makeEntry('ok1', localPath: 'media/ok1.jpg'),
          makeEntry('ev1', downloadStatus: kMediaDownloadStatusEvicted),
          makeEntry('pd1', downloadStatus: 'pending'),
          makeEntry(
            'if1',
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            localPath: 'media/if1.jpg',
          ),
          makeEntry('mi1', localPath: 'media/missing.jpg'),
          makeEntry('g1', ownerLane: MediaOwnerLane.group),
          makeEntry('u1', ownerLane: null),
        ],
        nextCursor: null,
      );

      final egressCalls =
          <
            ({
              List<DirectReceivedMediaActionIdentity> identities,
              MediaEgressDestination destination,
            })
          >[];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectSharedMediaLibraryScreen(
            contactPeerId: kContactPeerId,
            contactUsername: 'Alice',
            libraryRepository: repo,
            stateRepository: repo,
            fileExists: (path) => path != 'media/missing.jpg',
            resolveStoredPath: (storedPath) => storedPath,
            dispatchEgress: (identities, destination) async {
              egressCalls.add((
                identities: identities,
                destination: destination,
              ));
              // Plan-231 qualifier denial: a typed per-item denial with ZERO
              // native egress — the surface must report it truthfully.
              return DirectMediaLibraryBatchResult(
                items: [
                  for (final identity in identities)
                    DirectMediaLibraryBatchItemOutcome(
                      attachmentId: identity.attachmentId,
                      denial: DirectMediaEgressDenial.protected,
                      succeeded: false,
                    ),
                ],
                egressResult: null,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Exact truthful state per representable row.
      expect(
        find.descendant(
          of: tile('ev1'),
          matching: find.text('Local copy removed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('pd1'), matching: find.text('Not downloaded')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile('if1'),
          matching: find.text("Couldn't verify"),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile('mi1'), matching: find.text('File missing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shared-media-state-ok1')),
        findsNothing,
      );
      // Accessibility: the truthful state is part of the tile's semantics.
      final evictedSemantics = tester.getSemantics(tile('ev1'));
      expect(evictedSemantics.label, contains('Photo'));
      expect(evictedSemantics.label, contains('Local copy removed'));

      // Unresolved/group rows never cross the boundary in any state.
      expect(tile('g1'), findsNothing);
      expect(tile('u1'), findsNothing);

      // Opening the library made zero egress dispatches and the surface has
      // no downloader to trigger.
      expect(egressCalls, isEmpty);

      // An unavailable current item keeps every action disabled (fail
      // closed): no dispatch can happen from the viewer.
      await tester.tap(tile('ev1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      final disabledSave = tester.widget<IconButton>(
        find.byKey(const ValueKey('media_action_save')),
      );
      expect(disabledSave.onPressed, isNull);
      await tester.tap(
        find.byKey(const ValueKey('media_action_save')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(egressCalls, isEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));

      // An action-time qualifier denial on an AVAILABLE item is reported
      // truthfully as a failure without inventing a private lifecycle state.
      await tester.tap(tile('ok1'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('direct-media-save-photos')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(egressCalls, hasLength(1));
      expect(egressCalls.single.identities.single.attachmentId, 'ok1');
      expect(
        find.byKey(const ValueKey('media_action_result_failure')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'batch forward stays absent while only draft preflight is landed',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      repo.seedPage(
        entries: [makeEntry('no-forward', localPath: 'media/no-forward.jpg')],
        nextCursor: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectSharedMediaLibraryScreen(
            contactPeerId: kContactPeerId,
            contactUsername: 'Alice',
            libraryRepository: repo,
            stateRepository: repo,
            fileExists: (_) => true,
            resolveStoredPath: (storedPath) => storedPath,
            dispatchEgress: (identities, destination) async =>
                DirectMediaLibraryBatchResult(
                  items: [
                    for (final identity in identities)
                      DirectMediaLibraryBatchItemOutcome(
                        attachmentId: identity.attachmentId,
                        succeeded: true,
                        itemOutcome: MediaEgressItemOutcome.saved,
                      ),
                  ],
                  egressResult: null,
                ),
            dispatchDelete: (identities) async =>
                const DirectMediaLibraryBatchDeleteOutcome(
                  deletedMessageIds: {},
                  failedMessageIds: {},
                  deletedAttachmentIds: {},
                  failedAttachmentIds: {},
                ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.longPress(tile('no-forward'));
      await tester.pump(const Duration(milliseconds: 100));

      for (final key in const [
        'shared-media-action-save',
        'shared-media-action-share',
        'shared-media-action-delete',
        'shared-media-action-goto',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('shared-media-action-forward')),
        findsNothing,
      );
      expect(find.text('Forward'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library is virtualized localized and accessible in small LTR RTL viewports',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A 1,000-entry library served lazily as 20 chained 50-row pages —
      // the plan-228 contract itself caps one page at 100 rows.
      StrictDirectMediaLibraryRepository seedThousand() {
        final repo = StrictDirectMediaLibraryRepository(
          expectedContactPeerId: kContactPeerId,
        );
        for (var page = 0; page < 20; page++) {
          repo.seedPage(
            cursor: page == 0 ? null : 'big-c$page',
            entries: [
              for (var i = 0; i < 50; i++)
                makeEntry(
                  'big-${page * 50 + i}',
                  localPath: 'media/big-${page * 50 + i}.jpg',
                ),
            ],
            nextCursor: page == 19 ? null : 'big-c${page + 1}',
          );
        }
        return repo;
      }

      Widget app(Locale locale, StrictDirectMediaLibraryRepository repo) {
        return MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectSharedMediaLibraryScreen(
            contactPeerId: kContactPeerId,
            contactUsername: 'Alice',
            libraryRepository: repo,
            stateRepository: repo,
            fileExists: (_) => true,
            resolveStoredPath: (storedPath) => storedPath,
            dispatchEgress: (identities, destination) async =>
                DirectMediaLibraryBatchResult(
                  items: [
                    for (final identity in identities)
                      DirectMediaLibraryBatchItemOutcome(
                        attachmentId: identity.attachmentId,
                        succeeded: true,
                        itemOutcome: MediaEgressItemOutcome.saved,
                      ),
                  ],
                  egressResult: null,
                ),
            dispatchDelete: (identities) async =>
                const DirectMediaLibraryBatchDeleteOutcome(
                  deletedMessageIds: {},
                  failedMessageIds: {},
                  deletedAttachmentIds: {},
                  failedAttachmentIds: {},
                ),
          ),
        );
      }

      // ── Virtualization on the big fixture (independent of selection).
      final repo = seedThousand();
      await tester.pumpWidget(app(const Locale('en'), repo));
      await tester.pump(const Duration(milliseconds: 300));

      final builtBefore = builtTileIds(tester).length;
      expect(builtBefore, greaterThan(0));
      expect(
        builtBefore,
        lessThan(40),
        reason: 'a 1,000-entry library must build only the visible window',
      );

      await tester.drag(
        find.byKey(const ValueKey('shared-media-grid')),
        const Offset(0, -4000),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final builtAfter = builtTileIds(tester).length;
      expect(
        builtAfter,
        lessThan(40),
        reason: 'scrolling paginates lazily; earlier rows are released',
      );
      expect(tester.takeException(), isNull);

      // Selection semantics under the ceiling: two selected of the visible
      // window, localized count, selected-state semantics on the tile.
      final semantics = tester.ensureSemantics();
      final built = builtTileIds(tester);
      // Middle of the built window: unlike the leading cache-extent rows,
      // these are genuinely on screen and hit-testable.
      final visibleIds = built.sublist(built.length ~/ 2).take(2).toList();
      for (final id in visibleIds) {
        await tester.longPress(find.byKey(ValueKey('shared-media-tile-$id')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('2 selected'), findsOneWidget);
      final selectedData = tester
          .getSemantics(
            find.byKey(ValueKey('shared-media-tile-${visibleIds.first}')),
          )
          .getSemanticsData();
      expect(selectedData.label, 'Photo');
      final selectedTile = tester.widget<Semantics>(
        find.byKey(ValueKey('shared-media-tile-${visibleIds.first}')),
      );
      expect(selectedTile.properties.selected, isTrue);
      // The action surface stays reachable on the small viewport: every
      // batch action is present inside a horizontally scrollable bar.
      expect(
        find.byKey(const ValueKey('shared-media-selection-actions')),
        findsOneWidget,
      );
      for (final key in const [
        'shared-media-action-save',
        'shared-media-action-share',
        'shared-media-action-delete',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      semantics.dispose();

      // ── German: long labels on the same small viewport, no overflow.
      await tester.pumpWidget(const SizedBox());
      final repoDe = seedThousand();
      await tester.pumpWidget(app(const Locale('de'), repoDe));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Geteilte Medien'), findsOneWidget);
      expect(find.text('Gemerkt'), findsOneWidget);
      final deId = builtTileIds(tester).first;
      await tester.longPress(find.byKey(ValueKey('shared-media-tile-$deId')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('1 ausgewählt'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ── Arabic: RTL directionality, localized chrome, no overflow.
      await tester.pumpWidget(const SizedBox());
      final repoAr = seedThousand();
      await tester.pumpWidget(app(const Locale('ar'), repoAr));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        Directionality.of(
          tester.element(find.byKey(const ValueKey('shared-media-grid'))),
        ),
        TextDirection.rtl,
      );
      expect(find.text('الوسائط المشتركة'), findsOneWidget);
      expect(find.text('المحفوظة'), findsOneWidget);
      final arId = builtTileIds(tester).first;
      await tester.longPress(find.byKey(ValueKey('shared-media-tile-$arId')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('حذف'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
