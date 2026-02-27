import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/push/application/register_push_token_use_case.dart';

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
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async => true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(String peerId, String message, {int? timeoutMs}) async =>
      throw UnimplementedError();
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => null;
  @override
  Future<bool> dialPeer(String peerId, {List<String>? addresses}) async => true;
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => true;
  @override
  Future<List<Map<String, dynamic>>> retrieveInbox() async => [];
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
  Future<bool> sendLocalMessage(String peerId, String message, String fromPeerId) async => false;
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
  void dispose() {}
}

void main() {
  late _FakeP2PService p2pService;

  setUp(() {
    flowEventLoggingEnabled = false;
    p2pService = _FakeP2PService();
  });

  group('registerPushToken', () {
    test('success: returns success when token exists and registration succeeds',
        () async {
      final result = await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => 'fcm_token_abc',
        getPlatformFn: () => 'ios',
      );

      expect(result, equals(RegisterPushTokenResult.success));
    });

    test('noToken: returns noToken when getTokenFn returns null', () async {
      final result = await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => null,
        getPlatformFn: () => 'ios',
      );

      expect(result, equals(RegisterPushTokenResult.noToken));
    });

    test('failed: returns failed when p2pService.registerPushToken returns false',
        () async {
      p2pService.registerResult = false;

      final result = await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => 'fcm_token_abc',
        getPlatformFn: () => 'android',
      );

      expect(result, equals(RegisterPushTokenResult.failed));
    });

    test('sends correct token and platform to p2pService', () async {
      await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => 'my_device_token_xyz',
        getPlatformFn: () => 'android',
      );

      expect(p2pService.lastToken, equals('my_device_token_xyz'));
      expect(p2pService.lastPlatform, equals('android'));
    });

    test('uses platform function to determine ios vs android', () async {
      // Test iOS
      await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => 'tok',
        getPlatformFn: () => 'ios',
      );
      expect(p2pService.lastPlatform, equals('ios'));

      // Test Android
      await registerPushToken(
        p2pService: p2pService,
        getTokenFn: () async => 'tok',
        getPlatformFn: () => 'android',
      );
      expect(p2pService.lastPlatform, equals('android'));
    });
  });
}
