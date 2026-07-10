import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

/// Loads the media auto-download matrix; a missing, corrupt or
/// unknown-version stored value decodes to the HEAD-compatible enabled
/// defaults (see [MediaDownloadPreferences.fromStorageString]).
Future<MediaDownloadPreferences> loadMediaDownloadPreferences({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore.read(MediaDownloadPreferences.storageKey);
  return MediaDownloadPreferences.fromStorageString(value);
}

/// Persists the media auto-download matrix. Errors propagate so the settings
/// surface can roll back its optimistic state and stay honest.
Future<void> saveMediaDownloadPreferences({
  required SecureKeyStore secureKeyStore,
  required MediaDownloadPreferences preferences,
}) async {
  await secureKeyStore.write(
    MediaDownloadPreferences.storageKey,
    preferences.toStorageString(),
  );
}
