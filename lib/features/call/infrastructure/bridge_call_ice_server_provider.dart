import '../../../core/bridge/bridge.dart';
import '../../../core/bridge/p2p_bridge_client.dart';
import '../domain/call_engine.dart';
import '../domain/call_id.dart';

typedef CallTurnCredentialFetcher =
    Future<Map<String, dynamic>> Function(Bridge bridge);

/// Reads a fresh native-authenticated TURN bundle for the one bounded ICE
/// restart. Nothing is cached, so credential lifetime never becomes call
/// lifetime and there is no static fallback after expiry or relay failure.
final class BridgeCallIceServerProvider {
  BridgeCallIceServerProvider({
    required Bridge bridge,
    CallTurnCredentialFetcher fetch = callP2PTurnCredentialsV1,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _bridge = bridge,
       _fetch = fetch,
       _clock = clock ?? DateTime.now;

  final Bridge _bridge;
  final CallTurnCredentialFetcher _fetch;
  final DateTime Function() _clock;
  final Duration requestTimeout;

  Future<List<CallIceServer>> read(CallId callId) async {
    try {
      final response = await _fetch(_bridge).timeout(requestTimeout);
      if (response['ok'] != true) return const <CallIceServer>[];

      final rawUrls = response['urls'];
      final username = response['username'];
      final password = response['password'];
      final expiresAtMs = response['expiresAtMs'];
      if (rawUrls is! List ||
          rawUrls.isEmpty ||
          rawUrls.length > 16 ||
          username is! String ||
          username.isEmpty ||
          password is! String ||
          password.isEmpty ||
          expiresAtMs is! int) {
        return const <CallIceServer>[];
      }

      final urls = <String>[];
      for (final value in rawUrls) {
        if (value is! String || !_isTurnUrl(value)) {
          return const <CallIceServer>[];
        }
        urls.add(value);
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs,
        isUtc: true,
      );
      if (!expiresAt.isAfter(_clock().toUtc())) {
        return const <CallIceServer>[];
      }
      return <CallIceServer>[
        CallIceServer(
          urls: urls,
          username: username,
          credential: password,
          expiresAt: expiresAt,
        ),
      ];
    } catch (_) {
      return const <CallIceServer>[];
    }
  }

  static bool _isTurnUrl(String value) {
    if (value.isEmpty || value.length > 2048 || value.trim() != value) {
      return false;
    }
    final lower = value.toLowerCase();
    return lower.startsWith('turn:') || lower.startsWith('turns:');
  }
}
