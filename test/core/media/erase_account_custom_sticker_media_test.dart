import 'dart:io';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/media/erase_account_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory documents;
  late Directory temporary;
  const uuid = '11111111-2222-4333-8444-555555555555';
  const token = '0123456789abcdef0123456789abcdef';

  Future<File> write(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsBytes([7, 3, 9, 1], flush: true);
  }

  Future<void> erase({Directory? root, Directory? temp}) => eraseAccountMedia(
    documentsDirectory: root ?? documents,
    cacheDirectories: const [],
    temporaryDirectories: [temp ?? temporary],
    externalStorageDirectories: const [],
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('erase-custom-sticker-');
    documents = await Directory(p.join(sandbox.path, 'documents')).create();
    temporary = await Directory(p.join(sandbox.path, 'shared-temp')).create();
  });
  tearDown(() async => sandbox.delete(recursive: true));

  test(
    'BL17 erase removes durable stickers and actual owned temp forms while flag off',
    () async {
      expect(kCustomStickersEnabled, isFalse);
      final scratch = await temporary.createTemp('custom-sticker-');
      final animation = await temporary.createTemp('mknoon-sticker-animation-');
      final cutout = await temporary.createTemp(
        'mknoon-sticker-cutout-$token-',
      );
      final owned = [
        await write(p.join(documents.path, 'stickers/$uuid.webp')),
        await write(p.join(documents.path, 'stickers/orphan.webp')),
        await write(p.join(documents.path, 'stickers/editor/private.png')),
        await write(p.join(scratch.path, 'sticker-$token.webp')),
        await write(p.join(animation.path, 'frames.rgba')),
        await write(p.join(animation.path, 'poster.webp')),
        await write(p.join(cutout.path, 'result.png')),
        await write(p.join(cutout.path, '.validated-job/result.png')),
        await write(p.join(temporary.path, 'sticker-send-$uuid.webp')),
        await write(p.join(temporary.path, 'sticker-$token.webp')),
      ];
      final unrelated = [
        await write(p.join(documents.path, 'unrelated/keep.webp')),
        await write(p.join(sandbox.path, 'other-account/stickers/$uuid.webp')),
        await write(p.join(temporary.path, 'other-app/sticker-$token.webp')),
        await write(
          p.join(temporary.path, 'other-app/custom-sticker-copy/keep'),
        ),
      ];
      await erase();
      for (final file in owned) {
        expect(await file.exists(), isFalse, reason: file.path);
      }
      for (final directory in [
        scratch,
        animation,
        cutout,
        Directory(p.join(documents.path, 'stickers')),
      ]) {
        expect(await directory.exists(), isFalse);
      }
      for (final file in unrelated) {
        expect(await file.readAsBytes(), [7, 3, 9, 1]);
      }
      await erase();
      expect(await documents.exists(), isTrue);
      expect(await temporary.exists(), isTrue);
    },
  );

  test(
    'BL17 erase preserves neighboring names and wrong artifact types',
    () async {
      final preserved = <File>[
        for (final name in [
          'sticker-not-a-token.webp',
          'sticker-$token.webp.backup',
          'sticker-$token.png',
          'sticker-send-not-a-uuid.webp',
          'sticker-send-$uuid.webp.backup',
          'sticker-send-$uuid.png',
          'custom-sticker-not-a-directory',
          'mknoon-sticker-animation-not-a-directory',
          'mknoon-sticker-cutout-not-a-directory',
          'notes-sticker-$token.webp',
        ])
          await write(p.join(temporary.path, name)),
        await write(p.join(temporary.path, 'sticker-send-$uuid.webp/keep')),
        await write(p.join(temporary.path, 'sticker-$token.webp/keep')),
        await write(p.join(temporary.path, 'custom_sticker_notes/keep')),
      ];
      await erase();
      for (final file in preserved)
        expect(await file.readAsBytes(), [7, 3, 9, 1]);
    },
  );

  test(
    'BL17 erase refuses a symlinked stickers root without following it',
    () async {
      final outside = await write(p.join(sandbox.path, 'outside/keep.webp'));
      final root = Link(p.join(documents.path, 'stickers'));
      await root.create(outside.parent.path);
      await expectLater(erase(), throwsA(isA<FileSystemException>()));
      expect(await outside.readAsBytes(), [7, 3, 9, 1]);
      expect(await root.exists(), isTrue);
    },
  );

  test(
    'BL17 erase refuses a replaced Documents root before deleting its children',
    () async {
      final outside = await write(
        p.join(sandbox.path, 'foreign-documents/stickers/keep.webp'),
      );
      final alias = Link(p.join(sandbox.path, 'documents-alias'));
      await alias.create(p.dirname(outside.parent.path));
      await expectLater(
        erase(root: Directory(alias.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await outside.readAsBytes(), [7, 3, 9, 1]);
      expect(await alias.exists(), isTrue);
    },
  );

  test(
    'BL17 erase refuses a symlinked owned temp directory without following it',
    () async {
      final outside = await write(p.join(sandbox.path, 'outside/result.png'));
      final link = Link(p.join(temporary.path, 'custom-sticker-owned-link'));
      await link.create(outside.parent.path);
      await expectLater(erase(), throwsA(isA<FileSystemException>()));
      expect(await outside.readAsBytes(), [7, 3, 9, 1]);
      expect(await link.exists(), isTrue);
    },
  );

  test(
    'BL17 erase unlinks nested sticker links and keeps external contents',
    () async {
      final outside = await write(p.join(sandbox.path, 'outside/keep.webp'));
      final stickerRoot = await Directory(
        p.join(documents.path, 'stickers'),
      ).create();
      await write(p.join(stickerRoot.path, 'owned.webp'));
      await Link(
        p.join(stickerRoot.path, 'external-file.webp'),
      ).create(outside.path);
      await Link(
        p.join(stickerRoot.path, 'external-directory'),
      ).create(outside.parent.path);
      await erase();
      expect(await stickerRoot.exists(), isFalse);
      expect(await outside.readAsBytes(), [7, 3, 9, 1]);
    },
  );
}
