import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

void main() {
  late FakeBridge bridge;
  late FakeP2PService p2pService;

  setUp(() {
    bridge = FakeBridge();
    p2pService = FakeP2PService();
  });

  group('handleAppResumed', () {
    test('calls checkHealth on bridge', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.checkHealthCallCount, equals(1));
    });

    test('does not reinitialize when bridge is healthy', () async {
      bridge.checkHealthResult = true;

      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.reinitializeCallCount, equals(0));
    });

    test('reinitializes bridge when health check fails', () async {
      bridge.checkHealthResult = false;

      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(bridge.reinitializeCallCount, equals(1));
    });

    test('calls performImmediateHealthCheck on p2pService', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(p2pService.performImmediateHealthCheckCallCount, equals(1));
    });

    test('calls drainOfflineInbox on p2pService', () async {
      await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(p2pService.drainOfflineInboxCallCount, equals(1));
    });

    test('continues after bridge checkHealth exception', () async {
      bridge.throwOnCheckHealth = true;

      final result =
          await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(result, isNull);
    });

    test('continues after bridge reinitialize exception', () async {
      bridge.checkHealthResult = false;
      bridge.throwOnReinitialize = true;

      final result =
          await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(result, isNull);
    });

    test('continues after p2pService health check exception', () async {
      p2pService.throwOnHealthCheck = true;

      final result =
          await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(result, isNull);
    });

    test('returns true when bridge was healthy', () async {
      bridge.checkHealthResult = true;

      final result =
          await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(result, isTrue);
    });

    test('returns false when bridge was unhealthy', () async {
      bridge.checkHealthResult = false;

      final result =
          await handleAppResumed(bridge: bridge, p2pService: p2pService);

      expect(result, isFalse);
    });
  });
}
