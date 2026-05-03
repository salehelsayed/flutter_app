import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

enum GroupInviteAuthResult { authorized, unknownSender, invalidPayload }

Future<GroupInviteAuthResult> verifyGroupInviteAttestation({
  required GroupInvitePayload payload,
  required ContactRepository contactRepo,
  required Bridge bridge,
  DateTime? validationTime,
}) async {
  final contact = await contactRepo.getContact(payload.senderPeerId);
  if (contact == null) {
    return GroupInviteAuthResult.unknownSender;
  }
  if (contact.isBlocked || contact.publicKey.trim().isEmpty) {
    return GroupInviteAuthResult.invalidPayload;
  }

  final inviteSignature = payload.inviteSignature;
  if (inviteSignature == null) {
    return GroupInviteAuthResult.invalidPayload;
  }

  final isValid = await callVerifyPayload(
    bridge: bridge,
    publicKey: contact.publicKey,
    data: inviteSignature.signedPayload,
    signature: inviteSignature.signature,
  );
  if (!isValid) {
    return GroupInviteAuthResult.invalidPayload;
  }

  if (!isInviterAuthorizedBySignedSnapshot(
    payload: payload,
    trustedInviterPublicKey: contact.publicKey,
  )) {
    return GroupInviteAuthResult.invalidPayload;
  }

  if (!isMembershipFreshnessProofValid(
    payload: payload,
    trustedInviterPublicKey: contact.publicKey,
    validationTime: validationTime ?? DateTime.now().toUtc(),
  )) {
    return GroupInviteAuthResult.invalidPayload;
  }

  return GroupInviteAuthResult.authorized;
}

class GroupInviteMembershipFreshnessBuildResult {
  final Map<String, dynamic> groupConfig;
  final GroupMember inviterMember;
  final String groupConfigStateHash;
  final String membershipWatermark;

  const GroupInviteMembershipFreshnessBuildResult({
    required this.groupConfig,
    required this.inviterMember,
    required this.groupConfigStateHash,
    required this.membershipWatermark,
  });

  GroupInviteMembershipFreshnessProof buildProof({
    required String inviteId,
    required String groupId,
    required String? recipientPeerId,
    required String? recipientDeviceId,
    required String? recipientTransportPeerId,
    required String? recipientMlKemPublicKey,
    required String? recipientKeyPackageId,
    required String? recipientKeyPackagePublicMaterial,
    required String? inviterDeviceId,
    required String? inviterTransportPeerId,
    required String? inviterDeviceSigningPublicKey,
    required String? inviterKeyPackageId,
    required int keyEpoch,
    required DateTime issuedAt,
  }) {
    final issuedAtUtc = issuedAt.toUtc();
    return GroupInviteMembershipFreshnessProof(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      recipientDeviceId: recipientDeviceId,
      recipientTransportPeerId: recipientTransportPeerId,
      recipientMlKemPublicKey: recipientMlKemPublicKey,
      recipientKeyPackageId: recipientKeyPackageId,
      recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
      inviterPeerId: inviterMember.peerId,
      inviterDeviceId: inviterDeviceId,
      inviterTransportPeerId: inviterTransportPeerId,
      inviterDeviceSigningPublicKey: inviterDeviceSigningPublicKey,
      inviterKeyPackageId: inviterKeyPackageId,
      inviterPublicKey: inviterMember.publicKey ?? '',
      keyEpoch: keyEpoch,
      groupConfigStateHash: groupConfigStateHash,
      membershipWatermark: membershipWatermark,
      issuedAt: issuedAtUtc,
      expiresAt: issuedAtUtc.add(groupInviteMembershipFreshnessTtl),
      inviterMemberSnapshot: inviterMember.toConfigJson(),
    );
  }
}

Future<GroupInviteMembershipFreshnessBuildResult?>
loadCurrentInviteMembershipFreshnessState({
  required GroupRepository groupRepo,
  required String groupId,
  required String inviterPeerId,
  required String trustedInviterPublicKey,
}) async {
  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return null;
  }

  final members = await groupRepo.getMembers(groupId);
  GroupMember? inviterMember;
  for (final member in members) {
    if (member.peerId == inviterPeerId) {
      inviterMember = member;
      break;
    }
  }
  if (inviterMember == null) {
    return null;
  }

  final inviterPublicKey = inviterMember.publicKey?.trim();
  if (inviterPublicKey == null ||
      inviterPublicKey.isEmpty ||
      inviterPublicKey != trustedInviterPublicKey) {
    return null;
  }
  if (!inviterMember.permissions.allows(
    GroupMemberPermission.inviteMembers,
    inviterMember.role,
  )) {
    return null;
  }

  final groupConfig = buildGroupConfigPayload(group, members);
  final stateHash = groupConfig[groupConfigStateHashField];
  if (stateHash is! String || stateHash.trim().isEmpty) {
    return null;
  }

  return GroupInviteMembershipFreshnessBuildResult(
    groupConfig: groupConfig,
    inviterMember: inviterMember,
    groupConfigStateHash: stateHash,
    membershipWatermark:
        group.lastMembershipEventAt?.toUtc().toIso8601String() ?? stateHash,
  );
}

