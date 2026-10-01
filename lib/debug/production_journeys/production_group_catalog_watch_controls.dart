import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_catalog_controls.dart';
import 'production_journey_controller.dart';

/// Catalog journeys whose original proof reads production flow diagnostics
/// (for example NW-002 `group:discovery` route events).
const productionCatalogWatchJourneys = {
  groupCatalogRelayOnlyJourney,
  groupCatalogProcessDeathJourney,
  groupCatalogGm004Journey,
};

const _watchedFlowEvents = {
  'GROUP_DISCOVERY',
  'GROUP_SEND_MSG_USE_CASE_SUCCESS',
  'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
};

/// Read-only catalog observation: the run group, its members and key epoch,
/// exact rows for host-named texts, and the already-sanitized production flow
/// events the original oracle's diagnostics need. Never sends or mutates.
void bindProductionGroupCatalogWatchControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
}) {
  if (!productionCatalogWatchJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    return;
  }
  final flowEvents = <Map<String, Object?>>[];
  var overflow = false;
  final lease = installScopedE2EFlowEventSink((event) {
    if (!_watchedFlowEvents.contains(event['event'])) return;
    if (flowEvents.length >= 2048) {
      overflow = true;
      return;
    }
    flowEvents.add(Map<String, Object?>.from(event));
  });
  controller.bindDisposer(lease.release);

  // The original removed-member proof: one send attempt by the removed role
  // through the production use case, recording the actual (rejected) outcome.
  var removedSendAttempted = false;
  controller.bindAction('catalog_attempt_removed_send', (args) async {
    final key = args['key'];
    final text = args['text'];
    if (key is! String || text is! String || removedSendAttempted) {
      throw StateError('removed send attempt refused');
    }
    final identity = await identityRepository.loadIdentity();
    final named = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (identity == null ||
        named.length != 1 ||
        await groupRepository.getMember(named.single.id, identity.peerId) !=
            null) {
      throw StateError('exact removed identity and retained group required');
    }
    removedSendAttempted = true;
    final groupId = named.single.id;
    final scenario = controller.invocation.scenarioId.split('.').last;
    final messageId =
        'gmp_${controller.invocation.runId}_${scenario}_${key}_${controller.invocation.role}';
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      groupId: groupId,
      text: text,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      messageId: messageId,
      inviteDeliveryAttemptRepo: inviteDeliveryRepository,
    );
    return {
      'key': key,
      'messageId': message?.id ?? messageId,
      'text': text,
      'outcome': result.name,
      'senderPeerId': identity.peerId,
      'keyEpoch':
          message?.keyGeneration ??
          (await groupRepository.getLatestKey(groupId))?.keyGeneration ??
          0,
      'accepted':
          result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers,
    };
  });

  controller.bindAction('catalog_watch_snapshot', (args) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity absent');
    final named = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (named.length > 1) throw StateError('ambiguous run group');
    final base = <String, Object?>{
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'scenario': controller.invocation.scenarioId.split('.').last,
      'peerId': identity.peerId,
      'username': identity.username,
      'transportPeerId': p2pService.currentState.peerId,
      'relayReady': p2pService.currentState.relayReady,
      'advertisesRelayOnly':
          p2pService.currentState.featureFlags?['debugAdvertiseRelayOnly'] ==
          true,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'flowEvents': List.of(flowEvents),
      'flowEventOverflow': overflow,
      'groupPresent': named.isNotEmpty,
    };
    if (named.isEmpty) return base;
    final group = named.single;
    final members = await groupRepository.getMembers(group.id);
    final messages = await messageRepository.getMessagesPage(
      group.id,
      limit: 500,
    );
    final watched = (args['texts'] as Map?) ?? const {};
    return {
      ...base,
      'groupId': group.id,
      'topicName': group.topicName,
      'keyEpoch':
          (await groupRepository.getLatestKey(group.id))?.keyGeneration ?? 0,
      'groupConfigStateHash': buildGroupConfigPayload(
        group,
        members,
      )[groupConfigStateHashField],
      'memberPeerIds': [for (final m in members) m.peerId],
      'selfMember': members.any((m) => m.peerId == identity.peerId),
      'timelineTexts': [
        for (final m in messages)
          if (m.text.endsWith(' joined the group')) m.text,
      ],
      'watched': {
        for (final entry in watched.entries)
          '${entry.key}': [
            for (final m in messages)
              if (m.text == (entry.value as Map)['text'] &&
                  m.senderPeerId == (entry.value as Map)['senderPeerId'])
                {
                  'messageId': m.id,
                  'groupId': m.groupId,
                  'text': m.text,
                  'senderPeerId': m.senderPeerId,
                  'senderUsername': m.senderUsername,
                  'timestamp': m.timestamp.toUtc().toIso8601String(),
                  'keyEpoch': m.keyGeneration,
                  'isIncoming': m.isIncoming,
                  'status': m.status,
                },
          ],
      },
    };
  });
}
