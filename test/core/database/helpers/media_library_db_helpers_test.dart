import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
  // 228 TC-228-06/07/09: scoped shared-media-library pages over a REAL
  // database built through the shared production registry.
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  Future<void> saveVisual({
    required String id,
    required String messageId,
    required MediaOwnerLane owner,
    String mediaType = 'image',
    String mime = 'image/jpeg',
    String createdAt = '2026-07-01T00:00:01.000Z',
  }) async {
    await fixture.repo.saveAttachment(
      MediaAttachment(
        id: id,
        messageId: messageId,
        mime: mime,
        size: 100,
        mediaType: mediaType,
        downloadStatus: 'done',
        localPath: '/media/$id',
        createdAt: createdAt,
      ),
      owner: owner,
    );
  }

  test(
    'direct scope is owner isolated and excludes hidden and deleted parents',
    () async {
      // Live, hidden and deleted direct parents for contact-1; a live parent
      // for contact-2; and a same-ID group parent with a group attachment.
      await fixture.seedDirectParent(
        'msg-live',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.seedDirectParent(
        'msg-hidden',
        timestamp: '2026-07-01T11:00:00.000Z',
        hiddenAt: '2026-07-02T00:00:00.000Z',
      );
      await fixture.seedDirectParent(
        'msg-deleted',
        timestamp: '2026-07-01T12:00:00.000Z',
        deletedAt: '2026-07-02T00:00:00.000Z',
      );
      await fixture.seedDirectParent(
        'msg-other-contact',
        contactPeerId: 'contact-2',
        timestamp: '2026-07-01T13:00:00.000Z',
      );
      await fixture.seedGroupParent('msg-live');

      await saveVisual(
        id: 'att-live',
        messageId: 'msg-live',
        owner: MediaOwnerLane.direct,
      );
      await saveVisual(
        id: 'att-hidden',
        messageId: 'msg-hidden',
        owner: MediaOwnerLane.direct,
      );
      await saveVisual(
        id: 'att-deleted',
        messageId: 'msg-deleted',
        owner: MediaOwnerLane.direct,
      );
      await saveVisual(
        id: 'att-other-contact',
        messageId: 'msg-other-contact',
        owner: MediaOwnerLane.direct,
      );
      // Same-ID group sibling and an audio row that is not visual media.
      await saveVisual(
        id: 'att-group-sibling',
        messageId: 'msg-live',
        owner: MediaOwnerLane.group,
      );
      await fixture.repo.saveAttachment(
        MediaAttachment(
          id: 'att-audio',
          messageId: 'msg-live',
          mime: 'audio/mp4',
          size: 10,
          mediaType: 'audio',
          downloadStatus: 'done',
          createdAt: '2026-07-01T00:00:02.000Z',
        ),
        owner: MediaOwnerLane.direct,
      );

      final page = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.direct('contact-1'),
      );

      expect(page.entries.map((e) => e.attachment.id), ['att-live']);
      final entry = page.entries.single;
      // Aliased parent metadata maps correctly despite duplicate column
      // names (both tables have id/created_at/timestamp-like fields).
      expect(entry.parentTimestamp, '2026-07-01T10:00:00.000Z');
      expect(entry.attachment.messageId, 'msg-live');
      expect(entry.attachment.ownerLane, MediaOwnerLane.direct);
      expect(entry.attachment.createdAt, '2026-07-01T00:00:01.000Z');
      expect(page.nextCursor, isNull);
    },
  );

  test(
    'group scope is owner isolated and respects durable deletion tombstones',
    () async {
      await fixture.seedGroupParent(
        'msg-g1',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.seedGroupParent(
        'msg-g2',
        timestamp: '2026-07-01T11:00:00.000Z',
      );
      await fixture.seedGroupParent(
        'msg-other-group',
        groupId: 'group-2',
        timestamp: '2026-07-01T12:00:00.000Z',
      );
      // Same-ID direct parent + direct attachment (must never surface).
      await fixture.seedDirectParent('msg-g1');

      await saveVisual(
        id: 'att-g1',
        messageId: 'msg-g1',
        owner: MediaOwnerLane.group,
      );
      await saveVisual(
        id: 'att-g2',
        messageId: 'msg-g2',
        owner: MediaOwnerLane.group,
      );
      await saveVisual(
        id: 'att-other-group',
        messageId: 'msg-other-group',
        owner: MediaOwnerLane.group,
      );
      await saveVisual(
        id: 'att-direct-sibling',
        messageId: 'msg-g1',
        owner: MediaOwnerLane.direct,
      );

      final before = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.group('group-1'),
      );
      expect(
        before.entries.map((e) => e.attachment.id),
        ['att-g2', 'att-g1'],
      );

      // Real deletion workflow: records a durable tombstone AND deletes the
      // parent row.
      await dbDeleteGroupMessage(fixture.db, 'msg-g2');
      final afterDelete = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.group('group-1'),
      );
      expect(
        afterDelete.entries.map((e) => e.attachment.id),
        ['att-g1'],
      );

      // A replayed/reinserted parent stays invisible: the tombstone anti-join
      // outlives the parent row.
      await fixture.seedGroupParent(
        'msg-g2',
        timestamp: '2026-07-01T11:00:00.000Z',
      );
      final afterReinsert = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.group('group-1'),
      );
      expect(
        afterReinsert.entries.map((e) => e.attachment.id),
        ['att-g1'],
      );
    },
  );

  test(
    'keyset cursor binds scope filters and enforces the 100 row ceiling',
    () async {
      // Tied parent timestamps force the messageId/attachmentId tie-breakers.
      const tiedTs = '2026-07-01T10:00:00.000Z';
      for (final msgId in ['msg-a', 'msg-b', 'msg-c']) {
        await fixture.seedDirectParent(msgId, timestamp: tiedTs);
      }
      await fixture.seedGroupParent('msg-g', timestamp: tiedTs);

      // Two attachments per message; mixed image/video; some bookmarked.
      // INSERTION order is deliberately the REVERSE of the expected keyset
      // order (suffix 'a' saved before 'z', messages a->c), so an ordering
      // that silently falls back to rowid/insertion order cannot pass.
      for (final msgId in ['msg-a', 'msg-b', 'msg-c']) {
        for (final suffix in ['a', 'z']) {
          await saveVisual(
            id: 'att-$msgId-$suffix',
            messageId: msgId,
            owner: MediaOwnerLane.direct,
            mediaType: suffix == 'z' ? 'video' : 'image',
            mime: suffix == 'z' ? 'video/mp4' : 'image/jpeg',
          );
        }
      }
      final expectedOrder = <String>[
        for (final msgId in ['msg-c', 'msg-b', 'msg-a']) // messageId DESC
          for (final suffix in ['z', 'a']) // attachmentId DESC per message
            'att-$msgId-$suffix',
      ];
      await saveVisual(
        id: 'att-group-noise',
        messageId: 'msg-g',
        owner: MediaOwnerLane.group,
      );
      await fixture.repo.setBookmarked('att-msg-b-a', bookmarked: true);

      const scope = MediaLibraryScope.direct('contact-1');

      // Page through with limit 2: concatenated pages equal the unique
      // (timestamp DESC, messageId DESC, attachmentId DESC) order.
      final collected = <String>[];
      String? cursor;
      var pages = 0;
      do {
        final page = await fixture.repo.getMediaLibraryPage(
          scope: scope,
          limit: 2,
          cursor: cursor,
        );
        collected.addAll(page.entries.map((e) => e.attachment.id));
        cursor = page.nextCursor;
        pages += 1;
        expect(pages, lessThan(10), reason: 'pagination must terminate');
      } while (cursor != null);
      expect(collected, expectedOrder);

      // Filters: image-only, video-only, bookmarked-only.
      final images = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        filter: const MediaLibraryFilter(kind: MediaLibraryKind.image),
      );
      expect(
        images.entries.every((e) => e.attachment.mediaType == 'image'),
        isTrue,
      );
      expect(images.entries, hasLength(3));
      final videos = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        filter: const MediaLibraryFilter(kind: MediaLibraryKind.video),
      );
      expect(videos.entries, hasLength(3));
      final bookmarked = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        filter: const MediaLibraryFilter(bookmarkedOnly: true),
      );
      expect(
        bookmarked.entries.map((e) => e.attachment.id),
        ['att-msg-b-a'],
      );

      // Cursor is bound to scope AND filter signature: reuse elsewhere fails
      // with a typed argument error BEFORE any SQL runs.
      final firstPage = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        limit: 2,
      );
      final boundCursor = firstPage.nextCursor!;
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: const MediaLibraryScope.group('group-1'),
          cursor: boundCursor,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: scope,
          filter: const MediaLibraryFilter(kind: MediaLibraryKind.video),
          cursor: boundCursor,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: scope,
          cursor: 'not-a-cursor',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Limit contract: 1 and 100 work; 0 and 101 fail before SQL.
      expect(kMediaLibraryMaxPageSize, 100);
      final one = await fixture.repo.getMediaLibraryPage(scope: scope, limit: 1);
      expect(one.entries, hasLength(1));
      final hundred = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        limit: 100,
      );
      expect(hundred.entries, hasLength(6));
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(scope: scope, limit: 0),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(scope: scope, limit: 101),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
