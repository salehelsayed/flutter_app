import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Loads the app background preference from secure storage.
///
/// Returns [BackgroundPreference.defaultBackground] when no preference is stored.
Future<BackgroundPreference> loadBackgroundPreference({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore.read(BackgroundPreference.storageKey);
  return BackgroundPreference.fromStorageString(value);
}

/// Saves the app background preference to secure storage.
Future<void> saveBackgroundPreference({
  required SecureKeyStore secureKeyStore,
  required BackgroundPreference preference,
}) async {
  await secureKeyStore.write(
    BackgroundPreference.storageKey,
    preference.toStorageString(),
  );
}
