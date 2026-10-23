import 'dart:io';

import 'package:flutter_app/core/media/erase_account_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory documents;
  late Directory cache;
  late Directory temporary;
  late Directory external;

  Future<File> write(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  }

  Future<void> erase() => eraseAccountMedia(
    documentsDirectory: documents,
    cacheDirectories: [cache],
    temporaryDirectories: [temporary],
    externalStorageDirectories: [external],
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('account-media-erase-');
    documents = await Directory(p.join(sandbox.path, 'documents')).create();
    cache = await Directory(p.join(sandbox.path, 'app-cache')).create();
    temporary = await Directory(p.join(sandbox.path, 'shared-temp')).create();
    external = await Directory(p.join(sandbox.path, 'app-external')).create();
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  test(
    'erases received originals, thumbs, avatars and all durable media roots',
    () async {
      final owned = <File>[
        for (final name in [
          'photo.jpg',
          'video.mp4',
          'video.thumb.jpg',
          'voice.m4a',
          'file.pdf',
        ])
          await write(p.join(documents.path, 'media', 'old-peer', name)),
        for (final path in [
          'media/avatars/old-peer.jpg',
          'media/group_avatars/group.jpg',
          'local_media/old-peer/photo.jpg',
          'local_media_tmp/partial.jpg',
          'post_media/post/photo.jpg',
          'pending_uploads/message/source.jpg',
          'direct_media_blob_custody_v1/account/ciphertext.blob',
          'group_media_blob_custody_v1/account/group/ciphertext.blob',
          'account_migration/import/staged-media.jpg',
        ])
          await write(p.join(documents.path, path)),
      ];
      final unrelated = await write(
        p.join(documents.path, 'unrelated', 'keep'),
      );
      final receiver = await write(
        p.join(sandbox.path, 'other-package', 'media', 'photo.jpg'),
      );

      await erase();

      for (final file in owned) {
        expect(await file.exists(), isFalse, reason: file.path);
      }
      expect(await unrelated.exists(), isTrue);
      expect(await receiver.exists(), isTrue);
    },
  );

  test(
    'clears private caches and only owned artifacts in shared temporary roots',
    () async {
      final owned = <File>[
        await write(p.join(cache.path, 'picker-output.jpg')),
        await write(p.join(cache.path, 'share_cache', 'document.pdf')),
        for (final path in [
          'share_cache/shared.jpg',
          'video_compress/compressed.mp4',
          'mknoon_group_forward_snapshots_v1/snapshot_old/source.jpg',
          'mknoon-preview-request/Invoice.pdf',
          'mknoon-export-request/0/Invoice.pdf',
          'post-pass-avatar-post_author-old/source.jpg',
          'voice_1792760000000.m4a',
        ])
          await write(p.join(temporary.path, path)),
        await write(p.join(external.path, 'video_compress', 'compressed.mp4')),
      ];
      final neighbors = <File>[
        await write(p.join(temporary.path, 'other-app', 'keep')),
        await write(p.join(temporary.path, 'voice_unrelated.m4a')),
        await write(p.join(external.path, 'unrelated', 'keep')),
      ];

      await erase();

      for (final file in owned) {
        expect(await file.exists(), isFalse, reason: file.path);
      }
      for (final file in neighbors) {
        expect(await file.exists(), isTrue, reason: file.path);
      }
      expect(await cache.exists(), isTrue);
    },
  );

  test('missing roots and repeated erasure are harmless', () async {
    await erase();
    await erase();
    expect(await documents.exists(), isTrue);
  });

  test(
    'rejects a replaced media root and preserves its external target',
    () async {
      final outside = await write(p.join(sandbox.path, 'outside', 'keep.jpg'));
      final link = Link(p.join(documents.path, 'media'));
      await link.create(outside.parent.path);

      await expectLater(erase(), throwsA(isA<FileSystemException>()));

      expect(await outside.exists(), isTrue);
      expect(await link.exists(), isTrue);
    },
  );

  test(
    'does not follow a nested media symlink outside the owned root',
    () async {
      final outside = await write(p.join(sandbox.path, 'outside', 'keep.jpg'));
      final media = await Directory(p.join(documents.path, 'media')).create();
      await Link(p.join(media.path, 'external')).create(outside.parent.path);

      await erase();

      expect(await media.exists(), isFalse);
      expect(await outside.exists(), isTrue);
    },
  );

  test('reports an invalid cache root instead of claiming erasure', () async {
    await cache.delete();
    await File(cache.path).writeAsString('not a directory');

    await expectLater(erase(), throwsA(isA<FileSystemException>()));
  });
}
