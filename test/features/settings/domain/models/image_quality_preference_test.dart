import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

void main() {
  group('ImageQualityPreference', () {
    group('toStorageString', () {
      test('returns "compressed" for compressed', () {
        expect(
          ImageQualityPreference.compressed.toStorageString(),
          'compressed',
        );
      });

      test('returns "original" for original', () {
        expect(
          ImageQualityPreference.original.toStorageString(),
          'original',
        );
      });
    });

    group('fromStorageString', () {
      test('returns compressed for "compressed"', () {
        expect(
          ImageQualityPreference.fromStorageString('compressed'),
          ImageQualityPreference.compressed,
        );
      });

      test('returns original for "original"', () {
        expect(
          ImageQualityPreference.fromStorageString('original'),
          ImageQualityPreference.original,
        );
      });

      test('returns compressed for null (default)', () {
        expect(
          ImageQualityPreference.fromStorageString(null),
          ImageQualityPreference.compressed,
        );
      });

      test('returns compressed for unknown value', () {
        expect(
          ImageQualityPreference.fromStorageString('garbage'),
          ImageQualityPreference.compressed,
        );
      });
    });

    group('videoStorageKey', () {
      test('equals "video_quality_preference"', () {
        expect(
          ImageQualityPreference.videoStorageKey,
          'video_quality_preference',
        );
      });
    });
  });
}
