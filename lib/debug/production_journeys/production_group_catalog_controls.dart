import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';

String productionCatalogGroupName(ProductionJourneyController controller) =>
    'Catalog ${controller.invocation.scenarioId.split('.').last} ${controller.invocation.runId}';

/// Repository observations for a group created and joined through the real UI.
/// Receives existing owners; never creates a listener, repository or service.
void bindProductionGroupCatalogObservations({
  required ProductionJourneyController controller,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required GroupInviteDeliveryAttemptRepository deliveryRepository,
}) {
  if (!productionGroupCatalogJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    return;
  }
  final name = productionCatalogGroupName(controller);
  String? boundGroupId;
  controller.bindAction('catalog_group_snapshot', (_) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity absent');
    final groups = (await groupRepository.getAllGroups())
        .where((g) => g.name == name)
        .toList();
    if (groups.length > 1 ||
        (boundGroupId != null && groups.any((g) => g.id != boundGroupId))) {
      throw StateError('ambiguous or replaced catalog group');
    }
    final group = groups.singleOrNull;
    boundGroupId ??= group?.id;
    final state = p2pService.currentState;
    final snapshot = <String, Object?>{
      'runId': controller.invocation.runId,
      'scenario': controller.invocation.scenarioId.split('.').last,
      'role': controller.invocation.role,
      'peerId': identity.peerId,
      'username': identity.username,
      'transportPeerId': state.peerId,
      'relayReady': state.relayReady,
      'sendReady': state.sendCapabilityReady,
      'inboxReady': state.inboxCapabilityReady,
      'groupRecoveryActive': isGroupRecoveryInProgress(),
      'relayAddresses': defaultRelayAddresses().join(','),
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'group': null,
    };
    if (group == null) return snapshot;
    final members = await groupRepository.getMembers(group.id);
    if (!members.any((m) => m.peerId == identity.peerId)) {
      throw StateError('observed group has no current-identity membership');
    }
    final key = await groupRepository.getLatestKey(group.id);
    final messages = await messageRepository.getMessagesPage(
      group.id,
      limit: 500,
    );
    final config = buildGroupConfigPayload(group, members);
    snapshot['group'] = {
      'id': group.id,
      'name': group.name,
      'createdBy': group.createdBy,
      'type': group.type.name,
      'role': group.myRole.name,
      'topicName': group.topicName,
      'keyEpoch': key?.keyGeneration,
      'groupConfigStateHash': config[groupConfigStateHashField],
      // Field-level digests locate genuine peer divergence without exporting
      // public-key material or replacing the unchanged complete-state oracle.
      'configFieldDigests': productionCatalogConfigFieldDigests(config),
      'configVersion': config[groupConfigVersionField],
      'metadataUpdatedAt': config['metadataUpdatedAt'],
      'createdAt': config['createdAt'],
      'members': [
        for (final m in members) {'peerId': m.peerId, 'role': m.role.name},
      ],
      'deliveryAttempts': [
        for (final member in members)
          if (member.peerId != identity.peerId)
            if (await deliveryRepository.getAttempt(
                  groupId: group.id,
                  peerId: member.peerId,
                )
                case final attempt?)
              attempt.toMap(),
      ],
      'messages': [
        for (final m in messages)
          {
            'messageId': m.id,
            'groupId': m.groupId,
            'senderPeerId': m.senderPeerId,
            'text': m.text,
            'keyEpoch': m.keyGeneration,
            'isIncoming': m.isIncoming,
            'status': m.status,
          },
      ],
    };
    return snapshot;
  });
}

Map<String, String> productionCatalogConfigFieldDigests(
  Map<String, dynamic> config,
) {
  final fields = <String, String>{};
  void visit(String path, Object? value) {
    if (value is Map && value.isNotEmpty) {
      for (final entry in value.entries) {
        visit('$path/${entry.key}', entry.value);
      }
    } else if (value is List && value.isNotEmpty) {
      for (var i = 0; i < value.length; i++) {
        final row = value[i];
        final identity = row is Map ? row['peerId'] ?? row['deviceId'] ?? i : i;
        visit('$path/$identity', row);
      }
    } else {
      if (fields.containsKey(path)) {
        throw StateError('ambiguous config diagnostic path');
      }
      fields[path] = sha256.convert(utf8.encode(jsonEncode(value))).toString();
    }
  }

  visit('config', config);
  return fields;
}

void bindProductionGroupCatalogInviteObservations({
  required ProductionJourneyController controller,
  required PendingGroupInviteRepository pendingRepository,
}) {
  if (!productionGroupCatalogJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    return;
  }
  final name = productionCatalogGroupName(controller);
  String? boundInviteId;
  controller.bindAction('catalog_pending_snapshot', (_) async {
    final pending = (await pendingRepository.getPendingInvites())
        .where((i) => i.groupName == name)
        .toList();
    // A bound invitation seen leaving the pending list was consumed (accepted
    // or declined); a later re-add invitation may then bind afresh.
    if (pending.isEmpty) boundInviteId = null;
    if (pending.length > 1 ||
        (boundInviteId != null &&
            pending.any((i) => i.inviteId != boundInviteId))) {
      throw StateError('ambiguous or replaced catalog invitation');
    }
    boundInviteId ??= pending.singleOrNull?.inviteId;
    return {
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'pending': [
        for (final i in pending)
          {
            'inviteId': i.inviteId,
            'groupId': i.groupId,
            'senderPeerId': i.senderPeerId,
            'name': i.groupName,
            if (GroupInvitePayload.fromJson(i.payloadJson) case final payload?)
              'configuration': {
                'stateHash': payload.groupConfig[groupConfigStateHashField],
                'fieldDigests': productionCatalogConfigFieldDigests(
                  payload.groupConfig,
                ),
                'configVersion': payload.groupConfig[groupConfigVersionField],
                'membershipWatermark':
                    payload.membershipFreshnessProof?.membershipWatermark,
              },
          },
      ],
      'consumed': boundInviteId == null
          ? null
          : (await pendingRepository.getConsumedInvite(
              boundInviteId!,
            ))?.toMap(),
    };
  });
}
