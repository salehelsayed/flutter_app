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
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/application/group_role_update_authorization.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_reaction_use_case.dart';
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

part 'group_message_listener_system_transition_processor.dart';
part 'group_message_listener_membership_dependent_message_buffer.dart';
part 'group_message_listener_reaction_ingress_processor.dart';
part 'group_message_listener_media_receive_coordinator.dart';

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

/// Retires durable voluntary-exit work after an authenticated remote dissolve
/// has been committed locally. The concrete runtime callback deletes the
/// group's exit intent and that intent's exact leave-notice row atomically.
typedef TerminalizeGroupExitWorkAfterRemoteDissolve =
    Future<void> Function(String groupId);

/// Acquires one OS critical-task lease for an eligible background group-media
/// receive batch. A null result means the OS refused the lease.
typedef BeginGroupMediaReceiveCriticalTask = Future<String?> Function();

/// Releases the exact critical-task lease granted to a background group-media
/// receive batch.
typedef EndGroupMediaReceiveCriticalTask = Future<void> Function(String taskId);

/// Opaque ownership of one participant in the listener's shared group-media
/// receive critical task.
///
/// [release] is idempotent: every caller observes the same terminal future and
/// the underlying participant is released at most once.
final class GroupMediaReceiveCriticalTaskReservation {
  GroupMediaReceiveCriticalTaskReservation._(this._releaseParticipant);

  final Future<void> Function() _releaseParticipant;
  Future<void>? _releaseFuture;

  Future<void> release() {
    return _releaseFuture ??= _releaseOnce();
  }

  Future<void> _releaseOnce() async {
    await _releaseParticipant();
  }
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
/// When the local user is removed from a group, the listener retains the
/// read-only local history shell through [_retainSelfRemovedLocalHistory] and
/// emits the groupId on [groupRemovedStream]. Voluntary exit cleanup remains
/// owned by the durable group-exit coordinator and runner.
class GroupMessageListener {
  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final Bridge? _bridge;
  final Future<String?> Function()? _getSelfPeerId;
  final MediaAttachmentRepository? _mediaAttachmentRepo;
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
  final AppendGroupEventLogEntry? _appendGroupEventLogEntry;
  final Stream<Map<String, dynamic>>? _groupDiagnosticEvents;
  final GroupPendingKeyRepairRepository? _pendingKeyRepairRepo;
  final GroupPendingMembershipMessageRepository? _pendingMembershipMessageRepo;
  final GroupPendingReactionRepository? _pendingReactionRepo;
  final RequestGroupKeyRepair _requestGroupKeyRepair;
  final RecoverGroupDispatcherOverflow? _recoverFromDispatcherOverflow;
  final AccountMigrationNetworkGate _accountMigrationNetworkGate;
  final GroupPrivateMediaAvailability _privateMediaAvailability;

  late final _GroupMessageSystemTransitionProcessor _systemTransitionProcessor;
  late final _GroupMembershipDependentMessageBuffer
  _membershipDependentMessageBuffer;
  late final _GroupReactionIngressProcessor _reactionIngressProcessor;
  late final _GroupMediaReceiveCoordinator _mediaReceiveCoordinator;

