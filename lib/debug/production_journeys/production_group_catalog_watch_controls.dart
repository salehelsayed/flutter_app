import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/debug_group_delivery_observer.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/debug_group_exit_observer.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
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
  groupCatalogGm005Journey,
  groupCatalogOfflineRemoveJourney,
  groupCatalogGm006Journey,
  groupCatalogOfflineReaddJourney,
  groupCatalogGm001Journey,
  groupCatalogGe001Journey,
  groupCatalogDe003Journey,
  groupCatalogGe002Journey,
  groupCatalogGe003Journey,
  groupCatalogGm020Journey,
  groupCatalogGm034Journey,
  groupCatalogGm016Journey,
  groupCatalogGe004Journey,
  groupCatalogGm007Journey,
  groupCatalogGm019Journey,
  groupCatalogGe009Journey,
  groupCatalogRapidReaddJourney,
  groupCatalogIr001Journey,
  groupCatalogGm008Journey,
  groupCatalogGe007Journey,
  groupCatalogGe008Journey,
  groupCatalogGe005Journey,
  groupCatalogReaddCyclesJourney,
  groupCatalogGe010Journey,
  groupCatalogGo001Journey,
  groupCatalogGe011Journey,
  groupCatalogFullMeshJourney,
  groupCatalogDe002Journey,
  groupCatalogGe006Journey,
  groupCatalogDe007Journey,
  groupCatalogVoluntaryLeaveJourney,
  groupCatalogGm015Journey,
  groupCatalogGe024Journey,
  groupCatalogMediaReactionJourney,
  groupCatalogGm002Journey,
  groupCatalogMl002Journey,
  groupCatalogGm003Journey,
  groupCatalogMl003Journey,
  groupCatalogNw006Journey,
  groupCatalogMl020Journey,
  groupCatalogNw003Journey,
  groupCatalogNw010Journey,
  groupCatalogUp012Journey,
};

const _watchedFlowEvents = {
  'GROUP_DISCOVERY',
  'GROUP_FL_BRIDGE_LEAVE_REQUEST',
  'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
  'GROUP_FL_BRIDGE_JOIN_REQUEST',
  'GROUP_FL_BRIDGE_JOIN_CONFIG_REQUEST',
  'GROUP_PAYLOAD_PARSE_FAILED',
  'GROUP_DECRYPTION_FAILED',
  'GROUP_SEND_MSG_USE_CASE_SUCCESS',
  'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
  ..._drainFlowEvents,
};

// NW-010 reads the order in which a relaunched member applied its catch-up:
// each incoming message and the membership removal.
const _applyOrderFlowEvents = {
  'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
  'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED',
};

// Membership-edit outcomes, so a refused UI removal or re-add records why.
const _watchedFlowEventPrefixes = [
  'GROUP_REMOVE_MEMBER_USE_CASE_',
  'GROUP_ADD_MEMBER_USE_CASE_',
  'GROUP_RECOVERY_GATE_',
  'GROUP_ROTATE_KEY_',
  'GROUP_INFO_FL_REMOVE_',
  'GROUP_CREATOR_OWED_REKEY_',
  'GROUP_INVITE_STORE_PENDING_',
  'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_',
  // A rejected signed transition, with the state-hash breakdowns of the
  // signer and the rejecting member.
  'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_',
  'GROUP_TRANSITION_PRE_STATE_',
  'GROUP_MESSAGE_LISTENER_PRE_STATE_',
];

