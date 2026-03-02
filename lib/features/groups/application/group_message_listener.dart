import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Listener service that monitors incoming group messages.
///
/// Subscribes to a typed group message stream (from IncomingMessageRouter),
/// calls handleIncomingGroupMessage, and broadcasts persisted GroupMessages
/// to the UI layer.
///
/// Also handles system messages (e.g. config updates) published by the admin
/// when new members are added. These update the local DB and Go topic validator
/// so that messages from the new member are accepted.
class GroupMessageListener {
  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final Bridge? _bridge;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  final _messageController = StreamController<GroupMessage>.broadcast();

  GroupMessageListener({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    Bridge? bridge,
  })  : _groupRepo = groupRepo,
        _msgRepo = msgRepo,
        _bridge = bridge;

  /// Stream of new incoming group messages for the UI to listen to.
  Stream<GroupMessage> get groupMessageStream => _messageController.stream;

  /// Starts listening for incoming group messages.
  void start(Stream<Map<String, dynamic>> incomingGroupMessages) {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_START',
      details: {},
    );

    _subscription = incomingGroupMessages.listen(
      _handleMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  Future<void> _handleMessage(Map<String, dynamic> data) async {
    try {
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final senderUsername = data['senderUsername'] as String? ?? '';
      final keyEpoch = data['keyEpoch'] as int? ?? 0;
      final text = data['text'] as String? ?? '';
      final timestamp = data['timestamp'] as String? ??
          DateTime.now().toUtc().toIso8601String();

      if (groupId.isEmpty || senderId.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_MALFORMED',
          details: {'groupId': groupId, 'senderId': senderId},
        );
        return;
      }

      // Check for system message (config updates from admin)
      if (text.startsWith('{"__sys":') && _bridge != null) {
        await _handleSystemMessage(groupId, text);
        return;
      }

      final result = await handleIncomingGroupMessage(
        groupRepo: _groupRepo,
        msgRepo: _msgRepo,
        groupId: groupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
      );

      if (result != null) {
        _messageController.add(result);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Handles a system message (e.g. member_added config update).
  ///
  /// System messages are published by the admin via the group pubsub topic
  /// to notify existing members of config changes. They are not displayed
  /// as regular chat messages.
  Future<void> _handleSystemMessage(String groupId, String text) async {
    try {
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final sysType = parsed['__sys'] as String?;

      if (sysType == 'member_added') {
        await _handleMemberAdded(groupId, parsed);
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_UNKNOWN_SYS_TYPE',
          details: {'type': sysType ?? 'null'},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SYS_MSG_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Handles a member_added system message.
  ///
  /// Saves the new member to the local DB and updates the Go topic validator
  /// config so that messages from the new member are accepted.
  Future<void> _handleMemberAdded(
    String groupId,
    Map<String, dynamic> parsed,
  ) async {
    // Save new member to local DB
    final memberData = parsed['member'] as Map<String, dynamic>?;
    if (memberData != null) {
      final member = GroupMember(
        groupId: groupId,
        peerId: memberData['peerId'] as String,
        username: memberData['username'] as String?,
        role:
            MemberRole.fromValue(memberData['role'] as String? ?? 'writer'),
        publicKey: memberData['publicKey'] as String?,
        mlKemPublicKey: memberData['mlKemPublicKey'] as String?,
        joinedAt: DateTime.now().toUtc(),
      );
      await _groupRepo.saveMember(member);
    }

    // Update Go topic validator config
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null && _bridge != null) {
      await callGroupUpdateConfig(
        _bridge!,
        groupId: groupId,
        groupConfig: groupConfig,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_ADDED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': (memberData?['peerId'] as String?) ?? '?',
      },
    );
  }

  /// Stops listening for messages.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
  }
}
