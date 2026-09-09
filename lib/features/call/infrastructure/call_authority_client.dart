import 'dart:convert';

import '../diagnostics/call_diagnostics.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

enum CallEndpointPlatform {
  android('android'),
  ios('ios');

  const CallEndpointPlatform(this.wireName);

  final String wireName;

  static CallEndpointPlatform parse(String value) => switch (value) {
    'android' => CallEndpointPlatform.android,
    'ios' => CallEndpointPlatform.ios,
    _ => throw const CallAuthorityException(
      CallAuthorityErrorCode.malformedResponse,
    ),
  };
}

enum CallTokenKind {
  standardCall('standard_call'),
  iosVoip('ios_voip');

  const CallTokenKind(this.wireName);

  final String wireName;
}

enum CallAuthorityErrorCode {
  invalidRequest,
  bridgeFailure,
  malformedResponse,
  canonicalRecordMismatch,
}

final class CallAuthorityException implements Exception {
  const CallAuthorityException(this.code, {this.relayErrorCode});

  /// Relay error code the relay refused the request with (`CALL_STALE_EPOCH`
  /// etc.). Present only for a bridge failure that carried a safe,
  /// fixed-vocabulary code; never free text.
  static const String staleEpochRelayCode = 'CALL_STALE_EPOCH';

  final CallAuthorityErrorCode code;
  final String? relayErrorCode;

  /// The relay's refresh-epoch high-water rejected this registration epoch.
  bool get isStaleEpoch => relayErrorCode == staleEpochRelayCode;

  @override
  String toString() => 'Call authority request failed: ${code.name}';
}

final class CallEndpointRecord {
  const CallEndpointRecord({
    required this.accountPeerId,
    required this.devicePeerId,
    required this.capabilities,
    required this.platform,
    required this.expiresAtMs,
    required this.preferenceEpoch,
    required this.deviceKeyEpoch,
    required this.routingHandle,
  });

  static const String schema = 'mknoon.call_endpoint_set.v1';
  static const int version = 1;
  static const Set<String> _canonicalKeys = <String>{
    'schema',
    'version',
    'accountPeerId',
    'devicePeerId',
    'capabilities',
    'platform',
    'expiresAtMs',
    'preferenceEpoch',
    'deviceKeyEpoch',
    'routingHandle',
  };

  final String accountPeerId;
  final String devicePeerId;
  final Set<String> capabilities;
  final CallEndpointPlatform platform;
  final int expiresAtMs;
  final int preferenceEpoch;
  final int deviceKeyEpoch;
  final String routingHandle;

  Map<String, Object?> toCanonicalMap() => <String, Object?>{
    'schema': schema,
    'version': version,
    'accountPeerId': accountPeerId,
    'devicePeerId': devicePeerId,
    'capabilities': capabilities.toList(growable: false)..sort(),
    'platform': platform.wireName,
    'expiresAtMs': expiresAtMs,
    'preferenceEpoch': preferenceEpoch,
    'deviceKeyEpoch': deviceKeyEpoch,
    'routingHandle': routingHandle,
  };

  String get canonicalRecordJson => jsonEncode(toCanonicalMap());

  factory CallEndpointRecord.fromMap(Map<String, dynamic> map) {
    if (map.keys.toSet().difference(_canonicalKeys).isNotEmpty ||
        _canonicalKeys.difference(map.keys.toSet()).isNotEmpty ||
        map['schema'] != schema ||
        map['version'] != version ||
        map['accountPeerId'] is! String ||
        map['devicePeerId'] is! String ||
        map['capabilities'] is! List ||
        map['platform'] is! String ||
        map['expiresAtMs'] is! int ||
        map['preferenceEpoch'] is! int ||
        map['deviceKeyEpoch'] is! int ||
        map['routingHandle'] is! String) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    final rawCapabilities = map['capabilities'] as List;
    if (rawCapabilities.any((value) => value is! String)) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    return CallEndpointRecord(
      accountPeerId: map['accountPeerId'] as String,
      devicePeerId: map['devicePeerId'] as String,
      capabilities: Set<String>.unmodifiable(rawCapabilities.cast<String>()),
      platform: CallEndpointPlatform.parse(map['platform'] as String),
      expiresAtMs: map['expiresAtMs'] as int,
      preferenceEpoch: map['preferenceEpoch'] as int,
      deviceKeyEpoch: map['deviceKeyEpoch'] as int,
      routingHandle: map['routingHandle'] as String,
    );
  }
}

final class SignedCallEndpointRecord {
  const SignedCallEndpointRecord({
    required this.record,
    required this.signature,
    required this.canonicalRecordBase64,
  });

