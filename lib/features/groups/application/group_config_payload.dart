import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

const String groupConfigVersionField = 'configVersion';
const String groupConfigStateHashField = 'stateHash';
const String groupMetadataUpdatedEventType = 'group_metadata_updated';
const String groupMetadataActorEventEnvelopeField = 'actorEvent';
const String groupMetadataActorEventSignedPayloadField = 'signedPayload';
const String groupMetadataActorEventSignatureField = 'signature';
const String groupMetadataActorEventSignatureAlgorithmField =
    'signatureAlgorithm';
const String groupMetadataActorEventSignatureAlgorithm = 'ed25519';
const int groupMetadataActorEventSchemaVersion = 1;

class GroupMetadataActorEventVerificationData {
  const GroupMetadataActorEventVerificationData({
    required this.signedPayload,
    required this.signature,
    required this.actorPublicKey,
  });

  final String signedPayload;
  final String signature;
  final String actorPublicKey;
}

Map<String, dynamic> buildGroupConfigPayload(
  GroupModel group,
  List<GroupMember> members,
) {
  final configVersion = _groupConfigVersion(group);
  final payload = {
    'name': group.name,
    'groupType': group.type.toValue(),
    'description': group.description,
    'avatarBlobId': group.avatarBlobId,
    'avatarMime': group.avatarMime,
    'metadataUpdatedAt': group.lastMetadataEventAt?.toUtc().toIso8601String(),
    groupConfigVersionField: configVersion,
    'members': members.map((member) => member.toConfigJson()).toList(),
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };
  return {
    ...payload,
    groupConfigStateHashField: buildGroupConfigStateHash(
      groupId: group.id,
      groupConfig: payload,
    ),
  };
}

String buildGroupConfigStateHash({
  required String groupId,
  required Map<String, dynamic> groupConfig,
}) {
  final canonical = _canonicalGroupConfigForHash(
    groupId: groupId,
    groupConfig: groupConfig,
  );
  return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
}

bool isGroupConfigStateHashValid({
  required String groupId,
  required Map<String, dynamic> groupConfig,
}) {
  final supplied = groupConfig[groupConfigStateHashField];
  if (supplied == null) {
    return true;
  }
  if (supplied is! String || supplied.isEmpty) {
    return false;
  }
  return supplied ==
      buildGroupConfigStateHash(groupId: groupId, groupConfig: groupConfig);
}

Map<String, Object?> buildGroupMetadataActorEventPayload({
  required String groupId,
  required DateTime updatedAt,
  required String actorPeerId,
  required String actorUsername,
  required String actorPublicKey,
  required Map<String, dynamic> groupConfig,
}) {
  return {
    'schemaVersion': groupMetadataActorEventSchemaVersion,
    'eventType': groupMetadataUpdatedEventType,
    'groupId': groupId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'actor': {
      'peerId': actorPeerId,
      'username': actorUsername,
      'publicKey': actorPublicKey,
    },
    'groupConfigVersion': groupConfig[groupConfigVersionField],
    'groupConfigStateHash': groupConfig[groupConfigStateHashField],
    'groupConfig': groupConfig,
  };
}

String canonicalizeGroupMetadataActorEventPayload(
  Map<String, Object?> payload,
) {
  return canonicalizeGroupEventLogPayload(payload);
}

Map<String, Object?> buildSignedGroupMetadataActorEventEnvelope({
  required String signedPayload,
  required String signature,
}) {
  return {
    groupMetadataActorEventSignedPayloadField: signedPayload,
    groupMetadataActorEventSignatureField: signature,
    groupMetadataActorEventSignatureAlgorithmField:
        groupMetadataActorEventSignatureAlgorithm,
  };
}

