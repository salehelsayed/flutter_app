import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

const String callStoreV1BridgeCommand = 'call_store_v1';
const String callRetrieveV1BridgeCommand = 'call_retrieve_v1';
const String callAckV1BridgeCommand = 'call_ack_v1';
const String callCancelV1BridgeCommand = 'call_cancel_v1';

enum CallMailboxErrorCode {
  invalidRequest,
  oversized,
  bridgeFailure,
  malformedResponse,
}

final class CallMailboxException implements Exception {
  const CallMailboxException(this.code);

  final CallMailboxErrorCode code;

  @override
  String toString() => 'Call mailbox request failed: ${code.name}';
}

enum CallMailboxStoreStatus { stored, duplicate }

/// What became of the relay's wake for a stored event. `dispatched` means the
/// callee's device was alerted (a headless callee rings without signalling
/// anything until it is answered); `none` covers no route and a callee already
/// on the call; `failed` means the push provider refused.
enum CallMailboxWakeStatus { none, dispatched, failed }

final class CallMailboxStoreRequest {
  const CallMailboxStoreRequest({
    required this.recipientDevicePeerId,
    required this.callHandle,
    required this.messageId,
    required this.envelopeJson,
    required this.expiresAtMs,
    required this.wakeHandle,
  });

  final String recipientDevicePeerId;
  final String callHandle;
  final String messageId;
  final String envelopeJson;
  final int expiresAtMs;
  final String wakeHandle;
}

final class CallMailboxStoreResult {
  const CallMailboxStoreResult({
    required this.status,
    required this.receiptAtMs,
    required this.expiresAtMs,
    required this.eventCount,
    required this.totalBytes,
    required this.pendingHandles,
    this.wake = CallMailboxWakeStatus.none,
  });

  final CallMailboxStoreStatus status;
  final int receiptAtMs;
  final int expiresAtMs;
  final int eventCount;
  final int totalBytes;
  final int pendingHandles;
  final CallMailboxWakeStatus wake;
}

final class CallMailboxEvent {
  const CallMailboxEvent({
    required this.callHandle,
    required this.messageId,
    required this.authenticatedSenderDevicePeerId,
    required this.recipientDevicePeerId,
    required this.envelopeJson,
    required this.receiptAtMs,
    required this.expiresAtMs,
  });

  final String callHandle;
  final String messageId;
  final String authenticatedSenderDevicePeerId;
  final String recipientDevicePeerId;
  final String envelopeJson;
  final int receiptAtMs;
  final int expiresAtMs;
}

final class CallMailboxRetrieveResult {
  CallMailboxRetrieveResult({
    required List<CallMailboxEvent> events,
    required this.receiptAtMs,
    required this.expiresAtMs,
    required this.hasMore,
  }) : events = List<CallMailboxEvent>.unmodifiable(events);

  final List<CallMailboxEvent> events;
  final int receiptAtMs;
  final int expiresAtMs;
  final bool hasMore;
}

abstract interface class CallMailboxClient {
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request);

  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  });

  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  });

  /// Resolves true once the relay holds no cancellable invite of ours for
  /// this handle: cancelled now, or absent (never stored, already terminal,
  /// or expired). Every other refusal throws so terminal cleanup retries it.
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  });
}

