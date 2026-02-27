import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/local_discovery/local_p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_ws_server.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../bridge/fake_bridge.dart';

// -- Fake local discovery types for transport tagging tests --

class _LocalChatMessage extends LocalChatMessage {
  const _LocalChatMessage({
    required super.from,
    required super.to,
    required super.content,
    required super.timestamp,
    required super.isIncoming,
  });
}

class _FakeLocalP2PService extends LocalP2PService {
  final StreamController<LocalChatMessage> _controller;
  bool sendMediaResult = false;
  int sendMediaCallCount = 0;
  Map<String, dynamic>? lastSendMediaArgs;

  _FakeLocalP2PService(this._controller)
    : super(
        discovery: _FakeLocalDiscoveryService(),
        wsServer: _FakeLocalWsServer(),
      );

  @override
  Stream<LocalChatMessage> get localMessageStream => _controller.stream;

  @override
  Future<void> start(String peerId) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restartAdvertising() async {}

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  Future<bool> sendMessage(
    String peerId,
    String content,
    String fromPeerId,
  ) async => false;

  @override
  Future<bool> sendMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    sendMediaCallCount++;
    lastSendMediaArgs = {
      'peerId': peerId,
      'filePath': filePath,
      'mime': mime,
      'mediaId': mediaId,
      'fromPeerId': fromPeerId,
      'durationMs': durationMs,
      'waveform': waveform,
      'filename': filename,
    };
    return sendMediaResult;
  }

  @override
  void dispose() {}
}

class _FakeLocalDiscoveryService implements LocalDiscoveryService {
  @override
  Future<void> startAdvertising(String peerId, int port) async {}
  @override
  Future<void> stopAdvertising() async {}
  @override
  Stream<Map<String, LocalPeer>> get discoveredPeersStream =>
      const Stream.empty();
  @override
  Map<String, LocalPeer> get discoveredPeers => {};
  @override
  bool isLocalPeer(String peerId) => false;
  @override
  LocalPeer? getLocalPeer(String peerId) => null;
  @override
  void dispose() {}
}

class _FakeLocalWsServer extends LocalWsServer {
  _FakeLocalWsServer() : super(idleTimeout: Duration.zero);
}

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

/// A valid base64 key (32 bytes = Ed25519 seed).
/// base64Encode([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,
///               17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32])
const _testBase64Key = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';
const _testPeerId = '12D3KooWTestPeerId';

/// Standard node:start success response.
Map<String, dynamic> _nodeStartOk() => {
  'ok': true,
  'peerId': _testPeerId,
  'isStarted': true,
  'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
  'circuitAddresses': ['/p2p-circuit/test'],
  'connections': <Map<String, dynamic>>[],
};

/// Standard node:status success response.
Map<String, dynamic> _nodeStatusOk() => {
  'ok': true,
  'peerId': _testPeerId,
  'isStarted': true,
  'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
  'circuitAddresses': ['/p2p-circuit/test'],
  'connections': <Map<String, dynamic>>[],
};

// ---------------------------------------------------------------------------
// Slow bridge for concurrency tests
// ---------------------------------------------------------------------------

/// A bridge that uses a [Completer] to hold a specific command's response
/// until manually released.
class _SlowBridge extends FakeBridge {
  final Completer<void> _gate = Completer<void>();
  final String _blockCommand;

  _SlowBridge(this._blockCommand);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == _blockCommand && !_gate.isCompleted) {
      // Hold execution until the gate is released
      await _gate.future;
    }

    return super.send(message);
  }

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

// ---------------------------------------------------------------------------
// Counting bridge for warm-start fast circuit fallback tests
// ---------------------------------------------------------------------------

class _CountingBridge extends FakeBridge {
  int nodeStatusCallCount = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'node:status') nodeStatusCallCount++;
    return super.send(message);
  }
}

