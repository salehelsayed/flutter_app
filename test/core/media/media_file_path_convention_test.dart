import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';

void main() {
  group('MediaFilePathConvention.extensionFromMime', () {
    test('maps audio/mp4 (recorder default) to .m4a, never .bin/empty', () {
      // Voice notes record as audio/mp4 — they must get a playable extension.
      expect(MediaFilePathConvention.extensionFromMime('audio/mp4'), '.m4a');
    });

    test('maps re-encode-fallback video containers to playable extensions', () {
      // When the video re-encode falls back to the original container, the
      // real mime is one of these. They must map to a playable extension,
      // never '' (extensionless) which leaves the file unopenable.
      expect(MediaFilePathConvention.extensionFromMime('video/x-m4v'), '.m4v');
      expect(
        MediaFilePathConvention.extensionFromMime('video/x-msvideo'),
        '.avi',
      );
      expect(
        MediaFilePathConvention.extensionFromMime('video/x-matroska'),
        '.mkv',
      );
    });

    test('preserves the existing canonical mappings', () {
      expect(MediaFilePathConvention.extensionFromMime('image/jpeg'), '.jpg');
      expect(MediaFilePathConvention.extensionFromMime('image/png'), '.png');
      expect(MediaFilePathConvention.extensionFromMime('video/mp4'), '.mp4');
      expect(
        MediaFilePathConvention.extensionFromMime('video/quicktime'),
        '.mov',
      );
      expect(MediaFilePathConvention.extensionFromMime('audio/aac'), '.aac');
      expect(MediaFilePathConvention.extensionFromMime('audio/mpeg'), '.mp3');
    });

    test('returns empty string only for genuinely unknown mimes', () {
      expect(
        MediaFilePathConvention.extensionFromMime('application/x-unknown'),
        '',
      );
    });
  });
}
