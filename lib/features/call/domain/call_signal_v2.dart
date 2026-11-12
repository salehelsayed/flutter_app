import 'dart:convert';

import 'call_end_reason.dart';
import 'call_id.dart';
import 'call_signal.dart';

/// This version has its own closed event vocabulary; v1 is unchanged.
enum CallSignalV2Type {
  invite('invite'),
  ringing('ringing'),
  accept('accept'),
  reject('reject'),
  offer('offer'),
  answer('answer'),
  ice('ice'),
  iceRestart('ice_restart'),
  terminate('terminate'),
  mediaRequest('media_request'),
  mediaResponse('media_response'),
  mediaCommit('media_commit'),
  mediaCommitAck('media_commit_ack'),
  mediaAbort('media_abort'),
  cameraState('camera_state');

  const CallSignalV2Type(this.wireName);
  final String wireName;

  static CallSignalV2Type parse(String value) {
    for (final event in values) {
      if (event.wireName == value) return event;
    }
    throw const FormatException('unsupported v2 call event');
  }
}

/// Strict encrypted v2 data. Parsing alone cannot authorize capture or a call.
final class CallSignalV2 {
  CallSignalV2._({
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
  }) : payload = Map<String, Object?>.unmodifiable({
         for (final entry in payload.entries)
           entry.key: entry.value is List
               ? List<Object?>.unmodifiable(entry.value! as List)
               : entry.value,
       });

