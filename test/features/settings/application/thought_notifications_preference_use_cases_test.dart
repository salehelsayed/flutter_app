import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/notifications/thought_notifications_preferences.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

class _FailingStore extends FakeSecureKeyStore {
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read failed');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('write failed');
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Thought notifications default ON and persist exact native-compatible values',
    () async {
      final store = FakeSecureKeyStore();
      expect(
        await loadThoughtNotificationsEnabled(secureKeyStore: store),
        isTrue,
      );
      await saveThoughtNotificationsEnabled(
        secureKeyStore: store,
        enabled: false,
      );
      expect(await store.read('thought_notifications_enabled_v1'), '0');
      expect(
        await loadThoughtNotificationsEnabled(secureKeyStore: store),
        isFalse,
      );
      await saveThoughtNotificationsEnabled(
        secureKeyStore: store,
        enabled: true,
      );
      expect(await store.read('thought_notifications_enabled_v1'), '1');
      expect(
        await loadThoughtNotificationsEnabled(secureKeyStore: store),
        isTrue,
      );
      expect(await store.read('thoughts_enabled_v1'), isNull);
      await store.write(thoughtNotificationsEnabledStorageKey, 'unknown');
      expect(
        await loadThoughtNotificationsEnabled(secureKeyStore: store),
        isTrue,
      );
    },
  );

  test(
    'Thought notification storage failure propagates without overwriting durable OFF',
    () async {
      final store = _FailingStore();
      await saveThoughtNotificationsEnabled(
        secureKeyStore: store,
        enabled: false,
      );
      store.failWrite = true;
      await expectLater(
        saveThoughtNotificationsEnabled(secureKeyStore: store, enabled: true),
        throwsStateError,
      );
      expect(
        await loadThoughtNotificationsEnabled(secureKeyStore: store),
        isFalse,
      );
      store.failRead = true;
      await expectLater(
        loadThoughtNotificationsEnabled(secureKeyStore: store),
        throwsStateError,
      );
    },
  );

  test(
    'Thought notification background store uses canonical shared iOS scope only on iOS',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        (createThoughtNotificationsPreferenceStore() as FlutterSecureKeyStore)
            .appleAccessGroup,
        mknoonSharedAppleAccessGroup,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        (createThoughtNotificationsPreferenceStore() as FlutterSecureKeyStore)
            .appleAccessGroup,
        isNull,
      );
    },
  );
}
