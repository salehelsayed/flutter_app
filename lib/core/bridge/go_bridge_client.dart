import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../utils/flow_event_emitter.dart';

/// Dart bridge client that communicates with the Go native library
/// via Flutter platform channels.
///
/// Extends [Bridge] so it can be used as a drop-in replacement
/// for any bridge implementation. The [send] method translates the
/// cmd-based protocol to MethodChannel calls.
///
/// Push events from Go (message:received, peer:connected, etc.)
/// are streamed via the EventChannel and routed to the inherited
/// [onMessageReceived], [onPeerConnected], and [onPeerDisconnected]
/// callbacks.
class GoBridgeClient extends Bridge {
  static const _methodChannel = MethodChannel('com.mknoon/go_bridge');
  static const _eventChannel = EventChannel('com.mknoon/go_bridge_events');

  bool _initialized = false;
  StreamSubscription<dynamic>? _eventSubscription;

  @override
  bool get isInitialized => _initialized;

  /// Map of cmd to (methodName, hasPayload).
  ///
  /// Keys match the command strings sent by [call*] and [callP2P*]
  /// helper functions — identity/crypto use dots, P2P uses colons.
  static const _cmdMap = <String, _CmdSpec>{
    // Identity
    'identity.generate': _CmdSpec('generateIdentity', false),
    'identity.restore': _CmdSpec('restoreIdentity', true),
    // Crypto
    'mlkem.keygen': _CmdSpec('mlKemKeygen', false),
    'message.encrypt': _CmdSpec('encryptMessage', true),
    'message.decrypt': _CmdSpec('decryptMessage', true),
    'payload.sign': _CmdSpec('signPayload', true),
    'payload.verify': _CmdSpec('verifyPayload', true),
    // Node
    'node:start': _CmdSpec('startNode', true),
    'node:stop': _CmdSpec('stopNode', false),
    'node:status': _CmdSpec('nodeStatus', false),
    // Rendezvous
    'rendezvous:register': _CmdSpec('rendezvousRegister', true),
    'rendezvous:discover': _CmdSpec('rendezvousDiscover', true),
    // Relay
    'relay:reconnect': _CmdSpec('relayReconnect', false),
    // Peer
    'peer:dial': _CmdSpec('dialPeer', true),
    'peer:disconnect': _CmdSpec('disconnectPeer', true),
    // Messaging
    'message:send': _CmdSpec('sendMessage', true),
    // Inbox
    'inbox:store': _CmdSpec('inboxStore', true),
    'inbox:retrieve': _CmdSpec('inboxRetrieve', false),
    'inbox:register_token': _CmdSpec('inboxRegisterToken', true),
    // Media
    'media:upload': _CmdSpec('mediaUpload', true),
    'media:download': _CmdSpec('mediaDownload', true),
    'media:delete': _CmdSpec('mediaDelete', true),
    'media:list': _CmdSpec('mediaList', true),
    // Profile
    'profile:upload': _CmdSpec('profileUpload', true),
    'profile:download': _CmdSpec('profileDownload', true),
  };

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_INIT_START',
      details: {'type': 'native'},
    );

    // Subscribe to push events from the Go layer
    debugPrint('[BRIDGE] Subscribing to EventChannel...');
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (error) {
        debugPrint('[BRIDGE] ⚠ EventChannel ERROR: $error');
        emitFlowEvent(
          layer: 'FL',
          event: 'GO_BRIDGE_EVENT_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        debugPrint('[BRIDGE] ⚠ EventChannel DONE — stream closed! '
            'No more push events will be received.');
        emitFlowEvent(
          layer: 'FL',
          event: 'GO_BRIDGE_EVENT_STREAM_DONE',
          details: {},
        );
      },
    );

    _initialized = true;

    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_INIT_SUCCESS',
      details: {'type': 'native'},
    );
  }

  @override
  Future<bool> checkHealth() async {
    debugPrint('[BRIDGE] checkHealth() called, _initialized=$_initialized');
    if (!_initialized) return false;

    try {
      final start = DateTime.now();
      final response = await send(jsonEncode({'cmd': 'node:status'}))
          .timeout(const Duration(seconds: 5));
      final ms = DateTime.now().difference(start).inMilliseconds;
      final data = jsonDecode(response);
      final ok = data['ok'] == true;
      debugPrint('[BRIDGE] checkHealth() → ok=$ok, '
          'isStarted=${data['isStarted']}, '
          'circuitAddresses=${(data['circuitAddresses'] as List?)?.length ?? 0} '
          '(took ${ms}ms)');
      return ok;
    } catch (e) {
      debugPrint('[BRIDGE] checkHealth() FAILED: $e');
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_HEALTH_CHECK_FAILED',
        details: {},
      );
      return false;
    }
  }

  @override
  Future<void> reinitialize() async {
    debugPrint('[BRIDGE] reinitialize() starting — '
        'cancelling event subscription and re-subscribing...');
    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_REINIT_START',
      details: {},
    );

    // Preserve callbacks
    final savedOnMessage = onMessageReceived;
    final savedOnConnect = onPeerConnected;
    final savedOnDisconnect = onPeerDisconnected;
    final savedOnAddresses = onAddressesUpdated;

    // Cancel existing subscription
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _initialized = false;
    debugPrint('[BRIDGE] Event subscription cancelled, re-initializing...');

    // Restore callbacks
    onMessageReceived = savedOnMessage;
    onPeerConnected = savedOnConnect;
    onPeerDisconnected = savedOnDisconnect;
    onAddressesUpdated = savedOnAddresses;

    // Re-initialize
    await initialize();
    debugPrint('[BRIDGE] reinitialize() complete — '
        'event stream re-subscribed');
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _initialized = false;
    onMessageReceived = null;
    onPeerConnected = null;
    onPeerDisconnected = null;
    onAddressesUpdated = null;
  }

  /// Handle push events from the Go layer.
  void _handleEvent(dynamic event) {
    try {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      final eventName = data['event'] as String?;
      final eventData = data['data'] as Map<String, dynamic>? ?? {};

      debugPrint('[BRIDGE-EVENT] Push event received: $eventName');

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_PUSH_EVENT_RECEIVED',
        details: {'event': eventName},
      );

      switch (eventName) {
        case 'message:received':
          if (onMessageReceived != null) {
            try {
              final chatMessage = ChatMessage.fromJson(eventData);
              onMessageReceived!(chatMessage);
            } catch (e) {
              debugPrint('[GoBridgeClient] Error parsing chat message: $e');
            }
          }
          break;

        case 'peer:connected':
          if (onPeerConnected != null) {
            try {
              final connState = ConnectionState.fromJson(eventData);
              onPeerConnected!(connState);
            } catch (e) {
              debugPrint('[GoBridgeClient] Error parsing peer connected: $e');
            }
          }
          break;

        case 'peer:disconnected':
          if (onPeerDisconnected != null) {
            try {
              final connState = ConnectionState.fromJson(eventData);
              onPeerDisconnected!(connState);
            } catch (e) {
              debugPrint(
                  '[GoBridgeClient] Error parsing peer disconnected: $e');
            }
          }
          break;

        case 'addresses:updated':
          if (onAddressesUpdated != null) {
            final listenAddrs = (eventData['listenAddresses'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                [];
            final circuitAddrs =
                (eventData['circuitAddresses'] as List<dynamic>?)
                        ?.map((e) => e as String)
                        .toList() ??
                    [];
            onAddressesUpdated!(listenAddrs, circuitAddrs);
          }
          break;

        default:
          debugPrint('[GoBridgeClient] Unknown push event: $eventName');
      }
    } catch (e) {
      debugPrint('[GoBridgeClient] Error handling event: $e');
    }
  }

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final cmd = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;

    final spec = _cmdMap[cmd];
    if (spec == null) {
      return jsonEncode({
        'ok': false,
        'errorCode': 'UNKNOWN_COMMAND',
        'errorMessage': 'Unknown command: $cmd',
      });
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_SEND',
      details: {'cmd': cmd, 'method': spec.methodName},
    );

    try {
      final String? result;
      if (spec.hasPayload && payload != null) {
        result = await _methodChannel.invokeMethod<String>(
          spec.methodName,
          jsonEncode(payload),
        );
      } else {
        result = await _methodChannel.invokeMethod<String>(spec.methodName);
      }

      return result ??
          jsonEncode({
            'ok': false,
            'errorCode': 'NULL_RESPONSE',
            'errorMessage': 'Native bridge returned null',
          });
    } on PlatformException catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_PLATFORM_ERROR',
        details: {'cmd': cmd, 'error': e.message ?? 'unknown'},
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'PLATFORM_ERROR',
        'errorMessage': e.message ?? 'Platform channel error',
      });
    }
  }
}

class _CmdSpec {
  final String methodName;
  final bool hasPayload;

  const _CmdSpec(this.methodName, this.hasPayload);
}
