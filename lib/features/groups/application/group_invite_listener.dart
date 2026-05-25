import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

/// Listener service that monitors P2P messages for group invites.
///
/// Subscribes to the typed group invite stream (from IncomingMessageRouter),
/// calls handleIncomingGroupInvite, and broadcasts joined GroupModels to the
/// UI layer.
class GroupInviteListener {
  final Stream<ChatMessage> groupInviteStream;
  final GroupRepository groupRepo;
  final PendingGroupInviteRepository pendingInviteRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final Future<String?> Function() getOwnMlKemSecretKey;
  final Future<String?> Function()? getOwnPeerId;
  final Future<String?> Function()? getOwnDeviceId;
  final Future<String?> Function()? getOwnTransportPeerId;
  final Future<String?> Function()? getOwnMlKemPublicKey;
  final Future<String?> Function()? getOwnKeyPackageId;
  final Future<String?> Function()? getOwnKeyPackagePublicMaterial;
  final GroupMessageRepository? msgRepo;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final AppendGroupEventLogEntry? appendGroupEventLogEntry;
  final DateTime Function() now;

  StreamSubscription<ChatMessage>? _subscription;
  Future<void> _messageProcessing = Future<void>.value();
  final _groupJoinedController = StreamController<GroupModel>.broadcast();
  final _pendingInviteController =
      StreamController<PendingGroupInvite>.broadcast();

  GroupInviteListener({
    required this.groupInviteStream,
    required this.groupRepo,
    required this.pendingInviteRepo,
    required this.contactRepo,
    required this.bridge,
    required this.getOwnMlKemSecretKey,
    this.getOwnPeerId,
    this.getOwnDeviceId,
    this.getOwnTransportPeerId,
    this.getOwnMlKemPublicKey,
    this.getOwnKeyPackageId,
    this.getOwnKeyPackagePublicMaterial,
    this.msgRepo,
    this.mediaAttachmentRepo,
    this.appendGroupEventLogEntry,
    DateTime Function()? now,
  }) : now = now ?? _defaultNow;

  /// Stream of groups that the user has joined via invite.
  Stream<GroupModel> get groupJoinedStream => _groupJoinedController.stream;

  /// Stream of newly received pending invites for UI refresh.
  Stream<PendingGroupInvite> get pendingInviteStream =>
      _pendingInviteController.stream;

  /// Starts listening for incoming group invites.
  void start() {
    if (_subscription != null) return;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_LISTENER_START',
      details: {},
    );

    _subscription = groupInviteStream.listen(
      _enqueueMessage,
      onError: (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_LISTENER_ERROR',
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
    _pendingInviteController.close();
  }

  void _enqueueMessage(ChatMessage message) {
    _messageProcessing = _messageProcessing
        .catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INVITE_LISTENER_ERROR',
            details: {'error': error.toString()},
          );
        })
        .then((_) => _onMessage(message))
        .catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INVITE_LISTENER_ERROR',
            details: {'error': error.toString()},
          );
        });
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
      final isRevocation =
          GroupInviteRevocationPayload.parseEncryptedEnvelope(
            message.content,
          ) !=
          null;
      if (isRevocation) {
        final ownPeerId = await getOwnPeerId?.call();
        final (
          result,
          removedPendingInvite,
        ) = await handleIncomingGroupInviteRevocation(
          message: message,
          pendingInviteRepo: pendingInviteRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: ownSecretKey,
          ownPeerId: ownPeerId,
          now: now().toUtc(),
        );

        if (result == HandleGroupInviteRevocationResult.revoked &&
            removedPendingInvite != null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_INVITE_LISTENER_PENDING_REVOKED',
            details: {
              'groupId': removedPendingInvite.groupId.length > 8
                  ? removedPendingInvite.groupId.substring(0, 8)
                  : removedPendingInvite.groupId,
            },
          );
          _pendingInviteController.add(removedPendingInvite);
        }
        return;
      }

      final ownPeerId = await getOwnPeerId?.call();
      final ownDeviceId = await getOwnDeviceId?.call();
      final ownTransportPeerId = await getOwnTransportPeerId?.call();
      final ownMlKemPublicKey = await getOwnMlKemPublicKey?.call();
      final ownKeyPackageId = await getOwnKeyPackageId?.call();
      final ownKeyPackagePublicMaterial = await getOwnKeyPackagePublicMaterial
          ?.call();
      final receivedAt = now().toUtc();
      final (result, pendingInvite) = await storeIncomingPendingGroupInvite(
        message: message,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: ownSecretKey,
        ownPeerId: ownPeerId,
        ownDeviceId: ownDeviceId,
        ownTransportPeerId: ownTransportPeerId,
        ownMlKemPublicKey: ownMlKemPublicKey,
        ownKeyPackageId: ownKeyPackageId,
        ownKeyPackagePublicMaterial: ownKeyPackagePublicMaterial,
        receivedAt: receivedAt,
      );

      if (result == StorePendingGroupInviteResult.storedPending &&
          pendingInvite != null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_INVITE_LISTENER_PENDING_STORED',
          details: {
            'groupId': pendingInvite.groupId.length > 8
                ? pendingInvite.groupId.substring(0, 8)
                : pendingInvite.groupId,
            'name': pendingInvite.groupName,
          },
        );
        _pendingInviteController.add(pendingInvite);
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

DateTime _defaultNow() => DateTime.now().toUtc();
