import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// Result of creating a group with members.
class CreateGroupWithMembersResult {
  final GroupModel group;
  final int membersAdded;
  final int invitesSent;

  const CreateGroupWithMembersResult({
    required this.group,
    required this.membersAdded,
    required this.invitesSent,
  });
}

/// Creates a new group, adds selected contacts as members, updates config,
/// broadcasts a system message, and sends P2P invites.
///
/// Combines the logic from CreateGroupWired._onCreate and
/// ContactPickerWired._inviteSelected into one testable function.
Future<CreateGroupWithMembersResult> createGroupWithMembers({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required P2PService p2pService,
  required IdentityModel identity,
  required List<ContactModel> selectedContacts,
  required GroupType type,
  String? name,
  String? description,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'CREATE_GROUP_WITH_MEMBERS_BEGIN',
    details: {
      'contactCount': selectedContacts.length,
      'type': type.toValue(),
      'hasName': name != null,
    },
  );

  // 1. Resolve name: use provided or auto-generate from usernames
  final resolvedName = _resolveName(name, selectedContacts);

  // 2. Create the group (saves group + self as admin + key)
  final group = await createGroup(
    bridge: bridge,
    groupRepo: groupRepo,
    name: resolvedName,
    type: type,
    creatorPeerId: identity.peerId,
    creatorPublicKey: identity.publicKey,
    creatorMlKemPublicKey: identity.mlKemPublicKey ?? '',
    description: description,
  );

  // 3. Add each contact as a writer member
  final addedMembers = <GroupMember>[];
  for (final contact in selectedContacts) {
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
      );
      addedMembers.add(newMember);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CREATE_GROUP_WITH_MEMBERS_ADD_MEMBER_ERROR',
        details: {'peerId': contact.peerId, 'error': e.toString()},
      );
    }
  }

  // 4. Build full GroupConfig and update Go topic validator
  final allMembers = await groupRepo.getMembers(group.id);
  final groupConfig = {
    'name': group.name,
    'groupType': group.type.toValue(),
    if (group.description != null) 'description': group.description,
    'members': allMembers
        .map((m) => {
              'peerId': m.peerId,
              'username': m.username,
              'role': m.role.toValue(),
              'publicKey': m.publicKey,
              if (m.mlKemPublicKey != null) 'mlKemPublicKey': m.mlKemPublicKey,
            })
        .toList(),
    'createdBy': group.createdBy,
    'createdAt': group.createdAt.toUtc().toIso8601String(),
  };

  await callGroupUpdateConfig(
    bridge,
    groupId: group.id,
    groupConfig: groupConfig,
  );

  // 5. Broadcast members_added system message
  final sysMessage = jsonEncode({
    '__sys': 'members_added',
    'members': addedMembers
        .map((m) => {
              'peerId': m.peerId,
              'username': m.username,
              'role': m.role.toValue(),
              'publicKey': m.publicKey,
              if (m.mlKemPublicKey != null) 'mlKemPublicKey': m.mlKemPublicKey,
            })
        .toList(),
    'groupConfig': groupConfig,
  });

  await callGroupPublish(
    bridge,
    groupId: group.id,
    text: sysMessage,
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
    senderUsername: identity.username,
  );

  // 6. Send individual P2P invites (continue on individual failures)
  var invitesSent = 0;
  final keyInfo = await groupRepo.getLatestKey(group.id);
  if (keyInfo != null) {
    for (final contact in selectedContacts) {
      if (!addedMembers.any((m) => m.peerId == contact.peerId)) continue;
      try {
        final result = await sendGroupInvite(
          p2pService: p2pService,
          bridge: bridge,
          recipientPeerId: contact.peerId,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          groupId: group.id,
          groupKey: keyInfo.encryptedKey,
          keyEpoch: keyInfo.keyGeneration,
          groupConfig: groupConfig,
        );
        if (result == SendGroupInviteResult.success) {
          invitesSent++;
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CREATE_GROUP_WITH_MEMBERS_INVITE_ERROR',
          details: {'peerId': contact.peerId, 'error': e.toString()},
        );
      }
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CREATE_GROUP_WITH_MEMBERS_SUCCESS',
    details: {
      'groupId': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
      'membersAdded': addedMembers.length,
      'invitesSent': invitesSent,
    },
  );

  return CreateGroupWithMembersResult(
    group: group,
    membersAdded: addedMembers.length,
    invitesSent: invitesSent,
  );
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
