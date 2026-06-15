import 'dart:io';

import 'package:path/path.dart' as p;

class MigrationFileImportCleanup {
  final String stagingRootPath;

  const MigrationFileImportCleanup({required this.stagingRootPath});

  Future<void> cleanupSessionArtifacts({required String sessionId}) async {
    if (sessionId.isEmpty) {
      return;
    }
    final sessionDir = Directory(p.join(stagingRootPath, sessionId));
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
  }
}
