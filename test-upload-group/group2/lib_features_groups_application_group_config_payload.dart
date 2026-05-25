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
  List<GroupMember> members, {
  DateTime? configVersionOverride,
}) {
  final configVersion = _groupConfigVersion(
    group,
    override: configVersionOverride,
  );
  final normalizedMembers = normalizeGroupConfigMembers(members);
  final payload = {
    'name': group.name,
    'groupType': group.type.toValue(),
    'description': group.description,
    'avatarBlobId': group.avatarBlobId,
    'avatarMime': group.avatarMime,
    'metadataUpdatedAt': group.lastMetadataEventAt?.toUtc().toIso8601String(),
    groupConfigVersionField: configVersion,
    'members': normalizedMembers
        .map((member) => member.toConfigJson())
        .toList(),
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

List<GroupMember> normalizeGroupConfigMembers(List<GroupMember> members) {
  final normalized = <GroupMember>[];
  final indexByPeerId = <String, int>{};

  for (final member in members) {
    final peerId = member.peerId.trim();
    if (peerId.isEmpty) {
      continue;
    }
    final candidate = member.copyWith(
      peerId: peerId,
      devices: _normalizeGroupMemberDevices(member.devices),
    );
    if (!hasDeliverableGroupMemberIdentity(candidate)) {
      continue;
    }
    final existingIndex = indexByPeerId[peerId];
    if (existingIndex == null) {
      indexByPeerId[peerId] = normalized.length;
      normalized.add(candidate);
      continue;
    }
    if (_preferGroupMemberCandidate(candidate, normalized[existingIndex])) {
      normalized[existingIndex] = candidate;
    }
  }

  return normalized;
}

Map<String, dynamic> normalizeGroupConfigPayload({
  required String groupId,
  required Map<String, dynamic> groupConfig,
}) {
  final normalized = Map<String, dynamic>.from(groupConfig);
  final members = groupConfig['members'];
  if (members is List) {
    normalized['members'] = normalizeGroupConfigMemberEntries(members);
  }
  if (normalized.containsKey(groupConfigStateHashField)) {
    normalized[groupConfigStateHashField] = buildGroupConfigStateHash(
      groupId: groupId,
      groupConfig: normalized,
    );
  }
  return normalized;
}

List<Map<String, dynamic>> normalizeGroupConfigMemberEntries(
  List<dynamic> members,
) {
  final normalized = <Map<String, dynamic>>[];
  final indexByPeerId = <String, int>{};

  for (final rawMember in members) {
    final member = _stringKeyedDynamicMap(rawMember);
    if (member == null) {
      continue;
    }
    final peerId = (member['peerId'] as String?)?.trim();
    if (peerId == null || peerId.isEmpty) {
      continue;
    }
    final candidate = Map<String, dynamic>.from(member)..['peerId'] = peerId;
    final devices = candidate['devices'];
    if (devices is List) {
      candidate['devices'] = _normalizeGroupConfigDeviceEntries(devices);
    }
    if (!hasDeliverableGroupConfigMemberIdentity(candidate)) {
      continue;
    }

    final existingIndex = indexByPeerId[peerId];
    if (existingIndex == null) {
      indexByPeerId[peerId] = normalized.length;
      normalized.add(candidate);
      continue;
    }
    if (_preferGroupConfigMemberCandidate(
      candidate,
      normalized[existingIndex],
    )) {
      normalized[existingIndex] = candidate;
    }
  }

  return normalized;
}

bool hasDeliverableGroupMemberIdentity(GroupMember member) {
  if (!_hasTrimmedString(member.peerId)) {
    return false;
  }
  if (member.devices.any(_deviceIdentityIsDeliverable)) {
    return true;
  }
  return _hasTrimmedString(member.publicKey);
}

bool hasDeliverableGroupConfigMemberIdentity(Map<String, dynamic> member) {
  if (!_hasTrimmedString(member['peerId'])) {
    return false;
  }
  final devices = member['devices'];
  if (devices is List) {
    for (final rawDevice in devices) {
      final device = _stringKeyedDynamicMap(rawDevice);
      if (device != null && _deviceMapIsDeliverable(device)) {
        return true;
      }
    }
  }
  return _hasTrimmedString(member['publicKey']);
}

List<GroupMemberDeviceIdentity> _normalizeGroupMemberDevices(
  List<GroupMemberDeviceIdentity> devices,
) {
  final normalized = <GroupMemberDeviceIdentity>[];
  final indexByKey = <String, int>{};
  for (final device in devices) {
    final key = _deviceIdentityDedupKey(device);
    if (key == null) {
      continue;
    }
    final existingIndex = indexByKey[key];
    if (existingIndex == null) {
      indexByKey[key] = normalized.length;
      normalized.add(device);
      continue;
    }
    if (_preferDeviceIdentityCandidate(device, normalized[existingIndex])) {
      normalized[existingIndex] = device;
    }
  }
  return normalized;
}

List<Map<String, dynamic>> _normalizeGroupConfigDeviceEntries(
  List<dynamic> devices,
) {
  final normalized = <Map<String, dynamic>>[];
  final indexByKey = <String, int>{};
  for (final rawDevice in devices) {
    final device = _stringKeyedDynamicMap(rawDevice);
    if (device == null) {
      continue;
    }
    final key = _deviceMapDedupKey(device);
    if (key == null) {
      continue;
    }
    final candidate = Map<String, dynamic>.from(device);
    final existingIndex = indexByKey[key];
    if (existingIndex == null) {
      indexByKey[key] = normalized.length;
      normalized.add(candidate);
      continue;
    }
    if (_preferDeviceMapCandidate(candidate, normalized[existingIndex])) {
      normalized[existingIndex] = candidate;
    }
  }
  return normalized;
}

bool _preferGroupMemberCandidate(GroupMember candidate, GroupMember current) {
  final candidateScore = _groupMemberFreshnessScore(candidate);
  final currentScore = _groupMemberFreshnessScore(current);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore;
  }
  final candidateJoinedAt = candidate.joinedAt.toUtc();
  final currentJoinedAt = current.joinedAt.toUtc();
  if (!candidateJoinedAt.isAtSameMomentAs(currentJoinedAt)) {
    return candidateJoinedAt.isAfter(currentJoinedAt);
  }
  return true;
}

bool _preferGroupConfigMemberCandidate(
  Map<String, dynamic> candidate,
  Map<String, dynamic> current,
) {
  final candidateScore = _groupConfigMemberFreshnessScore(candidate);
  final currentScore = _groupConfigMemberFreshnessScore(current);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore;
  }
  return true;
}

