import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

const groupMembershipUpdateMessageType = 'group_membership_update';

class GroupMembershipUpdateDirectTarget {
  const GroupMembershipUpdateDirectTarget({
    required this.memberPeerId,
    required this.deliveryPeerId,
  });

  final String memberPeerId;
  final String deliveryPeerId;
}

List<GroupMembershipUpdateDirectTarget> groupMembershipUpdateDirectTargets({
  required Iterable<GroupMember> members,
  String? excludingPeerId,
}) {
  final excluded = excludingPeerId?.trim();
  final seenDeliveryPeerIds = <String>{};
  final targets = <GroupMembershipUpdateDirectTarget>[];

  for (final member in members) {
    final memberPeerId = member.peerId.trim();
    if (memberPeerId.isEmpty || memberPeerId == excluded) {
      continue;
    }

    final devices = member.activeDevicesWithLegacyFallback();
    if (devices.isEmpty) {
      if (seenDeliveryPeerIds.add(memberPeerId)) {
        targets.add(
          GroupMembershipUpdateDirectTarget(
            memberPeerId: memberPeerId,
            deliveryPeerId: memberPeerId,
          ),
        );
      }
      continue;
    }

    for (final device in devices) {
      final deliveryPeerId = device.transportPeerId.trim();
      if (deliveryPeerId.isEmpty || !seenDeliveryPeerIds.add(deliveryPeerId)) {
        continue;
      }
      targets.add(
        GroupMembershipUpdateDirectTarget(
          memberPeerId: memberPeerId,
          deliveryPeerId: deliveryPeerId,
        ),
      );
    }
  }

  return targets;
}

String buildGroupMembershipUpdateDirectEnvelope({
  required String groupId,
  required String senderPeerId,
  required String replayEnvelope,
  required DateTime timestamp,
  String? messageId,
}) {
  return jsonEncode({
    'type': groupMembershipUpdateMessageType,
    'version': '1',
    'groupId': groupId,
    'relayEnvelope': {
      'from': senderPeerId,
      'message': replayEnvelope,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (messageId != null && messageId.isNotEmpty) 'id': messageId,
    },
  });
}

Future<bool> sendGroupMembershipUpdateDirect({
  required Future<bool> Function(String peerId, String message)? sendP2PMessage,
  required String recipientPeerId,
  required String groupId,
  required String senderPeerId,
  required String replayEnvelope,
  required DateTime timestamp,
  String? messageId,
  int attemptCount = 3,
  Duration retryDelay = const Duration(milliseconds: 500),
}) async {
  if (sendP2PMessage == null) return false;
  final envelope = buildGroupMembershipUpdateDirectEnvelope(
    groupId: groupId,
    senderPeerId: senderPeerId,
    replayEnvelope: replayEnvelope,
    timestamp: timestamp,
    messageId: messageId,
  );

  for (var attempt = 1; attempt <= attemptCount; attempt++) {
    var sent = false;
    try {
      sent = await sendP2PMessage(recipientPeerId, envelope);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEMBERSHIP_UPDATE_DIRECT_ATTEMPT_FAILED',
        details: {
          'groupId': _safeId(groupId),
          'recipientPeerId': _safeId(recipientPeerId),
          'attempt': attempt,
          'error': error.toString(),
        },
      );
    }
    if (sent) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEMBERSHIP_UPDATE_DIRECT_SENT',
        details: {
          'groupId': _safeId(groupId),
          'recipientPeerId': _safeId(recipientPeerId),
          'attempt': attempt,
        },
      );
      return true;
    }
    if (attempt < attemptCount) {
      await Future<void>.delayed(retryDelay);
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_MEMBERSHIP_UPDATE_DIRECT_FAILED',
    details: {
      'groupId': _safeId(groupId),
      'recipientPeerId': _safeId(recipientPeerId),
      'attemptCount': attemptCount,
    },
  );
  return false;
}

class GroupMembershipUpdateListener {
  GroupMembershipUpdateListener({
    required Stream<ChatMessage> groupMembershipUpdateStream,
    required GroupRepository groupRepo,
    required Bridge bridge,
    required GroupMessageListener groupMessageListener,
    GroupMessageRepository? msgRepo,
    GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
    RequestGroupKeyRepair? requestGroupKeyRepair,
  }) : _stream = groupMembershipUpdateStream,
       _groupRepo = groupRepo,
       _bridge = bridge,
       _groupMessageListener = groupMessageListener,
       _msgRepo = msgRepo,
       _pendingKeyRepairRepo = pendingKeyRepairRepo,
       _requestGroupKeyRepair =
           requestGroupKeyRepair ?? emitGroupKeyRepairRequest;

