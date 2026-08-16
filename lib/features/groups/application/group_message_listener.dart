import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/group_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/group_notification_reconciliation_signal.dart';
import 'package:flutter_app/core/notifications/ios_mailbox_alert_silent_replay_context.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
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
import 'package:flutter_app/features/groups/application/group_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_notification_display_retry_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
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
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_membership_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/application/manage_pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
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

typedef LoadLatestUnreadGroupNotificationMessage =
    Future<GroupMessage?> Function(String groupId);
typedef IsActiveGroupNotificationReaction =
    Future<GroupNotificationCanonicalContentDecision> Function({
      required String groupId,
      required String selfPeerId,
      required String eventIdentity,
    });
typedef LoadLatestActiveGroupNotificationReaction =
    Future<GroupNotificationCanonicalReaction?> Function({
      required String groupId,
      required String selfPeerId,
    });
typedef GroupNotificationEventAcknowledgedResolver =
    Future<bool> Function({
      required String groupId,
      required ConversationNotificationContentKind contentKind,
      required String eventIdentity,
    });
typedef ResolveCurrentGroupNotificationOpaqueBinding =
    Future<String?> Function();

/// Identifier-only canonical reaction attention used to rebuild the shared
/// group card. Target text and raw emoji are intentionally not represented.
final class GroupNotificationCanonicalReaction {
  const GroupNotificationCanonicalReaction({
    required this.messageId,
    required this.actorPeerId,
    required this.eventIdentity,
    required this.timestamp,
  });

  final String messageId;
  final String actorPeerId;
  final String eventIdentity;
  final DateTime timestamp;
}

final class _GroupDurableNotificationAuthority {
  const _GroupDurableNotificationAuthority({
    required this.currentOpaqueBinding,
    required this.eventCorrelation,
    required this.conversationIdentity,
    required this.ledgerProducerKind,
    required this.outcomeProducerKind,
    required this.physicalPeerId,
    required this.eventKey,
    required this.registry,
  });

