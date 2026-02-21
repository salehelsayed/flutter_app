/// Result of video processing, containing the output path and optional metadata.
///
/// Unlike image processing (which returns just a path), video processing also
/// extracts dimensions and duration needed for [MediaAttachment] fields.
class VideoProcessResult {
  final String path;
  final int? width;
  final int? height;
  final int? durationMs;

  const VideoProcessResult({
    required this.path,
    this.width,
    this.height,
    this.durationMs,
  });
}
