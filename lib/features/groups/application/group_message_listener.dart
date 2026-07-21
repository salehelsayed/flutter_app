import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/application/trusted_private_group_system_event.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_multi_device_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_membership_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_reaction.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_membership_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/features/push/application/private_media_notification_body.dart';

typedef RecoverGroupDispatcherOverflow =
    Future<void> Function(Map<String, dynamic> diagnostic);

/// Re-keys a group after a remote member departure that the local device did
/// not author. Returns `true` if a new key epoch was generated and distributed.
///
/// Wired in [main] to [rotateAndDistributeGroupKey] with the local identity;
/// the use case is creator-gated, so only the group creator's device produces a
/// rotation (a single deterministic rotator — see [GroupMessageListener]
/// member_removed handling). Defaults to a no-op when not injected (tests / the
/// non-creator path).
typedef RotateGroupKeyAfterRemoteRemoval =
    Future<bool> Function(String groupId);

const _maxPendingMembershipDependentMessagesPerGroup = 50;

class _PendingMembershipDependentMessage {
  _PendingMembershipDependentMessage({
    required this.data,
    required this.senderPeerId,
    required this.messageId,
    required this.receivedAt,
    this.durableId,
  });

  final Map<String, dynamic> data;
  final String senderPeerId;
  final String? messageId;
  final DateTime receivedAt;
  final String? durableId;
}

bool _samePendingReaction(
  GroupPendingReaction current,
  GroupPendingReaction loaded,
) =>
    current.id == loaded.id &&
    current.groupId == loaded.groupId &&
    current.messageId == loaded.messageId &&
    current.senderPeerId == loaded.senderPeerId &&
    current.transportPeerId == loaded.transportPeerId &&
    current.senderDeviceId == loaded.senderDeviceId &&
    current.senderPublicKey == loaded.senderPublicKey &&
    current.reactionJson == loaded.reactionJson &&
    current.receivedAt.toUtc().isAtSameMomentAs(loaded.receivedAt.toUtc());

class _SignedTransitionAuditActorBinding {
  const _SignedTransitionAuditActorBinding({
    this.deviceId,
    this.transportPeerId,
  });

  final String? deviceId;
  final String? transportPeerId;

  bool get hasBinding =>
      (deviceId != null && deviceId!.isNotEmpty) ||
      (transportPeerId != null && transportPeerId!.isNotEmpty);
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
  // 118 Phase 4: shared per-conversation tone debounce (the same tracker the
  // direct listener uses; group + direct keys are disjoint).
  final NotificationToneTracker? _notificationToneTracker;
  final Future<DurableNotificationToneLease> Function()
  _durableNotificationCoordinatorResolver;
  final AppLifecycleState Function()? _getAppLifecycleState;
  final RecentRemoteNotificationGate _remoteNotificationGate;
  final ReactionRepository? _reactionRepo;
  final GroupInviteDeliveryAttemptRepository? _inviteDeliveryAttemptRepo;
  final DownloadGroupAvatarFn _downloadGroupAvatarFn;
  final AppendGroupEventLogEntry? _appendGroupEventLogEntry;
  final Stream<Map<String, dynamic>>? _groupDiagnosticEvents;
  final GroupPendingKeyRepairRepository? _pendingKeyRepairRepo;
  final GroupPendingMembershipMessageRepository? _pendingMembershipMessageRepo;
  final GroupPendingReactionRepository? _pendingReactionRepo;
  final RequestGroupKeyRepair _requestGroupKeyRepair;
  final RecoverGroupDispatcherOverflow? _recoverFromDispatcherOverflow;
  final RotateGroupKeyAfterRemoteRemoval? _rotateGroupKeyAfterRemoteRemoval;
  final AccountMigrationNetworkGate _accountMigrationNetworkGate;
  final HoldPendingSiblingDeviceFn? _holdPendingSiblingDevice;
  final GroupPrivateMediaAvailability _privateMediaAvailability;

  StreamSubscription<void>? _subscription;
  StreamSubscription<void>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _diagnosticSubscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();
  final Map<String, Future<void>> _groupConfigWorkQueue = {};
  final Map<String, Future<void>> _userMessageWorkQueue = {};
  final Map<String, String> _acceptedSignedTransitionAuditHashesBySourceId = {};
  final Map<String, List<_PendingMembershipDependentMessage>>
  _pendingMembershipDependentMessagesByGroup = {};
  final Set<Future<void>> _inFlightHandlers = {};
  Future<void>? _dispatcherOverflowRecovery;
  Future<void>? _stopFuture;
  Future<DurableNotificationToneLease?>? _durableNotificationCoordinatorFuture;
  String? _cachedSelfPeerId;
  var _hasResolvedSelfPeerId = false;
  Future<String?>? _selfPeerIdLoadFuture;
  var _isStopping = false;
  var _isDisposed = false;

