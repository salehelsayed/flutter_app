class PostMediaDraft {
  final String localFilePath;
  final String mime;
  final int? width;
  final int? height;
  final int? durationMs;
  final List<double>? waveform;

  const PostMediaDraft({
    required this.localFilePath,
    required this.mime,
    this.width,
    this.height,
    this.durationMs,
    this.waveform,
  });

  String get kind {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'voice';
    return 'file';
  }
}
