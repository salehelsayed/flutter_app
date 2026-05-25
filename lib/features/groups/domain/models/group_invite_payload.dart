import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';

import 'group_invite_policy.dart';
import 'group_welcome_key_package.dart';

export 'group_invite_policy.dart';

const groupInviteSignatureEnvelopeField = 'inviteSignature';
const groupInviteSignatureAlgorithmField = 'signatureAlgorithm';
const groupInviteSignedPayloadField = 'signedPayload';
const groupInviteSignatureField = 'signature';
const groupInviteSignatureAlgorithm = 'ed25519';
const groupInviteSignatureSchemaVersion = 1;
const groupInviteMembershipFreshnessProofField = 'membershipFreshnessProof';
const groupInviteMembershipFreshnessProofSchemaVersion = 1;
const groupInviteMembershipFreshnessTtl = Duration(hours: 24);
const groupInviteMembershipFreshnessClockSkew = Duration(minutes: 5);

enum GroupInvitePayloadParseFailure {
  malformed,
  invalidPolicy,
  invalidWelcomeKeyPackage,
  expired,
  staleMembershipFreshness,
  missingSignature,
  invalidSignature,
}

class GroupInvitePayloadParseResult {
  const GroupInvitePayloadParseResult._(this.payload, this.failure);

  const GroupInvitePayloadParseResult.success(GroupInvitePayload payload)
    : this._(payload, null);

  const GroupInvitePayloadParseResult.failure(
    GroupInvitePayloadParseFailure failure,
  ) : this._(null, failure);

  final GroupInvitePayload? payload;
  final GroupInvitePayloadParseFailure? failure;

  bool get isSuccess => payload != null;

  bool get isSecurityFailure =>
      failure == GroupInvitePayloadParseFailure.staleMembershipFreshness ||
      failure == GroupInvitePayloadParseFailure.missingSignature ||
      failure == GroupInvitePayloadParseFailure.invalidSignature;
}

class GroupInviteSignature {
  final String signatureAlgorithm;
  final String signedPayload;
  final String signature;

  const GroupInviteSignature({
    required this.signatureAlgorithm,
    required this.signedPayload,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      groupInviteSignatureAlgorithmField: signatureAlgorithm,
      groupInviteSignedPayloadField: signedPayload,
      groupInviteSignatureField: signature,
    };
  }

  static GroupInviteSignature? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final signatureAlgorithm =
        value[groupInviteSignatureAlgorithmField] as String?;
    final signedPayload = value[groupInviteSignedPayloadField] as String?;
    final signature = value[groupInviteSignatureField] as String?;
    if (signatureAlgorithm == null ||
        signedPayload == null ||
        signature == null) {
      return null;
    }
    return GroupInviteSignature(
      signatureAlgorithm: signatureAlgorithm,
      signedPayload: signedPayload,
      signature: signature,
    );
  }
}

class GroupInviteMembershipFreshnessProof {
  final int schemaVersion;
  final String inviteId;
  final String groupId;
  final String? recipientPeerId;
  final String? recipientDeviceId;
  final String? recipientTransportPeerId;
  final String? recipientMlKemPublicKey;
  final String? recipientKeyPackageId;
  final String? recipientKeyPackagePublicMaterial;
  final String inviterPeerId;
  final String? inviterDeviceId;
  final String? inviterTransportPeerId;
  final String? inviterDeviceSigningPublicKey;
  final String? inviterKeyPackageId;
  final String inviterPublicKey;
  final int keyEpoch;
  final String groupConfigStateHash;
  final String membershipWatermark;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final Map<String, dynamic> inviterMemberSnapshot;

