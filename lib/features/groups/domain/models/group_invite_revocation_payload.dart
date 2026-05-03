import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';

const groupInviteRevocationType = 'group_invite_revocation';
const groupInviteRevocationEnvelopeVersion = '1';
const groupInviteRevocationSignatureEnvelopeField = 'revocationSignature';
const groupInviteRevocationSignatureAlgorithmField = 'signatureAlgorithm';
const groupInviteRevocationSignedPayloadField = 'signedPayload';
const groupInviteRevocationSignatureField = 'signature';
const groupInviteRevocationSignatureAlgorithm = 'ed25519';
const groupInviteRevocationSignatureSchemaVersion = 1;

enum GroupInviteRevocationPayloadParseFailure {
  malformed,
  missingSignature,
  invalidSignature,
}

class GroupInviteRevocationPayloadParseResult {
  const GroupInviteRevocationPayloadParseResult._(this.payload, this.failure);

  const GroupInviteRevocationPayloadParseResult.success(
    GroupInviteRevocationPayload payload,
  ) : this._(payload, null);

  const GroupInviteRevocationPayloadParseResult.failure(
    GroupInviteRevocationPayloadParseFailure failure,
  ) : this._(null, failure);

  final GroupInviteRevocationPayload? payload;
  final GroupInviteRevocationPayloadParseFailure? failure;

  bool get isSuccess => payload != null;
}

class GroupInviteRevocationSignature {
  final String signatureAlgorithm;
  final String signedPayload;
  final String signature;

  const GroupInviteRevocationSignature({
    required this.signatureAlgorithm,
    required this.signedPayload,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      groupInviteRevocationSignatureAlgorithmField: signatureAlgorithm,
      groupInviteRevocationSignedPayloadField: signedPayload,
      groupInviteRevocationSignatureField: signature,
    };
  }

  static GroupInviteRevocationSignature? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final signatureAlgorithm =
        value[groupInviteRevocationSignatureAlgorithmField] as String?;
    final signedPayload =
        value[groupInviteRevocationSignedPayloadField] as String?;
    final signature = value[groupInviteRevocationSignatureField] as String?;
    if (signatureAlgorithm == null ||
        signedPayload == null ||
        signature == null) {
      return null;
    }
    return GroupInviteRevocationSignature(
      signatureAlgorithm: signatureAlgorithm,
      signedPayload: signedPayload,
      signature: signature,
    );
  }
}

class GroupInviteRevocationPayload {
  final String inviteId;
  final String groupId;
  final String recipientPeerId;
  final String revokedByPeerId;
  final String revokedAt;
  final String expiresAt;
  final Map<String, dynamic> revokerAuthorization;
  final GroupInviteRevocationSignature? revocationSignature;

  const GroupInviteRevocationPayload({
    required this.inviteId,
    required this.groupId,
    required this.recipientPeerId,
    required this.revokedByPeerId,
    required this.revokedAt,
    required this.expiresAt,
    required this.revokerAuthorization,
    this.revocationSignature,
  });

  DateTime get revokedAtDateTime => DateTime.parse(revokedAt).toUtc();

  DateTime get expiresAtDateTime => DateTime.parse(expiresAt).toUtc();

  bool isExpiredAt(DateTime now) => !expiresAtDateTime.isAfter(now.toUtc());

  bool isBoundToRecipient(String peerId) {
    return recipientPeerId.trim().isNotEmpty && recipientPeerId == peerId;
  }

  Map<String, dynamic> _toPayloadMap() {
    return {
      'inviteId': inviteId,
      'groupId': groupId,
      'recipientPeerId': recipientPeerId,
      'revokedByPeerId': revokedByPeerId,
      'revokedAt': revokedAt,
      'expiresAt': expiresAt,
      'revokerAuthorization': revokerAuthorization,
      if (revocationSignature != null)
        groupInviteRevocationSignatureEnvelopeField: revocationSignature!
            .toJson(),
    };
  }

  Map<String, Object?> _toSignedPayloadMap() {
    return {
      'schemaVersion': groupInviteRevocationSignatureSchemaVersion,
      'type': groupInviteRevocationType,
      'inviteId': inviteId,
      'groupId': groupId,
      'recipientPeerId': recipientPeerId,
      'revokedByPeerId': revokedByPeerId,
      'revokedAt': revokedAt,
      'expiresAt': expiresAt,
      'revokerAuthorization': revokerAuthorization,
    };
  }

  String canonicalRevocationSignedPayload() {
    return canonicalizeGroupEventLogPayload(_toSignedPayloadMap());
  }