  GroupMessageListener({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    Bridge? bridge,
    Future<String?> Function()? getSelfPeerId,
    MediaAttachmentRepository? mediaAttachmentRepo,
    MediaFileManager? mediaFileManager,
    NotificationService? notificationService,
    ActiveConversationTracker? groupConversationTracker,
    NotificationToneTracker? notificationToneTracker,
    Future<DurableNotificationToneLease> Function()?
    durableNotificationCoordinatorResolver,
    AppLifecycleState Function()? getAppLifecycleState,
    RecentRemoteNotificationGate? remoteNotificationGate,
    ReactionRepository? reactionRepo,
    GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
    DownloadGroupAvatarFn? downloadGroupAvatarFn,
    AppendGroupEventLogEntry? appendGroupEventLogEntry,
    Stream<Map<String, dynamic>>? groupDiagnosticEvents,
    GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
    GroupPendingMembershipMessageRepository? pendingMembershipMessageRepo,
    GroupPendingReactionRepository? pendingReactionRepo,
    RequestGroupKeyRepair? requestGroupKeyRepair,
    RecoverGroupDispatcherOverflow? recoverFromDispatcherOverflow,
    RotateGroupKeyAfterRemoteRemoval? rotateGroupKeyAfterRemoteRemoval,
    AccountMigrationNetworkGate accountMigrationNetworkGate =
        allowAccountMigrationNetworkSideEffects,
    HoldPendingSiblingDeviceFn? holdPendingSiblingDevice,
    GroupPrivateMediaAvailability privateMediaAvailability =
        productionGroupPrivateMediaAvailability,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _bridge = bridge,
       _getSelfPeerId = getSelfPeerId,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _mediaFileManager = mediaFileManager,
       _notificationService = notificationService,
       _groupConversationTracker = groupConversationTracker,
       _notificationToneTracker = notificationToneTracker,
       _durableNotificationCoordinatorResolver =
           durableNotificationCoordinatorResolver ??
           DurableNotificationToneLease.openMobileDefault,
       _getAppLifecycleState = getAppLifecycleState,
       _remoteNotificationGate =
           remoteNotificationGate ?? recentRemoteNotificationGate,
       _reactionRepo = reactionRepo,
       _inviteDeliveryAttemptRepo = inviteDeliveryAttemptRepo,
       _downloadGroupAvatarFn = downloadGroupAvatarFn ?? downloadGroupAvatar,
       _appendGroupEventLogEntry = appendGroupEventLogEntry,
       _groupDiagnosticEvents = groupDiagnosticEvents,
       _pendingKeyRepairRepo = pendingKeyRepairRepo,
       _pendingMembershipMessageRepo = pendingMembershipMessageRepo,
       _pendingReactionRepo = pendingReactionRepo,
       _requestGroupKeyRepair =
           requestGroupKeyRepair ?? emitGroupKeyRepairRequest,
       _recoverFromDispatcherOverflow = recoverFromDispatcherOverflow,
       _rotateGroupKeyAfterRemoteRemoval = rotateGroupKeyAfterRemoteRemoval,
       _accountMigrationNetworkGate = accountMigrationNetworkGate,
       _holdPendingSiblingDevice = holdPendingSiblingDevice,
       _privateMediaAvailability = privateMediaAvailability;

  Future<DurableNotificationToneLease?>
  _resolveDurableNotificationCoordinator() {
    return _durableNotificationCoordinatorFuture ??=
        _openDurableNotificationCoordinator();
  }

  Future<DurableNotificationToneLease?>
  _openDurableNotificationCoordinator() async {
    try {
      return await _durableNotificationCoordinatorResolver();
    } catch (error) {
      // Claim storage is additive. If the mobile app-group/support directory is
      // unavailable, keep the legacy remote gate and in-memory tone behavior.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_NOTIFICATION_CLAIM_STORAGE_UNAVAILABLE',
        details: {'error': error.toString()},
      );
      return null;
    }
  }

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
    bool allowMembershipBuffer = false,
    bool membershipPhaseHeld = false,
  }) async {
    if (!await _allowsInboundAccountSideEffects(
      operation: 'group_replay_message',
      data: data,
    )) {
      return;
    }
    return _handleQueuedUserMessage(
      data,
      msgRepoOverride: msgRepoOverride,
      rethrowOnError: rethrowOnError,
      allowMembershipBuffer: allowMembershipBuffer,
      deliverySource: 'replay',
      membershipPhaseHeld: membershipPhaseHeld,
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
    if (_isDisposed || _subscription != null) return;
    _isStopping = false;

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_START',
      details: {},
    );

    _subscription = incomingGroupMessages
        .asyncMap(_handleLiveMessage)
        .listen(
          (_) {},
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
      // asyncMap serializes reaction handling exactly like the message path
      // above — no two _handleLiveReaction invocations overlap (INV-R6).
      _reactionSubscription = incomingGroupReactions
          .asyncMap(_handleLiveReaction)
          .listen(
            (_) {},
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
        _handleLiveDiagnosticEvent,
        onError: (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_DIAGNOSTIC_STREAM_ERROR',
            details: {'error': error.toString()},
          );
        },
      );
    }

    if (_pendingMembershipMessageRepo != null) {
      unawaited(_flushStartupDurableMembershipDependentMessages());
    }

    if (_pendingReactionRepo != null) {
      unawaited(_flushStartupDurablePendingReactions());
    }
  }

  bool get _canEmitToStreams {
    return !_isStopping &&
        !_isDisposed &&
        !_messageController.isClosed &&
        !_removedController.isClosed &&
        !_reactionChangeController.isClosed;
  }

  void _emitGroupMessage(GroupMessage message) {
    if (!_canEmitToStreams || _messageController.isClosed) return;
    _messageController.add(message);
  }

  void _emitGroupRemoved(String groupId) {
    if (!_canEmitToStreams || _removedController.isClosed) return;
    _removedController.add(groupId);
  }

  void _emitReactionChange(ReactionChange change) {
    if (!_canEmitToStreams || _reactionChangeController.isClosed) return;
    _reactionChangeController.add(change);
  }

  /// Replays buffered reactions whose target [message] has just been persisted
  /// (INV-R4). Each row is DELETED before its [ReactionChange] is emitted, so
  /// an overlapping startup + live flush can never double-emit (INV-R5).
  Future<void> _flushPendingReactionsForMessage(
    GroupMessage message, {
    bool membershipPhaseHeld = false,
  }) async {
    final repo = _pendingReactionRepo;
    final reactionRepo = _reactionRepo;
    if (repo == null || reactionRepo == null) return;
    if (_isStopping || _isDisposed) return;

    List<GroupPendingReaction> buffered;
    try {
      buffered = await repo.getPendingReactionsForMessage(
        groupId: message.groupId,
        messageId: message.id,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_BUFFER_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
      return;
    }
    if (buffered.isEmpty) return;
    buffered.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

    for (final pending in buffered) {
      if (_isStopping || _isDisposed) return;
      if (membershipPhaseHeld) {
        await _flushPendingReactionLocked(
          message: message,
          loaded: pending,
          repo: repo,
          reactionRepo: reactionRepo,
        );
      } else {
        await runSelfRemovedGroupLifecycleLeaf<void>(
          groupRepo: _groupRepo,
          groupId: pending.groupId,
          action: (_) => _flushPendingReactionLocked(
            message: message,
            loaded: pending,
            repo: repo,
            reactionRepo: reactionRepo,
          ),
        );
      }
    }
  }

  Future<void> _flushPendingReactionLocked({
    required GroupMessage message,
    required GroupPendingReaction loaded,
    required GroupPendingReactionRepository repo,
    required ReactionRepository reactionRepo,
  }) async {
    final currentRows = await repo.getPendingReactionsForMessage(
      groupId: loaded.groupId,
      messageId: loaded.messageId,
    );
    GroupPendingReaction? pending;
    for (final current in currentRows) {
      if (_samePendingReaction(current, loaded)) {
        pending = current;
        break;
      }
    }
    if (pending == null ||
        message.groupId != pending.groupId ||
        message.id != pending.messageId) {
      return;
    }

    // Atomically claim the exact row before emitting; if another flush already
    // took it, skip so the ReactionChange is emitted exactly once.
    final claimed = await repo.deletePendingReaction(pending.id);
    if (claimed == 0) return;
    try {
      final (result, change) = await handleIncomingGroupReaction(
        groupRepo: _groupRepo,
        reactionRepo: reactionRepo,
        msgRepo: _msgRepo,
        groupId: pending.groupId,
        senderId: pending.senderPeerId,
        senderDeviceId: pending.senderDeviceId,
        transportPeerId: pending.transportPeerId,
        senderPublicKey: pending.senderPublicKey,
        reactionJson: pending.reactionJson,
      );
      if (result == HandleGroupReactionResult.success && change != null) {
        final targetMessage = await _loadReactionDerivativeTarget(
          groupId: pending.groupId,
          change: change,
        );
        if (targetMessage != null) {
          _emitReactionChange(change);
          final wireReaction = GroupReactionPayload.fromDecryptedJson(
            pending.reactionJson,
          );
          await _maybeNotifyGroupReaction(
            groupId: pending.groupId,
            reactorPeerId: pending.senderPeerId,
            change: change,
            targetMessage: targetMessage,
            eventId: wireReaction?.eventId,
          );
        }
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_BUFFER_FLUSHED',
        details: {
          'groupId': pending.groupId.length > 8
              ? pending.groupId.substring(0, 8)
              : pending.groupId,
          'messageId': pending.messageId.length > 8
              ? pending.messageId.substring(0, 8)
              : pending.messageId,
          'result': result.name,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_BUFFER_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// Startup flush: replays buffered reactions whose target message already
  /// exists locally. Mirrors [_flushStartupDurableMembershipDependentMessages].
  Future<void> _flushStartupDurablePendingReactions() async {
    final repo = _pendingReactionRepo;
    if (repo == null || _isStopping || _isDisposed) return;
    try {
      final pending = await repo.getPendingReactions(
        limit: kMaxBufferedGroupReactionsPerGroup * 8,
      );
      final flushedKeys = <String>{};
      for (final row in pending) {
        if (_isStopping || _isDisposed) return;
        final key = '${row.groupId}\u0000${row.messageId}';
        if (!flushedKeys.add(key)) continue;
        final message = await _msgRepo.getMessage(row.messageId);
        if (message == null || message.groupId != row.groupId) continue;
        await _flushPendingReactionsForMessage(message);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_BUFFER_STARTUP_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _handleLiveMessage(Map<String, dynamic> data) {
    return _trackInFlight(() async {
      if (!await _allowsInboundAccountSideEffects(
        operation: 'group_live_message',
        data: data,
      )) {
        return;
      }
      await _handleQueuedUserMessage(
        data,
        requestRecoveryOnError: true,
        deliverySource: 'live',
      );
    }());
  }

  Future<void> _handleLiveReaction(Map<String, dynamic> data) {
    // Return the tracked future so the reaction subscription's asyncMap awaits
    // the WHOLE handler — gate included — before delivering the next reaction.
    // Without this, two reactions' gate checks + applies could interleave
    // across their await points (INV-R6).
    return _trackInFlight(() async {
      if (!await _allowsInboundAccountSideEffects(
        operation: 'group_live_reaction',
        data: data,
      )) {
        return;
      }
      await _handleReaction(data);
    }());
  }

  void _handleLiveDiagnosticEvent(Map<String, dynamic> event) {
    _trackInFlight(() async {
      if (!await _allowsInboundAccountSideEffects(
        operation: 'group_live_diagnostic',
        data: event,
      )) {
        return;
      }
      await _handleGroupDiagnosticEvent(event);
    }());
  }

  Future<bool> _allowsInboundAccountSideEffects({
    required String operation,
    Map<String, dynamic>? data,
  }) async {
    try {
      final peerId = await _resolveSelfPeerId();
      final allowed = await _accountMigrationNetworkGate(
        peerId: peerId,
        operation: operation,
      );
      if (!allowed) {
        emitFlowEvent(
          layer: 'FL',
          event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
          details: {
            'operation': operation,
            'family': 'group',
            'peerId': ?peerId,
            if (data?['groupId'] != null)
              'groupId': data!['groupId'].toString().length > 8
                  ? data['groupId'].toString().substring(0, 8)
                  : data['groupId'].toString(),
          },
        );
      }
      return allowed;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED',
        details: {
          'operation': operation,
          'family': 'group',
          'reason': 'gate_error',
          'error': e.toString(),
        },
      );
      return false;
    }
  }

  Future<void> _trackInFlight(Future<void> work) {
    late final Future<void> tracked;
    tracked = work.whenComplete(() {
      _inFlightHandlers.remove(tracked);
    });
    _inFlightHandlers.add(tracked);
    return tracked;
  }

  Future<void> _awaitInFlightHandlers() async {
    while (_inFlightHandlers.isNotEmpty) {
      final current = _inFlightHandlers.toList(growable: false);
      await Future.wait<void>(current.map((work) => work.catchError((_) {})));
    }
  }

  String? _userMessageWorkKey(Map<String, dynamic> data) {
    final rawMessageId = data['messageId'];
    if (rawMessageId is! String) return null;
    final messageId = rawMessageId.trim();
    if (messageId.isEmpty) return null;

    final rawText = data['text'];
    final text = rawText is String ? rawText : '';
    if (text.startsWith('{"__sys":')) return null;

    return messageId;
  }

  Future<void> _handleQueuedUserMessage(
    Map<String, dynamic> data, {
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
    bool allowMembershipBuffer = true,
    bool requestRecoveryOnError = false,
    String deliverySource = 'listener',
    bool membershipPhaseHeld = false,
  }) {
    final queueKey = _userMessageWorkKey(data);
    if (queueKey == null) {
      return _handleMessage(
        data,
        msgRepoOverride: msgRepoOverride,
        rethrowOnError: rethrowOnError,
        allowMembershipBuffer: allowMembershipBuffer,
        requestRecoveryOnError: requestRecoveryOnError,
        deliverySource: deliverySource,
        membershipPhaseHeld: membershipPhaseHeld,
        deferKeyRepairRequest: membershipPhaseHeld,
      );
    }

    final previous = _userMessageWorkQueue[queueKey];
    final predecessor = previous?.catchError((_) {}) ?? Future<void>.value();
    late final Future<void> tracked;
    tracked = predecessor
        .then<void>(
          (_) => _handleMessage(
            data,
            msgRepoOverride: msgRepoOverride,
            rethrowOnError: rethrowOnError,
            allowMembershipBuffer: allowMembershipBuffer,
            requestRecoveryOnError: requestRecoveryOnError,
            deliverySource: deliverySource,
            membershipPhaseHeld: membershipPhaseHeld,
            deferKeyRepairRequest: membershipPhaseHeld,
          ),
        )
        .whenComplete(() {
          if (identical(_userMessageWorkQueue[queueKey], tracked)) {
            _userMessageWorkQueue.remove(queueKey);
          }
        });
    _userMessageWorkQueue[queueKey] = tracked;
    return tracked;
  }

  Future<void> _handleGroupDiagnosticEvent(Map<String, dynamic> event) async {
    final rejectedOutbound = await markOutboundGroupMessageRejectedByValidator(
      msgRepo: _msgRepo,
      diagnostic: event,
    );
    if (rejectedOutbound != null) {
      _emitGroupMessage(rejectedOutbound);
      return;
    }

    if (event['event'] == 'group:dispatcher_overflow') {
      await _handleGroupDispatcherOverflow(event);
      return;
    }

    if (event['event'] == groupPushLossDetectedEvent) {
      await _requestGroupPushLossRecovery(
        event,
        flowEventPrefix: 'GROUP_PUSH_LOSS_RECOVERY',
      );
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
      _emitGroupMessage(placeholder);
    }
  }

  Future<void> _handleGroupDispatcherOverflow(
    Map<String, dynamic> event,
  ) async {
    if (event['lastEvent'] != 'group_message:received') {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY_IGNORED',
        details: _groupPushLossRecoveryDiagnosticDetails(event),
      );
      return;
    }

    await _requestGroupPushLossRecovery(
      event,
      flowEventPrefix: 'GROUP_DISPATCHER_OVERFLOW_RECOVERY',
    );
  }

  Future<void> _requestGroupPushLossRecovery(
    Map<String, dynamic> event, {
    required String flowEventPrefix,
  }) async {
    final recover = _recoverFromDispatcherOverflow;
    if (recover == null) {
      emitFlowEvent(
        layer: 'FL',
        event: '${flowEventPrefix}_UNAVAILABLE',
        details: _groupPushLossRecoveryDiagnosticDetails(event),
      );
      return;
    }

    final currentRecovery = _dispatcherOverflowRecovery;
    if (currentRecovery != null) {
      emitFlowEvent(
        layer: 'FL',
        event: '${flowEventPrefix}_COALESCED',
        details: _groupPushLossRecoveryDiagnosticDetails(event),
      );
      return;
    }

    final diagnostic = Map<String, dynamic>.unmodifiable(event);
    final recovery = Future<void>.microtask(() async {
      emitFlowEvent(
        layer: 'FL',
        event: '${flowEventPrefix}_REQUESTED',
        details: _groupPushLossRecoveryDiagnosticDetails(diagnostic),
      );
      try {
        await recover(diagnostic);
        emitFlowEvent(
          layer: 'FL',
          event: '${flowEventPrefix}_DONE',
          details: _groupPushLossRecoveryDiagnosticDetails(diagnostic),
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: '${flowEventPrefix}_ERROR',
          details: {
            ..._groupPushLossRecoveryDiagnosticDetails(diagnostic),
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

  Map<String, dynamic> _groupPushLossRecoveryDiagnosticDetails(
    Map<String, dynamic> event,
  ) {
    return {
      if (event.containsKey('event')) 'event': event['event'],
      if (event.containsKey('reason')) 'reason': event['reason'],
      if (event.containsKey('streamFailureReason'))
        'streamFailureReason': event['streamFailureReason'],
      'lastEvent': event['lastEvent']?.toString(),
      if (event.containsKey('state')) 'state': event['state'],
      if (event.containsKey('droppedCount'))
        'droppedCount': event['droppedCount'],
      if (event.containsKey('queueDepth')) 'queueDepth': event['queueDepth'],
      if (event.containsKey('maxQueueSize'))
        'maxQueueSize': event['maxQueueSize'],
      if (event.containsKey('groupId')) 'groupId': event['groupId'],
      if (event.containsKey('messageId')) 'messageId': event['messageId'],
      if (event.containsKey('keyEpoch')) 'keyEpoch': event['keyEpoch'],
      if (event.containsKey('senderId')) 'senderId': event['senderId'],
      if (event.containsKey('senderDeviceId'))
        'senderDeviceId': event['senderDeviceId'],
      if (event.containsKey('transportPeerId'))
        'transportPeerId': event['transportPeerId'],
    };
  }

  Map<String, dynamic> _liveGroupPushLossDiagnostic(
    Map<String, dynamic> data,
    Object error,
  ) {
    final diagnostic = <String, dynamic>{
      'event': groupPushLossDetectedEvent,
      'reason': 'live_group_message_processing_error',
      'error': error.toString(),
    };
    for (final field in const [
      'groupId',
      'messageId',
      'keyEpoch',
      'senderId',
      'senderDeviceId',
      'transportPeerId',
    ]) {
      if (data.containsKey(field)) {
        diagnostic[field] = data[field];
      }
    }
    return diagnostic;
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
      'logicalDeliveryId',
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
    bool requestRecoveryOnError = false,
    String deliverySource = 'listener',
    bool membershipPhaseHeld = false,
    bool deferKeyRepairRequest = false,
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

      final wireMessageId = data['messageId'] as String?;
      final wireLogicalDeliveryId = data['logicalDeliveryId'] as String?;
      final isSystemPayload = text.startsWith('{"__sys":');
      if (isSystemPayload) {
        if (allowMembershipBuffer &&
            await _shouldBufferPreJoinSystemMessage(
              groupId: groupId,
              senderId: senderId,
              messageId: wireMessageId,
              msgRepo: msgRepo,
              data: data,
              text: text,
            )) {
          await _bufferMembershipDependentMessage(
            groupId: groupId,
            senderId: senderId,
            messageId: wireMessageId,
            data: data,
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_PRE_JOIN_SYSTEM_BUFFERED',
            details: {
              'groupId': _membershipFlowId(groupId),
              'senderId': _membershipFlowId(senderId),
              if (wireMessageId != null && wireMessageId.isNotEmpty)
                'messageId': _membershipFlowId(wireMessageId),
            },
          );
          return;
        }
        final bridge = _bridge;
        if (bridge == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_SYSTEM_NO_BRIDGE_REJECTED',
            details: {
              'groupId': _membershipFlowId(groupId),
              'senderId': _membershipFlowId(senderId),
              if (wireMessageId != null && wireMessageId.isNotEmpty)
                'messageId': _membershipFlowId(wireMessageId),
            },
          );
          return;
        }
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

      // Drop events that have neither text nor media. These are not valid
      // user messages — most likely a malformed envelope from upstream
      // (e.g. a partial-decrypt failure on the Go side that emits a
      // skeleton event without `text`). Persisting them produces empty
      // bubbles that survive cold-restart. The offline-drain undecryptable
      // path persists its own user-readable placeholder elsewhere; this
      // listener should never silently persist a row with no body.
      final mediaListForEmptyCheck = (data['media'] as List?) ?? const [];
      final hasExplicitPrivateMediaPolicy = GroupPrivateMediaPolicy.wireKeys
          .any(data.containsKey);
      if (text.isEmpty &&
          mediaListForEmptyCheck.isEmpty &&
          !hasExplicitPrivateMediaPolicy) {
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

      final mediaRaw = data['media'] as List<dynamic>?;
      final media = mediaRaw?.cast<Map<String, dynamic>>();
      final wireQuotedMessageId = data['quotedMessageId'] as String?;
      // 236: exact-bool decode — absent/null/string values stay false.
      final wireIsForwarded = data['isForwarded'] == true;
      final selfPeerId = await _resolveSelfPeerId();
      if (allowMembershipBuffer &&
          await _shouldBufferMembershipDependentMessage(
            groupId: groupId,
            senderId: senderId,
            messageId: wireMessageId,
            msgRepo: msgRepo,
            data: data,
          )) {
        await _bufferMembershipDependentMessage(
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
        logicalDeliveryId: wireLogicalDeliveryId,
        quotedMessageId: wireQuotedMessageId,
        isForwarded: wireIsForwarded,
        privateMediaPolicyFields: Map<String, Object?>.from(data),
        media: media,
        mediaAttachmentRepo: _mediaAttachmentRepo,
        appendGroupEventLogEntry: _appendGroupEventLogEntry,
        deliverySource: deliverySource,
      );

      if (result != null) {
        _emitGroupMessage(result);
        // The target message just landed — replay any reactions that arrived
        // before it (INV-R4). This single site serves BOTH live and offline
        // drain, because the drain replays messages through the same
        // _handleMessage → _emitGroupMessage path.
        await _flushPendingReactionsForMessage(
          result,
          membershipPhaseHeld: membershipPhaseHeld,
        );
        // A real live delivery for this group+epoch supersedes any synthetic
        // `live:` decryption-failure placeholder from the same sender — clears
        // the stuck placeholder and prevents the duplicate. Placed after the
        // message is persisted/emitted so a mid-way crash can never delete the
        // placeholder without the real message landing.
        final pendingKeyRepairRepo = _pendingKeyRepairRepo;
        if (pendingKeyRepairRepo != null &&
            result.keyGeneration > 0 &&
            senderId.isNotEmpty) {
          await supersedeLiveGroupDecryptionRepairForDelivery(
            pendingKeyRepairRepo: pendingKeyRepairRepo,
            msgRepo: msgRepo,
            groupId: groupId,
            senderPeerId: senderId,
            transportPeerId: transportPeerId,
            keyEpoch: result.keyGeneration,
          );
        }
        if (!deferKeyRepairRequest) {
          await _requestReceivedMessageKeyRepairIfLocalEpochIsBehind(result);
        }
        if (!_privateMediaAvailability.allowsMediaDerivatives(
          result.privateMediaPolicy,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_PRIVATE_MEDIA_DERIVATIVES_SUPPRESSED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'messageId': result.id.length > 8
                  ? result.id.substring(0, 8)
                  : result.id,
            },
          );
          return;
        }
        final isPrivateNotification = result.privateMediaPolicy.isPrivate;
        final persistedAttachments =
            isPrivateNotification || _mediaAttachmentRepo == null
            ? <MediaAttachment>[]
            : await _mediaAttachmentRepo.getAttachmentsForMessage(
                result.id,
                owner: MediaOwnerLane.group,
              );

        // Show notification for incoming group messages (skip own messages)
        if (senderId != selfPeerId &&
            _notificationService != null &&
            _groupConversationTracker != null &&
            _getAppLifecycleState != null) {
          final group = await _groupRepo.getGroup(groupId);
          final isMuted = group?.isMuted ?? false;
          final groupName = group?.name ?? 'Group';
          // Local notifications + the mute that suppresses them are device-local:
          // muting on one device must never silence another device.
          assert(
            isGroupMultiDeviceDeviceLocal(
              GroupMultiDeviceFacet.localNotifications,
            ),
          );
          assert(
            isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.mutePreference),
          );
          if (!isMuted) {
            await maybeShowNotification(
              notificationService: _notificationService,
              conversationTracker: _groupConversationTracker,
              getAppLifecycleState: _getAppLifecycleState,
              contactPeerId: 'group:$groupId',
              routePayload: NotificationRouteTarget.group(
                groupId,
                messageId: result.id,
              ).toPayload(),
              senderUsername: isPrivateNotification ? 'Mknoon' : groupName,
              // 04-P0 / QW-1: the OS banner body must use the sanitized,
              // member-bound fields the timeline persists (result.*), not the
              // raw wire `senderUsername`/`text` locals — otherwise bidi /
              // zero-width / overlong content the timeline strips still renders
              // in the most-trusted surface.
              messageText: isPrivateNotification
                  ? localizedGroupPrivateMediaNotificationBody()
                  : '${result.senderUsername ?? ''}: '
                        '${notificationBodyForMessage(result.text, persistedAttachments)}',
              messageId: result.id,
              toneTracker: _notificationToneTracker,
              durableNotificationCoordinatorResolver:
                  _resolveDurableNotificationCoordinator,
              notificationEventType: 'group_message',
              consumeRecentRemoteNotificationAnnouncement:
                  ({required payload, String? messageId}) =>
                      _remoteNotificationGate.consumeIfRecentAnnouncement(
                        payload: payload,
                        messageId: messageId,
                      ),
              // Keep group/announcement dedupe symmetric with direct chats. A
              // remote-first delivery is consumed above; a live-first delivery
              // writes the exact anchored message marker so a later recovery
              // path cannot emit the same banner again.
              markRecentRemoteNotificationAnnouncement:
                  ({required payload, String? messageId}) =>
                      _remoteNotificationGate.markAnnouncement(
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
      if (requestRecoveryOnError) {
        await _requestGroupPushLossRecovery(
          _liveGroupPushLossDiagnostic(data, e),
          flowEventPrefix: 'GROUP_PUSH_LOSS_RECOVERY',
        );
      }
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

  Future<void> flushPendingMembershipDependentMessagesForGroup(
    String groupId, {
    GroupMessageRepository? msgRepoOverride,
  }) async {
    final members = await _groupRepo.getMembers(groupId);
    if (members.isEmpty) return;
    await _flushMembershipDependentMessages(
      groupId: groupId,
      memberPeerIds: members.map((member) => member.peerId),
      msgRepo: msgRepoOverride ?? _msgRepo,
    );
  }

  Future<int> retryPendingKeyRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
  }) async {
    final bridge = _bridge;
    final pendingRepo = _pendingKeyRepairRepo;
    if (bridge == null || pendingRepo == null || keyEpoch <= 0) {
      return 0;
    }
    final runner = GroupPendingKeyRepairRunner(
      bridge: bridge,
      groupRepo: _groupRepo,
      msgRepo: _msgRepo,
      pendingKeyRepairRepo: pendingRepo,
      mediaAttachmentRepo: _mediaAttachmentRepo,
      reactionRepo: _reactionRepo,
      replayGroupEnvelope: (data) =>
          handleReplayEnvelope(data, allowMembershipBuffer: true),
    );
    return runner.retryPendingRepairsForKey(
      groupId: groupId,
      keyEpoch: keyEpoch,
    );
  }

  Future<bool> _shouldBufferPreJoinSystemMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required GroupMessageRepository msgRepo,
    required Map<String, dynamic> data,
    required String text,
  }) async {
    if (senderId.isEmpty) return false;
    final localSenderMember = await _groupRepo.getMember(groupId, senderId);
    if (localSenderMember != null) return false;
    if (messageId != null &&
        messageId.isNotEmpty &&
        await msgRepo.getMessage(messageId) != null) {
      return false;
    }

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    final sysType = parsed['__sys'] as String?;
    if (sysType != 'group_metadata_updated' &&
        sysType != 'members_added' &&
        sysType != 'member_role_updated') {
      return false;
    }
    final groupConfig = parsed['groupConfig'];
    if (groupConfig is! Map) return false;
    return _findGroupConfigMember(
          Map<String, dynamic>.from(groupConfig),
          senderId,
        ) !=
        null;
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

  Future<void> _bufferMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required Map<String, dynamic> data,
  }) async {
    final pendingData = Map<String, dynamic>.from(data);
    final receivedAt = DateTime.now().toUtc();
    final durable = await _saveDurableMembershipDependentMessage(
      groupId: groupId,
      senderId: senderId,
      messageId: messageId,
      data: pendingData,
      receivedAt: receivedAt,
    );
    final queue = _pendingMembershipDependentMessagesByGroup.putIfAbsent(
      groupId,
      () => <_PendingMembershipDependentMessage>[],
    );
    if (messageId != null && messageId.isNotEmpty) {
      queue.removeWhere((pending) => pending.messageId == messageId);
    }
    queue.add(
      _PendingMembershipDependentMessage(
        data: pendingData,
        senderPeerId: senderId,
        messageId: messageId,
        receivedAt: receivedAt,
        durableId: durable?.id,
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

  Future<GroupPendingMembershipMessage?>
  _saveDurableMembershipDependentMessage({
    required String groupId,
    required String senderId,
    required String? messageId,
    required Map<String, dynamic> data,
    required DateTime receivedAt,
  }) async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null) return null;
    final payloadJson = jsonEncode(data);
    final pending = GroupPendingMembershipMessage(
      id: groupPendingMembershipMessageId(
        groupId: groupId,
        senderPeerId: senderId,
        messageId: messageId,
        receivedAt: receivedAt,
        payloadJson: payloadJson,
      ),
      groupId: groupId,
      senderPeerId: senderId,
      messageId: messageId,
      payloadJson: payloadJson,
      receivedAt: receivedAt,
      createdAt: receivedAt,
      updatedAt: receivedAt,
    );
    final saved = await pendingRepo.savePendingMessage(pending);
    await pendingRepo.pruneGroup(
      groupId,
      maxRows: _maxPendingMembershipDependentMessagesPerGroup,
    );
    return saved;
  }

  Future<void> _bufferPersistedMembershipDependentMessage(
    GroupMessage message,
  ) async {
    if (message.id.startsWith('sys-')) return;
    if (message.text.isEmpty && message.media.isEmpty) return;

    await _bufferMembershipDependentMessage(
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
        if (message.isForwarded) 'isForwarded': true,
        ...?message.mediaPolicy.toWireExtras(),
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
    final allowedSenders = memberPeerIds
        .where((peerId) => peerId.isNotEmpty)
        .toSet();
    if (allowedSenders.isEmpty) return;

    final ready = <_PendingMembershipDependentMessage>[];
    final queue = _pendingMembershipDependentMessagesByGroup[groupId];
    if (queue != null && queue.isNotEmpty) {
      queue.removeWhere((pending) {
        final shouldFlush = allowedSenders.contains(pending.senderPeerId);
        if (shouldFlush) ready.add(pending);
        return shouldFlush;
      });
      if (queue.isEmpty) {
        _pendingMembershipDependentMessagesByGroup.remove(groupId);
      }
    }

    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo != null) {
      final durable = await pendingRepo.getPendingMessagesForGroupAndSenders(
        groupId: groupId,
        senderPeerIds: allowedSenders,
        limit: _maxPendingMembershipDependentMessagesPerGroup,
      );
      for (final pending in durable) {
        ready.add(_pendingMembershipDependentMessageFromDurable(pending));
      }
    }

    if (ready.isEmpty) return;

    final deduped = <String, _PendingMembershipDependentMessage>{};
    for (final pending in ready) {
      final key = _pendingMembershipDependentMessageKey(pending);
      final existing = deduped[key];
      if (existing == null ||
          (existing.durableId == null && pending.durableId != null)) {
        deduped[key] = pending;
      }
    }
    ready
      ..clear()
      ..addAll(deduped.values);
    ready.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSHED',
      details: {'groupId': _membershipFlowId(groupId), 'count': ready.length},
    );
    for (final pending in ready) {
      final text = pending.data['text'] as String? ?? '';
      if (text.startsWith('{"__sys":')) {
        // Listener membership callbacks stay outside the non-reentrant phase;
        // a replayed B3 transition owns its own lock and cuts off later work.
        await _flushMembershipDependentMessageLeaf(
          groupId: groupId,
          pending: pending,
          msgRepo: msgRepo,
          membershipPhaseHeld: false,
        );
        final group = await _groupRepo.getGroup(groupId);
        if (group == null || group.selfRemovedAt != null) return;
        continue;
      }

      final guarded = await runSelfRemovedGroupLifecycleLeaf<void>(
        groupRepo: _groupRepo,
        groupId: groupId,
        action: (_) => _flushMembershipDependentMessageLeaf(
          groupId: groupId,
          pending: pending,
          msgRepo: msgRepo,
          membershipPhaseHeld: true,
        ),
      );
      if (guarded.didRun) {
        await _requestDeferredMembershipMessageKeyRepair(pending, msgRepo);
      }
    }
  }

  Future<void> _flushMembershipDependentMessageLeaf({
    required String groupId,
    required _PendingMembershipDependentMessage pending,
    required GroupMessageRepository msgRepo,
    required bool membershipPhaseHeld,
  }) async {
    if (!await _isExactPendingMembershipMessage(pending)) return;
    if (!membershipPhaseHeld) {
      final currentGroup = await _groupRepo.getGroup(groupId);
      if (currentGroup == null || currentGroup.selfRemovedAt != null) return;
    }
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
      await _deleteDurableMembershipDependentMessage(pending);
      return;
    }
    try {
      await _handleMessage(
        pending.data,
        msgRepoOverride: msgRepo,
        allowMembershipBuffer: false,
        rethrowOnError: true,
        deliverySource: 'membershipBuffer',
        membershipPhaseHeld: membershipPhaseHeld,
        deferKeyRepairRequest: membershipPhaseHeld,
      );
      await _deleteDurableMembershipDependentMessage(pending);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_CONTENT_FLUSH_ERROR',
        details: {
          'groupId': _membershipFlowId(groupId),
          'senderId': _membershipFlowId(pending.senderPeerId),
          if (pending.messageId != null && pending.messageId!.isNotEmpty)
            'messageId': _membershipFlowId(pending.messageId!),
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _requestDeferredMembershipMessageKeyRepair(
    _PendingMembershipDependentMessage pending,
    GroupMessageRepository msgRepo,
  ) async {
    final messageId = pending.messageId;
    if (messageId == null || messageId.isEmpty) return;
    final stored = await msgRepo.getMessage(messageId);
    if (stored != null) {
      // This runs only after the leaf released its membership phase. The
      // guarded request sender may now acquire its own bounded network phase
      // without nesting the non-reentrant lock.
      await _requestReceivedMessageKeyRepairIfLocalEpochIsBehind(stored);
    }
  }

  Future<bool> _isExactPendingMembershipMessage(
    _PendingMembershipDependentMessage loaded,
  ) async {
    final durableId = loaded.durableId;
    if (durableId == null || durableId.isEmpty) return true;
    final repo = _pendingMembershipMessageRepo;
    if (repo == null) return false;
    final rows = await repo.getPendingMessagesForGroupAndSenders(
      groupId: loaded.data['groupId'] as String? ?? '',
      senderPeerIds: <String>{loaded.senderPeerId},
      limit: _maxPendingMembershipDependentMessagesPerGroup,
    );
    for (final current in rows) {
      if (current.id == durableId &&
          current.senderPeerId == loaded.senderPeerId &&
          current.messageId == loaded.messageId &&
          current.payloadJson == jsonEncode(loaded.data) &&
          current.receivedAt.toUtc().isAtSameMomentAs(
            loaded.receivedAt.toUtc(),
          )) {
        return true;
      }
    }
    return false;
  }

  _PendingMembershipDependentMessage
  _pendingMembershipDependentMessageFromDurable(
    GroupPendingMembershipMessage pending,
  ) {
    return _PendingMembershipDependentMessage(
      data: jsonDecode(pending.payloadJson) as Map<String, dynamic>,
      senderPeerId: pending.senderPeerId,
      messageId: pending.messageId,
      receivedAt: pending.receivedAt,
      durableId: pending.id,
    );
  }

  String _pendingMembershipDependentMessageKey(
    _PendingMembershipDependentMessage pending,
  ) {
    final messageId = pending.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      return 'message:$messageId';
    }
    final durableId = pending.durableId;
    if (durableId != null && durableId.isNotEmpty) {
      return 'durable:$durableId';
    }
    return 'payload:${jsonEncode(pending.data)}';
  }

  Future<void> _deleteDurableMembershipDependentMessage(
    _PendingMembershipDependentMessage pending,
  ) async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null) return;
    final durableId = pending.durableId;
    if (durableId != null && durableId.isNotEmpty) {
      await pendingRepo.deletePendingMessage(durableId);
      return;
    }
    final messageId = pending.messageId;
    if (messageId != null && messageId.isNotEmpty) {
      final groupId = pending.data['groupId'] as String?;
      if (groupId != null && groupId.isNotEmpty) {
        await pendingRepo.deletePendingMessageByGroupAndMessageId(
          groupId: groupId,
          messageId: messageId,
        );
      }
    }
  }

  Future<void> _flushStartupDurableMembershipDependentMessages() async {
    final pendingRepo = _pendingMembershipMessageRepo;
    if (pendingRepo == null || _isStopping || _isDisposed) return;
    try {
      final pending = await pendingRepo.getPendingMessages(
        limit: _maxPendingMembershipDependentMessagesPerGroup * 4,
      );
      final readyByGroup = <String, Set<String>>{};
      for (final row in pending) {
        if (_isStopping || _isDisposed) return;
        final member = await _groupRepo.getMember(
          row.groupId,
          row.senderPeerId,
        );
        if (member == null) continue;
        readyByGroup
            .putIfAbsent(row.groupId, () => <String>{})
            .add(row.senderPeerId);
      }
      for (final entry in readyByGroup.entries) {
        if (_isStopping || _isDisposed) return;
        await _flushMembershipDependentMessages(
          groupId: entry.key,
          memberPeerIds: entry.value,
          msgRepo: _msgRepo,
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event:
            'GROUP_MESSAGE_LISTENER_MEMBERSHIP_DEPENDENT_STARTUP_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<int> _deleteContentMessagesAtOrAfterRemoval({
    required String groupId,
    required String removedPeerId,
    required DateTime? removedAt,
    DateTime? beforeRejoinAt,
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
    final normalizedBeforeRejoinAt = beforeRejoinAt?.toUtc();
    final repairDeletionRepo =
        msgRepo is GroupMembershipRepairDeletionRepository
        ? msgRepo as GroupMembershipRepairDeletionRepository
        : null;
    for (final message in messages) {
      if (message.id.startsWith('sys-')) continue;
      if (message.senderPeerId != removedPeerId) continue;
      final messageTimestamp = message.timestamp.toUtc();
      if (messageTimestamp.isBefore(normalizedRemovedAt)) continue;
      if (normalizedBeforeRejoinAt != null &&
          !messageTimestamp.isBefore(normalizedBeforeRejoinAt)) {
        continue;
      }
      await _bufferPersistedMembershipDependentMessage(message);
      if (repairDeletionRepo != null) {
        await repairDeletionRepo.deleteMessageForMembershipRepair(message.id);
      } else {
        await msgRepo.deleteMessage(message.id);
      }
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
        owner: MediaOwnerLane.group,
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
            owner: MediaOwnerLane.group,
            enforceGroupMediaPolicy: true,
            groupMessageRepo: _msgRepo,
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
      _emitGroupMessage(message);
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
        'member_role_updated' => _parseMembershipEventAt(
          parsed['eventAt'] as String?,
        ),
        _ => null,
      };
      final eventAt = switch (sysType) {
        'member_removed' => explicitMembershipEventAt ?? envelopeEventAt,
        'member_role_updated' => explicitMembershipEventAt ?? envelopeEventAt,
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
        // device_announce signs eventAt into its payload; the wire timestamp is
        // the Go publish time (a different instant), so the signed-audit verify
        // MUST reconstruct eventAt from the payload or it fails payload_mismatch.
        'device_announce' =>
          _parseMembershipEventAt(parsed['eventAt'] as String?) ??
              envelopeEventAt,
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
        sysType: sysType,
        parsed: parsed,
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

      // The audit-borne source id (nullable) is the ONLY id used for the
      // deterministic equal-instant tie-break; the synthesized fallback below
      // is device-local / JSON-key-order-dependent and must never be persisted
      // or compared as a tie-breaker.
      final auditSourceEventId = signedGroupTransitionAuditSourceEventId(
        parsed,
      );
      final transitionSourceEventId =
          auditSourceEventId ??
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
            if (sysType == 'group_metadata_updated' &&
                await _shouldRetryAcceptedSignedMetadataAvatarRecovery(
                  groupId,
                  eventAt: eventAt,
                  parsed: parsed,
                )) {
              emitFlowEvent(
                layer: 'FL',
                event:
                    'GROUP_MESSAGE_LISTENER_SIGNED_METADATA_DUPLICATE_RETRYING_AVATAR',
                details: {
                  'groupId': groupId.length > 8
                      ? groupId.substring(0, 8)
                      : groupId,
                  'type': sysType ?? 'null',
                },
              );
            } else {
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
          } else {
            _emitSignedTransitionAuditRejected(
              groupId,
              sysType: sysType,
              reason: 'conflicting_replay',
            );
            return;
          }
        }

        final actorPublicKey = await _resolveActorSigningPublicKey(
          groupId: groupId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          transportPeerId: transportPeerId,
          sysType: sysType,
        );
        final expectedAuditActorBinding =
            await _expectedSignedAuditActorBindingForSystemEvent(
              groupId: groupId,
              senderId: senderId,
              senderDeviceId: senderDeviceId,
              transportPeerId: transportPeerId,
              sysType: sysType,
              parsed: parsed,
            );
        final relaxSnapshotBackedPreTransitionHash =
            await _shouldRelaxSnapshotBackedPreTransitionHash(
              groupId: groupId,
              senderId: senderId,
              senderDeviceId: senderDeviceId,
              transportPeerId: transportPeerId,
              sysType: sysType,
              parsed: parsed,
            );
        // B4 terminal-dissolve relaxation: group_dissolved is a TERMINAL
        // transition — no subsequent transition's chain integrity depends on it
        // — so for an authenticated admin dissolve we skip the pre-transition
        // STATE hash equality check, which otherwise rejects with
        // previous_transition_hash_mismatch whenever the receiver's local
        // transition state diverged from the signer's (e.g. after a rejected
        // upstream key_rotated/members_added). This is SAFE because, by the time
        // we reach here, a group_dissolved has ALREADY passed the membership
        // authorization gate (_requiresMembershipEventAuthorization +
        // _isAuthorizedMembershipEventSender → admin-role), and the actor
        // signature plus device/transport binding are still verified by
        // verifyGroupTransitionAudit below (Option A). Only the chain STATE hash
        // — meaningless for a terminal event — is relaxed. (The snapshot-backed
        // relaxation machinery cannot help here: a dissolve carries no
        // groupConfig, so it short-circuits to false.)
        final relaxTerminalDissolvePreTransitionHash =
            sysType == 'group_dissolved';
        final preTransitionStateHash =
            relaxSnapshotBackedPreTransitionHash ||
                relaxTerminalDissolvePreTransitionHash
            ? null
            : await buildGroupTransitionStateHash(_groupRepo, groupId);
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
          actorDeviceId: expectedAuditActorBinding.deviceId,
          actorTransportPeerId: expectedAuditActorBinding.transportPeerId,
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
            msgRepo: msgRepo,
          )) {
            return;
          }
          await _handleMemberRemoved(
            groupId,
            parsed,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            explicitRemovalAt: explicitMembershipEventAt,
            removalEventId:
                auditSourceEventId ??
                ((sourceEventId?.trim().isNotEmpty ?? false)
                    ? sourceEventId
                    : null),
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
            removalEventId:
                auditSourceEventId ??
                ((sourceEventId?.trim().isNotEmpty ?? false)
                    ? sourceEventId
                    : null),
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
            eventId: auditSourceEventId,
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
            eventId: auditSourceEventId,
            msgRepo: msgRepo,
          );
        });
      } else if (sysType == 'group_dissolved') {
        await _enqueueGroupConfigWork(groupId, () async {
          await _handleGroupDissolved(
            groupId,
            senderId: senderId,
            senderUsername: senderUsername,
            eventAt: membershipVersion.eventAt,
            msgRepo: msgRepo,
            appendSystemEventLog: appendSystemEventLog,
          );
        });
      } else if (sysType == 'group_metadata_updated') {
        await _enqueueGroupConfigWork(groupId, () async {
          if (await _shouldIgnoreStaleMetadataEvent(
            groupId,
            sysType: sysType,
            eventAt: eventAt,
            parsed: parsed,
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
      } else if (sysType == 'device_announce') {
        await _handleDeviceAnnounce(
          groupId: groupId,
          senderId: senderId,
          senderDeviceId: senderDeviceId,
          transportPeerId: transportPeerId,
          parsed: parsed,
          hasVerifiedSignedAudit: signedTransitionAudit != null,
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

  /// B1b: handle a `device_announce` system event — a same-user sibling device
  /// announcing itself. Trust is the ACCOUNT-key signed audit (already verified
  /// upstream in [_handleSystemMessage]); this refuses any announce that did not
  /// carry a verified audit, then HOLDS the announced device as PENDING an
  /// explicit user trust decision (R2) — it does NOT auto-admit, because
  /// auto-admitting any account-signed device is a self-compromise vector. The
  /// hold seam is wired in production; absent (null) it is a no-op.
  Future<void> _handleDeviceAnnounce({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
    required Map<String, dynamic> parsed,
    required bool hasVerifiedSignedAudit,
  }) async {
    if (!hasVerifiedSignedAudit) {
      _emitSignedTransitionAuditRejected(
        groupId,
        sysType: 'device_announce',
        reason: 'device_announce_requires_signed_audit',
      );
      return;
    }
    final accountKey = await _resolveActorSigningPublicKey(
      groupId: groupId,
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      transportPeerId: transportPeerId,
      sysType: 'device_announce',
    );
    if (accountKey == null || accountKey.isEmpty) {
      return;
    }
    final device = parsed['announcedDevice'];
    final deviceMap = device is Map ? device : const <String, dynamic>{};
    final announcedDeviceId = (deviceMap['deviceId'] as String?)?.trim() ?? '';
    final announcedTransportPeerId =
        (deviceMap['transportPeerId'] as String?)?.trim() ?? '';
    final announcedSigningKey =
        (deviceMap['deviceSigningPublicKey'] as String?)?.trim() ?? '';
    if (announcedDeviceId.isEmpty ||
        announcedTransportPeerId.isEmpty ||
        announcedSigningKey.isEmpty) {
      return;
    }
    await _holdPendingSiblingDevice?.call(
      groupId: groupId,
      memberPeerId: senderId,
      announcedDeviceId: announcedDeviceId,
      announcedTransportPeerId: announcedTransportPeerId,
      announcedDeviceSigningPublicKey: announcedSigningKey,
      verifiedAccountSigningPublicKey: accountKey,
      announcedMlKemPublicKey: deviceMap['mlKemPublicKey'] as String?,
      announcedKeyPackageId: deviceMap['keyPackageId'] as String?,
    );
  }

  Future<bool> _isBoundSystemEventSenderDevice({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
    String? sysType,
    Map<String, dynamic>? parsed,
  }) async {
    if (senderId.isEmpty) {
      return false;
    }
    // B1b device_announce: the announcing sibling device is, by definition, not
    // yet on the roster, so there is no per-device binding to check here. Its
    // trust comes entirely from the ACCOUNT-key signed audit verified at the
    // dispatch site (_handleDeviceAnnounce refuses an announce without a verified
    // audit), so the sender-device binding is intentionally skipped.
    if (sysType == 'device_announce') {
      return true;
    }
    final member = await _groupRepo.getMember(groupId, senderId);
    if (member == null) {
      return false;
    }
    final resolvedTransportPeerId = transportPeerId?.trim().isNotEmpty == true
        ? transportPeerId!.trim()
        : senderId;
    if (member.devices.isEmpty) {
      if (_canBootstrapSnapshotBackedSenderDevice(
        member: member,
        sysType: sysType,
        parsed: parsed,
        senderDeviceId: senderDeviceId,
        transportPeerId: resolvedTransportPeerId,
      )) {
        return true;
      }
      if (_canBootstrapSnapshotBackedSignedAuditActorDevice(
        member: member,
        sysType: sysType,
        parsed: parsed,
      )) {
        return true;
      }
      return resolvedTransportPeerId == senderId;
    }
    final device = senderDeviceId?.trim().isNotEmpty == true
        ? member.findDeviceById(senderDeviceId)
        : member.findDeviceByTransportPeerId(resolvedTransportPeerId);
    if (device != null &&
        device.isActive &&
        device.transportPeerId == resolvedTransportPeerId) {
      return true;
    }
    return _canBootstrapSnapshotBackedSenderDevice(
          member: member,
          sysType: sysType,
          parsed: parsed,
          senderDeviceId: senderDeviceId,
          transportPeerId: resolvedTransportPeerId,
        ) ||
        _canBootstrapSnapshotBackedSignedAuditActorDevice(
          member: member,
          sysType: sysType,
          parsed: parsed,
        ) ||
        _canAcceptLegacySnapshotBackedAccountSender(
          member: member,
          senderId: senderId,
          sysType: sysType,
          parsed: parsed,
          senderDeviceId: senderDeviceId,
          transportPeerId: resolvedTransportPeerId,
        );
  }

  Future<bool> _shouldRelaxSnapshotBackedPreTransitionHash({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
    String? sysType,
    Map<String, dynamic>? parsed,
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
    return _canBootstrapSnapshotBackedSenderDevice(
          member: member,
          sysType: sysType,
          parsed: parsed,
          senderDeviceId: senderDeviceId,
          transportPeerId: resolvedTransportPeerId,
        ) ||
        _canBootstrapSnapshotBackedSignedAuditActorDevice(
          member: member,
          sysType: sysType,
          parsed: parsed,
        ) ||
        _canAcceptLegacySnapshotBackedAccountSender(
          member: member,
          senderId: senderId,
          sysType: sysType,
          parsed: parsed,
          senderDeviceId: senderDeviceId,
          transportPeerId: resolvedTransportPeerId,
        );
  }

  Future<_SignedTransitionAuditActorBinding>
  _expectedSignedAuditActorBindingForSystemEvent({
    required String groupId,
    required String senderId,
    String? senderDeviceId,
    String? transportPeerId,
    String? sysType,
    Map<String, dynamic>? parsed,
  }) async {
    final defaultBinding = _SignedTransitionAuditActorBinding(
      deviceId: _trimToNull(senderDeviceId),
      transportPeerId: _trimToNull(transportPeerId),
    );
    // Self-authored voluntary leave: a `member_removed` whose removed peer IS the
    // signer can only remove the signer and is authenticated by the signer's own
    // signing key (still verified in verifyGroupTransitionAudit). Over a relay the
    // leaver's OBSERVED transport peer legitimately differs from the self-peerId it
    // signed, so enforcing the device/transport binding here wrongly rejects the
    // leave with transport_mismatch — blocking roster exclusion on every remaining
    // member and, with it, the creator's forward-secrecy re-key. Relax the binding
    // for THIS case only; admin-authored removals (removed != signer) keep the
    // strict binding so a removed/foreign device cannot spoof a removal.
    if (sysType == 'member_removed' && senderId.isNotEmpty) {
      final removedPeerId =
          (parsed?['member'] as Map<String, dynamic>?)?['peerId'] as String?;
      if (removedPeerId != null &&
          removedPeerId.isNotEmpty &&
          removedPeerId == senderId) {
        return const _SignedTransitionAuditActorBinding();
      }
    }
    if (!_allowsSnapshotBackedSystemSender(sysType) || senderId.isEmpty) {
      return defaultBinding;
    }

    final member = await _groupRepo.getMember(groupId, senderId);
    if (member == null) {
      return defaultBinding;
    }
    final resolvedTransportPeerId = transportPeerId?.trim().isNotEmpty == true
        ? transportPeerId!.trim()
        : senderId;
    final knownDevice = senderDeviceId?.trim().isNotEmpty == true
        ? member.findDeviceById(senderDeviceId)
        : member.findDeviceByTransportPeerId(resolvedTransportPeerId);
    if (knownDevice != null &&
        knownDevice.isActive &&
        knownDevice.transportPeerId == resolvedTransportPeerId) {
      return defaultBinding;
    }

    final signedAuditActorBinding = _signedTransitionAuditActorBinding(parsed);
    if (_canBootstrapSnapshotBackedSignedAuditActorDevice(
      member: member,
      sysType: sysType,
      parsed: parsed,
      actorBinding: signedAuditActorBinding,
    )) {
      return signedAuditActorBinding;
    }

    if (_canBootstrapSnapshotBackedSenderDevice(
      member: member,
      sysType: sysType,
      parsed: parsed,
      senderDeviceId: senderDeviceId,
      transportPeerId: resolvedTransportPeerId,
    )) {
      return defaultBinding;
    }

    if (_canAcceptLegacySnapshotBackedAccountSender(
      member: member,
      senderId: senderId,
      sysType: sysType,
      parsed: parsed,
      senderDeviceId: senderDeviceId,
      transportPeerId: resolvedTransportPeerId,
      actorBinding: signedAuditActorBinding,
    )) {
      return const _SignedTransitionAuditActorBinding();
    }

    return defaultBinding;
  }

  bool _canBootstrapSnapshotBackedSignedAuditActorDevice({
    required GroupMember member,
    required String? sysType,
    required Map<String, dynamic>? parsed,
    _SignedTransitionAuditActorBinding? actorBinding,
  }) {
    final binding = actorBinding ?? _signedTransitionAuditActorBinding(parsed);
    if (!binding.hasBinding) {
      return false;
    }
    final actorDeviceId = binding.deviceId;
    final actorTransportPeerId = binding.transportPeerId;
    if (actorDeviceId == null ||
        actorDeviceId.isEmpty ||
        actorTransportPeerId == null ||
        actorTransportPeerId.isEmpty) {
      return false;
    }
    return _canBootstrapSnapshotBackedSenderDevice(
      member: member,
      sysType: sysType,
      parsed: parsed,
      senderDeviceId: actorDeviceId,
      transportPeerId: actorTransportPeerId,
    );
  }

  bool _canAcceptLegacySnapshotBackedAccountSender({
    required GroupMember member,
    required String senderId,
    required String? sysType,
    required Map<String, dynamic>? parsed,
    required String? senderDeviceId,
    required String? transportPeerId,
    _SignedTransitionAuditActorBinding? actorBinding,
  }) {
    if (!_allowsSnapshotBackedSystemSender(sysType)) {
      return false;
    }
    if (!_isLegacyAccountSystemTransport(
      senderId: senderId,
      senderDeviceId: senderDeviceId,
      transportPeerId: transportPeerId,
    )) {
      return false;
    }

    final binding = actorBinding ?? _signedTransitionAuditActorBinding(parsed);
    if (binding.hasBinding &&
        !_isLegacyAccountSystemTransport(
          senderId: senderId,
          senderDeviceId: binding.deviceId,
          transportPeerId: binding.transportPeerId,
        )) {
      return false;
    }

    final trustedMemberPublicKey = member.publicKey?.trim();
    if (trustedMemberPublicKey == null || trustedMemberPublicKey.isEmpty) {
      return false;
    }
    final groupConfig = parsed?['groupConfig'] as Map<String, dynamic>?;
    final snapshotMemberData = _findGroupConfigMember(
      groupConfig,
      member.peerId,
    );
    if (snapshotMemberData == null) {
      return false;
    }
    final snapshotPublicKey = (snapshotMemberData['publicKey'] as String?)
        ?.trim();
    return snapshotPublicKey == trustedMemberPublicKey;
  }

  bool _isLegacyAccountSystemTransport({
    required String senderId,
    required String? senderDeviceId,
    required String? transportPeerId,
  }) {
    final normalizedSenderId = senderId.trim();
    if (normalizedSenderId.isEmpty) {
      return false;
    }
    final normalizedDeviceId = _trimToNull(senderDeviceId);
    final normalizedTransportPeerId = _trimToNull(transportPeerId);
    final deviceIsLegacy =
        normalizedDeviceId == null || normalizedDeviceId == normalizedSenderId;
    final transportIsLegacy =
        normalizedTransportPeerId == null ||
        normalizedTransportPeerId == normalizedSenderId ||
        (normalizedDeviceId != null &&
            normalizedTransportPeerId == normalizedDeviceId &&
            normalizedDeviceId == normalizedSenderId);
    return deviceIsLegacy && transportIsLegacy;
  }

  bool _canBootstrapSnapshotBackedSenderDevice({
    required GroupMember member,
    required String? sysType,
    required Map<String, dynamic>? parsed,
    required String? senderDeviceId,
    required String transportPeerId,
  }) {
    if (!_allowsSnapshotBackedSystemSender(sysType)) {
      return false;
    }
    final normalizedDeviceId = senderDeviceId?.trim();
    if (normalizedDeviceId == null || normalizedDeviceId.isEmpty) {
      return false;
    }
    final normalizedTransportPeerId = transportPeerId.trim();
    if (normalizedTransportPeerId.isEmpty ||
        normalizedTransportPeerId == member.peerId) {
      return false;
    }
    final localDeviceById = member.findDeviceById(
      normalizedDeviceId,
      activeOnly: false,
    );
    final localDeviceByTransport = member.findDeviceByTransportPeerId(
      normalizedTransportPeerId,
      activeOnly: false,
    );
    if (localDeviceById != null) {
      if (!localDeviceById.isActive ||
          localDeviceById.transportPeerId != normalizedTransportPeerId) {
        return false;
      }
      return false;
    }
    if (localDeviceByTransport != null) {
      if (!localDeviceByTransport.isActive ||
          localDeviceByTransport.deviceId != normalizedDeviceId) {
        return false;
      }
      return false;
    }

    final trustedMemberPublicKey = member.publicKey?.trim();
    if (trustedMemberPublicKey == null || trustedMemberPublicKey.isEmpty) {
      return false;
    }

    final groupConfig = parsed?['groupConfig'] as Map<String, dynamic>?;
    final snapshotMemberData = _findGroupConfigMember(
      groupConfig,
      member.peerId,
    );
    if (snapshotMemberData == null) {
      return false;
    }
    final snapshotPublicKey = (snapshotMemberData['publicKey'] as String?)
        ?.trim();
    if (snapshotPublicKey != trustedMemberPublicKey) {
      return false;
    }

    final devices = GroupMemberDeviceIdentity.listFromJson(
      snapshotMemberData['devices'],
    );
    return devices.any(
      (device) =>
          device.isActive &&
          device.deviceId == normalizedDeviceId &&
          device.transportPeerId == normalizedTransportPeerId &&
          device.deviceSigningPublicKey == trustedMemberPublicKey,
    );
  }

  _SignedTransitionAuditActorBinding _signedTransitionAuditActorBinding(
    Map<String, dynamic>? parsed,
  ) {
    final audit = parsed?[signedGroupTransitionAuditField];
    if (audit is! Map) {
      return const _SignedTransitionAuditActorBinding();
    }
    final signedPayload = audit['signedPayload'];
    if (signedPayload is! String || signedPayload.isEmpty) {
      return const _SignedTransitionAuditActorBinding();
    }
    try {
      final decoded = jsonDecode(signedPayload);
      if (decoded is! Map) {
        return const _SignedTransitionAuditActorBinding();
      }
      final actor = decoded['actor'];
      if (actor is! Map) {
        return const _SignedTransitionAuditActorBinding();
      }
      return _SignedTransitionAuditActorBinding(
        deviceId: _trimToNull(actor['deviceId'] as String?),
        transportPeerId: _trimToNull(actor['transportPeerId'] as String?),
      );
    } catch (_) {
      return const _SignedTransitionAuditActorBinding();
    }
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _allowsSnapshotBackedSystemSender(String? sysType) {
    return sysType == 'group_metadata_updated' ||
        sysType == 'members_added' ||
        sysType == 'member_role_updated';
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
    String? sysType,
  }) async {
    final member = await _groupRepo.getMember(groupId, senderId);
    if (member == null) {
      return null;
    }
    // device_announce is ALWAYS account-key-signed (the announcing device may not
    // be rostered, and a re-announce of an already-rostered device must still
    // resolve the ACCOUNT key — not the per-device key — or its signed audit
    // would spuriously fail with payload_mismatch and never re-arm delivery).
    if (sysType == 'device_announce') {
      final accountKey = member.publicKey?.trim();
      return accountKey == null || accountKey.isEmpty ? null : accountKey;
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
      final priorMember = addedPeerId == null
          ? null
          : await _groupRepo.getMember(groupId, addedPeerId);
      final member = GroupMember.fromConfigMap(
        groupId: groupId,
        map: validMemberData,
        existing: addedPeerId == null
            ? null
            : _existingMemberForMembershipAddEvent(priorMember, eventAt),
        joinedAt: eventAt ?? DateTime.now().toUtc(),
      );
      await _groupRepo.saveMember(member);
      // G-A: a remote member whose usable ML-KEM key first lands here may be
      // owed a deferred key distribution from an earlier rotation — drain it
      // promptly. Gated so benign username-only refreshes never burn an attempt.
      if (addedPeerId != null &&
          addedPeerId.isNotEmpty &&
          groupMemberRegainedDeliverableKey(
            existing: priorMember,
            saved: member,
          )) {
        await triggerDeferredDistributionDrainForPeer(
          groupId: groupId,
          peerId: addedPeerId,
        );
      }
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
      final synced = await _syncGroupConfig(
        groupId,
        await _buildLocalGroupConfigSnapshot(groupId) ?? groupConfig,
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
      _emitGroupMessage(savedTimelineMessage);
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
        final priorMember = peerId == null
            ? null
            : await _groupRepo.getMember(groupId, peerId);
        final member = GroupMember.fromConfigMap(
          groupId: groupId,
          map: data,
          existing: peerId == null
              ? null
              : _existingMemberForMembershipAddEvent(priorMember, eventAt),
          joinedAt: eventAt ?? DateTime.now().toUtc(),
        );
        await _groupRepo.saveMember(member);
        // G-A: prompt deferred-distribution drain when this member's usable
        // ML-KEM key first lands (see _handleMemberAdded for rationale).
        if (peerId != null &&
            peerId.isNotEmpty &&
            groupMemberRegainedDeliverableKey(
              existing: priorMember,
              saved: member,
            )) {
          await triggerDeferredDistributionDrainForPeer(
            groupId: groupId,
            peerId: peerId,
          );
        }
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
      final synced = await _syncGroupConfig(
        groupId,
        await _buildLocalGroupConfigSnapshot(groupId) ?? groupConfig,
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
      _emitGroupMessage(savedTimelineMessage);
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
    // note-1 idempotency: the same join can arrive over two transports (live
    // GossipSub + offline-replay inbox) with DIFFERENT envelope timestamps,
    // which yield different `sys-member_joined:` ids. Render at most one join
    // card per (groupId, peerId). Exact-id re-delivery still flows through
    // _saveTimelineMessagePreservingReadState below (preserves readAt + re-emits
    // per existing replay semantics); only a SECOND join under a DIFFERENT id is
    // dropped here.
    if (await msgRepo.getMessage(timelineMessage.id) == null) {
      final existingJoinAt = await msgRepo
          .getLatestSystemEventTimestampForTarget(
            groupId,
            eventType: 'member_joined',
            targetId: joinedPeerId,
          );
      if (existingJoinAt != null) {
        await _inviteDeliveryAttemptRepo?.markJoined(
          groupId: groupId,
          peerId: joinedPeerId,
          username: memberData?['username'] as String?,
          joinedAt: eventAt,
        );
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_MESSAGE_LISTENER_MEMBER_JOINED_DUPLICATE_IGNORED',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'memberPeerId': joinedPeerId.length > 8
                ? joinedPeerId.substring(0, 8)
                : joinedPeerId,
          },
        );
        return;
      }
    }
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
    _emitGroupMessage(savedTimelineMessage);

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
    required DateTime? explicitRemovalAt,
    String? removalEventId,
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
        // Idempotency: B3 now RETAINS a quiet group on self-removal instead of
        // deleting it, so the previous "group is gone" dedup no longer fires.
        // Treat a repeat (or stale post-leave) member_removed as a duplicate
        // when the group is gone OR self is no longer an active member — this
        // keeps self-removal to a single leave/emit and stops a stale envelope
        // from resurrecting membership on the retained read-only group.
        final existingGroup = await _groupRepo.getGroup(groupId);
        final selfStillActiveMember = existingGroup == null
            ? null
            : await _groupRepo.getMember(groupId, selfPeerId);
        if (existingGroup == null || selfStillActiveMember == null) {
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

        // B3: always retain the group locally as a read-only shell with a
        // visible "Admin removed you" timeline message. Previously a quiet
        // group (no non-`sys-` content) was hard-deleted, so a removed
        // member's chat silently vanished (the only artifact was an empty
        // `status:'cutoff'` placeholder purged with the group).
        // `_retainSelfRemovedLocalHistory` keeps the group row (removeMember
        // (self) + removeAllKeys, NO deleteGroup), writes the visible removal
        // message, and purges post-removal content. The composer then
        // auto-gates read-only via `_canWriteForGroup` (self no longer an
        // active member + no send key) with no new flag or migration.
        final selfRemovalCompleted = await _retainSelfRemovedLocalHistory(
          groupId,
          selfPeerId: selfPeerId,
          senderId: senderId,
          senderUsername: senderUsername,
          removedUsername: removedUsername,
          // The envelope timestamp remains a compatibility fallback for
          // ordinary member removals, but it is not canonical B3 authority.
          // A self-removal must carry its own parseable `removedAt` value.
          eventAt: explicitRemovalAt,
          removalEventId: removalEventId,
          msgRepo: msgRepo,
          appendSystemEventLog: appendSystemEventLog,
        );
        if (selfRemovalCompleted) {
          // Soft "you were removed" signal — the group row is retained
          // read-only, not destroyed.
          _emitGroupRemoved(groupId);
        }
        return;
      }
    }

    final resolvedEventAt = eventAt ?? DateTime.now().toUtc();

    await appendSystemEventLog();

    // Not self — retain the removed member's verification material for
    // historical replay before deleting the active membership row.
    // Whether THIS delivery actually transitioned the member present -> removed
    // is the idempotency anchor for the post-departure re-key below: a duplicate
    // member_removed (peer already gone) must not trigger a second rotation.
    var removedPeerWasActiveMember = false;
    if (removedPeerId != null && removedPeerId.isNotEmpty) {
      final removedMember = await _groupRepo.getMember(groupId, removedPeerId);
      removedPeerWasActiveMember = removedMember != null;
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
    _emitGroupMessage(savedTimelineMessage);

    await _recordMembershipEventWatermark(groupId, resolvedEventAt);
    await _deleteContentMessagesAtOrAfterRemoval(
      groupId: groupId,
      removedPeerId: removedPeerId ?? '',
      removedAt: resolvedEventAt,
      msgRepo: msgRepo,
    );

    // Forward secrecy: a remaining group creator re-keys when a member it did
    // not itself remove departs (the voluntary leaver could not rotate). This
    // closes the gap left by best-effort leave rotation, mirroring
    // admin-removal's remover-driven rotation.
    await _maybeRotateGroupKeyAfterRemoteRemoval(
      groupId,
      removedPeerId: removedPeerId,
      removedPeerWasActiveMember: removedPeerWasActiveMember,
      removalAuthorPeerId: senderId,
      snapshotHasNoActiveMembers: snapshotHasNoActiveMembers,
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

  /// Re-keys a group after a remote member departure the local device did not
  /// author, preserving forward secrecy when the leaver could not rotate.
  ///
  /// All guards must hold; in particular only the group CREATOR auto-rotates.
  /// That keeps a single deterministic rotator (matching
  /// [rotateAndDistributeGroupKey]'s creator-only gate), so multiple remaining
  /// admins never race, and other members converge via the creator's
  /// distributed `key:update`.
  Future<void> _maybeRotateGroupKeyAfterRemoteRemoval(
    String groupId, {
    required String? removedPeerId,
    required bool removedPeerWasActiveMember,
    required String removalAuthorPeerId,
    required bool snapshotHasNoActiveMembers,
  }) async {
    final rotate = _rotateGroupKeyAfterRemoteRemoval;
    if (rotate == null) return;
    // Nothing to rotate toward once the group has emptied.
    if (snapshotHasNoActiveMembers) return;
    // Idempotency: only the delivery that actually removed an active member
    // drives the re-key. A duplicate member_removed (peer already gone) is a
    // no-op, so the epoch advances exactly once per departure.
    if (removedPeerId == null ||
        removedPeerId.isEmpty ||
        !removedPeerWasActiveMember) {
      return;
    }

    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null) return;
    // Do not rotate on a removal this device authored: the remover already
    // rotated locally (admin-removal path) and a voluntary leaver cannot.
    if (removalAuthorPeerId == selfPeerId) return;

    final group = await _groupRepo.getGroup(groupId);
    if (group == null || group.createdBy != selfPeerId) return;

    final remainingMembers = await _groupRepo.getMembers(groupId);
    final hasOtherActiveMember = remainingMembers.any(
      (member) => member.peerId != selfPeerId,
    );
    if (!hasOtherActiveMember) return;

    if (!await _allowsInboundAccountSideEffects(
      operation: 'group_creator_rekey_on_remote_removal',
      data: {'groupId': groupId},
    )) {
      return;
    }

    final flowGroupId = groupId.length > 8 ? groupId.substring(0, 8) : groupId;
    try {
      final rotated = await rotate(groupId);
      emitFlowEvent(
        layer: 'FL',
        event: rotated
            ? 'GROUP_CREATOR_REKEY_AFTER_REMOTE_REMOVAL'
            : 'GROUP_CREATOR_REKEY_AFTER_REMOTE_REMOVAL_SKIPPED',
        details: {
          'groupId': flowGroupId,
          'removedPeerId': removedPeerId.length > 10
              ? removedPeerId.substring(0, 10)
              : removedPeerId,
        },
      );
    } catch (e) {
      // A re-key failure must not abort member_removed handling.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_CREATOR_REKEY_AFTER_REMOTE_REMOVAL_FAILED',
        details: {'groupId': flowGroupId, 'error': e.toString()},
      );
    }
  }

  Future<bool> _retainSelfRemovedLocalHistory(
    String groupId, {
    required String selfPeerId,
    required String senderId,
    required String senderUsername,
    String? removedUsername,
    GroupMessage? retainedTimelineMessage,
    DateTime? eventAt,
    String? removalEventId,
    required GroupMessageRepository msgRepo,
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final resolvedEventAt = eventAt?.toUtc();
    final stableEventId = removalEventId?.trim();
    final shellRepository = _groupRepo is SelfRemovedGroupShellRepository
        ? _groupRepo as SelfRemovedGroupShellRepository
        : null;
    // B3 is a destructive authority transition. Missing signed time/id or a
    // repository without the atomic capability fails closed before native
    // leave and before any local/projection mutation.
    if (resolvedEventAt == null ||
        stableEventId == null ||
        stableEventId.isEmpty ||
        shellRepository == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_AUTHORITY_UNAVAILABLE',
        details: {'groupId': groupId},
      );
      return false;
    }

    final SelfRemovalAuthorityCommitOutcome commitOutcome;
    try {
      commitOutcome = await runGroupMembershipMutationLocked(
        groupId: groupId,
        action: () async {
          final currentSelf = await _groupRepo.getMember(groupId, selfPeerId);
          if (currentSelf == null) {
            return SelfRemovalAuthorityCommitOutcome.refusedStateChanged;
          }
          final outcome = await shellRepository.commitSelfRemovalAuthority(
            groupId: groupId,
            selfPeerId: selfPeerId,
            expectedSelfJoinedAt: currentSelf.joinedAt,
            removalAt: resolvedEventAt,
            removalEventId: stableEventId,
            leaveNative: () => callGroupLeave(_bridge!, groupId),
          );
          if (outcome == SelfRemovalAuthorityCommitOutcome.committed) {
            // Marker and retained key/draft addresses now own retry. Failure at
            // any strict terminal boundary must not undo the durable shell.
            try {
              final authority = await shellRepository
                  .loadSelfRemovedShellAuthority(
                    groupId: groupId,
                    selfPeerId: selfPeerId,
                  );
              await shellRepository.terminalizeSelfRemovedShell(
                expected: authority,
              );
            } catch (error) {
              emitFlowEvent(
                layer: 'FL',
                event:
                    'GROUP_MESSAGE_LISTENER_SELF_REMOVED_TERMINAL_RETRY_REQUIRED',
                details: {'groupId': groupId, 'error': error.toString()},
              );
            }
          }
          return outcome;
        },
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_COMMIT_FAILED',
        details: {'groupId': groupId, 'error': error.toString()},
      );
      rethrow;
    }
    if (commitOutcome != SelfRemovalAuthorityCommitOutcome.committed) {
      return false;
    }

    // Presentation/evidence happens only after durable authority. Its failure
    // cannot make the already-committed marker unsafe or require native leave
    // again; local shell deletion remains available.
    try {
      await appendSystemEventLog();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_EVENT_LOG_FAILED',
        details: {'groupId': groupId, 'error': error.toString()},
      );
    }
    final timelineMessage =
        retainedTimelineMessage ??
        buildMemberRemovedTimelineMessage(
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
    _emitGroupMessage(savedTimelineMessage);
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
    String? removalEventId,
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

    final getSelfPeerId = _getSelfPeerId;
    if (getSelfPeerId != null) {
      final selfPeerId = await getSelfPeerId();
      if (selfPeerId != null && selfPeerId == event.targetPeerId) {
        if (_bridge == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_SELF_REMOVED_AUTHORITY_UNAVAILABLE',
            details: {'groupId': groupId},
          );
          return;
        }
        final completed = await _retainSelfRemovedLocalHistory(
          groupId,
          selfPeerId: selfPeerId,
          senderId: senderId,
          senderUsername: senderUsername,
          removedUsername: event.targetUsername,
          retainedTimelineMessage: timelineMessage,
          eventAt: event.eventAt,
          removalEventId: removalEventId,
          msgRepo: msgRepo,
          appendSystemEventLog: appendSystemEventLog,
        );
        if (completed) {
          _emitGroupRemoved(groupId);
        }
        return;
      }
    }

    await appendSystemEventLog();
    final savedTimelineMessage = await _saveTimelineMessagePreservingReadState(
      timelineMessage,
      msgRepo,
    );
    _emitGroupMessage(savedTimelineMessage);

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
    _emitGroupMessage(savedTimelineMessage);
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
    _emitGroupMessage(savedTimelineMessage);

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
    String? eventId,
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
      _emitGroupMessage(savedTimelineMessage);
    }

    await _recordMembershipEventWatermark(groupId, eventAt, eventId: eventId);

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
    _emitGroupMessage(savedTimelineMessage);

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
    required Future<void> Function() appendSystemEventLog,
  }) async {
    final guarded = await runSelfRemovedGroupLifecycleLeaf<GroupMessage?>(
      groupRepo: _groupRepo,
      groupId: groupId,
      action: (group) async {
        // A terminal dissolve owns one phase from the fresh unmarked check
        // through native leave. B3-first skips every effect; dissolve-first
        // completes before B3 can mark the shell.
        if (group.isDissolved) return null;

        await appendSystemEventLog();
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
        final savedTimelineMessage =
            await _saveTimelineMessagePreservingReadState(
              timelineMessage,
              msgRepo,
            );
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
                'groupId': groupId.length > 8
                    ? groupId.substring(0, 8)
                    : groupId,
                'error': e.toString(),
              },
            );
          }
        }
        return savedTimelineMessage;
      },
    );
    final savedTimelineMessage = guarded.value;
    if (!guarded.didRun || savedTimelineMessage == null) return;

    // Stream callbacks stay outside the non-reentrant membership phase.
    _emitGroupMessage(savedTimelineMessage);

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
      final wireReaction = GroupReactionPayload.fromDecryptedJson(reactionJson);

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
        msgRepo: _msgRepo,
        // Buffer a live reaction whose target message has not arrived yet, so
        // it replays when the message lands (INV-R4) instead of being dropped.
        pendingReactionRepo: _pendingReactionRepo,
        groupId: groupId,
        senderId: senderId,
        senderDeviceId: senderDeviceId,
        transportPeerId: transportPeerId,
        reactionJson: reactionJson,
      );

      if (result == HandleGroupReactionResult.success && change != null) {
        final targetMessage = await _loadReactionDerivativeTarget(
          groupId: groupId,
          change: change,
        );
        if (targetMessage != null) {
          _emitReactionChange(change);
          // Notify on a fresh group-reaction ADD. A reaction buffered before
          // its target joins this same validated/claimed path when the target
          // later materializes; ordinary replay duplicates remain silent.
          await _maybeNotifyGroupReaction(
            groupId: groupId,
            reactorPeerId: senderId,
            change: change,
            targetMessage: targetMessage,
            eventId: wireReaction?.eventId,
          );
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<GroupMessage?> _loadReactionDerivativeTarget({
    required String groupId,
    required ReactionChange change,
  }) async {
    final targetMessage = await _msgRepo.getMessage(change.messageId);
    if (targetMessage == null || targetMessage.groupId != groupId) return null;
    if (targetMessage.privateMediaPolicy.isOrdinary) {
      return targetMessage;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_PRIVATE_MEDIA_REACTION_DERIVATIVES_SUPPRESSED',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'messageId': change.messageId.length > 8
            ? change.messageId.substring(0, 8)
            : change.messageId,
      },
    );
    return null;
  }

  /// 127-Bug-D: shows a local notification when a contact reacts to a message
  /// in this group. Mirrors the group MESSAGE notification gates — skip own
  /// reaction, group mute, viewing-suppression + tone debounce (via
  /// [maybeShowNotification]) — and fires ONLY on a fresh ADD upsert (the
  /// remove and stale-ignored branches return a non-upserted/empty change and
  /// stay silent). The OS call is fire-and-forget so reaction throughput is
  /// never blocked.
  Future<void> _maybeNotifyGroupReaction({
    required String groupId,
    required String reactorPeerId,
    required ReactionChange change,
    required GroupMessage targetMessage,
    String? eventId,
  }) async {
    if (change.type != ReactionChangeType.upserted) return;
    final reaction = change.reaction;
    if (reaction == null) return;

    final notificationService = _notificationService;
    final tracker = _groupConversationTracker;
    final lifecycle = _getAppLifecycleState;
    if (notificationService == null || tracker == null || lifecycle == null) {
      return;
    }

    // Notification eligibility is recipient-owned. Missing local identity must
    // fail closed, and a group reaction echo from any device of this account
    // must stay silent.
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null || selfPeerId.isEmpty) return;
    if (reactorPeerId == selfPeerId) return;

    // Reaction state still converges for every eligible member; only the
    // locally-authored target is allowed to produce attention. Check the
    // persisted target after applying the reaction so a bystander, a stale or
    // deleted target, or a cross-group id can never become a notification.
    if (targetMessage.id != reaction.messageId ||
        targetMessage.groupId != groupId ||
        targetMessage.senderPeerId != selfPeerId ||
        targetMessage.isIncoming) {
      return;
    }

    final group = await _groupRepo.getGroup(groupId);
    // Device-local mute suppresses local notifications (mirrors the message
    // path); a missing group means we can't route, so skip.
    if (group == null || group.isMuted) return;

    // Best-effort reactor display name from the group roster.
    var reactorName = '';
    try {
      final members = await _groupRepo.getMembers(groupId);
      for (final member in members) {
        if (member.peerId == reactorPeerId) {
          reactorName = (member.username ?? '').trim();
          break;
        }
      }
    } catch (_) {}

    final body = reactorName.isNotEmpty
        ? '$reactorName reacted ${reaction.emoji} to your message'
        : 'Someone reacted ${reaction.emoji} to your message';
    final notificationEventId = eventId?.trim().isNotEmpty == true
        ? eventId!.trim()
        : reaction.id;

    unawaited(
      maybeShowNotification(
        notificationService: notificationService,
        conversationTracker: tracker,
        getAppLifecycleState: lifecycle,
        contactPeerId: 'group:$groupId',
        routePayload: NotificationRouteTarget.group(
          groupId,
          messageId: reaction.messageId,
        ).toPayload(),
        senderUsername: group.name,
        messageText: body,
        messageId: notificationEventId,
        notificationEventIdentity: boundedReactionEventIdentity(
          notificationEventId,
        ),
        notificationEventType: 'message_reaction',
        toneTracker: _notificationToneTracker,
        durableNotificationCoordinatorResolver:
            _resolveDurableNotificationCoordinator,
        consumeRecentRemoteNotificationAnnouncement:
            ({required payload, String? messageId}) =>
                _remoteNotificationGate.consumeIfRecentAnnouncement(
                  payload: payload,
                  messageId: messageId,
                ),
      ),
    );
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
    String? eventId,
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

    // Deterministic equal-instant tie-break: an incoming event whose audit
    // source id strictly out-ranks the stored id is fresh — the higher id wins
    // on every device, so concurrent same-instant cross-sender events converge.
    // Degrades to strict-stale when either id is absent (mixed-version safe).
    if (eventAt.isAtSameMomentAs(watermark) && eventId != null) {
      final storedEventId = await _storedMembershipEventIdAt(
        groupId,
        watermark,
      );
      if (storedEventId != null && eventId.compareTo(storedEventId) > 0) {
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

  /// The stored membership-event tie-breaker id, valid only when the persisted
  /// `lastMembershipEventAt` is exactly [watermark] (i.e. the watermark came
  /// from the stored field, not a synthesized createdAt/joinedAt fallback).
  Future<String?> _storedMembershipEventIdAt(
    String groupId,
    DateTime watermark,
  ) async {
    final group = await _groupRepo.getGroup(groupId);
    final storedAt = group?.lastMembershipEventAt?.toUtc();
    if (storedAt != null && storedAt.isAtSameMomentAs(watermark)) {
      return group!.lastMembershipEventId;
    }
    return null;
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
    required GroupMessageRepository msgRepo,
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
      if (existingMember != null && joinedAt != null) {
        if (joinedAt.isAfter(eventAt)) {
          final deleted = await _deleteContentMessagesAtOrAfterRemoval(
            groupId: groupId,
            removedPeerId: removedPeerId,
            removedAt: eventAt,
            beforeRejoinAt: joinedAt,
            msgRepo: msgRepo,
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MESSAGE_LISTENER_STALE_MEMBER_REMOVED_REPAIRED',
            details: {
              'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
              'memberPeerId': removedPeerId.length > 8
                  ? removedPeerId.substring(0, 8)
                  : removedPeerId,
              'eventAt': eventAt.toIso8601String(),
              'rejoinedAt': joinedAt.toIso8601String(),
              'deletedCount': deleted,
            },
          );
          return true;
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
    Map<String, dynamic>? parsed,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final group = await _groupRepo.getGroup(groupId);
    final watermark = group?.lastMetadataEventAt?.toUtc();
    if (watermark == null || eventAt.isAfter(watermark)) {
      return false;
    }

    if (group != null &&
        eventAt.isAtSameMomentAs(watermark) &&
        _metadataReplayRepairsVisibleFields(group, parsed)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_METADATA_EVENT_REPAIRING_EQUAL_VERSION',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'type': sysType ?? 'null',
          'eventAt': eventAt.toIso8601String(),
          'watermark': watermark.toIso8601String(),
        },
      );
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

  bool _metadataReplayRepairsVisibleFields(
    GroupModel group,
    Map<String, dynamic>? parsed,
  ) {
    final groupConfig = parsed?['groupConfig'];
    if (groupConfig is! Map) {
      return false;
    }
    final normalizedGroupConfig = normalizeGroupConfigPayload(
      groupId: group.id,
      groupConfig: Map<String, dynamic>.from(groupConfig),
    );
    final snapshotName = normalizedGroupConfig['name'] as String?;
    final snapshotDescription = normalizedGroupConfig.containsKey('description')
        ? normalizedGroupConfig['description'] as String?
        : group.description;
    return (snapshotName != null && snapshotName != group.name) ||
        snapshotDescription != group.description;
  }

  Future<bool> _shouldRetryAcceptedSignedMetadataAvatarRecovery(
    String groupId, {
    required DateTime? eventAt,
    required Map<String, dynamic> parsed,
  }) async {
    if (eventAt == null) {
      return false;
    }

    final groupConfig = parsed['groupConfig'] as Map<String, dynamic>?;
    final payloadAvatarBlobId = groupConfig?['avatarBlobId'] as String?;
    final payloadAvatarMime = groupConfig?['avatarMime'] as String?;
    if (payloadAvatarBlobId == null || payloadAvatarMime == null) {
      return false;
    }

    final group = await _groupRepo.getGroup(groupId);
    final watermark = group?.lastMetadataEventAt?.toUtc();
    if (group == null ||
        watermark == null ||
        !eventAt.toUtc().isAtSameMomentAs(watermark)) {
      return false;
    }

    return group.avatarBlobId == payloadAvatarBlobId &&
        group.avatarMime == payloadAvatarMime &&
        (group.avatarPath == null || group.avatarPath!.isEmpty);
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

      final savedMember = GroupMember.fromConfigMap(
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
      );
      await _groupRepo.saveMember(savedMember);
      // G-A: an authoritative config snapshot is the canonical receive site
      // where a member's ML-KEM key (or a new keyed device) first lands —
      // drain any deferred distribution owed to it. The delta guard makes the
      // common no-key-change member refresh a no-op (and avoids double-firing
      // with the member_added/members_added save that precedes this snapshot).
      if (groupMemberRegainedDeliverableKey(
        existing: existingMember,
        saved: savedMember,
      )) {
        await triggerDeferredDistributionDrainForPeer(
          groupId: groupId,
          peerId: peerId,
        );
      }
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
    final currentMetadataWatermark = group.lastMetadataEventAt?.toUtc();
    final appliesMetadataFields =
        resolvedMetadataUpdatedAt == null ||
        currentMetadataWatermark == null ||
        !resolvedMetadataUpdatedAt.isBefore(currentMetadataWatermark);
    if (!appliesMetadataFields) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MESSAGE_LISTENER_STALE_CONFIG_METADATA_FIELDS_IGNORED',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'metadataUpdatedAt': resolvedMetadataUpdatedAt.toIso8601String(),
          'watermark': currentMetadataWatermark.toIso8601String(),
        },
      );
    }
    final containsAvatarBlobId = normalizedGroupConfig.containsKey(
      'avatarBlobId',
    );
    final containsAvatarMime = normalizedGroupConfig.containsKey('avatarMime');
    final snapshotAvatarBlobId = containsAvatarBlobId
        ? normalizedGroupConfig['avatarBlobId'] as String?
        : group.avatarBlobId;
    final snapshotAvatarMime = containsAvatarMime
        ? normalizedGroupConfig['avatarMime'] as String?
        : group.avatarMime;
    final resolvedAvatarBlobId = appliesMetadataFields
        ? snapshotAvatarBlobId
        : group.avatarBlobId;
    final resolvedAvatarMime = appliesMetadataFields
        ? snapshotAvatarMime
        : group.avatarMime;
    final avatarChanged =
        resolvedAvatarBlobId != group.avatarBlobId ||
        resolvedAvatarMime != group.avatarMime;
    final shouldClearAvatar =
        appliesMetadataFields &&
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
        name: appliesMetadataFields
            ? normalizedGroupConfig['name'] as String? ?? group.name
            : group.name,
        type: appliesMetadataFields ? resolvedType : group.type,
        description: appliesMetadataFields
            ? (normalizedGroupConfig.containsKey('description')
                  ? normalizedGroupConfig['description'] as String?
                  : group.description)
            : group.description,
        avatarBlobId: resolvedAvatarBlobId,
        avatarMime: resolvedAvatarMime,
        avatarPath: nextAvatarPath,
        createdAt: appliesMetadataFields ? resolvedCreatedAt : group.createdAt,
        createdBy: appliesMetadataFields
            ? normalizedGroupConfig['createdBy'] as String? ?? group.createdBy
            : group.createdBy,
        myRole: selfSnapshotRole == null
            ? group.myRole
            : (selfSnapshotRole == MemberRole.admin
                  ? GroupRole.admin
                  : GroupRole.member),
        lastMetadataEventAt: appliesMetadataFields
            ? resolvedMetadataUpdatedAt ?? group.lastMetadataEventAt
            : group.lastMetadataEventAt,
      ),
    );

    final bridge = _bridge;
    if (appliesMetadataFields &&
        bridge != null &&
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
    DateTime? eventAt, {
    String? eventId,
  }) async {
    await recordGroupMembershipEventWatermark(
      groupRepo: _groupRepo,
      groupId: groupId,
      eventAt: eventAt,
      eventId: eventId,
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
  Future<void> stop() {
    final existingStop = _stopFuture;
    if (existingStop != null) return existingStop;

    _isStopping = true;
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_MESSAGE_LISTENER_STOP',
      details: {},
    );

    final messageSubscription = _subscription;
    _subscription = null;
    final reactionSubscription = _reactionSubscription;
    _reactionSubscription = null;
    final diagnosticSubscription = _diagnosticSubscription;
    _diagnosticSubscription = null;

    late final Future<void> stopFuture;
    stopFuture =
        Future.wait<void>([
          if (messageSubscription != null) messageSubscription.cancel(),
          if (reactionSubscription != null) reactionSubscription.cancel(),
          if (diagnosticSubscription != null) diagnosticSubscription.cancel(),
        ]).then((_) => _awaitInFlightHandlers()).whenComplete(() {
          if (identical(_stopFuture, stopFuture)) {
            _stopFuture = null;
          }
        });
    _stopFuture = stopFuture;
    return stopFuture;
  }

  /// Disposes of the listener and closes streams.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isStopping = true;
    unawaited(stop());
    if (!_messageController.isClosed) {
      unawaited(_messageController.close());
    }
    if (!_removedController.isClosed) {
      unawaited(_removedController.close());
    }
    if (!_reactionChangeController.isClosed) {
      unawaited(_reactionChangeController.close());
    }
  }
}
