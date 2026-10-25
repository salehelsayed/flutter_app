import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/features/posts/application/post_media_draft.dart';

/// [leftOut] is true when some chosen items did not make it into [drafts].
typedef PostMediaPick = ({List<PostMediaDraft> drafts, bool leftOut});

/// Supported picked files of any kind; [combinePostMedia] applies the
/// one-kind rule.
Future<PostMediaPick> pickPostMedia({MediaPicker? picker}) async {
  final selections = await (picker ?? SystemMediaPicker()).pickMultipleMedia();
  final drafts = [
    for (final file in selections)
      if (_mimeFromPath(file.path) case final mime?)
        PostMediaDraft(localFilePath: file.path, mime: mime),
  ];
  return (drafts: drafts, leftOut: drafts.length < selections.length);
}

/// The existing Posts selection rules, shared by the Orbit composer.
Future<List<PostMediaDraft>> pickPostMediaDrafts({MediaPicker? picker}) async =>
    combinePostMedia(
      const [],
      (await pickPostMedia(picker: picker)).drafts,
    ).drafts;

/// A post carries photos, or one video, or one voice note. Photos picked onto
/// photos are added; any other pick replaces [current].
PostMediaPick combinePostMedia(
  List<PostMediaDraft> current,
  List<PostMediaDraft> picked,
) {
  if (picked.isEmpty) return (drafts: current, leftOut: false);
  final kind = picked.first.kind;
  final sameKind = picked.where((draft) => draft.kind == kind).toList();
  final kept = kind == 'image' ? sameKind : sameKind.take(1).toList();
  final appendsPhotos =
      kind == 'image' && current.isNotEmpty && current.first.kind == 'image';
  return (
    drafts: appendsPhotos ? [...current, ...kept] : kept,
    leftOut: kept.length < picked.length,
  );
}

String? _mimeFromPath(String path) {
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
  return null;
}
