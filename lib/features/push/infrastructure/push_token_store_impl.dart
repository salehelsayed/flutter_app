import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/domain/push_token_store.dart';

const pushFcmTokenSecureStorageKey = 'push_fcm_token';
const pushFcmPlatformSecureStorageKey = 'push_fcm_platform';

class PushTokenStoreImpl implements PushTokenStore {
  final SecureKeyStore _secureKeyStore;

  PushTokenStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  @override
  Future<void> writeToken(String token, String platform) async {
    await _secureKeyStore.write(pushFcmTokenSecureStorageKey, token);
    await _secureKeyStore.write(pushFcmPlatformSecureStorageKey, platform);
  }

  @override
  Future<({String token, String platform})?> readToken() async {
    final token = await _secureKeyStore.read(pushFcmTokenSecureStorageKey);
    final platform = await _secureKeyStore.read(
      pushFcmPlatformSecureStorageKey,
    );
    if (token == null ||
        token.isEmpty ||
        platform == null ||
        platform.isEmpty) {
      if (token != null || platform != null) {
        await clearToken();
      }
      return null;
    }

    return (token: token, platform: platform);
  }

  @override
  Future<void> clearToken() async {
    await _secureKeyStore.delete(pushFcmTokenSecureStorageKey);
    await _secureKeyStore.delete(pushFcmPlatformSecureStorageKey);
  }
}