int _groupMemberFreshnessScore(GroupMember member) {
  final activeDevices = member.activeDevices;
  return activeDevices.length * 100 +
      activeDevices.where(_deviceIdentityHasKeyPackage).length * 10 +
      (member.publicKey?.trim().isNotEmpty == true ? 2 : 0) +
      (member.mlKemPublicKey?.trim().isNotEmpty == true ? 1 : 0);
}

int _groupConfigMemberFreshnessScore(Map<String, dynamic> member) {
  final devices = member['devices'];
  final deviceMaps = devices is List
      ? devices
            .map(_stringKeyedDynamicMap)
            .whereType<Map<String, dynamic>>()
            .toList(growable: false)
      : const <Map<String, dynamic>>[];
  final activeDevices = deviceMaps.where(_deviceMapIsActive).toList();
  return activeDevices.length * 100 +
      activeDevices.where(_deviceMapHasKeyPackage).length * 10 +
      ((member['publicKey'] as String?)?.trim().isNotEmpty == true ? 2 : 0) +
      ((member['mlKemPublicKey'] as String?)?.trim().isNotEmpty == true
          ? 1
          : 0);
}

bool _preferDeviceIdentityCandidate(
  GroupMemberDeviceIdentity candidate,
  GroupMemberDeviceIdentity current,
) {
  final candidateScore = _deviceIdentityFreshnessScore(candidate);
  final currentScore = _deviceIdentityFreshnessScore(current);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore;
  }
  return true;
}

bool _preferDeviceMapCandidate(
  Map<String, dynamic> candidate,
  Map<String, dynamic> current,
) {
  final candidateScore = _deviceMapFreshnessScore(candidate);
  final currentScore = _deviceMapFreshnessScore(current);
  if (candidateScore != currentScore) {
    return candidateScore > currentScore;
  }
  return true;
}

