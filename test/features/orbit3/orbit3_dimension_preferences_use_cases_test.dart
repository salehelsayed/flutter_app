import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_dimension_preferences_use_cases.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_dimension_preferences.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('orbit3 dimension preference use-cases', () {
    // TC-04
    test('save then load round-trips; empty store loads defaults', () async {
      final store = FakeSecureKeyStore();
      // Fresh install: nothing stored → defaults.
      expect(await loadOrbit3DimensionPreferences(secureKeyStore: store),
          Orbit3DimensionPreferences.defaults);

      const p = Orbit3DimensionPreferences(
        avatarScale: 1.2,
        spacingScale: 0.8,
        curveScale: 2.0,
        perRow: 5,
      );
      await saveOrbit3DimensionPreferences(secureKeyStore: store, prefs: p);
      // Same store instance models a relaunch reading what was saved.
      expect(await loadOrbit3DimensionPreferences(secureKeyStore: store), p);
    });

    // TC-05
    test('clear removes the stored key (load reverts to defaults)', () async {
      final store = FakeSecureKeyStore();
      const p = Orbit3DimensionPreferences(
        avatarScale: 1.2,
        spacingScale: 0.8,
        curveScale: 2.0,
        perRow: 5,
      );
      await saveOrbit3DimensionPreferences(secureKeyStore: store, prefs: p);
      expect(await store.read(Orbit3DimensionPreferences.storageKey), isNotNull);

      await clearOrbit3DimensionPreferences(secureKeyStore: store);
      expect(await store.read(Orbit3DimensionPreferences.storageKey), isNull,
          reason: 'clear DELETES the key, not writes defaults over it');
      expect(await loadOrbit3DimensionPreferences(secureKeyStore: store),
          Orbit3DimensionPreferences.defaults);
    });
  });
}
