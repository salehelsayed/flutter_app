import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
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
  }) => fixture.repo.saveAttachment(
    MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 100,
      mediaType: 'image',
      downloadStatus: 'done',
      localPath: '/media/$id.jpg',
      createdAt: '2026-07-10T00:00:00.000Z',
    ),
    owner: owner,
  );

  String oldV1Cursor({
    required String timestamp,
    required String messageId,
    required String attachmentId,
  }) => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'scopeKind': 'group',
        'scopeId': 'announcement-1',
        'kind': 'visual',
        'bookmarkedOnly': false,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  test(
    'AML-02 incoming only SQL and cursors exclude outgoing before limit without breaking defaults',
    () async {
      const incomingNewTimestamp = '2026-07-10T11:00:00.000Z';
      const incomingOldTimestamp = '2026-07-10T10:00:00.000Z';

      // Newer outgoing announcement rows deliberately fill a limit-1 page.
      // The incoming-only request must still return the older incoming row,
      // proving direction is applied in SQL before LIMIT rather than after.
      for (final parent in [
        ('outgoing-new', '2026-07-10T13:00:00.000Z', false),
        ('outgoing-old', '2026-07-10T12:00:00.000Z', false),
        ('incoming-new', incomingNewTimestamp, true),
        ('incoming-old', incomingOldTimestamp, true),
      ]) {
        await fixture.seedGroupParent(
          parent.$1,
          groupId: 'announcement-1',
          timestamp: parent.$2,
        );
        if (!parent.$3) {
          await fixture.db.update(
            'group_messages',
            {'is_incoming': 0},
            where: 'id = ?',
            whereArgs: [parent.$1],
          );
        }
        await saveVisual(
          id: 'att-${parent.$1}',
          messageId: parent.$1,
          owner: MediaOwnerLane.group,
        );
      }

      // Production-authority noise: wrong group, durable tombstone, a
      // same-parent-id direct sibling, and an unresolved legacy row.
      await fixture.seedGroupParent(
        'other-group',
        groupId: 'announcement-2',
        timestamp: '2026-07-10T15:00:00.000Z',
      );
      await saveVisual(
        id: 'att-other-group',
        messageId: 'other-group',
        owner: MediaOwnerLane.group,
      );

      await fixture.seedGroupParent(
        'tombstoned',
        groupId: 'announcement-1',
        timestamp: '2026-07-10T14:00:00.000Z',
      );
      await saveVisual(
        id: 'att-tombstoned',
        messageId: 'tombstoned',
        owner: MediaOwnerLane.group,
      );
      await dbDeleteGroupMessage(fixture.db, 'tombstoned');

      await fixture.seedDirectParent(
        'incoming-new',
        contactPeerId: 'contact-noise',
        timestamp: '2026-07-10T16:00:00.000Z',
      );
      await saveVisual(
        id: 'att-direct-same-parent',
        messageId: 'incoming-new',
        owner: MediaOwnerLane.direct,
      );
      await fixture.seedDirectParent(
        'direct-outgoing',
        contactPeerId: 'contact-noise',
        timestamp: '2026-07-10T18:00:00.000Z',
      );
      await fixture.db.update(
        'messages',
        {'is_incoming': 0},
        where: 'id = ?',
        whereArgs: ['direct-outgoing'],
      );
      await saveVisual(
        id: 'att-direct-outgoing',
        messageId: 'direct-outgoing',
        owner: MediaOwnerLane.direct,
      );

      await fixture.seedGroupParent(
        'unresolved-parent',
        groupId: 'announcement-1',
        timestamp: '2026-07-10T17:00:00.000Z',
      );
      await saveVisual(
        id: 'att-unresolved',
        messageId: 'unresolved-parent',
        owner: MediaOwnerLane.group,
      );
      await fixture.db.update(
        'media_attachments',
        {'owner_lane': 'unresolved'},
        where: 'id = ?',
        whereArgs: ['att-unresolved'],
      );

      const scope = MediaLibraryScope.group('announcement-1');
      const incomingOnly = MediaLibraryFilter(incomingOnly: true);

      final incomingPage = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        filter: incomingOnly,
        limit: 1,
      );
      expect(incomingPage.entries.map((entry) => entry.attachment.id), [
        'att-incoming-new',
      ]);
      expect(incomingPage.nextCursor, isNotNull);
      final incomingSecondPage = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        filter: incomingOnly,
        cursor: incomingPage.nextCursor,
      );
      expect(incomingSecondPage.entries.map((entry) => entry.attachment.id), [
        'att-incoming-old',
      ]);

      final defaults = await fixture.repo.getMediaLibraryPage(scope: scope);
      expect(defaults.entries.map((entry) => entry.attachment.id), [
        'att-outgoing-new',
        'att-outgoing-old',
        'att-incoming-new',
        'att-incoming-old',
      ]);

      // The helper applies the same parent-direction predicate to its direct
      // parent lane while preserving that lane's default mixed-direction
      // behavior.
      const directScope = MediaLibraryScope.direct('contact-noise');
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: directScope,
        )).entries.map((entry) => entry.attachment.id),
        ['att-direct-outgoing', 'att-direct-same-parent'],
      );
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: directScope,
          filter: incomingOnly,
        )).entries.map((entry) => entry.attachment.id),
        ['att-direct-same-parent'],
      );

      // A v1 cursor has no direction dimension and remains valid only for
      // the backward-compatible incomingOnly=false query identity.
      final legacyPage = await fixture.repo.getMediaLibraryPage(
        scope: scope,
        cursor: oldV1Cursor(
          timestamp: '2026-07-10T13:00:00.000Z',
          messageId: 'outgoing-new',
          attachmentId: 'att-outgoing-new',
        ),
      );
      expect(legacyPage.entries.map((entry) => entry.attachment.id), [
        'att-outgoing-old',
        'att-incoming-new',
        'att-incoming-old',
      ]);

      final defaultCursor = (await fixture.repo.getMediaLibraryPage(
        scope: scope,
        limit: 1,
      )).nextCursor!;
      final incomingCursor = incomingPage.nextCursor!;

      // Destroy the parent table before signature checks: ArgumentError can
      // only win if true/false cursor mismatches are rejected before DB SQL.
      await fixture.db.execute('DROP TABLE group_messages');
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: scope,
          filter: incomingOnly,
          cursor: defaultCursor,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: scope,
          cursor: incomingCursor,
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => fixture.repo.getMediaLibraryPage(
          scope: scope,
          filter: incomingOnly,
          cursor: oldV1Cursor(
            timestamp: '2026-07-10T13:00:00.000Z',
            messageId: 'outgoing-new',
            attachmentId: 'att-outgoing-new',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