  final Stream<ChatMessage> _stream;
  final GroupRepository _groupRepo;
  final Bridge _bridge;
  final GroupMessageListener _groupMessageListener;
  final GroupMessageRepository? _msgRepo;
  final GroupPendingKeyRepairRepository? _pendingKeyRepairRepo;
  final RequestGroupKeyRepair _requestGroupKeyRepair;
  StreamSubscription<ChatMessage>? _subscription;
  Future<void> _messageProcessing = Future<void>.value();

  void start() {
    if (_subscription != null) return;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_START',
      details: {},
    );
    _subscription = _stream.listen(
      _enqueueMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_ERROR',
          details: {'error': error.toString()},
        );
      },
    );
  }

  void _enqueueMessage(ChatMessage message) {
    _messageProcessing = _messageProcessing.then(
      (_) => _handleMessage(message),
    );
  }

  Future<void> waitForIdle() => _messageProcessing;

  Future<void> _handleMessage(ChatMessage message) async {
    try {
      final decoded = jsonDecode(message.content) as Map<String, dynamic>;
      if (decoded['type'] != groupMembershipUpdateMessageType) return;

      final groupId = decoded['groupId'] as String?;
      final relayEnvelopeRaw = decoded['relayEnvelope'];
      if (groupId == null ||
          groupId.isEmpty ||
          relayEnvelopeRaw is! Map<String, dynamic>) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_MALFORMED',
          details: {'reason': 'missing_group_or_envelope'},
        );
        return;
      }

      final relayEnvelope = Map<String, dynamic>.from(relayEnvelopeRaw);
      final relaySenderPeerId = relayEnvelope['from'] as String?;
      final replayEnvelopeMessage = relayEnvelope['message'];
      if (replayEnvelopeMessage is! String || replayEnvelopeMessage.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_MALFORMED',
          details: {'reason': 'missing_replay_message'},
        );
        return;
      }

      final offlineReplayEnvelope =
          jsonDecode(replayEnvelopeMessage) as Map<String, dynamic>;
      if (!isGroupOfflineReplayEnvelope(offlineReplayEnvelope)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_MALFORMED',
          details: {'reason': 'not_group_replay_envelope'},
        );
        return;
      }

      late final String plaintext;
      try {
        plaintext = await decryptGroupOfflineReplayEnvelope(
          bridge: _bridge,
          groupRepo: _groupRepo,
          groupId: groupId,
          envelope: offlineReplayEnvelope,
          expectedRelayPeerId: relaySenderPeerId,
        );
      } catch (error) {
        if (await _queueDeferredReplayIfMaterializationPending(
          groupId: groupId,
          relayEnvelope: relayEnvelope,
          replayEnvelope: offlineReplayEnvelope,
          error: error,
        )) {
          return;
        }
        rethrow;
      }
      final replayPayload = jsonDecode(plaintext) as Map<String, dynamic>;
      await _groupMessageListener.handleReplayEnvelope(
        replayPayload,
        allowMembershipBuffer: true,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_APPLIED',
        details: {'groupId': _safeId(groupId), 'from': _safeId(message.from)},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_REJECTED',
        details: {'error': error.toString()},
      );
    }
  }

  void dispose() {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_STOP',
      details: {},
    );
    _subscription?.cancel();
    _subscription = null;
  }

  Future<bool> _queueDeferredReplayIfMaterializationPending({
    required String groupId,
    required Map<String, dynamic> relayEnvelope,
    required Map<String, dynamic> replayEnvelope,
    required Object error,
  }) async {
    final pendingRepo = _pendingKeyRepairRepo;
    final messages = _msgRepo;
    if (pendingRepo == null || messages == null) return false;
    if (!_isMaterializationPendingReplayError(error)) return false;

    final queued = await queueMissingGroupReplayKeyRepairFromEnvelope(
      pendingKeyRepairRepo: pendingRepo,
      msgRepo: messages,
      groupId: groupId,
      relayEnvelope: relayEnvelope,
      replayEnvelope: replayEnvelope,
      requestGroupKeyRepair: _requestGroupKeyRepair,
      repairReason: groupKeyRepairReasonDirectMembershipUpdateDeferred,
    );
    if (queued) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_DEFERRED_REPLAY_QUEUED',
        details: {'groupId': _safeId(groupId), 'error': error.toString()},
      );
    }
    return queued;
  }
}

String _safeId(String value) {
  return value.length > 10 ? value.substring(0, 10) : value;
}

bool _isMaterializationPendingReplayError(Object error) {
  if (error.toString().contains('Missing group replay key')) return true;
  return error is GroupOfflineReplaySignatureException &&
      error.reason == 'unknown_sender';
}
