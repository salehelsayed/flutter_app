/// Represents a completed audio recording ready for upload.
class AudioRecording {
  final String filePath;
  final int durationMs;
  final String mime;
  final int sizeBytes;

  AudioRecording({
    required this.filePath,
    required this.durationMs,
    this.mime = 'audio/mp4',
    required this.sizeBytes,
  });

  @override
  String toString() =>
      'AudioRecording(filePath: $filePath, durationMs: $durationMs, '
      'mime: $mime, sizeBytes: $sizeBytes)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioRecording &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath;

  @override
  int get hashCode => filePath.hashCode;
}
