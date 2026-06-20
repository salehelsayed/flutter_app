import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';

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
      dbInsertMediaAttachment: (_) async => throw UnimplementedError(),
      dbLoadMediaForMessage: (_) async => throw UnimplementedError(),
      dbLoadMediaById: (_) async => throw UnimplementedError(),
      dbLoadMediaForMessages: (messageIds) async => rows
          .where((row) => messageIds.contains(row['message_id']))
          .toList(),
      dbUpdateMediaLocalPath: (_, _, _) async => throw UnimplementedError(),
      dbUpdateMediaDownloadStatus: (_, _) async => throw UnimplementedError(),
      dbDeleteMediaForMessage: (_) async => throw UnimplementedError(),
      dbDeleteMediaForContact: (_) async => throw UnimplementedError(),
      dbMarkUploadPendingAttachmentsFailedForMessage: (_) async =>
          throw UnimplementedError(),
      dbLoadPendingMediaDownloads: () async => throw UnimplementedError(),
      dbLoadUploadPendingAttachments: ({int limit = 50}) async =>
          throw UnimplementedError(),
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
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 1000,
      mediaType: mediaType,
      downloadStatus: 'done',
      createdAt: '2026-02-20T10:00:00.000Z',
      encryptionKeyBase64: encryptionKeyBase64,
    ).toMap();
  }

  group('getMediaPreviewDescriptors', () {
    test('returns empty map for empty ids', () async {
      expect(await repo.getMediaPreviewDescriptors([]), isEmpty);
    });

    test('single image -> image/count 1, not GIF, not mixed', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'));

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.type, 'image');
      expect(d.count, 1);
      expect(d.isGif, isFalse);
      expect(d.isMixed, isFalse);
    });

    test('voice note -> audio/count 1', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'audio/mp4', mediaType: 'audio'));

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.type, 'audio');
      expect(d.count, 1);
    });

    test('animated image -> isGif true', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'image/gif', mediaType: 'image'));

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.type, 'image');
      expect(d.isGif, isTrue);
    });

    test('multiple images -> count > 1, type image', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'));
      rows.add(row(id: 'b2', messageId: 'm1', mime: 'image/png', mediaType: 'image'));

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.type, 'image');
      expect(d.count, 2);
      expect(d.isMixed, isFalse);
    });

    test('mixed types -> isMixed, null type', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'));
      rows.add(row(id: 'b2', messageId: 'm1', mime: 'video/mp4', mediaType: 'video'));

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.isMixed, isTrue);
      expect(d.type, isNull);
      expect(d.count, 2);
    });

    test('groups by message id across the batch', () async {
      rows.add(row(id: 'b1', messageId: 'm1', mime: 'image/jpeg', mediaType: 'image'));
      rows.add(row(id: 'b2', messageId: 'm2', mime: 'audio/mp4', mediaType: 'audio'));

      final result = await repo.getMediaPreviewDescriptors(['m1', 'm2']);

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

      final d = (await repo.getMediaPreviewDescriptors(['m1']))['m1']!;

      expect(d.type, 'image');
      expect(secureKeyStore.readCount, 0);
    });
  });
}
