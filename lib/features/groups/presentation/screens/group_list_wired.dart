import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/widgets/undo_bar.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/core/config/on_join_metadata_resync_flag.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/on_join_group_config_resync_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_exit_recovery_sheet.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

typedef GroupInviteConversationLauncher =
    Future<void> Function(ContactModel contact, {required String initialText});

/// Wired widget connecting GroupListScreen to business logic.
class GroupListWired extends StatefulWidget {
  final GroupRepository groupRepo;
  final GroupMessageRepository msgRepo;
  final GroupMessageListener groupMessageListener;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo;
  final Bridge bridge;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final P2PService p2pService;
  final GroupInviteListener? groupInviteListener;
  final Future<void> Function()? waitForGroupMembershipUpdateIdle;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;
  final ImageProcessor? imageProcessor;
  final ImageQualityPreference qualityPreference;
  final ImageQualityPreference videoQualityPreference;
  final AudioRecorderService? audioRecorderService;
  final ActiveConversationTracker? groupConversationTracker;
  final ReactionRepository? reactionRepo;
  final GroupReactionReplayOutboxRepository?
  groupReactionReplayOutboxRepository;
  final DeleteSelfRemovedGroupShellCallback? deleteSelfRemovedGroupShell;
  final BackgroundPreference backgroundPreference;

  /// Narrow host-provided seam used only by the expired-invite recovery
  /// action. GroupList has no other ownership of 1:1 conversation routing.
  final GroupInviteConversationLauncher? openInviteConversation;

  const GroupListWired({
    super.key,
    required this.groupRepo,
    required this.msgRepo,
    required this.groupMessageListener,
    this.inviteDeliveryAttemptRepo,
    required this.bridge,
    required this.identityRepo,
    required this.contactRepo,
    required this.p2pService,
    this.groupInviteListener,
    this.waitForGroupMembershipUpdateIdle,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.imageProcessor,
    this.qualityPreference = ImageQualityPreference.compressed,
    this.videoQualityPreference = ImageQualityPreference.compressed,
    this.audioRecorderService,
    this.groupConversationTracker,
    this.reactionRepo,
    this.groupReactionReplayOutboxRepository,
    this.deleteSelfRemovedGroupShell,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.openInviteConversation,
  });

  @override
  State<GroupListWired> createState() => _GroupListWiredState();
}

