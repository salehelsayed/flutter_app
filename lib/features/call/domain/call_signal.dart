import 'dart:convert';

import 'call_end_reason.dart';
import 'call_id.dart';

enum CallSignalType {
  invite('invite'),
  ringing('ringing'),
  accept('accept'),
  reject('reject'),
  offer('offer'),
  answer('answer'),
  ice('ice'),
  iceRestart('ice_restart'),
  terminate('terminate');

  const CallSignalType(this.wireName);

  final String wireName;

  static CallSignalType parse(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw const FormatException('unsupported call signal event');
  }
}

/// The one canonical decrypted `mknoon.call_signal.v1` inner event. The secure
/// outer wrapper may add only its random call handle and cryptographic fields.
final class CallSignal {
  CallSignal._({
    required this.callId,
    required this.messageId,
    required this.event,
    required this.senderAccountPeerId,
    required this.senderDevicePeerId,
    required this.recipientAccountPeerId,
    required this.recipientDevicePeerId,
    required this.senderSequence,
    required this.iceGeneration,
    required this.createdAtMs,
    required this.expiresAtMs,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  static const String schema = 'mknoon.call_signal.v1';
  static const int maximumEncodedBytes = 96 * 1024;
  static const int maximumInvitePayloadBytes = 4096;
  static const int maximumPreconnectLifetimeMs = 45000;
  static const int maximumNegotiationReorderingDistance = 64;

  static const Set<String> _keys = <String>{
    'schema',
    'call_id',
    'message_id',
    'event',
    'sender_account_peer_id',
    'sender_device_peer_id',
    'recipient_account_peer_id',
    'recipient_device_peer_id',
    'sender_sequence',
    'ice_generation',
    'created_at_ms',
    'expires_at_ms',
    'payload',
  };

  final CallId callId;
  final String messageId;
  final CallSignalType event;
  final String senderAccountPeerId;
  final String senderDevicePeerId;
  final String recipientAccountPeerId;
  final String recipientDevicePeerId;
  final int senderSequence;
  final int iceGeneration;
  final int createdAtMs;
  final int expiresAtMs;
  final Map<String, Object?> payload;

  factory CallSignal.create({
    required CallId callId,
    required String messageId,
    required CallSignalType event,
    required String senderAccountPeerId,
    required String senderDevicePeerId,
    required String recipientAccountPeerId,
    required String recipientDevicePeerId,
    required int senderSequence,
    required int iceGeneration,
    required int createdAtMs,
    required int expiresAtMs,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => CallSignal.fromMap(<String, Object?>{
    'schema': schema,
    'call_id': callId.value,
    'message_id': messageId,
    'event': event.wireName,
    'sender_account_peer_id': senderAccountPeerId,
    'sender_device_peer_id': senderDevicePeerId,
    'recipient_account_peer_id': recipientAccountPeerId,
    'recipient_device_peer_id': recipientDevicePeerId,
    'sender_sequence': senderSequence,
    'ice_generation': iceGeneration,
    'created_at_ms': createdAtMs,
    'expires_at_ms': expiresAtMs,
    'payload': payload,
  });

  factory CallSignal.fromMap(Map<String, Object?> map) {
    final actualKeys = map.keys.toSet();
    if (actualKeys.difference(_keys).isNotEmpty ||
        _keys.difference(actualKeys).isNotEmpty ||
        map['schema'] != schema) {
      throw const FormatException('invalid call signal schema');
    }
    final rawCallId = map['call_id'];
    final messageId = map['message_id'];
    final rawEvent = map['event'];
    final senderAccount = map['sender_account_peer_id'];
    final senderDevice = map['sender_device_peer_id'];
    final recipientAccount = map['recipient_account_peer_id'];
    final recipientDevice = map['recipient_device_peer_id'];
    final sequence = map['sender_sequence'];
    final generation = map['ice_generation'];
    final createdAtMs = map['created_at_ms'];
    final expiresAtMs = map['expires_at_ms'];
    final rawPayload = map['payload'];
    if (rawCallId is! String ||
        messageId is! String ||
        rawEvent is! String ||
        senderAccount is! String ||
        senderDevice is! String ||
        recipientAccount is! String ||
        recipientDevice is! String ||
        sequence is! int ||
        sequence < 1 ||
        generation is! int ||
        generation < 0 ||
        createdAtMs is! int ||
        expiresAtMs is! int ||
        createdAtMs < 0 ||
        expiresAtMs <= createdAtMs ||
        rawPayload is! Map) {
      throw const FormatException('invalid call signal field types');
    }
    final callId = CallId.tryParse(rawCallId);
    if (callId == null ||
        CallId.tryParse(messageId) == null ||
        !_validIdentity(senderAccount) ||
        !_validIdentity(senderDevice) ||
        !_validIdentity(recipientAccount) ||
        !_validIdentity(recipientDevice)) {
      throw const FormatException('invalid call signal identifiers');
    }
    final event = CallSignalType.parse(rawEvent);
    if (_isPreconnect(event) &&
        expiresAtMs - createdAtMs > maximumPreconnectLifetimeMs) {
      throw const FormatException('preconnect call signal exceeds lifetime');
    }
    final payload = _copyStringMap(rawPayload);
    _validatePayload(event, payload);
    final signal = CallSignal._(
      callId: callId,
      messageId: messageId,
      event: event,
      senderAccountPeerId: senderAccount,
      senderDevicePeerId: senderDevice,
      recipientAccountPeerId: recipientAccount,
      recipientDevicePeerId: recipientDevice,
      senderSequence: sequence,
      iceGeneration: generation,
      createdAtMs: createdAtMs,
      expiresAtMs: expiresAtMs,
      payload: payload,
    );
    try {
      if (utf8.encode(jsonEncode(signal.toMap())).length >
          maximumEncodedBytes) {
        throw const FormatException('call signal exceeds maximum size');
      }
    } on JsonUnsupportedObjectError {
      throw const FormatException('call signal contains invalid JSON');
    }
    return signal;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'schema': schema,
    'call_id': callId.value,
    'message_id': messageId,
    'event': event.wireName,
    'sender_account_peer_id': senderAccountPeerId,
    'sender_device_peer_id': senderDevicePeerId,
    'recipient_account_peer_id': recipientAccountPeerId,
    'recipient_device_peer_id': recipientDevicePeerId,
    'sender_sequence': senderSequence,
    'ice_generation': iceGeneration,
    'created_at_ms': createdAtMs,
    'expires_at_ms': expiresAtMs,
    'payload': _copyJsonForOutput(payload),
  };

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'schema': schema,
    'event': event.wireName,
    'senderSequence': senderSequence,
    'iceGeneration': iceGeneration,
    'payloadFieldCount': payload.length,
  };

  @override
  String toString() => 'CallSignal(${toDiagnosticMap()})';

  static Map<String, Object?> _copyStringMap(Map<Object?, Object?> input) {
    final result = <String, Object?>{};
    for (final entry in input.entries) {
      if (entry.key is! String) {
        throw const FormatException('invalid call signal payload key');
      }
      result[entry.key! as String] = _freezeJson(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static Object? _freezeJson(Object? value) {
    if (value is Map) return _copyStringMap(value);
    if (value is List) {
      return List<Object?>.unmodifiable(value.map<Object?>(_freezeJson));
    }
    return value;
  }

  static Object? _copyJsonForOutput(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key! as String: _copyJsonForOutput(entry.value),
      };
    }
    if (value is List) {
      return value.map<Object?>(_copyJsonForOutput).toList(growable: true);
    }
    return value;
  }

  static bool _validIdentity(String value) =>
      value.trim() == value && value.isNotEmpty && value.length <= 512;

  static bool _isPreconnect(CallSignalType event) => switch (event) {
    CallSignalType.invite ||
    CallSignalType.ringing ||
    CallSignalType.accept ||
    CallSignalType.reject => true,
    _ => false,
  };

  static void _validatePayload(
    CallSignalType event,
    Map<String, Object?> payload,
  ) {
    switch (event) {
      case CallSignalType.invite:
        const allowed = <String>{'capabilities', 'metadata'};
        if (payload.keys.toSet().difference(allowed).isNotEmpty ||
            !_validJson(payload, depth: 0) ||
            _containsForbiddenInviteKey(payload)) {
          throw const FormatException('invalid invite payload');
        }
        if (utf8.encode(jsonEncode(payload)).length >
            maximumInvitePayloadBytes) {
          throw const FormatException('invalid invite payload');
        }
        return;
      case CallSignalType.ringing:
      case CallSignalType.accept:
      case CallSignalType.iceRestart:
        if (payload.isNotEmpty) {
          throw const FormatException('signal event requires empty payload');
        }
        return;
      case CallSignalType.reject:
      case CallSignalType.terminate:
        if (payload.keys.length != 1 ||
            payload.keys.single != 'reason' ||
            payload['reason'] is! String) {
          throw const FormatException('invalid terminal signal payload');
        }
        CallEndReason.parseWire(payload['reason']! as String);
        return;
      case CallSignalType.offer:
      case CallSignalType.answer:
        if (payload.keys.toSet().difference(const <String>{
              'description',
              'fingerprint',
            }).isNotEmpty ||
            payload.length != 2 ||
            payload['description'] is! String ||
            payload['fingerprint'] is! String ||
            (payload['description']! as String).isEmpty ||
            (payload['fingerprint']! as String).isEmpty) {
          throw const FormatException('invalid description signal payload');
        }
        return;
      case CallSignalType.ice:
        const allowed = <String>{'candidate', 'media_id', 'media_line_index'};
        if (payload.keys.toSet().difference(allowed).isNotEmpty ||
            payload['candidate'] is! String ||
            (payload['candidate']! as String).isEmpty ||
            (payload.containsKey('media_id') &&
                payload['media_id'] is! String?) ||
            (payload.containsKey('media_line_index') &&
                payload['media_line_index'] is! int?)) {
          throw const FormatException('invalid ICE signal payload');
        }
        return;
    }
  }

  static bool _validJson(Object? value, {required int depth}) {
    if (depth > 4) return false;
    if (value == null || value is bool) return true;
    if (value is num) return value.isFinite;
    if (value is String) return value.length <= 512;
    if (value is List) {
      return value.length <= 32 &&
          value.every((item) => _validJson(item, depth: depth + 1));
    }
    if (value is Map) {
      if (value.length > 32) return false;
      for (final entry in value.entries) {
        if (entry.key is! String ||
            entry.key.length > 64 ||
            !_validJson(entry.value, depth: depth + 1)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  static bool _containsForbiddenInviteKey(Object? value) {
    const forbidden = <String>{
      'sdp',
      'candidate',
      'candidates',
      'offer',
      'answer',
    };
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String &&
            forbidden.contains((entry.key as String).toLowerCase())) {
          return true;
        }
        if (_containsForbiddenInviteKey(entry.value)) return true;
      }
    } else if (value is List) {
      return value.any(_containsForbiddenInviteKey);
    }
    return false;
  }
}