  GroupInviteRevocationPayload withRevocationSignature({
    required String signature,
    String? signedPayload,
  }) {
    return GroupInviteRevocationPayload(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      revokedByPeerId: revokedByPeerId,
      revokedAt: revokedAt,
      expiresAt: expiresAt,
      revokerAuthorization: revokerAuthorization,
      revocationSignature: GroupInviteRevocationSignature(
        signatureAlgorithm: groupInviteRevocationSignatureAlgorithm,
        signedPayload: signedPayload ?? canonicalRevocationSignedPayload(),
        signature: signature,
      ),
    );
  }

  String toInnerJson() => jsonEncode(_toPayloadMap());

  static GroupInviteRevocationPayload? fromInnerJson(String innerJson) {
    return parseInnerJsonDetailed(innerJson).payload;
  }

  static GroupInviteRevocationPayloadParseResult parseInnerJsonDetailed(
    String innerJson,
  ) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      return _fromPayloadMap(payload);
    } catch (_) {
      return const GroupInviteRevocationPayloadParseResult.failure(
        GroupInviteRevocationPayloadParseFailure.malformed,
      );
    }
  }

  static GroupInviteRevocationPayloadParseResult _fromPayloadMap(
    Map<String, dynamic> payload,
  ) {
    final inviteId = payload['inviteId'] as String?;
    final groupId = payload['groupId'] as String?;
    final recipientPeerId = payload['recipientPeerId'] as String?;
    final revokedByPeerId = payload['revokedByPeerId'] as String?;
    final revokedAt = payload['revokedAt'] as String?;
    final expiresAt = payload['expiresAt'] as String?;
    final revokerAuthorization = payload['revokerAuthorization'];
    final revocationSignature = GroupInviteRevocationSignature.fromJson(
      payload[groupInviteRevocationSignatureEnvelopeField],
    );

    if (_isBlank(inviteId) ||
        _isBlank(groupId) ||
        _isBlank(recipientPeerId) ||
        _isBlank(revokedByPeerId) ||
        _isBlank(revokedAt) ||
        _isBlank(expiresAt) ||
        revokerAuthorization is! Map) {
      return const GroupInviteRevocationPayloadParseResult.failure(
        GroupInviteRevocationPayloadParseFailure.malformed,
      );
    }

    final revokedAtDateTime = DateTime.tryParse(revokedAt!)?.toUtc();
    final expiresAtDateTime = DateTime.tryParse(expiresAt!)?.toUtc();
    if (revokedAtDateTime == null ||
        expiresAtDateTime == null ||
        !expiresAtDateTime.isAfter(revokedAtDateTime)) {
      return const GroupInviteRevocationPayloadParseResult.failure(
        GroupInviteRevocationPayloadParseFailure.malformed,
      );
    }

    final revocation = GroupInviteRevocationPayload(
      inviteId: inviteId!,
      groupId: groupId!,
      recipientPeerId: recipientPeerId!,
      revokedByPeerId: revokedByPeerId!,
      revokedAt: revokedAtDateTime.toIso8601String(),
      expiresAt: expiresAtDateTime.toIso8601String(),
      revokerAuthorization: Map<String, dynamic>.from(revokerAuthorization),
      revocationSignature: revocationSignature,
    );

    final signatureFailure = revocation._validateSignature();
    if (signatureFailure != null) {
      return GroupInviteRevocationPayloadParseResult.failure(signatureFailure);
    }

    return GroupInviteRevocationPayloadParseResult.success(revocation);
  }

  GroupInviteRevocationPayloadParseFailure? _validateSignature() {
    final revocationSignature = this.revocationSignature;
    if (revocationSignature == null) {
      return GroupInviteRevocationPayloadParseFailure.missingSignature;
    }
    if (revocationSignature.signatureAlgorithm !=
            groupInviteRevocationSignatureAlgorithm ||
        revocationSignature.signedPayload.trim().isEmpty ||
        revocationSignature.signature.trim().isEmpty) {
      return GroupInviteRevocationPayloadParseFailure.invalidSignature;
    }

    final decodedSignedPayload = _decodeSignedPayload(
      revocationSignature.signedPayload,
    );
    if (decodedSignedPayload == null) {
      return GroupInviteRevocationPayloadParseFailure.invalidSignature;
    }

    final canonicalSignedPayload = canonicalizeGroupEventLogPayload(
      decodedSignedPayload,
    );
    if (canonicalSignedPayload != revocationSignature.signedPayload) {
      return GroupInviteRevocationPayloadParseFailure.invalidSignature;
    }
    if (canonicalRevocationSignedPayload() !=
        revocationSignature.signedPayload) {
      return GroupInviteRevocationPayloadParseFailure.invalidSignature;
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
      'type': groupInviteRevocationType,
      'version': groupInviteRevocationEnvelopeVersion,
      'id': inviteId,
      'senderPeerId': senderPeerId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    };
    return jsonEncode(envelope);
  }

  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != groupInviteRevocationType) return null;
      if (json['version'] != groupInviteRevocationEnvelopeVersion) return null;
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
