import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

const backgroundMotionEnabledStorageKey = 'background_motion_enabled';

/// Missing or unrecognized values retain the default moving background.
Future<bool> loadBackgroundMotionEnabled({
  required SecureKeyStore secureKeyStore,
}) async {
  return await secureKeyStore.read(backgroundMotionEnabledStorageKey) !=
      'false';
}

Future<void> saveBackgroundMotionEnabled({
  required SecureKeyStore secureKeyStore,
  required bool enabled,
}) => secureKeyStore.write(backgroundMotionEnabledStorageKey, '$enabled');

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