bool isMembershipFreshnessProofValid({
  required GroupInvitePayload payload,
  required String trustedInviterPublicKey,
  required DateTime validationTime,
}) {
  final proof = payload.membershipFreshnessProof;
  if (proof == null || !proof.structurallyMatchesPayload(payload)) {
    return false;
  }
  if (!proof.isFreshAt(validationTime) || !proof.hasSaneTtlWindow()) {
    return false;
  }
  final payloadTimestamp = DateTime.tryParse(payload.timestamp)?.toUtc();
  if (payloadTimestamp == null ||
      !proof.issueTimeIsCompatibleWith(payloadTimestamp)) {
    return false;
  }

  if (!isGroupConfigStateHashValid(
    groupId: payload.groupId,
    groupConfig: payload.groupConfig,
  )) {
    return false;
  }
  final computedStateHash = buildGroupConfigStateHash(
    groupId: payload.groupId,
    groupConfig: payload.groupConfig,
  );
  if (proof.groupConfigStateHash != computedStateHash) {
    return false;
  }

  if (proof.inviterPublicKey != trustedInviterPublicKey ||
      proof.inviterPeerId != payload.senderPeerId) {
    return false;
  }
  return _isAuthorizedMemberSnapshot(
    proof.inviterMemberSnapshot,
    peerId: payload.senderPeerId,
    trustedPublicKey: trustedInviterPublicKey,
  );
}

Future<GroupInviteAuthResult> verifyGroupInviteRevocationAttestation({
  required GroupInviteRevocationPayload payload,
  required ContactRepository contactRepo,
  required Bridge bridge,
}) async {
  final contact = await contactRepo.getContact(payload.revokedByPeerId);
  if (contact == null) {
    return GroupInviteAuthResult.unknownSender;
  }
  if (contact.isBlocked || contact.publicKey.trim().isEmpty) {
    return GroupInviteAuthResult.invalidPayload;
  }

  final revocationSignature = payload.revocationSignature;
  if (revocationSignature == null) {
    return GroupInviteAuthResult.invalidPayload;
  }

  final isValid = await callVerifyPayload(
    bridge: bridge,
    publicKey: contact.publicKey,
    data: revocationSignature.signedPayload,
    signature: revocationSignature.signature,
  );
  if (!isValid) {
    return GroupInviteAuthResult.invalidPayload;
  }

  if (!isRevokerAuthorizedBySignedSnapshot(
    payload: payload,
    trustedRevokerPublicKey: contact.publicKey,
  )) {
    return GroupInviteAuthResult.invalidPayload;
  }

  return GroupInviteAuthResult.authorized;
}

bool isInviterAuthorizedBySignedSnapshot({
  required GroupInvitePayload payload,
  required String trustedInviterPublicKey,
}) {
  final member = _findSenderMember(payload);
  if (member == null) {
    return false;
  }

  final memberPublicKey = member['publicKey'];
  if (memberPublicKey is! String ||
      memberPublicKey.trim().isEmpty ||
      memberPublicKey != trustedInviterPublicKey) {
    return false;
  }

  final roleValue = member['role'];
  if (roleValue is! String || roleValue.trim().isEmpty) {
    return false;
  }

  try {
    final role = MemberRole.fromValue(roleValue);
    return GroupMemberPermissions.fromJson(
      member['permissions'],
    ).allows(GroupMemberPermission.inviteMembers, role);
  } catch (_) {
    return false;
  }
}

bool _isAuthorizedMemberSnapshot(
  Map<String, dynamic> member, {
  required String peerId,
  required String trustedPublicKey,
}) {
  if (member['peerId'] != peerId) {
    return false;
  }

  final memberPublicKey = member['publicKey'];
  if (memberPublicKey is! String ||
      memberPublicKey.trim().isEmpty ||
      memberPublicKey != trustedPublicKey) {
    return false;
  }

  final roleValue = member['role'];
  if (roleValue is! String || roleValue.trim().isEmpty) {
    return false;
  }

  try {
    final role = MemberRole.fromValue(roleValue);
    return GroupMemberPermissions.fromJson(
      member['permissions'],
    ).allows(GroupMemberPermission.inviteMembers, role);
  } catch (_) {
    return false;
  }
}

Map<String, dynamic>? _findSenderMember(GroupInvitePayload payload) {
  return _findMember(payload.groupConfig, payload.senderPeerId);
}

bool isRevokerAuthorizedBySignedSnapshot({
  required GroupInviteRevocationPayload payload,
  required String trustedRevokerPublicKey,
}) {
  final member = payload.revokerAuthorization;
  if (member['peerId'] != payload.revokedByPeerId) {
    return false;
  }

  final memberPublicKey = member['publicKey'];
  if (memberPublicKey is! String ||
      memberPublicKey.trim().isEmpty ||
      memberPublicKey != trustedRevokerPublicKey) {
    return false;
  }

  final roleValue = member['role'];
  if (roleValue is! String || roleValue.trim().isEmpty) {
    return false;
  }

  try {
    final role = MemberRole.fromValue(roleValue);
    return GroupMemberPermissions.fromJson(
      member['permissions'],
    ).allows(GroupMemberPermission.inviteMembers, role);
  } catch (_) {
    return false;
  }
}

Map<String, dynamic>? buildGroupInviteRevokerAuthorizationSnapshot({
  required Map<String, dynamic> groupConfig,
  required String revokedByPeerId,
  required String trustedRevokerPublicKey,
}) {
  final member = _findMember(groupConfig, revokedByPeerId);
  if (member == null) {
    return null;
  }

  final memberPublicKey = member['publicKey'];
  final roleValue = member['role'];
  if (memberPublicKey is! String ||
      memberPublicKey.trim().isEmpty ||
      memberPublicKey != trustedRevokerPublicKey ||
      roleValue is! String ||
      roleValue.trim().isEmpty) {
    return null;
  }

  final snapshot = <String, dynamic>{
    'peerId': revokedByPeerId,
    'publicKey': memberPublicKey,
    'role': roleValue,
  };
  final permissions = member['permissions'];
  if (permissions is Map && permissions.isNotEmpty) {
    snapshot['permissions'] = Map<String, dynamic>.from(permissions);
  }
  return snapshot;
}

Map<String, dynamic>? _findMember(
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