  final String currentOpaqueBinding;
  final String eventCorrelation;
  final AppVisibilityConversationIdentity conversationIdentity;
  final LocalNotificationProducerKind ledgerProducerKind;
  final NotificationCompletedOutcomeProducerKind outcomeProducerKind;
  final String? physicalPeerId;
  final String? eventKey;
  final DurableLocalNotificationEffectRegistry registry;
}

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
  final AppVisibilitySuppressionReader? _appVisibility;
  // 118 Phase 4: shared per-conversation tone debounce (the same tracker the
  // direct listener uses; group + direct keys are disjoint).
  final NotificationToneTracker? _notificationToneTracker;
  final GroupNotificationPresentationCoordinator?
  _notificationPresentationCoordinator;
  late final GroupNotificationReadProjector? _notificationReadProjector;
  final Future<DurableNotificationToneLease> Function()
  _durableNotificationCoordinatorResolver;
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
  final PendingConversationNotificationOverlayStore?
  _pendingConversationNotificationOverlay;
  final GroupNotificationDisplayOutboxRepository? _notificationDisplayOutbox;
  final GroupNotificationReconciliationOutboxRepository?
  _notificationReconciliationOutbox;
  final LoadLatestUnreadGroupNotificationMessage?
  _loadLatestUnreadNotificationMessage;
  final IsActiveGroupNotificationReaction? _isActiveGroupNotificationReaction;
  final LoadLatestActiveGroupNotificationReaction?
  _loadLatestActiveNotificationReaction;
  final GroupNotificationEventAcknowledgedResolver?
  _isGroupNotificationEventAcknowledged;
  final Future<String?> Function()? _resolveCompletedOutcomePhysicalPeerId;
  final ResolveCurrentGroupNotificationOpaqueBinding?
  _resolveCurrentOpaqueBinding;
  final DurableLocalNotificationEffectRegistry?
  _durableLocalNotificationEffectRegistry;
  final LocalNotificationPresentationOwner _notificationPresentationOwner;
  final bool _completedOutcomeProducerEnabled;

  /// Live platform consumer read consulted at each producer event. Shared
  /// with the outcome drainer and paired capability registration so all three
  /// follow one binding/role epoch; a failed read never mints an outcome.
  final Future<bool> Function()? _readCompletedOutcomeProducerReady;
  late final GroupNotificationCanonicalReconciler?
  _notificationCanonicalReconciler;
  late final GroupNotificationDisplayRetryCoordinator<
    GroupNotificationDisplayOutboxEntry
  >?
  _notificationDisplayRetryCoordinator;
  late final GroupNotificationDisplayRetryCoordinator<
    GroupNotificationReconciliationOutboxEntry
  >?
  _notificationReconciliationRetryCoordinator;
  Timer? _notificationDisplayRetryTimer;
  DateTime? _notificationDisplayRetryDueAt;
  int _canonicalNotificationRecoveryDepth = 0;
  bool _canonicalNotificationRecoveryFailed = false;
  bool _canonicalNotificationStateIncomplete = false;
  bool _startupCanonicalNotificationRecoveryPending = false;

  late final _GroupMessageSystemTransitionProcessor _systemTransitionProcessor;
  late final _GroupMembershipDependentMessageBuffer
  _membershipDependentMessageBuffer;
  late final _GroupReactionIngressProcessor _reactionIngressProcessor;
  late final _GroupMediaReceiveCoordinator _mediaReceiveCoordinator;

  StreamSubscription<void>? _subscription;
  StreamSubscription<void>? _reactionSubscription;
  StreamSubscription<Map<String, dynamic>>? _diagnosticSubscription;
  StreamSubscription<String>? _notificationReconciliationSignalSubscription;
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
    AppVisibilitySuppressionReader? appVisibility,
    // Retained as a source-compatible N11 read/rewarm input for older test
    // compositions. Notification presentation never consults it.
    ActiveConversationTracker? groupConversationTracker,
    NotificationToneTracker? notificationToneTracker,
    GroupNotificationPresentationCoordinator?
    notificationPresentationCoordinator,
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
    PendingConversationNotificationOverlayStore?
    pendingConversationNotificationOverlay,
    GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator,
    GroupNotificationDisplayOutboxRepository? notificationDisplayOutbox,
    GroupNotificationReconciliationOutboxRepository?
    notificationReconciliationOutbox,
    LoadLatestUnreadGroupNotificationMessage?
    loadLatestUnreadNotificationMessage,
    IsActiveGroupNotificationReaction? isActiveGroupNotificationReaction,
    LoadLatestActiveGroupNotificationReaction?
    loadLatestActiveNotificationReaction,
    GroupNotificationEventAcknowledgedResolver?
    isGroupNotificationEventAcknowledged,
    Future<String?> Function()? resolveCompletedOutcomePhysicalPeerId,
    ResolveCurrentGroupNotificationOpaqueBinding? resolveCurrentOpaqueBinding,
    DurableLocalNotificationEffectRegistry?
    durableLocalNotificationEffectRegistry,
    LocalNotificationPresentationOwner notificationPresentationOwner =
        LocalNotificationPresentationOwner.mainApp,
    bool completedOutcomeProducerEnabled = false,
    Future<bool> Function()? readCompletedOutcomeProducerReady,
    BeginGroupMediaReceiveCriticalTask? beginGroupMediaReceiveCriticalTask,
    EndGroupMediaReceiveCriticalTask? endGroupMediaReceiveCriticalTask,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _bridge = bridge,
       _getSelfPeerId = getSelfPeerId,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _notificationService = notificationService,
       _appVisibility = appVisibility,
       _notificationToneTracker = notificationToneTracker,
       _notificationPresentationCoordinator =
           notificationPresentationCoordinator ??
           (notificationDisplayOutbox == null
               ? null
               : GroupNotificationPresentationCoordinator()),
       _durableNotificationCoordinatorResolver =
           durableNotificationCoordinatorResolver ??
           DurableNotificationToneLease.openMobileDefault,
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
       _privateMediaAvailability = privateMediaAvailability,
       _pendingConversationNotificationOverlay =
           pendingConversationNotificationOverlay,
       _notificationDisplayOutbox = notificationDisplayOutbox,
       _notificationReconciliationOutbox = notificationReconciliationOutbox,
       _loadLatestUnreadNotificationMessage =
           loadLatestUnreadNotificationMessage,
       _isActiveGroupNotificationReaction = isActiveGroupNotificationReaction,
       _loadLatestActiveNotificationReaction =
           loadLatestActiveNotificationReaction,
       _isGroupNotificationEventAcknowledged =
           isGroupNotificationEventAcknowledged,
       _resolveCompletedOutcomePhysicalPeerId =
           resolveCompletedOutcomePhysicalPeerId,
       _resolveCurrentOpaqueBinding = resolveCurrentOpaqueBinding,
       _durableLocalNotificationEffectRegistry =
           durableLocalNotificationEffectRegistry,
       _notificationPresentationOwner = notificationPresentationOwner,
       _completedOutcomeProducerEnabled = completedOutcomeProducerEnabled,
       _readCompletedOutcomeProducerReady = readCompletedOutcomeProducerReady {
    final readSource = msgRepo is GroupConversationReadEventSource
        ? msgRepo as GroupConversationReadEventSource
        : null;
    final ConversationNotificationCancellation? cancellation =
        notificationService is ConversationNotificationCancellation
        ? notificationService as ConversationNotificationCancellation
        : null;
    _notificationReadProjector =
        _notificationPresentationCoordinator != null && readSource != null
        ? GroupNotificationReadProjector(
            coordinator: _notificationPresentationCoordinator,
            readEvents: readSource.groupConversationReadStream,
            existingGroupIds: () async =>
                (await groupRepo.getAllGroups()).map((group) => group.id),
            unreadCountForGroup: msgRepo.getUnreadCount,
            messageEventIsRead: (groupId, eventIdentity) async {
              final message = await msgRepo.getMessage(eventIdentity);
              return message != null &&
                  message.groupId == groupId &&
                  message.isIncoming &&
                  message.readAt != null;
            },
            contentEventIsAcknowledged:
                _isGroupNotificationEventAcknowledged == null
                ? null
                : (groupId, metadata) {
                    final eventIdentity = metadata.eventIdentity?.trim();
                    if (eventIdentity == null || eventIdentity.isEmpty) {
                      return Future<bool>.value(false);
                    }
                    return _isGroupNotificationEventAcknowledged(
                      groupId: groupId,
                      contentKind: metadata.kind,
                      eventIdentity: eventIdentity,
                    );
                  },
            cancellation: cancellation,
          )
        : null;
    final generationCancellation =
        notificationService is ConversationNotificationGenerationCancellation
        ? notificationService as ConversationNotificationGenerationCancellation
        : null;
    final generationReplacement =
        notificationService is ConversationNotificationGenerationReplacement
        ? notificationService as ConversationNotificationGenerationReplacement
        : null;
    _notificationCanonicalReconciler =
        _notificationPresentationCoordinator != null &&
            notificationReconciliationOutbox != null &&
            generationCancellation != null &&
            generationReplacement != null &&
            loadLatestUnreadNotificationMessage != null &&
            isActiveGroupNotificationReaction != null &&
            loadLatestActiveNotificationReaction != null &&
            appVisibility != null
        ? GroupNotificationCanonicalReconciler(
            coordinator: _notificationPresentationCoordinator,
            generationCancellation: generationCancellation,
            generationReplacement: generationReplacement,
            isCurrentContentCanonical: _isCurrentNotificationContentCanonical,
            loadReplacement: _loadCanonicalNotificationReplacement,
          )
        : null;
    final displayOutbox = notificationDisplayOutbox;
    _notificationDisplayRetryCoordinator = displayOutbox == null
        ? null
        : GroupNotificationDisplayRetryCoordinator<
            GroupNotificationDisplayOutboxEntry
          >(
            loadReady: ({required limit}) =>
                displayOutbox.loadReady(limit: limit),
            entryIdentity: (entry) => entry.eventId,
            loadEarliestNextAttemptAt: displayOutbox.loadEarliestNextAttemptAt,
            project: _projectNotificationDisplayEntry,
            completeWithOutcome: (entry, outcome) async {
              final completed = await displayOutbox.completeIfExact(
                entry,
                outcome: outcome,
              );
              if (!completed) {
                throw const GroupNotificationDisplayRetryableException();
              }
            },
            retire: (entry) async {
              if (!await displayOutbox.retireIfExact(entry)) {
                throw const GroupNotificationDisplayRetryableException();
              }
            },
            recordFailure: (entry, error) async {
              await displayOutbox.recordRetryIfExact(
                eventId: entry.eventId,
                expectedRevision: entry.revision,
                lastErrorCode:
                    error is GroupNotificationDisplayStateUnavailableException
                    ? GroupNotificationDisplayOutboxErrorCode.stateUnavailable
                    : error is GroupNotificationDisplayRetryableException
                    ? GroupNotificationDisplayOutboxErrorCode.claimPending
                    : GroupNotificationDisplayOutboxErrorCode.displayFailed,
                nextAttemptAt: DateTime.now().toUtc().add(
                  const Duration(seconds: 65),
                ),
              );
            },
            scheduleRetry: _scheduleNotificationDisplayRetry,
          );
    final reconciliationOutbox = notificationReconciliationOutbox;
    final canonicalReconciler = _notificationCanonicalReconciler;
    _notificationReconciliationRetryCoordinator =
        reconciliationOutbox == null || canonicalReconciler == null
        ? null
        : GroupNotificationDisplayRetryCoordinator<
            GroupNotificationReconciliationOutboxEntry
          >(
            loadReady: ({required limit}) =>
                reconciliationOutbox.loadEligible(limit: limit),
            entryIdentity: (entry) => entry.groupId,
            loadEarliestNextAttemptAt:
                reconciliationOutbox.loadEarliestNextAttemptAt,
            project: (entry) async {
              await canonicalReconciler.reconcile(entry.groupId);
              return const GroupNotificationDisplayProjectionResult.completed();
            },
            completeWithOutcome: (entry, outcome) async {
              if (outcome != null) {
                throw StateError(
                  'group reconciliation cannot carry a display outcome',
                );
              }
              if (!await reconciliationOutbox.completeIfExact(entry)) {
                throw const GroupNotificationDisplayRetryableException();
              }
            },
            retire: (_) async {
              throw StateError('group reconciliation cannot retire');
            },
            recordFailure: (entry, _) async {
              await reconciliationOutbox.recordFailureIfExact(
                expected: entry,
                nextAttemptAt: DateTime.now().toUtc().add(
                  const Duration(seconds: 65),
                ),
              );
            },
            scheduleRetry: _scheduleNotificationDisplayRetry,
          );
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
      mediaAttachmentRepo: mediaAttachmentRepo,
      pendingReactionRepo: pendingReactionRepo,
      notificationService: notificationService,
      appVisibility: appVisibility,
      notificationToneTracker: notificationToneTracker,
      notificationPresentationCoordinator: _notificationPresentationCoordinator,
      remoteNotificationGate:
          remoteNotificationGate ?? recentRemoteNotificationGate,
      isStoppingOrDisposed: () => _isStopping || _isDisposed,
      resolveSelfPeerId: _resolveSelfPeerId,
      resolveDurableNotificationCoordinator:
          _resolveDurableNotificationCoordinator,
      loadGroupConversationNotificationSnapshot:
          _loadGroupConversationNotificationSnapshot,
      emitReactionChange: _emitReactionChange,
      stageNotificationDisplayCustody: _notificationDisplayOutbox == null
          ? null
          : _stageReactionNotificationDisplayCustody,
      reconcileNotificationDisplayCustody: _notificationDisplayOutbox == null
          ? null
          : _markNotificationDisplayCustodyReady,
      retryNotificationDisplays: _notificationDisplayOutbox == null
          ? null
          : retryPendingNotificationDisplays,
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

  Future<GroupMessageNotificationDisplayEligibility>
  _resolveGroupNotificationDisplayEligibility(
    String groupId,
    String? selfPeerId,
  ) async {
    final group = await _groupRepo.getGroup(groupId);
    final normalizedSelf = selfPeerId?.trim();
    final selfMember =
        group == null || normalizedSelf == null || normalizedSelf.isEmpty
        ? null
        : await _groupRepo.getMember(groupId, normalizedSelf);
    return evaluateGroupNotificationDisplayPolicy(
      GroupNotificationDisplayPolicyInput(
        groupExists: group != null,
        hasCurrentLocalMembership: selfMember != null,
        groupType: group?.type.name,
        isMuted: group?.isMuted ?? false,
        isArchived: group?.isArchived ?? false,
        isDissolved: group?.isDissolved ?? false,
        hasDissolvedAt: group?.dissolvedAt != null,
        hasSelfRemovedAt: group?.selfRemovedAt != null,
      ),
    );
  }

  Future<bool> _maySuppressGroupNotification(String groupId) async {
    final visibility = _appVisibility;
    if (visibility == null) return false;
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:$groupId',
    );
    return (await visibility.evaluate(identity)).maySuppress;
  }

  Future<GroupNotificationCanonicalContentDecision>
  _isCurrentNotificationContentCanonical(
    String groupId,
    ConversationNotificationContentMetadata metadata,
  ) async {
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null || selfPeerId.isEmpty) {
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    final eligibility = await _resolveGroupNotificationDisplayEligibility(
      groupId,
      selfPeerId,
    );
    if (!eligibility.shouldDisplay ||
        await _maySuppressGroupNotification(groupId)) {
      return GroupNotificationCanonicalContentDecision.retire;
    }
    final eventIdentity = metadata.eventIdentity?.trim();
    if (eventIdentity == null || eventIdentity.isEmpty) {
      return GroupNotificationCanonicalContentDecision.unknown;
    }
    if (await _isNotificationEventAcknowledged(
      groupId: groupId,
      contentKind: metadata.kind,
      eventIdentity: eventIdentity,
    )) {
      return GroupNotificationCanonicalContentDecision.retire;
    }
    final durableCorrelation =
        durableLocalNotificationContentGeneration(eventIdentity) ==
            metadata.generation?.trim()
        ? eventIdentity
        : null;
    return switch (metadata.kind) {
      ConversationNotificationContentKind.message => () async {
        final message = durableCorrelation == null
            ? await _msgRepo.getMessage(eventIdentity)
            : await _loadLatestUnreadNotificationMessage?.call(groupId);
        if (message == null) {
          if (durableCorrelation != null) {
            return GroupNotificationCanonicalContentDecision.unknown;
          }
          final deletionGroup = await _msgRepo.getLocalDeletionGroupId(
            eventIdentity,
          );
          return deletionGroup == groupId
              ? GroupNotificationCanonicalContentDecision.retire
              : GroupNotificationCanonicalContentDecision.unknown;
        }
        if (durableCorrelation != null) {
          final physicalPeerId = await _resolveCompletedOutcomePhysicalPeerId
              ?.call();
          final eventKey = trySelectNotificationCompletedOutcomeEventKey(
            producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
            authenticatedEnvelope: <String, Object?>{
              'messageId': message.id,
              if (message.logicalDeliveryId != null)
                'logicalDeliveryId': message.logicalDeliveryId,
            },
          );
          if (physicalPeerId == null ||
              eventKey == null ||
              tryComputeNotificationCompletedOutcomeCorrelation(
                    physicalPeerId: physicalPeerId,
                    producerKind:
                        NotificationCompletedOutcomeProducerKind.groupMessage,
                    eventKey: eventKey,
                  ) !=
                  durableCorrelation) {
            // A different newest canonical event owns the one group card.
            return GroupNotificationCanonicalContentDecision.retire;
          }
        }
        return message.groupId == groupId &&
                message.isIncoming &&
                message.readAt == null &&
                _privateMediaAvailability.allowsMediaDerivatives(
                  message.privateMediaPolicy,
                )
            ? GroupNotificationCanonicalContentDecision.keep
            : GroupNotificationCanonicalContentDecision.retire;
      }(),
      ConversationNotificationContentKind.reaction =>
        // Durable Plan-372 SQL commits the correlation into the canonical
        // reaction terminal marker. Legacy rows retain their bounded alias;
        // the same exact resolver supports both without inverting a digest.
        await _isActiveGroupNotificationReaction!(
          groupId: groupId,
          selfPeerId: selfPeerId,
          eventIdentity: eventIdentity,
        ),
    };
  }

  Future<CanonicalConversationNotificationReplacement?>
  _loadCanonicalNotificationReplacement(
    String groupId,
    ConversationNotificationContentMetadata currentMetadata,
  ) async {
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null || selfPeerId.isEmpty) {
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    final eligibility = await _resolveGroupNotificationDisplayEligibility(
      groupId,
      selfPeerId,
    );
    if (!eligibility.shouldDisplay ||
        await _maySuppressGroupNotification(groupId)) {
      return null;
    }
    final group = await _groupRepo.getGroup(groupId);
    if (group == null) return null;
    final snapshot = await _loadGroupConversationNotificationSnapshot(groupId);
    final latestMessage = await _loadLatestUnreadNotificationMessage!(groupId);
    final currentMessageEvent =
        currentMetadata.kind == ConversationNotificationContentKind.message
        ? currentMetadata.eventIdentity?.trim()
        : null;
    final currentMessage =
        currentMessageEvent == null ||
            currentMessageEvent.isEmpty ||
            latestMessage?.id == currentMessageEvent
        ? null
        : await _msgRepo.getMessage(currentMessageEvent);
    final reaction = await _loadLatestActiveNotificationReaction!(
      groupId: groupId,
      selfPeerId: selfPeerId,
    );

    final latestMessageCandidate = await _canonicalMessageReplacementCandidate(
      groupId: groupId,
      groupName: group.name,
      message: latestMessage,
    );
    final currentMessageCandidate = await _canonicalMessageReplacementCandidate(
      groupId: groupId,
      groupName: group.name,
      message: currentMessage,
    );
    final messageCandidate = _newerCanonicalReplacementCandidate(
      latestMessageCandidate,
      currentMessageCandidate,
    );
    final reactionCandidate = await _canonicalReactionReplacementCandidate(
      groupId: groupId,
      groupName: group.name,
      selfPeerId: selfPeerId,
      reaction: reaction,
    );
    if (messageCandidate == null) {
      return _replacementWithSnapshot(reactionCandidate?.replacement, snapshot);
    }
    if (reactionCandidate == null) {
      return _replacementWithSnapshot(messageCandidate.replacement, snapshot);
    }
    final eventOrder = messageCandidate.timestamp.compareTo(
      reactionCandidate.timestamp,
    );
    if (eventOrder != 0) {
      return _replacementWithSnapshot(
        eventOrder > 0
            ? messageCandidate.replacement
            : reactionCandidate.replacement,
        snapshot,
      );
    }
    // Canonical timestamps are normally unique; identity ordering makes the
    // rare tie deterministic across retries and process restarts.
    final replacement =
        messageCandidate.replacement.eventIdentity.compareTo(
              reactionCandidate.replacement.eventIdentity,
            ) >=
            0
        ? messageCandidate.replacement
        : reactionCandidate.replacement;
    return _replacementWithSnapshot(replacement, snapshot);
  }

  CanonicalConversationNotificationReplacement? _replacementWithSnapshot(
    CanonicalConversationNotificationReplacement? replacement,
    ConversationNotificationSnapshot? snapshot,
  ) {
    if (replacement == null) return null;
    return CanonicalConversationNotificationReplacement(
      senderUsername: replacement.senderUsername,
      messageText: replacement.messageText,
      routePayload: replacement.routePayload,
      contentKind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity,
      snapshot: snapshot,
    );
  }

  Future<ConversationNotificationSnapshot?>
  _loadGroupConversationNotificationSnapshot(String groupId) =>
      loadGroupConversationNotificationSnapshot(
        messageRepository: _msgRepo,
        groupId: groupId,
        mediaAttachmentRepository: _mediaAttachmentRepo,
        privateMediaAvailability: _privateMediaAvailability,
        pendingNotificationOverlay: _pendingConversationNotificationOverlay,
      );

  ({
    DateTime timestamp,
    CanonicalConversationNotificationReplacement replacement,
  })?
  _newerCanonicalReplacementCandidate(
    ({
      DateTime timestamp,
      CanonicalConversationNotificationReplacement replacement,
    })?
    first,
    ({
      DateTime timestamp,
      CanonicalConversationNotificationReplacement replacement,
    })?
    second,
  ) {
    if (first == null) return second;
    if (second == null) return first;
    final timeOrder = first.timestamp.compareTo(second.timestamp);
    if (timeOrder != 0) return timeOrder > 0 ? first : second;
    return first.replacement.eventIdentity.compareTo(
              second.replacement.eventIdentity,
            ) >=
            0
        ? first
        : second;
  }

  Future<
    ({
      DateTime timestamp,
      CanonicalConversationNotificationReplacement replacement,
    })?
  >
  _canonicalMessageReplacementCandidate({
    required String groupId,
    required String groupName,
    required GroupMessage? message,
  }) async {
    if (message == null ||
        message.groupId != groupId ||
        !message.isIncoming ||
        message.readAt != null ||
        !_privateMediaAvailability.allowsMediaDerivatives(
          message.privateMediaPolicy,
        )) {
      return null;
    }
    final isPrivate = message.privateMediaPolicy.isPrivate;
    final attachments = isPrivate || _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.group,
          );
    return (
      timestamp: message.timestamp.toUtc(),
      replacement: CanonicalConversationNotificationReplacement(
        senderUsername: isPrivate ? 'Mknoon' : groupName,
        messageText: isPrivate
            ? localizedGroupPrivateMediaNotificationBody()
            : '${message.senderUsername ?? ''}: '
                  '${notificationBodyForMessage(message.text, attachments)}',
        routePayload: NotificationRouteTarget.group(
          groupId,
          messageId: message.id,
        ).toPayload(),
        contentKind: ConversationNotificationContentKind.message,
        eventIdentity: message.id,
      ),
    );
  }

  Future<
    ({
      DateTime timestamp,
      CanonicalConversationNotificationReplacement replacement,
    })?
  >
  _canonicalReactionReplacementCandidate({
    required String groupId,
    required String groupName,
    required String selfPeerId,
    required GroupNotificationCanonicalReaction? reaction,
  }) async {
    if (reaction == null ||
        reaction.messageId.trim().isEmpty ||
        reaction.actorPeerId.trim().isEmpty ||
        reaction.eventIdentity.trim().isEmpty) {
      return null;
    }
    final target = await _msgRepo.getMessage(reaction.messageId);
    if (target == null) {
      final deletionGroup = await _msgRepo.getLocalDeletionGroupId(
        reaction.messageId,
      );
      if (deletionGroup == groupId) return null;
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    if (target.groupId != groupId ||
        target.senderPeerId != selfPeerId ||
        target.isIncoming ||
        !target.privateMediaPolicy.isOrdinary) {
      return null;
    }
    var actorName = '';
    try {
      actorName =
          (await _groupRepo.getMember(
            groupId,
            reaction.actorPeerId,
          ))?.username?.trim() ??
          '';
    } catch (_) {}
    final targetAttachments = _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            target.id,
            owner: MediaOwnerLane.group,
          );
    return (
      timestamp: reaction.timestamp.toUtc(),
      replacement: CanonicalConversationNotificationReplacement(
        senderUsername: groupName,
        messageText: localizedGroupReactionNotificationBody(
          actorName: actorName,
          targetAttachments: targetAttachments,
        ),
        routePayload: NotificationRouteTarget.group(
          groupId,
          messageId: target.id,
        ).toPayload(),
        contentKind: ConversationNotificationContentKind.reaction,
        eventIdentity: reaction.eventIdentity.trim(),
      ),
    );
  }

  void _scheduleNotificationDisplayRetry(Duration requestedDelay) {
    if (_isStopping || _isDisposed) return;
    final delay = requestedDelay.isNegative ? Duration.zero : requestedDelay;
    final dueAt = DateTime.now().toUtc().add(delay);
    final existingDueAt = _notificationDisplayRetryDueAt;
    if (_notificationDisplayRetryTimer?.isActive == true &&
        existingDueAt != null &&
        !dueAt.isBefore(existingDueAt)) {
      return;
    }
    _notificationDisplayRetryTimer?.cancel();
    _notificationDisplayRetryDueAt = dueAt;
    _notificationDisplayRetryTimer = Timer(delay, () {
      _notificationDisplayRetryTimer = null;
      _notificationDisplayRetryDueAt = null;
      if (_isStopping || _isDisposed) return;
      _retryPendingNotificationDisplaysUnawaited('timer');
    });
  }

  /// Runs one bounded canonical display-outbox pass. Startup/resume callers
  /// invoke this only after their canonical drains have completed.
  Future<void> retryPendingNotificationDisplays() {
    if (_isStopping || _isDisposed) return Future<void>.value();
    return _trackInFlight(_retryPendingNotificationDisplays());
  }

  Future<void> _retryPendingNotificationDisplays() async {
    if (_canonicalNotificationRecoveryDepth > 0 ||
        _canonicalNotificationStateIncomplete) {
      return;
    }
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _notificationDisplayRetryCoordinator?.retryNow();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _notificationReconciliationRetryCoordinator?.retryNow();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  void _retryPendingNotificationDisplaysUnawaited(String trigger) {
    unawaited(
      retryPendingNotificationDisplays().catchError((Object error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_NOTIFICATION_DISPLAY_BACKGROUND_RETRY_ERROR',
          details: {
            'trigger': trigger,
            'errorType': error.runtimeType.toString(),
          },
        );
      }),
    );
  }

  /// Defers every display projection while a canonical inbox recovery may
  /// still contain a later delete, read, reaction removal, or policy change.
  /// Concurrent drain owners share one generation.
  void beginCanonicalNotificationRecovery() {
    if ((_notificationDisplayOutbox == null &&
            _notificationReconciliationOutbox == null) ||
        _isDisposed) {
      return;
    }
    if (_canonicalNotificationRecoveryDepth == 0) {
      _canonicalNotificationRecoveryFailed = false;
    }
    _canonicalNotificationRecoveryDepth++;
  }

  /// Releases one canonical-recovery owner and projects only after every
  /// overlapping owner proved an exhausted, error-free drain.
  Future<void> endCanonicalNotificationRecovery({
    required bool canonicalStateComplete,
    bool releaseStartupHold = false,
  }) async {
    if ((_notificationDisplayOutbox == null &&
            _notificationReconciliationOutbox == null) ||
        _isDisposed) {
      return;
    }
    if (_canonicalNotificationRecoveryDepth <= 0) {
      throw StateError('canonical notification recovery was not started');
    }
    if (!canonicalStateComplete) {
      _canonicalNotificationRecoveryFailed = true;
    }
    var releaseCount = 1;
    if (releaseStartupHold && _startupCanonicalNotificationRecoveryPending) {
      _startupCanonicalNotificationRecoveryPending = false;
      releaseCount++;
    }
    if (_canonicalNotificationRecoveryDepth < releaseCount) {
      throw StateError('canonical notification recovery owner mismatch');
    }
    _canonicalNotificationRecoveryDepth -= releaseCount;
    if (_canonicalNotificationRecoveryDepth > 0) return;

    final mayProject = !_canonicalNotificationRecoveryFailed;
    _canonicalNotificationRecoveryFailed = false;
    if (!mayProject) {
      _canonicalNotificationStateIncomplete = true;
      _notificationReadProjector?.completeStartupCanonicalRecovery(
        canonicalStateComplete: false,
      );
      return;
    }
    _canonicalNotificationStateIncomplete = false;
    _notificationReadProjector?.completeStartupCanonicalRecovery(
      canonicalStateComplete: true,
    );
    try {
      await retryPendingNotificationDisplays();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_NOTIFICATION_DISPLAY_POST_DRAIN_RETRY_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _stageMessageNotificationDisplayCustody(
    GroupMessage message,
  ) async {
    final outbox = _notificationDisplayOutbox;
    if (outbox == null ||
        _notificationService == null ||
        _appVisibility == null ||
        !message.isIncoming) {
      return;
    }
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null || selfPeerId.isEmpty) {
      // Identity is projection authority, not an optional display hint. If it
      // is temporarily unavailable we cannot distinguish a self echo or
      // evaluate current local membership, so abort before canonical mutation
      // and let the existing inbox/relay owner retry.
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    if (message.senderPeerId == selfPeerId) return;
    final eligibility = await _resolveGroupNotificationDisplayEligibility(
      message.groupId,
      selfPeerId,
    );
    if (!eligibility.shouldDisplay) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await outbox.stage(
      GroupNotificationDisplayOutboxEntry.message(
        eventId: message.id,
        groupId: message.groupId,
        messageId: message.id,
        actorPeerId: message.senderPeerId,
        eventTimestamp: message.timestamp.toUtc().toIso8601String(),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _markNotificationDisplayCustodyReady(String eventId) async {
    final outbox = _notificationDisplayOutbox;
    if (outbox == null) return;
    var entry = await outbox.loadByEventId(eventId);
    if (entry == null || entry.isReady) return;
    final promoted = await outbox.promoteReadyIfExact(
      eventId: eventId,
      expectedRevision: entry.revision,
    );
    if (promoted) return;
    entry = await outbox.loadByEventId(eventId);
    if (entry?.isReady == true) return;
    throw StateError('group notification display custody ready CAS failed');
  }

  Future<void> _stageReactionNotificationDisplayCustody(
    GroupReactionPayload payload,
    String groupId,
  ) async {
    final outbox = _notificationDisplayOutbox;
    if (outbox == null ||
        payload.action != GroupReactionPayload.actionAdd ||
        _notificationService == null ||
        _appVisibility == null) {
      return;
    }
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null || selfPeerId.isEmpty) {
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    if (payload.senderPeerId == selfPeerId) return;
    final target = await _msgRepo.getMessage(payload.messageId);
    if (target == null ||
        target.groupId != groupId ||
        target.senderPeerId != selfPeerId ||
        target.isIncoming ||
        !target.privateMediaPolicy.isOrdinary) {
      return;
    }
    final eligibility = await _resolveGroupNotificationDisplayEligibility(
      groupId,
      selfPeerId,
    );
    if (!eligibility.shouldDisplay) return;

    final eventId = payload.notificationTransitionId;
    final now = DateTime.now().toUtc().toIso8601String();
    await outbox.stage(
      GroupNotificationDisplayOutboxEntry.reaction(
        eventId: eventId,
        groupId: groupId,
        messageId: payload.messageId,
        actorPeerId: payload.senderPeerId,
        eventTimestamp: payload.timestamp,
        reactionId: payload.id,
        reactionAction: payload.action,
        reactionTombstone: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectNotificationDisplayEntry(GroupNotificationDisplayOutboxEntry entry) {
    final coordinator = _notificationPresentationCoordinator;
    if (coordinator == null) {
      return Future<GroupNotificationDisplayProjectionResult>.value(
        const GroupNotificationDisplayProjectionResult.retryLater(),
      );
    }
    return coordinator.runForGroup(
      entry.groupId,
      () => _projectNotificationDisplayEntryInsideKey(entry),
    );
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectNotificationDisplayEntryInsideKey(
    GroupNotificationDisplayOutboxEntry entry,
  ) async {
    return switch (entry.eventKind) {
      GroupNotificationDisplayOutboxKind.message =>
        _projectMessageNotificationDisplay(entry),
      GroupNotificationDisplayOutboxKind.reaction =>
        _projectReactionNotificationDisplay(entry),
      _ => const GroupNotificationDisplayProjectionResult.retired(),
    };
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectMessageNotificationDisplay(
    GroupNotificationDisplayOutboxEntry entry,
  ) async {
    final message = await _msgRepo.getMessage(entry.messageId);
    if (message == null) {
      if (isGroupNotificationDisplayCanonicalRetiredMarker(
        entry.lastAttemptAt,
      )) {
        return _projectCanonicalRetiredMessageNotificationDisplay(entry);
      }
      final deletionGroup = await _msgRepo.getLocalDeletionGroupId(
        entry.messageId,
      );
      if (deletionGroup == entry.groupId) {
        return _projectCanonicalRetiredMessageNotificationDisplay(entry);
      }
      throw const GroupNotificationDisplayStateUnavailableException();
    }
    if (message.groupId != entry.groupId ||
        message.senderPeerId != entry.actorPeerId ||
        !_sameNotificationEventTime(message.timestamp, entry.eventTimestamp) ||
        !message.isIncoming) {
      if (groupNotificationDisplayDurableCorrelationFromMarker(
            entry.lastAttemptAt,
          ) !=
          null) {
        return _projectCanonicalRetiredMessageNotificationDisplay(entry);
      }
      return const GroupNotificationDisplayProjectionResult.retired();
    }
    final eventKey =
        message.logicalDeliveryId == null &&
            message.id.startsWith(kUnauthenticatedIncomingGroupMessageIdPrefix)
        ? null
        : trySelectNotificationCompletedOutcomeEventKey(
            producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
            authenticatedEnvelope: <String, Object?>{
              'messageId': message.id,
              if (message.logicalDeliveryId != null)
                'logicalDeliveryId': message.logicalDeliveryId,
            },
          );
    if (eventKey == null) {
      // Locally synthesized pre-authentication IDs have no stable producer
      // key and must not mint a ledger correlation. Drain them through the
      // incumbent exact-SQL compatibility path.
      return _projectLegacyMessageNotificationDisplay(entry, message);
    }
    final displayOutbox = _notificationDisplayOutbox;
    if (displayOutbox == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final authority = await _resolveDurableGroupNotificationAuthority(
      groupId: entry.groupId,
      producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
      ledgerProducerKind: LocalNotificationProducerKind.groupMessage,
      eventKey: eventKey,
    );
    if (authority == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final boundEntry = await displayOutbox.bindDurableCorrelationIfExact(
      entry,
      durableEventCorrelation: authority.eventCorrelation,
    );
    if (boundEntry == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    entry = boundEntry;
    final service = _notificationService;
    final visibility = _appVisibility;
    if (service == null || visibility == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final group = await _groupRepo.getGroup(entry.groupId);
    final isPrivate = message.privateMediaPolicy.isPrivate;
    final attachments = isPrivate || _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.group,
          );
    var sqlHandoffCompleted = false;
    var terminalEntry = entry;
    NotificationCompletedOutcomeCandidate? terminalOutcome;
    final durableContext = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: authority.currentOpaqueBinding,
      eventCorrelation: authority.eventCorrelation,
      conversationDigest: authority.conversationIdentity.digest,
      producerKind: LocalNotificationProducerKind.groupMessage,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: _notificationPresentationOwner,
      terminalObserverCompletesSqlHandoff: true,
      readFinalCanonicalDisposition: () =>
          _readFinalMessageNotificationDisposition(
            entry,
            acknowledgementEventIdentity: authority.eventCorrelation,
            onExactReady: (current) => terminalEntry = current,
          ),
      onEffectTerminal: (receipt) async {
        terminalOutcome = await _outcomeForTerminalReceipt(
          authority: authority,
          receipt: receipt,
        );
        final handoff = await displayOutbox.completeOrVerifyIfExact(
          terminalEntry,
          outcome: terminalOutcome,
          durableEventCorrelation: authority.eventCorrelation,
        );
        if (handoff ==
            DurableLocalNotificationSqlHandoffResult.retryableMismatch) {
          throw const GroupNotificationDisplayRetryableException();
        }
        final settled = await authority.registry.settleSqlReadyEffect(
          currentOpaqueBinding: authority.currentOpaqueBinding,
          eventCorrelation: receipt.eventCorrelation,
          expectedRevision: receipt.recordRevision,
        );
        if (settled == null) {
          throw const GroupNotificationDisplayRetryableException();
        }
        if (!await displayOutbox.retireAfterDurableSettlementIfExact(
          terminalEntry,
          durableEventCorrelation: authority.eventCorrelation,
        )) {
          throw const GroupNotificationDisplayRetryableException();
        }
        sqlHandoffCompleted = true;
      },
    );
    final result = await maybeShowNotification(
      notificationService: service,
      appVisibility: visibility,
      forceSilent: isIosMailboxAlertSilentReplayContext,
      contactPeerId: 'group:${entry.groupId}',
      routePayload: NotificationRouteTarget.group(
        entry.groupId,
        messageId: message.id,
      ).toPayload(),
      senderUsername: isPrivate ? 'Mknoon' : (group?.name ?? 'Mknoon'),
      messageText: isPrivate
          ? localizedGroupPrivateMediaNotificationBody()
          : '${message.senderUsername ?? ''}: '
                '${notificationBodyForMessage(message.text, attachments)}',
      messageId: message.id,
      notificationEventIdentity: entry.eventId,
      toneTracker: _notificationToneTracker,
      durableNotificationCoordinatorResolver:
          _resolveDurableNotificationCoordinator,
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(entry.groupId),
      notificationEventType: 'group_message',
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      markRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) => _remoteNotificationGate
              .markAnnouncement(payload: payload, messageId: messageId),
      backgroundDuplicateGuardDelay: Duration.zero,
      durableEffectContext: durableContext,
    );
    return _projectionForDurablePresentation(
      result: result,
      sqlHandoffCompleted: sqlHandoffCompleted,
      outcomeCandidate: terminalOutcome,
      expectedReady: terminalEntry,
    );
  }

  /// Drains pre-authentication compatibility custody without inventing a
  /// durable event identity.
  Future<GroupNotificationDisplayProjectionResult>
  _projectLegacyMessageNotificationDisplay(
    GroupNotificationDisplayOutboxEntry entry,
    GroupMessage message,
  ) async {
    final disposition = await _readFinalMessageNotificationDisposition(
      entry,
      acknowledgementEventIdentity: message.id,
      onExactReady: (_) {},
    );
    if (disposition ==
        DurableLocalNotificationCanonicalDisposition.retryableUnknown) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    if (disposition != DurableLocalNotificationCanonicalDisposition.eligible) {
      return const GroupNotificationDisplayProjectionResult.completed();
    }
    final service = _notificationService;
    final visibility = _appVisibility;
    if (service == null || visibility == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final group = await _groupRepo.getGroup(entry.groupId);
    final isPrivate = message.privateMediaPolicy.isPrivate;
    final attachments = isPrivate || _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.group,
          );
    final result = await maybeShowNotification(
      notificationService: service,
      appVisibility: visibility,
      forceSilent: isIosMailboxAlertSilentReplayContext,
      contactPeerId: 'group:${entry.groupId}',
      routePayload: NotificationRouteTarget.group(
        entry.groupId,
        messageId: message.id,
      ).toPayload(),
      senderUsername: isPrivate ? 'Mknoon' : (group?.name ?? 'Mknoon'),
      messageText: isPrivate
          ? localizedGroupPrivateMediaNotificationBody()
          : '${message.senderUsername ?? ''}: '
                '${notificationBodyForMessage(message.text, attachments)}',
      messageId: message.id,
      toneTracker: _notificationToneTracker,
      durableNotificationCoordinatorResolver:
          _resolveDurableNotificationCoordinator,
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(entry.groupId),
      notificationEventType: 'group_message',
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      markRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) => _remoteNotificationGate
              .markAnnouncement(payload: payload, messageId: messageId),
      backgroundDuplicateGuardDelay: Duration.zero,
    );
    return result == NotificationPresentationResult.contendedRetryable
        ? const GroupNotificationDisplayProjectionResult.retryLater()
        : const GroupNotificationDisplayProjectionResult.completed();
  }

  /// Re-enters the one final-effect boundary after canonical message removal.
  /// The opaque correlation was bound to READY before the original attempt,
  /// so deleted logical-delivery facts never need to be reconstructed here.
  Future<GroupNotificationDisplayProjectionResult>
  _projectCanonicalRetiredMessageNotificationDisplay(
    GroupNotificationDisplayOutboxEntry entry,
  ) async {
    final marker = entry.lastAttemptAt;
    if (!isGroupNotificationDisplayCanonicalRetiredMarker(marker)) {
      return groupNotificationDisplayDurableCorrelationFromMarker(marker) ==
              null
          ? const GroupNotificationDisplayProjectionResult.retired()
          : const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final correlation = groupNotificationDisplayDurableCorrelationFromMarker(
      marker,
    );
    if (correlation == null) {
      // Canonical retirement won the race before correlation binding, so no
      // Plan372 ledger attempt could have started for this exact READY row.
      return const GroupNotificationDisplayProjectionResult.retired();
    }
    final authority =
        await _resolveDurableGroupNotificationAuthorityFromCorrelation(
          groupId: entry.groupId,
          producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
          ledgerProducerKind: LocalNotificationProducerKind.groupMessage,
          eventCorrelation: correlation,
        );
    final service = _notificationService;
    final visibility = _appVisibility;
    final displayOutbox = _notificationDisplayOutbox;
    if (authority == null ||
        service == null ||
        visibility == null ||
        displayOutbox == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }

    var sqlHandoffCompleted = false;
    var terminalEntry = entry;
    final durableContext = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: authority.currentOpaqueBinding,
      eventCorrelation: authority.eventCorrelation,
      conversationDigest: authority.conversationIdentity.digest,
      producerKind: LocalNotificationProducerKind.groupMessage,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: _notificationPresentationOwner,
      terminalObserverCompletesSqlHandoff: true,
      readFinalCanonicalDisposition: () =>
          _readFinalMessageNotificationDisposition(
            entry,
            acknowledgementEventIdentity: authority.eventCorrelation,
            onExactReady: (current) => terminalEntry = current,
          ),
      onEffectTerminal: (receipt) async {
        final handoff = await displayOutbox.completeOrVerifyIfExact(
          terminalEntry,
          durableEventCorrelation: authority.eventCorrelation,
        );
        if (handoff ==
            DurableLocalNotificationSqlHandoffResult.retryableMismatch) {
          throw const GroupNotificationDisplayRetryableException();
        }
        final settled = await authority.registry.settleSqlReadyEffect(
          currentOpaqueBinding: authority.currentOpaqueBinding,
          eventCorrelation: receipt.eventCorrelation,
          expectedRevision: receipt.recordRevision,
        );
        if (settled == null ||
            !await displayOutbox.retireAfterDurableSettlementIfExact(
              terminalEntry,
              durableEventCorrelation: authority.eventCorrelation,
            )) {
          throw const GroupNotificationDisplayRetryableException();
        }
        sqlHandoffCompleted = true;
      },
    );
    final result = await maybeShowNotification(
      notificationService: service,
      appVisibility: visibility,
      forceSilent: isIosMailboxAlertSilentReplayContext,
      contactPeerId: 'group:${entry.groupId}',
      routePayload: NotificationRouteTarget.group(
        entry.groupId,
        messageId: entry.messageId,
      ).toPayload(),
      senderUsername: 'Mknoon',
      messageText: 'Mknoon',
      messageId: entry.messageId,
      notificationEventIdentity: entry.eventId,
      toneTracker: _notificationToneTracker,
      durableNotificationCoordinatorResolver:
          _resolveDurableNotificationCoordinator,
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(entry.groupId),
      notificationEventType: 'group_message',
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      markRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) => _remoteNotificationGate
              .markAnnouncement(payload: payload, messageId: messageId),
      backgroundDuplicateGuardDelay: Duration.zero,
      durableEffectContext: durableContext,
    );
    return _projectionForDurablePresentation(
      result: result,
      sqlHandoffCompleted: sqlHandoffCompleted,
      outcomeCandidate: null,
      expectedReady: terminalEntry,
    );
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectReactionNotificationDisplay(
    GroupNotificationDisplayOutboxEntry entry,
  ) async {
    if (entry.reactionAction != GroupReactionPayload.actionAdd ||
        entry.reactionTombstone != false ||
        entry.reactionId == null) {
      return const GroupNotificationDisplayProjectionResult.retired();
    }
    final target = await _msgRepo.getMessage(entry.messageId);
    final deletionGroup = target == null
        ? await _msgRepo.getLocalDeletionGroupId(entry.messageId)
        : null;
    if (target == null && deletionGroup != entry.groupId) {
      final marker = entry.lastAttemptAt;
      if (!isGroupNotificationDisplayCanonicalRetiredMarker(marker)) {
        throw const GroupNotificationDisplayStateUnavailableException();
      }
      if (groupNotificationDisplayDurableCorrelationFromMarker(marker) ==
          null) {
        // Pre-bind compatibility custody has no ledger attempt to settle.
        return const GroupNotificationDisplayProjectionResult.retired();
      }
    }
    if (target != null && target.groupId != entry.groupId) {
      if (groupNotificationDisplayDurableCorrelationFromMarker(
            entry.lastAttemptAt,
          ) !=
          null) {
        return const GroupNotificationDisplayProjectionResult.retryLater();
      }
      return const GroupNotificationDisplayProjectionResult.retired();
    }
    final eventKey = entry.eventId.startsWith('legacy-reaction:')
        ? null
        : trySelectNotificationCompletedOutcomeEventKey(
            producerKind:
                NotificationCompletedOutcomeProducerKind.groupReaction,
            authenticatedEnvelope: <String, Object?>{
              'notificationTransitionId': entry.eventId,
            },
          );
    if (eventKey == null) {
      // Pre-372 bounded legacy transitions have no authenticated raw producer
      // key and must not mint a ledger correlation. Keep their incumbent
      // exact-SQL projection path until custody drains naturally.
      return _projectLegacyReactionNotificationDisplay(entry, target);
    }
    final displayOutbox = _notificationDisplayOutbox;
    if (displayOutbox == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final authority = await _resolveDurableGroupNotificationAuthority(
      groupId: entry.groupId,
      producerKind: NotificationCompletedOutcomeProducerKind.groupReaction,
      ledgerProducerKind: LocalNotificationProducerKind.groupReaction,
      eventKey: eventKey,
    );
    if (authority == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final boundEntry = await displayOutbox.bindDurableCorrelationIfExact(
      entry,
      durableEventCorrelation: authority.eventCorrelation,
    );
    if (boundEntry == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    entry = boundEntry;
    final service = _notificationService;
    final visibility = _appVisibility;
    if (service == null || visibility == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final group = await _groupRepo.getGroup(entry.groupId);
    var actorName = '';
    try {
      final actor = await _groupRepo.getMember(
        entry.groupId,
        entry.actorPeerId,
      );
      actorName = actor?.username?.trim() ?? '';
    } catch (_) {}
    final attachments = _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : target == null || !target.privateMediaPolicy.isOrdinary
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            target.id,
            owner: MediaOwnerLane.group,
          );
    var sqlHandoffCompleted = false;
    var terminalEntry = entry;
    NotificationCompletedOutcomeCandidate? terminalOutcome;
    final durableContext = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: authority.currentOpaqueBinding,
      eventCorrelation: authority.eventCorrelation,
      conversationDigest: authority.conversationIdentity.digest,
      producerKind: LocalNotificationProducerKind.groupReaction,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: _notificationPresentationOwner,
      terminalObserverCompletesSqlHandoff: true,
      readFinalCanonicalDisposition: () =>
          _readFinalReactionNotificationDisposition(
            entry,
            acknowledgementEventIdentity: authority.eventCorrelation,
            onExactReady: (current) => terminalEntry = current,
          ),
      onEffectTerminal: (receipt) async {
        terminalOutcome = await _outcomeForTerminalReceipt(
          authority: authority,
          receipt: receipt,
        );
        final handoff = await displayOutbox.completeOrVerifyIfExact(
          terminalEntry,
          outcome: terminalOutcome,
          durableEventCorrelation: authority.eventCorrelation,
        );
        if (handoff ==
            DurableLocalNotificationSqlHandoffResult.retryableMismatch) {
          throw const GroupNotificationDisplayRetryableException();
        }
        final settled = await authority.registry.settleSqlReadyEffect(
          currentOpaqueBinding: authority.currentOpaqueBinding,
          eventCorrelation: receipt.eventCorrelation,
          expectedRevision: receipt.recordRevision,
        );
        if (settled == null) {
          throw const GroupNotificationDisplayRetryableException();
        }
        if (!await displayOutbox.retireAfterDurableSettlementIfExact(
          terminalEntry,
          durableEventCorrelation: authority.eventCorrelation,
        )) {
          throw const GroupNotificationDisplayRetryableException();
        }
        sqlHandoffCompleted = true;
      },
    );
    final result = await maybeShowNotification(
      notificationService: service,
      appVisibility: visibility,
      forceSilent: isIosMailboxAlertSilentReplayContext,
      contactPeerId: 'group:${entry.groupId}',
      routePayload: NotificationRouteTarget.group(
        entry.groupId,
        messageId: entry.messageId,
      ).toPayload(),
      senderUsername: group?.name ?? 'Mknoon',
      messageText: localizedGroupReactionNotificationBody(
        actorName: actorName,
        targetAttachments: attachments,
      ),
      messageId: entry.eventId,
      notificationEventIdentity: boundedReactionEventIdentity(entry.eventId),
      notificationEventType: 'message_reaction',
      toneTracker: _notificationToneTracker,
      durableNotificationCoordinatorResolver:
          _resolveDurableNotificationCoordinator,
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(entry.groupId),
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
      durableEffectContext: durableContext,
    );
    return _projectionForDurablePresentation(
      result: result,
      sqlHandoffCompleted: sqlHandoffCompleted,
      outcomeCandidate: terminalOutcome,
      expectedReady: terminalEntry,
    );
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectLegacyReactionNotificationDisplay(
    GroupNotificationDisplayOutboxEntry entry,
    GroupMessage? target,
  ) async {
    final disposition = await _readFinalReactionNotificationDisposition(
      entry,
      acknowledgementEventIdentity: boundedReactionEventIdentity(entry.eventId),
      onExactReady: (_) {},
    );
    if (disposition ==
        DurableLocalNotificationCanonicalDisposition.retryableUnknown) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    if (disposition != DurableLocalNotificationCanonicalDisposition.eligible) {
      return const GroupNotificationDisplayProjectionResult.completed();
    }
    final service = _notificationService;
    final visibility = _appVisibility;
    if (service == null || visibility == null || target == null) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    final group = await _groupRepo.getGroup(entry.groupId);
    var actorName = '';
    try {
      final actor = await _groupRepo.getMember(
        entry.groupId,
        entry.actorPeerId,
      );
      actorName = actor?.username?.trim() ?? '';
    } catch (_) {}
    final attachments =
        _mediaAttachmentRepo == null || !target.privateMediaPolicy.isOrdinary
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            target.id,
            owner: MediaOwnerLane.group,
          );
    final result = await maybeShowNotification(
      notificationService: service,
      appVisibility: visibility,
      forceSilent: isIosMailboxAlertSilentReplayContext,
      contactPeerId: 'group:${entry.groupId}',
      routePayload: NotificationRouteTarget.group(
        entry.groupId,
        messageId: entry.messageId,
      ).toPayload(),
      senderUsername: group?.name ?? 'Mknoon',
      messageText: localizedGroupReactionNotificationBody(
        actorName: actorName,
        targetAttachments: attachments,
      ),
      messageId: entry.eventId,
      notificationEventIdentity: boundedReactionEventIdentity(entry.eventId),
      notificationEventType: 'message_reaction',
      toneTracker: _notificationToneTracker,
      durableNotificationCoordinatorResolver:
          _resolveDurableNotificationCoordinator,
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(entry.groupId),
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
    );
    return result == NotificationPresentationResult.contendedRetryable
        ? const GroupNotificationDisplayProjectionResult.retryLater()
        : const GroupNotificationDisplayProjectionResult.completed();
  }

  Future<_GroupDurableNotificationAuthority?>
  _resolveDurableGroupNotificationAuthority({
    required String groupId,
    required NotificationCompletedOutcomeProducerKind producerKind,
    required LocalNotificationProducerKind ledgerProducerKind,
    required String eventKey,
  }) async {
    final resolveBinding = _resolveCurrentOpaqueBinding;
    final resolvePhysicalPeer = _resolveCompletedOutcomePhysicalPeerId;
    final registry = _durableLocalNotificationEffectRegistry;
    if (resolveBinding == null ||
        resolvePhysicalPeer == null ||
        registry == null) {
      return null;
    }
    final binding = await resolveBinding();
    final physicalPeerId = await resolvePhysicalPeer();
    if (!isCanonicalRuntimeOpaqueBinding(binding) || physicalPeerId == null) {
      return null;
    }
    final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
      physicalPeerId: physicalPeerId,
      producerKind: producerKind,
      eventKey: eventKey,
    );
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:$groupId',
    );
    if (correlation == null || identity == null) return null;
    return _GroupDurableNotificationAuthority(
      currentOpaqueBinding: binding!,
      eventCorrelation: correlation,
      conversationIdentity: identity,
      ledgerProducerKind: ledgerProducerKind,
      outcomeProducerKind: producerKind,
      physicalPeerId: physicalPeerId,
      eventKey: eventKey,
      registry: registry,
    );
  }

  Future<_GroupDurableNotificationAuthority?>
  _resolveDurableGroupNotificationAuthorityFromCorrelation({
    required String groupId,
    required NotificationCompletedOutcomeProducerKind producerKind,
    required LocalNotificationProducerKind ledgerProducerKind,
    required String eventCorrelation,
  }) async {
    final resolveBinding = _resolveCurrentOpaqueBinding;
    final registry = _durableLocalNotificationEffectRegistry;
    if (resolveBinding == null ||
        registry == null ||
        durableLocalNotificationContentGeneration(eventCorrelation) == null) {
      return null;
    }
    final binding = await resolveBinding();
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:$groupId',
    );
    if (!isCanonicalRuntimeOpaqueBinding(binding) || identity == null) {
      return null;
    }
    return _GroupDurableNotificationAuthority(
      currentOpaqueBinding: binding!,
      eventCorrelation: eventCorrelation,
      conversationIdentity: identity,
      ledgerProducerKind: ledgerProducerKind,
      outcomeProducerKind: producerKind,
      physicalPeerId: null,
      eventKey: null,
      registry: registry,
    );
  }

  Future<DurableLocalNotificationCanonicalDisposition>
  _readFinalMessageNotificationDisposition(
    GroupNotificationDisplayOutboxEntry entry, {
    required String acknowledgementEventIdentity,
    required void Function(GroupNotificationDisplayOutboxEntry) onExactReady,
  }) async {
    try {
      final selfPeerId = await _resolveSelfPeerId();
      if (selfPeerId == null || selfPeerId.isEmpty) {
        return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
      final group = await _groupRepo.getGroup(entry.groupId);
      final selfMember = group == null
          ? null
          : await _groupRepo.getMember(entry.groupId, selfPeerId);
      final message = await _msgRepo.getMessage(entry.messageId);
      final deletionGroup = message == null
          ? await _msgRepo.getLocalDeletionGroupId(entry.messageId)
          : null;
      final acknowledged = await _isNotificationEventAcknowledged(
        groupId: entry.groupId,
        contentKind: ConversationNotificationContentKind.message,
        eventIdentity: acknowledgementEventIdentity,
      );
      final policy = _evaluateCurrentGroupPolicy(
        group: group,
        hasCurrentLocalMembership: selfMember != null,
      );
      if (!policy.shouldDisplay ||
          (message != null &&
              !_privateMediaAvailability.allowsMediaDerivatives(
                message.privateMediaPolicy,
              ))) {
        return _finalDispositionForExactReady(
          entry,
          DurableLocalNotificationCanonicalDisposition.suppressedPolicy,
          onExactReady: onExactReady,
        );
      }
      final decisionWithoutAcknowledgement =
          evaluateBackgroundGroupNotificationPostShowState(
            comparand: BackgroundGroupMessageNotificationComparand(
              groupId: entry.groupId,
              messageId: entry.messageId,
              senderPeerId: entry.actorPeerId,
            ),
            localPeerId: selfPeerId,
            groupRow: group == null
                ? null
                : Map<String, Object?>.from(group.toMap()),
            localMemberRow: selfMember == null
                ? null
                : Map<String, Object?>.from(selfMember.toMap()),
            messageRow: message == null
                ? null
                : Map<String, Object?>.from(message.toMap()),
            messageDeletionRow: deletionGroup == entry.groupId
                ? <String, Object?>{
                    'group_id': entry.groupId,
                    'message_id': entry.messageId,
                  }
                : null,
            readAcknowledgementRow: null,
          );
      final disposition =
          decisionWithoutAcknowledgement ==
              BackgroundGroupNotificationPostShowDecision.retire
          ? DurableLocalNotificationCanonicalDisposition.cancelled
          : acknowledged
          ? DurableLocalNotificationCanonicalDisposition.read
          : _durableDisposition(decisionWithoutAcknowledgement);
      return _finalDispositionForExactReady(
        entry,
        disposition,
        onExactReady: onExactReady,
      );
    } on Object {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
  }

  Future<DurableLocalNotificationCanonicalDisposition>
  _readFinalReactionNotificationDisposition(
    GroupNotificationDisplayOutboxEntry entry, {
    required String acknowledgementEventIdentity,
    required void Function(GroupNotificationDisplayOutboxEntry) onExactReady,
  }) async {
    try {
      final selfPeerId = await _resolveSelfPeerId();
      if (selfPeerId == null || selfPeerId.isEmpty) {
        return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
      final group = await _groupRepo.getGroup(entry.groupId);
      final selfMember = group == null
          ? null
          : await _groupRepo.getMember(entry.groupId, selfPeerId);
      final target = await _msgRepo.getMessage(entry.messageId);
      final deletionGroup = target == null
          ? await _msgRepo.getLocalDeletionGroupId(entry.messageId)
          : null;
      final reaction = await _reactionRepo
          ?.getReactionForSenderIncludingRemoved(
            messageId: entry.messageId,
            senderPeerId: entry.actorPeerId,
          );
      final eventIdentity = boundedReactionEventIdentity(entry.eventId);
      final acknowledged = await _isNotificationEventAcknowledged(
        groupId: entry.groupId,
        contentKind: ConversationNotificationContentKind.reaction,
        eventIdentity: acknowledgementEventIdentity,
      );
      final policy = _evaluateCurrentGroupPolicy(
        group: group,
        hasCurrentLocalMembership: selfMember != null,
      );
      if (!policy.shouldDisplay ||
          (target != null && !target.privateMediaPolicy.isOrdinary)) {
        return _finalDispositionForExactReady(
          entry,
          DurableLocalNotificationCanonicalDisposition.suppressedPolicy,
          onExactReady: onExactReady,
        );
      }
      final reactionRow = reaction == null
          ? null
          : <String, Object?>{
              ...reaction.toMap(),
              'notification_acknowledged_at':
                  reaction.notificationAcknowledgedAt,
            };
      final decisionWithoutAcknowledgement =
          evaluateBackgroundGroupNotificationPostShowState(
            comparand: BackgroundGroupReactionNotificationComparand(
              groupId: entry.groupId,
              reactionId: entry.reactionId!,
              messageId: entry.messageId,
              senderPeerId: entry.actorPeerId,
              timestamp: entry.eventTimestamp,
              notificationEventIdentity: eventIdentity,
            ),
            localPeerId: selfPeerId,
            groupRow: group == null
                ? null
                : Map<String, Object?>.from(group.toMap()),
            localMemberRow: selfMember == null
                ? null
                : Map<String, Object?>.from(selfMember.toMap()),
            reactionRow: reactionRow,
            targetMessageRow: target == null
                ? null
                : Map<String, Object?>.from(target.toMap()),
            targetDeletionRow: deletionGroup == entry.groupId
                ? <String, Object?>{
                    'group_id': entry.groupId,
                    'message_id': entry.messageId,
                  }
                : null,
            readAcknowledgementRow: null,
          );
      final disposition =
          decisionWithoutAcknowledgement ==
              BackgroundGroupNotificationPostShowDecision.retire
          ? DurableLocalNotificationCanonicalDisposition.cancelled
          : acknowledged
          ? DurableLocalNotificationCanonicalDisposition.read
          : _durableDisposition(decisionWithoutAcknowledgement);
      return _finalDispositionForExactReady(
        entry,
        disposition,
        onExactReady: onExactReady,
      );
    } on Object {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
  }

  GroupMessageNotificationDisplayEligibility _evaluateCurrentGroupPolicy({
    required GroupModel? group,
    required bool hasCurrentLocalMembership,
  }) => evaluateGroupNotificationDisplayPolicy(
    GroupNotificationDisplayPolicyInput(
      groupExists: group != null,
      hasCurrentLocalMembership: hasCurrentLocalMembership,
      groupType: group?.type.name,
      isMuted: group?.isMuted ?? false,
      isArchived: group?.isArchived ?? false,
      isDissolved: group?.isDissolved ?? false,
      hasDissolvedAt: group?.dissolvedAt != null,
      hasSelfRemovedAt: group?.selfRemovedAt != null,
    ),
  );

  DurableLocalNotificationCanonicalDisposition _durableDisposition(
    BackgroundGroupNotificationPostShowDecision decision,
  ) => switch (decision) {
    BackgroundGroupNotificationPostShowDecision.keep =>
      DurableLocalNotificationCanonicalDisposition.eligible,
    BackgroundGroupNotificationPostShowDecision.retire =>
      DurableLocalNotificationCanonicalDisposition.cancelled,
    BackgroundGroupNotificationPostShowDecision.read =>
      DurableLocalNotificationCanonicalDisposition.read,
    BackgroundGroupNotificationPostShowDecision.unknown =>
      DurableLocalNotificationCanonicalDisposition.retryableUnknown,
  };

  Future<DurableLocalNotificationCanonicalDisposition>
  _finalDispositionForExactReady(
    GroupNotificationDisplayOutboxEntry expected,
    DurableLocalNotificationCanonicalDisposition disposition, {
    required void Function(GroupNotificationDisplayOutboxEntry) onExactReady,
  }) async {
    final current = await _notificationDisplayOutbox?.loadByEventId(
      expected.eventId,
    );
    if (current == null ||
        !current.isReady ||
        current.eventKind != expected.eventKind ||
        current.groupId != expected.groupId ||
        current.messageId != expected.messageId ||
        current.actorPeerId != expected.actorPeerId ||
        current.eventTimestamp != expected.eventTimestamp ||
        current.reactionId != expected.reactionId ||
        current.reactionAction != expected.reactionAction ||
        current.reactionTombstone != expected.reactionTombstone) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    if (isGroupNotificationDisplayCanonicalRetiredMarker(
      current.lastAttemptAt,
    )) {
      onExactReady(current);
      return DurableLocalNotificationCanonicalDisposition.cancelled;
    }
    if (current.revision != expected.revision) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    onExactReady(current);
    return disposition;
  }

  Future<NotificationCompletedOutcomeCandidate?> _outcomeForTerminalReceipt({
    required _GroupDurableNotificationAuthority authority,
    required DurableLocalNotificationEffectReceipt receipt,
  }) async {
    if (receipt.eventCorrelation != authority.eventCorrelation) {
      throw const GroupNotificationDisplayRetryableException();
    }
    final category = switch (receipt.presentationState) {
      LocalNotificationPresentationState.osPosted =>
        NotificationCompletedOutcomeCategory.osPosted,
      LocalNotificationPresentationState.inChat =>
        NotificationCompletedOutcomeCategory.inChat,
      LocalNotificationPresentationState.notEvaluated ||
      LocalNotificationPresentationState.suppressedPolicy ||
      LocalNotificationPresentationState.cancelled => null,
    };
    final physicalPeerId = authority.physicalPeerId;
    final eventKey = authority.eventKey;
    if (!_completedOutcomeProducerEnabled ||
        category == null ||
        physicalPeerId == null ||
        eventKey == null) {
      return null;
    }
    if (!await _liveCompletedOutcomeProducerReady()) return null;
    return NotificationCompletedOutcomeCandidate(
      physicalPeerId: physicalPeerId,
      producerKind: authority.outcomeProducerKind,
      eventKey: eventKey,
      outcome: category,
      completedAt: DateTime.now().toUtc(),
    );
  }

  Future<bool> _liveCompletedOutcomeProducerReady() async {
    final read = _readCompletedOutcomeProducerReady;
    if (read == null) return true;
    try {
      return await read();
    } on Object {
      return false;
    }
  }

  Future<GroupNotificationDisplayProjectionResult>
  _projectionForDurablePresentation({
    required NotificationPresentationResult result,
    required bool sqlHandoffCompleted,
    required NotificationCompletedOutcomeCandidate? outcomeCandidate,
    required GroupNotificationDisplayOutboxEntry expectedReady,
  }) async {
    if (result == NotificationPresentationResult.contendedRetryable) {
      return const GroupNotificationDisplayProjectionResult.retryLater();
    }
    if (!sqlHandoffCompleted) {
      // The durable boundary returned a terminal receipt, but exact SQL B did
      // not finish. Preserve the raw revision so SETTLED replay can retry the
      // same transaction-B CAS without manufacturing a new producer attempt.
      return GroupNotificationDisplayProjectionResult.retryLater(
        preserveReadyRevision: await _isStillExactReadyRevision(expectedReady),
      );
    }
    return GroupNotificationDisplayProjectionResult.completed(
      outcomeCandidate: outcomeCandidate,
      sqlHandoffCompleted: true,
    );
  }

  Future<bool> _isStillExactReadyRevision(
    GroupNotificationDisplayOutboxEntry expected,
  ) async {
    try {
      final current = await _notificationDisplayOutbox?.loadByEventId(
        expected.eventId,
      );
      return current != null &&
          current.isReady &&
          current.revision == expected.revision &&
          current.eventKind == expected.eventKind &&
          current.groupId == expected.groupId &&
          current.messageId == expected.messageId &&
          current.actorPeerId == expected.actorPeerId &&
          current.eventTimestamp == expected.eventTimestamp &&
          current.reactionId == expected.reactionId &&
          current.reactionAction == expected.reactionAction &&
          current.reactionTombstone == expected.reactionTombstone;
    } on Object {
      // Unknown storage state is not authority to rewrite READY. A later
      // lifecycle/reconciliation trigger will repeat the exact comparison.
      return true;
    }
  }

  Future<bool> _isNotificationEventAcknowledged({
    required String groupId,
    required ConversationNotificationContentKind contentKind,
    required String eventIdentity,
  }) async {
    final resolver = _isGroupNotificationEventAcknowledged;
    return resolver != null &&
        await resolver(
          groupId: groupId,
          contentKind: contentKind,
          eventIdentity: eventIdentity,
        );
  }

  bool _sameNotificationEventTime(DateTime canonical, String encoded) {
    final eventTime = DateTime.tryParse(encoded);
    return eventTime != null &&
        canonical.toUtc().isAtSameMomentAs(eventTime.toUtc());
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
    GroupMessageDeliveryDisposition? deliveryDisposition,
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
      deliverySource:
          deliveryDisposition == GroupMessageDeliveryDisposition.historyRepair
          ? 'historyRepair'
          : 'replay',
      deliveryDisposition: deliveryDisposition,
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
        final normalized = value?.trim();
        final resolved = normalized == null || normalized.isEmpty
            ? null
            : normalized;
        _cachedSelfPeerId = resolved;
        // A transient null during startup is not an authoritative identity
        // result. Keep the resolver retryable so durable custody can converge
        // without requiring a process restart.
        _hasResolvedSelfPeerId = resolved != null;
        _selfPeerIdLoadFuture = null;
        return resolved;
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
    // Live streams and startup durable-buffer flushes begin before the native
    // group inbox can be drained. Keep every staged display marker fail-closed
    // until that first canonical recovery proves it exhausted the inbox; a
    // later page may still contain a read, delete, dissolve, or reaction
    // REMOVE that terminalizes an earlier ADD.
    if ((_notificationDisplayOutbox != null ||
            _notificationReconciliationOutbox != null) &&
        !_startupCanonicalNotificationRecoveryPending) {
      _startupCanonicalNotificationRecoveryPending = true;
      beginCanonicalNotificationRecovery();
    }
    _notificationReadProjector?.start(
      deferStartupReconciliation: _startupCanonicalNotificationRecoveryPending,
    );
    if (_notificationReconciliationRetryCoordinator != null &&
        _notificationReconciliationSignalSubscription == null) {
      _notificationReconciliationSignalSubscription =
          groupNotificationReconciliationSignals.listen((_) {
            if (_isStopping || _isDisposed) return;
            _retryPendingNotificationDisplaysUnawaited('signal');
          });
    }

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
    if (rawMessageId.isEmpty || rawMessageId.trim() != rawMessageId) {
      return null;
    }

    final rawText = data['text'];
    final text = rawText is String ? rawText : '';
    if (text.startsWith('{"__sys":')) return null;

    return rawMessageId;
  }

  Future<void> _handleQueuedUserMessage(
    Map<String, dynamic> data, {
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
    bool allowMembershipBuffer = true,
    bool requestRecoveryOnError = false,
    String deliverySource = 'listener',
    GroupMessageDeliveryDisposition? deliveryDisposition,
    bool membershipPhaseHeld = false,
    VerifiedProtectedGroupAuthorityReplay? protectedAuthorityReplay,
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
        deliveryDisposition: deliveryDisposition,
        membershipPhaseHeld: membershipPhaseHeld,
        deferKeyRepairRequest: membershipPhaseHeld,
        protectedAuthorityReplay: protectedAuthorityReplay,
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
            deliveryDisposition: deliveryDisposition,
            membershipPhaseHeld: membershipPhaseHeld,
            deferKeyRepairRequest: membershipPhaseHeld,
            protectedAuthorityReplay: protectedAuthorityReplay,
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
    GroupMessageDeliveryDisposition? deliveryDisposition,
    bool membershipPhaseHeld = false,
    bool deferKeyRepairRequest = false,
    VerifiedProtectedGroupAuthorityReplay? protectedAuthorityReplay,
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
      final isHistoryRepair =
          deliveryDisposition == GroupMessageDeliveryDisposition.historyRepair;
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
          if (protectedAuthorityReplay != null) {
            throw StateError(
              'protected authority replay requires the signature bridge',
            );
          }
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
          authorityPhaseHeld: membershipPhaseHeld,
          protectedAuthorityReplay: protectedAuthorityReplay,
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
        deliveryDisposition: deliveryDisposition,
        stageNotificationDisplayCustody:
            isHistoryRepair || _notificationDisplayOutbox == null
            ? null
            : _stageMessageNotificationDisplayCustody,
        markNotificationDisplayCustodyReady:
            isHistoryRepair || _notificationDisplayOutbox == null
            ? null
            : (message) => _markNotificationDisplayCustodyReady(message.id),
      );

      if (!isHistoryRepair &&
          outcome is IncomingGroupMessageIgnored &&
          outcome.canonicalMessage != null &&
          _notificationDisplayOutbox != null &&
          wireMessageId == outcome.canonicalMessage!.id) {
        // Only an authority-exact stable-ID replay may recover custody left
        // not-ready by a crash after canonical persistence. Rejected events
        // carry no canonical authority and can never promote a reused wire ID.
        await _notificationDisplayOutbox.reconcileMessageAliasReady(
          aliasEventId: outcome.canonicalMessage!.id,
          canonicalMessage: outcome.canonicalMessage!,
        );
        await retryPendingNotificationDisplays();
      }

      if (outcome is IncomingGroupMessageDuplicate) {
        final canonicalMessage = outcome.canonicalMessage;
        final displayOutbox = _notificationDisplayOutbox;
        if (!isHistoryRepair && displayOutbox != null) {
          final aliasEventId = wireMessageId?.isNotEmpty == true
              ? wireMessageId!
              : canonicalMessage.id;
          await displayOutbox.reconcileMessageAliasReady(
            aliasEventId: aliasEventId,
            canonicalMessage: canonicalMessage,
          );
          await retryPendingNotificationDisplays();
        }
        if (outcome.persistedAttachmentIds.isNotEmpty &&
            _privateMediaAvailability.allowsMediaDerivatives(
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
          notificationInert: isHistoryRepair,
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

        // The durable path projects the ready marker through the same keyed
        // lane as read cancellation. Plugin failure is retained in SQLCipher
        // and no longer controls relay cursor progress.
        if (!isHistoryRepair && _notificationDisplayOutbox != null) {
          await retryPendingNotificationDisplays();
        }

        // Compatibility path for tests/non-production compositions without
        // the v106 outbox.
        if (!isHistoryRepair &&
            _notificationDisplayOutbox == null &&
            senderId != selfPeerId &&
            _notificationService != null &&
            _appVisibility != null) {
          final group = await _groupRepo.getGroup(groupId);
          final groupName = group?.name ?? 'Group';
          final displayEligibility =
              await _resolveGroupNotificationDisplayEligibility(
                groupId,
                selfPeerId,
              );
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
          if (displayEligibility.shouldDisplay) {
            Future<NotificationPresentationResult>
            present() => maybeShowNotification(
              notificationService: _notificationService,
              appVisibility: _appVisibility,
              forceSilent: isIosMailboxAlertSilentReplayContext,
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
              loadConversationNotificationSnapshot: () =>
                  _loadGroupConversationNotificationSnapshot(groupId),
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
            final presentationCoordinator =
                _notificationPresentationCoordinator;
            if (presentationCoordinator == null) {
              await present();
            } else {
              await presentationCoordinator.runForGroup(groupId, present);
            }
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
    _notificationDisplayRetryTimer?.cancel();
    _notificationDisplayRetryTimer = null;
    _notificationDisplayRetryDueAt = null;
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
    final reconciliationSignalSubscription =
        _notificationReconciliationSignalSubscription;
    _notificationReconciliationSignalSubscription = null;

    late final Future<void> stopFuture;
    stopFuture =
        () async {
          Object? cancellationError;
          StackTrace? cancellationStackTrace;
          try {
            await Future.wait<void>([
              if (messageSubscription != null) messageSubscription.cancel(),
              if (reactionSubscription != null) reactionSubscription.cancel(),
              if (diagnosticSubscription != null)
                diagnosticSubscription.cancel(),
              if (reconciliationSignalSubscription != null)
                reconciliationSignalSubscription.cancel(),
            ]);
          } catch (error, stackTrace) {
            cancellationError = error;
            cancellationStackTrace = stackTrace;
          }
          // Subscription cancellation can fail, but teardown must still quiesce
          // every handler that was already admitted before surfacing that error.
          await _awaitInFlightHandlers();
          if (cancellationError != null) {
            Error.throwWithStackTrace(
              cancellationError,
              cancellationStackTrace!,
            );
          }
        }().whenComplete(() {
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
    _notificationDisplayRetryTimer?.cancel();
    _notificationDisplayRetryTimer = null;
    _notificationDisplayRetryDueAt = null;
    _notificationDisplayRetryCoordinator?.dispose();
    _notificationReconciliationRetryCoordinator?.dispose();
    unawaited(_notificationReadProjector?.dispose());
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

/// Non-virtual composition seam for protected-content custody.
///
/// These adapters intentionally live outside [GroupMessageListener]'s stable,
/// subclassable facade. They reuse its canonical persistence, notification,
/// and stream owners without widening the DTR-16 override contract.
extension GroupMessageListenerProtectedContentAdapter on GroupMessageListener {
  /// Builds identifier-only READY custody for the typed protected-content
  /// transaction. No row is written here: the adapter commits this map with
  /// the event log and canonical projection in one SQL transaction.
  Future<Map<String, Object?>?> buildProtectedMessageDisplayReadyRow(
    GroupMessage message,
  ) async {
    if (_notificationDisplayOutbox == null ||
        _notificationService == null ||
        !message.isIncoming) {
      return null;
    }
    final selfPeerId = await _resolveSelfPeerId();
    if (selfPeerId == null ||
        selfPeerId.isEmpty ||
        message.senderPeerId == selfPeerId ||
        !(await _resolveGroupNotificationDisplayEligibility(
          message.groupId,
          selfPeerId,
        )).shouldDisplay) {
      return null;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    return GroupNotificationDisplayOutboxEntry.message(
      eventId: message.id,
      groupId: message.groupId,
      messageId: message.id,
      actorPeerId: message.senderPeerId,
      eventTimestamp: message.timestamp.toUtc().toIso8601String(),
      readiness: GroupNotificationDisplayOutboxReadiness.ready,
      createdAt: now,
      updatedAt: now,
    ).toMap();
  }

  Future<Map<String, Object?>?> buildProtectedReactionDisplayReadyRow(
    String groupId,
    GroupReactionPayload payload,
  ) async {
    if (_notificationDisplayOutbox == null ||
        _notificationService == null ||
        payload.action != GroupReactionPayload.actionAdd) {
      return null;
    }
    final selfPeerId = await _resolveSelfPeerId();
    final target = await _msgRepo.getMessage(payload.messageId);
    if (selfPeerId == null ||
        selfPeerId.isEmpty ||
        payload.senderPeerId == selfPeerId ||
        target == null ||
        target.groupId != groupId ||
        target.senderPeerId != selfPeerId ||
        target.isIncoming ||
        !target.privateMediaPolicy.isOrdinary ||
        !(await _resolveGroupNotificationDisplayEligibility(
          groupId,
          selfPeerId,
        )).shouldDisplay) {
      return null;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    return GroupNotificationDisplayOutboxEntry.reaction(
      eventId: payload.notificationTransitionId,
      groupId: groupId,
      messageId: payload.messageId,
      actorPeerId: payload.senderPeerId,
      eventTimestamp: payload.timestamp,
      reactionId: payload.id,
      reactionAction: payload.action,
      reactionTombstone: false,
      readiness: GroupNotificationDisplayOutboxReadiness.ready,
      createdAt: now,
      updatedAt: now,
    ).toMap();
  }

  void publishProtectedGroupMessage(GroupMessage message) {
    _emitGroupMessage(message);
  }

  void publishProtectedGroupReactionChange(ReactionChange change) {
    _emitReactionChange(change);
  }

  /// Replays one exact system transition under a capability minted only after
  /// its protected authority proof and durable PREPARED fact were verified.
  /// Mutable current-member authorization must not invalidate that historical
  /// authority while an interrupted projection is being repaired.
  Future<void> handleAuthenticatedAuthorityReplayEnvelope(
    Map<String, dynamic> data, {
    required VerifiedProtectedGroupAuthorityReplay authority,
    GroupMessageRepository? msgRepoOverride,
    bool rethrowOnError = false,
    bool membershipPhaseHeld = false,
  }) async {
    final replayData = Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(data),
    );
    if (!authority.authorizesSystemReplay(replayData)) {
      throw StateError('protected authority replay capability mismatch');
    }
    if (!await _allowsInboundAccountSideEffects(
      operation: 'group_replay_message',
      data: replayData,
    )) {
      throw StateError('protected authority replay account gate closed');
    }
    return _handleQueuedUserMessage(
      replayData,
      msgRepoOverride: msgRepoOverride,
      rethrowOnError: rethrowOnError,
      allowMembershipBuffer: false,
      deliverySource: 'protectedAuthorityReplay',
      membershipPhaseHeld: membershipPhaseHeld,
      protectedAuthorityReplay: authority,
    );
  }
}
