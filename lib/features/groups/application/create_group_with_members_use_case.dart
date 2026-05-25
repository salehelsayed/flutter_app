import 'dart:convert';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_sender_device_binding.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

class CreateGroupMemberAddFailure {
  final String peerId;
  final String username;

  const CreateGroupMemberAddFailure({
    required this.peerId,
    required this.username,
  });

  String get displayName {
    final trimmed = username.trim();
    return trimmed.isNotEmpty ? trimmed : peerId;
  }
}

/// Result of creating a group with members.
class CreateGroupWithMembersResult {
  final GroupModel group;
  final int membersAdded;
  final GroupInviteBatchResult? inviteBatchResult;
  final List<CreateGroupMemberAddFailure> _addMemberFailures;
  final bool inviteDeliverySkippedMissingKey;
  final bool membershipSyncRolledBack;
  final bool membersAddedPublishFailed;

  const CreateGroupWithMembersResult({
    required this.group,
    required this.membersAdded,
    this.inviteBatchResult,
    List<CreateGroupMemberAddFailure> addMemberFailures = const [],
    this.inviteDeliverySkippedMissingKey = false,
    this.membershipSyncRolledBack = false,
    this.membersAddedPublishFailed = false,
  }) : _addMemberFailures = addMemberFailures;

  int get invitesSent => inviteBatchResult?.successCount ?? 0;

  List<CreateGroupMemberAddFailure> get addMemberFailures =>
      List.unmodifiable(_addMemberFailures);

  bool get hasWarnings =>
      _addMemberFailures.isNotEmpty ||
      inviteDeliverySkippedMissingKey ||
      membershipSyncRolledBack ||
      membersAddedPublishFailed ||
      (inviteBatchResult?.hasFailures ?? false);

  String? buildCreateWarningMessage() {
    final issues = <String>[];
    if (_addMemberFailures.isNotEmpty) {
      issues.add(
        'selected members were not added: ${_describeAddMemberFailures()}',
      );
    }
    if (membershipSyncRolledBack) {
      issues.add(
        'no one else was added because membership setup could not be synced',
      );
    }
    if (inviteDeliverySkippedMissingKey) {
      issues.add(
        'invites were not sent because the group is missing its latest key',
      );
    }
    if (inviteBatchResult?.hasFailures ?? false) {
      issues.add('invite issues: ${inviteBatchResult!.describeFailures()}');
    }
    if (membersAddedPublishFailed) {
      issues.add('the add-members event could not be published');
    }
    if (issues.isEmpty) {
      return null;
    }
    return 'Group created, but ${issues.join('; ')}.';
  }

  String _describeAddMemberFailures({int limit = 3}) {
    final labels = _addMemberFailures
        .take(limit)
        .map((failure) => failure.displayName)
        .toList(growable: false);
    final hiddenCount = _addMemberFailures.length - labels.length;
    if (hiddenCount > 0) {
      labels.add('+$hiddenCount more');
    }
    return labels.join(', ');
  }
}