  StreamSubscription<void>? _subscription;
  StreamSubscription<void>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _diagnosticSubscription;
  final _messageController = StreamController<GroupMessage>.broadcast();
  final _removedController = StreamController<String>.broadcast();
  final _reactionChangeController =
      StreamController<ReactionChange>.broadcast();
  final Map<String, Future<void>> _userMessageWorkQueue = {};
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
    TerminalizeGroupExitWorkAfterRemoteDissolve?
    terminalizeGroupExitWorkAfterRemoteDissolve,
    AccountMigrationNetworkGate accountMigrationNetworkGate =
        allowAccountMigrationNetworkSideEffects,
    HoldPendingSiblingDeviceFn? holdPendingSiblingDevice,
    GroupPrivateMediaAvailability privateMediaAvailability =
        productionGroupPrivateMediaAvailability,
    GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator,
    BeginGroupMediaReceiveCriticalTask? beginGroupMediaReceiveCriticalTask,
    EndGroupMediaReceiveCriticalTask? endGroupMediaReceiveCriticalTask,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _bridge = bridge,
       _getSelfPeerId = getSelfPeerId,
       _mediaAttachmentRepo = mediaAttachmentRepo,
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
       _appendGroupEventLogEntry = appendGroupEventLogEntry,
       _groupDiagnosticEvents = groupDiagnosticEvents,
       _pendingKeyRepairRepo = pendingKeyRepairRepo,
       _pendingMembershipMessageRepo = pendingMembershipMessageRepo,
       _pendingReactionRepo = pendingReactionRepo,
       _requestGroupKeyRepair =
           requestGroupKeyRepair ?? emitGroupKeyRepairRequest,
       _recoverFromDispatcherOverflow = recoverFromDispatcherOverflow,
       _accountMigrationNetworkGate = accountMigrationNetworkGate,
       _privateMediaAvailability = privateMediaAvailability {
    _membershipDependentMessageBuffer = _GroupMembershipDependentMessageBuffer(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      pendingMembershipMessageRepo: pendingMembershipMessageRepo,
      isStoppingOrDisposed: () => _isStopping || _isDisposed,
      replayMessage: (data, {required msgRepo, required membershipPhaseHeld}) =>
          _handleMessage(
            data,
            msgRepoOverride: msgRepo,
            allowMembershipBuffer: false,
            rethrowOnError: true,
            deliverySource: 'membershipBuffer',
            membershipPhaseHeld: membershipPhaseHeld,
            deferKeyRepairRequest: membershipPhaseHeld,
          ),
      requestKeyRepair: _requestReceivedMessageKeyRepairIfLocalEpochIsBehind,
    );
    _reactionIngressProcessor = _GroupReactionIngressProcessor(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      reactionRepo: reactionRepo,
      pendingReactionRepo: pendingReactionRepo,
      notificationService: notificationService,
      groupConversationTracker: groupConversationTracker,
      getAppLifecycleState: getAppLifecycleState,
      notificationToneTracker: notificationToneTracker,
      remoteNotificationGate:
          remoteNotificationGate ?? recentRemoteNotificationGate,
      isStoppingOrDisposed: () => _isStopping || _isDisposed,
      resolveSelfPeerId: _resolveSelfPeerId,
      resolveDurableNotificationCoordinator:
          _resolveDurableNotificationCoordinator,
      emitReactionChange: _emitReactionChange,
    );
    _mediaReceiveCoordinator = _GroupMediaReceiveCoordinator(
      bridge: bridge,
      msgRepo: msgRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      getAppLifecycleState: getAppLifecycleState,
      groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
      beginGroupMediaReceiveCriticalTask: beginGroupMediaReceiveCriticalTask,
      endGroupMediaReceiveCriticalTask: endGroupMediaReceiveCriticalTask,
      emitGroupMessage: _emitGroupMessage,
      trackInFlight: _trackInFlight,
      isStoppingOrDisposed: () => _isStopping || _isDisposed,
    );
    _systemTransitionProcessor = _GroupMessageSystemTransitionProcessor(
      groupRepo: groupRepo,
      bridge: bridge,
      isStoppingOrDisposed: () => _isStopping || _isDisposed,
      getSelfPeerId: _getSelfPeerId,
      resolveSelfPeerId: _resolveSelfPeerId,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
      downloadGroupAvatarFn: downloadGroupAvatarFn ?? downloadGroupAvatar,
      appendGroupEventLogEntry: appendGroupEventLogEntry,
      holdPendingSiblingDevice: holdPendingSiblingDevice,
      rotateGroupKeyAfterRemoteRemoval: rotateGroupKeyAfterRemoteRemoval,
      terminalizeGroupExitWorkAfterRemoteDissolve:
          terminalizeGroupExitWorkAfterRemoteDissolve,
      allowsInboundAccountSideEffects: _allowsInboundAccountSideEffects,
      emitGroupMessage: _emitGroupMessage,
      emitGroupRemoved: _emitGroupRemoved,
      flushMembershipDependentMessages:
          _membershipDependentMessageBuffer._flushMembershipDependentMessages,
      deleteContentMessagesAtOrAfterRemoval: _membershipDependentMessageBuffer
          ._deleteContentMessagesAtOrAfterRemoval,
    );
  }

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

