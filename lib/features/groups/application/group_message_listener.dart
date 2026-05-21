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
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';

typedef RecoverGroupDispatcherOverflow =
    Future<void> Function(Map<String, dynamic> diagnostic);

const _maxPendingMembershipDependentMessagesPerGroup = 50;

class _PendingMembershipDependentMessage {
  _PendingMembershipDependentMessage({
    required this.data,
    required this.senderPeerId,
    required this.messageId,
    required this.receivedAt,
  });

  final Map<String, dynamic> data;
  final String senderPeerId;
  final String? messageId;
  final DateTime receivedAt;
}

String _membershipFlowId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;

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
  final GroupInviteDeliveryAttemptRepository? _inviteDeliveryAttemptRepo;
  final DownloadGroupAvatarFn _downloadGroupAvatarFn;
  final AppendGroupEventLogEntry? _appendGroupEventLogEntry;
  final Stream<Map<String, dynamic>>? _groupDiagnosticEvents;
  final GroupPendingKeyRepairRepository? _pendingKeyRepairRepo;
  final RequestGroupKeyRepair _requestGroupKeyRepair;
  final RecoverGroupDispatcherOverflow? _recoverFromDispatcherOverflow;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _diagnosticSubscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();
  final Map<String, Future<void>> _groupConfigWorkQueue = {};
  final Map<String, String> _acceptedSignedTransitionAuditHashesBySourceId = {};
  final Map<String, List<_PendingMembershipDependentMessage>>
  _pendingMembershipDependentMessagesByGroup = {};
  Future<void>? _dispatcherOverflowRecovery;
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
    GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
    DownloadGroupAvatarFn? downloadGroupAvatarFn,
    AppendGroupEventLogEntry? appendGroupEventLogEntry,
    Stream<Map<String, dynamic>>? groupDiagnosticEvents,
    GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
    RequestGroupKeyRepair? requestGroupKeyRepair,
    RecoverGroupDispatcherOverflow? recoverFromDispatcherOverflow,
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
       _inviteDeliveryAttemptRepo = inviteDeliveryAttemptRepo,
       _downloadGroupAvatarFn = downloadGroupAvatarFn ?? downloadGroupAvatar,
       _appendGroupEventLogEntry = appendGroupEventLogEntry,
       _groupDiagnosticEvents = groupDiagnosticEvents,
       _pendingKeyRepairRepo = pendingKeyRepairRepo,
       _requestGroupKeyRepair =
           requestGroupKeyRepair ?? emitGroupKeyRepairRequest,
       _recoverFromDispatcherOverflow = recoverFromDispatcherOverflow;

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
      allowMembershipBuffer: false,
    );
  }

  Future<String?> _resolveSelfPeerId() {
    if (_hasResolvedSelfPeerId) {
      return Future<String?>.value(_cachedSelfPeerId);
    }
    if (_selfPeerIdLoadFuture != null) {
      return _selfPeerIdLoadFuture!;
    }

    final getSelfPeerId = _getSelfPeerId;
    final loader = getSelfPeerId == null
        ? Future<String?>.value(null)
        : getSelfPeerId();
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
    final rejectedOutbound = await markOutboundGroupMessageRejectedByValidator(
      msgRepo: _msgRepo,
      diagnostic: event,
    );
    if (rejectedOutbound != null) {
      _messageController.add(rejectedOutbound);
      return;
    }

    if (event['event'] == 'group:dispatcher_overflow') {
      await _handleGroupDispatcherOverflow(event);
      return;
    }

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

  Future<void> _handleGroupDispatcherOverflow(
    Map<String, dynamic> event,
  ) async {
    if (event['lastEvent'] != 'group_message:received') {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_IGNORED',
        details: _dispatcherOverflowDiagnosticDetails(event),
      );
      return;
    }

    final recover = _recoverFromDispatcherOverflow;
    if (recover == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_UNAVAILABLE',
        details: _dispatcherOverflowDiagnosticDetails(event),
      );
      return;
    }

    final currentRecovery = _dispatcherOverflowRecovery;
    if (currentRecovery != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_COALESCED',
        details: _dispatcherOverflowDiagnosticDetails(event),
      );
      return;
    }

    final diagnostic = Map<String, dynamic>.unmodifiable(event);
    final recovery = Future<void>.microtask(() async {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_REQUESTED',
        details: _dispatcherOverflowDiagnosticDetails(diagnostic),
      );
      try {
        await recover(diagnostic);
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_DONE',
          details: _dispatcherOverflowDiagnosticDetails(diagnostic),
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_ERROR',
          details: {
            ..._dispatcherOverflowDiagnosticDetails(diagnostic),
            'error': error.toString(),
          },
        );
      }
    });

    _dispatcherOverflowRecovery = recovery;
    await recovery;
    if (identical(_dispatcherOverflowRecovery, recovery)) {
      _dispatcherOverflowRecovery = null;
    }
  }

  Map<String, dynamic> _dispatcherOverflowDiagnosticDetails(
    Map<String, dynamic> event,
  ) {
    return {
      'lastEvent': event['lastEvent']?.toString(),
      if (event.containsKey('state')) 'state': event['state'],
      if (event.containsKey('droppedCount'))
        'droppedCount': event['droppedCount'],
      if (event.containsKey('queueDepth')) 'queueDepth': event['queueDepth'],
      if (event.containsKey('maxQueueSize'))
        'maxQueueSize': event['maxQueueSize'],
    };
  }

  String? _groupMessageEventSchemaRejectReason(Map<String, dynamic> data) {
    String? requiredStringReason(String field) {
      final value = data[field];
      if (value is! String || value.trim().isEmpty) {
        return 'missing_or_invalid_$field';
      }
      return null;
    }

    for (final field in const ['groupId', 'senderId']) {
      final reason = requiredStringReason(field);
      if (reason != null) return reason;
    }

    for (final field in const [
      'senderUsername',
      'text',
      'timestamp',
      'messageId',
      'quotedMessageId',
      'transportPeerId',
      'senderDeviceId',
      'topicGroupId',
    ]) {
      final value = data[field];
      if (value != null && value is! String) {
        return 'invalid_$field';
      }
    }

    final text = data['text'];
    final isSystemPayload = text is String && text.startsWith('{"__sys":');
    final keyEpoch = data['keyEpoch'];
    if (keyEpoch != null && (keyEpoch is! int || keyEpoch < 0)) {
      return 'missing_or_invalid_keyEpoch';
    }
    if (!isSystemPayload && keyEpoch == null) {
      return 'missing_or_invalid_keyEpoch';
    }

    final media = data['media'];
    if (media != null) {
      if (media is! List) return 'invalid_media';
      if (media.any((entry) => entry is! Map)) {
        return 'invalid_media_entry';
      }
    }

    return null;
  }

  void _emitGroupMessageSchemaRejected(
    Map<String, dynamic> data,
    String reason,
  ) {
    final groupId = data['groupId'];
    final senderId = data['senderId'];
    final messageId = data['messageId'];
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_SCHEMA_REJECTED',
      details: {
        'reason': reason,
        if (groupId is String)
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        if (senderId is String)
          'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
        if (messageId is String)
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
      },
    );
  }

  Future<void> _handleMessage(
    Map<String, dynamic> data, {
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
    bool allowMembershipBuffer = true,
  }) async {
    try {
      final schemaRejectReason = _groupMessageEventSchemaRejectReason(data);
      if (schemaRejectReason != null) {
        _emitGroupMessageSchemaRejected(data, schemaRejectReason);
        return;
      }

      final msgRepo = msgRepoOverride ?? _msgRepo;
      final groupId = data['groupId'] as String? ?? '';
      final topicGroupId = data['topicGroupId'] as String?;
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

      if (topicGroupId != null &&
          topicGroupId.isNotEmpty &&
          topicGroupId != groupId) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_TOPIC_GROUP_MISMATCH_REJECTED',
          details: {
            'groupId': _membershipFlowId(groupId),
            'topicGroupId': _membershipFlowId(topicGroupId),
            'senderId': _membershipFlowId(senderId),
          },
        );
        return;
      }

      // Drop events that have neither text nor media. These are not valid
      // user messages — most likely a malformed envelope from upstream
      // (e.g. a partial-decrypt failure on the Go side that emits a
      // skeleton event without `text`). Persisting them produces empty
      // bubbles that survive cold-restart. The offline-drain undecryptable
      // path persists its own user-readable placeholder elsewhere; this
      // listener should never silently persist a row with no body.
      final mediaListForEmptyCheck = (data['media'] as List?) ?? const [];
      if (text.isEmpty && mediaListForEmptyCheck.isEmpty) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_EMPTY_DROP',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'senderId': senderId.length > 8
                ? senderId.substring(0, 8)
                : senderId,
            'hasTextField': data.containsKey('text'),
          },
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
      if (allowMembershipBuffer &&
          await _shouldBufferMembershipDependentMessage(
            groupId: groupId,
            senderId: senderId,
            messageId: wireMessageId,
            msgRepo: msgRepo,
            data: data,
          )) {
        _bufferMembershipDependentMessage(
          groupId: groupId,
          senderId: senderId,
          messageId: wireMessageId,
          data: data,
        );
        return;
      }

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
        await _requestReceivedMessageKeyRepairIfLocalEpochIsBehind(result);
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
              notificationService: _notificationService,
              conversationTracker: _groupConversationTracker,
              getAppLifecycleState: _getAppLifecycleState,
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

  Future<void> _requestReceivedMessageKeyRepairIfLocalEpochIsBehind(
    GroupMessage message,
  ) async {
    final incomingKeyEpoch = message.keyGeneration;
    if (incomingKeyEpoch <= 0) return;

    try {
      final latestKey = await _groupRepo.getLatestKey(message.groupId);
      final localKeyEpoch = latestKey?.keyGeneration;
      if (localKeyEpoch != null && incomingKeyEpoch <= localKeyEpoch) {
        return;
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL',
        details: {
          'groupId': message.groupId.length > 8
              ? message.groupId.substring(0, 8)
              : message.groupId,
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'incomingKeyEpoch': incomingKeyEpoch,
          'localKeyEpoch': localKeyEpoch,
          'reason': groupKeyRepairReasonReceivedMessageEpochMissingLocalKey,
        },
      );
      await _requestGroupKeyRepair(
        GroupKeyRepairRequest(
          groupId: message.groupId,
          keyEpoch: incomingKeyEpoch,
          reason: groupKeyRepairReasonReceivedMessageEpochMissingLocalKey,
          messageId: message.id,
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_RECEIVED_MESSAGE_KEY_REPAIR_CHECK_ERROR',
        details: {
          'groupId': message.groupId.length > 8
              ? message.groupId.substring(0, 8)
              : message.groupId,
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'incomingKeyEpoch': incomingKeyEpoch,
          'error': e.toString(),
        },
      );
    }
  }

  Future<bool> _shouldBufferMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required GroupMessageRepository msgRepo,
    required Map<String, dynamic> data,
  }) async {
    if (senderId.isEmpty) return false;
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) return false;
    if (await _groupRepo.getMember(groupId, senderId) != null) return false;
    final incomingKeyEpoch = data['keyEpoch'];
    final latestKey = incomingKeyEpoch is int && incomingKeyEpoch > 0
        ? await _groupRepo.getLatestKey(groupId)
        : null;
    if (latestKey != null &&
        latestKey.keyGeneration > 0 &&
        incomingKeyEpoch is int &&
        incomingKeyEpoch < latestKey.keyGeneration) {
      return false;
    }
    final membershipWatermark = group.lastMembershipEventAt?.toUtc();
    final messageTimestamp = DateTime.tryParse(
      data['timestamp'] as String? ?? '',
    )?.toUtc();
    final removalCutoff = await msgRepo.getLatestRemovalTimestampForSender(
      groupId,
      senderId,
    );
    if (removalCutoff != null &&
        (messageTimestamp == null ||
            messageTimestamp.isBefore(removalCutoff))) {
      return false;
    }
    if (membershipWatermark != null &&
        messageTimestamp != null &&
        !messageTimestamp.isAfter(membershipWatermark)) {
      return false;
    }
    if (messageId != null &&
        messageId.isNotEmpty &&
        await msgRepo.getMessage(messageId) != null) {
      return false;
    }
    final text = data['text'];
    final isSystemPayload = text is String && text.startsWith('{"__sys":');
    return !isSystemPayload;
  }

  void _bufferMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required Map<String, dynamic> data,
  }) {
    final queue = _pendingMembershipDependentMessagesByGroup.putIfAbsent(
      groupId,
      () => <_PendingMembershipDependentMessage>[],
    );
    if (messageId != null && messageId.isNotEmpty) {
      queue.removeWhere((pending) => pending.messageId == messageId);
    }
    queue.add(
      _PendingMembershipDependentMessage(
        data: Map<String, dynamic>.from(data),
        senderPeerId: senderId,
        messageId: messageId,
        receivedAt: DateTime.now().toUtc(),
      ),
    );
    while (queue.length > _maxPendingMembershipDependentMessagesPerGroup) {
      queue.removeAt(0);
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_BUFFERED',
      details: {
        'groupId': _membershipFlowId(groupId),
        'senderId': _membershipFlowId(senderId),
        if (messageId != null && messageId.isNotEmpty)
          'messageId': _membershipFlowId(messageId),
        'queueDepth': queue.length,
      },
    );
  }

  void _bufferPersistedMembershipDependentMessage(GroupMessage message) {
    if (message.id.startsWith('sys-')) return;
    if (message.text.isEmpty && message.media.isEmpty) return;

    _bufferMembershipDependentMessage(
      groupId: message.groupId,
      senderId: message.senderPeerId,
      messageId: message.id,
      data: {
        'groupId': message.groupId,
        'senderId': message.senderPeerId,
        if (message.senderUsername != null)
          'senderUsername': message.senderUsername,
        if (message.transportPeerId != null)
          'transportPeerId': message.transportPeerId,
        if (message.transportPeerId != null)
          'senderDeviceId': message.transportPeerId,
        'keyEpoch': message.keyGeneration,
        'text': message.text,
        'timestamp': message.timestamp.toUtc().toIso8601String(),
        'messageId': message.id,
        if (message.quotedMessageId != null)
          'quotedMessageId': message.quotedMessageId,
        if (message.media.isNotEmpty)
          'media': message.media
              .map((attachment) => attachment.toJson())
              .toList(growable: false),
      },
    );
  }

  Future<void> _flushMembershipDependentMessages({
    required String groupId,
    required Iterable<String> memberPeerIds,
    required GroupMessageRepository msgRepo,
  }) async {
    final queue = _pendingMembershipDependentMessagesByGroup[groupId];
    if (queue == null || queue.isEmpty) return;
    final allowedSenders = memberPeerIds
        .where((peerId) => peerId.isNotEmpty)
        .toSet();
    if (allowedSenders.isEmpty) return;

    final ready = <_PendingMembershipDependentMessage>[];
    queue.removeWhere((pending) {
      final shouldFlush = allowedSenders.contains(pending.senderPeerId);
      if (shouldFlush) ready.add(pending);
      return shouldFlush;
    });
    if (queue.isEmpty) {
      _pendingMembershipDependentMessagesByGroup.remove(groupId);
    }
    if (ready.isEmpty) return;

    ready.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSHED',
      details: {'groupId': _membershipFlowId(groupId), 'count': ready.length},
    );
    for (final pending in ready) {
      final member = await _groupRepo.getMember(groupId, pending.senderPeerId);
      final pendingTimestamp = DateTime.tryParse(
        pending.data['timestamp'] as String? ?? '',
      )?.toUtc();
      if (member != null &&
          pendingTimestamp != null &&
          pendingTimestamp.isBefore(member.joinedAt.toUtc())) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_HANDLE_INCOMING_MSG_SENDER_BEFORE_JOINED_REJECTED',
          details: {
            'groupId': _membershipFlowId(groupId),
            'senderId': _membershipFlowId(pending.senderPeerId),
            'joinedAt': member.joinedAt.toUtc().toIso8601String(),
          },
        );
        continue;
      }
      await _handleMessage(
        pending.data,
        msgRepoOverride: msgRepo,
        allowMembershipBuffer: false,
      );
    }
  }

  Future<int> _deleteContentMessagesAtOrAfterRemoval({
    required String groupId,
    required String removedPeerId,
    required DateTime? removedAt,
    required GroupMessageRepository msgRepo,
  }) async {
    if (removedPeerId.isEmpty || removedAt == null) {
      return 0;
    }
    final normalizedRemovedAt = removedAt.toUtc();
    final messages = <GroupMessage>[];
    const pageSize = 200;
    var offset = 0;
    while (true) {
      final page = await msgRepo.getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      messages.addAll(page);
      if (page.length < pageSize) break;
      offset += page.length;
    }

    var deleted = 0;
    for (final message in messages) {
      if (message.id.startsWith('sys-')) continue;
      if (message.senderPeerId != removedPeerId) continue;
      if (message.timestamp.toUtc().isBefore(normalizedRemovedAt)) continue;
      _bufferPersistedMembershipDependentMessage(message);
      await msgRepo.deleteMessage(message.id);
      deleted++;
    }
    if (deleted > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_REPAIRED',
        details: {
          'groupId': _membershipFlowId(groupId),
          'removedPeerId': _membershipFlowId(removedPeerId),
          'removedAt': normalizedRemovedAt.toIso8601String(),
          'deletedCount': deleted,
        },
      );
    }
    return deleted;
  }

  /// Downloads media attachments for an incoming group message.
  ///
  /// Runs fire-and-forget after the message is emitted. On completion,
  /// re-emits the message so the UI can update with resolved local paths.
  Future<void> _autoDownloadMedia(GroupMessage message) async {
    try {
      final bridge = _bridge;
      final mediaAttachmentRepo = _mediaAttachmentRepo;
      final mediaFileManager = _mediaFileManager;
      if (bridge == null ||
          mediaAttachmentRepo == null ||
          mediaFileManager == null) {
        return;
      }

      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        message.id,
      );
      if (attachments.isEmpty) return;

      for (final attachment in attachments) {
        if (attachment.downloadStatus != 'pending') continue;
        try {
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
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
      final explicitMembershipEventAt = switch (sysType) {
        'member_removed' => _parseMembershipEventAt(
          parsed['removedAt'] as String?,
        ),
        'member_added' || 'members_added' => _parseMembershipEventAt(
          parsed['eventAt'] as String?,
        ),
        _ => null,
      };
      final eventAt = switch (sysType) {
        'member_removed' => explicitMembershipEventAt ?? envelopeEventAt,
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
        'member_added' ||
        'members_added' => explicitMembershipEventAt ?? envelopeEventAt,
        _ => envelopeEventAt,
      };
      var membershipVersion = _resolveIncomingMembershipVersion(
        groupConfig,
        explicitEventAt: explicitMembershipEventAt,
        fallbackEventAt: eventAt,
      );

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
        if (signedTransitionAudit != null &&
            explicitMembershipEventAt == null &&
            (sysType == 'member_added' || sysType == 'members_added')) {
          membershipVersion = (
            eventAt: signedTransitionAudit.eventAt,
            hasConfigVersion: false,
          );
        }
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
              signedTransitionAudit.auditHash;
        }
      }

      if (sysType == 'member_added') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: membershipVersion.eventAt,
            allowEqualVersionReplay: true,
            parsed: parsed,
            msgRepo: msgRepo,
          )) {
            return;
          }
          if (await _isDuplicateMembersAddedReplayAlreadyApplied(
            groupId,
            parsed,
            sysType: sysType,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
          )) {
            await _recordMembershipEventWatermark(
              groupId,
              membershipVersion.eventAt,
            );
            emitFlowEvent(
              layer: 'FL',
              event:
                  'GROUP_MESSAGE_LISTENER_DUPLICATE_MEMBERS_ADDED_REPLAY_IGNORED',
              details: {
                'groupId': groupId.length > 8
                    ? groupId.substring(0, 8)
                    : groupId,
                'type': sysType ?? 'null',
              },
            );
            return;
          }
          await appendSystemEventLog();
          await _handleMemberAdded(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'members_added') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: membershipVersion.eventAt,
            allowEqualVersionReplay: true,
            parsed: parsed,
            msgRepo: msgRepo,
          )) {
            return;
          }
          if (await _isDuplicateMembersAddedReplayAlreadyApplied(
            groupId,
            parsed,
            sysType: sysType,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
          )) {
            await _recordMembershipEventWatermark(
              groupId,
              membershipVersion.eventAt,
            );
            emitFlowEvent(
              layer: 'FL',
              event:
                  'GROUP_MESSAGE_LISTENER_DUPLICATE_MEMBERS_ADDED_REPLAY_IGNORED',
              details: {
                'groupId': groupId.length > 8
                    ? groupId.substring(0, 8)
                    : groupId,
                'type': sysType ?? 'null',
              },
            );
            return;
          }
          await appendSystemEventLog();
          await _handleMembersAdded(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'member_removed') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMemberRemovedEvent(
            groupId,
            parsed: parsed,
            sysType: sysType,
            eventAt: membershipVersion.eventAt,
            hasExplicitConfigVersion: membershipVersion.hasConfigVersion,
          )) {
            return;
          }
          await _handleMemberRemoved(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
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
            eventAt: membershipVersion.eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleMemberRoleUpdated(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'group_dissolved') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMembershipEvent(
            groupId,
            sysType: sysType,
            eventAt: membershipVersion.eventAt,
          )) {
            return;
          }
          await appendSystemEventLog();
          await _handleGroupDissolved(
            groupId,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
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
      existingRole: existingMember.role,
      requestedPermissions: requestedPermissions,
      existingPermissions: existingMember.permissions,
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
    for (final member in normalizeGroupConfigMemberEntries(members)) {
      if (member['peerId'] == peerId) {
        return member;
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
    final rawMemberData = parsed['member'];
    final memberData = rawMemberData is Map
        ? Map<String, dynamic>.from(rawMemberData)
        : null;
    final validMemberData =
        memberData != null &&
            hasDeliverableGroupConfigMemberIdentity(memberData)
        ? memberData
        : null;
    final addedPeerId = validMemberData?['peerId'] as String?;
    final addedUsername = validMemberData?['username'] as String?;
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    final keyMaterialRejectReason =
        (memberData == null
            ? null
            : groupMemberConfigKeyMaterialRejectReason(memberData)) ??
        (groupConfig == null
            ? null
            : groupConfigMemberKeyMaterialRejectReason(groupConfig));
    if (keyMaterialRejectReason != null) {
      _emitMemberKeyMaterialRejected(
        groupId,
        sysType: 'member_added',
        reason: keyMaterialRejectReason,
      );
      return;
    }
    if (validMemberData != null) {
      final member = GroupMember.fromConfigMap(
        groupId: groupId,
        map: validMemberData,
        existing: addedPeerId == null
            ? null
            : _existingMemberForMembershipAddEvent(
                await _groupRepo.getMember(groupId, addedPeerId),
                eventAt,
              ),
        joinedAt: eventAt ?? DateTime.now().toUtc(),
      );
      await _groupRepo.saveMember(member);
    } else if (memberData != null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_INVALID_MEMBER_ADDED_IGNORED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'peerId': (memberData['peerId'] as String?) ?? '?',
        },
      );
    }

    // Update Go topic validator config
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
        eventMemberPeerIds: {
          if (addedPeerId != null && addedPeerId.isNotEmpty) addedPeerId,
        },
        msgRepo: msgRepo,
        pruneOmittedMembers: false,
      );
      await _syncGroupConfig(
        groupId,
        await _buildLocalGroupConfigSnapshot(groupId) ?? groupConfig,
      );
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
    if (addedPeerId != null && addedPeerId.isNotEmpty) {
      await _flushMembershipDependentMessages(
        groupId: groupId,
        memberPeerIds: <String>[addedPeerId],
        msgRepo: msgRepo,
      );
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_ADDED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'memberPeerId': (validMemberData?['peerId'] as String?) ?? '?',
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
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    String? directMembersRejectReason;
    if (membersList != null) {
      for (final memberData in membersList) {
        if (memberData is! Map) {
          continue;
        }
        final reason = groupMemberConfigKeyMaterialRejectReason(memberData);
        if (reason != null) {
          final peerId = memberData['peerId'];
          directMembersRejectReason =
              peerId is String && peerId.trim().isNotEmpty
              ? '$reason:${peerId.trim()}'
              : reason;
          break;
        }
      }
    }
    final keyMaterialRejectReason =
        directMembersRejectReason ??
        (groupConfig == null
            ? null
            : groupConfigMemberKeyMaterialRejectReason(groupConfig));
    if (keyMaterialRejectReason != null) {
      _emitMemberKeyMaterialRejected(
        groupId,
        sysType: 'members_added',
        reason: keyMaterialRejectReason,
      );
      return;
    }
    final validAddedMembers = <({String peerId, String? username})>[];
    if (membersList != null) {
      for (final memberData in membersList) {
        if (memberData is! Map) {
          continue;
        }
        final data = Map<String, dynamic>.from(memberData);
        if (!hasDeliverableGroupConfigMemberIdentity(data)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_INVALID_MEMBERS_ADDED_ENTRY_IGNORED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'peerId': (data['peerId'] as String?) ?? '?',
            },
          );
          continue;
        }
        final peerId = data['peerId'] as String?;
        if (peerId != null && peerId.isNotEmpty) {
          validAddedMembers.add((
            peerId: peerId,
            username: data['username'] as String?,
          ));
        }
        final member = GroupMember.fromConfigMap(
          groupId: groupId,
          map: data,
          existing: peerId == null
              ? null
              : _existingMemberForMembershipAddEvent(
                  await _groupRepo.getMember(groupId, peerId),
                  eventAt,
                ),
          joinedAt: eventAt ?? DateTime.now().toUtc(),
        );
        await _groupRepo.saveMember(member);
      }
    }

    if (groupConfig != null) {
      final addedPeerIds = validAddedMembers
          .map((member) => member.peerId)
          .toSet();
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
        eventMemberPeerIds: addedPeerIds,
        msgRepo: msgRepo,
        pruneOmittedMembers: false,
      );
      await _syncGroupConfig(
        groupId,
        await _buildLocalGroupConfigSnapshot(groupId) ?? groupConfig,
      );
    }

    final addedMembers = validAddedMembers;
    if (addedMembers.isNotEmpty) {
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
    await _flushMembershipDependentMessages(
      groupId: groupId,
      memberPeerIds: addedMembers.map((member) => member.peerId),
      msgRepo: msgRepo,
    );

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
    await _inviteDeliveryAttemptRepo?.markJoined(
      groupId: groupId,
      peerId: joinedPeerId,
      username: memberData?['username'] as String?,
      joinedAt: eventAt,
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
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final memberData = parsed['member'] as Map<String, dynamic>?;
    final removedPeerId = memberData?['peerId'] as String?;
    final removedUsername = memberData?['username'] as String?;

    // Check if the removed member is self
    final getSelfPeerId = _getSelfPeerId;
    final bridge = _bridge;
    if (removedPeerId != null && getSelfPeerId != null && bridge != null) {
      final selfPeerId = await getSelfPeerId();
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

        final shouldRetainHistory = await _hasRetainableSelfRemovalHistory(
          groupId,
          msgRepo,
        );
        if (shouldRetainHistory) {
          final selfRemovalCompleted = await _retainSelfRemovedLocalHistory(
            groupId,
            parsed,
            selfPeerId: selfPeerId,
            senderId: senderId,
            senderUsername: senderUsername,
            removedUsername: removedUsername,
            eventAt: eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
          );
          if (selfRemovalCompleted) {
            _removedController.add(groupId);
          }
          return;
        }

        final resolvedEventAt = eventAt ?? DateTime.now().toUtc();
        await msgRepo.saveMessage(
          GroupMessage(
            id: buildGroupRemovalCutoffMessageId(
              groupId: groupId,
              senderPeerId: removedPeerId,
              removedAt: resolvedEventAt,
            ),
            groupId: groupId,
            senderPeerId: senderId.isNotEmpty ? senderId : removedPeerId,
            senderUsername: senderUsername,
            text: '',
            timestamp: resolvedEventAt,
            status: 'cutoff',
            isIncoming: false,
            readAt: resolvedEventAt,
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await _recordMembershipEventWatermark(groupId, resolvedEventAt);

        final selfRemovalCompleted = await _deleteSelfRemovedLocalGroup(
          groupId: groupId,
          bridge: bridge,
          selfPeerId: selfPeerId,
          removedAt: resolvedEventAt,
        );

        await appendSystemEventLog();

        if (!selfRemovalCompleted) {
          return;
        }

        // Notify UI that we were removed from this group
        _removedController.add(groupId);
        return;
      }
    }

    final resolvedEventAt = eventAt ?? DateTime.now().toUtc();

    await appendSystemEventLog();

    // Not self — retain the removed member's verification material for
    // historical replay before deleting the active membership row.
    if (removedPeerId != null && removedPeerId.isNotEmpty) {
      final removedMember = await _groupRepo.getMember(groupId, removedPeerId);
      final snapshotRepo = _groupRepo is RemovedGroupMemberSnapshotRepository
          ? _groupRepo as RemovedGroupMemberSnapshotRepository
          : null;
      if (removedMember != null && snapshotRepo != null) {
        await snapshotRepo.saveRemovedMemberSnapshot(
          removedMember,
          removedAt: resolvedEventAt,
        );
      }
      await _groupRepo.removeMember(groupId, removedPeerId);
    }

    // Update Go topic validator config
    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    var snapshotHasNoActiveMembers = false;
    if (groupConfig != null) {
      final rawMembers = groupConfig['members'];
      snapshotHasNoActiveMembers = rawMembers is List && rawMembers.isEmpty;
      final normalizedGroupConfig = normalizeGroupConfigPayload(
        groupId: groupId,
        groupConfig: groupConfig,
      );
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        normalizedGroupConfig,
        eventAt: eventAt,
        msgRepo: msgRepo,
        pruneOmittedMembers: snapshotHasNoActiveMembers,
      );
      final syncGroupConfig =
          await _buildLocalGroupConfigSnapshot(groupId) ??
          normalizedGroupConfig;
      final synced = await _syncGroupConfig(
        groupId,
        syncGroupConfig,
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
      eventAt: resolvedEventAt,
    );
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _messageController.add(savedTimelineMessage);

    await _recordMembershipEventWatermark(groupId, resolvedEventAt);
    await _deleteContentMessagesAtOrAfterRemoval(
      groupId: groupId,
      removedPeerId: removedPeerId ?? '',
      removedAt: resolvedEventAt,
      msgRepo: msgRepo,
    );

    if (snapshotHasNoActiveMembers) {
      await _closeGroupForEmptyMembership(
        groupId,
        senderId: senderId,
        eventAt: resolvedEventAt,
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

  Future<bool> _deleteSelfRemovedLocalGroup({
    required String groupId,
    required Bridge bridge,
    required String selfPeerId,
    DateTime? removedAt,
  }) async {
    await callGroupLeave(bridge, groupId);
    if (await _repairLateSelfRemovalLeaveIfReadded(
      groupId,
      selfPeerId: selfPeerId,
      removedAt: removedAt,
    )) {
      return false;
    }
    await _groupRepo.removeAllMembers(groupId);
    await _groupRepo.removeAllKeys(groupId);
    await _groupRepo.deleteGroup(groupId);
    return true;
  }

  Future<bool> _hasRetainableSelfRemovalHistory(
    String groupId,
    GroupMessageRepository msgRepo,
  ) async {
    const pageSize = 200;
    var offset = 0;
    while (true) {
      final messages = await msgRepo.getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      if (messages.any((message) => !message.id.startsWith('sys-'))) {
        return true;
      }
      if (messages.length < pageSize) {
        return false;
      }
      offset += messages.length;
    }
  }

  Future<bool> _retainSelfRemovedLocalHistory(
    String groupId,
    Map<String, dynamic> parsed, {
    required String selfPeerId,
    required String senderId,
    required String senderUsername,
    String? removedUsername,
    DateTime? eventAt,
    required GroupMessageRepository msgRepo,
    required Future<void> Function() appendSystemEventLog,
  }) async {
    await callGroupLeave(_bridge!, groupId);
    if (await _repairLateSelfRemovalLeaveIfReadded(
      groupId,
      selfPeerId: selfPeerId,
      removedAt: eventAt,
    )) {
      await appendSystemEventLog();
      return false;
    }

    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    if (groupConfig != null) {
      await _applyAuthoritativeGroupConfigSnapshot(
        groupId,
        groupConfig,
        eventAt: eventAt,
        msgRepo: msgRepo,
        pruneOmittedMembers: false,
      );
    }
    await _groupRepo.removeMember(groupId, selfPeerId);
    await _groupRepo.removeAllKeys(groupId);

    await appendSystemEventLog();
    final resolvedEventAt = eventAt ?? DateTime.now().toUtc();
    final timelineMessage = buildMemberRemovedTimelineMessage(
      groupId: groupId,
      removedPeerId: selfPeerId,
      removedUsername: removedUsername,
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
    await _deleteContentMessagesAtOrAfterRemoval(
      groupId: groupId,
      removedPeerId: selfPeerId,
      removedAt: resolvedEventAt,
      msgRepo: msgRepo,
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_HISTORY_RETAINED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    return true;
  }

  Future<bool> _repairLateSelfRemovalLeaveIfReadded(
    String groupId, {
    required String selfPeerId,
    DateTime? removedAt,
  }) async {
    final removedAtUtc = removedAt?.toUtc();
    if (removedAtUtc == null) {
      return false;
    }

    final group = await _groupRepo.getGroup(groupId);
    if (group == null || group.isDissolved) {
      return false;
    }

    final selfMember = await _groupRepo.getMember(groupId, selfPeerId);
    final latestKey = await _groupRepo.getLatestKey(groupId);
    if (selfMember == null ||
        latestKey == null ||
        latestKey.keyGeneration <= 0 ||
        latestKey.encryptedKey.trim().isEmpty) {
      return false;
    }

    final selfRejoinedAfterRemoval = selfMember.joinedAt.toUtc().isAfter(
      removedAtUtc,
    );
    final membershipAdvancedAfterRemoval =
        group.lastMembershipEventAt?.toUtc().isAfter(removedAtUtc) ?? false;
    final keyAdvancedAfterRemoval = latestKey.createdAt.toUtc().isAfter(
      removedAtUtc,
    );
    if (!selfRejoinedAfterRemoval &&
        !membershipAdvancedAfterRemoval &&
        !keyAdvancedAfterRemoval) {
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      return false;
    }

    final members = await _groupRepo.getMembers(groupId);
    if (!members.any((member) => member.peerId == selfPeerId)) {
      return false;
    }

    final groupConfig = buildGroupConfigPayload(group, members);
    try {
      await callGroupJoinWithConfig(
        bridge,
        groupId: groupId,
        groupConfig: groupConfig,
        groupKey: latestKey.encryptedKey,
        keyEpoch: latestKey.keyGeneration,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVAL_LEAVE_REPAIRED_AFTER_READD',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'keyEpoch': latestKey.keyGeneration,
        },
      );
      return true;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVAL_LEAVE_REPAIR_FAILED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': e.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _closeGroupForEmptyMembership(
    String groupId, {
    required String senderId,
    required DateTime eventAt,
  }) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return;
    }

    if (!group.isDissolved) {
      await _groupRepo.updateGroup(
        group.copyWith(
          isDissolved: true,
          dissolvedAt: eventAt,
          dissolvedBy: senderId.isEmpty ? group.dissolvedBy : senderId,
          lastMembershipEventAt: eventAt,
        ),
      );
    }

    final bridge = _bridge;
    if (bridge != null) {
      try {
        await callGroupLeave(bridge, groupId);
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_EMPTY_MEMBERSHIP_LEAVE_ERROR',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'error': e.toString(),
          },
        );
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_EMPTY_MEMBERSHIP_DISSOLVED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'senderId': senderId.length > 8 ? senderId.substring(0, 8) : senderId,
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
            ...?updatedUsername == null
                ? null
                : <String, dynamic>{'username': updatedUsername},
            'role': newRole.toValue(),
          },
          existing: existingMember,
          joinedAt: eventAt ?? DateTime.now().toUtc(),
        ),
      );
    }

    final getSelfPeerId = _getSelfPeerId;
    if (getSelfPeerId != null &&
        updatedPeerId != null &&
        updatedPeerId.isNotEmpty) {
      final selfPeerId = await getSelfPeerId();
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

    final bridge = _bridge;
    if (bridge != null) {
      try {
        await callGroupLeave(bridge, groupId);
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

      final reactionRepo = _reactionRepo;
      if (reactionRepo == null) return;

      final (result, change) = await handleIncomingGroupReaction(
        groupRepo: _groupRepo,
        reactionRepo: reactionRepo,
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

  void _emitMemberKeyMaterialRejected(
    String groupId, {
    required String sysType,
    required String reason,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBER_KEY_MATERIAL_REJECTED',
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

  ({DateTime? eventAt, bool hasConfigVersion})
  _resolveIncomingMembershipVersion(
    Map<String, dynamic>? groupConfig, {
    required DateTime? explicitEventAt,
    required DateTime? fallbackEventAt,
  }) {
    final configVersionAt = parseGroupConfigVersionAt(groupConfig);
    final hasAuthoritativeConfigVersion =
        configVersionAt != null &&
        (explicitEventAt == null ||
            configVersionAt.isAtSameMomentAs(explicitEventAt));
    return (
      eventAt: explicitEventAt ?? configVersionAt ?? fallbackEventAt,
      hasConfigVersion: hasAuthoritativeConfigVersion,
    );
  }

  Future<bool> _isDuplicateMembersAddedReplayAlreadyApplied(
    String groupId,
    Map<String, dynamic> parsed, {
    required String? sysType,
    required String senderId,
    required String senderUsername,
    required DateTime? eventAt,
    required GroupMessageRepository msgRepo,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final addedMembers = _timelineAddedMembersForReplay(sysType, parsed);
    if (addedMembers.isEmpty) {
      return false;
    }

    final timelineMessage = buildMembersAddedTimelineMessage(
      groupId: groupId,
      addedMembers: addedMembers,
      senderId: senderId,
      senderUsername: senderUsername,
      eventAt: eventAt,
    );
    return await msgRepo.getMessage(timelineMessage.id) != null;
  }

  List<({String peerId, String? username})> _timelineAddedMembersForReplay(
    String? sysType,
    Map<String, dynamic> parsed,
  ) {
    if (sysType == 'member_added') {
      final rawMemberData = parsed['member'];
      final memberData = rawMemberData is Map
          ? Map<String, dynamic>.from(rawMemberData)
          : null;
      if (memberData == null ||
          !hasDeliverableGroupConfigMemberIdentity(memberData)) {
        return const [];
      }
      final peerId = memberData['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) {
        return const [];
      }
      return [(peerId: peerId, username: memberData['username'] as String?)];
    }

    if (sysType != 'members_added') {
      return const [];
    }

    final membersList = parsed['members'] as List<dynamic>?;
    if (membersList == null) {
      return const [];
    }

    final validAddedMembers = <({String peerId, String? username})>[];
    for (final memberData in membersList) {
      if (memberData is! Map) {
        continue;
      }
      final data = Map<String, dynamic>.from(memberData);
      if (!hasDeliverableGroupConfigMemberIdentity(data)) {
        continue;
      }
      final peerId = data['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) {
        continue;
      }
      validAddedMembers.add((
        peerId: peerId,
        username: data['username'] as String?,
      ));
    }
    return validAddedMembers;
  }

  Future<bool> _shouldIgnoreStaleMembershipEvent(
    String groupId, {
    required String? sysType,
    required DateTime? eventAt,
    bool allowEqualVersionReplay = false,
    Map<String, dynamic>? parsed,
    GroupMessageRepository? msgRepo,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final watermark = await _resolveMembershipEventWatermark(groupId);
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    final isMembershipAdd =
        sysType == 'member_added' || sysType == 'members_added';
    if (isMembershipAdd &&
        await _membershipAddAdvancesLocalMember(
          groupId,
          parsed: parsed,
          eventAt: eventAt,
          watermark: watermark,
          msgRepo: msgRepo,
        )) {
      return false;
    }

    if (!isMembershipAdd &&
        allowEqualVersionReplay &&
        eventAt.isAtSameMomentAs(watermark)) {
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

  Future<bool> _membershipAddAdvancesLocalMember(
    String groupId, {
    required Map<String, dynamic>? parsed,
    required DateTime eventAt,
    required DateTime watermark,
    GroupMessageRepository? msgRepo,
  }) async {
    final memberMaps = <Map<String, dynamic>>[];
    final singleMember = parsed?['member'];
    if (singleMember is Map) {
      memberMaps.add(Map<String, dynamic>.from(singleMember));
    }
    final multipleMembers = parsed?['members'];
    if (multipleMembers is List<dynamic>) {
      memberMaps.addAll(
        multipleMembers.whereType<Map>().map(
          (member) => Map<String, dynamic>.from(member),
        ),
      );
    }

    if (memberMaps.isEmpty) {
      return false;
    }

    final normalizedEventAt = eventAt.toUtc();
    final normalizedWatermark = watermark.toUtc();
    final groupConfig = parsed?['groupConfig'] as Map<String, dynamic>?;
    final configMembers = groupConfig?['members'] as List<dynamic>?;
    if (configMembers != null) {
      final snapshotPeerIds = configMembers
          .whereType<Map>()
          .map((memberData) => memberData['peerId'] as String? ?? '')
          .where((peerId) => peerId.isNotEmpty)
          .toSet();
      final existingMembers = await _groupRepo.getMembers(groupId);
      final omitsNewerExistingMember = existingMembers.any(
        (member) =>
            member.joinedAt.toUtc().isAfter(normalizedEventAt) &&
            !snapshotPeerIds.contains(member.peerId),
      );
      if (omitsNewerExistingMember) {
        return false;
      }
    }

    for (final memberData in memberMaps) {
      if (!hasDeliverableGroupConfigMemberIdentity(memberData)) {
        continue;
      }
      final peerId = memberData['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) {
        continue;
      }
      final existingMember = await _groupRepo.getMember(groupId, peerId);
      if (existingMember != null &&
          normalizedEventAt.isAfter(existingMember.joinedAt.toUtc())) {
        return true;
      }
      if (existingMember != null &&
          normalizedEventAt.isAtSameMomentAs(existingMember.joinedAt.toUtc()) &&
          normalizedEventAt.isAtSameMomentAs(normalizedWatermark) &&
          msgRepo != null &&
          !await _membershipAddTimelineExists(
            msgRepo,
            groupId: groupId,
            memberMaps: memberMaps,
            eventAt: normalizedEventAt,
          )) {
        return true;
      }
      if (existingMember == null &&
          await _canApplyAddForMissingMember(
            groupId,
            peerId: peerId,
            eventAt: normalizedEventAt,
            msgRepo: msgRepo,
          )) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _canApplyAddForMissingMember(
    String groupId, {
    required String peerId,
    required DateTime eventAt,
    GroupMessageRepository? msgRepo,
  }) async {
    if (msgRepo == null) {
      return false;
    }

    final latestRemovalAt = await msgRepo
        .getLatestSystemEventTimestampForTarget(
          groupId,
          eventType: 'member_removed',
          targetId: peerId,
        );
    return latestRemovalAt == null || latestRemovalAt.toUtc().isBefore(eventAt);
  }

  Future<bool> _membershipAddTimelineExists(
    GroupMessageRepository msgRepo, {
    required String groupId,
    required List<Map<String, dynamic>> memberMaps,
    required DateTime eventAt,
  }) async {
    final memberKey = memberMaps
        .map((memberData) => memberData['peerId'] as String? ?? '')
        .where((peerId) => peerId.isNotEmpty)
        .join(',');
    if (memberKey.isEmpty) {
      return false;
    }
    final latest = await msgRepo.getLatestSystemEventTimestampForTarget(
      groupId,
      eventType: 'members_added',
      targetId: memberKey,
    );
    return latest?.toUtc().isAtSameMomentAs(eventAt.toUtc()) ?? false;
  }

  Future<bool> _shouldIgnoreStaleMemberRemovedEvent(
    String groupId, {
    required Map<String, dynamic> parsed,
    required String? sysType,
    required DateTime? eventAt,
    bool hasExplicitConfigVersion = false,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final watermark = await _resolveMembershipEventWatermark(groupId);
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    if (hasExplicitConfigVersion) {
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

  Future<void> _applyAuthoritativeGroupConfigSnapshot(
    String groupId,
    Map<String, dynamic> groupConfig, {
    DateTime? eventAt,
    Set<String>? eventMemberPeerIds,
    GroupMessageRepository? msgRepo,
    bool pruneOmittedMembers = true,
  }) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return;
    }

    final normalizedGroupConfig = normalizeGroupConfigPayload(
      groupId: groupId,
      groupConfig: groupConfig,
    );
    final membersList = normalizedGroupConfig['members'] as List<dynamic>?;
    if (membersList == null) {
      return;
    }
    final keyMaterialRejectReason = groupConfigMemberKeyMaterialRejectReason(
      normalizedGroupConfig,
    );
    if (keyMaterialRejectReason != null) {
      _emitMemberKeyMaterialRejected(
        groupId,
        sysType: 'group_config_snapshot',
        reason: keyMaterialRejectReason,
      );
      return;
    }

    final existingMembers = await _groupRepo.getMembers(groupId);
    final existingByPeerId = {
      for (final member in existingMembers) member.peerId: member,
    };
    final snapshotPeerIds = <String>{};
    MemberRole? selfSnapshotRole;
    final getSelfPeerId = _getSelfPeerId;
    final selfPeerId = getSelfPeerId != null ? await getSelfPeerId() : null;

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

      if (eventAt != null && msgRepo != null) {
        final latestRemovalAt = await msgRepo
            .getLatestSystemEventTimestampForTarget(
              groupId,
              eventType: 'member_removed',
              targetId: peerId,
            );
        if (latestRemovalAt != null &&
            !latestRemovalAt.toUtc().isBefore(eventAt.toUtc())) {
          continue;
        }
      }

      await _groupRepo.saveMember(
        GroupMember.fromConfigMap(
          groupId: groupId,
          map: memberData,
          existing: existingMember,
          joinedAt: _resolveAuthoritativeSnapshotJoinedAt(
            peerId: peerId,
            existingMember: existingMember,
            groupCreatedAt: group.createdAt,
            eventAt: eventAt,
            eventMemberPeerIds: eventMemberPeerIds,
          ),
          preserveMissingPermissions: false,
        ),
      );
    }

    if (pruneOmittedMembers) {
      for (final existingMember in existingMembers) {
        if (!snapshotPeerIds.contains(existingMember.peerId)) {
          await _groupRepo.removeMember(groupId, existingMember.peerId);
        }
      }
    }

    var resolvedType = group.type;
    final groupTypeValue = normalizedGroupConfig['groupType'] as String?;
    if (groupTypeValue != null && groupTypeValue.isNotEmpty) {
      try {
        resolvedType = GroupType.fromValue(groupTypeValue);
      } on ArgumentError {
        resolvedType = group.type;
      }
    }

    final createdAtValue = normalizedGroupConfig['createdAt'] as String?;
    final resolvedCreatedAt =
        DateTime.tryParse(createdAtValue ?? '')?.toUtc() ?? group.createdAt;
    final metadataUpdatedAtValue =
        normalizedGroupConfig['metadataUpdatedAt'] as String?;
    final resolvedMetadataUpdatedAt = DateTime.tryParse(
      metadataUpdatedAtValue ?? '',
    )?.toUtc();
    final containsAvatarBlobId = normalizedGroupConfig.containsKey(
      'avatarBlobId',
    );
    final containsAvatarMime = normalizedGroupConfig.containsKey('avatarMime');
    final resolvedAvatarBlobId = containsAvatarBlobId
        ? normalizedGroupConfig['avatarBlobId'] as String?
        : group.avatarBlobId;
    final resolvedAvatarMime = containsAvatarMime
        ? normalizedGroupConfig['avatarMime'] as String?
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
        name: normalizedGroupConfig['name'] as String? ?? group.name,
        type: resolvedType,
        description: normalizedGroupConfig.containsKey('description')
            ? normalizedGroupConfig['description'] as String?
            : group.description,
        avatarBlobId: resolvedAvatarBlobId,
        avatarMime: resolvedAvatarMime,
        avatarPath: nextAvatarPath,
        createdAt: resolvedCreatedAt,
        createdBy:
            normalizedGroupConfig['createdBy'] as String? ?? group.createdBy,
        myRole: selfSnapshotRole == null
            ? group.myRole
            : (selfSnapshotRole == MemberRole.admin
                  ? GroupRole.admin
                  : GroupRole.member),
        lastMetadataEventAt:
            resolvedMetadataUpdatedAt ?? group.lastMetadataEventAt,
      ),
    );

    final bridge = _bridge;
    if (bridge != null &&
        resolvedAvatarBlobId != null &&
        resolvedAvatarMime != null &&
        (avatarChanged || nextAvatarPath == null)) {
      final avatarPath = await _downloadGroupAvatarFn(
        bridge: bridge,
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

  Future<Map<String, dynamic>?> _buildLocalGroupConfigSnapshot(
    String groupId,
  ) async {
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) {
      return null;
    }
    final members = await _groupRepo.getMembers(groupId);
    return buildGroupConfigPayload(group, members);
  }

  DateTime _resolveAuthoritativeSnapshotJoinedAt({
    required String peerId,
    required GroupMember? existingMember,
    required DateTime groupCreatedAt,
    required DateTime? eventAt,
    required Set<String>? eventMemberPeerIds,
  }) {
    final existingJoinedAt = existingMember?.joinedAt.toUtc();
    if (existingJoinedAt != null) {
      if (eventAt != null &&
          eventMemberPeerIds != null &&
          eventMemberPeerIds.contains(peerId)) {
        final normalizedEventAt = eventAt.toUtc();
        if (normalizedEventAt.isAfter(existingJoinedAt)) {
          return normalizedEventAt;
        }
      }
      return existingJoinedAt;
    }

    final groupCreatedAtUtc = groupCreatedAt.toUtc();
    if (eventMemberPeerIds == null || eventMemberPeerIds.contains(peerId)) {
      return eventAt?.toUtc() ?? groupCreatedAtUtc;
    }
    return groupCreatedAtUtc;
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

  GroupMember? _existingMemberForMembershipAddEvent(
    GroupMember? existing,
    DateTime? eventAt,
  ) {
    if (existing == null || eventAt == null) {
      return existing;
    }

    final normalizedEventAt = eventAt.toUtc();
    if (!normalizedEventAt.isAfter(existing.joinedAt.toUtc())) {
      return existing;
    }

    return existing.copyWith(joinedAt: normalizedEventAt);
  }

  Future<bool> _syncGroupConfig(
    String groupId,
    Map<String, dynamic> groupConfig, {
    bool emitFailureEvent = false,
  }) async {
    final bridge = _bridge;
    if (bridge == null) {
      return true;
    }

    final keyMaterialRejectReason = groupConfigMemberKeyMaterialRejectReason(
      groupConfig,
    );
    if (keyMaterialRejectReason != null) {
      _emitMemberKeyMaterialRejected(
        groupId,
        sysType: 'group_config_sync',
        reason: keyMaterialRejectReason,
      );
      return false;
    }

    try {
      final normalizedGroupConfig = normalizeGroupConfigPayload(
        groupId: groupId,
        groupConfig: groupConfig,
      );
      await callGroupUpdateConfig(
        bridge,
        groupId: groupId,
        groupConfig: normalizedGroupConfig,
      );
      return true;
    } catch (_) {
      try {
        final normalizedGroupConfig = normalizeGroupConfigPayload(
          groupId: groupId,
          groupConfig: groupConfig,
        );
        await callGroupUpdateConfig(
          bridge,
          groupId: groupId,
          groupConfig: normalizedGroupConfig,
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
