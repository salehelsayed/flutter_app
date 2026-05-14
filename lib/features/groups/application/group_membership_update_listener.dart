import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

const groupMembershipUpdateMessageType = 'group_membership_update';

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
  }) : _stream = groupMembershipUpdateStream,
       _groupRepo = groupRepo,
       _bridge = bridge,
       _groupMessageListener = groupMessageListener;

  final Stream<ChatMessage> _stream;
  final GroupRepository _groupRepo;
  final Bridge _bridge;
  final GroupMessageListener _groupMessageListener;
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

      final replayEnvelopeRaw = relayEnvelopeRaw['message'];
      if (replayEnvelopeRaw is! String || replayEnvelopeRaw.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_MALFORMED',
          details: {'reason': 'missing_replay_message'},
        );
        return;
      }

      final replayEnvelope =
          jsonDecode(replayEnvelopeRaw) as Map<String, dynamic>;
      if (!isGroupOfflineReplayEnvelope(replayEnvelope)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MEMBERSHIP_UPDATE_LISTENER_MALFORMED',
          details: {'reason': 'not_group_replay_envelope'},
        );
        return;
      }

      final plaintext = await decryptGroupOfflineReplayEnvelope(
        bridge: _bridge,
        groupRepo: _groupRepo,
        groupId: groupId,
        envelope: replayEnvelope,
        expectedRelayPeerId: relayEnvelopeRaw['from'] as String?,
      );
      final replayPayload = jsonDecode(plaintext) as Map<String, dynamic>;
      await _groupMessageListener.handleReplayEnvelope(replayPayload);

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
}

String _safeId(String value) {
  return value.length > 10 ? value.substring(0, 10) : value;
}