int _deviceIdentityFreshnessScore(GroupMemberDeviceIdentity device) {
  return (device.isActive ? 100 : 0) +
      (_deviceIdentityHasKeyPackage(device) ? 10 : 0) +
      (device.deviceSigningPublicKey.trim().isNotEmpty ? 2 : 0) +
      (device.mlKemPublicKey?.trim().isNotEmpty == true ? 1 : 0);
}

int _deviceMapFreshnessScore(Map<String, dynamic> device) {
  return (_deviceMapIsActive(device) ? 100 : 0) +
      (_deviceMapHasKeyPackage(device) ? 10 : 0) +
      ((device['deviceSigningPublicKey'] as String?)?.trim().isNotEmpty == true
          ? 2
          : 0) +
      ((device['mlKemPublicKey'] as String?)?.trim().isNotEmpty == true
          ? 1
          : 0);
}

bool _deviceIdentityHasKeyPackage(GroupMemberDeviceIdentity device) {
  return device.keyPackageId?.trim().isNotEmpty == true ||
      device.keyPackagePublicMaterial?.trim().isNotEmpty == true;
}

bool _deviceIdentityIsDeliverable(GroupMemberDeviceIdentity device) {
  return device.isActive &&
      _hasTrimmedString(device.deviceId) &&
      _hasTrimmedString(device.transportPeerId) &&
      _hasTrimmedString(device.deviceSigningPublicKey) &&
      (_hasTrimmedString(device.mlKemPublicKey) ||
          _deviceIdentityHasKeyPackage(device));
}

bool _deviceMapHasKeyPackage(Map<String, dynamic> device) {
  return (device['keyPackageId'] as String?)?.trim().isNotEmpty == true ||
      (device['keyPackagePublicMaterial'] as String?)?.trim().isNotEmpty ==
          true;
}

bool _deviceMapIsDeliverable(Map<String, dynamic> device) {
  return _deviceMapIsActive(device) &&
      _hasTrimmedString(device['deviceId']) &&
      _hasTrimmedString(device['transportPeerId']) &&
      _hasTrimmedString(device['deviceSigningPublicKey']) &&
      (_hasTrimmedString(device['mlKemPublicKey']) ||
          _deviceMapHasKeyPackage(device));
}

bool _deviceMapIsActive(Map<String, dynamic> device) {
  final status = (device['status'] as String?)?.trim();
  final revokedAt = (device['revokedAt'] as String?)?.trim();
  return (status == null || status.isEmpty || status == 'active') &&
      (revokedAt == null || revokedAt.isEmpty);
}

String? _deviceIdentityDedupKey(GroupMemberDeviceIdentity device) {
  final deviceId = device.deviceId.trim();
  if (deviceId.isNotEmpty) {
    return 'device:$deviceId';
  }
  final transportPeerId = device.transportPeerId.trim();
  if (transportPeerId.isNotEmpty) {
    return 'transport:$transportPeerId';
  }
  return null;
}

String? _deviceMapDedupKey(Map<String, dynamic> device) {
  final deviceId = (device['deviceId'] as String?)?.trim();
  if (deviceId != null && deviceId.isNotEmpty) {
    return 'device:$deviceId';
  }
  final transportPeerId = (device['transportPeerId'] as String?)?.trim();
  if (transportPeerId != null && transportPeerId.isNotEmpty) {
    return 'transport:$transportPeerId';
  }
  return null;
}

Map<String, dynamic>? _stringKeyedDynamicMap(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

bool _hasTrimmedString(Object? value) {
  return value is String && value.trim().isNotEmpty;
}

DateTime? parseGroupConfigVersionAt(Map<String, dynamic>? groupConfig) {
  final value = groupConfig?[groupConfigVersionField];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
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

String _groupConfigVersion(GroupModel group, {DateTime? override}) {
  if (override != null) {
    return override.toUtc().toIso8601String();
  }
  final candidates = <DateTime>[
    group.createdAt.toUtc(),
    if (group.lastMetadataEventAt != null) group.lastMetadataEventAt!.toUtc(),
    if (group.lastMembershipEventAt != null)
      group.lastMembershipEventAt!.toUtc(),
  ]..sort((a, b) => a.compareTo(b));
  return candidates.last.toIso8601String();
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
