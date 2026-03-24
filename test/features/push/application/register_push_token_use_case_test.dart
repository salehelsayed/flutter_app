import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';

import '../../../shared/fakes/fake_push_token_store.dart';

// ---------------------------------------------------------------------------
// Fake P2PService
// ---------------------------------------------------------------------------
class _FakeP2PService implements P2PService {
  bool registerResult = true;
  String? lastToken;
  String? lastPlatform;

  @override
  Future<bool> registerPushToken(String token, String platform) async {
    lastToken = token;
    lastPlatform = platform;
    return registerResult;
  }

  // Not needed for this test file
  @override
  NodeState get currentState => throw UnimplementedError();
  @override
  Stream<NodeState> get stateStream => throw UnimplementedError();
  @override
  Stream<ChatMessage> get messageStream => throw UnimplementedError();
  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;
  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => throw UnimplementedError();
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;
  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => true;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];
  @override
  Future<void> performImmediateHealthCheck() async {}
  @override
  Future<void> drainOfflineInbox() async {}
  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;
  @override
  bool isConnectedToPeer(String peerId) => false;
  @override
  bool isLocalPeer(String peerId) => false;
  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;
  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;
  @override
  String? get lastRecoveryMethod => null;
  @override
  void dispose() {}
}

void main() {
  late _FakeP2PService p2pService;
  late FakePushTokenStore pushTokenStore;

  setUp(() {
    flowEventLoggingEnabled = false;
    p2pService = _FakeP2PService();
    pushTokenStore = FakePushTokenStore();
  });

  group('registerPushToken', () {
    test(
      'success: returns success when token exists and registration succeeds',
      () async {
        final result = await registerPushToken(
          p2pService: p2pService,
          pushTokenStore: pushTokenStore,
          isIOSFn: () => false,
          getTokenFn: () async => 'fcm_token_abc',
          getPlatformFn: () => 'ios',
        );

        expect(result, equals(RegisterPushTokenResult.success));
        final stored = await pushTokenStore.readToken();
        expect(stored, isNotNull);
        expect(stored!.token, 'fcm_token_abc');
        expect(stored.platform, 'ios');
      },
    );

    test('noToken: returns noToken when getTokenFn returns null', () async {
      final result = await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => false,
        getTokenFn: () async => null,
        getPlatformFn: () => 'ios',
      );

      expect(result, equals(RegisterPushTokenResult.noToken));
    });

    test(
      'failed: returns failed when p2pService.registerPushToken returns false',
      () async {
        p2pService.registerResult = false;

        final result = await registerPushToken(
          p2pService: p2pService,
          isIOSFn: () => false,
          getTokenFn: () async => 'fcm_token_abc',
          getPlatformFn: () => 'android',
        );

        expect(result, equals(RegisterPushTokenResult.failed));
      },
    );

    test('sends correct token and platform to p2pService', () async {
      await registerPushToken(
        p2pService: p2pService,
        pushTokenStore: pushTokenStore,
        isIOSFn: () => false,
        getTokenFn: () async => 'my_device_token_xyz',
        getPlatformFn: () => 'android',
      );

      expect(p2pService.lastToken, equals('my_device_token_xyz'));
      expect(p2pService.lastPlatform, equals('android'));
    });

    test('does not persist token when relay registration fails', () async {
      p2pService.registerResult = false;

      final result = await registerPushToken(
        p2pService: p2pService,
        pushTokenStore: pushTokenStore,
        isIOSFn: () => false,
        getTokenFn: () async => 'fcm_token_abc',
        getPlatformFn: () => 'android',
      );

      expect(result, equals(RegisterPushTokenResult.failed));
      expect(await pushTokenStore.readToken(), isNull);
      expect(pushTokenStore.writeCallCount, 0);
    });

    test(
      'returns failed when token persistence throws after registration',
      () async {
        pushTokenStore.throwOnWrite = true;

        final result = await registerPushToken(
          p2pService: p2pService,
          pushTokenStore: pushTokenStore,
          isIOSFn: () => false,
          getTokenFn: () async => 'fcm_token_abc',
          getPlatformFn: () => 'android',
        );

        expect(result, equals(RegisterPushTokenResult.failed));
        expect(pushTokenStore.writeCallCount, 1);
        expect(await pushTokenStore.readToken(), isNull);
        expect(p2pService.lastToken, equals('fcm_token_abc'));
      },
    );

    test('uses platform function to determine ios vs android', () async {
      await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => false,
        getTokenFn: () async => 'tok',
        getPlatformFn: () => 'ios',
      );
      expect(p2pService.lastPlatform, equals('ios'));

      await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => false,
        getTokenFn: () async => 'tok',
        getPlatformFn: () => 'android',
      );
      expect(p2pService.lastPlatform, equals('android'));
    });

    test('returns noToken when getToken throws', () async {
      final result = await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => false,
        getTokenFn: () => Future<String?>.error(Exception('platform error')),
        getPlatformFn: () => 'ios',
      );

      expect(result, equals(RegisterPushTokenResult.noToken));
      expect(p2pService.lastToken, isNull);
    });

    test('waits for APNS token before requesting the iOS FCM token', () async {
      var apnsChecks = 0;
      var getTokenCalls = 0;
      var now = DateTime(2026, 1, 1);

      final result = await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => true,
        getApnsTokenFn: () async {
          apnsChecks++;
          return apnsChecks >= 3 ? 'apns-token' : null;
        },
        getTokenFn: () async {
          getTokenCalls++;
          return 'fcm-token';
        },
        getTokenWithTimeoutFn: (getToken, _) => getToken(),
        getPlatformFn: () => 'ios',
        getApnsTokenTimeout: const Duration(seconds: 3),
        getApnsTokenPollInterval: const Duration(seconds: 1),
        nowFn: () => now,
        delayFn: (duration) async {
          now = now.add(duration);
        },
      );

      expect(apnsChecks, greaterThanOrEqualTo(3));
      expect(getTokenCalls, equals(1));
      expect(result, equals(RegisterPushTokenResult.success));
      expect(p2pService.lastToken, equals('fcm-token'));
      expect(p2pService.lastPlatform, equals('ios'));
    });

    test('returns noToken when APNS token never appears on iOS', () async {
      var getTokenCalls = 0;
      var now = DateTime(2026, 1, 1);

      final result = await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => true,
        getApnsTokenFn: () async => null,
        getTokenFn: () async {
          getTokenCalls++;
          return 'unexpected-token';
        },
        getPlatformFn: () => 'ios',
        getApnsTokenTimeout: const Duration(seconds: 2),
        getApnsTokenPollInterval: const Duration(seconds: 1),
        nowFn: () => now,
        delayFn: (duration) async {
          now = now.add(duration);
        },
      );

      expect(result, equals(RegisterPushTokenResult.noToken));
      expect(getTokenCalls, equals(0));
      expect(p2pService.lastToken, isNull);
    });

    test('returns noToken when getToken times out on iOS', () async {
      final result = await registerPushToken(
        p2pService: p2pService,
        isIOSFn: () => true,
        getApnsTokenFn: () async => 'apns-token',
        getTokenFn: () async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 'too-late-token';
        },
        getPlatformFn: () => 'ios',
        getTokenTimeout: const Duration(seconds: 1),
      );

      expect(result, equals(RegisterPushTokenResult.noToken));
      expect(p2pService.lastToken, isNull);
    });

    // Note: iOS timeout path uses Future.timeout() which conflicts with
    // flutter_test's timer handling. The timeout works correctly on real
    // devices — the 'returns noToken when getToken times out on iOS' test
    // above verifies the timeout-returns-null contract.
  });
}
