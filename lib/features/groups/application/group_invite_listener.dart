import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for group invites.
///
/// Subscribes to the typed group invite stream (from IncomingMessageRouter),
/// calls handleIncomingGroupInvite, and broadcasts joined GroupModels to the
/// UI layer.
class GroupInviteListener {
  final Stream<ChatMessage> groupInviteStream;
  final GroupRepository groupRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final GroupMessageRepository? msgRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;

  StreamSubscription<ChatMessage>? _subscription;
  final _groupJoinedController = StreamController<GroupModel>.broadcast();

  GroupInviteListener({
    required this.groupInviteStream,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
    this.msgRepo,
    this.mediaAttachmentRepo,
  });

  /// Stream of groups that the user has joined via invite.
  Stream<GroupModel> get groupJoinedStream => _groupJoinedController.stream;

  /// Starts listening for incoming group invites.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_LISTENER_START',
      details: {},
    );

    _subscription = groupInviteStream.listen(
      _onMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_LISTENER_STREAM_ERROR',
          details: {'error': error.toString()},
        );
      },
      onDone: () {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_LISTENER_STREAM_DONE',
          details: {},
        );
      },
    );
  }

  /// Stops listening.
  void stop() {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_LISTENER_STOP',
      details: {},
    );

    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _groupJoinedController.close();
  }

  /// Decodes an inbox message from the relay's envelope format.
  static Map<String, dynamic> _decodeInboxMessage(
    Map<String, dynamic> envelope,
    String fallbackGroupId,
  ) {
    final messageStr = envelope['message'];
    if (messageStr is String && messageStr.isNotEmpty) {
      try {
        return jsonDecode(messageStr) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (envelope.containsKey('senderId')) {
      return envelope;
    }
    return {
      'groupId': fallbackGroupId,
      'senderId': envelope['from'] as String? ?? '',
      'senderUsername': '',
      'keyEpoch': 0,
      'text': messageStr?.toString() ?? '',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Drains offline inbox for a single group after joining via invite.
  Future<void> _drainGroupInbox(String groupId) async {
    final repo = msgRepo;
    if (repo == null) return;

    try {
      const pageSize = 50;
      var cursor = '';
      var totalMessages = 0;

      do {
        final page = await callGroupInboxRetrieveWithCursor(
          bridge,
          groupId,
          cursor,
          pageSize,
        );

        for (final msg in page.messages) {
          // The relay returns {from, message, timestamp} where `message`
          // is a JSON-encoded string with the actual message payload.
          final payload = _decodeInboxMessage(msg, groupId);
          final mediaRaw = payload['media'] as List<dynamic>?;
          final media = mediaRaw?.cast<Map<String, dynamic>>();
          await handleIncomingGroupMessage(
            groupRepo: groupRepo,
            msgRepo: repo,
            groupId: payload['groupId'] as String? ?? groupId,
            senderId: payload['senderId'] as String? ?? '',
            senderUsername: payload['senderUsername'] as String? ?? '',
            keyEpoch: payload['keyEpoch'] as int? ?? 0,
            text: payload['text'] as String? ?? '',
            timestamp:
                payload['timestamp'] as String? ??
                DateTime.now().toUtc().toIso8601String(),
            messageId: payload['messageId'] as String?,
            quotedMessageId: payload['quotedMessageId'] as String?,
            media: media,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
        }

        totalMessages += page.messages.length;
        cursor = page.cursor;
      } while (cursor.isNotEmpty);

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DRAIN_INBOX_DONE',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'messageCount': totalMessages,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_DRAIN_INBOX_ERROR',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _onMessage(ChatMessage message) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_LISTENER_MESSAGE_RECEIVED',
      details: {
        'from': message.from.length > 10
            ? message.from.substring(0, 10)
            : message.from,
        'contentLength': message.content.length,
      },
    );

    try {
      // Check if sender is blocked
      final senderPeerId = message.from;
      final senderContact = await contactRepo.getContact(senderPeerId);
      if (senderContact != null && senderContact.isBlocked) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_LISTENER_BLOCKED_REJECT',
          details: {
            'from': senderPeerId.length > 10
                ? senderPeerId.substring(0, 10)
                : senderPeerId,
          },
        );
        return;
      }

      final ownSecretKey = await getOwnMlKemSecretKey();

      final (result, groupId) = await handleIncomingGroupInvite(
        message: message,
        groupRepo: groupRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
      );

      if (result == HandleGroupInviteResult.success && groupId != null) {
        // Drain offline inbox for this group — retrieves messages sent while
        // we were offline. Must happen AFTER callGroupJoinWithConfig so the
        // Go node has already joined the topic.
        await _drainGroupInbox(groupId);

        final group = await groupRepo.getGroup(groupId);
        if (group != null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INVITE_LISTENER_NEW_GROUP',
            details: {
              'groupId': group.id.length > 8
                  ? group.id.substring(0, 8)
                  : group.id,
              'name': group.name,
            },
          );
          _groupJoinedController.add(group);
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