  final CallEndpointRecord record;
  final String signature;
  final String canonicalRecordBase64;

  String get canonicalRecordJson {
    try {
      return utf8.decode(base64Decode(canonicalRecordBase64));
    } catch (_) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
  }
}

final class CallWakeHandleRecord {
  const CallWakeHandleRecord({
    required this.authorizedSenderPeerId,
    required this.wakeHandle,
    required this.expiresAtMs,
  });

  final String authorizedSenderPeerId;
  final String wakeHandle;
  final int expiresAtMs;
}

final class CallTokenRecord {
  CallTokenRecord({
    required this.kind,
    required this.platform,
    required this.token,
    required this.expiresAtMs,
    this.environment,
    this.topic,
    this.capabilityVersion,
    this.refreshEpoch,
  }) {
    final validStandard =
        kind == CallTokenKind.standardCall &&
        platform == CallEndpointPlatform.android &&
        environment == null &&
        topic == null &&
        capabilityVersion == null &&
        refreshEpoch == null;
    final validIosVoip =
        kind == CallTokenKind.iosVoip &&
        platform == CallEndpointPlatform.ios &&
        (environment == 'sandbox' || environment == 'production') &&
        topic != null &&
        topic!.trim() == topic &&
        topic!.endsWith('.voip') &&
        capabilityVersion == 1 &&
        refreshEpoch != null &&
        refreshEpoch! > 0;
    if ((!validStandard && !validIosVoip) ||
        token.trim().isEmpty ||
        expiresAtMs <= 0) {
      throw ArgumentError('invalid call token record');
    }
  }

  final CallTokenKind kind;
  final CallEndpointPlatform platform;
  final String token;
  final int expiresAtMs;
  final String? environment;
  final String? topic;
  final int? capabilityVersion;
  final int? refreshEpoch;
}

/// Strict result for typed token publication. Standard Android registrations
/// remain boolean-compatible; iOS VoIP additionally receives relay-owned
/// generation and echoed refresh-epoch authority.
final class CallTokenPublication {
  const CallTokenPublication({
    required this.accepted,
    this.serverGeneration,
    this.refreshEpoch,
  });

  final bool accepted;
  final int? serverGeneration;
  final int? refreshEpoch;
}

abstract interface class CallAuthorityClient {
  Future<SignedCallEndpointRecord> signEndpoint({
    required CallEndpointRecord record,
    required String senderSigningPrivateKey,
  });

  Future<bool> setEndpoint(SignedCallEndpointRecord endpoint);

  Future<SignedCallEndpointRecord?> getEndpoint(String accountPeerId);

  Future<bool> verifyEndpoint(
    SignedCallEndpointRecord endpoint, {
    required String trustedDeviceSigningPublicKey,
  });

  Future<bool> revokeEndpoint({
    required String accountPeerId,
    required int preferenceEpoch,
  });

  Future<bool> setWakeHandle(CallWakeHandleRecord record);

  Future<bool> revokeWakeHandle({required String authorizedSenderPeerId});

  Future<bool> setToken(CallTokenRecord record);

  Future<CallTokenPublication> publishToken(CallTokenRecord record);

  Future<bool> revokeToken(CallTokenKind kind, {int? refreshEpoch});
}

