import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';

/// The existing Posts selection rules, shared by the Orbit composer.
Future<List<PostMediaDraft>> pickPostMediaDrafts({MediaPicker? picker}) async {
  final selections = await (picker ?? SystemMediaPicker()).pickMultipleMedia();
  if (selections.isEmpty) return const [];

  final firstKind = _kindFromMime(_mimeFromPath(selections.first.path));
  final filtered = selections.where(
    (file) => _kindFromMime(_mimeFromPath(file.path)) == firstKind,
  );
  final limited = firstKind == 'image' ? filtered : filtered.take(1);
  return limited
      .map(
        (file) => PostMediaDraft(
          localFilePath: file.path,
          mime: _mimeFromPath(file.path),
        ),
      )
      .toList(growable: false);
}

String _mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  return 'application/octet-stream';
}

String _kindFromMime(String mime) {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'voice';
  return 'other';
}
