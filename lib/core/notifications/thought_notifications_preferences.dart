import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

const thoughtNotificationsEnabledStorageKey =
    'thought_notifications_enabled_v1';

/// Each read reaches secure storage. An absent preference keeps alerts on;
/// storage errors propagate so a presentation owner can withhold an alert.
Future<bool> loadThoughtNotificationsEnabled({
  required SecureKeyStore secureKeyStore,
}) async =>
    await secureKeyStore.read(thoughtNotificationsEnabledStorageKey) != '0';

Future<void> saveThoughtNotificationsEnabled({
  required SecureKeyStore secureKeyStore,
  required bool enabled,
}) => secureKeyStore.write(
  thoughtNotificationsEnabledStorageKey,
  enabled ? '1' : '0',
);

/// Background isolates and standalone notification owners use the same
/// Keychain scope as the main production composition.
SecureKeyStore createThoughtNotificationsPreferenceStore() =>
    FlutterSecureKeyStore(
      appleAccessGroup: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? mknoonSharedAppleAccessGroup
          : null,
    );