/// node:start response with NO circuit addresses (simulates cold relay).
Map<String, dynamic> _nodeStartNoCircuit() => {
  'ok': true,
  'peerId': _testPeerId,
  'isStarted': true,
  'listenAddresses': ['/ip4/127.0.0.1/tcp/1234'],
  'circuitAddresses': <String>[],
  'connections': <Map<String, dynamic>>[],
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late FakeBridge bridge;
  late P2PServiceImpl service;

  setUp(() {
    bridge = FakeBridge();
    service = P2PServiceImpl(bridge: bridge);
  });

  tearDown(() {
    service.dispose();
  });

  // =========================================================================
  // startNodeCore
  // =========================================================================

  group('startNodeCore', () {
    test('returns true and emits state when bridge returns ok', () async {
      bridge.responses['node:start'] = _nodeStartOk();

      final statesFuture = service.stateStream.first;
      final result = await service.startNodeCore(_testBase64Key, _testPeerId);

      expect(result, isTrue);
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.peerId, _testPeerId);

      final emittedState = await statesFuture.timeout(
        const Duration(seconds: 1),
      );
      expect(emittedState.isStarted, isTrue);
      expect(emittedState.peerId, _testPeerId);
    });

    test('converts base64 key to hex before sending to bridge', () async {
      bridge.responses['node:start'] = _nodeStartOk();

      await service.startNodeCore(_testBase64Key, _testPeerId);

      // Verify the bridge received the hex-encoded key
      expect(bridge.lastSentMessage, isNotNull);
      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      final sentHex = payload['privateKeyHex'] as String;
      final expectedHex = base64ToHex(_testBase64Key);
      expect(sentHex, expectedHex);
    });

    test('sends correct namespace mknoon:chat:\$peerId', () async {
      bridge.responses['node:start'] = _nodeStartOk();

      await service.startNodeCore(_testBase64Key, _testPeerId);

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['namespace'], 'mknoon:chat:$_testPeerId');
    });

    test('returns false when bridge returns ok=false', () async {
      bridge.responses['node:start'] = {
        'ok': false,
        'errorCode': 'START_FAILED',
        'errorMessage': 'cannot start',
      };

      final result = await service.startNodeCore(_testBase64Key, _testPeerId);

      expect(result, isFalse);
      expect(service.currentState.isStarted, isFalse);
    });

    test('returns false when bridge.send() throws', () async {
      bridge.throwOnSend = true;
      bridge.throwOnSendMessage = 'network error';

      final result = await service.startNodeCore(_testBase64Key, _testPeerId);

      expect(result, isFalse);
      expect(service.currentState.isStarted, isFalse);
    });

    test('concurrent guard: returns false when already starting', () async {
      final slowBridge = _SlowBridge('node:start');
      slowBridge.responses['node:start'] = _nodeStartOk();
      final slowService = P2PServiceImpl(bridge: slowBridge);

      addTearDown(() {
        slowBridge.release();
        slowService.dispose();
      });

      // First call will be held by the gate
      final first = slowService.startNodeCore(_testBase64Key, _testPeerId);

      // Give microtask queue a chance to enter startNodeCore
      await Future.delayed(Duration.zero);

      // Second call should return false immediately (concurrent guard)
      final second = await slowService.startNodeCore(
        _testBase64Key,
        _testPeerId,
      );
      expect(second, isFalse);

      // Release the first call and verify it succeeds
      slowBridge.release();
      final firstResult = await first;
      expect(firstResult, isTrue);
    });

    test('resyncs via node:status when error is "already started"', () async {
      bridge.responses['node:start'] = {
        'ok': false,
        'errorCode': 'NODE_ALREADY_STARTED',
        'errorMessage': 'node already started',
      };
      bridge.responses['node:status'] = _nodeStatusOk();

      final result = await service.startNodeCore(_testBase64Key, _testPeerId);

      expect(result, isTrue);
      expect(service.currentState.isStarted, isTrue);
      expect(service.currentState.peerId, _testPeerId);
      // Verify it sent node:status after node:start failed
      expect(bridge.lastCommand, 'node:status');
    });

    test(
      'resyncs via node:status returns false when status also fails',
      () async {
        bridge.responses['node:start'] = {
          'ok': false,
          'errorCode': 'NODE_ALREADY_STARTED',
          'errorMessage': 'node already started',
        };
        bridge.responses['node:status'] = {
          'ok': false,
          'errorMessage': 'status failed',
        };

        final result = await service.startNodeCore(_testBase64Key, _testPeerId);

        expect(result, isFalse);
      },
    );

    test('resets _isStarting in finally block after exception', () async {
      bridge.throwOnSend = true;

      // First call fails with exception
      final result1 = await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(result1, isFalse);

      // Second call should NOT be blocked by the concurrent guard
      bridge.throwOnSend = false;
      bridge.responses['node:start'] = _nodeStartOk();
      final result2 = await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(result2, isTrue);
    });
  });

  // =========================================================================
  // startNode
  // =========================================================================

  group('startNode', () {
    test('calls startNodeCore and returns its result on success', () async {
      bridge.responses['node:start'] = _nodeStartOk();
      // inbox:retrieve for warmBackground drainOfflineInbox
      bridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};
      // node:status for health check / warmBackground
      bridge.responses['node:status'] = _nodeStatusOk();

      final result = await service.startNode(_testBase64Key, _testPeerId);

      expect(result, isTrue);
      expect(service.currentState.isStarted, isTrue);
    });

    test('returns false when startNodeCore fails', () async {
      bridge.responses['node:start'] = {'ok': false, 'errorMessage': 'fail'};

      final result = await service.startNode(_testBase64Key, _testPeerId);

      expect(result, isFalse);
    });
  });

  // =========================================================================
  // stopNode
  // =========================================================================

  group('stopNode', () {
    test('returns true and emits NodeState.stopped on success', () async {
      // Start the node first
      bridge.responses['node:start'] = _nodeStartOk();
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.isStarted, isTrue);

      bridge.responses['node:stop'] = {'ok': true, 'stopped': true};

      final statesFuture = service.stateStream.first;
      final result = await service.stopNode();

      expect(result, isTrue);
      expect(service.currentState.isStarted, isFalse);

      final emittedState = await statesFuture.timeout(
        const Duration(seconds: 1),
      );
      expect(emittedState.isStarted, isFalse);
    });

    test('returns false when bridge returns ok=false', () async {
      bridge.responses['node:stop'] = {
        'ok': false,
        'errorMessage': 'stop failed',
      };

      final result = await service.stopNode();

      expect(result, isFalse);
    });

    test('returns false when bridge.send() throws', () async {
      bridge.throwOnSend = true;

      final result = await service.stopNode();

      expect(result, isFalse);
    });
  });

  // =========================================================================
  // sendMessage
  // =========================================================================

  group('sendMessage', () {
    test('returns true when bridge returns acked=true', () async {
      bridge.responses['message:send'] = {
        'ok': true,
        'sent': true,
        'acked': true,
      };

      final result = await service.sendMessage('peer123', 'hello');

      expect(result, isTrue);
      expect(bridge.lastCommand, 'message:send');
    });

    test('returns false when ok=true but acked=false', () async {
      bridge.responses['message:send'] = {
        'ok': true,
        'sent': true,
        'acked': false,
      };

      final result = await service.sendMessage('peer123', 'hello');

      expect(result, isFalse);
    });

    test(
      'returns true for legacy bridge responses with non-empty reply',
      () async {
        bridge.responses['message:send'] = {
          'ok': true,
          'sent': true,
          'reply': 'ack',
        };

        final result = await service.sendMessage('peer123', 'hello');

        expect(result, isTrue);
      },
    );

    test('returns false when bridge returns ok=false', () async {
      bridge.responses['message:send'] = {
        'ok': false,
        'errorMessage': 'peer unreachable',
      };

      final result = await service.sendMessage('peer123', 'hello');

      expect(result, isFalse);
    });

    test('returns false when bridge throws', () async {
      bridge.throwOnSend = true;

      final result = await service.sendMessage('peer123', 'hello');

      expect(result, isFalse);
    });
  });

  // =========================================================================
  // sendMessageWithReply
  // =========================================================================

  group('sendMessageWithReply', () {
    test('returns SendMessageResult(sent: true, reply) on success', () async {
      bridge.responses['message:send'] = {
        'ok': true,
        'sent': true,
        'reply': 'ack',
      };

      final result = await service.sendMessageWithReply('peer123', 'hello');

      expect(result.sent, isTrue);
      expect(result.reply, 'ack');
    });

    test('returns SendMessageResult(sent: false) on error', () async {
      bridge.responses['message:send'] = {
        'ok': false,
        'errorMessage': 'timeout',
      };

      final result = await service.sendMessageWithReply('peer123', 'hello');

      expect(result.sent, isFalse);
      expect(result.reply, isNull);
    });

    test('returns SendMessageResult(sent: false) on exception', () async {
      bridge.throwOnSend = true;

      final result = await service.sendMessageWithReply('peer123', 'hello');

      expect(result.sent, isFalse);
      expect(result.reply, isNull);
    });
  });

  // =========================================================================
  // discoverPeer
  // =========================================================================

  group('discoverPeer', () {
    test('returns DiscoveredPeer when peers found', () async {
      bridge.responses['rendezvous:discover'] = {
        'ok': true,
        'peers': [
          {
            'peerId': 'discovered-peer-1',
            'addresses': ['/ip4/10.0.0.1/tcp/4001'],
          },
        ],
      };

      final peer = await service.discoverPeer('discovered-peer-1');

      expect(peer, isNotNull);
      expect(peer!.id, 'discovered-peer-1');
      expect(peer.addresses, ['/ip4/10.0.0.1/tcp/4001']);
    });

    test('returns null when no peers found', () async {
      bridge.responses['rendezvous:discover'] = {
        'ok': true,
        'peers': <Map<String, dynamic>>[],
      };

      final peer = await service.discoverPeer('unknown-peer');

      expect(peer, isNull);
    });

    test('returns null when bridge returns ok=false', () async {
      bridge.responses['rendezvous:discover'] = {
        'ok': false,
        'errorMessage': 'discovery failed',
      };

      final peer = await service.discoverPeer('some-peer');

      expect(peer, isNull);
    });

    test('returns null when bridge throws', () async {
      bridge.throwOnSend = true;

      final peer = await service.discoverPeer('some-peer');

      expect(peer, isNull);
    });

    test('sends correct namespace mknoon:chat:\$peerId', () async {
      bridge.responses['rendezvous:discover'] = {
        'ok': true,
        'peers': <Map<String, dynamic>>[],
      };

      await service.discoverPeer('target-peer');

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['namespace'], 'mknoon:chat:target-peer');
    });
  });

  // =========================================================================
  // dialPeer
  // =========================================================================

  group('dialPeer', () {
    test('returns true on success', () async {
      bridge.responses['peer:dial'] = {
        'ok': true,
        'connected': true,
        'peerId': 'peer123',
      };

      final result = await service.dialPeer('peer123');

      expect(result, isTrue);
      expect(bridge.lastCommand, 'peer:dial');
    });

    test('returns false on error', () async {
      bridge.responses['peer:dial'] = {
        'ok': false,
        'errorMessage': 'dial failed',
      };

      final result = await service.dialPeer('peer123');

      expect(result, isFalse);
    });

    test('returns false on exception', () async {
      bridge.throwOnSend = true;

      final result = await service.dialPeer('peer123');

      expect(result, isFalse);
    });

    test('passes addresses when provided', () async {
      bridge.responses['peer:dial'] = {'ok': true, 'connected': true};

      await service.dialPeer('peer123', addresses: ['/ip4/10.0.0.1/tcp/4001']);

      final sent = jsonDecode(bridge.lastSentMessage!) as Map<String, dynamic>;
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['addresses'], ['/ip4/10.0.0.1/tcp/4001']);
    });
  });

  // =========================================================================
  // storeInInbox
  // =========================================================================

  group('storeInInbox', () {
    test('returns true on success', () async {
      bridge.responses['inbox:store'] = {'ok': true, 'stored': true};

      final result = await service.storeInInbox('peer123', 'hello');

      expect(result, isTrue);
      expect(bridge.lastCommand, 'inbox:store');
    });

    test('returns false on error', () async {
      bridge.responses['inbox:store'] = {
        'ok': false,
        'errorMessage': 'store failed',
      };

      final result = await service.storeInInbox('peer123', 'hello');

      expect(result, isFalse);
    });

    test('returns false on exception', () async {
      bridge.throwOnSend = true;

      final result = await service.storeInInbox('peer123', 'hello');

      expect(result, isFalse);
    });
  });

  // =========================================================================
  // retrieveInbox
  // =========================================================================

  group('retrieveInbox', () {
    test('returns list of messages on success', () async {
      bridge.responses['inbox:retrieve'] = {
        'ok': true,
        'messages': [
          {'from': 'peer1', 'message': 'hi', 'timestamp': 1700000000000},
          {'from': 'peer2', 'message': 'hey', 'timestamp': 1700000001000},
        ],
      };

      final messages = await service.retrieveInbox();

      expect(messages, hasLength(2));
      expect(messages[0]['from'], 'peer1');
      expect(messages[1]['from'], 'peer2');
    });

    test('returns empty list on error', () async {
      bridge.responses['inbox:retrieve'] = {
        'ok': false,
        'errorMessage': 'retrieve failed',
      };

      final messages = await service.retrieveInbox();

      expect(messages, isEmpty);
    });

    test('returns empty list on exception', () async {
      bridge.throwOnSend = true;

      final messages = await service.retrieveInbox();

      expect(messages, isEmpty);
    });

    test('returns empty list when messages key is null', () async {
      bridge.responses['inbox:retrieve'] = {
        'ok': true,
        // No 'messages' key
      };

      final messages = await service.retrieveInbox();

      expect(messages, isEmpty);
    });
  });

  // =========================================================================
  // registerPushToken
  // =========================================================================

  group('registerPushToken', () {
    test('returns true and stores token on success', () async {
      bridge.responses['inbox:register_token'] = {
        'ok': true,
        'registered': true,
      };

      final result = await service.registerPushToken('fcm-token-123', 'ios');

      expect(result, isTrue);
      expect(bridge.lastCommand, 'inbox:register_token');
    });

    test('returns false on error', () async {
      bridge.responses['inbox:register_token'] = {
        'ok': false,
        'errorMessage': 'registration failed',
      };

      final result = await service.registerPushToken('fcm-token-123', 'ios');

      expect(result, isFalse);
    });

    test('returns false on exception', () async {
      bridge.throwOnSend = true;

      final result = await service.registerPushToken('fcm-token-123', 'ios');

      expect(result, isFalse);
    });
  });

  // =========================================================================
  // event handlers
  // =========================================================================

  group('event handlers', () {
    test('constructor registers all event handlers on bridge', () {
      expect(bridge.onMessageReceived, isNotNull);
      expect(bridge.onPeerConnected, isNotNull);
      expect(bridge.onPeerDisconnected, isNotNull);
      expect(bridge.onAddressesUpdated, isNotNull);
    });

    test('onMessageReceived adds message to messageStream', () async {
      final message = ChatMessage(
        from: 'sender',
        to: 'receiver',
        content: 'hello',
        timestamp: '2024-01-01T00:00:00Z',
        isIncoming: true,
      );

      final messageFuture = service.messageStream.first;
      bridge.onMessageReceived!(message);

      final received = await messageFuture.timeout(const Duration(seconds: 1));
      expect(received.from, 'sender');
      expect(received.to, 'receiver');
      expect(received.content, 'hello');
      expect(received.isIncoming, isTrue);
    });

    test('onPeerConnected adds connection to state and emits', () async {
      // Start the node so we have a valid state to modify
      bridge.responses['node:start'] = _nodeStartOk();
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.connections, isEmpty);

      final conn = ConnectionState(
        peerId: 'connected-peer',
        multiaddrs: ['/ip4/10.0.0.1/tcp/4001'],
        direction: 'inbound',
        status: 'connected',
      );

      final stateFuture = service.stateStream.first;
      bridge.onPeerConnected!(conn);

      final updatedState = await stateFuture.timeout(
        const Duration(seconds: 1),
      );
      expect(updatedState.connections, hasLength(1));
      expect(updatedState.connections.first.peerId, 'connected-peer');

      // Also verify currentState
      expect(service.currentState.connections, hasLength(1));
    });

    test(
      'onPeerDisconnected removes connection from state and emits',
      () async {
        // Start the node and add a connection first
        bridge.responses['node:start'] = _nodeStartOk();
        await service.startNodeCore(_testBase64Key, _testPeerId);

        final conn = ConnectionState(
          peerId: 'connected-peer',
          multiaddrs: ['/ip4/10.0.0.1/tcp/4001'],
          direction: 'inbound',
          status: 'connected',
        );
        bridge.onPeerConnected!(conn);
        await Future.delayed(Duration.zero);
        expect(service.currentState.connections, hasLength(1));

        // Now disconnect
        final disconnConn = ConnectionState(
          peerId: 'connected-peer',
          multiaddrs: [],
          direction: 'inbound',
          status: 'disconnected',
        );

        final stateFuture = service.stateStream.first;
        bridge.onPeerDisconnected!(disconnConn);

        final updatedState = await stateFuture.timeout(
          const Duration(seconds: 1),
        );
        expect(updatedState.connections, isEmpty);
        expect(service.currentState.connections, isEmpty);
      },
    );

    test('onAddressesUpdated updates state addresses and emits', () async {
      // Start the node so we have a valid state
      bridge.responses['node:start'] = {
        'ok': true,
        'peerId': _testPeerId,
        'isStarted': true,
        'listenAddresses': [],
        'circuitAddresses': [],
        'connections': [],
      };
      await service.startNodeCore(_testBase64Key, _testPeerId);
      expect(service.currentState.circuitAddresses, isEmpty);

      final stateFuture = service.stateStream.first;
      bridge.onAddressesUpdated!(
        ['/ip4/127.0.0.1/tcp/1234'],
        ['/p2p-circuit/relay'],
      );

      final updatedState = await stateFuture.timeout(
        const Duration(seconds: 1),
      );
      expect(updatedState.listenAddresses, ['/ip4/127.0.0.1/tcp/1234']);
      expect(updatedState.circuitAddresses, ['/p2p-circuit/relay']);
      expect(service.currentState.circuitAddresses, ['/p2p-circuit/relay']);
    });

    test(
      'onAddressesUpdated re-registers push token if circuit non-empty and token stored',
      () async {
        // Start node and register a push token first
        bridge.responses['node:start'] = _nodeStartOk();
        bridge.responses['inbox:register_token'] = {
          'ok': true,
          'registered': true,
        };
        await service.startNodeCore(_testBase64Key, _testPeerId);
        await service.registerPushToken('my-fcm-token', 'ios');

        // Reset the call count to track re-registration
        final callCountBefore = bridge.sendCallCount;

        // Trigger addresses update with non-empty circuit
        bridge.onAddressesUpdated!(
          ['/ip4/127.0.0.1/tcp/1234'],
          ['/p2p-circuit/new-relay'],
        );

        // Allow async re-registration to complete
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have sent inbox:register_token again
        expect(bridge.sendCallCount, greaterThan(callCountBefore));
        expect(bridge.lastCommand, 'inbox:register_token');
      },
    );

    test(
      'onAddressesUpdated does NOT re-register push token if circuit empty',
      () async {
        bridge.responses['node:start'] = _nodeStartOk();
        bridge.responses['inbox:register_token'] = {
          'ok': true,
          'registered': true,
        };
        await service.startNodeCore(_testBase64Key, _testPeerId);
        await service.registerPushToken('my-fcm-token', 'ios');

        final callCountBefore = bridge.sendCallCount;

        // Trigger addresses update with EMPTY circuit
        bridge.onAddressesUpdated!(
          ['/ip4/127.0.0.1/tcp/1234'],
          [], // empty circuit
        );

        await Future.delayed(const Duration(milliseconds: 50));

        // No additional bridge calls should have been made — empty circuit
        // means no re-registration.
        expect(bridge.sendCallCount, callCountBefore);
      },
    );
  });

  // =========================================================================
  // incoming transport tagging
  // =========================================================================

  group('incoming transport tagging', () {
    test('bridge relay messages tagged transport=relay', () async {
      final message = ChatMessage(
        from: 'sender',
        to: 'receiver',
        content: 'hello relay',
        timestamp: '2024-01-01T00:00:00Z',
        isIncoming: true,
      );

      final messageFuture = service.messageStream.first;
      bridge.onMessageReceived!(message);

      final received = await messageFuture.timeout(const Duration(seconds: 1));
      expect(received.transport, 'relay');
    });

    test('local WiFi messages tagged transport=wifi', () async {
      final localMessageController =
          StreamController<_LocalChatMessage>.broadcast();
      final fakeLocalP2P = _FakeLocalP2PService(localMessageController);
      final localService = P2PServiceImpl(
        bridge: bridge,
        localP2PService: fakeLocalP2P,
      );
      addTearDown(() {
        localService.dispose();
        localMessageController.close();
      });

      final messageFuture = localService.messageStream.first;
      localMessageController.add(
        _LocalChatMessage(
          from: 'local-sender',
          to: 'local-receiver',
          content: 'hello wifi',
          timestamp: DateTime.now(),
          isIncoming: true,
        ),
      );

      final received = await messageFuture.timeout(const Duration(seconds: 1));
      expect(received.transport, 'wifi');
      expect(received.from, 'local-sender');
    });

    test('inbox drain messages tagged transport=inbox', () async {
      bridge.responses['node:start'] = _nodeStartOk();
      bridge.responses['inbox:retrieve'] = {
        'ok': true,
        'messages': [
          {
            'from': 'inbox-sender',
            'message':
                '{"type":"chat_message","version":"1","payload":{"id":"inbox-001","text":"hello"}}',
            'timestamp': 1700000000000,
          },
        ],
      };
      bridge.responses['node:status'] = _nodeStatusOk();

      await service.startNodeCore(_testBase64Key, _testPeerId);

      final messageFuture = service.messageStream.first;
      await service.drainOfflineInbox();

      final received = await messageFuture.timeout(const Duration(seconds: 1));
      expect(received.transport, 'inbox');
      expect(received.from, 'inbox-sender');
    });
  });

  // =========================================================================
  // dispose
  // =========================================================================

  group('dispose', () {
    test('clears bridge event handlers', () {
      expect(bridge.onMessageReceived, isNotNull);
      expect(bridge.onPeerConnected, isNotNull);
      expect(bridge.onPeerDisconnected, isNotNull);
      expect(bridge.onAddressesUpdated, isNotNull);

      service.dispose();

      expect(bridge.onMessageReceived, isNull);
      expect(bridge.onPeerConnected, isNull);
      expect(bridge.onPeerDisconnected, isNull);
      expect(bridge.onAddressesUpdated, isNull);
    });

    test('closes stream controllers', () async {
      service.dispose();

      // After dispose, adding to the stream should not work.
      // Listening to a closed stream yields done immediately.
      var stateStreamDone = false;
      service.stateStream.listen((_) {}, onDone: () => stateStreamDone = true);
      await Future.delayed(Duration.zero);
      expect(stateStreamDone, isTrue);

      var messageStreamDone = false;
      service.messageStream.listen(
        (_) {},
        onDone: () => messageStreamDone = true,
      );
      await Future.delayed(Duration.zero);
      expect(messageStreamDone, isTrue);
    });
  });

  // =========================================================================
  // warm-start fast circuit fallback
  // =========================================================================

  group('warm-start fast circuit fallback', () {
    test('no circuit after 2s triggers immediate health poll', () {
      fakeAsync((async) {
        final countBridge = _CountingBridge();
        countBridge.responses['node:start'] = _nodeStartNoCircuit();
        countBridge.responses['node:status'] = _nodeStatusOk();
        countBridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

        final svc = P2PServiceImpl(bridge: countBridge);

        // startNode calls startNodeCore then warmBackground
        svc.startNode(_testBase64Key, _testPeerId);
        async.flushMicrotasks();

        // Record baseline before the 2s delayed future fires
        final baselineCount = countBridge.nodeStatusCallCount;

        // Elapse 2 seconds — the Future.delayed(2s) inside warmBackground fires
        async.elapse(const Duration(seconds: 2));

        // The fast circuit fallback should have triggered _performHealthCheck,
        // which sends node:status
        expect(
          countBridge.nodeStatusCallCount,
          greaterThan(baselineCount),
          reason:
              'Fast circuit fallback should poll node:status after 2s '
              'when no circuit addresses are present',
        );

        svc.dispose();
      });
    });

    test('already online does not trigger extra poll', () {
      fakeAsync((async) {
        final countBridge = _CountingBridge();
        // node:start returns WITH circuit addresses (already online)
        countBridge.responses['node:start'] = _nodeStartOk();
        countBridge.responses['node:status'] = _nodeStatusOk();
        countBridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

        final svc = P2PServiceImpl(bridge: countBridge);

        svc.startNode(_testBase64Key, _testPeerId);
        async.flushMicrotasks();

        // Record count after startup settles
        final baselineCount = countBridge.nodeStatusCallCount;

        // Elapse 2 seconds — the fast circuit check fires but should skip
        // because circuitAddresses is already non-empty
        async.elapse(const Duration(seconds: 2));

        expect(
          countBridge.nodeStatusCallCount,
          baselineCount,
          reason:
              'Fast circuit fallback should NOT poll node:status when '
              'circuit addresses are already present',
        );

        svc.dispose();
      });
    });

    test('addresses:updated push before 2s prevents extra poll', () {
      fakeAsync((async) {
        final countBridge = _CountingBridge();
        // Start with no circuits
        countBridge.responses['node:start'] = _nodeStartNoCircuit();
        countBridge.responses['node:status'] = _nodeStatusOk();
        countBridge.responses['inbox:retrieve'] = {'ok': true, 'messages': []};

        final svc = P2PServiceImpl(bridge: countBridge);

        svc.startNode(_testBase64Key, _testPeerId);
        async.flushMicrotasks();

        // At 1 second, simulate a push event delivering circuit addresses
        async.elapse(const Duration(seconds: 1));
        countBridge.onAddressesUpdated!(
          ['/ip4/127.0.0.1/tcp/1234'],
          ['/p2p-circuit/relay'],
        );
        async.flushMicrotasks();

        // Record count after the push event
        final baselineCount = countBridge.nodeStatusCallCount;

        // At 2 seconds the delayed future fires — but now circuitAddresses
        // is non-empty, so no extra poll should happen
        async.elapse(const Duration(seconds: 1));

        expect(
          countBridge.nodeStatusCallCount,
          baselineCount,
          reason:
              'Fast circuit fallback should NOT poll node:status when '
              'addresses:updated push delivered circuits before the 2s timeout',
        );

        svc.dispose();
      });
    });
  });

  group('sendLocalMedia delegation', () {
    test('returns false when local P2P service is not configured', () async {
      final result = await service.sendLocalMedia(
        peerId: 'peer-x',
        filePath: '/tmp/test.jpg',
        mime: 'image/jpeg',
        mediaId: 'm-no-local',
        fromPeerId: 'me',
      );

      expect(result, isFalse);
    });

    test(
      'delegates sendLocalMedia to LocalP2PService with same args',
      () async {
        final controller = StreamController<LocalChatMessage>.broadcast();
        final local = _FakeLocalP2PService(controller)..sendMediaResult = true;
        final svc = P2PServiceImpl(bridge: bridge, localP2PService: local);
        addTearDown(() async {
          await controller.close();
          svc.dispose();
        });

        final result = await svc.sendLocalMedia(
          peerId: 'peer-123',
          filePath: '/tmp/media.jpg',
          mime: 'image/jpeg',
          mediaId: 'media-123',
          fromPeerId: 'sender-abc',
          durationMs: 1234,
          waveform: const [0.1, 0.2],
          filename: 'media.jpg',
        );

        expect(result, isTrue);
        expect(local.sendMediaCallCount, 1);
        expect(local.lastSendMediaArgs, {
          'peerId': 'peer-123',
          'filePath': '/tmp/media.jpg',
          'mime': 'image/jpeg',
          'mediaId': 'media-123',
          'fromPeerId': 'sender-abc',
          'durationMs': 1234,
          'waveform': const [0.1, 0.2],
          'filename': 'media.jpg',
        });
      },
    );
  });
}
