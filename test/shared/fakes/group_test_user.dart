import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart'
    as group_react;
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../core/bridge/fake_bridge.dart';
import 'fake_group_pubsub_network.dart';
import 'in_memory_media_attachment_repository.dart';
import 'in_memory_group_message_repository.dart';
import 'in_memory_group_repository.dart';

/// Encapsulates the full per-user group stack for multi-user integration tests.
class GroupTestUser {
  final String peerId;
  final String username;
  final String publicKey;
  final String privateKey;
  final FakeBridge bridge;
  final InMemoryGroupRepository groupRepo;
  final InMemoryGroupMessageRepository msgRepo;
  final InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  final GroupMessageListener groupMessageListener;
  final ReactionRepository? reactionRepo;
  final FakeGroupPubSubNetwork _network;
  final StreamController<Map<String, dynamic>> _incomingController;
  final StreamController<Map<String, dynamic>> _incomingReactionController;

  GroupTestUser._({
    required this.peerId,
    required this.username,
    required this.publicKey,
    required this.privateKey,
    required this.bridge,
    required this.groupRepo,
    required this.msgRepo,
    required this.mediaAttachmentRepo,
    required this.groupMessageListener,
    required this.reactionRepo,
    required FakeGroupPubSubNetwork network,
    required StreamController<Map<String, dynamic>> incomingController,
    required StreamController<Map<String, dynamic>> incomingReactionController,
  }) : _network = network,
       _incomingController = incomingController,
       _incomingReactionController = incomingReactionController;

  factory GroupTestUser.create({
    required String peerId,
    required String username,
    required FakeGroupPubSubNetwork network,
    FakeBridge? bridge,
    ReactionRepository? reactionRepo,
    NotificationService? notificationService,
    ActiveConversationTracker? groupConversationTracker,
    AppLifecycleState Function()? getAppLifecycleState,
  }) {
    final effectiveBridge = bridge ?? FakeBridge();
    final groupRepo = InMemoryGroupRepository();
    final msgRepo = InMemoryGroupMessageRepository();
    final mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    final controller = network.registerPeer(peerId);
    final reactionController = network.registerReactionPeer(peerId);

    final listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: effectiveBridge,
      getSelfPeerId: () async => peerId,
      mediaAttachmentRepo: mediaAttachmentRepo,
      notificationService: notificationService,
      groupConversationTracker: groupConversationTracker,
      getAppLifecycleState: getAppLifecycleState,
      reactionRepo: reactionRepo,
    );