  const GroupInviteMembershipFreshnessProof({
    this.schemaVersion = groupInviteMembershipFreshnessProofSchemaVersion,
    required this.inviteId,
    required this.groupId,
    required this.recipientPeerId,
    this.recipientDeviceId,
    this.recipientTransportPeerId,
    this.recipientMlKemPublicKey,
    this.recipientKeyPackageId,
    this.recipientKeyPackagePublicMaterial,
    required this.inviterPeerId,
    this.inviterDeviceId,
    this.inviterTransportPeerId,
    this.inviterDeviceSigningPublicKey,
    this.inviterKeyPackageId,
    required this.inviterPublicKey,
    required this.keyEpoch,
    required this.groupConfigStateHash,
    required this.membershipWatermark,
    required this.issuedAt,
    required this.expiresAt,
    required this.inviterMemberSnapshot,
  });

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'inviteId': inviteId,
      'groupId': groupId,
      'recipientPeerId': recipientPeerId,
      if (_hasValue(recipientDeviceId)) 'recipientDeviceId': recipientDeviceId,
      if (_hasValue(recipientTransportPeerId))
        'recipientTransportPeerId': recipientTransportPeerId,
      if (_hasValue(recipientMlKemPublicKey))
        'recipientMlKemPublicKey': recipientMlKemPublicKey,
      if (_hasValue(recipientKeyPackageId))
        'recipientKeyPackageId': recipientKeyPackageId,
      if (_hasValue(recipientKeyPackagePublicMaterial))
        'recipientKeyPackagePublicMaterial': recipientKeyPackagePublicMaterial,
      'inviterPeerId': inviterPeerId,
      if (_hasValue(inviterDeviceId)) 'inviterDeviceId': inviterDeviceId,
      if (_hasValue(inviterTransportPeerId))
        'inviterTransportPeerId': inviterTransportPeerId,
      if (_hasValue(inviterDeviceSigningPublicKey))
        'inviterDeviceSigningPublicKey': inviterDeviceSigningPublicKey,
      if (_hasValue(inviterKeyPackageId))
        'inviterKeyPackageId': inviterKeyPackageId,
      'inviterPublicKey': inviterPublicKey,
      'keyEpoch': keyEpoch,
      'groupConfigStateHash': groupConfigStateHash,
      'membershipWatermark': membershipWatermark,
      'issuedAt': issuedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'inviterMemberSnapshot': inviterMemberSnapshot,
    };
  }

  static GroupInviteMembershipFreshnessProof? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final schemaVersion = value['schemaVersion'];
    final inviteId = _readRequiredString(value, 'inviteId');
    final groupId = _readRequiredString(value, 'groupId');
    final inviterPeerId = _readRequiredString(value, 'inviterPeerId');
    final inviterPublicKey = _readRequiredString(value, 'inviterPublicKey');
    final keyEpoch = value['keyEpoch'];
    final groupConfigStateHash = _readRequiredString(
      value,
      'groupConfigStateHash',
    );
    final membershipWatermark = _readRequiredString(
      value,
      'membershipWatermark',
    );
    final issuedAt = _readRequiredDateTime(value, 'issuedAt');
    final expiresAt = _readRequiredDateTime(value, 'expiresAt');
    final inviterMemberSnapshot = _readStringKeyedMap(
      value['inviterMemberSnapshot'],
    );
    if (schemaVersion != groupInviteMembershipFreshnessProofSchemaVersion ||
        inviteId == null ||
        groupId == null ||
        inviterPeerId == null ||
        inviterPublicKey == null ||
        keyEpoch is! int ||
        keyEpoch <= 0 ||
        groupConfigStateHash == null ||
        membershipWatermark == null ||
        issuedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(issuedAt) ||
        inviterMemberSnapshot == null) {
      return null;
    }

    return GroupInviteMembershipFreshnessProof(
      schemaVersion: schemaVersion,
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: _readOptionalString(value, 'recipientPeerId'),
      recipientDeviceId: _readOptionalString(value, 'recipientDeviceId'),
      recipientTransportPeerId: _readOptionalString(
        value,
        'recipientTransportPeerId',
      ),
      recipientMlKemPublicKey: _readOptionalString(
        value,
        'recipientMlKemPublicKey',
      ),
      recipientKeyPackageId: _readOptionalString(
        value,
        'recipientKeyPackageId',
      ),
      recipientKeyPackagePublicMaterial: _readOptionalString(
        value,
        'recipientKeyPackagePublicMaterial',
      ),
      inviterPeerId: inviterPeerId,
      inviterDeviceId: _readOptionalString(value, 'inviterDeviceId'),
      inviterTransportPeerId: _readOptionalString(
        value,
        'inviterTransportPeerId',
      ),
      inviterDeviceSigningPublicKey: _readOptionalString(
        value,
        'inviterDeviceSigningPublicKey',
      ),
      inviterKeyPackageId: _readOptionalString(value, 'inviterKeyPackageId'),
      inviterPublicKey: inviterPublicKey,
      keyEpoch: keyEpoch,
      groupConfigStateHash: groupConfigStateHash,
      membershipWatermark: membershipWatermark,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      inviterMemberSnapshot: inviterMemberSnapshot,
    );
  }

  bool structurallyMatchesPayload(GroupInvitePayload payload) {
    return inviteId == payload.id &&
        groupId == payload.groupId &&
        keyEpoch == payload.keyEpoch &&
        inviterPeerId == payload.senderPeerId &&
        _optionalEquals(recipientPeerId, payload.recipientPeerId) &&
        _optionalEquals(recipientDeviceId, payload.recipientDeviceId) &&
        _optionalEquals(
          recipientTransportPeerId,
          payload.recipientTransportPeerId,
        ) &&
        _optionalEquals(
          recipientMlKemPublicKey,
          payload.recipientMlKemPublicKey,
        ) &&
        _optionalEquals(recipientKeyPackageId, payload.recipientKeyPackageId) &&
        _optionalEquals(
          recipientKeyPackagePublicMaterial,
          payload.recipientKeyPackagePublicMaterial,
        ) &&
        _optionalEquals(inviterDeviceId, payload.senderDeviceId) &&
        _optionalEquals(
          inviterTransportPeerId,
          payload.senderTransportPeerId,
        ) &&
        _optionalEquals(
          inviterDeviceSigningPublicKey,
          payload.senderDeviceSigningPublicKey,
        ) &&
        _optionalEquals(inviterKeyPackageId, payload.senderKeyPackageId);
  }

  bool isFreshAt(DateTime validationTime) {
    return expiresAt.toUtc().isAfter(validationTime.toUtc());
  }

  bool hasSaneTtlWindow() {
    final maxExpiry = issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl);
    return expiresAt.toUtc().isAfter(issuedAt.toUtc()) &&
        !expiresAt.toUtc().isAfter(maxExpiry);
  }

  bool issueTimeIsCompatibleWith(DateTime payloadTimestamp) {
    final issued = issuedAt.toUtc();
    final payloadTime = payloadTimestamp.toUtc();
    return !issued.isAfter(
          payloadTime.add(groupInviteMembershipFreshnessClockSkew),
        ) &&
        !payloadTime.isAfter(
          issued.add(groupInviteMembershipFreshnessClockSkew),
        );
  }

  static bool _hasValue(String? value) => value != null && value.isNotEmpty;

  static bool _optionalEquals(String? left, String? right) {
    final normalizedLeft = left?.trim();
    final normalizedRight = right?.trim();
    final leftEmpty = normalizedLeft == null || normalizedLeft.isEmpty;
    final rightEmpty = normalizedRight == null || normalizedRight.isEmpty;
    if (leftEmpty || rightEmpty) {
      return leftEmpty && rightEmpty;
    }
    return normalizedLeft == normalizedRight;
  }

  static String? _readRequiredString(Map<dynamic, dynamic> value, String key) {
    final raw = value[key];
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return raw;
  }

  static String? _readOptionalString(Map<dynamic, dynamic> value, String key) {
    final raw = value[key];
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return raw;
  }

  static DateTime? _readRequiredDateTime(
    Map<dynamic, dynamic> value,
    String key,
  ) {
    final raw = value[key];
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Map<String, dynamic>? _readStringKeyedMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(raw);
  }
}

