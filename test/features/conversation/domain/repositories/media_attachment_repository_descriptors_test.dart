import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';

import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';

/// A secure key store that fails loudly if anything reads from it. The
/// metadata-only descriptor path must never hydrate a key (129 plan INV-8 +
/// the hot-path perf goal), so a single read here is a test failure.
class _ReadForbiddenSecureKeyStore implements SecureKeyStore {
  int readCount = 0;

  @override
  Future<String?> read(String key) async {
    readCount++;
    throw StateError('getMediaPreviewDescriptors must not read the key store');
  }

  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
  @override
  Future<bool> containsKey(String key) async => false;
}

void main() {
  late List<Map<String, Object?>> rows;
  late _ReadForbiddenSecureKeyStore secureKeyStore;
  late MediaAttachmentRepositoryImpl repo;

  setUp(() {
    rows = [];
    secureKeyStore = _ReadForbiddenSecureKeyStore();
    // Only dbLoadMediaForMessages is exercised by the descriptor path; the
    // other db hooks must never be reached, so they throw if invoked.
    repo = MediaAttachmentRepositoryImpl(
      dbSaveMediaAttachmentPreservingLocalState: (_) async =>
          throw UnimplementedError(),
      dbLoadMediaForMessage: (_, _) async => throw UnimplementedError(),
      dbLoadMediaById: (_) async => throw UnimplementedError(),
      dbLoadMediaForMessages: (messageIds, ownerLane) async => rows
          .where(
            (row) =>
                messageIds.contains(row['message_id']) &&
                row['owner_lane'] == ownerLane,
          )
          .toList(),
      dbUpdateMediaLocalPath: (_, _, _) async => throw UnimplementedError(),
      dbUpdateMediaDownloadStatus: (_, _) async => throw UnimplementedError(),
      dbDeleteMediaForMessage: (_, _) async => throw UnimplementedError(),
      dbDeleteMediaForContact: (_) async => throw UnimplementedError(),
      dbMarkUploadPendingAttachmentsFailedForMessage: (_, _) async =>
          throw UnimplementedError(),
      dbLoadPendingMediaDownloads: () async => throw UnimplementedError(),
      dbLoadUploadPendingAttachments:
          ({int limit = 50, required String ownerLane}) async =>
              throw UnimplementedError(),
      dbSetMediaBookmarked: (_, _) async => throw UnimplementedError(),
      dbUpdateMediaPlaybackPosition: (_, _) async =>
          throw UnimplementedError(),
      dbLoadMediaLibraryPage:
          ({
            required String scopeKind,
            required String scopeId,
            required List<String> mediaTypes,
            required bool bookmarkedOnly,
            required bool incomingOnly,
            required int limit,
            String? afterTimestamp,
            String? afterMessageId,
            String? afterAttachmentId,
          }) async => throw UnimplementedError(),
      secureKeyStore: secureKeyStore,
    );
  });

  Map<String, Object?> row({
    required String id,
    required String messageId,
    required String mime,
    required String mediaType,
    String? encryptionKeyBase64,
  }) {
    final map = MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 1000,
      mediaType: mediaType,
      downloadStatus: 'done',
      createdAt: '2026-02-20T10:00:00.000Z',
      encryptionKeyBase64: encryptionKeyBase64,
      ownerLane: MediaOwnerLane.direct,
    ).toMap();
    return map;
  }

  group('getMediaPreviewDescriptors', () {
    test('returns empty map for empty ids', () async {
      expect(
        await repo.getMediaPreviewDescriptors(
          [],
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
    });

    test('single image -> image/count 1, not GIF, not mixed', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.type, 'image');
      expect(d.count, 1);
      expect(d.isGif, isFalse);
      expect(d.isMixed, isFalse);
    });

    test('voice note -> audio/count 1', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'audio/mp4', mediaType: 'audio'),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.type, 'audio');
      expect(d.count, 1);
    });

    test('animated image -> isGif true', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'image/gif', mediaType: 'image'),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.type, 'image');
      expect(d.isGif, isTrue);
    });

    test('multiple images -> count > 1, type image', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'),
      );
      rows.add(
        row(id: 'b2', messageId: 'm1', mime: 'image/png', mediaType: 'image'),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.type, 'image');
      expect(d.count, 2);
      expect(d.isMixed, isFalse);
    });

    test('mixed types -> isMixed, null type', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'),
      );
      rows.add(
        row(id: 'b2', messageId: 'm1', mime: 'video/mp4', mediaType: 'video'),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.isMixed, isTrue);
      expect(d.type, isNull);
      expect(d.count, 2);
    });

    test('groups by message id across the batch', () async {
      rows.add(
        row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'),
      );
      rows.add(
        row(id: 'b2', messageId: 'm2', mime: 'audio/mp4', mediaType: 'audio'),
      );

      final result = await repo.getMediaPreviewDescriptors(
        ['m1', 'm2'],
        owner: MediaOwnerLane.direct,
      );

      expect(result['m1']!.type, 'image');
      expect(result['m2']!.type, 'audio');
    });

    test('never hydrates the secure key store (INV-8 + perf)', () async {
      // An encrypted attachment whose key lives only as a secure-store
      // reference: getAttachmentsForMessages would read it, but the descriptor
      // path must not — it never needs the key to render a label.
      rows.add(
        row(
          id: 'b1',
          messageId: 'm1',
          mime: 'image/jpeg',
          mediaType: 'image',
          encryptionKeyBase64: secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName('b1'),
          ),
        ),
      );

      final d = (await repo.getMediaPreviewDescriptors(
        ['m1'],
        owner: MediaOwnerLane.direct,
      ))['m1']!;

      expect(d.type, 'image');
      expect(secureKeyStore.readCount, 0);
    });
  });

  // --- 228 TC-228-12 ---

  group('media library page plumbing', () {
    test(
      'media library aliases index and hydration preserve keys without '
      'exposing them',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        final capturedEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(capturedEvents.add);
        try {
          // The intended bookmark index exists with the exact column order.
          final indexInfo = await fixture.db.rawQuery(
            'PRAGMA index_info(idx_media_attachments_owner_bookmark_message)',
          );
          final ordered = [...indexInfo]..sort(
            (a, b) => ((a['seqno'] as num).toInt()).compareTo(
              (b['seqno'] as num).toInt(),
            ),
          );
          expect(ordered.map((r) => r['name']).toList(), [
            'owner_lane',
            'is_bookmarked',
            'message_id',
          ]);

          // Collision fixture: the same parent id in both lanes; the direct
          // attachment is encrypted with a secure-store key.
          await fixture.seedDirectParent(
            'msg-shared',
            timestamp: '2026-07-01T10:00:00.000Z',
          );
          await fixture.seedGroupParent('msg-shared');
          const mediaKey = 'library-media-key-base64';
          await fixture.repo.saveAttachment(
            MediaAttachment(
              id: 'att-lib',
              messageId: 'msg-shared',
              mime: 'image/jpeg',
              size: 77,
              mediaType: 'image',
              downloadStatus: 'done',
              localPath: '/media/att-lib.jpg',
              createdAt: '2026-07-01T00:00:01.000Z',
              encryptionKeyBase64: mediaKey,
              encryptionNonce: 'library-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.direct,
          );
          await fixture.repo.saveAttachment(
            MediaAttachment(
              id: 'att-lib-group',
              messageId: 'msg-shared',
              mime: 'image/jpeg',
              size: 88,
              mediaType: 'image',
              downloadStatus: 'done',
              createdAt: '2026-07-01T00:00:02.000Z',
            ),
            owner: MediaOwnerLane.group,
          );

          final page = await fixture.repo.getMediaLibraryPage(
            scope: const MediaLibraryScope.direct('contact-1'),
          );

          // Aliased mapping: attachment fields come from the aliased
          // attachment columns despite duplicate id/created_at/timestamp
          // fields on the joined parent row.
          final entry = page.entries.single;
          expect(entry.attachment.id, 'att-lib');
          expect(entry.attachment.messageId, 'msg-shared');
          expect(entry.attachment.createdAt, '2026-07-01T00:00:01.000Z');
          expect(entry.parentTimestamp, '2026-07-01T10:00:00.000Z');
          expect(entry.parentSenderPeerId, 'contact-1');
          expect(entry.attachment.ownerLane, MediaOwnerLane.direct);

          // Hydration: the page attachment is decryptable (key hydrated from
          // the secure store), while the RAW row still holds only a
          // reference.
          expect(entry.attachment.encryptionKeyBase64, mediaKey);
          expect(entry.attachment.hasEncryptionMetadata, isTrue);
          final raw = await fixture.rawAttachmentRow('att-lib');
          expect(
            isSecureStoreReference(raw!['encryption_key_base64'] as String?),
            isTrue,
          );

          // No emitted flow event carries the key or nonce anywhere in its
          // payload.
          final allEventsJson = jsonEncode(capturedEvents);
          expect(allEventsJson, isNot(contains(mediaKey)));
          expect(allEventsJson, isNot(contains('library-nonce')));
        } finally {
          debugSetFlowEventSink(null);
          await fixture.dispose();
        }
      },
    );
  });
}
