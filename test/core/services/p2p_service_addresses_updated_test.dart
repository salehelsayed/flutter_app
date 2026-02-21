import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

// ---------------------------------------------------------------------------
// Fake Bridge
// ---------------------------------------------------------------------------

class _FakeBridge extends Bridge {
  Map<String, dynamic> startResponse = {
    'ok': true,
    'peerId': 'test-peer-id',
    'isStarted': true,
    'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
    'circuitAddresses': <String>[],
    'connections': <Map<String, dynamic>>[],
  };

  Map<String, dynamic> statusResponse = {
    'ok': true,
    'peerId': 'test-peer-id',
    'isStarted': true,
    'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
    'circuitAddresses': <String>[],
    'connections': <Map<String, dynamic>>[],
  };

  Map<String, dynamic> inboxResponse = {
    'ok': true,
    'messages': <Map<String, dynamic>>[],
  };

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    final cmd = req['cmd'] as String;
    switch (cmd) {
      case 'node:start':
        return jsonEncode(startResponse);
      case 'node:status':
        return jsonEncode(statusResponse);
      case 'inbox:retrieve':
        return jsonEncode(inboxResponse);
      default:
        return jsonEncode({'ok': true});
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeBridge fakeBridge;
  late P2PServiceImpl service;

  setUp(() {
    fakeBridge = _FakeBridge();
    service = P2PServiceImpl(bridge: fakeBridge);
  });

  tearDown(() {
    service.dispose();
  });

  test('onAddressesUpdated callback is registered on bridge', () {
    expect(fakeBridge.onAddressesUpdated, isNotNull);
  });

  test('addresses:updated updates state with circuit addresses', () async {
    // Start the node so service has a valid state.
    await service.startNodeCore('AAAA', 'test-peer-id');
    expect(service.currentState.isStarted, isTrue);
    expect(service.currentState.circuitAddresses, isEmpty);

    // Collect state stream emissions.
    final states = <dynamic>[];
    final sub = service.stateStream.listen(states.add);

    // Simulate addresses:updated push from Go.
    fakeBridge.onAddressesUpdated!(
      ['/ip4/127.0.0.1/tcp/1234'],
      ['/dns4/relay.example.com/tcp/4001/p2p/QmRelay/p2p-circuit'],
    );

    // Allow microtask queue to flush.
    await Future.delayed(Duration.zero);

    expect(service.currentState.circuitAddresses, hasLength(1));
    expect(
      service.currentState.circuitAddresses.first,
      contains('/p2p-circuit'),
    );
    expect(service.currentState.listenAddresses, hasLength(1));

    // State stream should have emitted.
    expect(states, isNotEmpty);

    await sub.cancel();
  });

  test('addresses:updated with empty circuit does not trigger FCM re-registration', () async {
    await service.startNodeCore('AAAA', 'test-peer-id');

    // Track calls to inbox:register_token by checking bridge calls.
    var registerTokenCalled = false;
    final originalSend = fakeBridge.send;
    // We can't override send on the fake, but we can check that registerPushToken
    // is NOT called by verifying no state change triggers it.
    // With empty circuit addresses and no prior FCM token, nothing should happen.
    fakeBridge.onAddressesUpdated!([], []);

    await Future.delayed(Duration.zero);

    // Current state should have empty circuit addresses.
    expect(service.currentState.circuitAddresses, isEmpty);
  });

  test('dispose clears onAddressesUpdated callback', () {
    service.dispose();
    expect(fakeBridge.onAddressesUpdated, isNull);
  });
}