/// Production adapter for the call-only Go bridge actions. It never invokes
/// `inbox:*`, the chat outbox, or the generic pending-message retrier.
final class BridgeCallMailboxClient implements CallMailboxClient {
  const BridgeCallMailboxClient({
    required Bridge bridge,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _bridge = bridge;

  static const int maxSignalBytes = 96 * 1024;
  static const int maxRetrieveEvents = 64;

  final Bridge _bridge;
  final Duration requestTimeout;

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    if (request.recipientDevicePeerId.trim().isEmpty ||
        request.callHandle.trim().isEmpty ||
        request.messageId.trim().isEmpty ||
        request.wakeHandle.trim().isEmpty ||
        request.expiresAtMs <= 0) {
      throw const CallMailboxException(CallMailboxErrorCode.invalidRequest);
    }
    if (utf8.encode(request.envelopeJson).length > maxSignalBytes) {
      throw const CallMailboxException(CallMailboxErrorCode.oversized);
    }
    final response = await _invoke(callStoreV1BridgeCommand, <String, Object?>{
      'toPeerId': request.recipientDevicePeerId,
      'callHandle': request.callHandle,
      'messageId': request.messageId,
      'envelope': request.envelopeJson,
      'expiresAtMs': request.expiresAtMs,
      'wakeHandle': request.wakeHandle,
    });
    final status = switch (response['storeStatus']) {
      'stored' => CallMailboxStoreStatus.stored,
      'duplicate' => CallMailboxStoreStatus.duplicate,
      _ => throw const CallMailboxException(
        CallMailboxErrorCode.malformedResponse,
      ),
    };
    return CallMailboxStoreResult(
      status: status,
      receiptAtMs: _responseInt(response, 'receiptAtMs'),
      expiresAtMs: _responseInt(response, 'expiresAtMs'),
      eventCount: _responseInt(response, 'eventCount'),
      totalBytes: _responseInt(response, 'totalBytes'),
      pendingHandles: _responseInt(response, 'pendingHandles'),
      wake: switch (response['wake']) {
        'dispatched' => CallMailboxWakeStatus.dispatched,
        'failed' => CallMailboxWakeStatus.failed,
        _ => CallMailboxWakeStatus.none,
      },
    );
  }

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = maxRetrieveEvents,
  }) async {
    if (limit < 1 || limit > maxRetrieveEvents) {
      throw const CallMailboxException(CallMailboxErrorCode.invalidRequest);
    }
    if (callHandle != null && callHandle.trim().isEmpty) {
      throw const CallMailboxException(CallMailboxErrorCode.invalidRequest);
    }
    final response = await _invoke(
      callRetrieveV1BridgeCommand,
      <String, Object?>{'callHandle': ?callHandle, 'limit': limit},
    );
    final rawEvents = response['events'];
    if (rawEvents is! List || rawEvents.length > limit) {
      throw const CallMailboxException(CallMailboxErrorCode.malformedResponse);
    }
    final events = <CallMailboxEvent>[];
    for (final raw in rawEvents) {
      if (raw is! Map) {
        throw const CallMailboxException(
          CallMailboxErrorCode.malformedResponse,
        );
      }
      final event = Map<String, dynamic>.from(raw);
      final envelope = _responseString(event, 'envelope');
      if (utf8.encode(envelope).length > maxSignalBytes) {
        throw const CallMailboxException(CallMailboxErrorCode.oversized);
      }
      events.add(
        CallMailboxEvent(
          callHandle: _responseString(event, 'callHandle'),
          messageId: _responseString(event, 'messageId'),
          authenticatedSenderDevicePeerId: _responseString(
            event,
            'senderPeerId',
          ),
          recipientDevicePeerId: _responseString(
            event,
            'recipientDevicePeerId',
          ),
          envelopeJson: envelope,
          receiptAtMs: _responseInt(event, 'receiptAtMs'),
          expiresAtMs: _responseInt(event, 'expiresAtMs'),
        ),
      );
    }
    final hasMore = response['hasMore'];
    if (hasMore is! bool) {
      throw const CallMailboxException(CallMailboxErrorCode.malformedResponse);
    }
    return CallMailboxRetrieveResult(
      events: events,
      receiptAtMs: _responseInt(response, 'receiptAtMs'),
      expiresAtMs: _responseInt(response, 'expiresAtMs'),
      hasMore: hasMore,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) async {
    if (callHandle.trim().isEmpty ||
        messageIds.isEmpty ||
        messageIds.length > maxRetrieveEvents ||
        messageIds.any((messageId) => messageId.trim().isEmpty)) {
      throw const CallMailboxException(CallMailboxErrorCode.invalidRequest);
    }
    final response = await _invoke(callAckV1BridgeCommand, <String, Object?>{
      'callHandle': callHandle,
      'messageIds': List<String>.unmodifiable(messageIds),
    });
    return _responseInt(response, 'acked');
  }

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) async {
    if (recipientDevicePeerId.trim().isEmpty || callHandle.trim().isEmpty) {
      throw const CallMailboxException(CallMailboxErrorCode.invalidRequest);
    }
    // The relay answers CALL_UNAUTHORIZED when it holds nothing of ours for
    // the handle (never stored, tombstone expired, or not our call). Nothing
    // is left to cancel, so cleanup must not retry it forever (device
    // 2026-09-05 17:15Z: an invite refused with CALL_RECIPIENT_CAPACITY kept
    // terminal cleanup blocked and every native terminal replay rejected).
    final response = await _invoke(callCancelV1BridgeCommand, <String, Object?>{
      'toPeerId': recipientDevicePeerId,
      'callHandle': callHandle,
    }, tolerated: _absentInviteCodes);
    return response['canceled'] == true ||
        _absentInviteCodes.contains(response['errorCode']);
  }

  static const Set<String> _absentInviteCodes = <String>{'CALL_UNAUTHORIZED'};

  Future<Map<String, dynamic>> _invoke(
    String command,
    Map<String, Object?> payload, {
    Set<String> tolerated = const <String>{},
  }) async {
    try {
      final raw = await _bridge
          .send(
            jsonEncode(<String, Object?>{'cmd': command, 'payload': payload}),
          )
          .timeout(requestTimeout);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        final code = decoded is Map<String, dynamic>
            ? _safeBridgeErrorCode(decoded['errorCode'])
            : 'MALFORMED_RESPONSE';
        _emitBridgeFailure(
          operation: _safeBridgeOperation(command),
          code: code,
        );
        if (decoded is Map<String, dynamic> && tolerated.contains(code)) {
          return <String, dynamic>{'ok': false, 'errorCode': code};
        }
        throw const CallMailboxException(CallMailboxErrorCode.bridgeFailure);
      }
      return decoded;
    } on CallMailboxException {
      rethrow;
    } catch (_) {
      throw const CallMailboxException(CallMailboxErrorCode.bridgeFailure);
    }
  }

  static String _safeBridgeOperation(String operation) => switch (operation) {
    callStoreV1BridgeCommand ||
    callRetrieveV1BridgeCommand ||
    callAckV1BridgeCommand ||
    callCancelV1BridgeCommand => operation,
    _ => 'unknown',
  };

  static const Set<String> _safeBridgeErrorCodes = <String>{
    'NOT_INITIALIZED',
    'INVALID_INPUT',
    'INTERNAL_ERROR',
    'CALL_CONTROL_UNAVAILABLE',
    'CALL_CONTROL_UNSUPPORTED',
    'CALL_CONTROL_INVALID_RESPONSE',
    'CALL_BACKEND_UNAVAILABLE',
    'CALL_INVALID_REQUEST',
    'CALL_UNAUTHORIZED',
    'CALL_IDENTITY_CONFLICT',
    'CALL_REPLAY',
    'CALL_EXPIRY_INVALID',
    'CALL_ENVELOPE_TOO_LARGE',
    'CALL_RECIPIENT_CAPACITY',
    'CALL_EVENT_CAPACITY',
    'CALL_BYTE_CAPACITY',
    'CALL_RATE_LIMITED',
    'CALL_STALE_EPOCH',
  };

  static String _safeBridgeErrorCode(Object? value) {
    if (value is String && _safeBridgeErrorCodes.contains(value)) {
      return value;
    }
    return 'UNKNOWN';
  }

  static void _emitBridgeFailure({
    required String operation,
    required String code,
  }) {
    try {
      emitFlowEvent(
        layer: 'FL',
        event: 'CALL_MAILBOX_BRIDGE_FAILURE',
        details: <String, Object?>{'operation': operation, 'code': code},
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change mailbox behavior.
    }
  }

  static String _responseString(Map<String, dynamic> response, String key) {
    final value = response[key];
    if (value is! String || value.isEmpty) {
      throw const CallMailboxException(CallMailboxErrorCode.malformedResponse);
    }
    return value;
  }

  static int _responseInt(Map<String, dynamic> response, String key) {
    final value = response[key];
    if (value is! int || value < 0) {
      throw const CallMailboxException(CallMailboxErrorCode.malformedResponse);
    }
    return value;
  }
}
