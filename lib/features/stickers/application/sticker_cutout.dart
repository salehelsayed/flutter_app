import 'dart:ui' show Rect;

enum StickerCutoutAvailability { ready, needsModel, unsupported }

enum StickerCutoutErrorCode {
  disabled,
  unsupported,
  unavailable,
  invalidSource,
  failed,
}

/// A safe error that never includes the caller's source path or image data.
final class StickerCutoutException implements Exception {
  const StickerCutoutException(this.code);

  final StickerCutoutErrorCode code;

  @override
  String toString() => 'StickerCutoutException(${code.name})';
}

/// An orientation-corrected PNG with alpha and no embedded metadata.
///
/// Fully transparent pixels have zero RGB. The service validates the raster
/// and bounds before returning it; constructing this value alone is not proof.
/// The caller owns [imagePath] after a successful extraction and must delete it
/// after admission or abandoning the editor.
final class StickerCutout {
  const StickerCutout({
    required this.imagePath,
    required this.width,
    required this.height,
    required this.subjectBounds,
  });

  final String imagePath;
  final int width;
  final int height;

  /// The subject rectangle in normalized 0..1 coordinates on the output image.
  final Rect subjectBounds;
}

abstract interface class StickerCutoutService {
  /// Model-not-ready and unsupported results route directly to ordinary crop.
  Future<StickerCutoutAvailability> availability();

  /// Extracts a still subject without changing the caller-owned source photo.
  ///
  /// Null means no clear subject, or that this operation was cancelled. The UI
  /// tracks explicit cancellation so it does not show no-subject copy for it.
  /// The service owns temporary output until a successful return, and removes
  /// output on failure or cancellation. Typed errors also route to crop.
  Future<StickerCutout?> extract(String sourceImagePath);

  /// Cancels the in-flight extraction, completing it with null and suppressing
  /// stale output. An already returned caller-owned result is never deleted.
  Future<void> cancel();
}