/// Wire-format model for group invite messages sent over P2P.
///
/// Follows the same envelope pattern as `MessagePayload`:
/// ```json
/// {
///   "type": "group_invite",
///   "version": "1",
///   "payload": { "id", "groupId", "groupKey", "keyEpoch", "groupConfig", ... }
/// }
/// ```
class GroupInvitePayload {
  final String id;
  final String groupId;
  final String groupKey;
  final int keyEpoch;
  final Map<String, dynamic> groupConfig;
  final String senderPeerId;
  final String senderUsername;
  final String timestamp;
  final String? recipientPeerId;
  final String? recipientDeviceId;
  final String? recipientTransportPeerId;
  final String? recipientMlKemPublicKey;
  final String? recipientKeyPackageId;
  final String? recipientKeyPackagePublicMaterial;
  final GroupWelcomeKeyPackage? welcomeKeyPackage;
  final String? senderDeviceId;
  final String? senderTransportPeerId;
  final String? senderDeviceSigningPublicKey;
  final String? senderKeyPackageId;
  final GroupInvitePolicy invitePolicy;
  final GroupInviteMembershipFreshnessProof? membershipFreshnessProof;
  final GroupInviteSignature? inviteSignature;

  const GroupInvitePayload({
    required this.id,
    required this.groupId,
    required this.groupKey,
    required this.keyEpoch,
    required this.groupConfig,
    required this.senderPeerId,
    required this.senderUsername,
    required this.timestamp,
    this.recipientPeerId,
    this.recipientDeviceId,
    this.recipientTransportPeerId,
    this.recipientMlKemPublicKey,
    this.recipientKeyPackageId,
    this.recipientKeyPackagePublicMaterial,
    this.welcomeKeyPackage,
    this.senderDeviceId,
    this.senderTransportPeerId,
    this.senderDeviceSigningPublicKey,
    this.senderKeyPackageId,
    required this.invitePolicy,
    this.membershipFreshnessProof,
    this.inviteSignature,
  });

