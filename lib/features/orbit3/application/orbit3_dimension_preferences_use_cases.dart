import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_dimension_preferences.dart';

/// Loads the Orbit3 dimension preferences from secure storage.
///
/// Returns [Orbit3DimensionPreferences.defaults] when nothing is stored (or the
/// stored value is corrupt — see [Orbit3DimensionPreferences.fromStorageString]).
Future<Orbit3DimensionPreferences> loadOrbit3DimensionPreferences({
  required SecureKeyStore secureKeyStore,
}) async {
  final value =
      await secureKeyStore.read(Orbit3DimensionPreferences.storageKey);
  return Orbit3DimensionPreferences.fromStorageString(value);
}

/// Saves the Orbit3 dimension preferences to secure storage.
Future<void> saveOrbit3DimensionPreferences({
  required SecureKeyStore secureKeyStore,
  required Orbit3DimensionPreferences prefs,
}) async {
  await secureKeyStore.write(
    Orbit3DimensionPreferences.storageKey,
    prefs.toStorageString(),
  );
}

/// Removes the stored Orbit3 dimension preferences so a fresh load yields the
/// defaults (the Reset-to-default action).
Future<void> clearOrbit3DimensionPreferences({
  required SecureKeyStore secureKeyStore,
}) async {
  await secureKeyStore.delete(Orbit3DimensionPreferences.storageKey);
}
