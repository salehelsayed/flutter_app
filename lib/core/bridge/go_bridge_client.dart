import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import '../database/db_write_transaction.dart';
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
    'group:validation_rejected',
    'group:publish_validation_rejected',
    'group:discovery',
    'group:publish_debug',
    'group:dispatcher_pressure',
    'group:dispatcher_overflow',
  };

  bool _initialized = false;
  bool _disposed = false;
  bool _intentionalEventStreamCancel = false;
  bool _eventStreamRecoveryInProgress = false;
  Future<void>? _reinitializeFuture;
  StreamSubscription<dynamic>? _eventSubscription;
  int _malformedPushEventCount = 0;
  int _unknownPushEventCount = 0;

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
    'group:sendReliable': _CmdSpec('groupSendReliable', true),
    'group:publishReaction': _CmdSpec('groupPublishReaction', true),
    'group:updateConfig': _CmdSpec('groupUpdateConfig', true),
    'group:generateNextKey': _CmdSpec('groupGenerateNextKey', true),
    'group:rotateKey': _CmdSpec('groupRotateKey', true),
    'group:updateKey': _CmdSpec('groupUpdateKey', true),
    'group:inboxStore': _CmdSpec('groupInboxStore', true),
    'group:inboxRetrieve': _CmdSpec('groupInboxRetrieve', true),
    'group:inboxRetrieveCursor': _CmdSpec('groupInboxRetrieveCursor', true),
    'group:historyRepairRange': _CmdSpec('groupHistoryRepairRange', true),
    'group:acknowledgeRecovery': _CmdSpec('groupAcknowledgeRecovery', false),
    'group.keygen': _CmdSpec('generateGroupKey', false),
    'group.encrypt': _CmdSpec('groupEncryptMessage', true),
    'group.decrypt': _CmdSpec('groupDecryptMessage', true),
    // Blob crypto
    'blob:keygen': _CmdSpec('blobKeygen', false),
    'blob:encrypt': _CmdSpec('blobEncrypt', true),
    'blob:decrypt': _CmdSpec('blobDecrypt', true),
    // Background task (iOS)
    'bg:begin': _CmdSpec('bgBegin', false, allowRawStringResponse: true),
    'bg:end': _CmdSpec('bgEnd', true),
  };

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _disposed = false;
    _intentionalEventStreamCancel = false;

    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_INIT_START',
      details: {'type': 'native'},
    );

    // Subscribe to push events from the Go layer
    debugPrint('[BRIDGE] Subscribing to EventChannel...');
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (error) => _handleEventStreamFailure('error', error),
      onDone: () => _handleEventStreamFailure('done', null),
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
  Future<void> reinitialize() {
    final activeReinitialize = _reinitializeFuture;
    if (activeReinitialize != null) {
      return activeReinitialize;
    }

    late final Future<void> future;
    future = _performReinitialize().whenComplete(() {
      if (identical(_reinitializeFuture, future)) {
        _reinitializeFuture = null;
      }
    });
    _reinitializeFuture = future;
    return future;
  }

  Future<void> _performReinitialize() async {
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
    _intentionalEventStreamCancel = true;
    try {
      await _eventSubscription?.cancel();
    } finally {
      _intentionalEventStreamCancel = false;
    }
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
    _disposed = true;
    _intentionalEventStreamCancel = true;
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

  @visibleForTesting
  int get debugMalformedPushEventCountForTest => _malformedPushEventCount;

  @visibleForTesting
  int get debugUnknownPushEventCountForTest => _unknownPushEventCount;

  void _emitRawGoFlowEvent(String? eventName, Map<String, dynamic> eventData) {
    if (eventName == null || !_rawFlowPassthroughEvents.contains(eventName)) {
      return;
    }
    emitFlowEvent(
      layer: 'GO',
      event: eventName,
      details: _rawGoFlowEventDetails(eventName, eventData),
    );
  }

  Map<String, dynamic> _rawGoFlowEventDetails(
    String eventName,
    Map<String, dynamic> eventData,
  ) {
    if (eventName != 'group_message:received') return eventData;

    final text = eventData['text'];
    final media = eventData['media'];
    return {
      if (eventData.containsKey('groupId')) 'groupId': eventData['groupId'],
      if (eventData.containsKey('senderId')) 'senderId': eventData['senderId'],
      if (eventData.containsKey('senderDeviceId'))
        'senderDeviceId': eventData['senderDeviceId'],
      if (eventData.containsKey('transportPeerId'))
        'transportPeerId': eventData['transportPeerId'],
      if (eventData.containsKey('messageId'))
        'messageId': eventData['messageId'],
      if (eventData.containsKey('keyEpoch')) 'keyEpoch': eventData['keyEpoch'],
      if (eventData.containsKey('decryptMs'))
        'decryptMs': eventData['decryptMs'],
      if (eventData.containsKey('deliveryMs'))
        'deliveryMs': eventData['deliveryMs'],
      if (text is String) 'textLength': text.length,
      if (media is List) 'mediaCount': media.length,
    };
  }

  Map<String, dynamic> _groupPushLossDiagnosticDetails({
    required String reason,
    String? error,
    String? streamFailureReason,
    Map<String, dynamic>? eventData,
  }) {
    final safeError = sanitizeDiagnosticText(error);
    final details = <String, dynamic>{
      'reason': reason,
      if (safeError.isNotEmpty) 'error': safeError,
      'streamFailureReason': ?streamFailureReason,
    };
    final data = eventData;
    if (data != null) {
      for (final field in const [
        'groupId',
        'messageId',
        'keyEpoch',
        'senderId',
        'senderDeviceId',
        'transportPeerId',
      ]) {
        if (data.containsKey(field)) {
          details[field] = data[field];
        }
      }
    }
    return details;
  }

  Map<String, Object?> _diagnosticDetails({
    required String reason,
    required int count,
    String? eventName,
    Object? error,
    Map<String, dynamic>? eventData,
  }) {
    final safeEventName = sanitizeDiagnosticText(eventName);
    final safeError = sanitizeDiagnosticText(error);
    final dataKeys = eventData == null
        ? const <String>[]
        : eventData.keys.map(sanitizeDiagnosticText).toList(growable: false);
    return {
      'reason': reason,
      'count': count,
      if (safeEventName.isNotEmpty) 'event': safeEventName,
      if (safeError.isNotEmpty) 'error': safeError,
      'dataKeyCount': dataKeys.length,
      if (dataKeys.isNotEmpty) 'dataKeys': dataKeys,
    };
  }

  void _recordMalformedPushEvent({
    required String reason,
    String? eventName,
    Object? error,
    Map<String, dynamic>? eventData,
  }) {
    _malformedPushEventCount++;
    final details = _diagnosticDetails(
      reason: reason,
      count: _malformedPushEventCount,
      eventName: eventName,
      error: error,
      eventData: eventData,
    );
    debugPrint(
      '[GoBridgeClient] Malformed push event: '
      'reason=$reason count=$_malformedPushEventCount',
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_MALFORMED_PUSH_EVENT',
      details: details,
    );
    logPushDiagnostic('go_bridge_malformed_push_event', details: details);
  }

  void _recordUnknownPushEvent(
    String eventName,
    Map<String, dynamic> eventData,
  ) {
    _unknownPushEventCount++;
    final details = _diagnosticDetails(
      reason: 'unknown_event',
      count: _unknownPushEventCount,
      eventName: eventName,
      eventData: eventData,
    );
    final safeEventName = sanitizeDiagnosticText(eventName);
    debugPrint('[GoBridgeClient] Unknown push event: $safeEventName');
    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_UNKNOWN_PUSH_EVENT',
      details: details,
    );
    logPushDiagnostic('go_bridge_unknown_push_event', details: details);
  }

  void _handleEventStreamFailure(String reason, Object? error) {
    if (_disposed || _intentionalEventStreamCancel) {
      debugPrint(
        '[BRIDGE] EventChannel $reason during intentional cancel; '
        'recovery skipped.',
      );
      return;
    }

    final safeError = sanitizeDiagnosticText(error);
    if (reason == 'error') {
      debugPrint('[BRIDGE] EventChannel ERROR: $safeError');
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_EVENT_STREAM_ERROR',
        details: {'error': safeError},
      );
    } else {
      debugPrint(
        '[BRIDGE] EventChannel DONE: stream closed; '
        'requesting bridge event-stream recovery.',
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_EVENT_STREAM_DONE',
        details: {},
      );
    }

    _initialized = false;
    logPushDiagnostic(
      'go_bridge_event_stream_$reason',
      details: {
        'recovery': 'requested',
        if (safeError.isNotEmpty) 'error': safeError,
      },
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GO_BRIDGE_EVENT_STREAM_RECOVERY_REQUESTED',
      details: {'reason': reason, if (safeError.isNotEmpty) 'error': safeError},
    );

    if (_eventStreamRecoveryInProgress) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_EVENT_STREAM_RECOVERY_COALESCED',
        details: {'reason': reason},
      );
      return;
    }

    unawaited(_recoverEventStream(reason, safeError));
  }

  Future<void> _recoverEventStream(String reason, String safeError) async {
    _eventStreamRecoveryInProgress = true;
    try {
      await reinitialize();
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_EVENT_STREAM_RECOVERY_SUCCESS',
        details: {'reason': reason},
      );
      emitGroupDiagnosticEvent(
        groupPushLossDetectedEvent,
        _groupPushLossDiagnosticDetails(
          reason: 'event_stream_recovered',
          streamFailureReason: reason,
          error: safeError,
        ),
      );
    } catch (error) {
      _initialized = false;
      emitFlowEvent(
        layer: 'FL',
        event: 'GO_BRIDGE_EVENT_STREAM_RECOVERY_FAILED',
        details: {
          'reason': reason,
          if (safeError.isNotEmpty) 'eventError': safeError,
          'error': sanitizeDiagnosticText(error),
        },
      );
    } finally {
      _eventStreamRecoveryInProgress = false;
    }
  }

  /// Handle push events from the Go layer.
  void _handleEvent(dynamic event) {
    if (event is! String) {
      _recordMalformedPushEvent(
        reason: 'non_string_event',
        error: 'type=${event.runtimeType}',
      );
      return;
    }

    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic>) {
        _recordMalformedPushEvent(
          reason: 'non_object_event',
          error: 'type=${decoded.runtimeType}',
        );
        return;
      }
      data = decoded;
    } catch (e) {
      _recordMalformedPushEvent(reason: 'invalid_json', error: e.runtimeType);
      return;
    }

    final eventValue = data['event'];
    if (eventValue is! String || eventValue.trim().isEmpty) {
      _recordMalformedPushEvent(
        reason: 'missing_event_name',
        eventName: eventValue?.toString(),
      );
      return;
    }

    final eventName = eventValue;
    final dataValue = data['data'];
    final Map<String, dynamic> eventData;
    if (dataValue == null) {
      eventData = {};
    } else if (dataValue is Map<String, dynamic>) {
      eventData = dataValue;
    } else {
      _recordMalformedPushEvent(
        reason: 'malformed_event_data',
        eventName: eventName,
        error: 'type=${dataValue.runtimeType}',
      );
      return;
    }

    try {
      final safeEventName = sanitizeDiagnosticText(eventName);
      debugPrint('[BRIDGE-EVENT] Push event received: $safeEventName');

      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_PUSH_EVENT_RECEIVED',
        details: {'event': safeEventName},
      );
      _emitRawGoFlowEvent(eventName, eventData);

      switch (eventName) {
        case 'message:received':
          if (onMessageReceived != null) {
            try {
              final chatMessage = ChatMessage.fromJson(eventData);
              onMessageReceived!(chatMessage);
            } catch (e) {
              debugPrint(
                '[GoBridgeClient] Error parsing chat message: '
                '${sanitizeDiagnosticText(e)}',
              );
            }
          }
          break;

        case 'peer:connected':
          if (onPeerConnected != null) {
            try {
              final connState = ConnectionState.fromJson(eventData);
              onPeerConnected!(connState);
            } catch (e) {
              debugPrint(
                '[GoBridgeClient] Error parsing peer connected: '
                '${sanitizeDiagnosticText(e)}',
              );
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
                '[GoBridgeClient] Error parsing peer disconnected: '
                '${sanitizeDiagnosticText(e)}',
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
              final error = sanitizeDiagnosticText(e);
              debugPrint(
                '[GoBridgeClient] Error handling group message: '
                '$error',
              );
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_MESSAGE_CALLBACK_ERROR',
                details: {'error': error},
              );
              emitGroupDiagnosticEvent(
                groupPushLossDetectedEvent,
                _groupPushLossDiagnosticDetails(
                  reason: 'group_message_callback_error',
                  error: error,
                  eventData: eventData,
                ),
              );
            }
          }
          break;

        case 'group_reaction:received':
          if (onGroupReactionReceived != null) {
            try {
              onGroupReactionReceived!(eventData);
            } catch (e) {
              final error = sanitizeDiagnosticText(e);
              debugPrint(
                '[GoBridgeClient] Error handling group reaction: '
                '$error',
              );
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_REACTION_CALLBACK_ERROR',
                details: {'error': error},
              );
            }
          }
          break;

        // Forward Go diagnostic events to FLOW logs for debugging.
        case 'group:decryption_failed':
        case 'group:payload_parse_failed':
        case 'group:validation_rejected':
        case 'group:publish_validation_rejected':
        case 'group:discovery':
        case 'group:publish_debug':
        case 'group:dispatcher_pressure':
        case 'group:dispatcher_overflow':
          if (eventName == 'group:decryption_failed' ||
              eventName == 'group:payload_parse_failed' ||
              eventName == 'group:validation_rejected' ||
              eventName == 'group:publish_validation_rejected' ||
              eventName == 'group:dispatcher_pressure' ||
              eventName == 'group:dispatcher_overflow') {
            emitGroupDiagnosticEvent(eventName, eventData);
          }
          if (eventName == 'group:dispatcher_pressure' ||
              eventName == 'group:dispatcher_overflow') {
            logPushDiagnostic(
              eventName.replaceAll(':', '_'),
              details: eventData.map(
                (key, value) => MapEntry(key, value as Object?),
              ),
            );
          }
          emitFlowEvent(
            layer: 'GO',
            event: eventName.replaceAll(':', '_').toUpperCase(),
            details: eventData,
          );
          break;

        default:
          _recordUnknownPushEvent(eventName, eventData);
      }
    } catch (e) {
      debugPrint(
        '[GoBridgeClient] Error handling event: ${sanitizeDiagnosticText(e)}',
      );
    }
  }

  @override
  Future<String> send(String message) async {
    final Map<String, dynamic> request;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return _invalidBridgeRequest('Bridge request must be a JSON object');
      }
      request = decoded;
    } catch (_) {
      return _invalidBridgeRequest('Bridge request must be valid JSON');
    }

    final rawCmd = request['cmd'];
    if (rawCmd is! String || rawCmd.trim().isEmpty) {
      return _invalidBridgeRequest('Bridge request missing valid cmd');
    }
    final cmd = rawCmd;

    final rawPayload = request['payload'];
    if (rawPayload != null && rawPayload is! Map<String, dynamic>) {
      return _invalidBridgeRequest(
        'Bridge request payload must be a JSON object',
      );
    }
    final payload = rawPayload as Map<String, dynamic>?;

    // Refuse to issue a native-bridge round-trip from inside a SQLCipher
    // write transaction. Holding the DB lock across this hop is what
    // produced the 10-second "database has been locked" warnings and the
    // stuck Orbit skeleton state.
    assertNotInsideDbWriteTransaction(commandPreview: cmd);

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

      if (result == null) {
        return jsonEncode({
          'ok': false,
          'errorCode': 'NULL_RESPONSE',
          'errorMessage': 'Native bridge returned null',
        });
      }
      if (spec.allowRawStringResponse) {
        return result;
      }
      return _sanitizeBridgeResult(result);
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
          'error': sanitizeDiagnosticText(e.message ?? e.toString()),
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
        details: {
          'cmd': cmd,
          'error': sanitizeDiagnosticText(e.message ?? 'unknown'),
        },
      );
      final safeMessage = sanitizeDiagnosticText(
        e.message ?? 'Platform channel error',
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'PLATFORM_ERROR',
        'errorMessage': safeMessage,
      });
    } catch (e) {
      bridgeStopwatch.stop();
      final safeError = sanitizeDiagnosticText(e);
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
        details: {'cmd': cmd, 'method': spec.methodName, 'error': safeError},
      );
      return jsonEncode({
        'ok': false,
        'errorCode': 'BRIDGE_EXCEPTION',
        'errorMessage': safeError,
      });
    }
  }
}

String _invalidBridgeRequest(String errorMessage) {
  return jsonEncode({
    'ok': false,
    'errorCode': 'INVALID_INPUT',
    'errorMessage': errorMessage,
  });
}

String _sanitizeBridgeResult(String result) {
  try {
    final decoded = jsonDecode(result);
    if (decoded is! Map<String, dynamic>) {
      return jsonEncode({
        'ok': false,
        'errorCode': 'MALFORMED_RESPONSE',
        'errorMessage': 'Native bridge returned malformed JSON',
      });
    }
    if (decoded['ok'] == false) {
      final errorMessage = decoded['errorMessage'];
      if (errorMessage is String) {
        return jsonEncode({
          ...decoded,
          'errorMessage': sanitizeDiagnosticText(errorMessage),
        });
      }
    }
  } catch (_) {
    return jsonEncode({
      'ok': false,
      'errorCode': 'MALFORMED_RESPONSE',
      'errorMessage': 'Native bridge returned malformed JSON',
    });
  }
  return result;
}

class _CmdSpec {
  final String methodName;
  final bool hasPayload;
  final bool allowRawStringResponse;

  const _CmdSpec(
    this.methodName,
    this.hasPayload, {
    this.allowRawStringResponse = false,
  });
}
