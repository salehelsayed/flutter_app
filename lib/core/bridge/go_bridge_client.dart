import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'bridge.dart';
import 'debug_group_delivery_observer.dart';
import '../database/db_write_transaction.dart';
import '../diagnostics/app_diagnostics.dart';
import '../diagnostics/local_connection_diagnostics.dart';
import '../../features/p2p/domain/models/chat_message.dart';
import '../../features/p2p/domain/models/connection_state.dart';
import '../local_discovery/local_discovery_service.dart';
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
  static const _transportDiagnosticEvents = <String>{
    'holepunch:attempt',
    'holepunch:success',
    'holepunch:failure',
    'transport:upgraded',
    'transport:downgraded',
  };
  static const _rawFlowPassthroughEvents = <String>{
    'node:startup_timing',
    'relay:warm_timing',
    'relay:reservation_timing',
    'circuit_address:timing',
    'inbox:store_timing',
    'inbox:retrieve_timing',
    'media:stream_open_timing',
    'media:upload_progress',
    'media:upload_complete',
    'media:download_complete',
    'media:download_failed',
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
    'holepunch:attempt',
    'holepunch:success',
    'holepunch:failure',
    'transport:upgraded',
    'transport:downgraded',
    // FDC-S5 (M1): native bridge dispatch queue-wait. Emitted (DEBUG builds only)
    // by the iOS/Android bridge with {method, queueWaitMs} = the time a call sat
    // between the platform-channel receive and the background-dispatch slot — the
    // thread-pool serialization signal. Surfaced here alongside BRIDGE_CALL_TIMING
    // {bridgeMs} so the deferred two-device M1 run can read the queue-wait delta
    // under concurrent warmPeer without any further client change.
    'bridge:dispatch_timing',
  };

  bool _initialized = false;
  bool _disposed = false;
  bool _intentionalEventStreamCancel = false;
  bool _eventStreamRecoveryInProgress = false;
  Future<void>? _reinitializeFuture;
  StreamSubscription<dynamic>? _eventSubscription;
  int _malformedPushEventCount = 0;
  int _unknownPushEventCount = 0;

  /// FDC-15: callback for an inbound libp2p-LAN media blob (the Go
  /// `media:lan_received` event). Declared on the concrete client (NOT the
  /// abstract [Bridge]) so adding it does not break the many `implements Bridge`
  /// fakes. Production wires this to the `linkIncomingLocalMedia` pipeline in
  /// main.dart; left null until the lane is active.
  void Function(LocalMediaReady)? onLocalMediaReceived;

  @override
  bool get isInitialized => _initialized;

  /// Map of cmd to (methodName, hasPayload).
  ///
  /// Keys match the command strings sent by [call*] and [callP2P*]
  /// helper functions — identity/crypto use dots, P2P uses colons.
  static const _cmdMap = <String, _CmdSpec>{
    // Identity
    'identity.generate': _CmdSpec(
      _BridgeCommandFamily.identity,
      'generateIdentity',
      false,
    ),
    'identity.restore': _CmdSpec(
      _BridgeCommandFamily.identity,
      'restoreIdentity',
      true,
    ),
    // Crypto
    'mlkem.keygen': _CmdSpec(_BridgeCommandFamily.crypto, 'mlKemKeygen', false),
    'message.encrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'encryptMessage',
      true,
    ),
    'message.decrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'decryptMessage',
      true,
    ),
    'payload.sign': _CmdSpec(_BridgeCommandFamily.crypto, 'signPayload', true),
    'payload.verify': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'verifyPayload',
      true,
    ),
    'contactrequest.encrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'encryptContactRequest',
      true,
    ),
    'contactrequest.decrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'decryptContactRequest',
      true,
    ),
    // Account-move transfer session crypto (protocol v2)
    'migration.session.encap': _CmdSpec(
      _BridgeCommandFamily.migration,
      'migrationSessionEncap',
      true,
    ),
    'migration.session.decap': _CmdSpec(
      _BridgeCommandFamily.migration,
      'migrationSessionDecap',
      true,
    ),
    'migration.chunk.encrypt': _CmdSpec(
      _BridgeCommandFamily.migration,
      'migrationChunkEncrypt',
      true,
    ),
    'migration.chunk.decrypt': _CmdSpec(
      _BridgeCommandFamily.migration,
      'migrationChunkDecrypt',
      true,
    ),
    // Node
    'node:start': _CmdSpec(_BridgeCommandFamily.network, 'startNode', true),
    'node:stop': _CmdSpec(_BridgeCommandFamily.network, 'stopNode', false),
    'node:status': _CmdSpec(_BridgeCommandFamily.network, 'nodeStatus', false),
    // Rendezvous
    'rendezvous:register': _CmdSpec(
      _BridgeCommandFamily.network,
      'rendezvousRegister',
      true,
    ),
    'rendezvous:unregister': _CmdSpec(
      _BridgeCommandFamily.network,
      'rendezvousUnregister',
      true,
    ),
    'rendezvous:discover': _CmdSpec(
      _BridgeCommandFamily.network,
      'rendezvousDiscover',
      true,
    ),
    // Relay
    'relay:reconnect': _CmdSpec(
      _BridgeCommandFamily.network,
      'relayReconnect',
      false,
    ),
    'relay:probe': _CmdSpec(_BridgeCommandFamily.network, 'relayProbe', true),
    // SE-42 D27: call-media protection lease on the relay recovery broker.
    'call_media:protection': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callMediaProtection',
      true,
    ),
    turnCredentialsV1BridgeCommand: _CmdSpec(
      _BridgeCommandFamily.callControl,
      turnCredentialsV1NativeMethod,
      false,
    ),
    'call_diagnostics_v1': _CmdSpec(
      _BridgeCommandFamily.diagnostics,
      'callDiagnosticsV1',
      true,
    ),
    'app_diagnostics_v1': _CmdSpec(
      _BridgeCommandFamily.diagnostics,
      'appDiagnosticsV1',
      true,
    ),
    'turn_credentials_with_diagnostics_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'turnCredentialsWithDiagnosticsV1',
      true,
    ),
    'call_store_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callStoreV1',
      true,
    ),
    'call_retrieve_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callRetrieveV1',
      true,
    ),
    'call_ack_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callAckV1',
      true,
    ),
    'call_cancel_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callCancelV1',
      true,
    ),
    'call_endpoint_set_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callEndpointSetV1',
      true,
    ),
    'call_endpoint_get_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callEndpointGetV1',
      true,
    ),
    'call_endpoint_revoke_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callEndpointRevokeV1',
      true,
    ),
    'call_wake_handle_set_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callWakeHandleSetV1',
      true,
    ),
    'call_wake_handle_revoke_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callWakeHandleRevokeV1',
      true,
    ),
    'call_token_set_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callTokenSetV1',
      true,
    ),
    'call_token_revoke_v1': _CmdSpec(
      _BridgeCommandFamily.callControl,
      'callTokenRevokeV1',
      true,
    ),
    // FDC-08: cheap presence lookup (no circuit dial). Native MethodChannel
    // dispatch ('relayPresenceGet' -> Bridge PresenceGet) + gomobile framework
    // rebuild land with the S1 device/live-relay closure.
    'relay:presence_get': _CmdSpec(
      _BridgeCommandFamily.network,
      'relayPresenceGet',
      true,
    ),
    // FDC-09: self-publish foreground/background presence (WRITE twin of
    // presence_get). Native MethodChannel dispatch ('relayPresenceSet' -> Bridge
    // PresenceSet) + gomobile framework rebuild land with the device/live-relay
    // closure (same deferral as presence_get).
    'relay:presence_set': _CmdSpec(
      _BridgeCommandFamily.network,
      'relayPresenceSet',
      true,
    ),
    // Peer
    'peer:dial': _CmdSpec(_BridgeCommandFamily.network, 'dialPeer', true),
    'peer:disconnect': _CmdSpec(
      _BridgeCommandFamily.network,
      'disconnectPeer',
      true,
    ),
    // 183: active-chat keepalive liveness probe (libp2p ping). Native
    // MethodChannel dispatch ('peerPing' -> Bridge PeerPing) + gomobile framework
    // rebuild land with the two-phone device-proof (TC-183-50).
    'peer:ping': _CmdSpec(_BridgeCommandFamily.network, 'peerPing', true),
    // FDC-11: bonsoir-discovered same-WiFi peer → libp2p LAN-direct dial. Native
    // MethodChannel dispatch ('lanPeerFound' -> Bridge HandleLANPeerFound) +
    // gomobile framework rebuild land with the D1 device closure.
    'lan:peer_found': _CmdSpec(
      _BridgeCommandFamily.network,
      'lanPeerFound',
      true,
    ),
    // Messaging
    'message:send': _CmdSpec(
      _BridgeCommandFamily.messaging,
      'sendMessage',
      true,
    ),
    'message:confirm': _CmdSpec(
      _BridgeCommandFamily.messaging,
      'confirmDirectMessage',
      true,
    ),
    // Inbox
    'inbox:store': _CmdSpec(_BridgeCommandFamily.inbox, 'inboxStore', true),
    'inbox:retrieve': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxRetrieve',
      true,
    ),
    'inbox:retrieve_pending': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxRetrievePending',
      true,
    ),
    'inbox:ack': _CmdSpec(_BridgeCommandFamily.inbox, 'inboxAck', true),
    // Plan 370: default-off completed-notification outcome. Native platform
    // dispatch and framework adoption remain downstream work; this host bridge
    // registration is the sole Dart -> gomobile command seam.
    'inbox:wake_outcome': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxWakeOutcome',
      true,
    ),
    'inbox:register_token': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxRegisterToken',
      true,
    ),
    'inbox:unregister_token': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxUnregisterToken',
      true,
    ),
    // FDC-09 §12: register the recipient's opaque wake-token set (access-token
    // anti-spam gate). Native MethodChannel dispatch ('inboxRegisterWakeTokens'
    // -> Bridge RegisterWakeTokens) + framework rebuild land with the device
    // closure (same deferral as presence_get/presence_set).
    'inbox:register_wake_tokens': _CmdSpec(
      _BridgeCommandFamily.inbox,
      'inboxRegisterWakeTokens',
      true,
    ),
    // Media
    'media:upload': _CmdSpec(_BridgeCommandFamily.media, 'mediaUpload', true),
    'media:download': _CmdSpec(
      _BridgeCommandFamily.media,
      'mediaDownload',
      true,
    ),
    'media:delete': _CmdSpec(_BridgeCommandFamily.media, 'mediaDelete', true),
    'media:list': _CmdSpec(_BridgeCommandFamily.media, 'mediaList', true),
    // FDC-15: 1:1 media over a libp2p LAN stream. The native `mediaLanSend`
    // MethodChannel handler (GoBridge.swift/.kt) + the gomobile framework
    // rebuild land with the D1 device closure; this Dart-side registration is
    // host-complete so the send leg resolves the command at that point.
    'media:lan_send': _CmdSpec(
      _BridgeCommandFamily.media,
      'mediaLanSend',
      true,
    ),
    // Profile
    'profile:upload': _CmdSpec(
      _BridgeCommandFamily.profile,
      'profileUpload',
      true,
    ),
    'profile:download': _CmdSpec(
      _BridgeCommandFamily.profile,
      'profileDownload',
      true,
    ),
    // Groups
    'group:create': _CmdSpec(_BridgeCommandFamily.group, 'groupCreate', true),
    'group:join': _CmdSpec(_BridgeCommandFamily.group, 'groupJoinTopic', true),
    'group:leave': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupLeaveTopic',
      true,
    ),
    'group:publish': _CmdSpec(_BridgeCommandFamily.group, 'groupPublish', true),
    'group:sendReliable': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupSendReliable',
      true,
    ),
    'group:publishReaction': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupPublishReaction',
      true,
    ),
    'group:updateConfig': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupUpdateConfig',
      true,
    ),
    'group:generateNextKey': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupGenerateNextKey',
      true,
    ),
    'group:updateKey': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupUpdateKey',
      true,
    ),
    'group:inboxStore': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupInboxStore',
      true,
    ),
    'group:inboxRetrieve': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupInboxRetrieve',
      true,
    ),
    'group:inboxRetrieveCursor': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupInboxRetrieveCursor',
      true,
    ),
    'group:historyRepairRange': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupHistoryRepairRange',
      true,
    ),
    'group:acknowledgeRecovery': _CmdSpec(
      _BridgeCommandFamily.group,
      'groupAcknowledgeRecovery',
      false,
    ),
    'group.keygen': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'generateGroupKey',
      false,
    ),
    'group.encrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'groupEncryptMessage',
      true,
    ),
    'group.decrypt': _CmdSpec(
      _BridgeCommandFamily.crypto,
      'groupDecryptMessage',
      true,
    ),
    // Blob crypto
    'blob:keygen': _CmdSpec(_BridgeCommandFamily.crypto, 'blobKeygen', false),
    'blob:encrypt': _CmdSpec(_BridgeCommandFamily.crypto, 'blobEncrypt', true),
    'blob:decrypt': _CmdSpec(_BridgeCommandFamily.crypto, 'blobDecrypt', true),
    // Background task (iOS)
    'bg:begin': _CmdSpec(
      _BridgeCommandFamily.background,
      'bgBegin',
      false,
      allowRawStringResponse: true,
    ),
    'bg:end': _CmdSpec(_BridgeCommandFamily.background, 'bgEnd', true),
    // FDC-S4 measurement: read the OS background grant (seconds) and return it.
    'bg:grantProbe': _CmdSpec(
      _BridgeCommandFamily.background,
      'bgGrantProbe',
      false,
      allowRawStringResponse: true,
    ),
    'bg:timeRemaining': _CmdSpec(
      _BridgeCommandFamily.background,
      'bgTimeRemaining',
      false,
      allowRawStringResponse: true,
    ),
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
    if (_transportDiagnosticEvents.contains(eventName)) {
      return sanitizeTransportDiagnosticEventData(eventName, eventData);
    }
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

        case 'media:download_progress':
          emitMediaDownloadProgressEvent(eventData);
          break;

        case 'node:startup_timing':
        case 'relay:warm_timing':
        case 'relay:reservation_timing':
        case 'circuit_address:timing':
        case 'inbox:store_timing':
        case 'inbox:retrieve_timing':
        case 'media:stream_open_timing':
        case 'media:upload_complete':
        case 'media:download_complete':
        case 'media:download_failed':
        case 'profile:upload_progress':
        case 'message:direct_ack_timing':
        case 'timeout:fired':
          break;

        case 'group_message:received':
          _observeGroupInbound('message', eventData);
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
          _observeGroupInbound('reaction', eventData);
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

        // NET-REL-02 Option A: forward DCUtR hole-punch / relay->direct
        // telemetry to FLOW logs (HOLEPUNCH_ATTEMPT / HOLEPUNCH_SUCCESS /
        // HOLEPUNCH_FAILURE / TRANSPORT_UPGRADED / TRANSPORT_DOWNGRADED).
        case 'holepunch:attempt':
        case 'holepunch:success':
        case 'holepunch:failure':
        case 'transport:upgraded':
        case 'transport:downgraded':
          final safeEventData = sanitizeTransportDiagnosticEventData(
            eventName,
            eventData,
          );
          emitTransportDiagnosticEvent(eventName, safeEventData);
          emitFlowEvent(
            layer: 'GO',
            event: eventName.replaceAll(':', '_').toUpperCase(),
            details: safeEventData,
          );
          break;

        // SE-42 D27: default-network handoff progress. The typed
        // NetworkPathSource consumes the stream; the flow log keeps only the
        // allow-listed counters, stages, family and timings.
        case 'network:path_changing':
        case 'network:relay_ready':
        case 'network:relay_failed':
        // Emitted by the native previous-network watcher, not by Go.
        case 'network:previous_path_lost':
          final safeEventData = sanitizeNetworkPathEventData(
            eventName,
            eventData,
          )..remove('event');
          emitNetworkPathEvent(eventName, eventData);
          emitFlowEvent(
            layer: 'GO',
            event: eventName.replaceAll(':', '_').toUpperCase(),
            details: safeEventData,
          );
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

        // FDC-S5 (M1): the GO-layer flow event was already emitted by
        // _emitRawGoFlowEvent above (bridge:dispatch_timing is in the raw
        // passthrough set). It carries no push-side effect, so consume it here to
        // keep it out of the unknown-event counter.
        case 'bridge:dispatch_timing':
          break;

        case 'media:lan_received':
          // FDC-15: route the libp2p-LAN media receipt to the typed consumer.
          // It MUST NOT fall through to _recordUnknownPushEvent — that bumps
          // _unknownPushEventCount and can regress the 1:1 gate
          // (go_bridge_client_test.dart is in ONE_TO_ONE_TESTS).
          if (onLocalMediaReceived != null) {
            try {
              onLocalMediaReceived!(LocalMediaReady.fromJson(eventData));
            } catch (e) {
              debugPrint(
                '[GoBridgeClient] Error parsing media:lan_received: '
                '${sanitizeDiagnosticText(e)}',
              );
            }
          }
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

  void _observeGroupInbound(String kind, Object? eventData) {
    final observer = debugGroupInboundObserver;
    if (observer == null || eventData is! Map<String, dynamic>) return;
    try {
      observer(kind, eventData);
    } catch (_) {
      // A debug observer never affects inbound group delivery.
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
      try {
        AppDiagnostics.instance.record(
          feature: 'runtime',
          stage: 'bridge',
          outcome: 'failed',
          reason: 'bridge_rejected',
          values: {
            'operation': 'other',
            'durationMs': 0,
            'bridgeCommandFamily': _BridgeCommandFamily.unknown.wireValue,
            'bridgeRejectionKind': _BridgeRejectionKind.unknown.wireValue,
          },
        );
      } catch (_) {
        // Observation cannot replace the existing unknown-command response.
      }
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
    const diagnosticOperations = {
      'node:start': 'node_start',
      'node:stop': 'node_stop',
      'relay:reconnect': 'relay_reconnect',
      'relay:probe': 'relay_probe',
      'peer:dial': 'peer_dial',
      'peer:disconnect': 'peer_disconnect',
    };
    final diagnosticOperation = diagnosticOperations[cmd];
    final diagnosticTrace = diagnosticOperation == null
        ? null
        : AppDiagnostics.instance.startAttempt(feature: 'network');
    void reportDiagnostic(
      bool success,
      String reason, [
      _BridgeRejectionKind kind = _BridgeRejectionKind.unknown,
    ]) {
      // A broken diagnostic transport must not report itself recursively.
      if (cmd == 'app_diagnostics_v1' || cmd == 'call_diagnostics_v1') return;
      final values = <String, Object?>{
        'operation': diagnosticOperation ?? 'other',
        'durationMs': bridgeStopwatch.elapsedMilliseconds,
        if (!success) ...{
          'bridgeCommandFamily': spec.family.wireValue,
          'bridgeRejectionKind': kind.wireValue,
        },
      };
      if (diagnosticOperation != null) {
        AppDiagnostics.instance.finishAttempt(
          feature: 'network',
          traceId: diagnosticTrace,
          outcome: success ? 'success' : 'failed',
          reason: reason,
          values: values,
        );
      } else if (!success) {
        AppDiagnostics.instance.record(
          feature: 'runtime',
          stage: 'bridge',
          outcome: 'failed',
          reason: reason,
          values: values,
        );
      }
    }

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
        // Native bgEnd releases the task and intentionally returns void.
        if (cmd == 'bg:end') {
          reportDiagnostic(true, 'none');
          return jsonEncode({'ok': true});
        }
        reportDiagnostic(
          false,
          'malformed_response',
          _BridgeRejectionKind.malformedResponse,
        );
        return jsonEncode({
          'ok': false,
          'errorCode': 'NULL_RESPONSE',
          'errorMessage': 'Native bridge returned null',
        });
      }
      if (spec.allowRawStringResponse) {
        reportDiagnostic(true, 'none');
        return result;
      }
      final sanitized = _sanitizeBridgeResult(result);
      final decoded = jsonDecode(sanitized) as Map;
      // Observe coarse native boundaries within the existing command/attempt.
      // No address parsing, payload inspection or diagnostic result owns send.
      try {
        final diagnostics = AppDiagnostics.instance;
        if (diagnostics.enabled &&
            (cmd == 'peer:dial' ||
                cmd == 'message:send' ||
                cmd == 'inbox:store')) {
          final isMessage = cmd != 'peer:dial';
          final feature = isMessage ? 'message' : 'network';
          final trace = isMessage
              ? diagnostics.currentTraceForFeature('message')
              : diagnosticTrace;
          void record(Map<String, Object?> values) => diagnostics.record(
            feature: feature,
            stage: switch (values['connectionStage']) {
              'recipient_ack' => 'receipt',
              'inbox_acceptance' => 'store',
              'recovery' => 'recover',
              _ => 'bridge',
            },
            outcome: switch (values['connectionOutcome']) {
              'ok' => 'ok',
              'failed' => 'failed',
              _ => 'unknown',
            },
            traceId: trace,
            values: values,
          );
          observeConnectionDiagnostics(
            decoded['connectionDiagnostics'],
            record,
          );
          if (cmd == 'inbox:store') {
            final accepted =
                decoded['ok'] == true &&
                (decoded['storeStatus'] == 'stored' ||
                    decoded['storeStatus'] == 'duplicate');
            record({
              'connectionStage': 'inbox_acceptance',
              'connectionOutcome': accepted
                  ? 'ok'
                  : decoded['ok'] == false
                  ? 'failed'
                  : 'unknown',
            });
          }
        }
      } catch (_) {
        // Diagnostics never replace an ordinary bridge result.
      }
      final hasErrorCode = decoded.containsKey('errorCode');
      // Only this exact uncoded lifecycle reply establishes not-ready. Coded
      // rejections retain their code-derived kind, even with the same text.
      final nodeStopped =
          decoded['ok'] == false &&
          !hasErrorCode &&
          decoded['error'] == 'node stopped';
      // These two best-effort calls return ordinary negative results when a
      // peer/relay is unavailable. Preserve the result without a failure event.
      final expectedMiss =
          decoded['ok'] == false &&
          !hasErrorCode &&
          !nodeStopped &&
          (cmd == 'peer:ping' || cmd == 'relay:presence_set');
      if (!expectedMiss) {
        reportDiagnostic(
          decoded['ok'] == true,
          decoded['ok'] == true
              ? 'none'
              : switch ((cmd, decoded['errorCode'])) {
                  ('peer:dial', 'NOT_INITIALIZED') => 'bridge_unavailable',
                  ('peer:dial', 'INVALID_INPUT') => 'invalid_request',
                  // DIAL_ERROR includes several native causes; it does not
                  // establish that the peer is offline or the dial timed out.
                  ('peer:dial', 'DIAL_ERROR') => 'route_failed',
                  _ => 'bridge_rejected',
                },
          nodeStopped
              ? _BridgeRejectionKind.notReady
              : _bridgeRejectionKinds[decoded['errorCode']] ??
                    _BridgeRejectionKind.unknown,
        );
      }
      final deliveryObserver = debugGroupDeliveryObserver;
      if (deliveryObserver != null &&
          payload != null &&
          debugObservedGroupDeliveryCommands.contains(cmd)) {
        try {
          deliveryObserver(cmd, payload, decoded);
        } catch (_) {
          // A debug observer never replaces an ordinary bridge result.
        }
      }
      return sanitized;
    } on MissingPluginException catch (e) {
      bridgeStopwatch.stop();
      reportDiagnostic(false, 'bridge_handler_missing');
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
      reportDiagnostic(false, 'bridge_unavailable');
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
      reportDiagnostic(
        false,
        e is TimeoutException ? 'bridge_timeout' : 'bridge_unavailable',
        e is TimeoutException
            ? _BridgeRejectionKind.timeout
            : _BridgeRejectionKind.unknown,
      );
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

enum _BridgeCommandFamily {
  identity('identity'),
  crypto('crypto'),
  migration('migration'),
  network('network'),
  callControl('call_control'),
  messaging('messaging'),
  inbox('inbox'),
  media('media'),
  profile('profile'),
  group('group'),
  background('background'),
  diagnostics('diagnostics'),
  unknown('unknown');

  const _BridgeCommandFamily(this.wireValue);
  final String wireValue;
}

enum _BridgeRejectionKind {
  timeout('timeout'),
  notReady('not_ready'),
  invalidArgument('invalid_argument'),
  notFound('not_found'),
  permission('permission'),
  internal('internal'),
  malformedResponse('malformed_response'),
  unsupported('unsupported'),
  capacity('capacity'),
  unknown('unknown');

  const _BridgeRejectionKind(this.wireValue);
  final String wireValue;
}

// This table uses explicit codes; broad unclassified failures stay unknown.
// Dispatch separately recognizes the exact uncoded lifecycle reply above.
// Raw commands, payloads, peer identifiers and error text are never recorded.
const _bridgeRejectionKinds = <String, _BridgeRejectionKind>{
  'BRIDGE_TIMEOUT': _BridgeRejectionKind.timeout,
  'NOT_INITIALIZED': _BridgeRejectionKind.notReady,
  'NO_RESERVATION': _BridgeRejectionKind.notReady,
  'CUSTODY_ADMISSION_DISABLED': _BridgeRejectionKind.notReady,
  'MEDIA_CUSTODY_ADMISSION_DISABLED': _BridgeRejectionKind.notReady,
  'MEDIA_CUSTODY_CLEANUP_PENDING': _BridgeRejectionKind.notReady,
  'INVALID_INPUT': _BridgeRejectionKind.invalidArgument,
  'INVALID_MNEMONIC': _BridgeRejectionKind.invalidArgument,
  'INVALID_GROUP_KEY': _BridgeRejectionKind.invalidArgument,
  'INVALID_JOIN_MATERIAL': _BridgeRejectionKind.invalidArgument,
  'INVALID_KEY_EPOCH': _BridgeRejectionKind.invalidArgument,
  'CALL_INVALID_REQUEST': _BridgeRejectionKind.invalidArgument,
  'CALL_EXPIRY_INVALID': _BridgeRejectionKind.invalidArgument,
  'CALL_ENVELOPE_TOO_LARGE': _BridgeRejectionKind.invalidArgument,
  'GROUP_KEY_NOT_FOUND': _BridgeRejectionKind.notFound,
  'MEDIA_CUSTODY_NOT_FOUND': _BridgeRejectionKind.notFound,
  'CALL_UNAUTHORIZED': _BridgeRejectionKind.permission,
  'MEDIA_CUSTODY_NOT_AUTHORIZED': _BridgeRejectionKind.permission,
  'INTERNAL_ERROR': _BridgeRejectionKind.internal,
  'PROFILE_ERROR': _BridgeRejectionKind.internal,
  'NULL_RESPONSE': _BridgeRejectionKind.malformedResponse,
  'MALFORMED_RESPONSE': _BridgeRejectionKind.malformedResponse,
  'CALL_CONTROL_INVALID_RESPONSE': _BridgeRejectionKind.malformedResponse,
  'TURN_CREDENTIALS_INVALID_RESPONSE': _BridgeRejectionKind.malformedResponse,
  'TURN_CREDENTIALS_UNSUPPORTED': _BridgeRejectionKind.unsupported,
  'CALL_CONTROL_UNSUPPORTED': _BridgeRejectionKind.unsupported,
  'LEGACY_ROTATE_KEY_UNSUPPORTED': _BridgeRejectionKind.unsupported,
  'MEDIA_CUSTODY_UNSUPPORTED': _BridgeRejectionKind.unsupported,
  'INBOX_FULL': _BridgeRejectionKind.capacity,
  'MEDIA_CUSTODY_FULL': _BridgeRejectionKind.capacity,
  'CALL_RECIPIENT_CAPACITY': _BridgeRejectionKind.capacity,
  'CALL_EVENT_CAPACITY': _BridgeRejectionKind.capacity,
  'CALL_BYTE_CAPACITY': _BridgeRejectionKind.capacity,
  'CALL_RATE_LIMITED': _BridgeRejectionKind.capacity,
};

class _CmdSpec {
  final _BridgeCommandFamily family;
  final String methodName;
  final bool hasPayload;
  final bool allowRawStringResponse;

  const _CmdSpec(
    this.family,
    this.methodName,
    this.hasPayload, {
    this.allowRawStringResponse = false,
  });
}
