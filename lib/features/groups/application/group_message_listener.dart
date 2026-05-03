import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/trusted_private_group_system_event.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
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
  final RecentRemoteNotificationGate _remoteNotificationGate;
  final ReactionRepository? _reactionRepo;
  final DownloadGroupAvatarFn _downloadGroupAvatarFn;
  final AppendGroupEventLogEntry? _appendGroupEventLogEntry;
  final Stream<Map<String, dynamic>>? _groupDiagnosticEvents;
  final GroupPendingKeyRepairRepository? _pendingKeyRepairRepo;
  final RequestGroupKeyRepair _requestGroupKeyRepair;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _diagnosticSubscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();
  final Map<String, Future<void>> _groupConfigWorkQueue = {};
  final Map<String, String> _acceptedSignedTransitionAuditHashesBySourceId = {};
  String? _cachedSelfPeerId;
  var _hasResolvedSelfPeerId = false;
  Future<String?>? _selfPeerIdLoadFuture;

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
    RecentRemoteNotificationGate? remoteNotificationGate,
    ReactionRepository? reactionRepo,
    DownloadGroupAvatarFn? downloadGroupAvatarFn,
    AppendGroupEventLogEntry? appendGroupEventLogEntry,
    Stream<Map<String, dynamic>>? groupDiagnosticEvents,
    GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
    RequestGroupKeyRepair? requestGroupKeyRepair,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _bridge = bridge,
       _getSelfPeerId = getSelfPeerId,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _mediaFileManager = mediaFileManager,
       _notificationService = notificationService,
       _groupConversationTracker = groupConversationTracker,
       _getAppLifecycleState = getAppLifecycleState,
       _remoteNotificationGate =
           remoteNotificationGate ?? recentRemoteNotificationGate,
       _reactionRepo = reactionRepo,
       _downloadGroupAvatarFn = downloadGroupAvatarFn ?? downloadGroupAvatar,
       _appendGroupEventLogEntry = appendGroupEventLogEntry,
       _groupDiagnosticEvents = groupDiagnosticEvents,
       _pendingKeyRepairRepo = pendingKeyRepairRepo,
       _requestGroupKeyRepair =
           requestGroupKeyRepair ?? emitGroupKeyRepairRequest;

  /// Stream of new incoming group messages for the UI to listen to.
  Stream<GroupMessage> get groupMessageStream => _messageController.stream;

  /// Stream of group IDs that the local user was removed from.
  Stream<String> get groupRemovedStream => _removedController.stream;

  /// Stream of incoming group reaction changes for the UI to listen to.
  Stream<ReactionChange> get groupReactionChangeStream =>
      _reactionChangeController.stream;

  AppendGroupEventLogEntry? get appendGroupEventLogEntry =>
      _appendGroupEventLogEntry;

  /// Replays one already-decoded group envelope through the live listener path.
  ///
  /// Offline inbox recovery uses this so replayed system payloads can trigger
  /// the same cleanup and UI streams as live listener traffic.
  Future<void> handleReplayEnvelope(
    Map<String, dynamic> data, {
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
  }) {
    return _handleMessage(
      data,
      msgRepoOverride: msgRepoOverride,
      rethrowOnError: rethrowOnError,
    );
  }

  Future<String?> _resolveSelfPeerId() {
    if (_hasResolvedSelfPeerId) {
      return Future<String?>.value(_cachedSelfPeerId);
    }
    if (_selfPeerIdLoadFuture != null) {
      return _selfPeerIdLoadFuture!;
    }

    final loader = _getSelfPeerId == null
        ? Future<String?>.value(null)
        : _getSelfPeerId!();
    _selfPeerIdLoadFuture = loader.then(
      (value) {
        _cachedSelfPeerId = value;
        _hasResolvedSelfPeerId = true;
        _selfPeerIdLoadFuture = null;
        return value;
      },
      onError: (Object error, StackTrace stackTrace) {
        _selfPeerIdLoadFuture = null;
        throw error;
      },
    );
    return _selfPeerIdLoadFuture!;
  }

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

    final diagnostics = _groupDiagnosticEvents;
    if (diagnostics != null && _diagnosticSubscription == null) {
      _diagnosticSubscription = diagnostics.listen(
        _handleGroupDiagnosticEvent,
        onError: (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_DIAGNOSTIC_STREAM_ERROR',
            details: {'error': error.toString()},
          );
        },
      );
    }
  }

  Future<void> _handleGroupDiagnosticEvent(Map<String, dynamic> event) async {
    final pendingRepo = _pendingKeyRepairRepo;
    if (pendingRepo == null) return;
    final placeholder = await queueLiveGroupDecryptionFailureRepair(
      groupRepo: _groupRepo,
      msgRepo: _msgRepo,
      pendingKeyRepairRepo: pendingRepo,
      diagnostic: event,
      requestGroupKeyRepair: _requestGroupKeyRepair,
    );
    if (placeholder != null) {
      _messageController.add(placeholder);
    }
  }

  Future<void> _handleMessage(
    Map<String, dynamic> data, {
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
  }) async {
    try {
      final msgRepo = msgRepoOverride ?? _msgRepo;
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final senderUsername = data['senderUsername'] as String? ?? '';
      final keyEpoch = data['keyEpoch'] as int? ?? 0;
      final text = data['text'] as String? ?? '';
      final transportPeerId =
          data['transportPeerId'] as String? ??
          data['senderDeviceId'] as String?;
      final senderDeviceId = data['senderDeviceId'] as String?;
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

      final wireMessageId = data['messageId'] as String?;

      // Check for system message (config updates from admin)
      if (text.startsWith('{"__sys":') && _bridge != null) {
        await _handleSystemMessage(
          groupId,
          text,
          timestamp,
          senderId: senderId,
          senderUsername: senderUsername,
          senderDeviceId: senderDeviceId,
          transportPeerId: transportPeerId,
          sourceEventId: wireMessageId,
          msgRepo: msgRepo,
          rethrowOnError: rethrowOnError,
        );
        return;
      }

      final mediaRaw = data['media'] as List<dynamic>?;
      final media = mediaRaw?.cast<Map<String, dynamic>>();
      final wireQuotedMessageId = data['quotedMessageId'] as String?;
      final selfPeerId = await _resolveSelfPeerId();

      final result = await handleIncomingGroupMessage(
        groupRepo: _groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        senderId: senderId,
        senderUsername: senderUsername,
        keyEpoch: keyEpoch,
        text: text,
        timestamp: timestamp,
        transportPeerId: transportPeerId,
        senderDeviceId: senderDeviceId,
        selfPeerId: selfPeerId,
        messageId: wireMessageId,
        quotedMessageId: wireQuotedMessageId,
        media: media,
        mediaAttachmentRepo: _mediaAttachmentRepo,
        appendGroupEventLogEntry: _appendGroupEventLogEntry,
      );

      if (result != null) {
        _messageController.add(result);
        final persistedAttachments = _mediaAttachmentRepo == null
            ? <MediaAttachment>[]
            : await _mediaAttachmentRepo.getAttachmentsForMessage(result.id);

        // Show notification for incoming group messages (skip own messages)
        if (senderId != selfPeerId &&
            _notificationService != null &&
            _groupConversationTracker != null &&
            _getAppLifecycleState != null) {
          final group = await _groupRepo.getGroup(groupId);
          final isMuted = group?.isMuted ?? false;
          final groupName = group?.name ?? 'Group';
          if (!isMuted) {
            maybeShowNotification(
              notificationService: _notificationService!,
              conversationTracker: _groupConversationTracker!,
              getAppLifecycleState: _getAppLifecycleState!,
              contactPeerId: 'group:$groupId',
              routePayload: NotificationRouteTarget.group(
                groupId,
                messageId: result.id,
              ).toPayload(),
              senderUsername: groupName,
              messageText:
                  '$senderUsername: ${notificationBodyForMessage(text, persistedAttachments)}',
              messageId: result.id,
              consumeRecentRemoteNotificationAnnouncement:
                  ({required payload, String? messageId}) =>
                      _remoteNotificationGate.consumeIfRecentAnnouncement(
                        payload: payload,
                        messageId: messageId,
                      ),
              backgroundDuplicateGuardDelay: Duration.zero,
            );
          }
        }

        // Fire-and-forget: auto-download media attachments
        if (_bridge != null &&
            _mediaAttachmentRepo != null &&
            _mediaFileManager != null &&
            persistedAttachments.isNotEmpty) {
          _autoDownloadMedia(result);
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
      if (rethrowOnError) rethrow;
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
            enforceGroupMediaPolicy: true,
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
  /// System messages are published over the group topic to notify members of
  /// config changes. Membership events may also materialize durable timeline
  /// rows so the UI can show human-readable history later.
  Future<void> _handleSystemMessage(
    String groupId,
    String text,
    String timestamp, {
    required String senderId,
    required String senderUsername,
    String? senderDeviceId,
    String? transportPeerId,
    String? sourceEventId,
    required GroupMessageRepository msgRepo,
    bool rethrowOnError = false,
  }) async {
    try {
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final sysType = parsed['__sys'] as String?;
      final envelopeEventAt = _parseMembershipEventAt(timestamp);
      final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
      final eventAt = switch (sysType) {
        'member_removed' =>
          _parseMembershipEventAt(parsed['removedAt'] as String?) ??
              envelopeEventAt,
        'group_dissolved' =>
          _parseMembershipEventAt(parsed['dissolvedAt'] as String?) ??
              envelopeEventAt,
        'group_metadata_updated' =>
          _parseMembershipEventAt(parsed['updatedAt'] as String?) ??
              _parseMembershipEventAt(
                groupConfig?['metadataUpdatedAt'] as String?,
              ) ??
              envelopeEventAt,
        'member_banned' ||
        'member_unbanned' ||
        'group_message_deleted' => trustedPrivateSystemEventAt(
          sysType,
          parsed,
          fallback: envelopeEventAt,
        ),
        _ => envelopeEventAt,
      };

      if (!await _isBoundSystemEventSenderDevice(
        groupId: groupId,
        senderId: senderId,
        senderDeviceId: senderDeviceId,
        transportPeerId: transportPeerId,
      )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_UNBOUND_SYSTEM_DEVICE',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
          },
        );
        return;
      }

      if (sysType == 'member_joined' &&
          !await _isAuthorizedJoinEventSender(groupId, senderId, parsed)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_UNAUTHORIZED_JOIN_EVENT',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'type': sysType,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
          },
        );
        return;
      }

      if (_requiresMembershipEventAuthorization(sysType) &&
          !await _isAuthorizedMembershipEventSender(
            groupId,
            senderId,
            sysType: sysType,
            parsed: parsed,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_UNAUTHORIZED_MEMBERSHIP_EVENT',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'type': sysType,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
          },
        );
        return;
      }

      final transitionSourceEventId =
          signedGroupTransitionAuditSourceEventId(parsed) ??
          (sourceEventId != null && sourceEventId.isNotEmpty
              ? sourceEventId
              : 'system:$groupId:$senderId:$sysType:$timestamp:${jsonEncode(parsed)}');
      SignedGroupTransitionAuditVerification? signedTransitionAudit;
      if (_shouldRequireSignedTransitionAudit(sysType, parsed)) {
        final signedAuditHash = signedGroupTransitionAuditHashFromPayload(
          parsed,
        );
        final acceptedHash =
            _acceptedSignedTransitionAuditHashesBySourceId[transitionSourceEventId];
        if (acceptedHash != null) {
          if (signedAuditHash != null && acceptedHash == signedAuditHash) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_DUPLICATE_IGNORED',
              details: {
                'groupId': groupId.length > 8
                    ? groupId.substring(0, 8)
                    : groupId,
                'type': sysType ?? 'null',
              },
            );
            return;
          }
          _emitSignedTransitionAuditRejected(
            groupId,
            sysType: sysType,
            reason: 'conflicting_replay',
          );
          return;
        }

        final actorPublicKey = await _resolveActorSigningPublicKey(
          groupId: groupId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          transportPeerId: transportPeerId,
        );
        final preTransitionStateHash = await buildGroupTransitionStateHash(
          _groupRepo,
          groupId,
        );
        final auditCheck = await verifyGroupTransitionAudit(
          bridge: _bridge!,
          containerPayload: parsed,
          groupId: groupId,
          transitionType: sysType ?? '',
          sourceEventId: transitionSourceEventId,
          eventAt: eventAt ?? envelopeEventAt ?? DateTime.now().toUtc(),
          actorPeerId: senderId,
          actorUsername: senderUsername,
          actorSigningPublicKey: actorPublicKey ?? '',
          actorDeviceId: senderDeviceId,
          actorTransportPeerId: transportPeerId,
          expectedPreTransitionStateHash: preTransitionStateHash,
          expectedTransitionSubject: buildGroupSystemTransitionSubject(parsed),
        );
        if (!auditCheck.isValid) {
          _emitSignedTransitionAuditRejected(
            groupId,
            sysType: sysType,
            reason: auditCheck.failure?.reason ?? 'signature_invalid',
          );
          return;
        }
        signedTransitionAudit = auditCheck.verification;
        if (_appendGroupEventLogEntry == null &&
            signedTransitionAudit != null) {
          _acceptedSignedTransitionAuditHashesBySourceId[transitionSourceEventId] =
              signedTransitionAudit.auditHash;
        }
      }

      final group = await _groupRepo.getGroup(groupId);
      if (group?.isDissolved == true && sysType != 'group_dissolved') {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_IGNORED_AFTER_DISSOLVE',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'type': sysType,
          },
        );
        return;
      }

      Future<void> appendSystemEventLog() async {
        final append = _appendGroupEventLogEntry;
        if (append == null || sysType == null) return;
        await append(
          groupId: groupId,
          eventType: sysType,
          sourcePeerId: senderId,
          sourceEventId: transitionSourceEventId,
          sourceTimestamp:
              (eventAt ?? envelopeEventAt ?? DateTime.now().toUtc())
                  .toIso8601String(),
          payload: {
            'groupId': groupId,
            'senderId': senderId,
            'senderUsername': senderUsername,
            'systemType': sysType,
            'payload': parsed,
          },
        );
        if (signedTransitionAudit != null) {
          _acceptedSignedTransitionAuditHashesBySourceId[transitionSourceEventId] =
              signedTransitionAudit!.auditHash;
        }
      }

      if (sysType == 'member_added') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleMemberAdded(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'members_added') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleMembersAdded(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'member_removed') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMemberRemovedEvent(
            groupId,
            parsed: parsed,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleMemberRemoved(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'member_banned') {
        await _enqueueGroupConfigWork(groupId, () async {
          await _handleMemberBanned(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
          );
        });
      } else if (sysType == 'member_unbanned') {
        await _enqueueGroupConfigWork(groupId, () async {
          await _handleMemberUnbanned(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
          );
        });
      } else if (sysType == 'group_message_deleted') {
        await _enqueueGroupConfigWork(groupId, () async {
          await _handleGroupMessageDeleted(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
          );
        });
      } else if (sysType == 'member_role_updated') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleMemberRoleUpdated(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'group_dissolved') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleGroupDissolved(
            groupId,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'group_metadata_updated') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMetadataEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
          )) {
            return;
          }
          if (!await _verifyGroupMetadataActorEvent(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleGroupMetadataUpdated(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'member_joined') {
        await appendSystemEventLog();
        await _handleMemberJoined(
          groupId,
          parsed,
          eventAt: eventAt,
          msgRepo: msgRepo,
        );
      } else if (sysType == 'key_rotated') {
        await appendSystemEventLog();
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
      if (rethrowOnError) rethrow;
    }
  }

  Future<bool> _isBoundSystemEventSenderDevice({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
  }) async {
    if (senderId.isEmpty) {
      return false;
    }
    final member = await _groupRepo.getMember(groupId, senderId);
    if (member == null) {
      return false;
    }
    final resolvedTransportPeerId = transportPeerId?.trim().isNotEmpty == true
        ? transportPeerId!.trim()
        : senderId;
    if (member.devices.isEmpty) {
      return resolvedTransportPeerId == senderId;
    }
    final device = senderDeviceId?.trim().isNotEmpty == true
        ? member.findDeviceById(senderDeviceId)
        : member.findDeviceByTransportPeerId(resolvedTransportPeerId);
    return device != null &&
        device.isActive &&
        device.transportPeerId == resolvedTransportPeerId;
  }

  bool _shouldRequireSignedTransitionAudit(
    String? sysType,
    Map<String, dynamic> parsed,
  ) {
    if (!requiresSignedGroupTransitionAudit(sysType)) {
      return false;
    }
    return _appendGroupEventLogEntry != null ||
        parsed.containsKey(signedGroupTransitionAuditField);
  }

  Future<String?> _resolveActorSigningPublicKey({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
  }) async {
    final member = await _groupRepo.getMember(groupId, senderId);
    if (member == null) {
      return null;
    }
    if (member.devices.isNotEmpty) {
      final device = senderDeviceId?.trim().isNotEmpty == true
          ? member.findDeviceById(senderDeviceId)
          : member.findDeviceByTransportPeerId(transportPeerId);
      final devicePublicKey = device?.deviceSigningPublicKey.trim();
      if (devicePublicKey != null && devicePublicKey.isNotEmpty) {
        return devicePublicKey;
      }
    }
    final memberPublicKey = member.publicKey?.trim();
    return memberPublicKey == null || memberPublicKey.isEmpty
        ? null
        : memberPublicKey;
  }

  void _emitSignedTransitionAuditRejected(
    String groupId, {
    required String? sysType,
    required String reason,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'type': sysType ?? 'null',
        'reason': reason,
      },
    );
  }

  bool _requiresMembershipEventAuthorization(String? sysType) {
    return sysType == 'member_added' ||
        sysType == 'members_added' ||
        sysType == 'member_removed' ||
        sysType == 'member_role_updated' ||
        sysType == 'group_dissolved' ||
        sysType == 'group_metadata_updated';
  }

  Future<bool> _isAuthorizedMembershipEventSender(
    String groupId,
    String senderId, {
    String? sysType,
    Map<String, dynamic>? parsed,
  }) async {
    if (senderId.isEmpty) {
      return false;
    }

    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return false;
    }

    final senderMember = await _groupRepo.getMember(groupId, senderId);
    // Stored creator identity alone is not sufficient once the creator has
    // been demoted or removed; receive-side mutations recheck current state.
    if (sysType == 'group_dissolved') {
      return senderMember?.role == MemberRole.admin;
    }

    if (sysType == 'member_role_updated') {
      if (senderMember == null) return false;
      return _canApplyIncomingMemberRoleUpdate(
        groupId: groupId,
        actor: senderMember,
        parsed: parsed,
      );
    }

    if (sysType == 'member_removed') {
      final memberData = parsed?['member'] as Map<String, dynamic>?;
      final removedPeerId = memberData?['peerId'] as String?;
      if (removedPeerId != null &&
          removedPeerId.isNotEmpty &&
          removedPeerId == senderId &&
          senderMember != null) {
        return true;
      }
    }
    return senderMember?.role == MemberRole.admin;
  }

  Future<bool> _isAuthorizedTrustedPrivateMemberModerator(
    String groupId,
    String senderId,
  ) async {
    if (senderId.isEmpty) {
      return false;
    }
    final senderMember = await _groupRepo.getMember(groupId, senderId);
    if (senderMember == null) {
      return false;
    }
    return senderMember.permissions.allows(
      GroupMemberPermission.removeMembers,
      senderMember.role,
    );
  }

  Future<bool> _isAuthorizedTrustedPrivateMessageDelete(
    String groupId,
    String senderId,
    GroupMessage targetMessage,
  ) async {
    if (senderId.isEmpty) {
      return false;
    }
    final senderMember = await _groupRepo.getMember(groupId, senderId);
    if (senderMember == null) {
      return false;
    }
    if (senderMember.permissions.allows(
      GroupMemberPermission.deleteMessages,
      senderMember.role,
    )) {
      return true;
    }
    return targetMessage.senderPeerId == senderId;
  }

  Future<bool> _canApplyIncomingMemberRoleUpdate({
    required String groupId,
    required GroupMember actor,
    required Map<String, dynamic>? parsed,
  }) async {
    final memberData = parsed?['member'] as Map<String, dynamic>?;
    if (memberData == null) {
      return false;
    }
    final updatedPeerId = memberData['peerId'] as String?;
    if (updatedPeerId == null || updatedPeerId.isEmpty) {
      return false;
    }

    final existingMember = await _groupRepo.getMember(groupId, updatedPeerId);
    if (existingMember == null) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATE_MISSING_TARGET_IGNORED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'memberPeerId': updatedPeerId.length > 8
              ? updatedPeerId.substring(0, 8)
              : updatedPeerId,
          'actorPeerId': actor.peerId.length > 8
              ? actor.peerId.substring(0, 8)
              : actor.peerId,
        },
      );
      return false;
    }

    final groupConfig = parsed?['groupConfig'] as Map<String, dynamic>?;
    final snapshotMemberData = _findGroupConfigMember(
      groupConfig,
      updatedPeerId,
    );
    final effectiveMemberData = snapshotMemberData ?? memberData;

    final roleValue = effectiveMemberData['role'] as String?;
    final requestedRole = MemberRole.fromValue(roleValue ?? 'writer');
    final containsPermissions = effectiveMemberData.containsKey('permissions');
    final requestedPermissions = containsPermissions
        ? GroupMemberPermissions.fromJson(effectiveMemberData['permissions'])
        : null;

    return canApplyGroupMemberRoleUpdate(
      actor: actor,
      newRole: requestedRole,
      existingRole: existingMember?.role,
      requestedPermissions: requestedPermissions,
      existingPermissions: existingMember?.permissions,
    );
  }

  Map<String, dynamic>? _findGroupConfigMember(
    Map<String, dynamic>? groupConfig,
    String peerId,
  ) {
    final members = groupConfig?['members'] as List<dynamic>?;
    if (members == null) {
      return null;
    }
    for (final rawMember in members) {
      if (rawMember is! Map) {
        continue;
      }
      if (rawMember['peerId'] == peerId) {
        return rawMember.cast<String, dynamic>();
      }
    }
    return null;
  }

  Future<bool> _isAuthorizedJoinEventSender(
    String groupId,
    String senderId,
    Map<String, dynamic> parsed,
  ) async {
    if (senderId.isEmpty) {
      return false;
    }
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final joinedPeerId = memberData?['peerId'] as String?;
    if (joinedPeerId == null ||
        joinedPeerId.isEmpty ||
        joinedPeerId != senderId) {
      return false;
    }
    final joinedMember = await _groupRepo.getMember(groupId, joinedPeerId);
    return joinedMember != null;
  }

  /// Handles a member_added system message.
  ///
  /// Saves the new member to the local DB and updates the Go topic validator
  /// config so that messages from the new member are accepted.
  Future<void> _handleMemberAdded(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    // Save new member to local DB
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final addedPeerId = memberData?['peerId'] as String?;
    final addedUsername = memberData?['username'] as String?;
    if (memberData != null) {
      final member = GroupMember.fromConfigMap(
        groupId: groupId,
        map: Map<String, dynamic>.from(memberData),
        existing: addedPeerId == null
            ? null
            : await _groupRepo.getMember(groupId, addedPeerId),
        joinedAt: eventAt ?? DateTime.now().toUtc(),
      );
      await _groupRepo.saveMember(member);
    }

    // Update Go topic validator config
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
      );
      await _syncGroupConfig(groupId, groupConfig);
    }

    if (addedPeerId != null && addedPeerId.isNotEmpty) {
      final timelineMessage = buildMembersAddedTimelineMessage(
        groupId: groupId,
        addedMembers: [(peerId: addedPeerId, username: addedUsername)],
        senderId: senderId,
        senderUsername: senderUsername,
        eventAt: eventAt ?? DateTime.now().toUtc(),
      );
      final savedTimelineMessage =
          await _saveTimelineMessagePreservingReadState(
            timelineMessage,
            msgRepo,
          );
      _messageController.add(savedTimelineMessage);
    }

    await _recordMembershipEventWatermark(groupId, eventAt);

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
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final membersList = parsed['members'] as List<dynamic>?;
    if (membersList != null) {
      for (final memberData in membersList) {
        final data = Map<String, dynamic>.from(memberData as Map);
        final peerId = data['peerId'] as String?;
        final member = GroupMember.fromConfigMap(
          groupId: groupId,
          map: data,
          existing: peerId == null
              ? null
              : await _groupRepo.getMember(groupId, peerId),
          joinedAt: eventAt ?? DateTime.now().toUtc(),
        );
        await _groupRepo.saveMember(member);
      }
    }

    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
      );
      await _syncGroupConfig(groupId, groupConfig);
    }

    final addedMembers = membersList
        ?.whereType<Map<String, dynamic>>()
        .map(
          (data) => (
            peerId: data['peerId'] as String? ?? '',
            username: data['username'] as String?,
          ),
        )
        .where((member) => member.peerId.isNotEmpty)
        .toList(growable: false);
    if (addedMembers != null && addedMembers.isNotEmpty) {
      final timelineMessage = buildMembersAddedTimelineMessage(
        groupId: groupId,
        addedMembers: addedMembers,
        senderId: senderId,
        senderUsername: senderUsername,
        eventAt: eventAt ?? DateTime.now().toUtc(),
      );
      final savedTimelineMessage =
          await _saveTimelineMessagePreservingReadState(
            timelineMessage,
            msgRepo,
          );
      _messageController.add(savedTimelineMessage);
    }

    await _recordMembershipEventWatermark(groupId, eventAt);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERS_ADDED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'count': membersList?.length ?? 0,
      },
    );
  }

  Future<void> _handleMemberJoined(
    String groupId,
    Map<String, dynamic> parsed, {
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final joinedPeerId = memberData?['peerId'] as String? ?? '';
    if (joinedPeerId.isEmpty) {
      return;
    }
    final timelineMessage = buildMemberJoinedTimelineMessage(
      groupId: groupId,
      joinedPeerId: joinedPeerId,
      joinedUsername: memberData?['username'] as String?,
      eventAt: eventAt ?? DateTime.now().toUtc(),
    );
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_JOINED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': joinedPeerId.length > 8
            ? joinedPeerId.substring(0, 8)
            : joinedPeerId,
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
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final removedPeerId = memberData?['peerId'] as String?;
    final removedUsername = memberData?['username'] as String?;

    // Check if the removed member is self
    if (removedPeerId != null && _getSelfPeerId != null && _bridge != null) {
      final selfPeerId = await _getSelfPeerId!();
      if (selfPeerId != null && selfPeerId == removedPeerId) {
        if (await _groupRepo.getGroup(groupId) == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_DUPLICATE_IGNORED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            },
          );
          return;
        }

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
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
      );
      final synced = await _syncGroupConfig(
        groupId,
        groupConfig,
        emitFailureEvent: true,
      );
      if (!synced) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONFIG_SYNC_FAILED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          },
        );
      }
    }

    final timelineMessage = buildMemberRemovedTimelineMessage(
      groupId: groupId,
      removedPeerId: removedPeerId ?? '',
      removedUsername: removedUsername,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: eventAt ?? DateTime.now().toUtc(),
    );
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    await _recordMembershipEventWatermark(groupId, eventAt);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'removedPeerId': removedPeerId ?? '?',
      },
    );
  }

  Future<void> _handleMemberBanned(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final event = parseTrustedPrivateMemberSystemEvent(
      parsed,
      systemType: 'member_banned',
      fallbackEventAt: eventAt,
    );
    if (event == null) {
      return;
    }

    final timelineMessage = _buildTrustedPrivateMemberTombstoneMessage(
      eventType: 'member_banned',
      groupId: groupId,
      targetPeerId: event.targetPeerId,
      targetUsername: event.targetUsername,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: event.eventAt,
    );
    if (await msgRepo.getMessage(timelineMessage.id) != null) {
      return;
    }

    final latestUnbanAt = await msgRepo.getLatestSystemEventTimestampForTarget(
      groupId,
      eventType: 'member_unbanned',
      targetId: event.targetPeerId,
    );
    if (latestUnbanAt != null && !event.eventAt.isAfter(latestUnbanAt)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'member_banned',
        reason: 'stale_after_unban',
      );
      return;
    }

    final existingMember = await _groupRepo.getMember(
      groupId,
      event.targetPeerId,
    );
    if (existingMember == null ||
        existingMember.joinedAt.toUtc().isAfter(event.eventAt)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'member_banned',
        reason: 'stale_or_missing_target',
      );
      return;
    }

    if (!await _isAuthorizedTrustedPrivateMemberModerator(groupId, senderId)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'member_banned',
        reason: 'unauthorized',
      );
      return;
    }

    await appendSystemEventLog();
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    final getSelfPeerId = _getSelfPeerId;
    final bridge = _bridge;
    if (getSelfPeerId != null && bridge != null) {
      final selfPeerId = await getSelfPeerId();
      if (selfPeerId == event.targetPeerId) {
        await leaveGroup(
          bridge: bridge,
          groupRepo: _groupRepo,
          groupId: groupId,
        );
        _removedController.add(groupId);
        return;
      }
    }

    await _groupRepo.removeMember(groupId, event.targetPeerId);

    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: event.eventAt,
      );
      final synced = await _syncGroupConfig(
        groupId,
        groupConfig,
        emitFailureEvent: true,
      );
      if (!synced) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONFIG_SYNC_FAILED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          },
        );
      }
    }

    await _recordMembershipEventWatermark(groupId, event.eventAt);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_BANNED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': event.targetPeerId.length > 8
            ? event.targetPeerId.substring(0, 8)
            : event.targetPeerId,
      },
    );
  }

  Future<void> _handleMemberUnbanned(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final event = parseTrustedPrivateMemberSystemEvent(
      parsed,
      systemType: 'member_unbanned',
      fallbackEventAt: eventAt,
    );
    if (event == null) {
      return;
    }

    final timelineMessage = _buildTrustedPrivateMemberTombstoneMessage(
      eventType: 'member_unbanned',
      groupId: groupId,
      targetPeerId: event.targetPeerId,
      targetUsername: event.targetUsername,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: event.eventAt,
    );
    if (await msgRepo.getMessage(timelineMessage.id) != null) {
      return;
    }

    final latestBanAt = await msgRepo.getLatestSystemEventTimestampForTarget(
      groupId,
      eventType: 'member_banned',
      targetId: event.targetPeerId,
    );
    if (latestBanAt != null && latestBanAt.isAfter(event.eventAt)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'member_unbanned',
        reason: 'stale_before_ban',
      );
      return;
    }

    if (!await _isAuthorizedTrustedPrivateMemberModerator(groupId, senderId)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'member_unbanned',
        reason: 'unauthorized',
      );
      return;
    }

    await appendSystemEventLog();
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);
    await _recordMembershipEventWatermark(groupId, event.eventAt);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_UNBANNED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': event.targetPeerId.length > 8
            ? event.targetPeerId.substring(0, 8)
            : event.targetPeerId,
      },
    );
  }

  Future<void> _handleGroupMessageDeleted(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final event = parseTrustedPrivateMessageDeleteEvent(
      parsed,
      fallbackEventAt: eventAt,
    );
    if (event == null) {
      return;
    }

    final timelineMessage = _buildTrustedPrivateMessageDeleteTombstoneMessage(
      groupId: groupId,
      targetMessageId: event.targetMessageId,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: event.eventAt,
    );
    if (await msgRepo.getMessage(timelineMessage.id) != null) {
      return;
    }

    final targetMessage = await msgRepo.getMessage(event.targetMessageId);
    if (targetMessage == null ||
        targetMessage.groupId != groupId ||
        targetMessage.id.startsWith('sys-') ||
        !targetMessage.timestamp.toUtc().isBefore(event.eventAt)) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'group_message_deleted',
        reason: 'stale_or_missing_target',
      );
      return;
    }

    if (!await _isAuthorizedTrustedPrivateMessageDelete(
      groupId,
      senderId,
      targetMessage,
    )) {
      _emitTrustedPrivateSystemEventIgnored(
        groupId,
        sysType: 'group_message_deleted',
        reason: 'unauthorized',
      );
      return;
    }

    await appendSystemEventLog();
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    await msgRepo.deleteMessage(event.targetMessageId);
    _messageController.add(savedTimelineMessage);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_GROUP_MESSAGE_DELETED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'targetMessageId': event.targetMessageId.length > 8
            ? event.targetMessageId.substring(0, 8)
            : event.targetMessageId,
      },
    );
  }

  Future<void> _handleMemberRoleUpdated(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final updatedPeerId = memberData?['peerId'] as String?;
    final updatedUsername = memberData?['username'] as String?;
    final newRole = MemberRole.fromValue(
      memberData?['role'] as String? ?? 'writer',
    );
    final existingMember = updatedPeerId == null
        ? null
        : await _groupRepo.getMember(groupId, updatedPeerId);

    if (updatedPeerId != null && updatedPeerId.isNotEmpty) {
      await _groupRepo.saveMember(
        GroupMember.fromConfigMap(
          groupId: groupId,
          map: {
            ...?memberData,
            'peerId': updatedPeerId,
            if (updatedUsername != null) 'username': updatedUsername,
            'role': newRole.toValue(),
          },
          existing: existingMember,
          joinedAt: eventAt ?? DateTime.now().toUtc(),
        ),
      );
    }

    if (_getSelfPeerId != null &&
        updatedPeerId != null &&
        updatedPeerId.isNotEmpty) {
      final selfPeerId = await _getSelfPeerId!();
      final group = await _groupRepo.getGroup(groupId);
      if (group != null && selfPeerId == updatedPeerId) {
        final updatedMyRole = newRole == MemberRole.admin
            ? GroupRole.admin
            : GroupRole.member;
        if (group.myRole != updatedMyRole) {
          await _groupRepo.updateGroup(group.copyWith(myRole: updatedMyRole));
        }
      }
    }

    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
      );
      final synced = await _syncGroupConfig(
        groupId,
        groupConfig,
        emitFailureEvent: true,
      );
      if (!synced) {
        emitFlowEvent(
          layer: 'FL',
          event: 'CONFIG_SYNC_FAILED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          },
        );
      }
    }

    if (updatedPeerId != null && updatedPeerId.isNotEmpty) {
      final timelineMessage = buildMemberRoleUpdatedTimelineMessage(
        groupId: groupId,
        updatedPeerId: updatedPeerId,
        updatedUsername: updatedUsername,
        previousRole: existingMember?.role,
        newRole: newRole,
        senderId: senderId,
        senderUsername: senderUsername,
        eventAt: eventAt ?? DateTime.now().toUtc(),
      );
      final savedTimelineMessage =
          await _saveTimelineMessagePreservingReadState(
            timelineMessage,
            msgRepo,
          );
      _messageController.add(savedTimelineMessage);
    }

    await _recordMembershipEventWatermark(groupId, eventAt);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': updatedPeerId ?? '?',
        'role': newRole.toValue(),
      },
    );
  }

  Future<void> _handleGroupMetadataUpdated(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig == null) {
      return;
    }
    if (!isGroupConfigStateHashValid(
      groupId: groupId,
      groupConfig: groupConfig,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_METADATA_STATE_HASH_MISMATCH',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return;
    }

    await _applyAuthoritativeGroupConfigSnapshot(groupId, groupConfig);
    final synced = await _syncGroupConfig(
      groupId,
      groupConfig,
      emitFailureEvent: true,
    );
    if (!synced) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONFIG_SYNC_FAILED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
    }

    final timelineMessage = GroupMessage(
      id:
          'sys-group_metadata_updated:$groupId:${senderId.isEmpty ? 'system' : senderId}:'
          '${(eventAt ?? DateTime.now().toUtc()).microsecondsSinceEpoch}',
      groupId: groupId,
      senderPeerId: senderId.isEmpty ? 'system' : senderId,
      senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
      text: _buildMetadataTimelineText(senderUsername),
      timestamp: eventAt ?? DateTime.now().toUtc(),
      status: 'delivered',
      isIncoming: true,
      createdAt: eventAt ?? DateTime.now().toUtc(),
    );
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_GROUP_METADATA_UPDATED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
  }

  Future<bool> _verifyGroupMetadataActorEvent(
    String groupId,
    Map<String, dynamic> parsed, {
    required String senderId,
    required String senderUsername,
  }) async {
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig == null) {
      return false;
    }
    if (!isGroupConfigStateHashValid(
      groupId: groupId,
      groupConfig: groupConfig,
    )) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_METADATA_STATE_HASH_MISMATCH',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        },
      );
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      _emitMetadataSignatureRejected(groupId, reason: 'bridge_missing');
      return false;
    }

    final senderMember = await _groupRepo.getMember(groupId, senderId);
    final trustedActorPublicKey = senderMember?.publicKey?.trim() ?? '';
    final verificationData = extractGroupMetadataActorEventVerificationData(
      systemPayload: parsed,
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      trustedActorPublicKey: trustedActorPublicKey,
    );
    if (verificationData == null) {
      _emitMetadataSignatureRejected(groupId, reason: 'envelope_invalid');
      return false;
    }

    final isValid = await callVerifyPayload(
      bridge: bridge,
      publicKey: verificationData.actorPublicKey,
      data: verificationData.signedPayload,
      signature: verificationData.signature,
    );
    if (!isValid) {
      _emitMetadataSignatureRejected(groupId, reason: 'signature_invalid');
      return false;
    }

    return true;
  }

  void _emitMetadataSignatureRejected(
    String groupId, {
    required String reason,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'reason': reason,
      },
    );
  }

  String _buildMetadataTimelineText(String senderUsername) {
    final actor = senderUsername.trim().isNotEmpty
        ? senderUsername.trim()
        : 'Admin';
    return '$actor updated the group details';
  }

  Future<void> _handleGroupDissolved(
    String groupId, {
    required String senderId,
    required String senderUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return;
    }

    final resolvedEventAt = (eventAt ?? DateTime.now().toUtc()).toUtc();
    await _groupRepo.updateGroup(
      group.copyWith(
        isDissolved: true,
        dissolvedAt: resolvedEventAt,
        dissolvedBy: senderId.isEmpty ? group.dissolvedBy : senderId,
        lastMembershipEventAt: resolvedEventAt,
      ),
    );

    final timelineMessage = buildGroupDissolvedTimelineMessage(
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: resolvedEventAt,
    );
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    await _recordMembershipEventWatermark(groupId, resolvedEventAt);

    if (_bridge != null) {
      try {
        await callGroupLeave(_bridge!, groupId);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_DISSOLVE_LEAVE_ERROR',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'error': e.toString(),
          },
        );
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_GROUP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
      },
    );
  }

  /// Handles an incoming group reaction event from the bridge.
  Future<void> _handleReaction(Map<String, dynamic> data) async {
    try {
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final senderDeviceId = data['senderDeviceId'] as String?;
      final transportPeerId = data['transportPeerId'] as String?;
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
        senderDeviceId: senderDeviceId,
        transportPeerId: transportPeerId,
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

  Future<void> _enqueueGroupConfigWork(
    String groupId,
    Future<void> Function() work,
  ) async {
    final previousWork = _groupConfigWorkQueue[groupId] ?? Future.value();
    final nextWork = previousWork.catchError((_) {}).then((_) => work());

    _groupConfigWorkQueue[groupId] = nextWork.whenComplete(() {
      if (_groupConfigWorkQueue[groupId] == nextWork) {
        _groupConfigWorkQueue.remove(groupId);
      }
    });
    await _groupConfigWorkQueue[groupId];
  }

  Future<GroupMessage> _saveTimelineMessagePreservingReadState(
    GroupMessage timelineMessage,
    GroupMessageRepository msgRepo,
  ) async {
    final existing = await msgRepo.getMessage(timelineMessage.id);
    final existingReadAt = existing?.readAt;
    final messageToSave = existingReadAt == null
        ? timelineMessage
        : timelineMessage.copyWith(readAt: existingReadAt);
    await msgRepo.saveMessage(messageToSave);
    return messageToSave;
  }

  GroupMessage _buildTrustedPrivateMemberTombstoneMessage({
    required String eventType,
    required String groupId,
    required String targetPeerId,
    String? targetUsername,
    required String senderId,
    required String senderUsername,
    required DateTime eventAt,
  }) {
    final normalizedEventAt = eventAt.toUtc();
    final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';
    final actor = senderUsername.trim().isNotEmpty
        ? senderUsername.trim()
        : 'Admin';
    final subject = targetUsername?.trim().isNotEmpty == true
        ? targetUsername!.trim()
        : 'a member';
    final action = eventType == 'member_unbanned' ? 'unbanned' : 'banned';
    return GroupMessage(
      id:
          'sys-$eventType:$groupId:$targetPeerId:'
          '$effectiveSenderId:${normalizedEventAt.microsecondsSinceEpoch}',
      groupId: groupId,
      senderPeerId: effectiveSenderId,
      senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
      text: '$actor $action $subject',
      timestamp: normalizedEventAt,
      status: 'delivered',
      isIncoming: true,
      createdAt: normalizedEventAt,
    );
  }

  GroupMessage _buildTrustedPrivateMessageDeleteTombstoneMessage({
    required String groupId,
    required String targetMessageId,
    required String senderId,
    required String senderUsername,
    required DateTime eventAt,
  }) {
    final normalizedEventAt = eventAt.toUtc();
    final effectiveSenderId = senderId.isNotEmpty ? senderId : 'system';
    final actor = senderUsername.trim().isNotEmpty
        ? senderUsername.trim()
        : 'Admin';
    return GroupMessage(
      id:
          'sys-group_message_deleted:$groupId:$targetMessageId:'
          '$effectiveSenderId:${normalizedEventAt.microsecondsSinceEpoch}',
      groupId: groupId,
      senderPeerId: effectiveSenderId,
      senderUsername: senderUsername.isNotEmpty ? senderUsername : null,
      text: '$actor deleted a message',
      timestamp: normalizedEventAt,
      status: 'delivered',
      isIncoming: true,
      createdAt: normalizedEventAt,
    );
  }

  void _emitTrustedPrivateSystemEventIgnored(
    String groupId, {
    required String sysType,
    required String reason,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_TRUSTED_PRIVATE_SYSTEM_EVENT_IGNORED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'type': sysType,
        'reason': reason,
      },
    );
  }

  DateTime? _parseMembershipEventAt(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(timestamp);
    return parsed?.toUtc();
  }

  Future<bool> _shouldIgnoreStaleMembershipEvent(
    String groupId, {
    required String? sysType,
    required DateTime? eventAt,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final watermark = await _resolveMembershipEventWatermark(groupId);
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_STALE_MEMBERSHIP_EVENT_IGNORED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'type': sysType ?? 'null',
        'eventAt': eventAt.toIso8601String(),
        'watermark': watermark.toIso8601String(),
      },
    );
    return true;
  }

  Future<bool> _shouldIgnoreStaleMemberRemovedEvent(
    String groupId, {
    required Map<String, dynamic> parsed,
    required String? sysType,
    required DateTime? eventAt,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final watermark = await _resolveMembershipEventWatermark(groupId);
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    final memberData = parsed['member'] as Map<String, dynamic>?;
    final removedPeerId = memberData?['peerId'] as String?;
    if (removedPeerId != null && removedPeerId.isNotEmpty) {
      final existingMember = await _groupRepo.getMember(groupId, removedPeerId);
      final joinedAt = existingMember?.joinedAt.toUtc();
      if (existingMember != null &&
          joinedAt != null &&
          !joinedAt.isAfter(eventAt)) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_CONFLICT_APPLIED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'memberPeerId': removedPeerId.length > 8
                ? removedPeerId.substring(0, 8)
                : removedPeerId,
            'eventAt': eventAt.toIso8601String(),
            'watermark': watermark.toIso8601String(),
          },
        );
        return false;
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_STALE_MEMBERSHIP_EVENT_IGNORED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'type': sysType ?? 'null',
        'eventAt': eventAt.toIso8601String(),
        'watermark': watermark.toIso8601String(),
      },
    );
    return true;
  }

  Future<DateTime?> _resolveMembershipEventWatermark(String groupId) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return null;
    }

    if (group.lastMembershipEventAt != null) {
      return group.lastMembershipEventAt!.toUtc();
    }

    final candidates = <DateTime>[group.createdAt.toUtc()];
    if (group.archivedAt != null) {
      candidates.add(group.archivedAt!.toUtc());
    }

    final members = await _groupRepo.getMembers(groupId);
    for (final member in members) {
      candidates.add(member.joinedAt.toUtc());
    }

    final latestKey = await _groupRepo.getLatestKey(groupId);
    if (latestKey != null) {
      candidates.add(latestKey.createdAt.toUtc());
    }

    candidates.sort((a, b) => a.compareTo(b));
    return candidates.last;
  }

  Future<bool> _shouldIgnoreStaleMetadataEvent(
    String groupId, {
    required String? sysType,
    required DateTime? eventAt,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final group = await _groupRepo.getGroup(groupId);
    final watermark = group?.lastMetadataEventAt?.toUtc();
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    final shouldRetryAvatarRecovery =
        group != null &&
        eventAt.isAtSameMomentAs(watermark) &&
        group.avatarBlobId != null &&
        group.avatarMime != null &&
        (group.avatarPath == null || group.avatarPath!.isEmpty);
    if (shouldRetryAvatarRecovery) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_METADATA_EVENT_RETRYING_AVATAR_DOWNLOAD',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'type': sysType ?? 'null',
          'eventAt': eventAt.toIso8601String(),
          'watermark': watermark.toIso8601String(),
        },
      );
      return false;
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_STALE_METADATA_EVENT_IGNORED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'type': sysType ?? 'null',
        'eventAt': eventAt.toIso8601String(),
        'watermark': watermark.toIso8601String(),
      },
    );
    return true;
  }

  Future<DateTime?> _resolveMetadataEventWatermark(String groupId) async {
    final group = await _groupRepo.getGroup(groupId);
    return group?.lastMetadataEventAt?.toUtc();
  }

  Future<void> _applyAuthoritativeGroupConfigSnapshot(
    String groupId,
    Map<String, dynamic> groupConfig, {
    DateTime? eventAt,
  }) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return;
    }

    final membersList = groupConfig['members'] as List<dynamic>?;
    if (membersList == null) {
      return;
    }

    final existingMembers = await _groupRepo.getMembers(groupId);
    final existingByPeerId = {
      for (final member in existingMembers) member.peerId: member,
    };
    final snapshotPeerIds = <String>{};
    MemberRole? selfSnapshotRole;
    final selfPeerId = _getSelfPeerId != null ? await _getSelfPeerId!() : null;

    for (final rawMember in membersList) {
      final memberData = rawMember as Map<String, dynamic>;
      final peerId = memberData['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) {
        continue;
      }

      final existingMember = existingByPeerId[peerId];
      final role = MemberRole.fromValue(
        memberData['role'] as String? ?? 'writer',
      );
      snapshotPeerIds.add(peerId);

      if (selfPeerId != null && selfPeerId == peerId) {
        selfSnapshotRole = role;
      }

      await _groupRepo.saveMember(
        GroupMember.fromConfigMap(
          groupId: groupId,
          map: memberData,
          existing: existingMember,
          joinedAt: eventAt ?? group.createdAt.toUtc(),
        ),
      );
    }

    for (final existingMember in existingMembers) {
      if (!snapshotPeerIds.contains(existingMember.peerId)) {
        await _groupRepo.removeMember(groupId, existingMember.peerId);
      }
    }

    var resolvedType = group.type;
    final groupTypeValue = groupConfig['groupType'] as String?;
    if (groupTypeValue != null && groupTypeValue.isNotEmpty) {
      try {
        resolvedType = GroupType.fromValue(groupTypeValue);
      } on ArgumentError {
        resolvedType = group.type;
      }
    }

    final createdAtValue = groupConfig['createdAt'] as String?;
    final resolvedCreatedAt =
        DateTime.tryParse(createdAtValue ?? '')?.toUtc() ?? group.createdAt;
    final metadataUpdatedAtValue = groupConfig['metadataUpdatedAt'] as String?;
    final resolvedMetadataUpdatedAt = DateTime.tryParse(
      metadataUpdatedAtValue ?? '',
    )?.toUtc();
    final containsAvatarBlobId = groupConfig.containsKey('avatarBlobId');
    final containsAvatarMime = groupConfig.containsKey('avatarMime');
    final resolvedAvatarBlobId = containsAvatarBlobId
        ? groupConfig['avatarBlobId'] as String?
        : group.avatarBlobId;
    final resolvedAvatarMime = containsAvatarMime
        ? groupConfig['avatarMime'] as String?
        : group.avatarMime;
    final avatarChanged =
        resolvedAvatarBlobId != group.avatarBlobId ||
        resolvedAvatarMime != group.avatarMime;
    final shouldClearAvatar =
        (containsAvatarBlobId || containsAvatarMime) &&
        (resolvedAvatarBlobId == null || resolvedAvatarMime == null);
    final nextAvatarPath = shouldClearAvatar || avatarChanged
        ? null
        : group.avatarPath;

    if ((avatarChanged || shouldClearAvatar) && group.avatarPath != null) {
      await deleteGroupAvatar(storedPath: group.avatarPath);
    }

    await _groupRepo.updateGroup(
      group.copyWith(
        name: groupConfig['name'] as String? ?? group.name,
        type: resolvedType,
        description: groupConfig.containsKey('description')
            ? groupConfig['description'] as String?
            : group.description,
        avatarBlobId: resolvedAvatarBlobId,
        avatarMime: resolvedAvatarMime,
        avatarPath: nextAvatarPath,
        createdAt: resolvedCreatedAt,
        createdBy: groupConfig['createdBy'] as String? ?? group.createdBy,
        myRole: selfSnapshotRole == null
            ? group.myRole
            : (selfSnapshotRole == MemberRole.admin
                  ? GroupRole.admin
                  : GroupRole.member),
        lastMetadataEventAt:
            resolvedMetadataUpdatedAt ?? group.lastMetadataEventAt,
      ),
    );

    if (_bridge != null &&
        resolvedAvatarBlobId != null &&
        resolvedAvatarMime != null &&
        (avatarChanged || nextAvatarPath == null)) {
      final avatarPath = await _downloadGroupAvatarFn(
        bridge: _bridge!,
        groupId: groupId,
        blobId: resolvedAvatarBlobId,
      );
      if (avatarPath != null) {
        final refreshedGroup = await _groupRepo.getGroup(groupId);
        if (refreshedGroup != null &&
            refreshedGroup.avatarBlobId == resolvedAvatarBlobId) {
          await _groupRepo.updateGroup(
            refreshedGroup.copyWith(avatarPath: avatarPath),
          );
        }
      }
    }
  }

  Future<void> _recordMembershipEventWatermark(
    String groupId,
    DateTime? eventAt,
  ) async {
    await recordGroupMembershipEventWatermark(
      groupRepo: _groupRepo,
      groupId: groupId,
      eventAt: eventAt,
    );
  }

  Future<bool> _syncGroupConfig(
    String groupId,
    Map<String, dynamic> groupConfig, {
    bool emitFailureEvent = false,
  }) async {
    if (_bridge == null) {
      return true;
    }

    try {
      await callGroupUpdateConfig(
        _bridge!,
        groupId: groupId,
        groupConfig: groupConfig,
      );
      return true;
    } catch (_) {
      try {
        await callGroupUpdateConfig(
          _bridge!,
          groupId: groupId,
          groupConfig: groupConfig,
        );
        return true;
      } catch (e) {
        if (emitFailureEvent) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_CONFIG_UPDATE_RETRY_FAILED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'error': e.toString(),
            },
          );
        }
        return false;
      }
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
    _diagnosticSubscription?.cancel();
    _diagnosticSubscription = null;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    stop();
    _messageController.close();
    _removedController.close();
    _reactionChangeController.close();
  }
}
