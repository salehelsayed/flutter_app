import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_batch_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_library_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _hash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test(
    'GPL-09A stale ordinary library entries cannot bookmark batch or egress a current private parent',
    () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);

      const timestamps = <String, String>{
        'private-parent': '2026-07-12T15:00:00.000Z',
        'unsupported-parent': '2026-07-12T14:00:00.000Z',
        'corrupt-parent': '2026-07-12T13:00:00.000Z',
        'ordinary-new': '2026-07-12T12:00:00.000Z',
        'ordinary-old': '2026-07-12T11:00:00.000Z',
      };
      for (final entry in timestamps.entries) {
        await fixture.seedGroupParent(
          entry.key,
          groupId: 'group-a',
          timestamp: entry.value,
        );
        await fixture.repo.saveAttachment(
          _attachment('att-${entry.key}', entry.key),
          owner: MediaOwnerLane.group,
        );
      }
      await fixture.db.update(
        'group_messages',
        {
          'media_policy_version': 1,
          'media_lifecycle': 'view_once',
          'media_protected': 1,
          'media_received_at': 1_800_000_000_000,
        },
        where: 'id = ?',
        whereArgs: ['private-parent'],
      );
      await fixture.db.update(
        'group_messages',
        {
          'media_policy_version': 9,
          'media_lifecycle': 'unsupported',
          'media_protected': 1,
        },
        where: 'id = ?',
        whereArgs: ['unsupported-parent'],
      );
      await fixture.db.update(
        'group_messages',
        {'media_cleanup_pending': 1},
        where: 'id = ?',
        whereArgs: ['corrupt-parent'],
      );

      final page = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.group('group-a'),
        limit: 2,
      );
      expect(page.entries.map((entry) => entry.attachment.id), <String>[
        'att-ordinary-new',
        'att-ordinary-old',
      ]);

      // Same message ID in the direct table plus an unresolved legacy row are
      // siblings, not authority for the exact group bookmark write.
      await fixture.seedDirectParent('ordinary-new');
      await fixture.repo.saveAttachment(
        _attachment('direct-sibling', 'ordinary-new'),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        _attachment('unresolved-sibling', 'ordinary-new'),
        owner: MediaOwnerLane.direct,
      );
      await fixture.db.update(
        'media_attachments',
        {'owner_lane': 'unresolved'},
        where: 'id = ?',
        whereArgs: ['unresolved-sibling'],
      );

      expect(
        await fixture.repo.setGroupBookmarkedIfOrdinary(
          groupId: 'group-a',
          messageId: 'private-parent',
          attachmentId: 'att-private-parent',
          bookmarked: true,
        ),
        isFalse,
      );
      expect(
        await fixture.repo.setGroupBookmarkedIfOrdinary(
          groupId: 'group-a',
          messageId: 'ordinary-new',
          attachmentId: 'att-ordinary-new',
          bookmarked: true,
        ),
        isTrue,
      );
      final bookmarkRows = await fixture.db.query(
        'media_attachments',
        columns: const ['id', 'owner_lane', 'is_bookmarked'],
        where: 'message_id = ?',
        whereArgs: ['ordinary-new'],
        orderBy: 'id',
      );
      expect(
        {
          for (final row in bookmarkRows)
            row['id'] as String: (row['owner_lane'], row['is_bookmarked']),
        },
        <String, (Object?, Object?)>{
          'att-ordinary-new': ('group', 1),
          'direct-sibling': ('direct', 0),
          'unresolved-sibling': ('unresolved', 0),
        },
      );

      // A controller loaded while the row was ordinary delegates to the exact
      // atomic capability. A now-private refusal does not use the generic
      // ID-only writer or update its stale cache.
      final staleLibrary = _StaleLibraryRepository(
        _entry(_attachment('stale-att', 'stale-parent')),
      );
      final controller = GroupSharedMediaLibraryController(
        groupId: 'group-a',
        libraryRepository: staleLibrary,
        stateRepository: staleLibrary,
      );
      await controller.loadNextPage();
      expect(
        await controller.setBookmarked('stale-att', bookmarked: true),
        isFalse,
      );
      expect(staleLibrary.groupBookmarkCalls, 1);
      expect(staleLibrary.genericBookmarkCalls, 0);
      expect(controller.entries, isEmpty);

      final messages = InMemoryGroupMessageRepository();
      await messages.saveMessage(
        _message(const GroupPrivateMediaPolicy.viewOnce()),
      );
      final media = InMemoryMediaAttachmentRepository();
      await media.saveAttachment(
        _attachment('stale-att', 'stale-parent'),
        owner: MediaOwnerLane.group,
      );
      final egress = _RecordingEgressService();
      var clearCalls = 0;
      final batch = GroupSharedMediaBatchActionsCoordinator(
        messageRepository: messages,
        mediaAttachmentRepository: media,
        egressService: egress,
        mediaFileManager: FakeMediaFileManager(),
        fileExists: (_) async => true,
        stateRepository: staleLibrary,
        clearLocalCopy:
            ({required scope, required attachmentId, required mime}) async {
              clearCalls++;
              return MediaClearLocalCopyResult.cleared;
            },
      );
      const identity = GroupSharedMediaIdentity(
        groupId: 'group-a',
        messageId: 'stale-parent',
        attachmentId: 'stale-att',
      );
      final bookmark = await batch.performBatchBookmark(
        identities: const [identity],
        bookmarked: true,
      );
      final clear = await batch.performBatchClear(identities: const [identity]);
      final exported = await batch.performBatchEgress(
        identities: const [identity],
        destination: MediaEgressDestination.files,
      );
      expect(bookmark.failedIds, {'stale-att'});
      expect(clear.failedIds, {'stale-att'});
      expect(exported.failedIds, {'stale-att'});
      expect(
        exported.items.single.denial,
        GroupSharedMediaPreflightDenial.lifecycleRestricted,
      );
      expect(staleLibrary.groupBookmarkCalls, 1);
      expect(staleLibrary.genericBookmarkCalls, 0);
      expect(clearCalls, 0);
      expect(egress.calls, 0);

      final delete = _RecordingDeleteCoordinator();
      final deleted = await deleteGroupSharedMediaSelection(
        identities: const [identity],
        messageRepository: messages,
        coordinator: delete,
      );
      expect(deleted.failedAttachmentIds, {'stale-att'});
      expect(delete.calls, 0);
    },
  );

  testWidgets(
    'GPL-09V stale ordinary Shared Media requalifies before thumbnail or viewer exposure',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('gpl-09v-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File('${temp.path}/stale.jpg')..writeAsBytesSync(<int>[0]);

      Future<void> expectDeniedBeforeDisplay(
        GroupPrivateMediaPolicy currentPolicy,
        String suffix,
      ) async {
        final qualificationGate = Completer<void>();
        final qualifications = <GroupSharedMediaIdentity>[];
        final staleLibrary = _StaleLibraryRepository(
          _entry(
            _attachment(
              'stale-att-$suffix',
              'stale-parent-$suffix',
            ).copyWith(localPath: image.path),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupSharedMediaLibraryScreen(
              groupId: 'group-a',
              libraryRepository: staleLibrary,
              stateRepository: staleLibrary,
              qualifyViewerEntry: (identity) async {
                qualifications.add(identity);
                await qualificationGate.future;
                return currentPolicy.isOrdinary;
              },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(qualifications, hasLength(1));
        expect(find.byType(MediaGridCell), findsNothing);
        expect(find.byType(MediaThumbnailImage), findsNothing);
        expect(find.byType(FullScreenTypedMediaViewer), findsNothing);

        qualificationGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(MediaGridCell), findsNothing);
        expect(find.byType(MediaThumbnailImage), findsNothing);
        expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      }

      await expectDeniedBeforeDisplay(
        const GroupPrivateMediaPolicy.viewOnce(),
        'private',
      );
      await expectDeniedBeforeDisplay(
        const GroupPrivateMediaPolicy.unsupported(sourceVersion: 9),
        'unsupported',
      );

      var currentPolicy = const GroupPrivateMediaPolicy.ordinary();
      final qualificationGate = Completer<void>();
      final qualifications = <GroupSharedMediaIdentity>[];
      final ordinaryLibrary = _StaleLibraryRepository(
        _entry(
          _attachment(
            'stale-att-ordinary',
            'stale-parent-ordinary',
          ).copyWith(localPath: image.path),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupSharedMediaLibraryScreen(
            groupId: 'group-a',
            libraryRepository: ordinaryLibrary,
            stateRepository: ordinaryLibrary,
            qualifyViewerEntry: (identity) async {
              qualifications.add(identity);
              await qualificationGate.future;
              return currentPolicy.isOrdinary;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(qualifications, hasLength(1));
      expect(find.byType(MediaGridCell), findsNothing);
      expect(find.byType(MediaThumbnailImage), findsNothing);

      qualificationGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MediaGridCell), findsOneWidget);
      expect(find.byType(MediaThumbnailImage), findsOneWidget);

      currentPolicy = const GroupPrivateMediaPolicy.viewOnce();
      tester
          .widget<GestureDetector>(
            find.byKey(
              const ValueKey(
                'media-grid-cell-stale-parent-ordinary-stale-att-ordinary',
              ),
            ),
          )
          .onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(qualifications, hasLength(2));
      expect(qualifications.last.groupId, 'group-a');
      expect(qualifications.last.messageId, 'stale-parent-ordinary');
      expect(qualifications.last.attachmentId, 'stale-att-ordinary');
      expect(find.byType(MediaGridCell), findsNothing);
      expect(find.byType(MediaThumbnailImage), findsNothing);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
    },
  );

  testWidgets(
    'GPL-09W Shared Media viewer withholds pending sibling metadata and preserves qualified pagination',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('gpl-09w-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final safePath = '${temp.path}/safe.jpg';
      final privatePath = '${temp.path}/PRIVATE-SIBLING.webp';
      final pagedPath = '${temp.path}/paged.jpg';
      File(safePath).writeAsBytesSync(<int>[0]);
      File(privatePath).writeAsBytesSync(<int>[0]);
      File(pagedPath).writeAsBytesSync(<int>[0]);

      final safeEntry = _entry(
        _attachment('safe-att', 'safe-parent').copyWith(localPath: safePath),
      );
      final pendingPrivateEntry = _entry(
        _attachment(
          'private-att',
          'private-parent',
        ).copyWith(mime: 'image/webp', localPath: privatePath, size: 987654),
      );
      final pagedOrdinaryEntry = _entry(
        _attachment('paged-att', 'paged-parent').copyWith(localPath: pagedPath),
      );
      final repository = _PagedStaleLibraryRepository(
        firstPage: [safeEntry, pendingPrivateEntry],
        secondPage: [pagedOrdinaryEntry],
      );
      final privateQualification = Completer<void>();
      addTearDown(() {
        if (!privateQualification.isCompleted) {
          privateQualification.complete();
        }
      });

      Future<bool> qualify(GroupSharedMediaIdentity identity) async {
        if (identity.messageId == 'private-parent') {
          await privateQualification.future;
          return false;
        }
        return true;
      }

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupSharedMediaLibraryScreen(
            groupId: 'group-a',
            libraryRepository: repository,
            stateRepository: repository,
            qualifyViewerEntry: qualify,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (find
            .byKey(const ValueKey('media-grid-cell-safe-parent-safe-att'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      expect(
        find.byKey(const ValueKey('media-grid-cell-safe-parent-safe-att')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('media-grid-cell-private-parent-private-att'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('media-grid-cell-safe-parent-safe-att')),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        final viewers = find.byType(FullScreenTypedMediaViewer);
        if (viewers.evaluate().isNotEmpty) {
          final viewer = tester.widget<FullScreenTypedMediaViewer>(viewers);
          if (viewer.items.any((item) => item.attachmentId == 'paged-att')) {
            break;
          }
        }
      }

      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items.map((item) => item.attachmentId), [
        'safe-att',
        'paged-att',
      ]);
      expect(
        viewer.items.any(
          (item) =>
              item.attachmentId == 'private-att' ||
              item.localPath == privatePath ||
              item.mime == 'image/webp' ||
              item.sizeBytes == 987654,
        ),
        isFalse,
      );
      expect(repository.requestedCursors, [null, 'page-2']);

      privateQualification.complete();
      await tester.pump(const Duration(milliseconds: 50));
      final afterDenial = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(afterDenial.items.map((item) => item.attachmentId), [
        'safe-att',
        'paged-att',
      ]);
    },
  );
}

class _StaleLibraryRepository
    implements
        MediaLibraryRepository,
        MediaLibraryStateRepository,
        GroupMediaLibraryStateRepository {
  _StaleLibraryRepository(this.entry);

  final MediaLibraryEntry entry;
  int genericBookmarkCalls = 0;
  int groupBookmarkCalls = 0;

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async => MediaLibraryPage(entries: [entry], nextCursor: null);

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) async {
    genericBookmarkCalls++;
  }

  @override
  Future<bool> setGroupBookmarkedIfOrdinary({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  }) async {
    groupBookmarkCalls++;
    return false;
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) async {}
}

class _PagedStaleLibraryRepository extends _StaleLibraryRepository {
  _PagedStaleLibraryRepository({
    required this.firstPage,
    required this.secondPage,
  }) : super(firstPage.first);

  final List<MediaLibraryEntry> firstPage;
  final List<MediaLibraryEntry> secondPage;
  final List<String?> requestedCursors = [];

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    requestedCursors.add(cursor);
    return cursor == null
        ? MediaLibraryPage(entries: firstPage, nextCursor: 'page-2')
        : MediaLibraryPage(entries: secondPage, nextCursor: null);
  }
}

class _RecordingEgressService extends ReceivedMediaEgressService {
  int calls = 0;

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls++;
    return MediaEgressResult(
      requestId: requestId,
      outcome: MediaEgressOutcome.saved,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

class _RecordingDeleteCoordinator implements GroupMediaDeleteForMeCoordinator {
  int calls = 0;

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    calls++;
  }
}

GroupMessage _message(GroupPrivateMediaPolicy policy) => GroupMessage(
  id: 'stale-parent',
  groupId: 'group-a',
  senderPeerId: 'peer-a',
  text: '',
  timestamp: DateTime.utc(2026, 7, 12),
  privateMediaPolicy: policy,
  createdAt: DateTime.utc(2026, 7, 12),
);

MediaLibraryEntry _entry(MediaAttachment attachment) => MediaLibraryEntry(
  attachment: attachment.copyWith(ownerLane: MediaOwnerLane.group),
  parentTimestamp: '2026-07-12T15:00:00.000Z',
  parentSenderPeerId: 'peer-a',
);

MediaAttachment _attachment(String id, String messageId) => MediaAttachment(
  id: id,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 128,
  mediaType: 'image',
  localPath: 'media/group-a/$id.jpg',
  downloadStatus: 'done',
  createdAt: '2026-07-12T00:00:00.000Z',
  contentHash: _hash,
  encryptionKeyBase64: 'a2V5',
  encryptionNonce: 'bm9uY2U=',
  encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
);