    return GroupTestUser._(
      peerId: peerId,
      username: username,
      publicKey: 'pk-$peerId',
      privateKey: 'sk-$peerId',
      bridge: effectiveBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      groupMessageListener: listener,
      reactionRepo: reactionRepo,
      network: network,
      incomingController: controller,
      incomingReactionController: reactionController,
    );
  }

  // ---- Actions ----

  /// Starts the listener (subscribes to the incoming stream from FakeGroupPubSubNetwork).
  void start() {
    groupMessageListener.start(
      _incomingController.stream,
      incomingGroupReactions: _incomingReactionController.stream,
    );
  }

  /// Creates a group: saves to local repo, subscribes on network, returns the group.
  Future<GroupModel> createGroup({
    required String groupId,
    required String name,
    GroupType type = GroupType.chat,
    String? description,
  }) async {
    final now = DateTime.now().toUtc();
    final group = GroupModel(
      id: groupId,
      name: name,
      type: type,
      topicName: 'topic-$groupId',
      description: description,
      createdAt: now,
      createdBy: peerId,
      myRole: GroupRole.admin,
    );
    await groupRepo.saveGroup(group);

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: peerId,
        username: username,
        role: MemberRole.admin,
        publicKey: publicKey,
        joinedAt: now,
      ),
    );

    _network.subscribe(groupId, peerId);

    return group;
  }

  /// Adds another user to a group (admin action).
  ///
  /// Saves the member to both admin's and invitee's repos, subscribes invitee
  /// on the network.
  Future<void> addMember({
    required String groupId,
    required GroupTestUser invitee,
  }) async {
    final now = DateTime.now().toUtc();

    // Save member to admin's local repo
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: invitee.peerId,
        username: invitee.username,
        role: MemberRole.writer,
        publicKey: invitee.publicKey,
        joinedAt: now,
      ),
    );

    // Save group + members to invitee's repos (simulates invite acceptance)
    final group = await groupRepo.getGroup(groupId);
    if (group != null) {
      await invitee.groupRepo.saveGroup(
        group.copyWith(myRole: GroupRole.member),
      );

      final members = await groupRepo.getMembers(groupId);
      for (final m in members) {
        await invitee.groupRepo.saveMember(m);
      }
    }

    // Subscribe invitee on the network
    _network.subscribe(groupId, invitee.peerId);
  }

  /// Sends a message to a group (publishes via network fan-out + saves locally).
  Future<GroupMessage?> sendGroupMessage({
    required String groupId,
    required String text,
    String? quotedMessageId,
  }) async {
    final now = DateTime.now().toUtc();
    final latestKey = await groupRepo.getLatestKey(groupId);
    final keyEpoch = latestKey?.keyGeneration ?? 0;
    final messageId = '${peerId}_${now.millisecondsSinceEpoch}';

    final message = GroupMessage(
      id: messageId,
      groupId: groupId,
      senderPeerId: peerId,
      senderUsername: username,
      text: text,
      timestamp: now,
      quotedMessageId: quotedMessageId,
      keyGeneration: keyEpoch,
      status: 'sent',
      isIncoming: false,
      createdAt: now,
    );
    await msgRepo.saveMessage(message);

    final envelope = {
      'groupId': groupId,
      'senderId': peerId,
      'senderUsername': username,
      'keyEpoch': keyEpoch,
      'text': text,
      'timestamp': now.toIso8601String(),
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
    };
    await _network.publish(groupId, peerId, envelope);

    return message;
  }

  /// Sends through the real bridge-backed use case and mirrors successful
  /// live publish delivery into the fake pubsub network.
  Future<(group_send.SendGroupMessageResult, GroupMessage?)>
  sendGroupMessageViaBridge({
    required String groupId,
    required String text,
    String? quotedMessageId,
    List<MediaAttachment>? mediaAttachments,
    int? publishTopicPeersOverride,
  }) async {
    final now = DateTime.now().toUtc();
    final messageId = '${peerId}_${now.millisecondsSinceEpoch}';
    final topicPeers =
        publishTopicPeersOverride ??
        _network
            .getSubscribers(groupId)
            .where((subscriber) => subscriber != peerId)
            .length;

    final previousPublishResponse = bridge.responses['group:publish'];
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': messageId,
      'topicPeers': topicPeers,
    };
    try {
      final (result, message) = await group_send.sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: text,
        senderPeerId: peerId,
        senderPublicKey: publicKey,
        senderPrivateKey: privateKey,
        senderUsername: username,
        messageId: messageId,
        timestamp: now,
        quotedMessageId: quotedMessageId,
        mediaAttachments: mediaAttachments,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (result == group_send.SendGroupMessageResult.success &&
          message != null) {
        final publishRaw = bridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;

        final envelope = <String, dynamic>{
          'groupId': groupId,
          'senderId': peerId,
          'senderUsername': username,
          'keyEpoch': message.keyGeneration,
          'text': publishPayload['text'] as String? ?? text,
          'timestamp': message.timestamp.toUtc().toIso8601String(),
          'messageId': publishPayload['messageId'] as String? ?? message.id,
          if (quotedMessageId != null && quotedMessageId.isNotEmpty)
            'quotedMessageId': quotedMessageId,
          if (publishPayload['media'] is List<dynamic>)
            'media': publishPayload['media'] as List<dynamic>,
        };
        await _network.publish(groupId, peerId, envelope);
      }

      return (result, message);
    } finally {
      if (previousPublishResponse == null) {
        bridge.responses.remove('group:publish');
      } else {
        bridge.responses['group:publish'] = previousPublishResponse;
      }
    }
  }

  /// Sends through the real bridge-backed reaction use case and mirrors
  /// successful live publish delivery into the fake pubsub reaction stream.
  Future<(group_react.SendGroupReactionResult, MessageReaction?)>
  sendGroupReactionViaBridge({
    required String groupId,
    required String messageId,
    required String emoji,
  }) async {
    final repo = reactionRepo;
    if (repo == null) {
      throw StateError('sendGroupReactionViaBridge requires a reactionRepo');
    }

    final previousPublishResponse = bridge.responses['group:publishReaction'];
    bridge.responses['group:publishReaction'] = {'ok': true};
    try {
      final (result, reaction) = await group_react.sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        reactionRepo: repo,
        groupId: groupId,
        messageId: messageId,
        emoji: emoji,
        senderPeerId: peerId,
        senderPublicKey: publicKey,
        senderPrivateKey: privateKey,
      );

      if (result == group_react.SendGroupReactionResult.success &&
          reaction != null) {
        final publishRaw = bridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publishReaction',
        );
        final publishPayload =
            (jsonDecode(publishRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;

        await _network.publishReaction(groupId, peerId, {
          'groupId': groupId,
          'senderId': peerId,
          'reaction':
              publishPayload['reactionPayload'] as String? ??
              jsonEncode({
                'id': reaction.id,
                'messageId': reaction.messageId,
                'emoji': reaction.emoji,
                'action': 'add',
                'senderPeerId': reaction.senderPeerId,
                'timestamp': reaction.timestamp,
              }),
        });
      }

      return (result, reaction);
    } finally {
      if (previousPublishResponse == null) {
        bridge.responses.remove('group:publishReaction');
      } else {
        bridge.responses['group:publishReaction'] = previousPublishResponse;
      }
    }
  }

  /// Removes a member from a group (admin action).
  ///
  /// Removes from local repo + broadcasts member_removed system message +
  /// unsubscribes the removed member from the network.
  Future<void> removeMember({
    required String groupId,
    required String memberPeerId,
    required String memberUsername,
  }) async {
    await groupRepo.removeMember(groupId, memberPeerId);
    final removedAt = DateTime.now().toUtc();
    await msgRepo.saveMessage(
      buildMemberRemovedTimelineMessage(
        groupId: groupId,
        removedPeerId: memberPeerId,
        removedUsername: memberUsername,
        senderId: peerId,
        senderUsername: username,
        eventAt: removedAt,
      ),
    );

    final group = await groupRepo.getGroup(groupId);
    final remainingMembers = await groupRepo.getMembers(groupId);

    final groupConfig = {
      'name': group!.name,
      'groupType': group.type.toValue(),
      if (group.description != null) 'description': group.description,
      'members': remainingMembers
          .map(
            (m) => {
              'peerId': m.peerId,
              'username': m.username,
              'role': m.role.toValue(),
              'publicKey': m.publicKey,
            },
          )
          .toList(),
      'createdBy': group.createdBy,
      'createdAt': group.createdAt.toUtc().toIso8601String(),
    };

    final sysText = jsonEncode({
      '__sys': 'member_removed',
      'member': {'peerId': memberPeerId, 'username': memberUsername},
      'removedAt': removedAt.toIso8601String(),
      'groupConfig': groupConfig,
    });

    final envelope = {
      'groupId': groupId,
      'senderId': peerId,
      'senderUsername': username,
      'keyEpoch': 0,
      'text': sysText,
      'timestamp': removedAt.toIso8601String(),
    };
    await _network.publish(groupId, peerId, envelope);

    _network.unsubscribe(groupId, memberPeerId);
  }

  /// Broadcasts a member_added system message to existing group members.
  Future<void> broadcastMemberAdded({
    required String groupId,
    required GroupTestUser newMember,
  }) async {
    final group = await groupRepo.getGroup(groupId);
    final allMembers = await groupRepo.getMembers(groupId);

    final groupConfig = {
      'name': group!.name,
      'groupType': group.type.toValue(),
      if (group.description != null) 'description': group.description,
      'members': allMembers
          .map(
            (m) => {
              'peerId': m.peerId,
              'username': m.username,
              'role': m.role.toValue(),
              'publicKey': m.publicKey,
            },
          )
          .toList(),
      'createdBy': group.createdBy,
      'createdAt': group.createdAt.toUtc().toIso8601String(),
    };

    final sysText = jsonEncode({
      '__sys': 'member_added',
      'member': {
        'peerId': newMember.peerId,
        'username': newMember.username,
        'role': 'writer',
        'publicKey': newMember.publicKey,
      },
      'groupConfig': groupConfig,
    });

    final envelope = {
      'groupId': groupId,
      'senderId': peerId,
      'senderUsername': username,
      'keyEpoch': 0,
      'text': sysText,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    await _network.publish(groupId, peerId, envelope);
  }

  /// Loads all messages for a group from the local repo.
  Future<List<GroupMessage>> loadGroupMessages(String groupId) async {
    return msgRepo.getMessagesPage(groupId);
  }

  /// Leaves a group voluntarily.
  Future<void> leaveGroup(String groupId) async {
    _network.unsubscribe(groupId, peerId);
    await groupRepo.removeAllMembers(groupId);
    await groupRepo.removeAllKeys(groupId);
    await groupRepo.deleteGroup(groupId);
  }

  void dispose() {
    groupMessageListener.dispose();
    _network.unregisterPeer(peerId);
  }
}
