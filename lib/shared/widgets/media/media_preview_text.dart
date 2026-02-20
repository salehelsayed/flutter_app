import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'media_display_helpers.dart';

/// Returns a human-readable summary for a list of media attachments.
///
/// Examples: "Photo", "3 photos", "Video", "Audio \u00B7 0:24",
/// "2 photos \u00B7 Video" (mixed types).
String mediaPreviewText(List<MediaAttachment> media) {
  if (media.isEmpty) return '';

  final imageCount = media.where((a) => a.mediaType == 'image').length;
  final videoCount = media.where((a) => a.mediaType == 'video').length;
  final audioCount = media.where((a) => a.mediaType == 'audio').length;

  final segments = <String>[];

  if (imageCount == 1) {
    segments.add('Photo');
  } else if (imageCount > 1) {
    segments.add('$imageCount photos');
  }

  if (videoCount == 1) {
    segments.add('Video');
  } else if (videoCount > 1) {
    segments.add('$videoCount videos');
  }

  if (audioCount >= 1) {
    final firstAudio = media.firstWhere((a) => a.mediaType == 'audio');
    final dur = formatDurationMs(firstAudio.durationMs);
    segments.add('Audio \u00B7 $dur');
  }

  if (segments.isEmpty) {
    // Fallback for file-type attachments
    return media.length == 1 ? 'File' : '${media.length} files';
  }

  return segments.join(' \u00B7 ');
}

/// Returns an appropriate icon for a list of media attachments.
IconData mediaPreviewIcon(List<MediaAttachment> media) {
  if (media.isEmpty) return Icons.attach_file_outlined;

  final hasImage = media.any((a) => a.mediaType == 'image');
  final hasVideo = media.any((a) => a.mediaType == 'video');
  final hasAudio = media.any((a) => a.mediaType == 'audio');

  if (hasImage && !hasVideo && !hasAudio) return Icons.camera_alt_outlined;
  if (hasVideo && !hasImage && !hasAudio) return Icons.videocam_outlined;
  if (hasAudio && !hasImage && !hasVideo) return Icons.mic_outlined;

  // Mixed media
  return Icons.camera_alt_outlined;
}