  /// Plan 325: the durable buffer for a reaction whose target message has not
  /// arrived yet. Exposed so a drain lane that already receives this listener
  /// can forward the SAME repository instance rather than threading it
  /// separately through the widget tree — the accept-invite lane
  /// (`accept_pending_group_invite_use_case.dart`) is the caller this exists
  /// for. Without it that lane drops such reactions permanently, because the
  /// drain consumes the relay entry and the cursor commits regardless.
  GroupPendingReactionRepository? get pendingReactionRepository =>
      _pendingReactionRepo;

  bool get canHandleReplayReactions => _reactionRepo != null;

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

  /// Replays one verified offline reaction through the same persistence,
  /// stream, notification-policy, and durable notification-claim path as live
  /// reaction ingress.
  Future<void> handleReplayReaction(
    Map<String, dynamic> data, {
    bool rethrowOnError = false,
  }) async {
    if (!await _allowsInboundAccountSideEffects(
      operation: 'group_replay_reaction',
      data: data,
    )) {
      if (rethrowOnError) {
        throw StateError('group replay reaction side effects are blocked');
      }
      return;
    }
    return _reactionIngressProcessor._handleReaction(
      data,
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
      unawaited(
        _membershipDependentMessageBuffer
            ._flushStartupDurableMembershipDependentMessages(),
      );
    }

    if (_pendingReactionRepo != null) {
      unawaited(
        _reactionIngressProcessor._flushStartupDurablePendingReactions(),
      );
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
      await _reactionIngressProcessor._handleReaction(data);
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
            await _systemTransitionProcessor._shouldBufferPreJoinSystemMessage(
              groupId: groupId,
              senderId: senderId,
              messageId: wireMessageId,
              msgRepo: msgRepo,
              data: data,
              text: text,
            )) {
          await _membershipDependentMessageBuffer
              ._bufferMembershipDependentMessage(
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
        await _systemTransitionProcessor._handleSystemMessage(
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
          await _membershipDependentMessageBuffer
              ._shouldBufferMembershipDependentMessage(
                groupId: groupId,
                senderId: senderId,
                messageId: wireMessageId,
                msgRepo: msgRepo,
                data: data,
              )) {
        await _membershipDependentMessageBuffer
            ._bufferMembershipDependentMessage(
              groupId: groupId,
              senderId: senderId,
              messageId: wireMessageId,
              data: data,
            );
        return;
      }

      final outcome = await handleIncomingGroupMessageDetailed(
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

      if (outcome is IncomingGroupMessageDuplicateEnriched) {
        final canonicalMessage = outcome.canonicalMessage;
        if (_privateMediaAvailability.allowsMediaDerivatives(
              canonicalMessage.privateMediaPolicy,
            ) &&
            _mediaReceiveCoordinator._hasAutomaticMediaRecovery) {
          // A stable duplicate may add media that was absent from the original
          // delivery. Recover only the IDs this invocation actually committed;
          // do not replay delivery, notification, unread, reaction, or key-
          // repair side effects for the canonical message.
          _trackInFlight(
            _mediaReceiveCoordinator._recoverAutomaticMedia(
              canonicalMessage,
              attachmentIds: outcome.persistedAttachmentIds,
              emitAfterDownload: false,
            ),
          );
        }
        return;
      }

      if (outcome is IncomingGroupMessageDelivered) {
        final result = outcome.message;
        _emitGroupMessage(result);
        // The target message just landed — replay any reactions that arrived
        // before it (INV-R4). This single site serves BOTH live and offline
        // drain, because the drain replays messages through the same
        // _handleMessage → _emitGroupMessage path.
        await _reactionIngressProcessor._flushPendingReactionsForMessage(
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
          final isArchived = group?.isArchived ?? false;
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
          if (!isMuted && !isArchived) {
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
        if (_mediaReceiveCoordinator._hasAutomaticMediaRecovery &&
            persistedAttachments.isNotEmpty) {
          _trackInFlight(
            _mediaReceiveCoordinator._recoverAutomaticMedia(
              result,
              attachmentIds: persistedAttachments.map(
                (attachment) => attachment.id,
              ),
            ),
          );
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
  }) {
    return _membershipDependentMessageBuffer
        .flushPendingMembershipDependentMessagesForGroup(
          groupId,
          msgRepoOverride: msgRepoOverride,
        );
  }

  Future<GroupMediaReceiveCriticalTaskReservation>
  reserveGroupMediaReceiveCriticalTaskForForegroundHandoff() {
    return _mediaReceiveCoordinator
        .reserveGroupMediaReceiveCriticalTaskForForegroundHandoff();
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
