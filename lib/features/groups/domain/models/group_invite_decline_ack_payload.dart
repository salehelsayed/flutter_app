import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

const groupInviteDeclineAckType = 'group_invite_decline_ack';
const groupInviteDeclineAckEnvelopeVersion = '1';
const groupInviteDeclineAckSignatureEnvelopeField = 'declineSignature';
const groupInviteDeclineAckSignatureAlgorithmField = 'signatureAlgorithm';
const groupInviteDeclineAckSignedPayloadField = 'signedPayload';
const groupInviteDeclineAckSignatureField = 'signature';
const groupInviteDeclineAckSignatureAlgorithm = 'ed25519';
const groupInviteDeclineAckSignatureSchemaVersion = 1;

enum GroupInviteDeclineAckPayloadParseFailure {
  malformed,
  missingSignature,
  invalidSignature,
}

class GroupInviteDeclineAckPayloadParseResult {
  const GroupInviteDeclineAckPayloadParseResult._(this.payload, this.failure);

  const GroupInviteDeclineAckPayloadParseResult.success(
    GroupInviteDeclineAckPayload payload,
  ) : this._(payload, null);

  const GroupInviteDeclineAckPayloadParseResult.failure(
    GroupInviteDeclineAckPayloadParseFailure failure,
  ) : this._(null, failure);

  final GroupInviteDeclineAckPayload? payload;
  final GroupInviteDeclineAckPayloadParseFailure? failure;

  bool get isSuccess => payload != null;
}

class GroupInviteDeclineAckSignature {
  final String signatureAlgorithm;
  final String signedPayload;
  final String signature;

  const GroupInviteDeclineAckSignature({
    required this.signatureAlgorithm,
    required this.signedPayload,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      groupInviteDeclineAckSignatureAlgorithmField: signatureAlgorithm,
      groupInviteDeclineAckSignedPayloadField: signedPayload,
      groupInviteDeclineAckSignatureField: signature,
    };
  }

  static GroupInviteDeclineAckSignature? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final signatureAlgorithm =
        value[groupInviteDeclineAckSignatureAlgorithmField] as String?;
    final signedPayload =
        value[groupInviteDeclineAckSignedPayloadField] as String?;
    final signature = value[groupInviteDeclineAckSignatureField] as String?;
    if (signatureAlgorithm == null ||
        signedPayload == null ||
        signature == null) {
      return null;
    }
    return GroupInviteDeclineAckSignature(
      signatureAlgorithm: signatureAlgorithm,
      signedPayload: signedPayload,
      signature: signature,
    );
  }
}

/// A decliner's acknowledgement, sent direct (encrypted to the inviter) so the
/// inviter's per-peer delivery-attempt row can flip to `declined`. The decliner
/// is a pending invitee, not yet a roster member, so this 1:1 envelope is the
/// only viable channel. Best-effort: the local decline never blocks on it.
class GroupInviteDeclineAckPayload {
  final String inviteId;
  final String groupId;
  final String declinedByPeerId;
  final String declinedAt;
  final String expiresAt;
  final GroupInviteDeclineAckSignature? declineSignature;

  const GroupInviteDeclineAckPayload({
    required this.inviteId,
    required this.groupId,
    required this.declinedByPeerId,
    required this.declinedAt,
    required this.expiresAt,
    this.declineSignature,
  });

  DateTime get declinedAtDateTime => DateTime.parse(declinedAt).toUtc();

  DateTime get expiresAtDateTime => DateTime.parse(expiresAt).toUtc();

  bool isExpiredAt(DateTime now) => !expiresAtDateTime.isAfter(now.toUtc());

  Map<String, dynamic> _toPayloadMap() {
    return {
      'inviteId': inviteId,
      'groupId': groupId,
      'declinedByPeerId': declinedByPeerId,
      'declinedAt': declinedAt,
      'expiresAt': expiresAt,
      if (declineSignature != null)
        groupInviteDeclineAckSignatureEnvelopeField: declineSignature!.toJson(),
    };
  }

  Map<String, Object?> _toSignedPayloadMap() {
    return {
      'schemaVersion': groupInviteDeclineAckSignatureSchemaVersion,
      'type': groupInviteDeclineAckType,
      'inviteId': inviteId,
      'groupId': groupId,
      'declinedByPeerId': declinedByPeerId,
      'declinedAt': declinedAt,
      'expiresAt': expiresAt,
    };
  }

  String canonicalDeclineAckSignedPayload() {
    return canonicalizeGroupEventLogPayload(_toSignedPayloadMap());
  }

  GroupInviteDeclineAckPayload withDeclineSignature({
    required String signature,
    String? signedPayload,
  }) {
    return GroupInviteDeclineAckPayload(
      inviteId: inviteId,
      groupId: groupId,
      declinedByPeerId: declinedByPeerId,
      declinedAt: declinedAt,
      expiresAt: expiresAt,
      declineSignature: GroupInviteDeclineAckSignature(
        signatureAlgorithm: groupInviteDeclineAckSignatureAlgorithm,
        signedPayload: signedPayload ?? canonicalDeclineAckSignedPayload(),
        signature: signature,
      ),
    );
  }

