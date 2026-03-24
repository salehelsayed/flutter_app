import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

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
  final MediaAttachmentRepository? _mediaAttachmentRepo;
  final MediaFileManager? _mediaFileManager;
  final NotificationService? _notificationService;
  final ActiveConversationTracker? _groupConversationTracker;
  final AppLifecycleState Function()? _getAppLifecycleState;
  final ReactionRepository? _reactionRepo;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();

  GroupMessageListener({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    Bridge? bridge,
    Future<String?> Function()? getSelfPeerId,
    MediaAttachmentRepository? mediaAttachmentRepo,
    MediaFileManager? mediaFileManager,
    NotificationService? notificationService,
    ActiveConversationTracker? groupConversationTracker,
    AppLifecycleState Function()? getAppLifecycleState,
    ReactionRepository? reactionRepo,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _bridge = bridge,
       _getSelfPeerId = getSelfPeerId,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _mediaFileManager = mediaFileManager,
       _notificationService = notificationService,
       _groupConversationTracker = groupConversationTracker,
       _getAppLifecycleState = getAppLifecycleState,
       _reactionRepo = reactionRepo;

  /// Stream of new incoming group messages for the UI to listen to.
  Stream<GroupMessage> get groupMessageStream => _messageController.stream;

  /// Stream of group IDs that the local user was removed from.
  Stream<String> get groupRemovedStream => _removedController.stream;

  /// Stream of incoming group reaction changes for the UI to listen to.
  Stream<ReactionChange> get groupReactionChangeStream =>
      _reactionChangeController.stream;

  /// Starts listening for incoming group messages and optionally reactions.
  void start(
    Stream<Map<String, dynamic>> incomingGroupMessages, {
    Stream<Map<String, dynamic>>? incomingGroupReactions,
  }) {
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

    if (incomingGroupReactions != null) {
      _reactionSubscription = incomingGroupReactions.listen(
        _handleReaction,
        onError: (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_REACTION_LISTENER_STREAM_ERROR',
            details: {'error': error.toString()},
          );
        },
      );
    }
  }

  Future<void> _handleMessage(Map<String, dynamic> data) async {
    try {
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final senderUsername = data['senderUsername'] as String? ?? '';
      final keyEpoch = data['keyEpoch'] as int? ?? 0;
      final text = data['text'] as String? ?? '';
      final timestamp =
          data['timestamp'] as String? ??
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

      final mediaRaw = data['media'] as List<dynamic>?;
      final media = mediaRaw?.cast<Map<String, dynamic>>();
      final wireMessageId = data['messageId'] as String?;
      final wireQuotedMessageId = data['quotedMessageId'] as String?;

      final result = await handleIncomingGroupMessage(
        groupRepo: _groupRepo,
        msgRepo: _msgRepo,
        groupId: groupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
        messageId: wireMessageId,
        quotedMessageId: wireQuotedMessageId,
        media: media,
        mediaAttachmentRepo: _mediaAttachmentRepo,
      );

      if (result != null) {
        _messageController.add(result);

        // Show notification for incoming group messages (skip own messages)
        final selfPeerId = _getSelfPeerId != null
            ? await _getSelfPeerId!()
            : null;
        if (senderId != selfPeerId &&
            _notificationService != null &&
            _groupConversationTracker != null &&
            _getAppLifecycleState != null) {
          final group = await _groupRepo.getGroup(groupId);
          final groupName = group?.name ?? 'Group';
          final notifAttachments = media
              ?.map((m) => MediaAttachment.fromJson(m))
              .toList() ??
              <MediaAttachment>[];
          maybeShowNotification(
            notificationService: _notificationService!,
            conversationTracker: _groupConversationTracker!,
            getAppLifecycleState: _getAppLifecycleState!,
            contactPeerId: 'group:$groupId',
            senderUsername: groupName,
            messageText: '$senderUsername: ${notificationBodyForMessage(text, notifAttachments)}',
          );
        }

        // Fire-and-forget: auto-download media attachments
        if (_bridge != null &&
            _mediaAttachmentRepo != null &&
            _mediaFileManager != null &&
            media != null &&
            media.isNotEmpty) {
          _autoDownloadMedia(result);
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Downloads media attachments for an incoming group message.
  ///
  /// Runs fire-and-forget after the message is emitted. On completion,
  /// re-emits the message so the UI can update with resolved local paths.
  Future<void> _autoDownloadMedia(GroupMessage message) async {
    try {
      final attachments = await _mediaAttachmentRepo!.getAttachmentsForMessage(
        message.id,
      );
      if (attachments.isEmpty) return;

      for (final attachment in attachments) {
        if (attachment.downloadStatus != 'pending') continue;
        try {
          await downloadMedia(
            bridge: _bridge!,
            mediaAttachmentRepo: _mediaAttachmentRepo!,
            mediaFileManager: _mediaFileManager!,
            attachment: attachment,
            contactPeerId: message.groupId,
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_LISTENER_DOWNLOAD_ERROR',
            details: {
              'blobId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'error': e.toString(),
            },
          );
        }
      }

      // Re-emit so the UI refreshes with downloaded media
      _messageController.add(message);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LISTENER_AUTO_DOWNLOAD_ERROR',
        details: {
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'error': e.toString(),
        },
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
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
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
        role: MemberRole.fromValue(memberData['role'] as String? ?? 'writer'),
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
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
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

  /// Handles an incoming group reaction event from the bridge.
  Future<void> _handleReaction(Map<String, dynamic> data) async {
    try {
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final reactionJson = data['reaction'] as String? ?? '';

      if (groupId.isEmpty || senderId.isEmpty || reactionJson.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REACTION_LISTENER_MALFORMED',
          details: {'groupId': groupId, 'senderId': senderId},
        );
        return;
      }

      if (_reactionRepo == null) return;

      final (result, change) = await handleIncomingGroupReaction(
        groupRepo: _groupRepo,
        reactionRepo: _reactionRepo!,
        groupId: groupId,
        senderId: senderId,
        reactionJson: reactionJson,
      );

      if (result == HandleGroupReactionResult.success && change != null) {
        _reactionChangeController.add(change);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
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
    _reactionSubscription?.cancel();
    _reactionSubscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
    _removedController.close();
    _reactionChangeController.close();
  }
}
