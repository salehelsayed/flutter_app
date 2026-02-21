import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/application/image_quality_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('loadImageQualityPreference', () {
    test('returns compressed when key not set', () async {
      final store = FakeSecureKeyStore();

      final result = await loadImageQualityPreference(secureKeyStore: store);

      expect(result, ImageQualityPreference.compressed);
    });

    test('returns original when key is "original"', () async {
      final store = FakeSecureKeyStore();
      await store.write('image_quality_preference', 'original');

      final result = await loadImageQualityPreference(secureKeyStore: store);

      expect(result, ImageQualityPreference.original);
    });

    test('returns compressed when key is "compressed"', () async {
      final store = FakeSecureKeyStore();
      await store.write('image_quality_preference', 'compressed');

      final result = await loadImageQualityPreference(secureKeyStore: store);

      expect(result, ImageQualityPreference.compressed);
    });

    test('returns compressed for unknown value', () async {
      final store = FakeSecureKeyStore();
      await store.write('image_quality_preference', 'garbage');

      final result = await loadImageQualityPreference(secureKeyStore: store);

      expect(result, ImageQualityPreference.compressed);
    });
  });

  group('saveImageQualityPreference', () {
    test('saves "original" to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveImageQualityPreference(
        secureKeyStore: store,
        preference: ImageQualityPreference.original,
      );

      expect(await store.read('image_quality_preference'), 'original');
    });

    test('saves "compressed" to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveImageQualityPreference(
        secureKeyStore: store,
        preference: ImageQualityPreference.compressed,
      );

      expect(await store.read('image_quality_preference'), 'compressed');
    });

    test('overwrites existing value', () async {
      final store = FakeSecureKeyStore();
      await store.write('image_quality_preference', 'original');

      await saveImageQualityPreference(
        secureKeyStore: store,
        preference: ImageQualityPreference.compressed,
      );

      expect(await store.read('image_quality_preference'), 'compressed');
    });
  });
}
