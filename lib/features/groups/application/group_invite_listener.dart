import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/on_join_metadata_resync_flag.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_invite_identity_callbacks.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_decline_ack.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_config_resync_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_decline_ack_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

typedef ScheduleGroupInviteRetirement =
    void Function({required String groupId, required String inviteId});

typedef PresentPendingGroupInviteNotification =
    Future<void> Function(PendingGroupInvite invite);

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
  final Future<GroupInviteLocalIdentitySnapshot> Function()?
  loadOwnInviteIdentity;
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
  final ScheduleGroupInviteRetirement? scheduleGroupInviteRetirement;
  final PresentPendingGroupInviteNotification?
  presentPendingGroupInviteNotification;

  /// Inviter-side per-peer delivery-attempt store, used to flip a row to
  /// `declined` when an inbound decline-ack arrives. Null when not wired.
  final GroupInviteDeliveryAttemptRepository? deliveryRepo;

  /// On-join metadata resync (finding D), all null/false unless wired + flag on.
  final P2PService? p2pService;
  final Future<IdentityModel?> Function()? loadOwnIdentity;
  final DownloadGroupAvatarFn? downloadGroupAvatarFn;
  final bool onJoinMetadataResyncEnabled;
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
    this.loadOwnInviteIdentity,
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
    this.scheduleGroupInviteRetirement,
    this.presentPendingGroupInviteNotification,
    this.deliveryRepo,
    this.p2pService,
    this.loadOwnIdentity,
    this.downloadGroupAvatarFn,
    this.onJoinMetadataResyncEnabled = kOnJoinMetadataResyncEnabled,
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

  Future<void> waitForIdle() => _messageProcessing;

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

      final useIdentitySnapshot = loadOwnInviteIdentity != null;
      final ownInviteIdentity = useIdentitySnapshot
          ? await loadOwnInviteIdentity!()
          : null;
      final ownSecretKey = useIdentitySnapshot
          ? ownInviteIdentity!.mlKemSecretKey
          : await getOwnMlKemSecretKey();

      // On-join metadata resync (finding D) — most-specific discriminators
      // first, flag-gated. config:response applies; config:request responds.
      if (onJoinMetadataResyncEnabled) {
        if (GroupConfigResyncEnvelope.isResponse(message.content)) {
          await handleIncomingGroupConfigResponse(
            message: message,
            groupRepo: groupRepo,
            bridge: bridge,
            ownMlKemSecretKey: ownSecretKey,
            downloadGroupAvatarFn: downloadGroupAvatarFn,
            now: now().toUtc(),
          );
          return;
        }
        if (GroupConfigResyncEnvelope.isRequest(message.content)) {
          final p2p = p2pService;
          if (p2p != null) {
            await handleIncomingGroupConfigRequest(
              message: message,
              groupRepo: groupRepo,
              p2pService: p2p,
              bridge: bridge,
              ownIdentity: await loadOwnIdentity?.call(),
              ownMlKemSecretKey: ownSecretKey,
              now: now().toUtc(),
            );
          }
          return;
        }
      }

      final isRevocation =
          GroupInviteRevocationPayload.parseEncryptedEnvelope(
            message.content,
          ) !=
          null;
      if (isRevocation) {
        final ownPeerId = useIdentitySnapshot
            ? ownInviteIdentity!.accountPeerId
            : await getOwnPeerId?.call();
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

      final isDeclineAck =
          GroupInviteDeclineAckPayload.parseEncryptedEnvelope(
            message.content,
          ) !=
          null;
      if (isDeclineAck) {
        await handleIncomingGroupInviteDeclineAck(
          message: message,
          deliveryRepo: deliveryRepo,
          bridge: bridge,
          contactRepo: contactRepo,
          ownMlKemSecretKey: ownSecretKey,
          now: now().toUtc(),
        );
        return;
      }

      final ownPeerId = useIdentitySnapshot
          ? ownInviteIdentity!.accountPeerId
          : await getOwnPeerId?.call();
      final ownDeviceId = useIdentitySnapshot
          ? ownInviteIdentity!.deviceId
          : await getOwnDeviceId?.call();
      final ownTransportPeerId = useIdentitySnapshot
          ? ownInviteIdentity!.transportPeerId
          : await getOwnTransportPeerId?.call();
      final ownMlKemPublicKey = useIdentitySnapshot
          ? ownInviteIdentity!.mlKemPublicKey
          : await getOwnMlKemPublicKey?.call();
      final ownKeyPackageId = useIdentitySnapshot
          ? ownInviteIdentity!.keyPackageId
          : await getOwnKeyPackageId?.call();
      final ownKeyPackagePublicMaterial = useIdentitySnapshot
          ? ownInviteIdentity!.keyPackagePublicMaterial
          : await getOwnKeyPackagePublicMaterial?.call();
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
        final presentNotification = presentPendingGroupInviteNotification;
        if (presentNotification != null) {
          // Native publication is downstream of durable invite custody. Do not
          // let a stalled platform callback block later invite, revocation,
          // decline-ack, or config messages in the serialized listener queue.
          unawaited(
            _presentPendingInviteNotification(
              presentNotification,
              pendingInvite,
            ),
          );
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

  Future<void> _presentPendingInviteNotification(
    PresentPendingGroupInviteNotification presentNotification,
    PendingGroupInvite pendingInvite,
  ) async {
    try {
      await presentNotification(pendingInvite);
    } catch (error) {
      // Publication failure must never undo persistence or suppress the UI
      // refresh signal emitted before this detached effect.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_INVITE_LISTENER_NOTIFICATION_ERROR',
        details: {
          'groupId': pendingInvite.groupId.length > 8
              ? pendingInvite.groupId.substring(0, 8)
              : pendingInvite.groupId,
          'inviteId': pendingInvite.inviteId.length > 8
              ? pendingInvite.inviteId.substring(0, 8)
              : pendingInvite.inviteId,
          'errorType': error.runtimeType.toString(),
        },
      );
    }
  }
}

DateTime _defaultNow() => DateTime.now().toUtc();
