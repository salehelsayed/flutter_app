import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'direct_media_blob_artifact_store.dart';
import 'group_media_blob_artifact_store.dart';
import 'media_file_manager.dart';

/// Removes owned account media before the database and secure keys are erased.
/// The caller must keep account work blocked until restart, including on failure.
/// Supplied roots must come from this application's path-provider directories.
Future<void> eraseAccountMedia({
  Directory? documentsDirectory,
  List<Directory>? cacheDirectories,
  List<Directory>? temporaryDirectories,
  List<Directory>? externalStorageDirectories,
}) async {
  final documents =
      documentsDirectory ?? await getApplicationDocumentsDirectory();
  final caches = cacheDirectories ?? [await getApplicationCacheDirectory()];
  if (cacheDirectories == null && Platform.isAndroid) {
    caches.addAll(await getExternalCacheDirectories() ?? []);
  }
  final temporary =
      temporaryDirectories ??
      [await getTemporaryDirectory(), Directory.systemTemp];
  final external =
      externalStorageDirectories ??
      (Platform.isAndroid
          ? await getExternalStorageDirectories() ?? []
          : <Directory>[]);

  for (final name in [
    'media',
    'local_media',
    'local_media_tmp',
    'post_media',
    'pending_uploads',
    kDirectMediaBlobArtifactRootDirectory,
    kGroupMediaBlobArtifactRootDirectory,
    'account_migration',
  ]) {
    await _eraseDirectory(Directory(p.join(documents.path, name)));
  }

  // Application cache is package-specific. Temporary directories on desktop
  // can be shared with other apps, so never clear those wholesale.
  for (final directory in caches) {
    if (!await _directoryExists(directory)) continue;
    await for (final entry in directory.list(followLinks: false)) {
      await _eraseEntry(entry);
    }
    if (!await directory.list(followLinks: false).isEmpty) {
      throw FileSystemException(
        'Account cache erasure incomplete',
        directory.path,
      );
    }
  }

  for (final directory in temporary) {
    if (!await _directoryExists(directory)) continue;
    await for (final entry in directory.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (name == 'share_cache' ||
          name == 'video_compress' ||
          name == MediaFileManager.groupForwardSnapshotRootDirectoryName ||
          name.startsWith('mknoon-preview-') ||
          name.startsWith('mknoon-export-') ||
          name.startsWith('post-pass-avatar-')) {
        await _eraseDirectory(Directory(entry.path));
      } else if (RegExp(r'^voice_[0-9]+\.m4a$').hasMatch(name)) {
        await _eraseEntry(entry);
      }
    }
  }

  // Android video_compress writes outside cacheDir, but still beneath this
  // package's external-files roots. Public exports/gallery files are untouched.
  for (final directory in external) {
    await _eraseDirectory(Directory(p.join(directory.path, 'video_compress')));
  }
}

Future<bool> _directoryExists(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return false;
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('Unsafe account media directory', directory.path);
  }
  return true;
}

Future<void> _eraseDirectory(Directory directory) async {
  if (!await _directoryExists(directory)) return;
  await _eraseEntry(directory);
}

Future<void> _eraseEntry(FileSystemEntity entry) async {
  // Directory.delete does not follow nested symbolic links. A link entry in
  // private cache is itself removed, preserving anything outside that cache.
  await entry.delete(recursive: true);
  if (await FileSystemEntity.type(entry.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException('Account media erasure incomplete', entry.path);
  }
}
