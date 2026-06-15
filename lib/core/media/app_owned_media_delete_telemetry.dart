import 'dart:io';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';

String appOwnedMediaPathKind(String? path) {
  if (path == null || path.isEmpty) {
    return 'empty';
  }
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return 'absolute';
  }
  return 'relative';
}

Future<void> deleteAppOwnedMediaFileIfExists({
  required File file,
  required String caller,
  required String reason,
  String? storedPath,
  Map<String, Object?> details = const {},
  bool swallowErrors = false,
}) async {
  await _deleteAppOwnedMediaTargetIfExists(
    path: file.path,
    targetKind: 'file',
    caller: caller,
    reason: reason,
    storedPath: storedPath,
    details: details,
    swallowErrors: swallowErrors,
    exists: file.exists,
    bytes: file.length,
    delete: () => file.delete(),
  );
}

Future<void> deleteAppOwnedMediaDirectoryIfExists({
  required Directory directory,
  required String caller,
  required String reason,
  Map<String, Object?> details = const {},
  bool recursive = false,
  bool swallowErrors = false,
}) async {
  await _deleteAppOwnedMediaTargetIfExists(
    path: directory.path,
    targetKind: 'directory',
    caller: caller,
    reason: reason,
    details: {'recursive': recursive, ...details},
    swallowErrors: swallowErrors,
    exists: directory.exists,
    bytes: () => _directoryEntryCount(directory),
    delete: () => directory.delete(recursive: recursive),
  );
}

Future<void> _deleteAppOwnedMediaTargetIfExists({
  required String path,
  required String targetKind,
  required String caller,
  required String reason,
  String? storedPath,
  required Map<String, Object?> details,
  required bool swallowErrors,
  required Future<bool> Function() exists,
  required Future<int> Function() bytes,
  required Future<FileSystemEntity> Function() delete,
}) async {
  var existsBefore = false;
  int? bytesBefore;
  int? entryCountBefore;
  Object? statError;
  try {
    existsBefore = await exists();
    if (existsBefore) {
      if (targetKind == 'directory') {
        entryCountBefore = await bytes();
      } else {
        bytesBefore = await bytes();
      }
    }
  } catch (e) {
    statError = e;
  }

  final baseDetails = <String, dynamic>{
    'caller': caller,
    'reason': reason,
    'targetKind': targetKind,
    'path': path,
    'pathKind': appOwnedMediaPathKind(path),
    if (storedPath != null) 'storedPath': storedPath,
    if (storedPath != null) 'storedPathKind': appOwnedMediaPathKind(storedPath),
    'existsBefore': existsBefore,
    if (bytesBefore != null) 'bytesBefore': bytesBefore,
    if (entryCountBefore != null) 'entryCountBefore': entryCountBefore,
    if (statError != null) 'statError': statError.toString(),
    ...details,
  };

  emitFlowEvent(
    layer: 'FL',
    event: 'APP_OWNED_MEDIA_DELETE_START',
    details: baseDetails,
  );

  if (!existsBefore) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_OWNED_MEDIA_DELETE_SKIPPED_MISSING',
      details: baseDetails,
    );
    return;
  }

  try {
    await delete();
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_OWNED_MEDIA_DELETE_SUCCESS',
      details: {...baseDetails, 'existsAfter': await exists()},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_OWNED_MEDIA_DELETE_ERROR',
      details: {...baseDetails, 'error': e.toString()},
    );
    if (!swallowErrors) {
      rethrow;
    }
  }
}

Future<int> _directoryEntryCount(Directory directory) async {
  var count = 0;
  await for (final _ in directory.list(recursive: true, followLinks: false)) {
    count += 1;
  }
  return count;
}
