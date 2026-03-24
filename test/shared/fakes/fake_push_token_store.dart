import 'package:flutter_app/features/push/domain/push_token_store.dart';

/// In-memory push token store for tests.
///
/// Records all token writes and reads. Simulates persistence across
/// logical "restarts" by retaining the map between calls.
class FakePushTokenStore implements PushTokenStore {
  String? _storedToken;
  String? _storedPlatform;

  int writeCallCount = 0;
  int readCallCount = 0;
  int clearCallCount = 0;

  bool throwOnWrite = false;

  @override
  Future<void> writeToken(String token, String platform) async {
    writeCallCount++;
    if (throwOnWrite) throw Exception('FakePushTokenStore: write error');
    _storedToken = token;
    _storedPlatform = platform;
  }

  @override
  Future<({String token, String platform})?> readToken() async {
    readCallCount++;
    if (_storedToken == null) return null;
    return (token: _storedToken!, platform: _storedPlatform!);
  }

  @override
  Future<void> clearToken() async {
    clearCallCount++;
    _storedToken = null;
    _storedPlatform = null;
  }

  /// Simulates app restart: the in-memory store survives (persisted).
  /// Call this between logical app sessions in tests.
  void simulateRestart() {
    // No-op: data persists. This exists to mark intent in test code.
  }

  /// Whether a token is currently stored.
  bool get hasToken => _storedToken != null;
  String? get storedToken => _storedToken;
  String? get storedPlatform => _storedPlatform;
}
