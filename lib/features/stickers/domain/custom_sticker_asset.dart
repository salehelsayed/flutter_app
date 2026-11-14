/// An editor/encoder's description of its caller-owned output.
///
/// This is not proof of file ownership, integrity, or successful normalization.
/// Library admission must validate its own snapshot before storing any bytes.
/// Static editor input may be bounded PNG; stored assets are canonical WebP.
final class NormalizedStickerAsset {
  const NormalizedStickerAsset({
    required this.filePath,
    required this.sha256Hex,
    required this.mime,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.durationMs,
    this.posterPath,
  });

  final String filePath;
  final String sha256Hex;
  final String mime;
  final int byteLength;
  final int width;
  final int height;
  final int frameCount;
  final int durationMs;

  /// A disposable preview claim; admission may regenerate it.
  final String? posterPath;

  bool get isAnimated => frameCount > 1;
}
