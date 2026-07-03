import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/application/orbit_geometry_prefs_use_cases.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('OrbitGeometryPrefs use-cases (198 F3)', () {
    // TC-198-33 persistence half
    test('save then load round-trips through the store', () async {
      final store = FakeSecureKeyStore();
      const p = OrbitGeometryPrefs(
        avatarScale: 0.8,
        spacingScale: 1.2,
        arcWrap: 1.3,
        maxPerArc: 5,
        orbitGap: 1.5,
      );
      await saveOrbitGeometryPrefs(secureKeyStore: store, prefs: p);
      expect(await loadOrbitGeometryPrefs(secureKeyStore: store), p);
    });

    // TC-198-33 fresh-install half
    test('empty store loads defaults', () async {
      final store = FakeSecureKeyStore();
      expect(await loadOrbitGeometryPrefs(secureKeyStore: store),
          OrbitGeometryPrefs.defaults);
    });

    // TC-198-36 persistence half — Reset DELETES the key, does not overwrite.
    test('clear deletes the key so load reverts to defaults', () async {
      final store = FakeSecureKeyStore();
      const p = OrbitGeometryPrefs(
        avatarScale: 0.8,
        spacingScale: 1.2,
        arcWrap: 1.3,
        maxPerArc: 5,
        orbitGap: 1.5,
      );
      await saveOrbitGeometryPrefs(secureKeyStore: store, prefs: p);
      expect(await store.read(OrbitGeometryPrefs.storageKey), isNotNull);

      await clearOrbitGeometryPrefs(secureKeyStore: store);
      expect(await store.read(OrbitGeometryPrefs.storageKey), isNull,
          reason: 'clear DELETES the key, it does not write defaults over it');
      expect(await loadOrbitGeometryPrefs(secureKeyStore: store),
          OrbitGeometryPrefs.defaults);
    });

    // TC-198-34 store half — a corrupt stored value loads defaults, no throw.
    test('corrupt stored value loads defaults without throwing', () async {
      final store = FakeSecureKeyStore();
      await store.write(OrbitGeometryPrefs.storageKey, 'garbage|not|a|prefs');
      expect(await loadOrbitGeometryPrefs(secureKeyStore: store),
          OrbitGeometryPrefs.defaults);
    });
  });
}
