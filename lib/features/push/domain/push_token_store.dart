abstract class PushTokenStore {
  Future<void> writeToken(String token, String platform);

  Future<({String token, String platform})?> readToken();

  Future<void> clearToken();
}
