import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const signedGroupTransitionAuditField = 'signedTransitionAudit';
const signedGroupTransitionAuditSchemaVersion = 1;
const signedGroupTransitionAuditSignatureAlgorithm = 'ed25519';

const _transitionSubjectField = 'transitionSubject';

class SignedGroupTransitionAuditVerification {
  const SignedGroupTransitionAuditVerification({
    required this.sourceEventId,
    required this.eventAt,
    required this.auditHash,
    required this.signedPayload,
  });

  final String sourceEventId;
  final DateTime eventAt;
  final String auditHash;
  final String signedPayload;
}

class SignedGroupTransitionAuditFailure {
  const SignedGroupTransitionAuditFailure(this.reason);

  final String reason;
}

class SignedGroupTransitionAuditCheck {
  const SignedGroupTransitionAuditCheck._({this.verification, this.failure});

  final SignedGroupTransitionAuditVerification? verification;
  final SignedGroupTransitionAuditFailure? failure;

  bool get isValid => verification != null;

  static SignedGroupTransitionAuditCheck valid(
    SignedGroupTransitionAuditVerification verification,
  ) {
    return SignedGroupTransitionAuditCheck._(verification: verification);
  }

  static SignedGroupTransitionAuditCheck invalid(String reason) {
    return SignedGroupTransitionAuditCheck._(
      failure: SignedGroupTransitionAuditFailure(reason),
    );
  }
}

bool requiresSignedGroupTransitionAudit(String? transitionType) {
  return transitionType == 'member_added' ||
      transitionType == 'members_added' ||
      transitionType == 'member_removed' ||
      transitionType == 'member_banned' ||
      transitionType == 'member_unbanned' ||
      transitionType == 'member_role_updated' ||
      transitionType == 'group_message_deleted' ||
      transitionType == 'group_metadata_updated' ||
      transitionType == 'group_dissolved' ||
      transitionType == 'key_rotated' ||
      transitionType == 'group_key_update';
}

Future<Map<String, dynamic>> signGroupSystemTransitionPayload({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String transitionType,
  required String sourceEventId,
  required DateTime eventAt,
  required String actorPeerId,
  required String actorUsername,
  required String actorSigningPublicKey,
  required String actorPrivateKey,
  required Map<String, dynamic> systemPayload,
  String? actorDeviceId,
  String? actorTransportPeerId,
  String? actorKeyPackageId,
  String? preTransitionStateHash,
}) async {
  final audit = await signGroupTransitionAudit(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: groupId,
    transitionType: transitionType,
    sourceEventId: sourceEventId,
    eventAt: eventAt,
    actorPeerId: actorPeerId,
    actorUsername: actorUsername,
    actorSigningPublicKey: actorSigningPublicKey,
    actorPrivateKey: actorPrivateKey,
    actorDeviceId: actorDeviceId,
    actorTransportPeerId: actorTransportPeerId,
    actorKeyPackageId: actorKeyPackageId,
    preTransitionStateHash: preTransitionStateHash,
    transitionSubject: buildGroupSystemTransitionSubject(systemPayload),
  );
  return {...systemPayload, signedGroupTransitionAuditField: audit};
}

Future<Map<String, Object?>> signGroupTransitionAudit({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String transitionType,
  required String sourceEventId,
  required DateTime eventAt,
  required String actorPeerId,
  required String actorUsername,
  required String actorSigningPublicKey,
  required String actorPrivateKey,
  required Map<String, Object?> transitionSubject,
  String? actorDeviceId,
  String? actorTransportPeerId,
  String? actorKeyPackageId,
  String? preTransitionStateHash,
}) async {
  final resolvedPreStateHash =
      preTransitionStateHash ??
      await buildGroupTransitionStateHash(groupRepo, groupId);
  final signedPayload = canonicalizeGroupEventLogPayload({
    'schemaVersion': signedGroupTransitionAuditSchemaVersion,
    'transitionType': transitionType,
    'groupId': groupId,
    'sourceEventId': sourceEventId,
    'eventAt': eventAt.toUtc().toIso8601String(),
    'actor': {
      'peerId': actorPeerId,
      'username': actorUsername,
      'signingPublicKey': actorSigningPublicKey,
      if (actorDeviceId != null && actorDeviceId.isNotEmpty)
        'deviceId': actorDeviceId,
      if (actorTransportPeerId != null && actorTransportPeerId.isNotEmpty)
        'transportPeerId': actorTransportPeerId,
      if (actorKeyPackageId != null && actorKeyPackageId.isNotEmpty)
        'keyPackageId': actorKeyPackageId,
    },
    _transitionSubjectField: transitionSubject,
    'preTransitionStateHash': resolvedPreStateHash,
    'transitionOutputHash': buildGroupTransitionOutputHash(transitionSubject),
  });
  final signResult = await callSignPayload(
    bridge: bridge,
    dataToSign: signedPayload,
    privateKey: actorPrivateKey,
  );
  final signature = signResult['signature'];
  if (signResult['ok'] != true || signature is! String || signature.isEmpty) {
    throw StateError('Failed to sign group transition audit');
  }

  return {
    'schemaVersion': signedGroupTransitionAuditSchemaVersion,
    'transitionType': transitionType,
    'groupId': groupId,
    'sourceEventId': sourceEventId,
    'eventAt': eventAt.toUtc().toIso8601String(),
    'signatureAlgorithm': signedGroupTransitionAuditSignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': signature,
  };
}