class _GroupListWiredState extends State<GroupListWired>
    with WidgetsBindingObserver {
  static const _loadErrorMessage = "Couldn't load groups";
  static const _acceptRecoveryRetryCount = 5;
  static const _acceptRecoveryRetryDelay = Duration(milliseconds: 500);

  /// 153: how long the "Invite declined" SnackBar offers an Undo before the
  /// decline commits irrevocably.
  static const kDeclineUndoWindow = Duration(seconds: 4);

  List<GroupModel> _groups = [];
  Map<String, GroupMessage?> _latestMessages = {};
  Map<String, int> _unreadCounts = {};
  Map<String, int> _rejoinAttempts = {};
  Set<String> _exitIntentGroupIds = <String>{};
  List<PendingGroupInvite> _pendingInvites = [];
  bool _isLoading = true;
  String? _currentLoadErrorMessage;
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<GroupModel>? _joinedInviteSubscription;
  StreamSubscription<PendingGroupInvite>? _pendingInviteSubscription;
  final Set<String> _changedGroupIds = <String>{};
  final Set<String> _processingInviteIds = <String>{};
  bool _isDeletingSelfRemovedShell = false;

  /// 153: invites optimistically hidden while their deferred decline commit is
  /// pending. Filtered inside [_loadGroups] so every reactive reload respects
  /// the hide; the per-invite [UndoBarHandle] commits on timeout (Undo /
  /// dispose cancels it first).
  final Set<String> _optimisticallyDeclinedInviteIds = <String>{};
  final Map<String, UndoBarHandle> _declineUndoBars = <String, UndoBarHandle>{};

  /// Per-row invite outcome state keyed by group id. It intentionally survives
  /// reactive/lifecycle reloads so a terminal ghost is not erased by the
  /// repository event triggered by deleting its live invite.
  final Map<String, PendingInviteRowOutcome> _inviteRowOutcomes =
      <String, PendingInviteRowOutcome>{};
  Set<String> _askNewInviteIds = <String>{};
  Set<String> _unavailableInviteContactIds = <String>{};
  int _inviteRequestQualificationEpoch = 0;

  bool get _hasDisplayableContent =>
      _groups.isNotEmpty || _pendingInvites.isNotEmpty;

  FeedRouteChanges? _buildRouteChanges() {
    final changes = FeedRouteChanges(
      changedGroupIds: Set<String>.from(_changedGroupIds),
    );
    return changes.hasChanges ? changes : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    emitFlowEvent(layer: 'FL', event: 'GROUP_LIST_FL_SCREEN_INIT', details: {});
    _loadGroups();
    _startListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadGroups());
    }
  }

  @override
  void didUpdateWidget(covariant GroupListWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openInviteConversation != widget.openInviteConversation) {
      unawaited(_refreshInviteRequestAvailability());
    }
  }

  Future<void> _loadGroups({bool showLoadingWhenEmpty = false}) async {
    if (showLoadingWhenEmpty) {
      _beginLoadGroups();
    }

    try {
      final groups = await widget.groupRepo.getActiveGroups();
      final latestMessages = <String, GroupMessage?>{};
      final unreadCounts = <String, int>{};
      final pendingInvites = await _loadPendingInvites();
      // B2: drop invites whose group is already joined (a materialized
      // orphan). Filter on membership only, never on expiry — expired-but-
      // unjoined invites keep their card so the user can still dismiss them.
      final joinedGroupIds = groups.map((group) => group.id).toSet();
      final visibleInvites = pendingInvites
          .where(
            (invite) =>
                !joinedGroupIds.contains(invite.groupId) &&
                // 153: keep optimistically-declined rows hidden across every
                // reactive reload until their deferred commit/undo resolves.
                !_optimisticallyDeclinedInviteIds.contains(invite.groupId),
          )
          .toList();
      // E: half-materialized groups (topic-join not yet succeeded) carry a
      // bounded rejoin row; surface a "Joining…"/"Couldn't join" badge for them.
      final rejoinStates = await widget.groupRepo.loadGroupRejoinStates();
      final rejoinAttempts = <String, int>{
        for (final entry in rejoinStates.entries)
          entry.key: entry.value.attemptCount,
      };
      final exitIntents = await loadAllGroupExitIntents();

      for (final group in groups) {
        latestMessages[group.id] = await widget.msgRepo.getLatestMessage(
          group.id,
        );
        unreadCounts[group.id] = await widget.msgRepo.getUnreadCount(group.id);
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _latestMessages = latestMessages;
        _unreadCounts = unreadCounts;
        _rejoinAttempts = rejoinAttempts;
        if (exitIntents.isAvailable) {
          _exitIntentGroupIds = exitIntents.intents
              .map((intent) => intent.groupId)
              .toSet();
        }
        _pendingInvites = visibleInvites;
        _isLoading = false;
        _currentLoadErrorMessage = null;
      });
      unawaited(_refreshInviteRequestAvailability());
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!_hasDisplayableContent) {
            _currentLoadErrorMessage = _loadErrorMessage;
          }
        });
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_LOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  void _beginLoadGroups() {
    if (!mounted) return;

    final shouldShowLoading = !_hasDisplayableContent;
    final shouldUpdateState =
        _currentLoadErrorMessage != null || (shouldShowLoading && !_isLoading);
    if (!shouldUpdateState) return;

    setState(() {
      _currentLoadErrorMessage = null;
      if (shouldShowLoading) {
        _isLoading = true;
      }
    });
  }

  void _retryLoadGroups() {
    unawaited(_loadGroups(showLoadingWhenEmpty: true));
  }

  Future<List<PendingGroupInvite>> _loadPendingInvites() async {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null) {
      return const [];
    }
    return inviteListener.pendingInviteRepo.getPendingInvites();
  }

  void _startListening() {
    _messageSubscription = widget.groupMessageListener.groupMessageStream
        .listen(
          (_) => _loadGroups(),
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_LIST_FL_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );

    _joinedInviteSubscription = widget.groupInviteListener?.groupJoinedStream
        .listen(
          (_) => _loadGroups(),
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_LIST_FL_INVITE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );

    _pendingInviteSubscription = widget.groupInviteListener?.pendingInviteStream
        .listen(
          (_) => _loadGroups(),
          onError: (error) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_LIST_FL_PENDING_INVITE_STREAM_ERROR',
              details: {'error': error.toString()},
            );
          },
        );
  }

  void _onGroupTap(GroupModel group) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: widget.groupRepo,
              msgRepo: widget.msgRepo,
              groupMessageListener: widget.groupMessageListener,
              openAnnouncementSenderConversation: null,
              inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
              bridge: widget.bridge,
              identityRepo: widget.identityRepo,
              contactRepo: widget.contactRepo,
              p2pService: widget.p2pService,
              mediaAttachmentRepo: widget.mediaAttachmentRepo,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              qualityPreference: widget.qualityPreference,
              videoQualityPreference: widget.videoQualityPreference,
              audioRecorderService: widget.audioRecorderService,
              groupConversationTracker: widget.groupConversationTracker,
              reactionRepo: widget.reactionRepo,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              backgroundPreference: widget.backgroundPreference,
            ),
          ),
        )
        .then((_) {
          _changedGroupIds.add(group.id);
          _loadGroups();
        });
  }

  void _onBack() {
    Navigator.of(context).pop(_buildRouteChanges());
  }

  Future<void> _onAcceptPendingInvite(PendingGroupInvite invite) async {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null ||
        _processingInviteIds.contains(invite.groupId)) {
      return;
    }

    setState(() {
      _processingInviteIds.add(invite.groupId);
      _inviteRowOutcomes.remove(invite.groupId);
      _askNewInviteIds.remove(invite.groupId);
      _unavailableInviteContactIds.remove(invite.groupId);
    });
    try {
      await _drainPendingGroupInviteInboxBeforeAccept(
        inviteListener,
        invite.groupId,
      );
      final identity = await widget.identityRepo.loadIdentity();
      final localTransportPeerId = widget.p2pService.currentState.peerId;
      final (result, group) = await _acceptPendingInviteWithRecoveryRetry(
        inviteListener: inviteListener,
        invite: invite,
        senderPeerId: identity?.peerId,
        senderPublicKey: identity?.publicKey,
        senderPrivateKey: identity?.privateKey,
        senderUsername: identity?.username,
        localTransportPeerId: localTransportPeerId,
        ownMlKemPublicKey: identity?.mlKemPublicKey,
      );
      if (group != null) {
        _changedGroupIds.add(group.id);
      }
      await _loadGroups();
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;

      // Plan 150: each non-navigating accept outcome becomes per-row inline
      // state (live card for KEPT invites; ghost row for the 8 terminal
      // outcomes whose invite was just deleted) instead of a transient
      // snackbar. 208 extends this to the 2 navigating outcomes (success /
      // join-with-recovery): they navigate straight into the chat with NO
      // snackbar (reverses DECISION-2's navigate-time confirmation toast).
      switch (result) {
        case AcceptPendingGroupInviteResult.success:
          // 208: navigating accept — move into the group chat with NO
          // confirmation snackbar.
          if (group != null && mounted) {
            _onGroupTap(group);
          }
          break;
        case AcceptPendingGroupInviteResult.bridgeError:
          if (group != null) {
            // Shape-b: the group materialized but background recovery is still
            // draining. Treat as join-with-recovery — navigate into the chat
            // with NO snackbar (208 reverses DECISION-2's navigate-time
            // recovery toast; the card is consumed/gone, so nothing renders
            // inline either).
            if (mounted) {
              _onGroupTap(group);
            }
          } else {
            // Shape-a: keep-pending retryable. The live card stays — surface
            // an inline Retry that re-runs accept through the guard.
            _setInviteRowOutcome(invite, PendingInviteRowState.retryable);
          }
          break;
        case AcceptPendingGroupInviteResult.repairPending:
          // Invite KEPT → live card shows the "Waiting for key" inline state.
          _setInviteRowOutcome(invite, PendingInviteRowState.waitingForKey);
          break;
        case AcceptPendingGroupInviteResult.notFound:
          _setTerminalOutcome(invite, l10n.group_invite_no_longer_available);
          break;
        case AcceptPendingGroupInviteResult.expired:
          _setTerminalOutcome(invite, l10n.group_invite_expired);
          break;
        case AcceptPendingGroupInviteResult.expiredFreshness:
          _setTerminalOutcome(invite, l10n.group_invite_expired_ask_resend);
          break;
        case AcceptPendingGroupInviteResult.revoked:
          _setTerminalOutcome(invite, l10n.group_invite_revoked);
          break;
        case AcceptPendingGroupInviteResult.alreadyUsed:
          _setTerminalOutcome(invite, l10n.group_invite_already_used);
          break;
        case AcceptPendingGroupInviteResult.wrongIdentity:
          _setTerminalOutcome(invite, l10n.group_invite_wrong_identity);
          break;
        case AcceptPendingGroupInviteResult.invalidPayload:
          _setTerminalOutcome(invite, l10n.group_invite_invalid);
          break;
        case AcceptPendingGroupInviteResult.duplicateGroup:
          _setTerminalOutcome(invite, l10n.group_invite_duplicate_group);
          break;
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_ACCEPT_PENDING_INVITE_ERROR',
        details: {
          'groupId': invite.groupId.length > 8
              ? invite.groupId.substring(0, 8)
              : invite.groupId,
          'error': e.toString(),
        },
      );
      await _loadGroups();
      if (mounted) {
        _showSnackBar(AppLocalizations.of(context)!.group_invite_accept_failed);
      }
    } finally {
      if (mounted) {
        setState(() => _processingInviteIds.remove(invite.groupId));
      }
    }
  }

  /// Re-runs accept for a keep-pending (retryable) invite when its inline Retry
  /// control is tapped. Routes back through [_onAcceptPendingInvite] so the
  /// `_processingInviteIds` re-entrancy guard is NEVER bypassed (INV-2).
  Future<void> _onRetryPendingInvite(PendingGroupInvite invite) {
    return _onAcceptPendingInvite(invite);
  }

  /// Sets the inline (live-card) row state for a KEPT invite (plan 150). Carries
  /// a group-name snapshot so the value class is uniform with terminal rows.
  void _setInviteRowOutcome(
    PendingGroupInvite invite,
    PendingInviteRowState state,
  ) {
    if (!mounted) return;
    setState(() {
      _inviteRowOutcomes[invite.groupId] = PendingInviteRowOutcome(
        state: state,
        groupName: invite.groupName,
        inviterPeerId: invite.senderPeerId,
        inviterUsername: invite.senderUsername,
      );
    });
    unawaited(_refreshInviteRequestAvailability());
  }

  /// Sets a terminal ghost-row outcome (plan 150 C1). The invite was deleted by
  /// the use-case, so the name is snapshotted from [invite] BEFORE `_loadGroups`
  /// dropped the live card. No snackbar — the ghost row IS the feedback.
  ///
  void _setTerminalOutcome(PendingGroupInvite invite, String reason) {
    if (!mounted) return;
    setState(() {
      _inviteRowOutcomes[invite.groupId] = PendingInviteRowOutcome(
        state: PendingInviteRowState.idle,
        groupName: invite.groupName,
        reason: reason,
        inviterPeerId: invite.senderPeerId,
        inviterUsername: invite.senderUsername,
      );
    });
    unawaited(_refreshInviteRequestAvailability());
  }

  Map<String, _InviteRequestTarget> _inviteRequestTargets() {
    if (widget.openInviteConversation == null) return const {};

    final now = DateTime.now().toUtc();
    final liveIds = _pendingInvites.map((invite) => invite.groupId).toSet();
    final targets = <String, _InviteRequestTarget>{};
    for (final invite in _pendingInvites) {
      if (invite.isExpiredAt(now) && invite.senderPeerId.isNotEmpty) {
        targets[invite.groupId] = _InviteRequestTarget(
          peerId: invite.senderPeerId,
          groupName: invite.groupName,
        );
      }
    }
    for (final entry in _inviteRowOutcomes.entries) {
      if (liveIds.contains(entry.key)) continue;
      final peerId = entry.value.inviterPeerId;
      if (peerId != null && peerId.isNotEmpty) {
        targets[entry.key] = _InviteRequestTarget(
          peerId: peerId,
          groupName: entry.value.groupName,
        );
      }
    }
    return targets;
  }

  bool _isQualifiedInviteContact(ContactModel? contact, String peerId) {
    return contact != null &&
        contact.peerId == peerId &&
        !contact.isBlocked &&
        !contact.isArchived;
  }

  Future<void> _refreshInviteRequestAvailability() async {
    final epoch = ++_inviteRequestQualificationEpoch;
    final targets = _inviteRequestTargets();
    final eligible = <String>{};
    for (final entry in targets.entries) {
      ContactModel? contact;
      try {
        contact = await widget.contactRepo.getContact(entry.value.peerId);
      } catch (_) {
        contact = null;
      }
      if (_isQualifiedInviteContact(contact, entry.value.peerId)) {
        eligible.add(entry.key);
      }
    }
    if (!mounted || epoch != _inviteRequestQualificationEpoch) return;
    setState(() {
      _askNewInviteIds = eligible;
      _unavailableInviteContactIds = _unavailableInviteContactIds.intersection(
        targets.keys.toSet(),
      )..removeAll(eligible);
    });
  }

  Future<void> _onAskForNewInvite(String inviteId) async {
    final launcher = widget.openInviteConversation;
    final target = _inviteRequestTargets()[inviteId];
    if (launcher == null || target == null) return;

    ContactModel? contact;
    try {
      contact = await widget.contactRepo.getContact(target.peerId);
    } catch (_) {
      contact = null;
    }
    if (!mounted) return;
    if (!_isQualifiedInviteContact(contact, target.peerId)) {
      setState(() {
        _askNewInviteIds.remove(inviteId);
        _unavailableInviteContactIds.add(inviteId);
      });
      return;
    }

    final draft = AppLocalizations.of(
      context,
    )!.group_invite_request_new_draft(target.groupName);
    await launcher(contact!, initialText: draft);
  }

  Future<(AcceptPendingGroupInviteResult, GroupModel?)>
  _acceptPendingInviteWithRecoveryRetry({
    required GroupInviteListener inviteListener,
    required PendingGroupInvite invite,
    required String? senderPeerId,
    required String? senderPublicKey,
    required String? senderPrivateKey,
    required String? senderUsername,
    required String? localTransportPeerId,
    required String? ownMlKemPublicKey,
  }) async {
    Future<(AcceptPendingGroupInviteResult, GroupModel?)> attempt() {
      return acceptPendingGroupInvite(
        pendingInviteRepo: inviteListener.pendingInviteRepo,
        groupRepo: widget.groupRepo,
        contactRepo: widget.contactRepo,
        msgRepo: widget.msgRepo,
        bridge: widget.bridge,
        groupId: invite.groupId,
        mediaAttachmentRepo: widget.mediaAttachmentRepo,
        reactionRepo: widget.reactionRepo,
        groupMessageListener: widget.groupMessageListener,
        senderPeerId: senderPeerId,
        senderPublicKey: senderPublicKey,
        senderPrivateKey: senderPrivateKey,
        senderUsername: senderUsername,
        ownDeviceId: localTransportPeerId,
        ownTransportPeerId: localTransportPeerId,
        ownMlKemPublicKey: ownMlKemPublicKey,
        ownKeyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(
          localTransportPeerId,
        ),
        ownKeyPackagePublicMaterial: ownMlKemPublicKey,
        onJoinConfigRequest: kOnJoinMetadataResyncEnabled
            ? ({required group, required invite}) async {
                final inviterMember = await widget.groupRepo.getMember(
                  group.id,
                  invite.senderPeerId,
                );
                unawaited(
                  sendOnJoinGroupConfigRequest(
                    p2pService: widget.p2pService,
                    bridge: widget.bridge,
                    groupId: group.id,
                    requesterPeerId: senderPeerId ?? '',
                    inviterPeerId: invite.senderPeerId,
                    inviterMlKemPublicKey: inviterMember?.mlKemPublicKey,
                  ),
                );
              }
            : null,
        drainAcceptedInboxAllPages: true,
        acceptedInboxDrainMaxAttempts: 4,
      );
    }

    var outcome = await attempt();
    for (
      var retry = 0;
      outcome.$1 == AcceptPendingGroupInviteResult.bridgeError &&
          outcome.$2 == null &&
          retry < _acceptRecoveryRetryCount;
      retry++
    ) {
      if (await inviteListener.pendingInviteRepo.getPendingInvite(
            invite.groupId,
          ) ==
          null) {
        return outcome;
      }
      await Future<void>.delayed(_acceptRecoveryRetryDelay);
      await _drainPendingGroupInviteInboxBeforeAccept(
        inviteListener,
        invite.groupId,
      );
      outcome = await attempt();
    }
    return outcome;
  }

  Future<void> _drainPendingGroupInviteInboxBeforeAccept(
    GroupInviteListener inviteListener,
    String groupId,
  ) async {
    try {
      final p2pService = widget.p2pService;
      if (p2pService is P2PFullInboxDrain) {
        await (p2pService as P2PFullInboxDrain).drainOfflineInboxFully();
      } else {
        await p2pService.drainOfflineInbox();
      }
      await inviteListener.waitForIdle();
      await widget.waitForGroupMembershipUpdateIdle?.call();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_ACCEPT_PENDING_INVITE_PREFLIGHT_WARNING',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'error': e.toString(),
        },
      );
    }
  }

  /// 153: optimistically hide the row and offer an Undo. The real decline —
  /// and its irreversible decline-ack — is deferred behind [kDeclineUndoWindow]
  /// and commits exactly once on timeout (not at all on Undo / dispose). Runs
  /// synchronously (no awaits) so the hide is instant; the held
  /// `_processingInviteIds` guard makes the commit once-only under double-tap.
  void _onDeclinePendingInvite(PendingGroupInvite invite) {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null ||
        _processingInviteIds.contains(invite.groupId)) {
      return;
    }

    setState(() {
      _processingInviteIds.add(invite.groupId);
      _optimisticallyDeclinedInviteIds.add(invite.groupId);
      _pendingInvites = _pendingInvites
          .where((i) => !_optimisticallyDeclinedInviteIds.contains(i.groupId))
          .toList();
    });

    final l10n = AppLocalizations.of(context)!;
    _declineUndoBars[invite.groupId] = showUndoBar(
      context,
      message: l10n.group_invite_declined,
      window: kDeclineUndoWindow,
      onUndo: () => _undoDecline(invite),
      onCommit: () => _commitDecline(invite),
    );
  }

  /// Cancel a pending decline before its window elapses: re-surface the invite,
  /// emit UNDONE, and never send the decline-ack. The shared handle invokes
  /// this callback only while the Undo authority is still active.
  void _undoDecline(PendingGroupInvite invite) {
    if (!mounted) return;
    _declineUndoBars.remove(invite.groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_UNDONE',
      details: {
        'surface': 'group_list',
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );
    setState(() {
      _optimisticallyDeclinedInviteIds.remove(invite.groupId);
      _processingInviteIds.remove(invite.groupId);
    });
    unawaited(_loadGroups());
  }

  /// Fire the deferred decline once the undo window elapses. Runs the real
  /// (already-idempotent) use-case, then in `finally` releases the optimistic
  /// hide + processing guard and reloads — so a throwing commit re-surfaces the
  /// still-present invite (no permanently-stuck row), while a successful commit
  /// keeps it gone (the repo deleted it).
  Future<void> _commitDecline(PendingGroupInvite invite) async {
    _declineUndoBars.remove(invite.groupId);
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DECLINE_COMMITTED',
      details: {
        'surface': 'group_list',
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );

    final inviteListener = widget.groupInviteListener;
    DeclinePendingGroupInviteResult? result;
    Object? error;
    try {
      if (inviteListener != null) {
        // Best-effort decline-ack deps (the local decline never blocks on them).
        final identity = await widget.identityRepo.loadIdentity();
        result = await declinePendingGroupInvite(
          pendingInviteRepo: inviteListener.pendingInviteRepo,
          groupId: invite.groupId,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepo,
          declinerPeerId: identity?.peerId,
          declinerPrivateKey: identity?.privateKey,
        );
      }
    } catch (e) {
      error = e;
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_DECLINE_PENDING_INVITE_ERROR',
        details: {
          'groupId': invite.groupId.length > 8
              ? invite.groupId.substring(0, 8)
              : invite.groupId,
          'error': e.toString(),
        },
      );
    } finally {
      _optimisticallyDeclinedInviteIds.remove(invite.groupId);
      _processingInviteIds.remove(invite.groupId);
      await _loadGroups();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final l10n = AppLocalizations.of(context)!;
        if (error != null) {
          _showSnackBar(l10n.group_invite_decline_failed);
        } else if (result != null) {
          switch (result) {
            case DeclinePendingGroupInviteResult.success:
              _showSnackBar(l10n.group_invite_declined);
              break;
            case DeclinePendingGroupInviteResult.notFound:
              _showSnackBar(l10n.group_invite_no_longer_available);
              break;
            case DeclinePendingGroupInviteResult.expired:
              _showSnackBar(l10n.group_invite_expired);
              break;
          }
        }
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  /// "Retry now" on a stuck (given-up) rejoin row: force the row eligible so the
  /// bounded retrier no longer skips it on backoff, then kick a fresh rejoin
  /// pass and refresh the badge (G2). Never auto-deletes the group.
  Future<void> _onRetryStuckRejoin(GroupModel group) async {
    try {
      await widget.groupRepo.forceGroupRejoinEligible(group.id);
      // Plan 150: the inline "Joining…"/"Couldn't join — retry" badge already
      // conveys this state; the redundant snackbar is dropped.
      await rejoinGroupTopics(
        bridge: widget.bridge,
        groupRepo: widget.groupRepo,
        reason: RejoinReason.nodeRequestedRecovery,
        canRejoinForExitIntent: canRejoinForExitIntent,
        processExitIntent: processExistingGroupExitIntent,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_STUCK_REJOIN_RETRY_ERROR',
        details: {'groupId': group.id, 'error': e.toString()},
      );
    } finally {
      await _loadGroups();
    }
  }

  /// "Leave" from a stuck rejoin row — a reachable exit from the dead-end (G2).
  /// Tears the group down via the normal leave path (never a silent auto-delete)
  /// and refreshes the list.
  Future<void> _onLeaveStuckGroup(GroupModel group) async {
    String? selfPeerId;
    GroupExitSnapshot? snapshot;
    try {
      final identity = await widget.identityRepo.loadIdentity();
      selfPeerId = identity?.peerId;
      if (selfPeerId != null) {
        snapshot = await resolveGroupExitSnapshot(
          groupRepo: widget.groupRepo,
          groupId: group.id,
          selfPeerId: selfPeerId,
          messageRepo: widget.msgRepo,
          inviteDeliveryAttemptRepo: widget.inviteDeliveryAttemptRepo,
          loadPendingBroadcasts: loadGroupPendingBroadcasts,
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LIST_FL_STUCK_EXIT_CLASSIFY_ERROR',
        details: {'groupId': group.id, 'error': error.toString()},
      );
    }
    if (!mounted) return;
    if (snapshot == null) {
      final l10n = AppLocalizations.of(context)!;
      _showSnackBar(
        group.selfRemovedAt != null
            ? l10n.group_removed_delete_failed
            : l10n.group_info_leave_failed,
      );
      return;
    }
    if (snapshot.group == null) {
      _changedGroupIds.add(group.id);
      await _loadGroups();
      return;
    }
    if (snapshot.disposition == GroupExitDisposition.selfRemovedDeleteLocally) {
      await _confirmDeleteSelfRemovedGroupShell(
        groupId: group.id,
        selfPeerId: selfPeerId!,
      );
      return;
    }
    if (snapshot.disposition == GroupExitDisposition.noOp) {
      _changedGroupIds.add(group.id);
      await _loadGroups();
      return;
    }

    final result = await requestGroupExitIntentLeave(group.id);
    await _handleGroupExitIntentResult(group, result);
  }

  Future<void> _handleGroupExitIntentResult(
    GroupModel group,
    GroupExitIntentRequestResult result,
  ) async {
    if (!mounted) return;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.noOp:
        _changedGroupIds.add(group.id);
        await _loadGroups();
      case GroupExitIntentRequestStatus.pendingRoleSync:
        await _showPendingGroupExit(group);
      case GroupExitIntentRequestStatus.queued:
        await _showQueuedGroupExit(group);
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        if (result.intent != null) {
          await _showQueuedGroupExit(group);
          return;
        }
        _showSnackBar(lastAdminLeaveBlockedMessage);
      case GroupExitIntentRequestStatus.unavailable:
        if (result.intent != null) {
          await _showQueuedGroupExit(group);
          return;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_LIST_FL_STUCK_LEAVE_ERROR',
          details: {'groupId': group.id, 'error': result.cause.toString()},
        );
        _showSnackBar(AppLocalizations.of(context)!.group_info_leave_failed);
      case GroupExitIntentRequestStatus.failed:
        if (result.intent != null) {
          await _showQueuedGroupExit(group);
          return;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_LIST_FL_STUCK_LEAVE_ERROR',
          details: {'groupId': group.id, 'error': result.cause.toString()},
        );
        _showSnackBar(AppLocalizations.of(context)!.group_info_leave_failed);
    }
  }

  Future<bool> _closeSheetForGroupExitResult(
    GroupExitIntentRequestResult result,
  ) async {
    if (!mounted) return false;
    switch (result.status) {
      case GroupExitIntentRequestStatus.started:
      case GroupExitIntentRequestStatus.queued:
      case GroupExitIntentRequestStatus.noOp:
        return true;
      case GroupExitIntentRequestStatus.pendingRoleSync:
        return false;
      case GroupExitIntentRequestStatus.blockedLastAdmin:
        _showSnackBar(lastAdminLeaveBlockedMessage);
        return false;
      case GroupExitIntentRequestStatus.unavailable:
      case GroupExitIntentRequestStatus.failed:
        _showSnackBar(AppLocalizations.of(context)!.group_info_leave_failed);
        return false;
    }
  }

  Future<void> _showPendingGroupExit(GroupModel group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupExitRecoverySheet.pendingRoleSync(
        groupName: group.name,
        onLeaveWhenSyncCompletes: () async => _closeSheetForGroupExitResult(
          await queueGroupExitIntentLeaveWhenSyncCompletes(group.id),
        ),
        onTryAgain: () async => _closeSheetForGroupExitResult(
          await retryGroupExitIntentLeave(group.id),
        ),
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _showQueuedGroupExit(GroupModel group) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupExitRecoverySheet.queuedLeave(
        groupName: group.name,
        onTryAgain: () async => _closeSheetForGroupExitResult(
          await retryGroupExitIntentLeave(group.id),
        ),
        onCancelQueuedLeave: () async {
          final result = await cancelQueuedGroupExitIntent(group.id);
          return switch (result.status) {
            GroupExitIntentCancelStatus.cancelled ||
            GroupExitIntentCancelStatus.notFound =>
              GroupExitQueuedCancelUiResult.cancelled,
            GroupExitIntentCancelStatus.tooLate =>
              GroupExitQueuedCancelUiResult.tooLate,
            GroupExitIntentCancelStatus.unavailable ||
            GroupExitIntentCancelStatus.failed =>
              GroupExitQueuedCancelUiResult.failed,
          };
        },
        onRefreshQueuedState: _loadGroups,
      ),
    );
    if (mounted) await _loadGroups();
  }

  Future<void> _confirmDeleteSelfRemovedGroupShell({
    required String groupId,
    required String selfPeerId,
  }) async {
    if (!mounted || _isDeletingSelfRemovedShell) return;
    _isDeletingSelfRemovedShell = true;
    final l10n = AppLocalizations.of(context)!;
    try {
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) {
          final dialogL10n = AppLocalizations.of(context)!;
          return AlertDialog(
            title: Text(dialogL10n.group_removed_delete_title),
            content: Text(dialogL10n.group_removed_delete_body),
            actions: [
              TextButton(
                key: const ValueKey('group-list-self-removed-delete-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(dialogL10n.btn_cancel),
              ),
              FilledButton(
                key: const ValueKey('group-list-self-removed-delete-confirm'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(dialogL10n.group_removed_delete_action),
              ),
            ],
          );
        },
      );
      if (shouldDelete != true || !mounted) return;

      final deleteShell =
          widget.deleteSelfRemovedGroupShell ??
          defaultDeleteSelfRemovedGroupShell;
      if (deleteShell == null) {
        await _loadGroups();
        if (mounted) _showSnackBar(l10n.group_removed_delete_failed);
        return;
      }

      DeleteSelfRemovedGroupShellResult result;
      try {
        result = await deleteShell(groupId: groupId, selfPeerId: selfPeerId);
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_LIST_FL_DELETE_SELF_REMOVED_GROUP_ERROR',
          details: {'groupId': groupId, 'error': error.toString()},
        );
        result = DeleteSelfRemovedGroupShellResult.cleanupIncomplete;
      }
      if (!mounted) return;

      _changedGroupIds.add(groupId);
      switch (result) {
        case DeleteSelfRemovedGroupShellResult.deleted:
        case DeleteSelfRemovedGroupShellResult.alreadyAbsent:
          await _loadGroups();
          return;
        case DeleteSelfRemovedGroupShellResult.refusedStateChanged:
          await _loadGroups();
          return;
        case DeleteSelfRemovedGroupShellResult.cleanupIncomplete:
          await _loadGroups();
          if (mounted) _showSnackBar(l10n.group_removed_delete_failed);
          return;
      }
    } finally {
      _isDeletingSelfRemovedShell = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _joinedInviteSubscription?.cancel();
    _pendingInviteSubscription?.cancel();
    // 153: never commit a deferred decline after unmount (safe-failure = the
    // invite is kept; a re-mount re-surfaces it = implicit undo).
    for (final bar in _declineUndoBars.values) {
      bar.cancel();
    }
    _declineUndoBars.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GroupListScreen(
      groups: _groups,
      latestMessages: _latestMessages,
      unreadCounts: _unreadCounts,
      pendingInvites: _pendingInvites,
      processingInviteIds: _processingInviteIds,
      inviteRowOutcomes: _inviteRowOutcomes,
      askNewInviteIds: _askNewInviteIds,
      unavailableInviteContactIds: _unavailableInviteContactIds,
      rejoinAttempts: _rejoinAttempts,
      exitIntentGroupIds: _exitIntentGroupIds,
      isLoading: _isLoading,
      loadErrorMessage: _currentLoadErrorMessage,
      onRetryLoad: _retryLoadGroups,
      onGroupTap: _onGroupTap,
      onAcceptPendingInvite: _onAcceptPendingInvite,
      onDeclinePendingInvite: _onDeclinePendingInvite,
      onRetryPendingInvite: _onRetryPendingInvite,
      onAskForNewInvite: _onAskForNewInvite,
      onRetryStuckRejoin: _onRetryStuckRejoin,
      onLeaveStuckGroup: _onLeaveStuckGroup,
      onBack: _onBack,
      backgroundPreference: widget.backgroundPreference,
    );
  }
}

class _InviteRequestTarget {
  final String peerId;
  final String groupName;

  const _InviteRequestTarget({required this.peerId, required this.groupName});
}
