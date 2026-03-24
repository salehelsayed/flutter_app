import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/domain/push_token_store.dart';

const _kPushToken = 'push_fcm_token';
const _kPushPlatform = 'push_fcm_platform';

class PushTokenStoreImpl implements PushTokenStore {
  final SecureKeyStore _secureKeyStore;

  PushTokenStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  @override
  Future<void> writeToken(String token, String platform) async {
    await _secureKeyStore.write(_kPushToken, token);
    await _secureKeyStore.write(_kPushPlatform, platform);
  }

  @override
  Future<({String token, String platform})?> readToken() async {
    final token = await _secureKeyStore.read(_kPushToken);
    final platform = await _secureKeyStore.read(_kPushPlatform);
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
    await _secureKeyStore.delete(_kPushToken);
    await _secureKeyStore.delete(_kPushPlatform);
  }
}