  Map<String, dynamic> _toPayloadMap() {
    return {
      'id': id,
      'groupId': groupId,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
      'groupConfig': groupConfig,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      if (recipientPeerId != null && recipientPeerId!.isNotEmpty)
        'recipientPeerId': recipientPeerId,
      if (recipientDeviceId != null && recipientDeviceId!.isNotEmpty)
        'recipientDeviceId': recipientDeviceId,
      if (recipientTransportPeerId != null &&
          recipientTransportPeerId!.isNotEmpty)
        'recipientTransportPeerId': recipientTransportPeerId,
      if (recipientMlKemPublicKey != null &&
          recipientMlKemPublicKey!.isNotEmpty)
        'recipientMlKemPublicKey': recipientMlKemPublicKey,
      if (recipientKeyPackageId != null && recipientKeyPackageId!.isNotEmpty)
        'recipientKeyPackageId': recipientKeyPackageId,
      if (recipientKeyPackagePublicMaterial != null &&
          recipientKeyPackagePublicMaterial!.isNotEmpty)
        'recipientKeyPackagePublicMaterial': recipientKeyPackagePublicMaterial,
      if (welcomeKeyPackage != null)
        'welcomeKeyPackage': welcomeKeyPackage!.toJson(),
      if (senderDeviceId != null && senderDeviceId!.isNotEmpty)
        'senderDeviceId': senderDeviceId,
      if (senderTransportPeerId != null && senderTransportPeerId!.isNotEmpty)
        'senderTransportPeerId': senderTransportPeerId,
      if (senderDeviceSigningPublicKey != null &&
          senderDeviceSigningPublicKey!.isNotEmpty)
        'senderDeviceSigningPublicKey': senderDeviceSigningPublicKey,
      if (senderKeyPackageId != null && senderKeyPackageId!.isNotEmpty)
        'senderKeyPackageId': senderKeyPackageId,
      'invitePolicy': invitePolicy.toJson(),
      if (membershipFreshnessProof != null)
        groupInviteMembershipFreshnessProofField: membershipFreshnessProof!
            .toJson(),
      if (inviteSignature != null)
        groupInviteSignatureEnvelopeField: inviteSignature!.toJson(),
    };
  }

  Map<String, Object?> _toInviteSignedPayloadMap() {
    return {
      'schemaVersion': groupInviteSignatureSchemaVersion,
      'type': 'group_invite',
      'id': id,
      'groupId': groupId,
      'groupKey': groupKey,
      'keyEpoch': keyEpoch,
      'groupConfig': groupConfig,
      'senderPeerId': senderPeerId,
      'senderUsername': senderUsername,
      'timestamp': timestamp,
      'recipientPeerId': recipientPeerId,
      'recipientDeviceId': recipientDeviceId,
      'recipientTransportPeerId': recipientTransportPeerId,
      'recipientMlKemPublicKey': recipientMlKemPublicKey,
      'recipientKeyPackageId': recipientKeyPackageId,
      'recipientKeyPackagePublicMaterial': recipientKeyPackagePublicMaterial,
      'welcomeKeyPackage': welcomeKeyPackage?.toJson(),
      'senderDeviceId': senderDeviceId,
      'senderTransportPeerId': senderTransportPeerId,
      'senderDeviceSigningPublicKey': senderDeviceSigningPublicKey,
      'senderKeyPackageId': senderKeyPackageId,
      'invitePolicy': invitePolicy.toJson(),
      groupInviteMembershipFreshnessProofField: membershipFreshnessProof
          ?.toJson(),
    };
  }

  String canonicalInviteSignedPayload() {
    return canonicalizeGroupEventLogPayload(_toInviteSignedPayloadMap());
  }

  GroupInvitePayload withInviteSignature({
    required String signature,
    String? signedPayload,
  }) {
    return GroupInvitePayload(
      id: id,
      groupId: groupId,
      groupKey: groupKey,
      keyEpoch: keyEpoch,
      groupConfig: groupConfig,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      timestamp: timestamp,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      welcomeKeyPackage: welcomeKeyPackage,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderDeviceSigningPublicKey: senderDeviceSigningPublicKey,
      senderKeyPackageId: senderKeyPackageId,
      invitePolicy: invitePolicy,
      membershipFreshnessProof: membershipFreshnessProof,
      inviteSignature: GroupInviteSignature(
        signatureAlgorithm: groupInviteSignatureAlgorithm,
        signedPayload: signedPayload ?? canonicalInviteSignedPayload(),
        signature: signature,
      ),
    );
  }

  /// Serializes only the inner payload fields (without envelope wrapper).
  ///
  /// Used as plaintext input for encryption in v2 flow.
  String toInnerJson() {
    return jsonEncode(_toPayloadMap());
  }

  /// Creates a GroupInvitePayload from inner JSON string (decrypted payload).
  ///
  /// Returns null if JSON is invalid or missing required fields.
  static GroupInvitePayload? fromInnerJson(
    String innerJson, {
    DateTime? validationTime,
  }) {
    return parseInnerJsonDetailed(
      innerJson,
      validationTime: validationTime,
    ).payload;
  }