final class BridgeCallAuthorityClient implements CallAuthorityClient {
  const BridgeCallAuthorityClient({
    required Bridge bridge,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _bridge = bridge;

  final Bridge _bridge;
  final Duration requestTimeout;

  @override
  Future<SignedCallEndpointRecord> signEndpoint({
    required CallEndpointRecord record,
    required String senderSigningPrivateKey,
  }) async {
    _validateEndpointRecord(record);
    late final Map<String, dynamic> signatureResult;
    try {
      signatureResult = await callSignPayload(
        bridge: _bridge,
        dataToSign: record.canonicalRecordJson,
        privateKey: senderSigningPrivateKey,
      ).timeout(requestTimeout);
    } catch (_) {
      throw const CallAuthorityException(CallAuthorityErrorCode.bridgeFailure);
    }
    final signature = signatureResult['signature'];
    if (signatureResult['ok'] != true || signature is! String) {
      throw const CallAuthorityException(CallAuthorityErrorCode.bridgeFailure);
    }
    return SignedCallEndpointRecord(
      record: record,
      signature: signature,
      canonicalRecordBase64: base64Encode(
        utf8.encode(record.canonicalRecordJson),
      ),
    );
  }

  @override
  Future<bool> setEndpoint(SignedCallEndpointRecord endpoint) async {
    _validateEndpointRecord(endpoint.record);
    if (endpoint.signature.trim().isEmpty) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final record = endpoint.record;
    final response = await _invoke('call_endpoint_set_v1', <String, Object?>{
      'accountPeerId': record.accountPeerId,
      'devicePeerId': record.devicePeerId,
      'capabilities': record.capabilities.toList(growable: false)..sort(),
      'platform': record.platform.wireName,
      'expiresAtMs': record.expiresAtMs,
      'preferenceEpoch': record.preferenceEpoch,
      'deviceKeyEpoch': record.deviceKeyEpoch,
      'routingHandle': record.routingHandle,
      'signature': endpoint.signature,
    });
    return response['ok'] == true;
  }

  @override
  Future<SignedCallEndpointRecord?> getEndpoint(String accountPeerId) async {
    if (accountPeerId.trim().isEmpty) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final response = await _invoke('call_endpoint_get_v1', <String, Object?>{
      'accountPeerId': accountPeerId,
    });
    if (response['found'] == false) return null;
    final rawEndpoint = response['endpoint'];
    final rawCanonical = response['canonicalRecord'];
    if (response['found'] != true ||
        rawEndpoint is! Map ||
        rawCanonical is! String) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    final endpoint = Map<String, dynamic>.from(rawEndpoint);
    final signature = endpoint.remove('signature');
    if (signature is! String) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    return SignedCallEndpointRecord(
      record: CallEndpointRecord.fromMap(endpoint),
      signature: signature,
      canonicalRecordBase64: rawCanonical,
    );
  }

  @override
  Future<bool> verifyEndpoint(
    SignedCallEndpointRecord endpoint, {
    required String trustedDeviceSigningPublicKey,
  }) async {
    if (trustedDeviceSigningPublicKey.trim().isEmpty ||
        endpoint.signature.trim().isEmpty) {
      return false;
    }
    late final String relayCanonical;
    try {
      relayCanonical = endpoint.canonicalRecordJson;
    } catch (_) {
      return false;
    }
    if (relayCanonical != endpoint.record.canonicalRecordJson) return false;
    try {
      return await callVerifyPayload(
        bridge: _bridge,
        publicKey: trustedDeviceSigningPublicKey,
        data: relayCanonical,
        signature: endpoint.signature,
      ).timeout(requestTimeout);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> revokeEndpoint({
    required String accountPeerId,
    required int preferenceEpoch,
  }) async {
    if (accountPeerId.trim().isEmpty || preferenceEpoch < 0) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final response = await _invoke('call_endpoint_revoke_v1', <String, Object?>{
      'accountPeerId': accountPeerId,
      'preferenceEpoch': preferenceEpoch,
    });
    return response['revoked'] == true;
  }

  @override
  Future<bool> setWakeHandle(CallWakeHandleRecord record) async {
    if (record.authorizedSenderPeerId.trim().isEmpty ||
        record.wakeHandle.trim().isEmpty ||
        record.expiresAtMs <= 0) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final response = await _invoke('call_wake_handle_set_v1', <String, Object?>{
      'authorizedSenderPeerId': record.authorizedSenderPeerId,
      'wakeHandle': record.wakeHandle,
      'expiresAtMs': record.expiresAtMs,
    });
    return response['ok'] == true;
  }

  @override
  Future<bool> revokeWakeHandle({
    required String authorizedSenderPeerId,
  }) async {
    if (authorizedSenderPeerId.trim().isEmpty) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final response = await _invoke(
      'call_wake_handle_revoke_v1',
      <String, Object?>{'authorizedSenderPeerId': authorizedSenderPeerId},
    );
    return response['revoked'] == true;
  }

  @override
  Future<bool> setToken(CallTokenRecord record) async =>
      (await publishToken(record)).accepted;

  @override
  Future<CallTokenPublication> publishToken(CallTokenRecord record) async {
    final payload = <String, Object?>{
      'tokenKind': record.kind.wireName,
      'platform': record.platform.wireName,
      'token': record.token,
      'expiresAtMs': record.expiresAtMs,
      if (record.environment != null) 'environment': record.environment,
      if (record.topic != null) 'topic': record.topic,
      if (record.capabilityVersion != null)
        'capabilityVersion': record.capabilityVersion,
      if (record.refreshEpoch != null) 'refreshEpoch': record.refreshEpoch,
    };
    final response = await _invoke('call_token_set_v1', payload);
    if (record.kind == CallTokenKind.standardCall) {
      return const CallTokenPublication(accepted: true);
    }
    final generation = response['generation'];
    final refreshEpoch = response['refreshEpoch'];
    if (generation is! int ||
        generation <= 0 ||
        refreshEpoch is! int ||
        refreshEpoch != record.refreshEpoch) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    return CallTokenPublication(
      accepted: true,
      serverGeneration: generation,
      refreshEpoch: refreshEpoch,
    );
  }

  @override
  Future<bool> revokeToken(CallTokenKind kind, {int? refreshEpoch}) async {
    final validStandard =
        kind == CallTokenKind.standardCall && refreshEpoch == null;
    final validIosVoip =
        kind == CallTokenKind.iosVoip &&
        refreshEpoch != null &&
        refreshEpoch > 0;
    if (!validStandard && !validIosVoip) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
    final response = await _invoke('call_token_revoke_v1', <String, Object?>{
      'tokenKind': kind.wireName,
      'expectedRefreshEpoch': ?refreshEpoch,
    });
    final revoked = response['revoked'];
    if (revoked is! bool) {
      throw const CallAuthorityException(
        CallAuthorityErrorCode.malformedResponse,
      );
    }
    return revoked;
  }

  Future<Map<String, dynamic>> _invoke(
    String command,
    Map<String, Object?> payload,
  ) async {
    final diagnostics = CallDiagnostics.instance;
    final context = diagnostics.contextForWire(
      callHandle: payload['callHandle'] as String?,
    );
    final wirePayload = <String, Object?>{...payload, 'diagnostics': ?context};
    final action = command.contains('_revoke_')
        ? 'revoke'
        : command.contains('_set_')
        ? 'publish'
        : command.contains('_get_')
        ? 'lookup'
        : command.contains('_store_')
        ? 'store'
        : command.contains('_retrieve_')
        ? 'retrieve'
        : command.contains('_ack_')
        ? 'ack'
        : command.contains('_cancel_')
        ? 'cancel'
        : 'check';
    void record(String outcome, [String reason = 'none']) => diagnostics.record(
      stage: 'authority',
      action: action,
      outcome: outcome,
      reason: reason,
      traceId: context?['traceId'] as String?,
      requestId: context?['requestId'] as String?,
      operationId: context?['operationId'] as String?,
      parentOperationId: context?['parentOperationId'] as String?,
    );
    record('started');
    try {
      final raw = await _bridge
          .send(
            jsonEncode(<String, Object?>{
              'cmd': command,
              'payload': wirePayload,
            }),
          )
          .timeout(requestTimeout);
      final response = jsonDecode(raw);
      if (response is! Map<String, dynamic> || response['ok'] != true) {
        final code = response is Map<String, dynamic>
            ? _safeBridgeErrorCode(response['errorCode'])
            : 'MALFORMED_RESPONSE';
        record('rejected', _diagnosticRelayReason(code));
        _emitBridgeFailure(operation: command, code: code);
        throw CallAuthorityException(
          CallAuthorityErrorCode.bridgeFailure,
          relayErrorCode: code == 'UNKNOWN' || code == 'MALFORMED_RESPONSE'
              ? null
              : code,
        );
      }
      record('ok');
      return response;
    } on CallAuthorityException {
      rethrow;
    } catch (_) {
      record('failed', 'bridge_unavailable');
      throw const CallAuthorityException(CallAuthorityErrorCode.bridgeFailure);
    }
  }

  static String _diagnosticRelayReason(String code) => switch (code) {
    'CALL_STALE_EPOCH' => 'stale_epoch',
    'CALL_UNAUTHORIZED' => 'authority_rejected',
    'CALL_RATE_LIMITED' => 'rate_limited',
    'CALL_BACKEND_UNAVAILABLE' => 'backend_unavailable',
    'CALL_CONTROL_UNSUPPORTED' => 'legacy_peer',
    'CALL_INVALID_REQUEST' || 'INVALID_INPUT' => 'invalid_request',
    'CALL_CONTROL_INVALID_RESPONSE' ||
    'MALFORMED_RESPONSE' => 'malformed_response',
    'CALL_EXPIRED' => 'expired',
    _ => 'unknown',
  };

  static String _safeBridgeErrorCode(Object? value) {
    if (value is String &&
        value.length <= 64 &&
        RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(value)) {
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
        event: 'CALL_AUTHORITY_BRIDGE_FAILURE',
        details: <String, Object?>{'operation': operation, 'code': code},
      );
    } catch (_) {
      // Identifier-free diagnostics cannot change authority behavior.
    }
  }

  static void _validateEndpointRecord(CallEndpointRecord record) {
    if (record.accountPeerId.trim().isEmpty ||
        record.devicePeerId.trim().isEmpty ||
        !record.capabilities.contains('voice_call_v1') ||
        record.expiresAtMs <= 0 ||
        record.preferenceEpoch < 0 ||
        record.deviceKeyEpoch < 0 ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(record.routingHandle)) {
      throw const CallAuthorityException(CallAuthorityErrorCode.invalidRequest);
    }
  }
}
