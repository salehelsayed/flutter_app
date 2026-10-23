/// Abstract interface for secure key-value storage.
///
/// Production implementations use platform secure storage
/// (iOS Keychain / Android EncryptedSharedPreferences).
/// Test implementations use an in-memory map.
abstract class SecureKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> containsKey(String key);
}

/// Full inventory required by explicit local account erasure, including keys
/// whose database references have already been removed.
abstract interface class SecureKeyStoreInventory {
  Future<Map<String, String>> readAll();
}
