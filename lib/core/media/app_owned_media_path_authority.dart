import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AppDocumentsDirectoryProvider = Future<Directory> Function();

/// Canonical, local-only authority for media bytes owned by this app.
///
/// A path is data, never identity. Callers must separately reload and match the
/// current attachment row. This authority proves only that an existing regular
/// file resolves beneath one literal app-owned media root without escaping a
/// symlink boundary.
abstract interface class AppOwnedMediaPathAuthority {
  Future<String?> authorize(String? candidatePath);
}

class IoAppOwnedMediaPathAuthority implements AppOwnedMediaPathAuthority {
  IoAppOwnedMediaPathAuthority({
    AppDocumentsDirectoryProvider? documentsDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const Set<String> approvedRootNames = <String>{
    'media',
    'local_media',
    'post_media',
  };

  final AppDocumentsDirectoryProvider _documentsDirectory;

  @override
  Future<String?> authorize(String? candidatePath) async {
    if (candidatePath == null || candidatePath.trim().isEmpty) return null;
    try {
      final documents = await _documentsDirectory();
      if (!await documents.exists()) return null;
      final documentsReal = p.normalize(await documents.resolveSymbolicLinks());

      final candidate = File(candidatePath);
      if (!await candidate.exists()) return null;
      final candidateReal = p.normalize(await candidate.resolveSymbolicLinks());
      if ((await FileStat.stat(candidateReal)).type !=
          FileSystemEntityType.file) {
        return null;
      }

      for (final rootName in approvedRootNames) {
        final lexicalRoot = p.normalize(p.join(documentsReal, rootName));
        final root = Directory(lexicalRoot);
        if (!await root.exists()) continue;
        final canonicalRoot = p.normalize(await root.resolveSymbolicLinks());
        // A symlink at the authority root changes the boundary itself and is
        // rejected even when its current target happens to remain app-local.
        if (canonicalRoot != lexicalRoot) continue;
        if (candidateReal == canonicalRoot ||
            p.isWithin(canonicalRoot, candidateReal)) {
          return candidateReal;
        }
      }
    } on FileSystemException {
      return null;
    } on ArgumentError {
      return null;
    }
    return null;
  }
}
