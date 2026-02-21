/// User preference for image quality when sending.
///
/// - [compressed]: Images are compressed (quality 85, default).
/// - [original]: Images are sent at full quality (quality 100).
///
/// EXIF metadata is always stripped regardless of quality setting.
enum ImageQualityPreference {
  compressed,
  original;

  /// Key used in SecureKeyStore for image quality.
  static const storageKey = 'image_quality_preference';

  /// Key used in SecureKeyStore for video quality.
  static const videoStorageKey = 'video_quality_preference';

  String toStorageString() => name;

  /// Parses a storage string. Returns [compressed] for null or unknown values.
  static ImageQualityPreference fromStorageString(String? value) {
    if (value == 'original') return ImageQualityPreference.original;
    return ImageQualityPreference.compressed;
  }
}
