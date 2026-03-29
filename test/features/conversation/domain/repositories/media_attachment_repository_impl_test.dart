import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository_impl.dart';

void main() {
  // In-memory store for testing
  late Map<String, Map<String, Object?>> store;
  late MediaAttachmentRepositoryImpl repo;

  setUp(() {
    store = {};

    repo = MediaAttachmentRepositoryImpl(
      dbInsertMediaAttachment: (row) async {
        store[row['id'] as String] = Map.from(row);
      },
      dbLoadMediaForMessage: (messageId) async {
        return store.values
            .where((row) => row['message_id'] == messageId)
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
      },
      dbLoadMediaForMessages: (messageIds) async {
        return store.values
            .where((row) => messageIds.contains(row['message_id']))
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
      },
      dbUpdateMediaLocalPath: (id, localPath, downloadStatus) async {
        if (store.containsKey(id)) {
          store[id]!['local_path'] = localPath;
          store[id]!['download_status'] = downloadStatus;
        }
      },
      dbUpdateMediaDownloadStatus: (id, downloadStatus) async {
        if (store.containsKey(id)) {
          store[id]!['download_status'] = downloadStatus;
        }
      },
      dbDeleteMediaForMessage: (messageId) async {
        final keys = store.entries
            .where((e) => e.value['message_id'] == messageId)
            .map((e) => e.key)
            .toList();
        for (final key in keys) {
          store.remove(key);
        }
        return keys.length;
      },
      dbDeleteMediaForContact: (contactPeerId) async {
        // Simplified: in real DB this is a subquery on messages table
        // For testing, we just return 0
        return 0;
      },
      dbMarkUploadPendingAttachmentsFailedForMessage: (messageId) async {
        var count = 0;
        for (final row in store.values) {
          if (row['message_id'] == messageId &&
              row['download_status'] == 'upload_pending') {
            row['download_status'] = 'upload_failed';
            count++;
          }
        }
        return count;
      },
      dbLoadPendingMediaDownloads: () async {
        return store.values
            .where((row) => row['download_status'] == 'pending')
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
      },
      dbLoadUploadPendingAttachments: ({int limit = 50}) async {
        return store.values
            .where((row) => row['download_status'] == 'upload_pending')
            .toList()
          ..sort(
            (a, b) => (a['created_at'] as String).compareTo(
              b['created_at'] as String,
            ),
          );
      },
    );
  });

  MediaAttachment makeAttachment({
    String id = 'blob-001',
    String messageId = 'msg-001',
    String mime = 'image/jpeg',
    int size = 245000,
    String mediaType = 'image',
    int? width = 1920,
    int? height = 1080,
    String downloadStatus = 'pending',
    String createdAt = '2026-02-20T10:00:00.000Z',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: size,
      mediaType: mediaType,
      width: width,
      height: height,
      downloadStatus: downloadStatus,
      createdAt: createdAt,
    );
  }

  group('MediaAttachmentRepositoryImpl', () {
    test('saveAttachment persists to store', () async {
      final attachment = makeAttachment();
      await repo.saveAttachment(attachment);

      expect(store.containsKey('blob-001'), true);
      expect(store['blob-001']!['mime'], 'image/jpeg');
      expect(store['blob-001']!['message_id'], 'msg-001');
      expect(store['blob-001']!['size'], 245000);
    });

    test('saveAttachment replaces existing (INSERT OR REPLACE)', () async {
      await repo.saveAttachment(makeAttachment(downloadStatus: 'pending'));
      await repo.saveAttachment(makeAttachment(downloadStatus: 'done'));

      expect(store.length, 1);
      expect(store['blob-001']!['download_status'], 'done');
    });

    test('getAttachmentsForMessage returns empty list when none', () async {
      final result = await repo.getAttachmentsForMessage('nonexistent');
      expect(result, isEmpty);
    });

    test('getAttachmentsForMessage returns matching attachments', () async {
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-2',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await repo.saveAttachment(
        makeAttachment(id: 'blob-3', messageId: 'msg-B'),
      );

      final result = await repo.getAttachmentsForMessage('msg-A');
      expect(result.length, 2);
      expect(result[0].id, 'blob-1');
      expect(result[1].id, 'blob-2');
    });

    test('getAttachmentsForMessage returns MediaAttachment objects', () async {
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-typed',
          mime: 'video/mp4',
          size: 5000000,
          mediaType: 'video',
          width: 1280,
          height: 720,
        ),
      );

      final result = await repo.getAttachmentsForMessage('msg-001');
      expect(result.length, 1);
      expect(result[0], isA<MediaAttachment>());
      expect(result[0].mime, 'video/mp4');
      expect(result[0].size, 5000000);
      expect(result[0].width, 1280);
    });

    group('getAttachmentsForMessages', () {
      test('returns empty map for empty messageIds', () async {
        final result = await repo.getAttachmentsForMessages([]);
        expect(result, isEmpty);
      });

      test('groups attachments by messageId', () async {
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-1',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
        );
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-2',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:01:00.000Z',
          ),
        );
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-3',
            messageId: 'msg-B',
            createdAt: '2026-02-20T10:02:00.000Z',
          ),
        );
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-4',
            messageId: 'msg-C',
            createdAt: '2026-02-20T10:03:00.000Z',
          ),
        );

        final result = await repo.getAttachmentsForMessages(['msg-A', 'msg-B']);

        expect(result.length, 2);
        expect(result['msg-A']!.length, 2);
        expect(result['msg-A']![0].id, 'blob-1');
        expect(result['msg-A']![1].id, 'blob-2');
        expect(result['msg-B']!.length, 1);
        expect(result['msg-B']![0].id, 'blob-3');
        // msg-C not requested, should not appear
        expect(result.containsKey('msg-C'), isFalse);
      });

      test('returns empty map when no matches', () async {
        await repo.saveAttachment(
          makeAttachment(id: 'blob-1', messageId: 'msg-X'),
        );

        final result = await repo.getAttachmentsForMessages(['msg-A', 'msg-B']);
        expect(result, isEmpty);
      });
    });

    test('updateLocalPath updates path and sets status to done', () async {
      await repo.saveAttachment(makeAttachment(downloadStatus: 'downloading'));

      await repo.updateLocalPath('blob-001', '/path/to/file.jpg');

      expect(store['blob-001']!['local_path'], '/path/to/file.jpg');
      expect(store['blob-001']!['download_status'], 'done');
    });

    test('updateDownloadStatus changes status', () async {
      await repo.saveAttachment(makeAttachment(downloadStatus: 'pending'));

      await repo.updateDownloadStatus('blob-001', 'downloading');
      expect(store['blob-001']!['download_status'], 'downloading');

      await repo.updateDownloadStatus('blob-001', 'failed');
      expect(store['blob-001']!['download_status'], 'failed');
    });

    test('deleteAttachmentsForMessage removes matching rows', () async {
      await repo.saveAttachment(
        makeAttachment(id: 'blob-1', messageId: 'msg-A'),
      );
      await repo.saveAttachment(
        makeAttachment(id: 'blob-2', messageId: 'msg-A'),
      );
      await repo.saveAttachment(
        makeAttachment(id: 'blob-3', messageId: 'msg-B'),
      );

      final count = await repo.deleteAttachmentsForMessage('msg-A');
      expect(count, 2);
      expect(store.length, 1);
      expect(store.containsKey('blob-3'), true);
    });

    test('deleteAttachmentsForMessage returns 0 when no matches', () async {
      final count = await repo.deleteAttachmentsForMessage('nonexistent');
      expect(count, 0);
    });

    test(
      'markUploadPendingAttachmentsFailedForMessage only terminalizes pending rows for the target message',
      () async {
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-target-pending',
            messageId: 'msg-target',
            downloadStatus: 'upload_pending',
          ),
        );
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-target-done',
            messageId: 'msg-target',
            downloadStatus: 'done',
          ),
        );
        await repo.saveAttachment(
          makeAttachment(
            id: 'blob-other-pending',
            messageId: 'msg-other',
            downloadStatus: 'upload_pending',
          ),
        );

        final count = await repo.markUploadPendingAttachmentsFailedForMessage(
          'msg-target',
        );

        expect(count, 1);
        expect(
          store['blob-target-pending']!['download_status'],
          'upload_failed',
        );
        expect(store['blob-target-done']!['download_status'], 'done');
        expect(
          store['blob-other-pending']!['download_status'],
          'upload_pending',
        );
      },
    );

    test('getPendingDownloads returns only pending attachments', () async {
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-1',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-2',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await repo.saveAttachment(
        makeAttachment(
          id: 'blob-3',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:02:00.000Z',
        ),
      );

      final pending = await repo.getPendingDownloads();
      expect(pending.length, 2);
      expect(pending[0].id, 'blob-1');
      expect(pending[1].id, 'blob-3');
    });

    test('getPendingDownloads returns empty list when none pending', () async {
      await repo.saveAttachment(
        makeAttachment(id: 'blob-1', downloadStatus: 'done'),
      );

      final pending = await repo.getPendingDownloads();
      expect(pending, isEmpty);
    });
  });
}
