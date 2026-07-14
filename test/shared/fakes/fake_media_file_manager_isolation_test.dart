import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_media_file_manager.dart';

void main() {
  test('default root preserves the test_docs layout contract', () async {
    final root = FakeMediaFileManager.testRootPath;
    final path = await FakeMediaFileManager().localPathForAttachment(
      contactPeerId: 'peer-A',
      blobId: 'media-1',
      mime: 'image/jpeg',
    );

    expect(p.basename(root), 'test_docs');
    expect(path, p.join(root, 'media', 'peer-A', 'media-1.jpg'));
  });

  test('managers in the same test isolate share one default root', () async {
    final first = await FakeMediaFileManager().localPathForAttachment(
      contactPeerId: 'peer-A',
      blobId: 'media-1',
      mime: 'image/jpeg',
    );
    final second = await FakeMediaFileManager().localPathForAttachment(
      contactPeerId: 'peer-A',
      blobId: 'media-1',
      mime: 'image/jpeg',
    );

    expect(first, second);
    expect(p.isWithin(FakeMediaFileManager.testRootPath, first), isTrue);
  });

  test('independently spawned test isolates receive distinct roots', () async {
    final roots = await Future.wait(<Future<String>>[
      Isolate.run(() => FakeMediaFileManager.testRootPath),
      Isolate.run(() => FakeMediaFileManager.testRootPath),
    ]);

    addTearDown(() => _deleteRoots(roots));
    expect(roots.toSet(), hasLength(2));
    expect(roots.every((root) => p.basename(root) == 'test_docs'), isTrue);
  });

  test(
    'recursive teardown in one isolate cannot delete another root',
    () async {
      final seeded = await Future.wait(<Future<_SeededRoot>>[
        _seedIsolateRoot('first'),
        _seedIsolateRoot('second'),
      ]);
      final first = seeded[0];
      final second = seeded[1];
      addTearDown(() => _deleteRoots(seeded.map((entry) => entry.root)));

      expect(first.root, isNot(second.root));
      expect(File(first.filePath).existsSync(), isTrue);
      expect(File(second.filePath).existsSync(), isTrue);

      Directory(first.root).deleteSync(recursive: true);

      expect(File(first.filePath).existsSync(), isFalse);
      expect(File(second.filePath).existsSync(), isTrue);
    },
  );
}

Future<_SeededRoot> _seedIsolateRoot(String marker) {
  return Isolate.run(() async {
    final manager = FakeMediaFileManager();
    final filePath = await manager.localPathForAttachment(
      contactPeerId: 'peer-A',
      blobId: marker,
      mime: 'image/jpeg',
    );
    File(filePath).writeAsStringSync(marker);
    return _SeededRoot(FakeMediaFileManager.testRootPath, filePath);
  });
}

void _deleteRoots(Iterable<String> roots) {
  for (final root in roots.toSet()) {
    final directory = Directory(root);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

final class _SeededRoot {
  const _SeededRoot(this.root, this.filePath);

  final String root;
  final String filePath;
}
