import 'package:flutter_app/features/push/infrastructure/push_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  group('PushTokenStoreImpl', () {
    test(
      'writes token and platform to the device-bound secure-store keys',
      () async {
        final store = FakeSecureKeyStore();
        final tokenStore = PushTokenStoreImpl(secureKeyStore: store);

        await tokenStore.writeToken('fcm-token', 'ios');

        expect(await store.read(pushFcmTokenSecureStorageKey), 'fcm-token');
        expect(await store.read(pushFcmPlatformSecureStorageKey), 'ios');
        expect(await tokenStore.readToken(), (
          token: 'fcm-token',
          platform: 'ios',
        ));
      },
    );

    test('clears token and platform together for regeneration', () async {
      final store = FakeSecureKeyStore();
      final tokenStore = PushTokenStoreImpl(secureKeyStore: store);
      await tokenStore.writeToken('fcm-token', 'ios');

      await tokenStore.clearToken();

      expect(await store.read(pushFcmTokenSecureStorageKey), isNull);
      expect(await store.read(pushFcmPlatformSecureStorageKey), isNull);
    });

    test('invalid partial token state is removed and read as absent', () async {
      final store = FakeSecureKeyStore();
      final tokenStore = PushTokenStoreImpl(secureKeyStore: store);
      await store.write(pushFcmTokenSecureStorageKey, 'fcm-token');

      final loaded = await tokenStore.readToken();

      expect(loaded, isNull);
      expect(await store.read(pushFcmTokenSecureStorageKey), isNull);
      expect(await store.read(pushFcmPlatformSecureStorageKey), isNull);
    });
  });
}
