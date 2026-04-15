import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../utils/flow_event_emitter.dart';
import '../utils/push_diagnostics_logger.dart';

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
  static const _rawFlowPassthroughEvents = <String>{
    'node:startup_timing',
    'relay:warm_timing',
    'circuit_address:timing',
    'inbox:store_timing',
    'inbox:retrieve_timing',
    'media:stream_open_timing',
    'media:upload_progress',
    'media:upload_complete',
    'profile:upload_progress',
    'message:direct_ack_timing',
    'timeout:fired',
    'group_message:received',
    'group:decryption_failed',
    'group:payload_parse_failed',
    'group:discovery',
    'group:publish_debug',
    'group:dispatcher_pressure',
    'group:dispatcher_overflow',
  };

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
    'contactrequest.encrypt': _CmdSpec('encryptContactRequest', true),
    'contactrequest.decrypt': _CmdSpec('decryptContactRequest', true),
    // Node
    'node:start': _CmdSpec('startNode', true),
    'node:stop': _CmdSpec('stopNode', false),
    'node:status': _CmdSpec('nodeStatus', false),
    // Rendezvous
    'rendezvous:register': _CmdSpec('rendezvousRegister', true),
    'rendezvous:discover': _CmdSpec('rendezvousDiscover', true),
    // Relay
    'relay:reconnect': _CmdSpec('relayReconnect', false),
    'relay:probe': _CmdSpec('relayProbe', true),
    // Peer
    'peer:dial': _CmdSpec('dialPeer', true),
    'peer:disconnect': _CmdSpec('disconnectPeer', true),
    // Messaging
    'message:send': _CmdSpec('sendMessage', true),
    'message:confirm': _CmdSpec('confirmDirectMessage', true),
    // Inbox
    'inbox:store': _CmdSpec('inboxStore', true),
    'inbox:retrieve': _CmdSpec('inboxRetrieve', true),
    'inbox:retrieve_pending': _CmdSpec('inboxRetrievePending', true),
    'inbox:ack': _CmdSpec('inboxAck', true),
    'inbox:register_token': _CmdSpec('inboxRegisterToken', true),
    // Media
    'media:upload': _CmdSpec('mediaUpload', true),
    'media:download': _CmdSpec('mediaDownload', true),
    'media:delete': _CmdSpec('mediaDelete', true),
    'media:list': _CmdSpec('mediaList', true),
    // Profile
    'profile:upload': _CmdSpec('profileUpload', true),
    'profile:download': _CmdSpec('profileDownload', true),
    // Groups
    'group:create': _CmdSpec('groupCreate', true),
    'group:join': _CmdSpec('groupJoinTopic', true),
    'group:leave': _CmdSpec('groupLeaveTopic', true),
    'group:publish': _CmdSpec('groupPublish', true),
    'group:publishReaction': _CmdSpec('groupPublishReaction', true),
    'group:updateConfig': _CmdSpec('groupUpdateConfig', true),
    'group:generateNextKey': _CmdSpec('groupGenerateNextKey', true),
    'group:rotateKey': _CmdSpec('groupRotateKey', true),
    'group:updateKey': _CmdSpec('groupUpdateKey', true),
    'group:inboxStore': _CmdSpec('groupInboxStore', true),
    'group:inboxRetrieve': _CmdSpec('groupInboxRetrieve', true),
    'group:inboxRetrieveCursor': _CmdSpec('groupInboxRetrieveCursor', true),
    'group:acknowledgeRecovery': _CmdSpec('groupAcknowledgeRecovery', false),
    'group.keygen': _CmdSpec('generateGroupKey', false),
    'group.encrypt': _CmdSpec('groupEncryptMessage', true),
    'group.decrypt': _CmdSpec('groupDecryptMessage', true),
    // Blob crypto
    'blob:keygen': _CmdSpec('blobKeygen', false),
    'blob:encrypt': _CmdSpec('blobEncrypt', true),
    'blob:decrypt': _CmdSpec('blobDecrypt', true),
    // Background task (iOS)
    'bg:begin': _CmdSpec('bgBegin', false),
    'bg:end': _CmdSpec('bgEnd', true),
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
        debugPrint(
          '[BRIDGE] ⚠ EventChannel DONE — stream closed! '
          'No more push events will be received.',
        );
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
      final response = await send(
        jsonEncode({'cmd': 'node:status'}),
      ).timeout(const Duration(seconds: 5));
      final ms = DateTime.now().difference(start).inMilliseconds;
      final data = jsonDecode(response);
      final ok = data['ok'] == true;
      debugPrint(
        '[BRIDGE] checkHealth() → ok=$ok, '
        'isStarted=${data['isStarted']}, '
        'circuitAddresses=${(data['circuitAddresses'] as List?)?.length ?? 0} '
        '(took ${ms}ms)',
      );
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
    debugPrint(
      '[BRIDGE] reinitialize() starting — '
      'cancelling event subscription and re-subscribing...',
    );
    emitFlowEvent(layer: 'FL', event: 'GO_BRIDGE_REINIT_START', details: {});

    // Preserve callbacks
    final savedOnMessage = onMessageReceived;
    final savedOnConnect = onPeerConnected;
    final savedOnDisconnect = onPeerDisconnected;
    final savedOnAddresses = onAddressesUpdated;
    final savedOnRelayState = onRelayStateChanged;
    final savedOnGroupMessage = onGroupMessageReceived;
    final savedOnGroupReaction = onGroupReactionReceived;

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
    onRelayStateChanged = savedOnRelayState;
    onGroupMessageReceived = savedOnGroupMessage;
    onGroupReactionReceived = savedOnGroupReaction;

    // Re-initialize
    await initialize();
    debugPrint(
      '[BRIDGE] reinitialize() complete — '
      'event stream re-subscribed',
    );
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
    onRelayStateChanged = null;
    onGroupMessageReceived = null;
    onGroupReactionReceived = null;
  }

  @visibleForTesting
  void debugHandleEventForTest(dynamic event) => _handleEvent(event);

  void _emitRawGoFlowEvent(String? eventName, Map<String, dynamic> eventData) {
    if (eventName == null || !_rawFlowPassthroughEvents.contains(eventName)) {
      return;
    }
    emitFlowEvent(layer: 'GO', event: eventName, details: eventData);
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
      _emitRawGoFlowEvent(eventName, eventData);

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
                '[GoBridgeClient] Error parsing peer disconnected: $e',
              );
            }
          }
          break;

        case 'addresses:updated':
          if (onAddressesUpdated != null) {
            final listenAddrs =
                (eventData['listenAddresses'] as List<dynamic>?)
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

        case 'relay:state':
          if (onRelayStateChanged != null) {
            onRelayStateChanged!(eventData);
          }
          break;

        case 'media:upload_progress':
          emitMediaUploadProgressEvent(eventData);
          break;

        case 'node:startup_timing':
        case 'relay:warm_timing':
        case 'circuit_address:timing':
        case 'inbox:store_timing':
        case 'inbox:retrieve_timing':
        case 'media:stream_open_timing':
        case 'media:upload_complete':
        case 'profile:upload_progress':
        case 'message:direct_ack_timing':
        case 'timeout:fired':
          break;

        case 'group_message:received':
          if (onGroupMessageReceived != null) {
            try {
              onGroupMessageReceived!(eventData);
            } catch (e) {
              debugPrint('[GoBridgeClient] Error handling group message: $e');
            }
          }
          break;

        case 'group_reaction:received':
          if (onGroupReactionReceived != null) {
            try {
              onGroupReactionReceived!(eventData);
            } catch (e) {
              debugPrint('[GoBridgeClient] Error handling group reaction: $e');
            }
          }
          break;

        // Forward Go diagnostic events to FLOW logs for debugging.
        case 'group:decryption_failed':
        case 'group:payload_parse_failed':
        case 'group:discovery':
        case 'group:publish_debug':
        case 'group:dispatcher_pressure':
        case 'group:dispatcher_overflow':
          if (eventName == 'group:decryption_failed' ||
              eventName == 'group:payload_parse_failed' ||
              eventName == 'group:dispatcher_pressure' ||
              eventName == 'group:dispatcher_overflow') {
            emitGroupDiagnosticEvent(eventName!, eventData);
          }
          if (eventName == 'group:dispatcher_pressure' ||
              eventName == 'group:dispatcher_overflow') {
            logPushDiagnostic(
              eventName!.replaceAll(':', '_'),
              details: eventData.map(
                (key, value) => MapEntry(key, value as Object?),
              ),
            );
          }
          emitFlowEvent(
            layer: 'GO',
            event: eventName!.replaceAll(':', '_').toUpperCase(),
            details: eventData,
          );
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

    final bridgeStopwatch = Stopwatch()..start();
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
      bridgeStopwatch.stop();

      emitFlowEvent(
        layer: 'FL',
        event: 'BRIDGE_CALL_TIMING',
        details: {
          'cmd': cmd,
          'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
          'outcome': 'success',
        },
      );

      return result ??
          jsonEncode({
            'ok': false,
            'errorCode': 'NULL_RESPONSE',
            'errorMessage': 'Native bridge returned null',
          });
    } on MissingPluginException catch (e) {
      bridgeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'BRIDGE_CALL_TIMING',
        details: {
          'cmd': cmd,
          'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
          'outcome': 'missing_plugin',
        },
      );
      final errorMessage =
          'Native bridge method ${spec.methodName} is not available for '
          '$cmd on channel com.mknoon/go_bridge. Rebuild the app with the '
          'updated native bridge.';
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_MISSING_PLUGIN',
        details: {
          'cmd': cmd,
          'method': spec.methodName,
          'initialized': _initialized,
          'error': e.message ?? e.toString(),
        },
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'MISSING_PLUGIN',
        'errorMessage': errorMessage,
      });
    } on PlatformException catch (e) {
      bridgeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'BRIDGE_CALL_TIMING',
        details: {
          'cmd': cmd,
          'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
          'outcome': 'platform_error',
        },
      );
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
    } catch (e) {
      bridgeStopwatch.stop();
      emitFlowEvent(
        layer: 'FL',
        event: 'BRIDGE_CALL_TIMING',
        details: {
          'cmd': cmd,
          'bridgeMs': bridgeStopwatch.elapsedMilliseconds,
          'outcome': 'error',
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_UNEXPECTED_ERROR',
        details: {'cmd': cmd, 'method': spec.methodName, 'error': e.toString()},
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'BRIDGE_EXCEPTION',
        'errorMessage': e.toString(),
      });
    }
  }
}

class _CmdSpec {
  final String methodName;
  final bool hasPayload;

  const _CmdSpec(this.methodName, this.hasPayload);
}