// The drain diagnostics the original offline-removal proof summarizes.
const _drainFlowEvents = {
  'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE',
  'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE',
  'GROUP_DRAIN_OFFLINE_INBOX_STOP_GROUP_REMOVED',
  'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED',
  'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED',
  'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED',
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
  required MediaAttachmentRepository mediaAttachmentRepository,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
  required GroupMessageListener groupMessageListener,
}) {
  if (!productionCatalogWatchJourneys.contains(
    controller.invocation.scenarioId,
  )) {
    return;
  }
  final flowEvents = <Map<String, Object?>>[];
  var overflow = false;
  final applyOrder =
      controller.invocation.scenarioId == groupCatalogNw010Journey;
  final lease = installScopedE2EFlowEventSink((event) {
    final name = '${event['event']}';
    if (!_watchedFlowEvents.contains(name) &&
        !_watchedFlowEventPrefixes.any(name.startsWith) &&
        !(applyOrder && _applyOrderFlowEvents.contains(name))) {
      return;
    }
    // Long journeys keep the newest events; the overflow flag records that
    // older ones were dropped.
    if (flowEvents.length >= 2048) {
      overflow = true;
      flowEvents.removeAt(0);
    }
    flowEvents.add(Map<String, Object?>.from(event));
  });
  controller.bindDisposer(lease.release);

  // Durable recipients of each group send, for originals that read them from
  // a recording bridge. Copies only ids, recipients and delivery counts; the
  // request payload (which carries signing keys) is never retained.
  final deliveries = <Map<String, Object?>>[];
  // Native topic leaves per group id (H-01 bridge leave counts).
  final topicLeaves = <String, int>{};
  debugGroupDeliveryObserver = (cmd, payload, response) {
    if (cmd == 'group:leave') {
      if (payload['groupId'] case final String groupId) {
        topicLeaves[groupId] = (topicLeaves[groupId] ?? 0) + 1;
      }
      return;
    }
    String? messageId;
    if (cmd == 'group:sendReliable') {
      messageId = payload['messageId'] as String?;
    } else if (payload['message'] case final String envelope) {
      try {
        messageId = (jsonDecode(envelope) as Map)['messageId'] as String?;
      } catch (_) {}
    }
    if (messageId == null || deliveries.length >= 512) return;
    final recipients = cmd == 'group:sendReliable'
        ? response['recipientPeerIds']
        : payload['recipientPeerIds'];
    deliveries.add({
      'cmd': cmd,
      'messageId': messageId,
      'ok': response['ok'] == true,
      'recipientPeerIds': [
        if (recipients is List)
          for (final r in recipients) '$r',
      ],
      'inboxStored': ?response['inboxStored'],
      'topicPeers': ?(response['topicPeerCount'] ?? response['topicPeers']),
      'expectedRecipientCount': ?response['expectedRecipientCount'],
      'deliveryMode': ?response['deliveryMode'],
    });
  };
  controller.bindDisposer(() => debugGroupDeliveryObserver = null);

  // Raw inbound group traffic per group id, for originals that count what a
  // removed member still receives, and the ids of messages that arrived live
  // on the topic (anything else came from the offline inbox). Counts and ids
  // only; payloads are not retained.
  final inbound = <String, Map<String, int>>{};
  final liveMessageIds = <String, Set<String>>{};
  debugGroupInboundObserver = (kind, data) {
    final groupId = data['groupId'];
    if (groupId is! String) return;
    final counts = inbound.putIfAbsent(groupId, () => {});
    counts[kind] = (counts[kind] ?? 0) + 1;
    final messageId = data['messageId'];
    if (kind == 'message' && messageId is String) {
      final ids = liveMessageIds.putIfAbsent(groupId, () => {});
      if (ids.length < 2048) ids.add(messageId);
    }
  };
  controller.bindDisposer(() => debugGroupInboundObserver = null);

  // Voluntary exit steps per group id, for originals that read the durable
  // exit evidence of a leave (H-01, GM-015): step counts (requests by kind:
  // request_leave, request_queue, request_retry), the rotation outcome and
  // the leave request's status with the intent ids.
  final exits = <String, Map<String, Object?>>{};
  debugGroupExitObserver = (step, groupId, details) {
    final record = exits.putIfAbsent(
      groupId,
      () => <String, Object?>{'counts': <String, int>{}},
    );
    final counts = record['counts']! as Map<String, int>;
    counts[step] = (counts[step] ?? 0) + 1;
    if (step == 'request_leave') record['request'] = Map.of(details);
    if (step == 'rotation_result') {
      record['rotationDeferred'] = details['deferred'];
    }
  };
  controller.bindDisposer(() => debugGroupExitObserver = null);

  // The original removed-member proof: one send attempt per original key by
  // the removed role
  // through the production use case, recording the actual (rejected) outcome.
  final removedSendKeys = <String>{};
  controller.bindAction('catalog_attempt_removed_send', (args) async {
    final key = args['key'];
    final text = args['text'];
    if (key is! String || text is! String || removedSendKeys.contains(key)) {
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
    removedSendKeys.add(key);
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

  // The original `_drainOfflineRemovalUntilSelfRemoved`: explicit production
  // drains every second until the group is gone or 45 s elapse, summarizing
  // the drain diagnostics emitted during that window.
  controller.bindAction('catalog_drain_until_self_removed', (_) async {
    final identity = await identityRepository.loadIdentity();
    final named = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (identity == null || named.length != 1) {
      throw StateError('exact run group required for catch-up drain');
    }
    final groupId = named.single.id;
    final start = flowEvents.length;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var attempts = 0, completed = 0;
    final errors = <String>[];
    while (true) {
      attempts++;
      try {
        await drainGroupOfflineInboxForGroup(
          bridge: bridge,
          groupRepo: groupRepository,
          msgRepo: messageRepository,
          groupId: groupId,
          groupMessageListener: groupMessageListener,
          selfPeerId: identity.peerId,
        );
        completed++;
      } catch (error) {
        errors.add('$error');
      }
      if (await groupRepository.getGroup(groupId) == null ||
          !DateTime.now().isBefore(deadline)) {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    int count(Object? value) =>
        value is int ? value : int.tryParse('${value ?? ''}') ?? 0;
    final retrieve = <int>[], groupDone = <int>[];
    var removalStop = false;
    var recipientSkipped = 0, signatureRejected = 0, decodeSkipped = 0;
    for (final event in flowEvents.skip(start)) {
      final details = event['details'] is Map
          ? event['details'] as Map
          : const {};
      switch (event['event']) {
        case 'GROUP_FL_BRIDGE_INBOX_RETRIEVE_CURSOR_RESPONSE':
          retrieve.add(count(details['count']));
        case 'GROUP_DRAIN_OFFLINE_INBOX_GROUP_DONE':
          groupDone.add(count(details['messageCount']));
        case 'GROUP_DRAIN_OFFLINE_INBOX_STOP_GROUP_REMOVED':
          removalStop = true;
        case 'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED':
          recipientSkipped++;
        case 'GROUP_DRAIN_OFFLINE_INBOX_REPLAY_SIGNATURE_REJECTED':
          signatureRejected++;
        case 'GROUP_DRAIN_OFFLINE_INBOX_DECODE_SKIPPED':
          decodeSkipped++;
      }
    }
    return {
      'drainAttemptCount': attempts,
      'completedDrainCount': completed,
      'drainErrorCount': errors.length,
      if (errors.isNotEmpty) 'drainErrors': errors.take(5).toList(),
      'drainRetrieveCounts': retrieve,
      'drainRetrievedMessageCount': retrieve.fold<int>(0, (a, b) => a + b),
      'drainGroupDoneMessageCounts': groupDone,
      'drainSawRemovalStop': removalStop,
      'drainRecipientSkippedCount': recipientSkipped,
      'drainSignatureRejectedCount': signatureRejected,
      'drainDecodeSkippedCount': decodeSkipped,
    };
  });

  // The original DE-003 replay check: one explicit production catch-up drain
  // of the run group; the host then counts the rows by message id.
  controller.bindAction('catalog_drain_once', (_) async {
    final identity = await identityRepository.loadIdentity();
    final named = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (identity == null || named.length != 1) {
      throw StateError('exact run group required for catch-up drain');
    }
    await drainGroupOfflineInboxForGroup(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      groupId: named.single.id,
      groupMessageListener: groupMessageListener,
      selfPeerId: identity.peerId,
    );
    return {'completedDrainCount': 1};
  });

  // The durable exit state of one group by id, readable after the group is
  // deleted: presence, its remaining rows, and whether its exit intent and
  // pending leave broadcast are gone (terminal cleanup).
  controller.bindAction('catalog_exit_snapshot', (args) async {
    final groupId = args['groupId'];
    if (groupId is! String || groupId.isEmpty) {
      throw StateError('exit snapshot needs a group id');
    }
    final lookup = await loadGroupExitIntent(groupId);
    final pending = await loadGroupPendingBroadcasts(groupId);
    final messages = await messageRepository.getMessagesPage(
      groupId,
      limit: 500,
    );
    return {
      'groupPresent': await groupRepository.getGroup(groupId) != null,
      'latestKeyGeneration': (await groupRepository.getLatestKey(
        groupId,
      ))?.keyGeneration,
      'messageCount': messages.length,
      'memberRemovedTimelineIds': [
        for (final m in messages)
          if (m.id.startsWith('sys-member_removed:')) m.id,
      ],
      'intentLookupAvailable': lookup.isAvailable,
      'intentPresent': lookup.intent != null,
      'intentState': lookup.intent?.state.databaseValue,
      'pendingBroadcastIds': [for (final b in pending) b.id],
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
      'deliveries': List.of(deliveries),
      'topicLeaves': Map.of(topicLeaves),
      'exits': {
        for (final MapEntry(:key, :value) in exits.entries)
          key: {...value, 'counts': Map.of(value['counts']! as Map)},
      },
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
    final config = buildGroupConfigPayload(group, members);
    return {
      ...base,
      'groupId': group.id,
      'topicName': group.topicName,
      'keyEpoch':
          (await groupRepository.getLatestKey(group.id))?.keyGeneration ?? 0,
      'groupConfigStateHash': config[groupConfigStateHashField],
      'configMemberPeerIds': [
        for (final m in (config['members'] as List? ?? const []))
          if (m is Map && m['peerId'] is String) m['peerId'] as String,
      ],
      'lastMembershipEventAt': group.lastMembershipEventAt
          ?.toUtc()
          .toIso8601String(),
      'messageCount': messages.length,
      'createdBy': group.createdBy,
      'isDissolved': group.isDissolved,
      'dissolveTimelineTexts': [
        for (final m in messages)
          if (m.id.startsWith('sys-group_dissolved:')) m.text,
      ],
      'memberRemovedTimelineIds': [
        for (final m in messages)
          if (m.id.startsWith('sys-member_removed:')) m.id,
      ],
      'inbound': inbound[group.id] ?? const {},
      'liveMessageIds': [...?liveMessageIds[group.id]],
      'memberPeerIds': [for (final m in members) m.peerId],
      // UP-012 reads every notification request of this app process (title
      // and body hashes only).
      if (controller.invocation.scenarioId == groupCatalogUp012Journey)
        'notifications': controller.foregroundPush.snapshotNotifications(),
      'memberDetails': [
        for (final m in members)
          {
            'peerId': m.peerId,
            'role': m.role.name,
            'deviceCount': m.devices.length,
            'activeTransportPeerIds': [
              for (final d in m.activeDevices) d.transportPeerId,
            ],
          },
      ],
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
                  'quotedMessageId': m.quotedMessageId,
                  'mediaAttachmentCount':
                      (await mediaAttachmentRepository.getAttachmentsForMessage(
                        m.id,
                        owner: MediaOwnerLane.group,
                      )).length,
                },
          ],
      },
    };
  });
}