Future<SignedGroupTransitionAuditCheck> verifyGroupTransitionAudit({
  required Bridge bridge,
  required Map<String, dynamic> containerPayload,
  required String groupId,
  required String transitionType,
  required String sourceEventId,
  required DateTime eventAt,
  required String actorPeerId,
  required String actorUsername,
  required String actorSigningPublicKey,
  required Map<String, Object?> expectedTransitionSubject,
  String? actorDeviceId,
  String? actorTransportPeerId,
  String? expectedPreTransitionStateHash,
}) async {
  final audit = _stringKeyedObjectMap(
    containerPayload[signedGroupTransitionAuditField],
  );
  if (audit == null) {
    return SignedGroupTransitionAuditCheck.invalid('missing_signed_audit');
  }
  if (audit['signatureAlgorithm'] !=
      signedGroupTransitionAuditSignatureAlgorithm) {
    return SignedGroupTransitionAuditCheck.invalid('signature_invalid');
  }
  final signedPayload = audit['signedPayload'];
  final signature = audit['signature'];
  if (signedPayload is! String ||
      signedPayload.isEmpty ||
      signature is! String ||
      signature.isEmpty) {
    return SignedGroupTransitionAuditCheck.invalid('malformed_signed_audit');
  }

  final decodedPayload = _decodeSignedPayload(signedPayload);
  if (decodedPayload == null ||
      canonicalizeGroupEventLogPayload(decodedPayload) != signedPayload) {
    return SignedGroupTransitionAuditCheck.invalid('payload_mismatch');
  }

  final actor = _stringKeyedObjectMap(decodedPayload['actor']);
  if (actor == null) {
    return SignedGroupTransitionAuditCheck.invalid('payload_mismatch');
  }

  final expectedEventAt = eventAt.toUtc().toIso8601String();
  final expectedOutputHash = buildGroupTransitionOutputHash(
    expectedTransitionSubject,
  );
  if (decodedPayload['schemaVersion'] !=
          signedGroupTransitionAuditSchemaVersion ||
      decodedPayload['transitionType'] != transitionType ||
      decodedPayload['groupId'] != groupId ||
      decodedPayload['sourceEventId'] != sourceEventId ||
      decodedPayload['eventAt'] != expectedEventAt ||
      actor['peerId'] != actorPeerId ||
      actor['username'] != actorUsername ||
      actor['signingPublicKey'] != actorSigningPublicKey ||
      decodedPayload['transitionOutputHash'] != expectedOutputHash ||
      !_canonicalEquals(
        decodedPayload[_transitionSubjectField],
        expectedTransitionSubject,
      )) {
    return SignedGroupTransitionAuditCheck.invalid('payload_mismatch');
  }

  if (actorDeviceId != null &&
      actorDeviceId.isNotEmpty &&
      actor['deviceId'] != actorDeviceId) {
    return SignedGroupTransitionAuditCheck.invalid('device_mismatch');
  }
  if (actorTransportPeerId != null &&
      actorTransportPeerId.isNotEmpty &&
      actor['transportPeerId'] != actorTransportPeerId) {
    return SignedGroupTransitionAuditCheck.invalid('transport_mismatch');
  }
  if (expectedPreTransitionStateHash != null &&
      expectedPreTransitionStateHash.isNotEmpty &&
      decodedPayload['preTransitionStateHash'] !=
          expectedPreTransitionStateHash) {
    return SignedGroupTransitionAuditCheck.invalid(
      'previous_transition_hash_mismatch',
    );
  }

  final validSignature = await callVerifyPayload(
    bridge: bridge,
    publicKey: actorSigningPublicKey,
    data: signedPayload,
    signature: signature,
  );
  if (!validSignature) {
    return SignedGroupTransitionAuditCheck.invalid('signature_invalid');
  }

  return SignedGroupTransitionAuditCheck.valid(
    SignedGroupTransitionAuditVerification(
      sourceEventId: sourceEventId,
      eventAt: eventAt.toUtc(),
      auditHash: signedGroupTransitionAuditHash(audit),
      signedPayload: signedPayload,
    ),
  );
}