GroupMetadataActorEventVerificationData?
extractGroupMetadataActorEventVerificationData({
  required Map<String, dynamic> systemPayload,
  required String groupId,
  required String senderId,
  required String senderUsername,
  required String trustedActorPublicKey,
}) {
  if (trustedActorPublicKey.isEmpty) {
    return null;
  }

  final envelope = _stringKeyedObjectMap(
    systemPayload[groupMetadataActorEventEnvelopeField],
  );
  if (envelope == null) {
    return null;
  }
  if (envelope[groupMetadataActorEventSignatureAlgorithmField] !=
      groupMetadataActorEventSignatureAlgorithm) {
    return null;
  }

  final signedPayload =
      envelope[groupMetadataActorEventSignedPayloadField] as String?;
  final signature = envelope[groupMetadataActorEventSignatureField] as String?;
  if (signedPayload == null ||
      signedPayload.isEmpty ||
      signature == null ||
      signature.isEmpty) {
    return null;
  }

  final decodedSignedPayload = _decodeSignedActorPayload(signedPayload);
  if (decodedSignedPayload == null) {
    return null;
  }
  final canonicalSignedPayload = canonicalizeGroupMetadataActorEventPayload(
    decodedSignedPayload,
  );
  if (canonicalSignedPayload != signedPayload) {
    return null;
  }

  final actor = _stringKeyedObjectMap(decodedSignedPayload['actor']);
  final outerGroupConfig = _stringKeyedObjectMap(systemPayload['groupConfig']);
  final signedGroupConfig = _stringKeyedObjectMap(
    decodedSignedPayload['groupConfig'],
  );
  if (actor == null || outerGroupConfig == null || signedGroupConfig == null) {
    return null;
  }

  if (systemPayload['__sys'] != groupMetadataUpdatedEventType ||
      decodedSignedPayload['schemaVersion'] !=
          groupMetadataActorEventSchemaVersion ||
      decodedSignedPayload['eventType'] != groupMetadataUpdatedEventType ||
      decodedSignedPayload['groupId'] != groupId ||
      decodedSignedPayload['updatedAt'] != systemPayload['updatedAt'] ||
      decodedSignedPayload['groupConfigVersion'] !=
          outerGroupConfig[groupConfigVersionField] ||
      decodedSignedPayload['groupConfigStateHash'] !=
          outerGroupConfig[groupConfigStateHashField] ||
      actor['peerId'] != senderId ||
      actor['username'] != senderUsername ||
      actor['publicKey'] != trustedActorPublicKey) {
    return null;
  }

  if (outerGroupConfig[groupConfigVersionField] is! String ||
      (outerGroupConfig[groupConfigVersionField] as String).isEmpty ||
      outerGroupConfig[groupConfigStateHashField] is! String ||
      (outerGroupConfig[groupConfigStateHashField] as String).isEmpty) {
    return null;
  }

  if (!_canonicalObjectEquals(outerGroupConfig, signedGroupConfig)) {
    return null;
  }

  return GroupMetadataActorEventVerificationData(
    signedPayload: canonicalSignedPayload,
    signature: signature,
    actorPublicKey: trustedActorPublicKey,
  );
}

String _groupConfigVersion(GroupModel group) {
  return (group.lastMetadataEventAt ?? group.createdAt)
      .toUtc()
      .toIso8601String();
}

Map<String, Object?> _canonicalGroupConfigForHash({
  required String groupId,
  required Map<String, dynamic> groupConfig,
}) {
  final members =
      (groupConfig['members'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(_canonicalMemberForHash)
          .toList()
        ..sort((a, b) {
          final aPeerId = a['peerId'] as String? ?? '';
          final bPeerId = b['peerId'] as String? ?? '';
          return aPeerId.compareTo(bPeerId);
        });

  return {
    'groupId': groupId,
    'name': groupConfig['name'] as String?,
    'groupType': groupConfig['groupType'] as String?,
    'description': groupConfig['description'] as String?,
    'avatarBlobId': groupConfig['avatarBlobId'] as String?,
    'avatarMime': groupConfig['avatarMime'] as String?,
    'metadataUpdatedAt': groupConfig['metadataUpdatedAt'] as String?,
    groupConfigVersionField: groupConfig[groupConfigVersionField] as String?,
    'createdBy': groupConfig['createdBy'] as String?,
    'createdAt': groupConfig['createdAt'] as String?,
    'members': members,
  };
}

Map<String, Object?> _canonicalMemberForHash(Map<dynamic, dynamic> member) {
  return {
    'peerId': member['peerId'] as String?,
    'username': member['username'] as String?,
    'role': member['role'] as String?,
    'permissions': _canonicalPermissions(member['permissions']),
    'publicKey': member['publicKey'] as String?,
    'mlKemPublicKey': member['mlKemPublicKey'] as String?,
    'devices': _canonicalDevices(member['devices']),
  };
}

List<Map<String, Object?>>? _canonicalDevices(Object? raw) {
  if (raw is! List) {
    return null;
  }
  final devices =
      raw
          .whereType<Map<dynamic, dynamic>>()
          .map(_canonicalDeviceForHash)
          .toList()
        ..sort((a, b) {
          final aDeviceId = a['deviceId'] as String? ?? '';
          final bDeviceId = b['deviceId'] as String? ?? '';
          return aDeviceId.compareTo(bDeviceId);
        });
  return devices.isEmpty ? null : devices;
}

Map<String, Object?> _canonicalDeviceForHash(Map<dynamic, dynamic> device) {
  return {
    'deviceId': device['deviceId'] as String?,
    'transportPeerId': device['transportPeerId'] as String?,
    'deviceSigningPublicKey': device['deviceSigningPublicKey'] as String?,
    'mlKemPublicKey': device['mlKemPublicKey'] as String?,
    'keyPackageId': device['keyPackageId'] as String?,
    'keyPackagePublicMaterial': device['keyPackagePublicMaterial'] as String?,
    'status': device['status'] as String?,
    'revokedAt': device['revokedAt'] as String?,
  };
}

Map<String, Object?>? _canonicalPermissions(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final permissions = GroupMemberPermissions.fromJson(raw);
  return permissions.hasOverrides ? permissions.toJson() : null;
}

Map<String, Object?>? _decodeSignedActorPayload(String signedPayload) {
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

bool _canonicalObjectEquals(Object? left, Object? right) {
  return canonicalizeGroupEventLogPayload({'value': left}) ==
      canonicalizeGroupEventLogPayload({'value': right});
}
