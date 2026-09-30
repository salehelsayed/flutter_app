import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';

String productionInviteMatrixGroupId(String runId) =>
    'invite-status-matrix-$runId';

String productionInviteMatrixGroupName(String runId) =>
    'Invite Status Matrix $runId';

/// The original matrix's seven non-admin members, in its display order.
/// `acceptedOne` is the member device's real account; the rest are run-owned
/// synthetic peers that never publish.
const productionInviteMatrixSlots = [
  'acceptedOne',
  'acceptedTwo',
  'sent',
  'queued',
  'resend',
  'cannot',
  'unknown',
];

String productionInviteMatrixSyntheticPeer(String runId, String slot) =>
    'matrix-$runId-$slot';

/// Seeds the original invite-status matrix into the production repositories.
/// The original harness is a display proof over seeded rows
/// (`relayLifecycleProof: false`); the operation under test is the production
/// Group Info projection reached through ordinary UI. No invitation is sent,
/// no service is constructed and no receive outcome is synthesized.
void bindProductionGroupInviteMatrixControls({
  required ProductionJourneyController controller,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required GroupInviteDeliveryAttemptRepository deliveryRepository,
}) {
  if (controller.invocation.scenarioId != groupInviteMatrixJourney) return;
  final run = controller.invocation.runId;
  final role = controller.invocation.role;
  final groupId = productionInviteMatrixGroupId(run);
  var seeded = false;

  String string(Map<String, Object?> values, String name) {
    final value = values[name];
    if (value is! String || value.isEmpty) {
      throw FormatException('missing $name');
    }
    return value;
  }

  controller.bindAction('prepare_invite_matrix', (args) async {
    final adminPeerId = string(args, 'adminPeerId');
    final memberPeerId = string(args, 'memberPeerId');
    final identity = await identityRepository.loadIdentity();
    final self = role == 'alice' ? adminPeerId : memberPeerId;
    if (seeded ||
        identity == null ||
        identity.peerId != self ||
        adminPeerId == memberPeerId ||
        await groupRepository.getGroup(groupId) != null) {
      throw StateError('invite matrix seed rejected');
    }
    seeded = true;
    final peers = {
      for (final slot in productionInviteMatrixSlots)
        slot: slot == 'acceptedOne'
            ? memberPeerId
            : productionInviteMatrixSyntheticPeer(run, slot),
    };
    // The original fixed minute offsets are kept relative to one base time so
    // the accepted-two join note stays after its stale "sent" attempt.
    final base = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    DateTime at(int minute) => base.add(Duration(minutes: minute));
    final random = Random.secure();
    await groupRepository.saveGroup(
      GroupModel(
        id: groupId,
        name: productionInviteMatrixGroupName(run),
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        description: 'Creator-side invite status matrix proof',
        createdAt: base,
        createdBy: adminPeerId,
        myRole: role == 'alice' ? GroupRole.admin : GroupRole.member,
      ),
    );
    await groupRepository.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: base64Encode(
          List<int>.generate(32, (_) => random.nextInt(256)),
        ),
        createdAt: at(0),
      ),
    );
    const usernames = {
      'acceptedOne': 'Accepted One',
      'acceptedTwo': 'Accepted Two',
      'sent': 'Sent Member',
      'queued': 'Queued Member',
      'resend': 'Resend Member',
      'cannot': 'Cannot Member',
      'unknown': 'Unknown Member',
    };
    await groupRepository.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: adminPeerId,
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-$adminPeerId',
        mlKemPublicKey: 'mlkem-pk-$adminPeerId',
        joinedAt: at(0),
      ),
    );
    for (final (index, slot) in productionInviteMatrixSlots.indexed) {
      final peerId = peers[slot]!;
      await groupRepository.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: usernames[slot],
          role: MemberRole.writer,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-pk-$peerId',
          joinedAt: at(index + 1),
        ),
      );
    }
    for (final (slot, minute) in [('acceptedOne', 10), ('acceptedTwo', 11)]) {
      await groupMessageRepository.saveMessage(
        buildMemberJoinedTimelineMessage(
          groupId: groupId,
          joinedPeerId: peers[slot]!,
          joinedUsername: usernames[slot],
          eventAt: at(minute),
        ),
      );
    }
    for (final (slot, status, minute, error) in [
      ('acceptedTwo', GroupInviteDeliveryStatus.sent, 8, null),
      ('sent', GroupInviteDeliveryStatus.sent, 12, null),
      ('queued', GroupInviteDeliveryStatus.queued, 13, null),
      ('resend', GroupInviteDeliveryStatus.needsResend, 14, null),
      ('cannot', GroupInviteDeliveryStatus.cannotSend, 15, 'missing_secure_key'),
    ]) {
      await deliveryRepository.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peers[slot]!,
          username: usernames[slot],
          status: status,
          attemptedAt: at(minute),
          updatedAt: at(minute),
          lastError: error,
        ),
      );
    }
    return {'groupId': groupId, 'peers': peers};
  });

  // Read-only: valid only for this run's deterministic group, so it also works
  // after the ordinary reopen that lets Orbit list the seeded group.
  controller.bindAction('invite_matrix_snapshot', (_) async {
    final group = await groupRepository.getGroup(groupId);
    if (group == null || group.name != productionInviteMatrixGroupName(run)) {
      throw StateError('invite matrix group is not run-owned');
    }
    final identity = await identityRepository.loadIdentity();
    final members = await groupRepository.getMembers(groupId);
    final attempts = await deliveryRepository.getAttemptsForGroup(groupId);
    return {
      'runId': run,
      'role': role,
      'selfPeerId': identity?.peerId,
      'groupId': groupId,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'group': {
        'id': group.id,
        'name': group.name,
        'createdBy': group.createdBy,
        'role': group.myRole.name,
        'type': group.type.name,
      },
      'members': [
        for (final member in members)
          {
            'peerId': member.peerId,
            'username': member.username,
            'role': member.role.name,
            'joinedEvidenceAt':
                (await groupMessageRepository
                        .getLatestSystemEventTimestampForTarget(
                          groupId,
                          eventType: 'member_joined',
                          targetId: member.peerId,
                        ))
                    ?.toUtc()
                    .toIso8601String(),
          },
      ],
      'attempts': [
        for (final attempt in attempts)
          {
            'peerId': attempt.peerId,
            'status': attempt.status.name,
            'lastError': attempt.lastError,
            'attemptedAt': attempt.attemptedAt.toUtc().toIso8601String(),
            'updatedAt': attempt.updatedAt.toUtc().toIso8601String(),
          },
      ],
    };
  });
}
