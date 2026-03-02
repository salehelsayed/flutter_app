import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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

  StreamSubscription<ChatMessage>? _subscription;
  final _groupJoinedController = StreamController<GroupModel>.broadcast();

  GroupInviteListener({
    required this.groupInviteStream,
    required this.groupRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
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
