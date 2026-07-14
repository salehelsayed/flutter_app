import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../shared/fakes/fake_media_file_manager.dart';

/// Fake path provider that returns a temp directory.
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;

  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _SnapshotTestMediaFileManager extends MediaFileManager {
  _SnapshotTestMediaFileManager(this.snapshotRootPath);

  final String snapshotRootPath;
  int remainingDeleteFailures = 0;
  int physicalDeleteAttempts = 0;

  @override
  Future<String> groupForwardSnapshotRootPath() async => snapshotRootPath;

  @override
  Future<void> deleteGroupForwardSnapshotDirectoryOnce(
    Directory directory,
  ) async {
    physicalDeleteAttempts++;
    if (remainingDeleteFailures > 0) {
      remainingDeleteFailures--;
      throw const FileSystemException('simulated snapshot delete failure');
    }
    await super.deleteGroupForwardSnapshotDirectoryOnce(directory);
  }
}

void main() {
  late MediaFileManager fileManager;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_file_mgr_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    fileManager = MediaFileManager();
  });

  tearDown(() async {
    debugSetFlowEventSink(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaFileManager', () {
    group('group forward snapshot ownership and recovery', () {
      test('delete retries and remains idempotent after success', () async {
        final manager = _SnapshotTestMediaFileManager(
          p.join(
            tempDir.path,
            MediaFileManager.groupForwardSnapshotRootDirectoryName,
          ),
        );
        final snapshot = await manager.createGroupForwardSnapshotDirectory();
        await File(
          p.join(snapshot.path, 'source.jpg'),
        ).writeAsBytes(const [0xff, 0xd8, 0xff, 0xe0]);
        manager.remainingDeleteFailures = 2;

        expect(
          await manager.deleteGroupForwardSnapshotDirectory(snapshot.path),
          isTrue,
        );
        expect(manager.physicalDeleteAttempts, 3);
        expect(await snapshot.exists(), isFalse);

        expect(
          await manager.deleteGroupForwardSnapshotDirectory(snapshot.path),
          isTrue,
        );
        expect(manager.physicalDeleteAttempts, 3);
      });

      test(
        'failed delete is reclaimed by the next scavenger operation',
        () async {
          final manager = _SnapshotTestMediaFileManager(
            p.join(
              tempDir.path,
              MediaFileManager.groupForwardSnapshotRootDirectoryName,
            ),
          );
          final snapshot = await manager.createGroupForwardSnapshotDirectory();
          await File(
            p.join(snapshot.path, 'source.jpg'),
          ).writeAsBytes(const [0xff, 0xd8, 0xff, 0xe0]);
          manager.remainingDeleteFailures = 3;

          expect(
            await manager.deleteGroupForwardSnapshotDirectory(snapshot.path),
            isFalse,
          );
          expect(manager.physicalDeleteAttempts, 3);
          expect(await snapshot.exists(), isTrue);

          expect(await manager.scavengeGroupForwardSnapshotOrphans(), 1);
          expect(manager.physicalDeleteAttempts, 4);
          expect(await snapshot.exists(), isFalse);
        },
      );

      test(
        'scavenger deletes only stale owned children and startup reclaims fresh orphans',
        () async {
          final root = Directory(
            p.join(
              tempDir.path,
              MediaFileManager.groupForwardSnapshotRootDirectoryName,
            ),
          );
          final manager = _SnapshotTestMediaFileManager(root.path);
          final active = await manager.createGroupForwardSnapshotDirectory();
          final stale = Directory(p.join(root.path, 'snapshot_stale_case'));
          final fresh = Directory(p.join(root.path, 'snapshot_fresh_case'));
          final future = Directory(p.join(root.path, 'snapshot_future_case'));
          final unrelatedChild = Directory(p.join(root.path, 'other_case'));
          final unrelatedSibling = Directory(
            p.join(tempDir.path, 'unrelated_temp_neighbor'),
          );
          for (final directory in <Directory>[
            stale,
            fresh,
            future,
            unrelatedChild,
            unrelatedSibling,
          ]) {
            await directory.create(recursive: true);
          }
          final matchingFile = File(p.join(root.path, 'snapshot_regular_file'));
          await matchingFile.writeAsBytes(const [1]);
          final outsideTarget = Directory(p.join(tempDir.path, 'outside'));
          await outsideTarget.create();
          final link = Link(p.join(root.path, 'snapshot_link_case'));
          await link.create(outsideTarget.path);
          final touched = await Process.run('touch', [
            '-t',
            '202001010000',
            stale.path,
          ]);
          expect(touched.exitCode, 0);

          expect(
            await manager.scavengeGroupForwardSnapshotOrphans(
              now: DateTime.utc(2026, 7, 14),
            ),
            1,
          );
          expect(await stale.exists(), isFalse);
          expect(await fresh.exists(), isTrue);
          expect(await future.exists(), isTrue);
          expect(await active.exists(), isTrue);
          expect(await unrelatedChild.exists(), isTrue);
          expect(await unrelatedSibling.exists(), isTrue);
          expect(await matchingFile.exists(), isTrue);
          expect(await link.exists(), isTrue);
          expect(await outsideTarget.exists(), isTrue);

          expect(
            await manager.scavengeGroupForwardSnapshotOrphans(
              deleteFreshOrphans: true,
            ),
            2,
          );
          expect(await fresh.exists(), isFalse);
          expect(await future.exists(), isFalse);
          expect(await active.exists(), isTrue);
          expect(await unrelatedChild.exists(), isTrue);
          expect(await unrelatedSibling.exists(), isTrue);
          expect(await matchingFile.exists(), isTrue);
          expect(await link.exists(), isTrue);
          expect(await outsideTarget.exists(), isTrue);

          expect(
            await manager.deleteGroupForwardSnapshotDirectory(active.path),
            isTrue,
          );
        },
      );

      test('scavenger work is bounded per pass', () async {
        final root = Directory(
          p.join(
            tempDir.path,
            MediaFileManager.groupForwardSnapshotRootDirectoryName,
          ),
        );
        final manager = _SnapshotTestMediaFileManager(root.path);
        await root.create(recursive: true);
        for (var index = 0; index < 80; index++) {
          await Directory(
            p.join(root.path, 'snapshot_bounded_$index'),
          ).create();
        }

        expect(
          await manager.scavengeGroupForwardSnapshotOrphans(
            now: DateTime.now().add(const Duration(hours: 7)),
          ),
          16,
        );
        expect(await root.list().length, 64);
      });
    });

    group('localPathForAttachment', () {
      test('returns path with correct structure', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-A',
          blobId: 'blob-001',
          mime: 'image/jpeg',
        );

        expect(path, contains('media'));
        expect(path, contains('contact-A'));
        expect(path, contains('blob-001'));
        expect(path, endsWith('.jpg'));
      });

      test('creates media directory if it does not exist', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'new-contact',
          blobId: 'blob-new',
          mime: 'image/png',
        );

        final dir = Directory(path).parent;
        expect(await dir.exists(), isTrue);
      });

      test('maps image/jpeg to .jpg', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/jpeg',
        );
        expect(path, endsWith('.jpg'));
      });

      test('maps image/png to .png', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/png',
        );
        expect(path, endsWith('.png'));
      });

      test('maps image/gif to .gif', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/gif',
        );
        expect(path, endsWith('.gif'));
      });

      test('maps image/webp to .webp', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/webp',
        );
        expect(path, endsWith('.webp'));
      });

      test('maps image/heic to .heic', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/heic',
        );
        expect(path, endsWith('.heic'));
      });

      test('maps video/mp4 to .mp4', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'video/mp4',
        );
        expect(path, endsWith('.mp4'));
      });

      test('maps video/quicktime to .mov', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'video/quicktime',
        );
        expect(path, endsWith('.mov'));
      });

      test('maps audio/aac to .aac', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'audio/aac',
        );
        expect(path, endsWith('.aac'));
      });

      test('maps audio/mpeg to .mp3', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'audio/mpeg',
        );
        expect(path, endsWith('.mp3'));
      });

      test('maps audio/mp4 to .m4a', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'audio/mp4',
        );
        expect(path, endsWith('.m4a'));
      });

      test('maps audio/ogg to .ogg', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'audio/ogg',
        );
        expect(path, endsWith('.ogg'));
      });

      test('maps application/pdf to .pdf', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'application/pdf',
        );
        expect(path, endsWith('.pdf'));
      });

      test('unknown MIME gets no extension', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'blob-id',
          mime: 'application/octet-stream',
        );
        // Should end with just the blob ID, no extension
        expect(path, endsWith('blob-id'));
      });
    });

    group('deleteMediaForContact', () {
      test('deletes contact media directory', () async {
        // Create a directory and file first
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-to-delete',
          blobId: 'blob-1',
          mime: 'image/jpeg',
        );
        await File(path).writeAsBytes([0xFF]);
        expect(await File(path).exists(), isTrue);

        await fileManager.deleteMediaForContact('contact-to-delete');

        expect(await Directory(File(path).parent.path).exists(), isFalse);
      });

      test('emits caller and reason telemetry for directory cleanup', () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'contact-telemetry',
          blobId: 'blob-1',
          mime: 'image/jpeg',
        );
        await File(path).writeAsBytes([0xFF]);

        await fileManager.deleteMediaForContact('contact-telemetry');

        final success = events.singleWhere(
          (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_SUCCESS',
        );
        expect(
          success['details'],
          allOf(
            containsPair('caller', 'MediaFileManager.deleteMediaForContact'),
            containsPair('reason', 'contact_media_dir_cleanup'),
            containsPair('targetKind', 'directory'),
            containsPair('contactPeerId', '[redacted]'),
            containsPair('recursive', true),
            containsPair('existsBefore', true),
            containsPair('existsAfter', false),
          ),
        );
      });

      test('does not throw when directory does not exist', () async {
        // Should not throw
        await fileManager.deleteMediaForContact('nonexistent-contact');
      });
    });

    group('relativePathForAttachment', () {
      test('returns relative path without leading slash', () {
        final path = fileManager.relativePathForAttachment(
          contactPeerId: 'contact-A',
          blobId: 'blob-001',
          mime: 'image/jpeg',
        );
        expect(path, equals('media/contact-A/blob-001.jpg'));
      });

      test('maps MIME types correctly', () {
        expect(
          fileManager.relativePathForAttachment(
            contactPeerId: 'c',
            blobId: 'b',
            mime: 'image/png',
          ),
          equals('media/c/b.png'),
        );
      });

      test('unknown MIME gets no extension', () {
        final path = fileManager.relativePathForAttachment(
          contactPeerId: 'c',
          blobId: 'blob-id',
          mime: 'application/octet-stream',
        );
        expect(path, equals('media/c/blob-id'));
      });
    });

    group('resolveStoredPath', () {
      test('resolves relative path to absolute', () async {
        final resolved = await fileManager.resolveStoredPath(
          'media/contact-A/blob-001.jpg',
        );
        expect(
          resolved,
          equals('${tempDir.path}/media/contact-A/blob-001.jpg'),
        );
      });

      test('resolves legacy absolute path with /media/ segment', () async {
        final legacyPath =
            '/old-container-uuid/Documents/media/contact-A/blob-001.jpg';
        final resolved = await fileManager.resolveStoredPath(legacyPath);
        expect(
          resolved,
          equals('${tempDir.path}/media/contact-A/blob-001.jpg'),
        );
      });

      test('resolves migrated local_media relative path to absolute', () async {
        final resolved = await fileManager.resolveStoredPath(
          'local_media/contact-A/blob-001.jpg',
        );
        expect(
          resolved,
          equals('${tempDir.path}/local_media/contact-A/blob-001.jpg'),
        );
      });

      test('rebases legacy absolute path with /local_media/ segment', () async {
        final legacyPath =
            '/old-container-uuid/Documents/local_media/contact-A/blob-001.jpg';
        final resolved = await fileManager.resolveStoredPath(legacyPath);
        expect(
          resolved,
          equals('${tempDir.path}/local_media/contact-A/blob-001.jpg'),
        );
      });

      test('returns unknown absolute path as-is', () async {
        const unknownPath = '/some/random/path.jpg';
        final resolved = await fileManager.resolveStoredPath(unknownPath);
        expect(resolved, equals(unknownPath));
      });
    });

    group('resolveStoredPathSync (127 round-3 render-boundary resolver)', () {
      test('returns the path unchanged when the cache is unseeded', () {
        // Declared first so the process-wide cache is still null here.
        expect(
          MediaFileManager.resolveStoredPathSync('media/contact-A/blob.jpg'),
          equals('media/contact-A/blob.jpg'),
        );
      });

      test('resolves a relative path against the cached documents dir', () {
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        expect(
          MediaFileManager.resolveStoredPathSync('media/contact-A/blob.jpg'),
          equals('${tempDir.path}/media/contact-A/blob.jpg'),
        );
      });

      test(
        'rebases a stale legacy absolute /media/ path onto the cached dir',
        () {
          MediaFileManager.cacheDocumentsDir(tempDir.path);
          expect(
            MediaFileManager.resolveStoredPathSync(
              '/old-container/Documents/media/contact-A/blob.jpg',
            ),
            equals('${tempDir.path}/media/contact-A/blob.jpg'),
          );
        },
      );

      test('is idempotent on an already-correct absolute path', () {
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        final abs = '${tempDir.path}/media/contact-A/blob.jpg';
        expect(MediaFileManager.resolveStoredPathSync(abs), equals(abs));
      });

      test('returns an unknown absolute path as-is', () {
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        expect(
          MediaFileManager.resolveStoredPathSync('/some/random/path.jpg'),
          equals('/some/random/path.jpg'),
        );
      });

      test(
        'matches the async resolveStoredPath for relative media paths',
        () async {
          MediaFileManager.cacheDocumentsDir(tempDir.path);
          const stored = 'media/contact-B/blob-2.jpg';
          expect(
            MediaFileManager.resolveStoredPathSync(stored),
            equals(await fileManager.resolveStoredPath(stored)),
          );
        },
      );

      test(
        '128: emits MEDIA_RESOLVE_SYNC_NO_CACHE once when cache is unseeded',
        () {
          MediaFileManager.debugResetDocumentsDirCache();
          final events = <Map<String, dynamic>>[];
          debugSetFlowEventSink(events.add);
          addTearDown(() => debugSetFlowEventSink(null));

          MediaFileManager.resolveStoredPathSync('media/a/b.jpg');
          MediaFileManager.resolveStoredPathSync('media/c/d.jpg');

          final noCache = events
              .where((e) => e['event'] == 'MEDIA_RESOLVE_SYNC_NO_CACHE')
              .toList();
          expect(
            noCache,
            hasLength(1),
            reason: 'once per process, not per call',
          );
        },
      );

      test('128: no MEDIA_RESOLVE_SYNC_NO_CACHE when the cache is seeded', () {
        MediaFileManager.debugResetDocumentsDirCache();
        MediaFileManager.cacheDocumentsDir(tempDir.path);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        MediaFileManager.resolveStoredPathSync('media/a/b.jpg');

        expect(
          events.where((e) => e['event'] == 'MEDIA_RESOLVE_SYNC_NO_CACHE'),
          isEmpty,
        );
      });
    });

    group('deleteFile', () {
      test(
        'private cleanup telemetry redacts paths and ids on start success and error',
        () async {
          const messageId = 'private-message-id-must-never-appear';
          const attachmentId = 'private-attachment-id-must-never-appear';
          const storedPath = 'media/private-contact/$attachmentId.jpg';
          final events = <Map<String, dynamic>>[];
          debugSetFlowEventSink(events.add);

          final successPath =
              '${tempDir.path}/private/$messageId/$attachmentId.jpg';
          final successFile = File(successPath);
          await successFile.parent.create(recursive: true);
          await successFile.writeAsBytes(const [1, 2, 3]);
          await fileManager.deleteFile(
            successPath,
            caller: 'DirectPrivateMediaLifecycle.cleanupTerminalWithinLock',
            reason: 'direct_private_media_terminal_cleanup',
            storedPath: storedPath,
            details: const {
              'messageId': messageId,
              'attachmentId': attachmentId,
            },
            redactTelemetry: true,
          );

          final deniedDirectory = Directory(
            '${tempDir.path}/private-error/$messageId',
          );
          await deniedDirectory.create(recursive: true);
          final errorPath = '${deniedDirectory.path}/$attachmentId.jpg';
          await File(errorPath).writeAsBytes(const [4, 5, 6]);
          final chmodDenied = await Process.run('chmod', [
            '500',
            deniedDirectory.path,
          ]);
          expect(chmodDenied.exitCode, 0);
          try {
            await expectLater(
              fileManager.deleteFile(
                errorPath,
                caller: 'DirectPrivateMediaLifecycle.cleanupTerminalWithinLock',
                reason: 'direct_private_media_terminal_cleanup',
                storedPath: storedPath,
                details: const {
                  'messageId': messageId,
                  'attachmentId': attachmentId,
                },
                redactTelemetry: true,
              ),
              throwsA(isA<FileSystemException>()),
            );
          } finally {
            await Process.run('chmod', ['700', deniedDirectory.path]);
          }

          final privateEvents = events
              .where(
                (event) =>
                    (event['details'] as Map?)?['reason'] ==
                    'direct_private_media_terminal_cleanup',
              )
              .toList(growable: false);
          expect(
            privateEvents
                .where(
                  (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_START',
                )
                .length,
            2,
          );
          expect(
            privateEvents.any(
              (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_SUCCESS',
            ),
            isTrue,
          );
          expect(
            privateEvents.any(
              (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_ERROR',
            ),
            isTrue,
          );
          for (final event in privateEvents) {
            final details = event['details'] as Map<String, dynamic>;
            expect(details['path'], '[redacted]');
            expect(details['pathKind'], '[redacted]');
            expect(details['storedPath'], '[redacted]');
            expect(details['storedPathKind'], '[redacted]');
            expect(details, isNot(contains('messageId')));
            expect(details, isNot(contains('attachmentId')));
          }
          final errorEvent = privateEvents.singleWhere(
            (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_ERROR',
          );
          final redactedError =
              (errorEvent['details'] as Map<String, dynamic>)['error']
                  as String;
          expect(redactedError, matches(RegExp(r'^[A-Za-z]+Exception$')));
          expect(redactedError, isNot(contains(errorPath)));
          final encoded = jsonEncode(privateEvents);
          for (final secret in [
            successPath,
            errorPath,
            storedPath,
            messageId,
            attachmentId,
          ]) {
            expect(encoded, isNot(contains(secret)), reason: secret);
          }

          final adapterSource = File(
            'lib/features/conversation/application/'
            'direct_private_media_lifecycle.dart',
          ).readAsStringSync();
          expect(adapterSource, contains('redactTelemetry: true'));
          expect(adapterSource, isNot(contains("'messageId': parent.id")));
          expect(
            adapterSource,
            isNot(contains("'attachmentId': attachment.id")),
          );
        },
      );

      test('deletes an existing file', () async {
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'b',
          mime: 'image/jpeg',
        );
        await File(path).writeAsBytes([0xFF]);
        expect(await File(path).exists(), isTrue);

        await fileManager.deleteFile(path);

        expect(await File(path).exists(), isFalse);
      });

      test('emits caller and reason telemetry when deleting a file', () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        final path = await fileManager.localPathForAttachment(
          contactPeerId: 'c',
          blobId: 'telemetry',
          mime: 'image/jpeg',
        );
        await File(path).writeAsBytes([0xFF]);

        await fileManager.deleteFile(
          path,
          caller: 'test.deleteFile',
          reason: 'test_cleanup',
          storedPath: 'media/c/telemetry.jpg',
          details: {'messageId': 'msg-telemetry'},
        );

        final success = events.singleWhere(
          (event) => event['event'] == 'APP_OWNED_MEDIA_DELETE_SUCCESS',
        );
        expect(
          success['details'],
          allOf(
            containsPair('caller', 'test.deleteFile'),
            containsPair('reason', 'test_cleanup'),
            containsPair('targetKind', 'file'),
            containsPair('storedPath', 'media/c/telemetry.jpg'),
            containsPair('messageId', 'msg-telemetry'),
            containsPair('existsBefore', true),
            containsPair('existsAfter', false),
          ),
        );
      });

      test('does not throw when file does not exist', () async {
        await fileManager.deleteFile('/nonexistent/path/file.jpg');
      });
    });

    group('deleteOwnedPendingUploadFilesForMessage', () {
      test(
        'deletes only app-owned pending_upload paths for the target message',
        () async {
          final fakeFileManager = FakeMediaFileManager();

          await fakeFileManager.deleteOwnedPendingUploadFilesForMessage(
            messageId: 'msg-123',
            storedPaths: const [
              'pending_uploads/msg-123/owned.jpg',
              'pending_uploads/msg-other/other.jpg',
              '/private/var/mobile/Containers/Data/Application/uuid/Documents/pending_uploads/msg-123/owned-abs.jpg',
              '/var/mobile/Media/DCIM/100APPLE/source.jpg',
            ],
          );

          expect(
            fakeFileManager.deletedFilePaths,
            contains(endsWith('pending_uploads/msg-123/owned.jpg')),
          );
          expect(
            fakeFileManager.deletedFilePaths,
            contains(
              '/private/var/mobile/Containers/Data/Application/uuid/Documents/pending_uploads/msg-123/owned-abs.jpg',
            ),
          );
          expect(
            fakeFileManager.deletedFilePaths,
            isNot(contains(endsWith('pending_uploads/msg-other/other.jpg'))),
          );
          expect(
            fakeFileManager.deletedFilePaths,
            isNot(contains('/var/mobile/Media/DCIM/100APPLE/source.jpg')),
          );
        },
      );

      test('preserves arbitrary stored source paths on disk', () async {
        final ownedDir = Directory('${tempDir.path}/pending_uploads/msg-safe');
        await ownedDir.create(recursive: true);
        final ownedFile = File('${ownedDir.path}/owned.jpg');
        await ownedFile.writeAsBytes([0x01]);

        final galleryFile = File('${tempDir.path}/gallery/source.jpg');
        await galleryFile.parent.create(recursive: true);
        await galleryFile.writeAsBytes([0x02]);

        await fileManager.deleteOwnedPendingUploadFilesForMessage(
          messageId: 'msg-safe',
          storedPaths: ['pending_uploads/msg-safe/owned.jpg', galleryFile.path],
        );

        expect(await ownedFile.exists(), isFalse);
        expect(await galleryFile.exists(), isTrue);
      });
    });
  });
}
