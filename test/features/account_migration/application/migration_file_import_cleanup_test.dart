import 'dart:io';

import 'package:flutter_app/features/account_migration/application/migration_file_import_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MigrationFileImportCleanup', () {
    late Directory tempDir;
    late Directory documentsRoot;
    late Directory stagingRoot;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig005_cleanup_');
      documentsRoot = Directory(p.join(tempDir.path, 'documents'));
      stagingRoot = Directory(p.join(tempDir.path, 'staging'));
      await documentsRoot.create(recursive: true);
      await stagingRoot.create(recursive: true);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'deletes session-scoped staged file artifacts without deleting active media',
      () async {
        final stagedFile = File(
          p.join(stagingRoot.path, 'session-1', 'media', 'copy.jpg'),
        );
        await stagedFile.parent.create(recursive: true);
        await stagedFile.writeAsString('staged', flush: true);
        final activeFile = File(
          p.join(documentsRoot.path, 'media', 'live.jpg'),
        );
        await activeFile.parent.create(recursive: true);
        await activeFile.writeAsString('active', flush: true);

        final cleanup = MigrationFileImportCleanup(
          stagingRootPath: stagingRoot.path,
        );

        await cleanup.cleanupSessionArtifacts(sessionId: 'session-1');

        expect(await stagedFile.exists(), isFalse);
        expect(await activeFile.exists(), isTrue);
        expect(await activeFile.readAsString(), 'active');
      },
    );

    test('ignores missing session directories', () async {
      final cleanup = MigrationFileImportCleanup(
        stagingRootPath: stagingRoot.path,
      );

      await cleanup.cleanupSessionArtifacts(sessionId: 'missing');

      expect(await stagingRoot.exists(), isTrue);
    });
  });
}
