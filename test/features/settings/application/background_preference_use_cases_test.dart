import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('BackgroundPreference', () {
    test('serializes background preferences to storage strings', () {
      expect(
        BackgroundPreference.defaultBackground.toStorageString(),
        'default',
      );
      expect(BackgroundPreference.cosmic.toStorageString(), 'cosmic');
      expect(BackgroundPreference.aurora.toStorageString(), 'aurora');
      expect(
        BackgroundPreference.daylightLagoon.toStorageString(),
        'daylight_lagoon',
      );
    });

    test('parses known, missing, and unknown values', () {
      expect(
        BackgroundPreference.fromStorageString('default'),
        BackgroundPreference.defaultBackground,
      );
      expect(
        BackgroundPreference.fromStorageString('cosmic'),
        BackgroundPreference.cosmic,
      );
      expect(
        BackgroundPreference.fromStorageString('aurora'),
        BackgroundPreference.aurora,
      );
      expect(
        BackgroundPreference.fromStorageString('cosmic_mirrored'),
        BackgroundPreference.defaultBackground,
      );
      expect(
        BackgroundPreference.fromStorageString('daylight_lagoon'),
        BackgroundPreference.daylightLagoon,
      );
      expect(
        BackgroundPreference.fromStorageString(null),
        BackgroundPreference.defaultBackground,
      );
      expect(
        BackgroundPreference.fromStorageString('future-background'),
        BackgroundPreference.defaultBackground,
      );
    });

    test('aurora token round-trips', () {
      expect(BackgroundPreference.aurora.toStorageString(), 'aurora');
      expect(
        BackgroundPreference.fromStorageString('aurora'),
        BackgroundPreference.aurora,
      );
    });

    test('parses cosmic_mirrored as the new default', () {
      expect(
        BackgroundPreference.fromStorageString('cosmic_mirrored'),
        BackgroundPreference.defaultBackground,
      );
    });
  });

  group('loadBackgroundPreference', () {
    test('returns default when key is not set', () async {
      final store = FakeSecureKeyStore();

      final result = await loadBackgroundPreference(secureKeyStore: store);

      expect(result, BackgroundPreference.defaultBackground);
    });

    test('returns default when stored value is default', () async {
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'default');

      final result = await loadBackgroundPreference(secureKeyStore: store);

      expect(result, BackgroundPreference.defaultBackground);
    });

    test('returns cosmic when stored value is cosmic', () async {
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'cosmic');

      final result = await loadBackgroundPreference(secureKeyStore: store);

      expect(result, BackgroundPreference.cosmic);
    });

    test('returns default when stored value is cosmic_mirrored', () async {
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'cosmic_mirrored');

      final result = await loadBackgroundPreference(secureKeyStore: store);

      expect(result, BackgroundPreference.defaultBackground);
    });

    test(
      'returns daylight lagoon when stored value is daylight_lagoon',
      () async {
        final store = FakeSecureKeyStore();
        await store.write(BackgroundPreference.storageKey, 'daylight_lagoon');

        final result = await loadBackgroundPreference(secureKeyStore: store);

        expect(result, BackgroundPreference.daylightLagoon);
      },
    );

    test('returns default for unknown stored value', () async {
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'garbage');

      final result = await loadBackgroundPreference(secureKeyStore: store);

      expect(result, BackgroundPreference.defaultBackground);
    });
  });

  group('saveBackgroundPreference', () {
    test('saves default to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveBackgroundPreference(
        secureKeyStore: store,
        preference: BackgroundPreference.defaultBackground,
      );

      expect(await store.read(BackgroundPreference.storageKey), 'default');
    });

    test('saves cosmic to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveBackgroundPreference(
        secureKeyStore: store,
        preference: BackgroundPreference.cosmic,
      );

      expect(await store.read(BackgroundPreference.storageKey), 'cosmic');
    });

    test('saves aurora to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveBackgroundPreference(
        secureKeyStore: store,
        preference: BackgroundPreference.aurora,
      );

      expect(await store.read(BackgroundPreference.storageKey), 'aurora');
    });

    test('saves daylight lagoon to secure storage', () async {
      final store = FakeSecureKeyStore();

      await saveBackgroundPreference(
        secureKeyStore: store,
        preference: BackgroundPreference.daylightLagoon,
      );

      expect(
        await store.read(BackgroundPreference.storageKey),
        'daylight_lagoon',
      );
    });

    test('overwrites existing value', () async {
      final store = FakeSecureKeyStore();
      await store.write(BackgroundPreference.storageKey, 'old-value');

      await saveBackgroundPreference(
        secureKeyStore: store,
        preference: BackgroundPreference.daylightLagoon,
      );

      expect(
        await store.read(BackgroundPreference.storageKey),
        'daylight_lagoon',
      );
    });
  });
}
