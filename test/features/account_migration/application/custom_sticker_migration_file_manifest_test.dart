import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_file_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/application/migration_file_manifest_validator.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory documents;

  Future<File> write(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('sticker-manifest-');
    documents = await Directory(p.join(sandbox.path, 'documents')).create();
  });
  tearDown(() async => sandbox.delete(recursive: true));

  test(
    'BL17 manifest includes only row-owned critical sticker bytes',
    () async {
      final rows = <Map<String, Object?>>[];
      for (var index = 0; index < 2; index++) {
        final bytes = _webp(index);
        final row = _row('item-$index', bytes, position: 1 - index);
        await write(
          p.join(documents.path, row['relative_path'] as String),
          bytes,
        );
        rows.add(row);
      }
      for (final path in [
        'stickers/orphan.webp',
        'stickers/orphan.thumb.jpg',
        'stickers/editor/source.png',
        'custom-sticker-scratch/working.webp',
        'sticker-send-11111111-1111-4111-8111-111111111111.webp',
        'unrelated/photo.webp',
      ]) {
        await write(p.join(documents.path, path), [9, 8, 7]);
      }

      final manifest = await MigrationFileManifestBuilder(
        documentsRootPath: documents.path,
      ).build(customStickerRows: rows);

      expect(manifest.isValid, isTrue);
      expect(manifest.items, hasLength(2));
      expect(manifest.pathRepairs, isEmpty);
      expect(manifest.totalNonCriticalBytes, 0);
      expect(
        manifest.totalCriticalBytes,
        rows.fold<int>(0, (sum, row) => sum + (row['size_bytes'] as int)),
      );
      for (final row in rows) {
        final item = manifest.items.singleWhere(
          (item) => item.sourceId == row['id'],
        );
        expect(item.kind, MigrationFileManifestItemKind.customSticker);
        expect(item.sourceTable, 'custom_stickers');
        expect(item.criticality, MigrationFileCriticality.critical);
        expect(item.relativePath, row['relative_path']);
        expect(item.sha256, row['content_sha256']);
        expect(item.sizeBytes, row['size_bytes']);
        expect(item.toJson()['kind'], 'customSticker');
      }
    },
  );

  test('BL17 manifest never discovers orphan stickers without rows', () async {
    await write(p.join(documents.path, 'stickers/orphan.webp'), _webp(1));
    await write(p.join(documents.path, 'stickers/orphan.thumb.jpg'), [1, 2]);
    final manifest = await MigrationFileManifestBuilder(
      documentsRootPath: documents.path,
    ).build();
    expect(manifest.items, isEmpty);
  });

  for (final corruption in [
    'missing',
    'same-size-tamper',
    'wrong-size',
    'relative-outside',
    'absolute-outside',
    'file-link',
    'parent-link',
    'stickers-root-link',
    'documents-root-link',
  ]) {
    test(
      'BL17 manifest blocks $corruption claimed sticker without mutation',
      () async {
        final bytes = _webp(1);
        final row = _row('claimed', bytes);
        final canonical = await write(
          p.join(documents.path, 'stickers/claimed.webp'),
          bytes,
        );
        final outside = await write(
          p.join(sandbox.path, 'outside/claimed.webp'),
          bytes,
        );
        File protectedFile = canonical;
        switch (corruption) {
          case 'missing':
            await canonical.delete();
            protectedFile = outside;
          case 'same-size-tamper':
            final tampered = List<int>.of(bytes);
            tampered[bytes.length - 1] ^= 1;
            await canonical.writeAsBytes(tampered, flush: true);
          case 'wrong-size':
            row['size_bytes'] = bytes.length + 1;
          case 'relative-outside':
            row['relative_path'] = '../outside/claimed.webp';
          case 'absolute-outside':
            row['relative_path'] = outside.path;
          case 'file-link':
            await canonical.delete();
            await Link(canonical.path).create(outside.path);
            protectedFile = outside;
          case 'parent-link':
            row['relative_path'] = 'stickers/linked/claimed.webp';
            await Link(
              p.join(documents.path, 'stickers/linked'),
            ).create(outside.parent.path);
          case 'stickers-root-link':
            final movedStickers = await canonical.parent.rename(
              p.join(sandbox.path, 'moved-stickers'),
            );
            await Link(
              p.join(documents.path, 'stickers'),
            ).create(movedStickers.path);
            protectedFile = File(p.join(movedStickers.path, 'claimed.webp'));
          case 'documents-root-link':
            final movedDocuments = await documents.rename(
              p.join(sandbox.path, 'moved-documents'),
            );
            await Link(documents.path).create(movedDocuments.path);
            protectedFile = File(
              p.join(movedDocuments.path, 'stickers/claimed.webp'),
            );
        }
        final rowBefore = Map<String, Object?>.of(row);
        final protectedBefore = await protectedFile.readAsBytes();
        final outsideBefore = await outside.readAsBytes();
        final result = await MigrationFileManifestValidator(
          documentsRootPath: documents.path,
        ).validateRows(customStickerRows: [row]);

        expect(result.isValid, isFalse);
        expect(
          result.items.where((item) => item.sourceTable == 'custom_stickers'),
          isEmpty,
        );
        final issue = result.issues.singleWhere(
          (issue) => issue.sourceId == 'claimed',
        );
        expect(issue.sourceTable, 'custom_stickers');
        expect(issue.blocking, isTrue);
        expect(issue.criticality, MigrationFileCriticality.critical);
        expect(issue.code, switch (corruption) {
          'missing' => MigrationFileManifestIssueCode.missingRequiredFile,
          'same-size-tamper' ||
          'wrong-size' => MigrationFileManifestIssueCode.fileSizeMismatch,
          _ => MigrationFileManifestIssueCode.unsupportedAbsolutePath,
        });
        expect(
          result.pathRepairs,
          isEmpty,
          reason: 'custom corruption must not rewrite account rows',
        );
        expect(row, rowBefore);
        expect(await protectedFile.readAsBytes(), protectedBefore);
        expect(await outside.readAsBytes(), outsideBefore);
        if (corruption == 'missing') expect(await canonical.exists(), isFalse);
      },
    );
  }
}

List<int> _webp(int variant) {
  final image = img.Image(width: 4, height: 4, numChannels: 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      image.setPixelRgba(x, y, 30 + variant * 40, 70 + x, 100 + y, 255);
    }
  }
  return img.encodeWebP(image, lossless: true);
}

Map<String, Object?> _row(String id, List<int> bytes, {int position = 0}) => {
  'id': id,
  'relative_path': 'stickers/$id.webp',
  'content_sha256': sha256.convert(bytes).toString(),
  'mime': 'image/webp',
  'size_bytes': bytes.length,
  'width': 4,
  'height': 4,
  'frame_count': 1,
  'duration_ms': 0,
  'created_at_ms': 1700000000000,
  'last_used_at_ms': 1700000000100,
  'position': position,
};
