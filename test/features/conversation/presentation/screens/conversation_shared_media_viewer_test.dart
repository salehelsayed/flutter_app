import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/repositories/strict_direct_media_library_repository.dart';

const String kContactPeerId = '12D3KooWViewerContactPeer';

void main() {
  MediaLibraryEntry makeEntry(
    String attachmentId, {
    String? messageId,
    String parentTimestamp = '2026-02-11T10:00:00.000Z',
    String mediaType = 'image',
    String? localPath = 'media/present.jpg',
    String downloadStatus = 'done',
  }) {
    return makeDirectLibraryEntry(
      attachmentId,
      contactPeerId: kContactPeerId,
      messageId: messageId,
      parentTimestamp: parentTimestamp,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
    );
  }

  Finder tile(String attachmentId) =>
      find.byKey(ValueKey('shared-media-tile-$attachmentId'));

  Widget buildLibraryApp(
    StrictDirectMediaLibraryRepository repo, {
    DirectMediaLibraryEgressDispatch? dispatchEgress,
    DirectMediaLibraryDeleteDispatch? dispatchDelete,
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
      expect(
        egressCalls.single.destination,
        MediaEgressDestination.share,
      );

      // Swiping to the next page updates identity/metadata to THAT item —
      // never retained from the first parent message.
      await tester.fling(
        find.byType(PageView),
        const Offset(-400, 0),
        1000,
      );
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

    await tester.tap(find.byKey(const ValueKey('media_action_bookmark')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(repo.bookmarkCalls, [(id: 'wa', bookmarked: true)]);

    // ── Save prompts for a destination, then dispatches the exact current
    // item to the chosen destination once.
    await tester.tap(find.byKey(const ValueKey('media_action_save')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('direct-media-save-files')),
    );
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
    expect(find.byKey(const ValueKey('media_action_result_failure')), findsOneWidget);
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
