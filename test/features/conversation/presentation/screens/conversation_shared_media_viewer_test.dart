import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/repositories/strict_direct_media_library_repository.dart';

const String kContactPeerId = '12D3KooWViewerContactPeer';

void main() {
  MediaLibraryEntry makeEntry(
    String attachmentId, {
    String? messageId,
    String parentTimestamp = '2026-02-11T10:00:00.000Z',
    String mediaType = 'image',
    String mime = 'image/jpeg',
    String? localPath = 'media/present.jpg',
    String downloadStatus = 'done',
    int size = 3,
    int? width,
    int? height,
    int? durationMs,
    String? parentSenderPeerId = kContactPeerId,
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
  }) {
    final resolvedMessageId = messageId ?? 'msg-of-$attachmentId';
    return MediaLibraryEntry(
      attachment: MediaAttachment(
        id: attachmentId,
        messageId: resolvedMessageId,
        mime: mime,
        size: size,
        mediaType: mediaType,
        width: width,
        height: height,
        durationMs: durationMs,
        localPath: localPath,
        downloadStatus: downloadStatus,
        createdAt: parentTimestamp,
        ownerLane: ownerLane,
      ),
      parentTimestamp: parentTimestamp,
      parentSenderPeerId: parentSenderPeerId,
    );
  }

  Finder tile(String attachmentId) =>
      find.byKey(ValueKey('shared-media-tile-$attachmentId'));

  Widget buildLibraryApp(
    StrictDirectMediaLibraryRepository repo, {
    DirectMediaLibraryEgressDispatch? dispatchEgress,
    DirectMediaLibraryDeleteDispatch? dispatchDelete,
    DirectPrivateMediaActionDecisionLoader? loadActionDecision,
    void Function(Set<String>)? onMessagesDeleted,
  }) {
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
        loadActionDecision: loadActionDecision,
        dispatchEgress: dispatchEgress,
        dispatchDelete: dispatchDelete,
        onMessagesDeleted: onMessagesDeleted,
      ),
    );
  }

  DirectMediaLibraryBatchResult successResult(
    List<DirectReceivedMediaActionIdentity> identities,
    MediaEgressDestination destination,
  ) {
    return DirectMediaLibraryBatchResult(
      items: [
        for (final identity in identities)
          DirectMediaLibraryBatchItemOutcome(
            attachmentId: identity.attachmentId,
            itemOutcome: MediaEgressItemOutcome.saved,
            succeeded: true,
          ),
      ],
      egressResult: MediaEgressResult(
        requestId: 'req-viewer',
        outcome: destination == MediaEgressDestination.share
            ? MediaEgressOutcome.presented
            : MediaEgressOutcome.saved,
        items: const [],
      ),
    );
  }

  testWidgets(
    'library opens cross-message typed viewer at exact attachment identity',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      // Three entries from three DIFFERENT parent messages, two sharing a
      // local path — identity must come from the attachment/message ids.
      repo.seedPage(
        entries: [
          makeEntry('va', messageId: 'msg-a', localPath: 'media/shared.jpg'),
          makeEntry('vb', messageId: 'msg-b', localPath: 'media/shared.jpg'),
          makeEntry('vc', messageId: 'msg-c'),
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
        buildLibraryApp(
          repo,
          dispatchEgress: (identities, destination) async {
            egressCalls.add((identities: identities, destination: destination));
            return successResult(identities, destination);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Tap the SECOND tile: the viewer must open at exactly that
      // attachment, not at the first item and not at a same-path neighbor.
      await tester.tap(tile('vb'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);

      // The current-item action carries the exact tapped identity.
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(egressCalls, hasLength(1));
      expect(egressCalls.single.identities.single.attachmentId, 'vb');
      expect(egressCalls.single.identities.single.messageId, 'msg-b');
      expect(egressCalls.single.destination, MediaEgressDestination.share);

      // Swiping to the next page updates identity/metadata to THAT item —
      // never retained from the first parent message.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('3 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(egressCalls, hasLength(2));
      expect(egressCalls.last.identities.single.attachmentId, 'vc');
      expect(egressCalls.last.identities.single.messageId, 'msg-c');
    },
  );

  testWidgets(
    'direct Shared Media hides automatic metadata for image and video pages while GIF remains visible',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final incomingImage = makeEntry(
        'hidden-library-incoming',
        messageId: 'message-library-incoming',
        parentTimestamp: '2026-04-11T10:11:00.000Z',
        mime: 'image/x-library-incoming-306',
        localPath: 'media/library-incoming.jpg',
        size: 101,
        width: 301,
        height: 201,
      );
      final outgoingImage = makeEntry(
        'hidden-library-outgoing',
        messageId: 'message-library-outgoing',
        parentTimestamp: '2026-04-12T12:13:00.000Z',
        mime: 'image/x-library-outgoing-306',
        localPath: 'media/library-outgoing.jpg',
        size: 202,
        width: 302,
        height: 202,
        parentSenderPeerId: '12D3KooWViewerOwnPeer',
      );
      final visibleGif = makeEntry(
        'visible-library-gif',
        messageId: 'message-library-gif',
        parentTimestamp: '2026-04-13T14:15:00.000Z',
        mime: 'image/gif',
        localPath: 'media/library.gif',
        size: 303,
        width: 303,
        height: 203,
      );
      final incomingVideo = makeEntry(
        'hidden-library-incoming-video-312',
        messageId: 'message-library-incoming-video-312',
        parentTimestamp: '2026-04-14T16:17:00.000Z',
        mediaType: 'video',
        mime: 'video/x-library-incoming-312',
        localPath: 'media/library-incoming-312.mp4',
        size: 404,
        durationMs: 61000,
      );
      final outgoingVideo = makeEntry(
        'hidden-library-outgoing-video-312',
        messageId: 'message-library-outgoing-video-312',
        parentTimestamp: '2026-04-15T18:19:00.000Z',
        mediaType: 'video',
        mime: 'video/x-library-outgoing-312',
        localPath: 'media/library-outgoing-312.mp4',
        size: 505,
        durationMs: 62000,
        parentSenderPeerId: '12D3KooWViewerOwnPeer',
      );
      final entries = [
        incomingImage,
        outgoingImage,
        visibleGif,
        incomingVideo,
        outgoingVideo,
      ];
      final byAttachmentId = {
        for (final entry in entries) entry.attachment.id: entry,
      };
      final egressCalls =
          <
            ({
              List<DirectReceivedMediaActionIdentity> identities,
              MediaEgressDestination destination,
            })
          >[];
      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      )..seedPage(entries: entries, nextCursor: null);

      await tester.pumpWidget(
        buildLibraryApp(
          repo,
          loadActionDecision: (identity) async {
            final entry = byAttachmentId[identity.attachmentId]!;
            final isIncoming = entry.parentSenderPeerId == kContactPeerId;
            final parent = ConversationMessage(
              id: identity.messageId,
              contactPeerId: kContactPeerId,
              senderPeerId: isIncoming
                  ? kContactPeerId
                  : '12D3KooWViewerOwnPeer',
              text: '',
              timestamp: entry.parentTimestamp,
              status: 'delivered',
              isIncoming: isIncoming,
              createdAt: entry.parentTimestamp,
              media: [entry.attachment],
              privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
            );
            return DirectPrivateMediaActionEligibility.evaluate(
              parent: parent,
              attachment: entry.attachment,
              expectedMessageId: identity.messageId,
              expectedAttachmentId: identity.attachmentId,
              requireIncoming: false,
            );
          },
          dispatchEgress: (identities, destination) async {
            egressCalls.add((identities: identities, destination: destination));
            return successResult(identities, destination);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(tile(incomingImage.attachment.id));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items, hasLength(5));
      for (final entry in entries) {
        final item = viewer.items.singleWhere(
          (candidate) => candidate.attachmentId == entry.attachment.id,
        );
        expect(item.messageId, entry.attachment.messageId);
        expect(item.owner, MediaOwnerLane.direct);
        expect(item.mime, entry.attachment.mime);
        expect(item.sizeBytes, entry.attachment.size);
        expect(item.width, entry.attachment.width);
        expect(item.height, entry.attachment.height);
        expect(item.durationMs, entry.attachment.durationMs);
        expect(item.timestamp, DateTime.tryParse(entry.parentTimestamp));
        expect(
          item.senderLabel,
          entry.parentSenderPeerId == kContactPeerId ? 'Alice' : null,
        );
      }
      expect(viewer.items.map((item) => item.kind), [
        MediaViewerKind.image,
        MediaViewerKind.image,
        MediaViewerKind.gif,
        MediaViewerKind.video,
        MediaViewerKind.video,
      ]);

      String renderedTimestamp(String isoTimestamp) {
        final value = DateTime.parse(isoTimestamp).toLocal();
        String two(int part) => part.toString().padLeft(2, '0');
        return '${value.year}-${two(value.month)}-${two(value.day)} '
            '${two(value.hour)}:${two(value.minute)}';
      }

      const detailKeys = <String>[
        'media_meta_sender',
        'media_meta_timestamp',
        'media_meta_mime',
        'media_meta_size',
        'media_meta_dimensions',
        'media_meta_duration',
      ];
      void expectHiddenDetails(
        MediaLibraryEntry entry, {
        required String renderedSize,
        required String renderedShape,
      }) {
        for (final key in detailKeys) {
          expect(
            find.byKey(ValueKey(key)),
            findsNothing,
            reason: '$key leaked for ${entry.attachment.id}',
          );
        }
        final hiddenValues = <String>[
          if (entry.parentSenderPeerId == kContactPeerId) 'Alice',
          renderedTimestamp(entry.parentTimestamp),
          entry.attachment.mime,
          renderedSize,
          renderedShape,
        ];
        for (final value in hiddenValues) {
          expect(find.text(value), findsNothing);
          expect(
            find.semantics.byLabel(RegExp(RegExp.escape(value))),
            findsNothing,
          );
        }
        expect(
          find.byKey(const ValueKey('media_viewer_metadata_content')),
          findsNothing,
        );
      }

      String visibleMetadata(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).data!;

      expectHiddenDetails(
        incomingImage,
        renderedSize: '101 B',
        renderedShape: '301 × 201',
      );
      expect(find.byKey(const ValueKey('media_action_share')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        egressCalls.single.identities.single.attachmentId,
        incomingImage.attachment.id,
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2 / 5'), findsOneWidget);
      expectHiddenDetails(
        outgoingImage,
        renderedSize: '202 B',
        renderedShape: '302 × 202',
      );
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        egressCalls.last.identities.single.attachmentId,
        outgoingImage.attachment.id,
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('3 / 5'), findsOneWidget);
      expect(visibleMetadata('media_meta_sender'), 'Alice');
      expect(
        visibleMetadata('media_meta_timestamp'),
        renderedTimestamp(visibleGif.parentTimestamp),
      );
      expect(visibleMetadata('media_meta_mime'), 'image/gif');
      expect(visibleMetadata('media_meta_size'), '303 B');
      expect(visibleMetadata('media_meta_dimensions'), '303 × 203');

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('4 / 5'), findsOneWidget);
      expectHiddenDetails(
        incomingVideo,
        renderedSize: '404 B',
        renderedShape: '1:01',
      );
      expect(
        viewer.items
            .singleWhere(
              (item) => item.attachmentId == incomingVideo.attachment.id,
            )
            .showMetadataDetails,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        egressCalls.last.identities.single.attachmentId,
        incomingVideo.attachment.id,
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('5 / 5'), findsOneWidget);
      expectHiddenDetails(
        outgoingVideo,
        renderedSize: '505 B',
        renderedShape: '1:02',
      );
      expect(
        viewer.items
            .singleWhere(
              (item) => item.attachmentId == outgoingVideo.attachment.id,
            )
            .showMetadataDetails,
        isFalse,
      );

      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('4 / 5'), findsOneWidget);
      expectHiddenDetails(
        incomingVideo,
        renderedSize: '404 B',
        renderedShape: '1:01',
      );

      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('3 / 5'), findsOneWidget);
      expect(visibleMetadata('media_meta_mime'), 'image/gif');
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stale Shared Media parent is revalidated and removed before viewer entry',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      final staleEntry = makeEntry(
        'stale-private',
        messageId: 'msg-stale-private',
      );
      repo.seedPage(entries: [staleEntry], nextCursor: null);
      final currentParent = ConversationMessage(
        id: 'msg-stale-private',
        contactPeerId: kContactPeerId,
        senderPeerId: kContactPeerId,
        text: 'SECRET stale caption',
        timestamp: '2026-02-11T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-11T10:00:01.000Z',
        privateMediaPolicy: const PrivateMediaPolicy.protected(),
        privateMediaState: PrivateMediaLifecycleState.available,
      );
      var decisionLoads = 0;

      await tester.pumpWidget(
        buildLibraryApp(
          repo,
          loadActionDecision: (identity) async {
            decisionLoads++;
            return DirectPrivateMediaActionEligibility.evaluate(
              parent: currentParent,
              attachment: staleEntry.attachment,
              expectedMessageId: identity.messageId,
              expectedAttachmentId: identity.attachmentId,
            );
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(tile('stale-private'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(decisionLoads, 1);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      expect(tile('stale-private'), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewer continuation keeps direct cursor signature fenced and current item stable',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      repo.seedPage(
        entries: [for (var i = 1; i <= 6; i++) makeEntry('c0$i')],
        nextCursor: 'page-c1',
      );
      // The continuation page overlaps c01: it must appear exactly once.
      repo.seedPage(
        cursor: 'page-c1',
        entries: [makeEntry('c07'), makeEntry('c01'), makeEntry('c08')],
        nextCursor: null,
      );

      await tester.pumpWidget(buildLibraryApp(repo));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.pageCalls, hasLength(1));

      // Open near the boundary, then gate the continuation request.
      repo.gateRequests = true;
      await tester.tap(tile('c04'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('4 / 6'), findsOneWidget);

      // Being near the boundary issued exactly ONE cursor-bound request.
      expect(repo.pageCalls, hasLength(2));
      expect(repo.pageCalls.last.cursor, 'page-c1');
      expect(repo.pageCalls.last.filter, const MediaLibraryFilter());

      // Duplicate boundary signals while the request is in flight must NOT
      // issue another call.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('5 / 6'), findsOneWidget);
      expect(
        repo.pageCalls,
        hasLength(2),
        reason: 'in-flight continuation must be fenced',
      );

      // Release: the page appends behind the CURRENT item — identity and
      // position are preserved, the duplicate id appears once.
      repo.gates[0].complete();
      repo.gateRequests = false;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('5 / 8'), findsOneWidget);

      // Swipe forward through the appended items: c07 then c08 — the
      // overlapping c01 was deduplicated (8 pages, not 9).
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('6 / 8'), findsOneWidget);

      // The exhausted chain issues no further requests.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('7 / 8'), findsOneWidget);
      expect(repo.pageCalls, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'later Shared Media page requalifies PiP true while protected media stays false',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      final firstPage = [
        for (var i = 1; i <= 4; i++)
          makeEntry('initial-$i', messageId: 'initial-message-$i'),
      ];
      final eligibleVideo = makeEntry(
        'later-eligible-video',
        messageId: 'later-eligible-message',
        mediaType: 'video',
        localPath: 'media/later-eligible.mp4',
      );
      final protectedVideo = makeEntry(
        'later-protected-video',
        messageId: 'later-protected-message',
        mediaType: 'video',
        localPath: 'media/later-protected.mp4',
      );
      repo.seedPage(entries: firstPage, nextCursor: 'later-page');
      repo.seedPage(
        cursor: 'later-page',
        entries: [eligibleVideo, protectedVideo],
        nextCursor: null,
      );
      final entriesByAttachmentId = {
        for (final entry in [...firstPage, eligibleVideo, protectedVideo])
          entry.attachment.id: entry,
      };
      final qualifiedAttachmentIds = <String>[];

      await tester.pumpWidget(
        buildLibraryApp(
          repo,
          loadActionDecision: (identity) async {
            qualifiedAttachmentIds.add(identity.attachmentId);
            final entry = entriesByAttachmentId[identity.attachmentId]!;
            final isProtected =
                identity.attachmentId == protectedVideo.attachment.id;
            final parent = ConversationMessage(
              id: identity.messageId,
              contactPeerId: kContactPeerId,
              senderPeerId: kContactPeerId,
              text: isProtected ? 'private' : 'ordinary',
              timestamp: entry.parentTimestamp,
              status: 'delivered',
              isIncoming: true,
              createdAt: entry.parentTimestamp,
              privateMediaPolicy: isProtected
                  ? const PrivateMediaPolicy.protected()
                  : const PrivateMediaPolicy.ordinary(),
              privateMediaState: isProtected
                  ? PrivateMediaLifecycleState.available
                  : PrivateMediaLifecycleState.none,
            );
            return DirectPrivateMediaActionEligibility.evaluate(
              parent: parent,
              attachment: entry.attachment,
              expectedMessageId: identity.messageId,
              expectedAttachmentId: identity.attachmentId,
            );
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Index 1 is inside the continuation threshold for a four-item page.
      await tester.tap(tile('initial-2'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      final eligible = viewer.items.singleWhere(
        (item) => item.attachmentId == eligibleVideo.attachment.id,
      );
      expect(eligible.canEnterPictureInPicture, isTrue);
      expect(
        viewer.items.any(
          (item) => item.attachmentId == protectedVideo.attachment.id,
        ),
        isFalse,
        reason: 'a protected continuation parent must be reconciled, not shown',
      );
      expect(
        qualifiedAttachmentIds,
        containsAll(<String>[
          eligibleVideo.attachment.id,
          protectedVideo.attachment.id,
        ]),
      );
      expect(repo.pageCalls, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('in-viewer current item actions execute across parent messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = StrictDirectMediaLibraryRepository(
      expectedContactPeerId: kContactPeerId,
    );
    repo.seedPage(
      entries: [
        makeEntry('wa', messageId: 'msg-live'),
        makeEntry('wb', messageId: 'msg-missing'),
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
    final deleteCalls = <List<DirectReceivedMediaActionIdentity>>[];
    final deletedNotifications = <Set<String>>[];

    await tester.pumpWidget(
      buildLibraryApp(
        repo,
        dispatchEgress: (identities, destination) async {
          egressCalls.add((identities: identities, destination: destination));
          return successResult(identities, destination);
        },
        dispatchDelete: (identities) async {
          deleteCalls.add(identities);
          // msg-live resolves and deletes; msg-missing is a typed failure
          // with zero deletions.
          final messageIds = identities.map((i) => i.messageId).toSet();
          if (messageIds.contains('msg-missing')) {
            return DirectMediaLibraryBatchDeleteOutcome(
              deletedMessageIds: const {},
              failedMessageIds: messageIds,
              deletedAttachmentIds: const {},
              failedAttachmentIds: identities
                  .map((i) => i.attachmentId)
                  .toSet(),
            );
          }
          return DirectMediaLibraryBatchDeleteOutcome(
            deletedMessageIds: messageIds,
            failedMessageIds: const {},
            deletedAttachmentIds: identities.map((i) => i.attachmentId).toSet(),
            failedAttachmentIds: const {},
          );
        },
        onMessagesDeleted: deletedNotifications.add,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // ── Bookmark executes for the exact current item through the real
    // ID-based state API.
    await tester.tap(tile('wa'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('media_action_more')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('media_action_bookmark')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.bookmarkCalls, [(id: 'wa', bookmarked: true)]);

    // ── Save prompts for a destination, then dispatches the exact current
    // item to the chosen destination once.
    await tester.tap(find.byKey(const ValueKey('media_action_save')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('direct-media-save-files')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(egressCalls, hasLength(1));
    expect(egressCalls.single.identities.single.attachmentId, 'wa');
    expect(egressCalls.single.destination, MediaEgressDestination.files);

    // ── Swipe: delete now targets the SECOND item's parent. Cancelling the
    // confirmation performs zero delete dispatches.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media_action_delete')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('shared-media-delete-cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(deleteCalls, isEmpty);

    // Confirmed delete of the missing parent: exactly one dispatch, a
    // truthful failure, no entry removal, no deleted notification.
    await tester.tap(find.byKey(const ValueKey('media_action_delete')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('shared-media-delete-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(deleteCalls, hasLength(1));
    expect(deleteCalls.single.single.messageId, 'msg-missing');
    expect(deleteCalls.single.single.attachmentId, 'wb');
    expect(
      find.byKey(const ValueKey('media_action_result_failure')),
      findsOneWidget,
    );
    expect(deletedNotifications, isEmpty);
    expect(find.text('2 / 2'), findsOneWidget);

    // ── Swipe back: confirmed delete of the LIVE parent dispatches once for
    // exactly that identity, reconciles the library and notifies the owner.
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media_action_delete')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('shared-media-delete-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(deleteCalls, hasLength(2));
    expect(deleteCalls.last.single.messageId, 'msg-live');
    expect(deleteCalls.last.single.attachmentId, 'wa');
    expect(deletedNotifications, [
      {'msg-live'},
    ]);
    // The viewer closed onto the reconciled grid: wa is gone, wb remains.
    expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
    expect(tile('wa'), findsNothing);
    expect(tile('wb'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
