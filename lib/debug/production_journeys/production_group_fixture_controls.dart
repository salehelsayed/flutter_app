import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';

import 'production_journey_controller.dart';
import 'production_group_catalog_controls.dart';
import 'production_group_recovery_hold.dart';

String productionFixtureGroupName(
  ProductionJourneyController controller,
  GroupType type,
) => controller.invocation.scenarioId == notificationSoundJourney
    ? 'Notification Sound ${type.name} ${controller.invocation.runId}'
    : controller.invocation.scenarioId == groupInviteJourney
    ? 'Invite Reliability ${controller.invocation.runId}'
    : 'Foreground Push ${controller.invocation.runId}';

/// Fixture setup and read-only observations bound to production instances.
/// Sending messages and ordinary navigation belong to the UI flow. The only
/// fault controls here are leaving a live topic and the exact S3 drain failure.
void bindProductionGroupFixtureControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
}) {
  String string(Map<String, Object?> values, String name) {
    final value = values[name];
    if (value is! String || value.isEmpty) {
      throw FormatException('missing $name');
    }
    return value;
  }

  final ownedGroups = <String>{};
  final recoveryHold = ProductionGroupRecoveryHold(gate: groupRecoveryGate);
  controller.bindDisposer(recoveryHold.dispose);
  String? liveGapGroup;
  void requireOwned(String groupId) {
    if (!ownedGroups.contains(groupId)) {
      throw StateError('group is not fixture-owned');
    }
  }

  controller.bindAction('identity', (_) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity is absent');
    return {
      'peerId': identity.peerId,
      'publicKey': identity.publicKey,
      'mlKemPublicKey': identity.mlKemPublicKey,
      'username': identity.username,
      'online': {
        BadgeReadinessState.online,
        BadgeReadinessState.onlineDotted,
        BadgeReadinessState.onlineDirect,
      }.contains(p2pService.currentState.badgeReadinessState),
    };
  });
  controller.bindAction('prepare_contact', (args) async {
    await contactRepository.addContact(
      ContactModel(
        peerId: string(args, 'peerId'),
        publicKey: string(args, 'publicKey'),
        username: string(args, 'username'),
        rendezvous: '/mknoon/production-journey/${controller.invocation.runId}',
        signature: 'fixture-${controller.invocation.runId}',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: string(args, 'mlKemPublicKey'),
      ),
    );
    return {'contactPrepared': true};
  });
  if (productionGroupCatalogJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    bindProductionGroupCatalogObservations(
      controller: controller,
      p2pService: p2pService,
      identityRepository: identityRepository,
      groupRepository: groupRepository,
      messageRepository: groupMessageRepository,
      deliveryRepository: inviteDeliveryRepository,
    );
    // The catalog's create/join/send operations must remain real UI actions.
    // Do not expose fixture import, forced join or protocol send shortcuts.
    return;
  }
  controller.bindAction('prepare_group', (args) async {
    if (controller.invocation.scenarioId == groupInviteJourney) {
      throw StateError(
        'invitation journey requires production UI group creation',
      );
    }
    final sound = controller.invocation.scenarioId == notificationSoundJourney;
    final type = switch (args['groupType']) {
      null || 'chat' => GroupType.chat,
      'announcement' when sound => GroupType.announcement,
      _ => throw StateError('unsupported fixture group type'),
    };
    final identity = await identityRepository.loadIdentity();
    final contact = await contactRepository.getContact(string(args, 'peerId'));
    if (identity == null || contact == null) {
      throw StateError('fixture identity missing');
    }
    final result = await createGroupWithMembers(
      bridge: bridge,
      groupRepo: groupRepository,
      p2pService: p2pService,
      identity: identity,
      selectedContacts: [contact],
      type: type,
      name: productionFixtureGroupName(controller, type),
      inviteDeliveryAttemptRepo: inviteDeliveryRepository,
    );
    final group = result.group;
    ownedGroups.add(group.id);
    final key = await groupRepository.getLatestKey(group.id);
    final members = await groupRepository.getMembers(group.id);
    if (key == null) throw StateError('fixture group key missing');
    return {
      'group': group.toMap(),
      'key': key.toMap(),
      'members': members.map((member) => member.toMap()).toList(),
      'groupConfig': buildGroupConfigPayload(group, members),
    };
  });
  controller.bindAction('import_group', (args) async {
    final group = GroupModel.fromMap(
      Map<String, dynamic>.from(args['group'] as Map),
    );
    if (group.name != productionFixtureGroupName(controller, group.type) ||
        !{GroupType.chat, GroupType.announcement}.contains(group.type)) {
      throw StateError('fixture group belongs to another invocation');
    }
    final identity = await identityRepository.loadIdentity();
    final key = GroupKeyInfo.fromMap(
      Map<String, dynamic>.from(args['key'] as Map),
    );
    final members = (args['members'] as List)
        .map(
          (member) =>
              GroupMember.fromMap(Map<String, dynamic>.from(member as Map)),
        )
        .toList();
    final self = members.singleWhere(
      (member) => member.peerId == identity?.peerId,
    );
    ownedGroups.add(group.id);
    await groupRepository.saveGroup(
      group.copyWith(
        myRole: self.role == MemberRole.admin
            ? GroupRole.admin
            : GroupRole.member,
      ),
    );
    for (final member in members) {
      await groupRepository.saveMember(member);
    }
    await groupRepository.saveKey(key);
    await callGroupJoinWithConfig(
      bridge,
      groupId: group.id,
      groupConfig: Map<String, dynamic>.from(args['groupConfig'] as Map),
      groupKey: key.encryptedKey,
      keyEpoch: key.keyGeneration,
    );
    return {'groupId': group.id};
  });
  controller.bindAction('mark_fixture_joined', (args) async {
    final groupId = string(args, 'groupId');
    requireOwned(groupId);
    await inviteDeliveryRepository.markJoined(
      groupId: groupId,
      peerId: string(args, 'peerId'),
      username: string(args, 'username'),
    );
    return {'joined': true};
  });
  controller.bindAction('adopt_prepared_group', (args) async {
    // A fresh invocation after normal application restart may observe only the
    // same run's already-persisted fixture. This does not create or join a group.
    final groupId = string(args, 'groupId');
    final group = await groupRepository.getGroup(groupId);
    final identity = await identityRepository.loadIdentity();
    final members = await groupRepository.getMembers(groupId);
    if (group == null ||
        group.name != productionFixtureGroupName(controller, group.type) ||
        identity == null ||
        !members.any((member) => member.peerId == identity.peerId) ||
        await groupRepository.getLatestKey(groupId) == null) {
      throw StateError('prepared fixture does not belong to this invocation');
    }
    ownedGroups.add(groupId);
    return {'groupId': groupId, 'persistedFixtureAccepted': true};
  });
  controller.bindAction('leave_topic', (args) async {
    final groupId = string(args, 'groupId');
    requireOwned(groupId);
    await recoveryHold.acquire();
    try {
      await callGroupLeave(bridge, groupId);
      recoveryHold.requireHeld();
      liveGapGroup = groupId;
      return {'leftTopic': groupId, 'competingRecoveryHeld': true};
    } catch (_) {
      recoveryHold.dispose();
      rethrow;
    }
  });
  controller.bindAction('rejoin_topics', (_) async {
    if (liveGapGroup != null) {
      await recoveryHold.release();
      liveGapGroup = null;
    }
    final result = await rejoinGroupTopics(
      bridge: bridge,
      groupRepo: groupRepository,
      reason: RejoinReason.inPlaceRecovery,
    );
    return {
      'errorCount': result.errorCount,
      'joinedGroupCount': result.joinedGroupCount,
    };
  });
  controller.bindAction('snapshot', (args) async {
    final groupId = string(args, 'groupId');
    requireOwned(groupId);
    if (liveGapGroup == groupId) recoveryHold.requireHeld();
    final messages = await groupMessageRepository.getMessagesPage(
      groupId,
      limit: 500,
    );
    return {
      'messages': messages
          .map(
            (message) => {
              'id': message.id,
              'text': message.text,
              'incoming': message.isIncoming,
            },
          )
          .toList(),
      'notifications': controller.foregroundPush.snapshotNotifications(),
    };
  });
  controller.bindAction('foreground_push', (args) async {
    final groupId = string(args, 'groupId');
    final fail = args['failMissingGroupDrain'] == true;
    if (fail) {
      if (groupId != 'missing-${controller.invocation.runId}' ||
          await groupRepository.getGroup(groupId) != null) {
        throw StateError(
          'failure injection requires the exact absent fixture group',
        );
      }
    } else {
      requireOwned(groupId);
      if (liveGapGroup == groupId) recoveryHold.requireHeld();
    }
    return controller.foregroundPush.inject(
      groupId: groupId,
      messageId: string(args, 'messageId'),
      failMissingGroupDrain: fail,
    );
  });
}