String? signedGroupTransitionAuditSourceEventId(
  Map<String, dynamic> containerPayload,
) {
  final audit = _stringKeyedObjectMap(
    containerPayload[signedGroupTransitionAuditField],
  );
  final sourceEventId = audit?['sourceEventId'];
  return sourceEventId is String && sourceEventId.isNotEmpty
      ? sourceEventId
      : null;
}

String? signedGroupTransitionAuditHashFromPayload(
  Map<String, dynamic> containerPayload,
) {
  final audit = _stringKeyedObjectMap(
    containerPayload[signedGroupTransitionAuditField],
  );
  return audit == null ? null : signedGroupTransitionAuditHash(audit);
}

String signedGroupTransitionAuditHash(Map<String, Object?> audit) {
  final signedPayload = audit['signedPayload'];
  if (signedPayload is String && signedPayload.isNotEmpty) {
    return sha256.convert(utf8.encode(signedPayload)).toString();
  }
  return sha256
      .convert(utf8.encode(canonicalizeGroupEventLogPayload(audit)))
      .toString();
}

Map<String, Object?> buildGroupSystemTransitionSubject(
  Map<String, dynamic> systemPayload,
) {
  final transitionType = systemPayload['__sys'];
  switch (transitionType) {
    case 'member_added':
      return {
        'member': _canonicalMember(systemPayload['member']),
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
      };
    case 'members_added':
      return {
        'members': _canonicalMembers(systemPayload['members']),
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
      };
    case 'member_removed':
      return {
        'member': _canonicalMember(systemPayload['member']),
        'removedAt': systemPayload['removedAt'] as String?,
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
      };
    case 'member_banned':
      return {
        'targetPeerId': _canonicalTargetPeerId(systemPayload),
        'bannedAt':
            systemPayload['bannedAt'] as String? ??
            systemPayload['eventAt'] as String?,
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
      };
    case 'member_unbanned':
      return {
        'targetPeerId': _canonicalTargetPeerId(systemPayload),
        'unbannedAt':
            systemPayload['unbannedAt'] as String? ??
            systemPayload['eventAt'] as String?,
      };
    case 'member_role_updated':
      return {
        'member': _canonicalMember(systemPayload['member']),
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
      };
    case 'group_message_deleted':
      return {
        'targetMessageId':
            systemPayload['targetMessageId'] as String? ??
            systemPayload['deletedMessageId'] as String? ??
            systemPayload['messageId'] as String?,
        'deletedAt':
            systemPayload['deletedAt'] as String? ??
            systemPayload['eventAt'] as String?,
      };
    case 'group_metadata_updated':
      return {
        'updatedAt': systemPayload['updatedAt'] as String?,
        'groupConfigHash': _groupConfigHash(systemPayload['groupConfig']),
        'actorEventHash': _hashValue(systemPayload['actorEvent']),
      };
    case 'group_dissolved':
      return {
        'dissolvedAt': systemPayload['dissolvedAt'] as String?,
        'dissolvedBy': systemPayload['dissolvedBy'] as String?,
      };
    case 'key_rotated':
      return {'newKeyEpoch': systemPayload['newKeyEpoch']};
    default:
      return {'type': transitionType};
  }
}