  static const String schema = 'mknoon.call_signal.v2';
  static const Set<String> _keys = {
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
  final CallSignalV2Type event;
  final String senderAccountPeerId;
  final String senderDevicePeerId;
  final String recipientAccountPeerId;
  final String recipientDevicePeerId;
  final int senderSequence;
  final int iceGeneration;
  final int createdAtMs;
  final int expiresAtMs;
  final Map<String, Object?> payload;

  factory CallSignalV2.fromMap(
    Map<String, Object?> map, {
    bool videoEnabled = false,
  }) {
    if (!videoEnabled) {
      throw const FormatException('call signal v2 is disabled');
    }
    _exactKeys(map, _keys);
    if (map['schema'] != schema) {
      throw const FormatException('invalid v2 call schema');
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
        createdAtMs < 0 ||
        expiresAtMs is! int ||
        expiresAtMs <= createdAtMs ||
        rawPayload is! Map) {
      throw const FormatException('invalid v2 call field types');
    }
    final callId = CallId.tryParse(rawCallId);
    if (callId == null ||
        CallId.tryParse(messageId) == null ||
        !_validIdentity(senderAccount) ||
        !_validIdentity(senderDevice) ||
        !_validIdentity(recipientAccount) ||
        !_validIdentity(recipientDevice)) {
      throw const FormatException('invalid v2 call identifiers');
    }
    final event = CallSignalV2Type.parse(rawEvent);
    if (const {
          CallSignalV2Type.invite,
          CallSignalV2Type.ringing,
          CallSignalV2Type.accept,
          CallSignalV2Type.reject,
        }.contains(event) &&
        expiresAtMs - createdAtMs > CallSignal.maximumPreconnectLifetimeMs) {
      throw const FormatException('v2 preconnect lifetime exceeded');
    }
    final payload = <String, Object?>{};
    for (final entry in rawPayload.entries) {
      if (entry.key is! String) {
        throw const FormatException('invalid v2 payload key');
      }
      payload[entry.key! as String] = entry.value;
    }
    _validatePayload(event, payload);
    final signal = CallSignalV2._(
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
    if (event == CallSignalV2Type.invite &&
        utf8.encode(jsonEncode(payload)).length >
            CallSignal.maximumInvitePayloadBytes) {
      throw const FormatException('v2 invite payload too large');
    }
    if (utf8.encode(jsonEncode(signal.toMap())).length >
        CallSignal.maximumEncodedBytes) {
      throw const FormatException('v2 call signal too large');
    }
    return signal;
  }

  Map<String, Object?> toMap() => {
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
    'payload': <String, Object?>{
      for (final entry in payload.entries)
        entry.key: entry.value is List
            ? List<Object?>.of(entry.value! as List)
            : entry.value,
    },
  };

  Map<String, Object?> toDiagnosticMap() => {
    'schema': schema,
    'event': event.wireName,
    'senderSequence': senderSequence,
    'iceGeneration': iceGeneration,
    'payloadFieldCount': payload.length,
  };

  @override
  String toString() => 'CallSignalV2(${toDiagnosticMap()})';

  static bool _validIdentity(String value) =>
      value.trim() == value && value.isNotEmpty && value.length <= 512;

  static void _exactKeys(Map<String, Object?> map, Set<String> expected) {
    if (map.length != expected.length || !map.keys.every(expected.contains)) {
      throw const FormatException('invalid v2 field set');
    }
  }

  static void _validatePayload(CallSignalV2Type event, Map<String, Object?> p) {
    switch (event) {
      case CallSignalV2Type.invite:
        _exactKeys(p, const {'media', 'camera', 'capabilities'});
        _mediaCamera(p, 'media');
        final capabilities = p['capabilities'];
        if (capabilities is! List ||
            capabilities.length != 2 ||
            capabilities[0] is! String ||
            capabilities[0] != 'audio' ||
            capabilities[1] is! String ||
            capabilities[1] != 'video') {
          throw const FormatException('invalid v2 invite capabilities');
        }
        return;
      case CallSignalV2Type.ringing:
        _exactKeys(p, const {});
        return;
      case CallSignalV2Type.accept:
        _exactKeys(p, const {'media', 'camera'});
        _mediaCamera(p, 'media');
        return;
      case CallSignalV2Type.reject:
      case CallSignalV2Type.terminate:
        _exactKeys(p, const {'reason'});
        _text(p, 'reason');
        CallEndReason.parseWire(p['reason']! as String);
        return;
      case CallSignalV2Type.offer:
      case CallSignalV2Type.answer:
        _exactKeys(p, const {
          'negotiation_id',
          'purpose',
          'switch_id',
          'media_revision',
          'media',
          'description',
          'fingerprint',
        });
        _uuid(p, 'negotiation_id');
        _oneOf(p, 'purpose', const {
          'initial',
          'media_switch',
          'ice_restart',
          'media_repair',
        });
        _revision(p, 'media_revision');
        _oneOf(p, 'media', const {'audio', 'video'});
        _text(p, 'description');
        _text(p, 'fingerprint');
        final purpose = p['purpose'];
        if (purpose == 'media_switch' || purpose == 'media_repair') {
          _uuid(p, 'switch_id');
        } else if (p['switch_id'] != null) {
          throw const FormatException('unexpected v2 switch binding');
        }
        if (purpose == 'initial' && p['media_revision'] != 0) {
          throw const FormatException('initial media revision must be zero');
        }
        if (purpose == 'media_switch' && p['media_revision'] == 0) {
          throw const FormatException('media switch must advance revision');
        }
        if (purpose == 'media_repair' && p['media'] != 'audio') {
          throw const FormatException('media repair must preserve audio');
        }
        return;
      case CallSignalV2Type.ice:
        _exactKeys(p, const {
          'negotiation_id',
          'candidate',
          'media_id',
          'media_line_index',
        });
        _uuid(p, 'negotiation_id');
        _text(p, 'candidate');
        if (p['media_id'] is! String? || p['media_line_index'] is! int?) {
          throw const FormatException('invalid v2 ICE fields');
        }
        return;
      case CallSignalV2Type.iceRestart:
        _exactKeys(p, const {'negotiation_id', 'media_revision'});
        _uuid(p, 'negotiation_id');
        _revision(p, 'media_revision');
        return;
      case CallSignalV2Type.mediaRequest:
        _exactKeys(p, const {
          'switch_id',
          'base_revision',
          'target_media',
          'camera',
        });
        _uuid(p, 'switch_id');
        _revision(p, 'base_revision');
        _mediaCamera(p, 'target_media');
        return;
      case CallSignalV2Type.mediaResponse:
        _exactKeys(p, const {
          'switch_id',
          'base_revision',
          'decision',
          'camera',
        });
        _uuid(p, 'switch_id');
        _revision(p, 'base_revision');
        _oneOf(p, 'decision', const {
          'accept',
          'decline',
          'busy',
          'stale',
          'superseded',
          'unsupported',
        });
        _oneOf(p, 'camera', const {'on', 'off'});
        if (p['decision'] != 'accept' && p['camera'] != 'off') {
          throw const FormatException('declined media cannot enable camera');
        }
        return;
      case CallSignalV2Type.mediaCommit:
      case CallSignalV2Type.mediaCommitAck:
        _exactKeys(p, const {'switch_id', 'media_revision', 'media'});
        _uuid(p, 'switch_id');
        _revision(p, 'media_revision');
        _oneOf(p, 'media', const {'audio', 'video'});
        return;
      case CallSignalV2Type.mediaAbort:
        _exactKeys(p, const {
          'switch_id',
          'base_revision',
          'media_revision',
          'media',
          'reason',
        });
        _uuid(p, 'switch_id');
        _revision(p, 'base_revision');
        _revision(p, 'media_revision');
        _oneOf(p, 'media', const {'audio'});
        _oneOf(p, 'reason', const {
          'cancelled',
          'timeout',
          'permission',
          'negotiation',
          'transport',
          'superseded',
        });
        return;
      case CallSignalV2Type.cameraState:
        _exactKeys(p, const {'media_revision', 'state'});
        _revision(p, 'media_revision');
        _oneOf(p, 'state', const {'on', 'off', 'paused'});
        return;
    }
  }

  static void _oneOf(
    Map<String, Object?> payload,
    String key,
    Set<String> values,
  ) {
    final value = payload[key];
    if (value is! String || !values.contains(value)) {
      throw const FormatException('invalid v2 enum');
    }
  }

  static void _text(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || value.isEmpty) {
      throw const FormatException('invalid v2 text field');
    }
  }

  static void _uuid(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! String || CallId.tryParse(value) == null) {
      throw const FormatException('invalid v2 transaction identifier');
    }
  }

  static void _revision(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is! int || value < 0) {
      throw const FormatException('invalid v2 media revision');
    }
  }

  static void _mediaCamera(Map<String, Object?> payload, String mediaKey) {
    _oneOf(payload, mediaKey, const {'audio', 'video'});
    _oneOf(payload, 'camera', const {'on', 'off'});
    if (payload[mediaKey] == 'audio' && payload['camera'] != 'off') {
      throw const FormatException('audio media requires camera off');
    }
  }
}
