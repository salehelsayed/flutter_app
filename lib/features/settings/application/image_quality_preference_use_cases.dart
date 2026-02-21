import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Loads the image quality preference from secure storage.
///
/// Returns [ImageQualityPreference.compressed] if no preference is stored.
Future<ImageQualityPreference> loadImageQualityPreference({
  required SecureKeyStore secureKeyStore,
}) async {
  final value = await secureKeyStore.read(ImageQualityPreference.storageKey);
  return ImageQualityPreference.fromStorageString(value);
}

/// Saves the image quality preference to secure storage.
Future<void> saveImageQualityPreference({
  required SecureKeyStore secureKeyStore,
  required ImageQualityPreference preference,
}) async {
  await secureKeyStore.write(
    ImageQualityPreference.storageKey,
    preference.toStorageString(),
  );
}

/// Loads the video quality preference from secure storage.
///
/// Returns [ImageQualityPreference.compressed] if no preference is stored.
Future<ImageQualityPreference> loadVideoQualityPreference({
  required SecureKeyStore secureKeyStore,
}) async {
  final value =
      await secureKeyStore.read(ImageQualityPreference.videoStorageKey);
  return ImageQualityPreference.fromStorageString(value);
}

/// Saves the video quality preference to secure storage.
Future<void> saveVideoQualityPreference({
  required SecureKeyStore secureKeyStore,
  required ImageQualityPreference preference,
}) async {
  await secureKeyStore.write(
    ImageQualityPreference.videoStorageKey,
    preference.toStorageString(),
  );
}
