import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';

/// 198 — load/save/clear trio for the Orbit sculpt geometry knobs over
/// [SecureKeyStore]. Donors: `background_preference_use_cases.dart`, the orbit3
/// dimension-preference trio. Change-detection (no write on no-op) lives at the
/// call site (`orbit_wired`), NOT here — banning the lab's write-on-noop.

/// Loads the sculpt geometry from secure storage. Returns
/// [OrbitGeometryPrefs.defaults] when nothing is stored (or the value is
/// corrupt — see [OrbitGeometryPrefs.fromStorageString]).
Future<OrbitGeometryPrefs> loadOrbitGeometryPrefs({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore.read(OrbitGeometryPrefs.storageKey);
  return OrbitGeometryPrefs.fromStorageString(value);
}

/// Persists the sculpt geometry.
Future<void> saveOrbitGeometryPrefs({
  required SecureKeyStore secureKeyStore,
  required OrbitGeometryPrefs prefs,
}) async {
  await secureKeyStore.write(
    OrbitGeometryPrefs.storageKey,
    prefs.toStorageString(),
  );
}

/// Deletes the stored geometry so a fresh load yields the defaults (Reset).
Future<void> clearOrbitGeometryPrefs({
  required SecureKeyStore secureKeyStore,
}) async {
  await secureKeyStore.delete(OrbitGeometryPrefs.storageKey);
}