  static GroupInvitePayloadParseResult parseInnerJsonDetailed(
    String innerJson, {
    DateTime? validationTime,
  }) {
    try {
      final payload = jsonDecode(innerJson) as Map<String, dynamic>;
      return _fromPayloadMap(payload, validationTime: validationTime);
    } catch (_) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.malformed,
      );
    }
  }

  /// Serializes to the full v1 JSON envelope string.
  String toJson() {
    final envelope = {
      'type': 'group_invite',
      'version': '1',
      'payload': _toPayloadMap(),
    };
    return jsonEncode(envelope);
  }

  /// Parses a JSON string into a GroupInvitePayload, or returns null if invalid.
  ///
  /// Expects the full v1 envelope: `{ "type": "group_invite", "version": "1", "payload": {...} }`.
  static GroupInvitePayload? fromJson(
    String jsonString, {
    DateTime? validationTime,
  }) {
    return parseJsonDetailed(
      jsonString,
      validationTime: validationTime,
    ).payload;
  }

  static GroupInvitePayloadParseResult parseJsonDetailed(
    String jsonString, {
    DateTime? validationTime,
  }) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      if (json['type'] != 'group_invite') {
        return const GroupInvitePayloadParseResult.failure(
          GroupInvitePayloadParseFailure.malformed,
        );
      }

      final payload = json['payload'] as Map<String, dynamic>?;
      if (payload == null) {
        return const GroupInvitePayloadParseResult.failure(
          GroupInvitePayloadParseFailure.malformed,
        );
      }

      return _fromPayloadMap(payload, validationTime: validationTime);
    } catch (_) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.malformed,
      );
    }
  }

  bool isInvitePolicyValid({DateTime? validationTime}) {
    if (groupKey.trim().isEmpty || keyEpoch <= 0) {
      return false;
    }

    final recipient = recipientPeerId?.trim();
    if (recipient == null || recipient.isEmpty) {
      return false;
    }

    final payloadTimestamp = DateTime.tryParse(timestamp)?.toUtc();
    if (payloadTimestamp == null) {
      return false;
    }

    if (!invitePolicy.expiresAt.isAfter(payloadTimestamp)) {
      return false;
    }
    if (validationTime != null &&
        !invitePolicy.expiresAt.isAfter(validationTime.toUtc())) {
      return false;
    }

    final boundRecipientDeviceId = _effectiveRecipientDeviceId;
    if (boundRecipientDeviceId == null ||
        invitePolicy.allowedDevices.isEmpty ||
        !invitePolicy.allowedDevices.contains(boundRecipientDeviceId)) {
      return false;
    }

    if (invitePolicy.joinMaterialKind != GroupInvitePolicy.inlineGroupKeyKind ||
        invitePolicy.keyEpoch != keyEpoch) {
      return false;
    }

    if (!isWelcomeKeyPackageValid(validationTime: validationTime)) {
      return false;
    }

    final recipientRole = _recipientRoleInConfig(groupConfig, recipient);
    if (recipientRole == null || recipientRole != invitePolicy.assignedRole) {
      return false;
    }

    if (!_isRecipientDeviceBindingValid(recipient)) {
      return false;
    }

    return _isSenderDeviceBindingValid();
  }

  bool isWelcomeKeyPackageValid({DateTime? validationTime}) {
    final welcome = welcomeKeyPackage;
    if (welcome == null) {
      return !_requiresWelcomeKeyPackage;
    }

    final payloadTimestamp = DateTime.tryParse(timestamp)?.toUtc();
    if (payloadTimestamp == null ||
        welcome.issuedAt.isAfter(payloadTimestamp)) {
      return false;
    }
    if (!welcome.matchesInviteAndRecipient(
      inviteId: id,
      groupId: groupId,
      keyEpoch: keyEpoch,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      at: validationTime ?? payloadTimestamp,
    )) {
      return false;
    }
    final policyPackageExpiresAt = invitePolicy.welcomeKeyPackageExpiresAt
        ?.toUtc();
    if (invitePolicy.welcomeKeyPackageId != welcome.packageId ||
        invitePolicy.welcomeKeyPackagePublicMaterialHash !=
            welcome.publicMaterialHash ||
        policyPackageExpiresAt == null ||
        !policyPackageExpiresAt.isAtSameMomentAs(welcome.expiresAt.toUtc())) {
      return false;
    }
    return true;
  }

  bool isInvitePolicyExpiredAt(DateTime now) {
    return !invitePolicy.expiresAt.isAfter(now.toUtc());
  }

  GroupInvitePayloadParseFailure? currentTimeValidationFailure(
    DateTime validationTime,
  ) {
    final validationTimeUtc = validationTime.toUtc();
    if (isInvitePolicyExpiredAt(validationTimeUtc)) {
      return GroupInvitePayloadParseFailure.expired;
    }

    if ((hasWelcomeKeyPackage || requiresWelcomeKeyPackage) &&
        !isWelcomeKeyPackageValid(validationTime: validationTimeUtc)) {
      return GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage;
    }

    return _validateMembershipFreshnessAt(validationTimeUtc);
  }

  static GroupInvitePayloadParseResult _fromPayloadMap(
    Map<String, dynamic> payload, {
    DateTime? validationTime,
  }) {
    final id = payload['id'] as String?;
    final groupId = payload['groupId'] as String?;
    final groupKey = payload['groupKey'] as String?;
    final keyEpoch = payload['keyEpoch'] as int?;
    final groupConfig = payload['groupConfig'] as Map<String, dynamic>?;
    final senderPeerId = payload['senderPeerId'] as String?;
    final senderUsername = payload['senderUsername'] as String?;
    final timestamp = payload['timestamp'] as String?;
    final recipientPeerId = payload['recipientPeerId'] as String?;
    final recipientDeviceId = payload['recipientDeviceId'] as String?;
    final recipientTransportPeerId =
        payload['recipientTransportPeerId'] as String?;
    final recipientMlKemPublicKey =
        payload['recipientMlKemPublicKey'] as String?;
    final recipientKeyPackageId = payload['recipientKeyPackageId'] as String?;
    final recipientKeyPackagePublicMaterial =
        payload['recipientKeyPackagePublicMaterial'] as String?;
    final welcomeKeyPackage = GroupWelcomeKeyPackage.fromJson(
      payload['welcomeKeyPackage'],
    );
    final senderDeviceId = payload['senderDeviceId'] as String?;
    final senderTransportPeerId = payload['senderTransportPeerId'] as String?;
    final senderDeviceSigningPublicKey =
        payload['senderDeviceSigningPublicKey'] as String?;
    final senderKeyPackageId = payload['senderKeyPackageId'] as String?;
    final invitePolicy = GroupInvitePolicy.fromJson(payload['invitePolicy']);
    final membershipFreshnessProof =
        GroupInviteMembershipFreshnessProof.fromJson(
          payload[groupInviteMembershipFreshnessProofField],
        );
    final inviteSignature = GroupInviteSignature.fromJson(
      payload[groupInviteSignatureEnvelopeField],
    );

    if (id == null ||
        groupId == null ||
        groupKey == null ||
        keyEpoch == null ||
        groupConfig == null ||
        senderPeerId == null ||
        senderUsername == null ||
        timestamp == null ||
        invitePolicy == null) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.malformed,
      );
    }

    if (payload.containsKey('welcomeKeyPackage') && welcomeKeyPackage == null) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage,
      );
    }

    final invite = GroupInvitePayload(
      id: id,
      groupId: groupId,
      groupKey: groupKey,
      keyEpoch: keyEpoch,
      groupConfig: groupConfig,
      senderPeerId: senderPeerId,
      senderUsername: senderUsername,
      timestamp: timestamp,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      welcomeKeyPackage: welcomeKeyPackage,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderDeviceSigningPublicKey: senderDeviceSigningPublicKey,
      senderKeyPackageId: senderKeyPackageId,
      invitePolicy: invitePolicy,
      membershipFreshnessProof: membershipFreshnessProof,
      inviteSignature: inviteSignature,
    );

    if (invite._requiresWelcomeKeyPackage && invite.welcomeKeyPackage == null) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage,
      );
    }

    if (invite.welcomeKeyPackage != null &&
        !invite.isWelcomeKeyPackageValid()) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.invalidWelcomeKeyPackage,
      );
    }

    if (!invite.isInvitePolicyValid()) {
      return const GroupInvitePayloadParseResult.failure(
        GroupInvitePayloadParseFailure.invalidPolicy,
      );
    }

    final attestationFailure = invite._validateInviteSignature();
    if (attestationFailure != null) {
      return GroupInvitePayloadParseResult.failure(attestationFailure);
    }

    final currentTimeFailure = validationTime == null
        ? null
        : invite.currentTimeValidationFailure(validationTime);
    if (currentTimeFailure != null) {
      return GroupInvitePayloadParseResult.failure(currentTimeFailure);
    }

    return GroupInvitePayloadParseResult.success(invite);
  }

  GroupInvitePayloadParseFailure? _validateMembershipFreshnessAt(
    DateTime validationTime,
  ) {
    final proof = membershipFreshnessProof;
    if (proof == null || !proof.structurallyMatchesPayload(this)) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }
    if (!proof.hasSaneTtlWindow()) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }

    final payloadTimestamp = DateTime.tryParse(timestamp)?.toUtc();
    if (payloadTimestamp == null ||
        !proof.issueTimeIsCompatibleWith(payloadTimestamp)) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }
    if (!proof.isFreshAt(validationTime)) {
      return GroupInvitePayloadParseFailure.staleMembershipFreshness;
    }
    return null;
  }

  GroupInvitePayloadParseFailure? _validateInviteSignature() {
    final proof = membershipFreshnessProof;
    if (proof == null || !proof.structurallyMatchesPayload(this)) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }

    final inviteSignature = this.inviteSignature;
    if (inviteSignature == null) {
      return GroupInvitePayloadParseFailure.missingSignature;
    }
    if (inviteSignature.signatureAlgorithm != groupInviteSignatureAlgorithm ||
        inviteSignature.signedPayload.trim().isEmpty ||
        inviteSignature.signature.trim().isEmpty) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }

    final decodedSignedPayload = _decodeSignedPayload(
      inviteSignature.signedPayload,
    );
    if (decodedSignedPayload == null) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }

    final canonicalSignedPayload = canonicalizeGroupEventLogPayload(
      decodedSignedPayload,
    );
    if (canonicalSignedPayload != inviteSignature.signedPayload) {
      return GroupInvitePayloadParseFailure.invalidSignature;
    }

    if (canonicalInviteSignedPayload() != inviteSignature.signedPayload) {
      return GroupInvitePayloadParseFailure.invalidSignature;
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

  static String? _recipientRoleInConfig(
    Map<String, dynamic> groupConfig,
    String recipientPeerId,
  ) {
    final members = groupConfig['members'];
    if (members is! List) {
      return null;
    }
    for (final rawMember in members) {
      if (rawMember is! Map) {
        continue;
      }
      final peerId = rawMember['peerId'];
      final role = rawMember['role'];
      if (peerId == recipientPeerId && role is String && role.isNotEmpty) {
        return role;
      }
    }
    return null;
  }

  String? get _effectiveRecipientDeviceId {
    final deviceId = recipientDeviceId?.trim();
    if (deviceId != null && deviceId.isNotEmpty) {
      return deviceId;
    }
    final recipient = recipientPeerId?.trim();
    return recipient == null || recipient.isEmpty ? null : recipient;
  }

  bool get hasDeviceBoundRecipient =>
      recipientDeviceId?.trim().isNotEmpty == true ||
      recipientTransportPeerId?.trim().isNotEmpty == true ||
      recipientMlKemPublicKey?.trim().isNotEmpty == true ||
      recipientKeyPackageId?.trim().isNotEmpty == true ||
      recipientKeyPackagePublicMaterial?.trim().isNotEmpty == true;

  bool get hasWelcomeKeyPackage => welcomeKeyPackage != null;

  bool get requiresWelcomeKeyPackage => _requiresWelcomeKeyPackage;

  bool get _requiresWelcomeKeyPackage =>
      recipientKeyPackageId?.trim().isNotEmpty == true ||
      recipientKeyPackagePublicMaterial?.trim().isNotEmpty == true;

  bool isBoundToRecipientDevice({
    required String ownPeerId,
    String? ownDeviceId,
    String? ownTransportPeerId,
    String? ownMlKemPublicKey,
    String? ownKeyPackageId,
    String? ownKeyPackagePublicMaterial,
  }) {
    final expectedPeerId = ownPeerId.trim();
    if (expectedPeerId.isEmpty || recipientPeerId != expectedPeerId) {
      return false;
    }
    if (!hasDeviceBoundRecipient) {
      return invitePolicy.allowedDevices.contains(expectedPeerId);
    }

    final expectedDeviceId = recipientDeviceId?.trim();
    final localDeviceId = ownDeviceId?.trim();
    if (expectedDeviceId == null ||
        expectedDeviceId.isEmpty ||
        localDeviceId == null ||
        localDeviceId.isEmpty ||
        expectedDeviceId != localDeviceId) {
      return false;
    }

    final deviceFieldsMatch =
        _optionalMatches(recipientTransportPeerId, ownTransportPeerId) &&
        _optionalMatches(recipientMlKemPublicKey, ownMlKemPublicKey) &&
        _optionalMatches(recipientKeyPackageId, ownKeyPackageId) &&
        _optionalMatches(
          recipientKeyPackagePublicMaterial,
          ownKeyPackagePublicMaterial,
        );
    if (!deviceFieldsMatch) {
      return false;
    }

    final welcome = welcomeKeyPackage;
    if (welcome == null) {
      return !_requiresWelcomeKeyPackage;
    }
    return welcome.matchesInviteAndRecipient(
      inviteId: id,
      groupId: groupId,
      keyEpoch: keyEpoch,
      recipientPeerId: expectedPeerId,
      recipientDeviceId: localDeviceId,
      recipientTransportPeerId: ownTransportPeerId,
      recipientMlKemPublicKey: ownMlKemPublicKey,
      recipientKeyPackageId: ownKeyPackageId,
      recipientKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
    );
  }

  bool _isRecipientDeviceBindingValid(String recipientPeerId) {
    if (!hasDeviceBoundRecipient) {
      return true;
    }
    final member = _memberInConfig(groupConfig, recipientPeerId);
    if (member == null) {
      return false;
    }
    final devices = GroupMemberDeviceIdentity.listFromJson(member['devices']);
    if (devices.isEmpty) {
      return false;
    }
    final deviceId = recipientDeviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      return false;
    }
    GroupMemberDeviceIdentity? device;
    for (final candidate in devices) {
      if (candidate.deviceId == deviceId && candidate.isActive) {
        device = candidate;
        break;
      }
    }
    if (device == null) {
      return false;
    }
    return _optionalMatches(recipientTransportPeerId, device.transportPeerId) &&
        _optionalMatches(recipientMlKemPublicKey, device.mlKemPublicKey) &&
        _optionalMatches(recipientKeyPackageId, device.keyPackageId) &&
        _optionalMatches(
          recipientKeyPackagePublicMaterial,
          device.keyPackagePublicMaterial,
        );
  }

  bool _isSenderDeviceBindingValid() {
    final deviceId = senderDeviceId?.trim();
    if (deviceId == null || deviceId.isEmpty) {
      return true;
    }
    final member = _memberInConfig(groupConfig, senderPeerId);
    if (member == null) {
      return false;
    }
    final devices = GroupMemberDeviceIdentity.listFromJson(member['devices']);
    if (devices.isEmpty) {
      return false;
    }
    GroupMemberDeviceIdentity? device;
    for (final candidate in devices) {
      if (candidate.deviceId == deviceId && candidate.isActive) {
        device = candidate;
        break;
      }
    }
    if (device == null) {
      return false;
    }
    return _optionalMatches(senderTransportPeerId, device.transportPeerId) &&
        _optionalMatches(
          senderDeviceSigningPublicKey,
          device.deviceSigningPublicKey,
        ) &&
        _optionalMatches(senderKeyPackageId, device.keyPackageId);
  }

  static Map<String, dynamic>? _memberInConfig(
    Map<String, dynamic> groupConfig,
    String peerId,
  ) {
    final members = groupConfig['members'];
    if (members is! List) {
      return null;
    }
    for (final rawMember in members) {
      if (rawMember is! Map) {
        continue;
      }
      final member = Map<String, dynamic>.from(rawMember);
      if (member['peerId'] == peerId) {
        return member;
      }
    }
    return null;
  }

  static bool _optionalMatches(String? expected, String? actual) {
    final expectedTrimmed = expected?.trim();
    if (expectedTrimmed == null || expectedTrimmed.isEmpty) {
      return true;
    }
    final actualTrimmed = actual?.trim();
    return actualTrimmed != null &&
        actualTrimmed.isNotEmpty &&
        actualTrimmed == expectedTrimmed;
  }

  /// Builds a v2 encrypted envelope JSON string.
  ///
  /// The envelope contains the KEM ciphertext, AES ciphertext, and nonce
  /// alongside the sender's peer ID (cleartext for routing).
  static String buildEncryptedEnvelope({
    required String senderPeerId,
    required String kem,
    required String ciphertext,
    required String nonce,
    String? inviteId,
    String? groupId,
    String? senderUsername,
    String? groupName,
  }) {
    final envelope = {
      'type': 'group_invite',
      'version': '2',
      if (inviteId != null && inviteId.isNotEmpty) 'id': inviteId,
      'senderPeerId': senderPeerId,
      if (senderUsername != null && senderUsername.isNotEmpty)
        'senderUsername': senderUsername,
      if (groupId != null && groupId.isNotEmpty) 'groupId': groupId,
      if (groupName != null && groupName.isNotEmpty) 'groupName': groupName,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
    };
    return jsonEncode(envelope);
  }

  /// Attempts to parse a JSON string as a v2 encrypted envelope.
  ///
  /// Returns the parsed envelope map if it's a v2 group_invite with
  /// encrypted block, or null otherwise.
  static Map<String, dynamic>? parseEncryptedEnvelope(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      if (json['type'] != 'group_invite') return null;
      if (json['version'] != '2') return null;
      final encrypted = json['encrypted'] as Map<String, dynamic>?;
      if (encrypted == null) return null;
      if (encrypted['kem'] == null ||
          encrypted['ciphertext'] == null ||
          encrypted['nonce'] == null) {
        return null;
      }
      return json;
    } catch (_) {
      return null;
    }
  }
}
