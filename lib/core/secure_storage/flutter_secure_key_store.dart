import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_key_store.dart';

const mknoonSharedAppleAccessGroup = 'group.com.mknoon.app.share';

/// Production [SecureKeyStore] backed by flutter_secure_storage.
///
/// Uses iOS Keychain on iOS and EncryptedSharedPreferences on Android.
/// - iOS: kSecAttrAccessibleWhenUnlockedThisDeviceOnly — keys stay on-device,
///   inaccessible while locked, excluded from iCloud/iTunes backups.
/// - Android: EncryptedSharedPreferences backed by Android Keystore.
class FlutterSecureKeyStore implements SecureKeyStore {
  final FlutterSecureStorage _storage;
  final String? appleAccessGroup;

  FlutterSecureKeyStore({this.appleAccessGroup})
    : _storage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          groupId: appleAccessGroup,
        ),
      );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}
