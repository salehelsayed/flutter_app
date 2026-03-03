import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
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
/// when members are added or removed. These update the local DB and Go topic
/// validator so that messages are accepted/rejected accordingly.
///
/// When the local user is removed from a group, the listener calls
/// [leaveGroup] to unsubscribe from the Go pubsub topic and clean up
/// local data, then emits the groupId on [groupRemovedStream].
class GroupMessageListener {
  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final Bridge? _bridge;
  final Future<String?> Function()? _getSelfPeerId;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();

  GroupMessageListener({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    Bridge? bridge,
    Future<String?> Function()? getSelfPeerId,
  })  : _groupRepo = groupRepo,
        _msgRepo = msgRepo,
        _bridge = bridge,
        _getSelfPeerId = getSelfPeerId;

  /// Stream of new incoming group messages for the UI to listen to.
  Stream<GroupMessage> get groupMessageStream => _messageController.stream;

  /// Stream of group IDs that the local user was removed from.
  Stream<String> get groupRemovedStream => _removedController.stream;

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

  /// Handles a system message (e.g. member_added/member_removed config update).
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
      } else if (sysType == 'members_added') {
        await _handleMembersAdded(groupId, parsed);
      } else if (sysType == 'member_removed') {
        await _handleMemberRemoved(groupId, parsed);
      } else if (sysType == 'key_rotated') {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_KEY_ROTATED',
          details: {
            'groupId':
                groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'newKeyEpoch': parsed['newKeyEpoch'] ?? -1,
          },
        );
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

  /// Handles a members_added (batch) system message.
  ///
  /// Saves all new members to the local DB and updates the Go topic validator
  /// config so that messages from the new members are accepted.
  Future<void> _handleMembersAdded(
    String groupId,
    Map<String, dynamic> parsed,
  ) async {
    final membersList = parsed['members'] as List<dynamic>?;
    if (membersList != null) {
      for (final memberData in membersList) {
        final data = memberData as Map<String, dynamic>;
        final member = GroupMember(
          groupId: groupId,
          peerId: data['peerId'] as String,
          username: data['username'] as String?,
          role: MemberRole.fromValue(data['role'] as String? ?? 'writer'),
          publicKey: data['publicKey'] as String?,
          mlKemPublicKey: data['mlKemPublicKey'] as String?,
          joinedAt: DateTime.now().toUtc(),
        );
        await _groupRepo.saveMember(member);
      }
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
      event: 'GROUP_MESSAGE_LISTENER_MEMBERS_ADDED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'count': membersList?.length ?? 0,
      },
    );
  }

  /// Handles a member_removed system message.
  ///
  /// If the removed member is the local user, calls [leaveGroup] to
  /// unsubscribe from the Go pubsub topic and clean up local data,
  /// then emits on [groupRemovedStream].
  ///
  /// Otherwise, removes the member from the local DB and updates the Go
  /// topic validator config.
  Future<void> _handleMemberRemoved(
    String groupId,
    Map<String, dynamic> parsed,
  ) async {
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final removedPeerId = memberData?['peerId'] as String?;

    // Check if the removed member is self
    if (removedPeerId != null && _getSelfPeerId != null && _bridge != null) {
      final selfPeerId = await _getSelfPeerId!();
      if (selfPeerId != null && selfPeerId == removedPeerId) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED',
          details: {
            'groupId':
                groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          },
        );

        // Leave the group: unsubscribe from topic + clean up local data
        await leaveGroup(
          bridge: _bridge!,
          groupRepo: _groupRepo,
          groupId: groupId,
        );

        // Notify UI that we were removed from this group
        _removedController.add(groupId);
        return;
      }
    }

    // Not self — remove the other member from local DB
    if (removedPeerId != null && removedPeerId.isNotEmpty) {
      await _groupRepo.removeMember(groupId, removedPeerId);
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
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'removedPeerId': removedPeerId ?? '?',
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
    _removedController.close();
  }
}
