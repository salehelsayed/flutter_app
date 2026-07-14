import 'dart:io';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

const double mediaGridGap = 3.0;
const double mediaGridContainerRadius = 10.0;
const double mediaGridItemRadius = 4.0;

/// Resolves the existing local file that every media display surface must use.
///
/// The attachment's stored path remains authoritative while it exists. A
/// sender-side optimistic path can disappear after upload, though, while the
/// durable owned copy remains at `media/<owner>/<attachment>.<ext>`. Falling
/// back by stable attachment identity keeps the chat thumbnail and viewer on
/// the same bytes instead of letting one render while the other opens a stale
/// path.
String? resolveExistingMediaPathForDisplay({
  required MediaAttachment attachment,
  String? ownedMediaPeerId,
}) {
  final localPath = attachment.localPath;
  if (localPath != null && localPath.isNotEmpty) {
    final resolved = MediaFileManager.resolveStoredPathSync(localPath);
    if (File(resolved).existsSync()) return resolved;
  }

  final ownerId = ownedMediaPeerId;
  if (ownerId == null || ownerId.isEmpty || attachment.id.isEmpty) return null;
  final ownedRelative = MediaFilePathConvention.relativePathForAttachment(
    contactPeerId: ownerId,
    blobId: attachment.id,
    mime: attachment.mime,
  );
  final ownedResolved = MediaFileManager.resolveStoredPathSync(ownedRelative);
  return File(ownedResolved).existsSync() ? ownedResolved : null;
}

String formatDurationMs(int? ms) {
  if (ms == null || ms <= 0) return '0:00';
  final seconds = (ms ~/ 1000) % 60;
  final minutes = ms ~/ 60000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