  String toInnerJson() => jsonEncode(_toPayloadMap());

  static GroupInviteDeclineAckPayload? fromInnerJson(String innerJson) {
    return parseInnerJsonDetailed(innerJson).payload;
  }

  static GroupInviteDeclineAckPayloadParseResult parseInnerJsonDetailed(
    String innerJson,
  ) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      return _fromPayloadMap(payload);
    } catch (_) {
      return const GroupInviteDeclineAckPayloadParseResult.failure(
        GroupInviteDeclineAckPayloadParseFailure.malformed,
      );
    }
  }

  static GroupInviteDeclineAckPayloadParseResult _fromPayloadMap(
    Map<String, dynamic> payload,
  ) {
    final inviteId = payload['inviteId'] as String?;
    final groupId = payload['groupId'] as String?;
    final declinedByPeerId = payload['declinedByPeerId'] as String?;
    final declinedAt = payload['declinedAt'] as String?;
    final expiresAt = payload['expiresAt'] as String?;
    final declineSignature = GroupInviteDeclineAckSignature.fromJson(
      payload[groupInviteDeclineAckSignatureEnvelopeField],
    );

    if (_isBlank(inviteId) ||
        _isBlank(groupId) ||
        _isBlank(declinedByPeerId) ||
        _isBlank(declinedAt) ||
        _isBlank(expiresAt)) {
      return const GroupInviteDeclineAckPayloadParseResult.failure(
        GroupInviteDeclineAckPayloadParseFailure.malformed,
      );
    }

    final declinedAtDateTime = DateTime.tryParse(declinedAt!)?.toUtc();
    final expiresAtDateTime = DateTime.tryParse(expiresAt!)?.toUtc();
    if (declinedAtDateTime == null ||
        expiresAtDateTime == null ||
        !expiresAtDateTime.isAfter(declinedAtDateTime)) {
      return const GroupInviteDeclineAckPayloadParseResult.failure(
        GroupInviteDeclineAckPayloadParseFailure.malformed,
      );
    }

    final ack = GroupInviteDeclineAckPayload(
      inviteId: inviteId!,
      groupId: groupId!,
      declinedByPeerId: declinedByPeerId!,
      declinedAt: declinedAtDateTime.toIso8601String(),
      expiresAt: expiresAtDateTime.toIso8601String(),
      declineSignature: declineSignature,
    );

    final signatureFailure = ack._validateSignature();
    if (signatureFailure != null) {
      return GroupInviteDeclineAckPayloadParseResult.failure(signatureFailure);
    }

    return GroupInviteDeclineAckPayloadParseResult.success(ack);
  }

  GroupInviteDeclineAckPayloadParseFailure? _validateSignature() {
    final declineSignature = this.declineSignature;
    if (declineSignature == null) {
      return GroupInviteDeclineAckPayloadParseFailure.missingSignature;
    }
    if (declineSignature.signatureAlgorithm !=
            groupInviteDeclineAckSignatureAlgorithm ||
        declineSignature.signedPayload.trim().isEmpty ||
        declineSignature.signature.trim().isEmpty) {
      return GroupInviteDeclineAckPayloadParseFailure.invalidSignature;
    }

    final decodedSignedPayload = _decodeSignedPayload(
      declineSignature.signedPayload,
    );
    if (decodedSignedPayload == null) {
      return GroupInviteDeclineAckPayloadParseFailure.invalidSignature;
    }

    final canonicalSignedPayload = canonicalizeGroupEventLogPayload(
      decodedSignedPayload,
    );
    if (canonicalSignedPayload != declineSignature.signedPayload) {
      return GroupInviteDeclineAckPayloadParseFailure.invalidSignature;
    }
    if (canonicalDeclineAckSignedPayload() != declineSignature.signedPayload) {
      return GroupInviteDeclineAckPayloadParseFailure.invalidSignature;
    }
    return null;
  }

  static Map<String, Object?>? _decodeSignedPayload(String signedPayload) {
    try {
      final decoded = jsonDecode(signedPayload);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static String buildEncryptedEnvelope({
    required String senderPeerId,
    required String inviteId,
    required String kem,
    required String ciphertext,
    required String nonce,
  }) {
    final envelope = {
      'type': groupInviteDeclineAckType,
      'version': groupInviteDeclineAckEnvelopeVersion,
      'id': inviteId,
      'senderPeerId': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    };
    return jsonEncode(envelope);
  }

  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != groupInviteDeclineAckType) return null;
      if (json['version'] != groupInviteDeclineAckEnvelopeVersion) return null;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return null;
      if (_isBlank(json['id'] as String?) ||
          _isBlank(json['senderPeerId'] as String?) ||
          _isBlank(encrypted['kem'] as String?) ||
          _isBlank(encrypted['ciphertext'] as String?) ||
          _isBlank(encrypted['nonce'] as String?)) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
