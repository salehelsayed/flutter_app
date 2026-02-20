import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';

/// Fake path provider that returns a temp directory.
class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;

  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaFileManager', () {
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

      test('does not throw when directory does not exist', () async {
        // Should not throw
        await fileManager.deleteMediaForContact('nonexistent-contact');
      });
    });

    group('deleteFile', () {
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

      test('does not throw when file does not exist', () async {
        await fileManager.deleteFile('/nonexistent/path/file.jpg');
      });
    });
  });
}