Map<String, Object?> buildGroupKeyUpdateTransitionSubject({
  required String groupId,
  required String sourcePeerId,
  required int keyGeneration,
  required String encryptedKey,
  String? sourceDeviceId,
  String? sourceTransportPeerId,
  String? recipientPeerId,
  String? recipientDeviceId,
  String? recipientTransportPeerId,
  String? recipientKeyPackageId,
}) {
  return {
    'groupId': groupId,
    'sourcePeerId': sourcePeerId,
    if (sourceDeviceId != null && sourceDeviceId.isNotEmpty)
      'sourceDeviceId': sourceDeviceId,
    if (sourceTransportPeerId != null && sourceTransportPeerId.isNotEmpty)
      'sourceTransportPeerId': sourceTransportPeerId,
    if (recipientPeerId != null && recipientPeerId.isNotEmpty)
      'recipientPeerId': recipientPeerId,
    if (recipientDeviceId != null && recipientDeviceId.isNotEmpty)
      'recipientDeviceId': recipientDeviceId,
    if (recipientTransportPeerId != null && recipientTransportPeerId.isNotEmpty)
      'recipientTransportPeerId': recipientTransportPeerId,
    if (recipientKeyPackageId != null && recipientKeyPackageId.isNotEmpty)
      'recipientKeyPackageId': recipientKeyPackageId,
    'keyGeneration': keyGeneration,
    'encryptedKeyHash': sha256.convert(utf8.encode(encryptedKey)).toString(),
  };
}

String buildGroupTransitionOutputHash(Map<String, Object?> transitionSubject) {
  return sha256
      .convert(utf8.encode(canonicalizeGroupEventLogPayload(transitionSubject)))
      .toString();
}

Future<String> buildGroupTransitionStateHash(
  GroupRepository groupRepo,
  String groupId,
) async {
  final group = await groupRepo.getGroup(groupId);
  final members = await groupRepo.getMembers(groupId);
  members.sort((a, b) => a.peerId.compareTo(b.peerId));
  final latestKey = await groupRepo.getLatestKey(groupId);
  return sha256
      .convert(
        utf8.encode(
          canonicalizeGroupEventLogPayload({
            'groupId': groupId,
            'group': {
              'name': group?.name,
              'type': group?.type.toValue(),
              'createdBy': group?.createdBy,
              'createdAt': group?.createdAt.toUtc().toIso8601String(),
              'isDissolved': group?.isDissolved,
              'dissolvedAt': group?.dissolvedAt?.toUtc().toIso8601String(),
              'dissolvedBy': group?.dissolvedBy,
              'lastMembershipEventAt': group?.lastMembershipEventAt
                  ?.toUtc()
                  .toIso8601String(),
              'lastMetadataEventAt': group?.lastMetadataEventAt
                  ?.toUtc()
                  .toIso8601String(),
            },
            'members': members.map((member) => member.toConfigJson()).toList(),
            'latestKeyGeneration': latestKey?.keyGeneration,
          }),
        ),
      )
      .toString();
}

Map<String, Object?>? _decodeSignedPayload(String signedPayload) {
  try {
    return _stringKeyedObjectMap(jsonDecode(signedPayload));
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _stringKeyedObjectMap(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

List<Map<String, Object?>> _canonicalMembers(Object? raw) {
  if (raw is! List) {
    return const <Map<String, Object?>>[];
  }
  final members = raw.map(_canonicalMember).toList(growable: false);
  members.sort((a, b) {
    final aPeerId = a['peerId'] as String? ?? '';
    final bPeerId = b['peerId'] as String? ?? '';
    return aPeerId.compareTo(bPeerId);
  });
  return members;
}

Map<String, Object?> _canonicalMember(Object? raw) {
  final member = raw is Map ? raw : const <String, Object?>{};
  return {
    'peerId': member['peerId'] as String?,
    'username': member['username'] as String?,
    'role': member['role'] as String?,
    'permissions': member['permissions'],
    'publicKey': member['publicKey'] as String?,
    'mlKemPublicKey': member['mlKemPublicKey'] as String?,
    'devices': member['devices'],
  };
}

String? _canonicalTargetPeerId(Map<String, dynamic> systemPayload) {
  final member = systemPayload['member'];
  final memberMap = member is Map ? member : const <String, Object?>{};
  return systemPayload['targetPeerId'] as String? ??
      systemPayload['memberPeerId'] as String? ??
      systemPayload['bannedPeerId'] as String? ??
      systemPayload['unbannedPeerId'] as String? ??
      memberMap['peerId'] as String?;
}

String? _groupConfigHash(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final stateHash = raw['stateHash'];
  if (stateHash is String && stateHash.isNotEmpty) {
    return stateHash;
  }
  return _hashValue(raw);
}

String? _hashValue(Object? value) {
  if (value == null) {
    return null;
  }
  return sha256
      .convert(utf8.encode(canonicalizeGroupEventLogPayload({'value': value})))
      .toString();
}

bool _canonicalEquals(Object? left, Object? right) {
  return canonicalizeGroupEventLogPayload({'value': left}) ==
      canonicalizeGroupEventLogPayload({'value': right});
}