/// Creates a new group, adds selected contacts as members, updates config,
/// broadcasts a system message, and sends P2P invites.
///
/// Combines the routed create-group picker flow and invite fanout into one
/// testable function.
Future<CreateGroupWithMembersResult> createGroupWithMembers({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required P2PService p2pService,
  required IdentityModel identity,
  required List<ContactModel> selectedContacts,
  required GroupType type,
  String? name,
  String? description,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  AppendGroupEventLogEntry? appendGroupEventLogEntry,
}) async {
  final uniqueContacts = _dedupeContactsByPeerId(selectedContacts);
  emitFlowEvent(
    layer: 'FL',
    event: 'CREATE_GROUP_WITH_MEMBERS_BEGIN',
    details: {
      'contactCount': uniqueContacts.length,
      if (uniqueContacts.length != selectedContacts.length)
        'duplicateContactCount':
            selectedContacts.length - uniqueContacts.length,
      'type': type.toValue(),
      'hasName': name != null,
    },
  );

  // 1. Resolve name: use provided or auto-generate from usernames
  final resolvedName = _resolveName(name, uniqueContacts);

  ensureWithinGroupMembershipLimit(
    currentMemberCount: 1,
    requestedAdditionalMembers: uniqueContacts.length,
  );

  final creatorMlKemPublicKey = identity.mlKemPublicKey;
  if (creatorMlKemPublicKey == null || creatorMlKemPublicKey.trim().isEmpty) {
    throw ArgumentError('Creator ML-KEM public key must not be empty');
  }

  // 2. Create the group (saves group + self as admin + key)
  final group = await createGroup(
    bridge: bridge,
    groupRepo: groupRepo,
    name: resolvedName,
    type: type,
    creatorPeerId: identity.peerId,
    creatorPublicKey: identity.publicKey,
    creatorMlKemPublicKey: creatorMlKemPublicKey,
    creatorUsername: identity.username,
    creatorPrivateKey: identity.privateKey,
    appendGroupEventLogEntry: appendGroupEventLogEntry,
    description: description,
  );
  final currentSenderDeviceId = p2pService.currentState.peerId?.trim();
  if (currentSenderDeviceId != null && currentSenderDeviceId.isNotEmpty) {
    final creatorMember = await groupRepo.getMember(group.id, identity.peerId);
    if (creatorMember != null &&
        creatorMember.findDeviceById(currentSenderDeviceId) == null) {
      await groupRepo.saveMember(
        creatorMember.copyWith(
          devices: [
            ...creatorMember.devices,
            GroupMemberDeviceIdentity(
              deviceId: currentSenderDeviceId,
              transportPeerId: currentSenderDeviceId,
              deviceSigningPublicKey: identity.publicKey,
              mlKemPublicKey: identity.mlKemPublicKey,
            ),
          ],
        ),
      );
    }
  }
  final preTransitionStateHash = await buildGroupTransitionStateHash(
    groupRepo,
    group.id,
  );

  // 3. Add each contact as a writer member
  final addedMembers = <GroupMember>[];
  final addMemberFailures = <CreateGroupMemberAddFailure>[];
  for (final contact in uniqueContacts) {
    try {
      final newMember = GroupMember(
        groupId: group.id,
        peerId: contact.peerId,
        username: contact.username,
        role: MemberRole.writer,
        publicKey: contact.publicKey,
        mlKemPublicKey: contact.mlKemPublicKey,
        joinedAt: DateTime.now().toUtc(),
      );
      await addGroupMember(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: group.id,
        newMember: newMember,
        selfPeerId: identity.peerId,
        syncBridgeConfig: false,
      );
      addedMembers.add(newMember);
    } catch (e) {
      addMemberFailures.add(
        CreateGroupMemberAddFailure(
          peerId: contact.peerId,
          username: contact.username,
        ),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'CREATE_GROUP_WITH_MEMBERS_ADD_MEMBER_ERROR',
        details: {'peerId': contact.peerId, 'error': e.toString()},
      );
    }
  }

  // 4. Build full GroupConfig and update Go topic validator
  final allMembers = await groupRepo.getMembers(group.id);
  final membershipEventAt = DateTime.now().toUtc();
  final groupForConfig = group.copyWith(
    lastMembershipEventAt: membershipEventAt,
  );
  final groupConfig = buildGroupConfigPayload(
    groupForConfig,
    allMembers,
    configVersionOverride: membershipEventAt,
  );
  final senderBinding = await resolveGroupSenderDeviceBinding(
    groupRepo: groupRepo,
    groupId: group.id,
    senderPeerId: identity.peerId,
    preferredDeviceId:
        currentSenderDeviceId == null || currentSenderDeviceId.isEmpty
        ? null
        : currentSenderDeviceId,
    preferredTransportPeerId:
        currentSenderDeviceId == null || currentSenderDeviceId.isEmpty
        ? null
        : currentSenderDeviceId,
    senderPublicKey: identity.publicKey,
  );

  try {
    await callGroupUpdateConfig(
      bridge,
      groupId: group.id,
      groupConfig: groupConfig,
    );
    await recordGroupMembershipEventWatermark(
      groupRepo: groupRepo,
      groupId: group.id,
      eventAt: membershipEventAt,
    );
  } catch (e) {
    for (final member in addedMembers) {
      await groupRepo.removeMember(group.id, member.peerId);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'CREATE_GROUP_WITH_MEMBERS_CONFIG_SYNC_ROLLED_BACK',
      details: {'groupId': group.id, 'error': e.toString()},
    );
    return CreateGroupWithMembersResult(
      group: group,
      membersAdded: 0,
      addMemberFailures: addMemberFailures,
      membershipSyncRolledBack: true,
    );
  }

  // 5. Broadcast members_added system message
  final publishedAt = membershipEventAt;
  final sourceEventId =
      'members_added:${group.id}:${identity.peerId}:${publishedAt.microsecondsSinceEpoch}';
  final sysPayload = await signGroupSystemTransitionPayload(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    transitionType: 'members_added',
    sourceEventId: sourceEventId,
    eventAt: publishedAt,
    actorPeerId: identity.peerId,
    actorUsername: identity.username,
    actorSigningPublicKey: identity.publicKey,
    actorPrivateKey: identity.privateKey,
    actorDeviceId: senderBinding.deviceId,
    actorTransportPeerId: senderBinding.transportPeerId,
    actorKeyPackageId: senderBinding.keyPackageId,
    preTransitionStateHash: preTransitionStateHash,
    systemPayload: {
      '__sys': 'members_added',
      'members': addedMembers.map((m) => m.toConfigJson()).toList(),
      'groupConfig': groupConfig,
    },
  );
  final sysMessage = jsonEncode(sysPayload);

  var membersAddedPublishFailed = false;
  try {
    final publishResult = await callGroupPublish(
      bridge,
      groupId: group.id,
      text: sysMessage,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      senderDeviceId: senderBinding.deviceId,
      senderTransportPeerId: senderBinding.transportPeerId,
      senderDevicePublicKey: senderBinding.devicePublicKey,
      senderKeyPackageId: senderBinding.keyPackageId,
      messageId: sourceEventId,
    );
    if (publishResult['ok'] != true) {
      membersAddedPublishFailed = true;
    }
  } catch (e) {
    membersAddedPublishFailed = true;
  }
  if (membersAddedPublishFailed) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CREATE_GROUP_WITH_MEMBERS_PUBLISH_WARNING',
      details: {'groupId': group.id},
    );
  }

  // 6. Send individual P2P invites in parallel
  GroupInviteBatchResult? inviteBatchResult;
  var inviteDeliverySkippedMissingKey = false;
  final keyInfo = await groupRepo.getLatestKey(group.id);
  if (keyInfo != null) {
    final recipients = uniqueContacts
        .where((c) => addedMembers.any((m) => m.peerId == c.peerId))
        .map(
          (c) => (
            peerId: c.peerId,
            username: c.username,
            mlKemPublicKey: c.mlKemPublicKey,
          ),
        )
        .toList();

    inviteBatchResult = await sendGroupInvitesInParallel(
      p2pService: p2pService,
      bridge: bridge,
      groupRepo: groupRepo,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      senderDeviceId: senderBinding.deviceId,
      groupId: group.id,
      groupKey: keyInfo.encryptedKey,
      keyEpoch: keyInfo.keyGeneration,
      groupConfig: groupConfig,
      recipients: recipients,
    );
    await recordGroupInviteDeliveryBatch(
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      groupId: group.id,
      attempts: inviteBatchResult.attempts,
    );
  } else if (addedMembers.isNotEmpty) {
    inviteDeliverySkippedMissingKey = true;
    await recordMissingGroupKeyInviteDeliveryAttempts(
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      groupId: group.id,
      members: addedMembers,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'CREATE_GROUP_WITH_MEMBERS_MISSING_GROUP_KEY',
      details: {'groupId': group.id},
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CREATE_GROUP_WITH_MEMBERS_SUCCESS',
    details: {
      'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
      'membersAdded': addedMembers.length,
      'invitesSent': inviteBatchResult?.successCount ?? 0,
    },
  );

  final updatedGroup = await groupRepo.getGroup(group.id) ?? groupForConfig;

  return CreateGroupWithMembersResult(
    group: updatedGroup,
    membersAdded: addedMembers.length,
    inviteBatchResult: inviteBatchResult,
    addMemberFailures: addMemberFailures,
    inviteDeliverySkippedMissingKey: inviteDeliverySkippedMissingKey,
    membersAddedPublishFailed: membersAddedPublishFailed,
  );
}

List<ContactModel> _dedupeContactsByPeerId(List<ContactModel> contacts) {
  final byPeerId = <String, ContactModel>{};
  for (final contact in contacts) {
    final key = contact.peerId.trim();
    byPeerId.putIfAbsent(key, () => contact);
  }
  return byPeerId.values.toList(growable: false);
}

/// Resolves the group name: uses provided name if non-null/non-empty,
/// otherwise auto-generates from contact usernames.
String _resolveName(String? name, List<ContactModel> contacts) {
  if (name != null && name.trim().isNotEmpty) return name.trim();

  if (contacts.length <= 2) {
    return contacts.map((c) => c.username).join(', ');
  }

  final firstTwo = contacts.take(2).map((c) => c.username).join(', ');
  return '$firstTwo +${contacts.length - 2}';
}
