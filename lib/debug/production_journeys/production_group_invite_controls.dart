import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';
import 'production_group_catalog_controls.dart';

/// Reads run-owned invitation facts from production repositories. UI actions
/// create, decline and revoke invitations. The original protocol's resend after
/// decline has no UI affordance; its one-shot action calls the real use case on
/// the same production owners. No receipts or application services are created.
void bindProductionGroupInviteControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required GroupRepository groupRepository,
  required PendingGroupInviteRepository pendingInviteRepository,
  required GroupInviteDeliveryAttemptRepository deliveryRepository,
}) {
  if (productionGroupCatalogJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    bindProductionGroupCatalogInviteObservations(
      controller: controller,
      pendingRepository: pendingInviteRepository,
    );
    return;
  }
  if (controller.invocation.scenarioId != groupInviteJourney) return;
  final run = controller.invocation.runId;
  final name = 'Invite Reliability $run';
  final names = {name, '$name (fresh)'};
  String? ownedGroup;
  String? ownedPeer;
  final inviteIds = <String>{};
  var exported = false;
  var requested = false;
  var resent = false;

  Future<void> bindPeer(Object? value) async {
    if (value is! String ||
        value.isEmpty ||
        (ownedPeer != null && value != ownedPeer)) {
      throw StateError('exact invitation peer required');
    }
    final contact = await contactRepository.getContact(value);
    if (contact?.rendezvous != '/mknoon/production-journey/$run') {
      throw StateError('invitation peer is not run-owned');
    }
    ownedPeer = value;
  }

  controller.bindAction('invite_snapshot', (args) async {
    await bindPeer(args['peerId']);
    final groups = (await groupRepository.getAllGroups())
        .where((g) => names.contains(g.name))
        .toList();
    final pending = (await pendingInviteRepository.getPendingInvites())
        .where(
          (i) => names.contains(i.groupName) && i.senderPeerId == ownedPeer,
        )
        .toList();
    final ids = {...groups.map((g) => g.id), ...pending.map((i) => i.groupId)};
    if (ids.length > 1 ||
        (ownedGroup != null && ids.any((id) => id != ownedGroup))) {
      throw StateError('ambiguous or changed invitation group');
    }
    ownedGroup ??= ids.singleOrNull;
    final id = ownedGroup;
    final group = id == null ? null : await groupRepository.getGroup(id);
    final members = id == null ? null : await groupRepository.getMembers(id);
    final key = id == null ? null : await groupRepository.getLatestKey(id);
    final attempt = id == null
        ? null
        : await deliveryRepository.getAttempt(groupId: id, peerId: ownedPeer!);
    for (final invite in pending) {
      inviteIds.add(invite.inviteId);
    }
    if (attempt?.inviteId != null) inviteIds.add(attempt!.inviteId!);
    if (inviteIds.length > 2) {
      throw StateError('unexpected additional invitation');
    }
    return {
      'runId': run,
      'role': controller.invocation.role,
      'peerId': ownedPeer,
      'groupId': id,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'group': group == null
          ? null
          : {
              'id': group.id,
              'name': group.name,
              'createdBy': group.createdBy,
              'role': group.myRole.name,
              'metadataAt': group.lastMetadataEventAt
                  ?.toUtc()
                  .toIso8601String(),
              'type': group.type.name,
            },
      'members': [
        for (final m in members ?? const <GroupMember>[])
          {'peerId': m.peerId, 'role': m.role.name},
      ],
      'keyGeneration': key?.keyGeneration,
      'pending': [
        for (final i in pending)
          {
            'groupId': i.groupId,
            'inviteId': i.inviteId,
            'senderPeerId': i.senderPeerId,
            'name': i.groupName,
          },
      ],
      'attempt': attempt?.toMap(),
      'revoked': [
        for (final invite in inviteIds)
          if (await pendingInviteRepository.getRevokedInvite(invite)
              case final value?)
            value.toMap(),
      ],
      'consumed': [
        for (final invite in inviteIds)
          if (await pendingInviteRepository.getConsumedInvite(invite)
              case final value?)
            value.toMap(),
      ],
    };
  });

  controller.bindAction('export_invite_stale_fixture', (_) async {
    if (controller.invocation.role != 'alice' ||
        exported ||
        ownedGroup == null) {
      throw StateError('initial group fixture export rejected');
    }
    final group = await groupRepository.getGroup(ownedGroup!);
    final key = await groupRepository.getLatestKey(ownedGroup!);
    final members = await groupRepository.getMembers(ownedGroup!);
    final identity = await identityRepository.loadIdentity();
    if (group?.name != name ||
        key == null ||
        identity == null ||
        group!.createdBy != identity.peerId ||
        members.length != 2 ||
        !members.any((m) => m.peerId == ownedPeer)) {
      throw StateError('initial production-created group fixture missing');
    }
    exported = true;
    // Private host evidence: copied only to the owned peer's original stale
    // membership prerequisite. Never include key material in summary reports.
    return {
      'group': group.toMap(),
      'key': key.toMap(),
      'members': members.map((m) => m.toMap()).toList(),
      'groupConfig': buildGroupConfigPayload(group, members),
    };
  });

  controller.bindAction('invite_drain_inbox', (_) async {
    if (ownedPeer == null) throw StateError('invitation peer not bound');
    await p2pService.drainOfflineInbox();
    return {'drainReturned': true};
  });

  controller.bindAction('resend_declined_invite', (_) async {
    if (controller.invocation.role != 'alice' ||
        !exported ||
        resent ||
        ownedGroup == null ||
        ownedPeer == null) {
      throw StateError('declined invitation resend prerequisite missing');
    }
    final attempt = await deliveryRepository.getAttempt(
      groupId: ownedGroup!,
      peerId: ownedPeer!,
    );
    final identity = await identityRepository.loadIdentity();
    final group = await groupRepository.getGroup(ownedGroup!);
    if (attempt?.status.name != 'declined' ||
        attempt?.inviteId == null ||
        inviteIds.length != 1 ||
        !inviteIds.contains(attempt!.inviteId) ||
        identity == null ||
        group?.createdBy != identity.peerId ||
        group?.name != name) {
      throw StateError('exact declined production invitation required');
    }
    resent = true;
    final result = await resendGroupInvite(
      p2pService: p2pService,
      bridge: bridge,
      groupRepo: groupRepository,
      inviteDeliveryAttemptRepo: deliveryRepository,
      identity: identity,
      groupId: ownedGroup!,
      memberPeerId: ownedPeer!,
    );
    if (!result.wasQueuedOrSent) {
      throw StateError('production resend failed: ${result.reason.name}');
    }
    return {'status': result.status.name, 'reason': result.reason.name};
  });

  controller.bindAction('prepare_invite_fresh_metadata', (_) async {
    if (controller.invocation.role != 'alice' ||
        !exported ||
        ownedGroup == null ||
        ownedPeer == null) {
      throw StateError('fresh metadata fixture prerequisite missing');
    }
    final group = await groupRepository.getGroup(ownedGroup!);
    final attempt = await deliveryRepository.getAttempt(
      groupId: ownedGroup!,
      peerId: ownedPeer!,
    );
    if (group?.name != name ||
        attempt?.status.name != 'revoked' ||
        attempt?.inviteId == null ||
        inviteIds.length != 2) {
      throw StateError('fresh metadata requires completed exact revocation');
    }
    // Original D fixture: direct metadata setup deliberately emits no group
    // broadcast. An ordinary edit could converge the recipient before the
    // config-request/response operation being measured.
    await groupRepository.updateGroup(
      group!.copyWith(
        name: '$name (fresh)',
        lastMetadataEventAt: DateTime.now().toUtc(),
      ),
    );
    return {'fixturePrepared': true, 'groupId': ownedGroup};
  });

  controller.bindAction('request_invite_metadata', (_) async {
    if (controller.invocation.role != 'bob' ||
        requested ||
        ownedGroup == null ||
        ownedPeer == null ||
        inviteIds.length != 2) {
      throw StateError('metadata request prerequisite missing');
    }
    final group = await groupRepository.getGroup(ownedGroup!);
    final identity = await identityRepository.loadIdentity();
    final contact = await contactRepository.getContact(ownedPeer!);
    if (group?.name != name ||
        identity == null ||
        contact == null ||
        await pendingInviteRepository.getPendingInvite(ownedGroup!) != null) {
      throw StateError('exact stale membership required');
    }
    requested = true;
    final result = await sendOnJoinGroupConfigRequest(
      p2pService: p2pService,
      bridge: bridge,
      groupId: ownedGroup!,
      requesterPeerId: identity.peerId,
      inviterPeerId: contact.peerId,
      inviterMlKemPublicKey: contact.mlKemPublicKey,
    );
    return {
      'result': result.name,
      'groupId': ownedGroup,
      'requesterPeerId': identity.peerId,
      'inviterPeerId': contact.peerId,
    };
  });
}
