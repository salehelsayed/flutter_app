import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_key_store.dart';

/// The resolved `keychain-access-groups` entitlement shared by Runner and the
/// notification service extension. `flutter_secure_storage` forwards this
/// value directly to `kSecAttrAccessGroup`, so the AppIdentifierPrefix must be
/// present; the raw App Group identifier is not a valid Keychain access group.
const mknoonSharedAppleAccessGroup = '397R9Q4WMX.group.com.mknoon.app.share';

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

  /// Bounded harness support for a dedicated disposable application namespace.
  /// Production code must continue to use key-specific deletes.
  Future<void> deleteAll() => _storage.deleteAll();

  /// Read-back used to prove the dedicated namespace is empty after reset.
  Future<Map<String, String>> readAll() => _storage.readAll();
}
