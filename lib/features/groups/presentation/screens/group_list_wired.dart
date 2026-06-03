import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
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
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
  final BackgroundPreference backgroundPreference;

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
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<GroupListWired> createState() => _GroupListWiredState();
}

class _GroupListWiredState extends State<GroupListWired>
    with WidgetsBindingObserver {
  static const _loadErrorMessage = "Couldn't load groups";
  static const _acceptRecoveryRetryCount = 5;
  static const _acceptRecoveryRetryDelay = Duration(milliseconds: 500);

  List<GroupModel> _groups = [];
  Map<String, GroupMessage?> _latestMessages = {};
  Map<String, int> _unreadCounts = {};
  List<PendingGroupInvite> _pendingInvites = [];
  bool _isLoading = true;
  String? _currentLoadErrorMessage;
  StreamSubscription<GroupMessage>? _messageSubscription;
  StreamSubscription<GroupModel>? _joinedInviteSubscription;
  StreamSubscription<PendingGroupInvite>? _pendingInviteSubscription;
  final Set<String> _changedGroupIds = <String>{};
  final Set<String> _processingInviteIds = <String>{};

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

  Future<void> _loadGroups({bool showLoadingWhenEmpty = false}) async {
    if (showLoadingWhenEmpty) {
      _beginLoadGroups();
    }

    try {
      final groups = await widget.groupRepo.getActiveGroups();
      final latestMessages = <String, GroupMessage?>{};
      final unreadCounts = <String, int>{};
      final pendingInvites = await _loadPendingInvites();

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
        _pendingInvites = pendingInvites;
        _isLoading = false;
        _currentLoadErrorMessage = null;
      });
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

    setState(() => _processingInviteIds.add(invite.groupId));
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

      switch (result) {
        case AcceptPendingGroupInviteResult.success:
          _showSnackBar(
            l10n.group_invite_joined(group?.name ?? invite.groupName),
          );
          break;
        case AcceptPendingGroupInviteResult.notFound:
          _showSnackBar(l10n.group_invite_no_longer_available);
          break;
        case AcceptPendingGroupInviteResult.expired:
          _showSnackBar(l10n.group_invite_expired);
          break;
        case AcceptPendingGroupInviteResult.revoked:
          _showSnackBar(l10n.group_invite_revoked);
          break;
        case AcceptPendingGroupInviteResult.alreadyUsed:
          _showSnackBar(l10n.group_invite_already_used);
          break;
        case AcceptPendingGroupInviteResult.wrongIdentity:
          _showSnackBar(l10n.group_invite_wrong_identity);
          break;
        case AcceptPendingGroupInviteResult.repairPending:
          _showSnackBar(l10n.group_invite_needs_key);
          break;
        case AcceptPendingGroupInviteResult.invalidPayload:
          _showSnackBar(l10n.group_invite_invalid);
          break;
        case AcceptPendingGroupInviteResult.duplicateGroup:
          _showSnackBar(l10n.group_invite_duplicate_group);
          break;
        case AcceptPendingGroupInviteResult.bridgeError:
          _showSnackBar(l10n.group_invite_accept_failed);
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
        drainAcceptedInboxAllPages: true,
        acceptedInboxDrainMaxAttempts: 4,
      );
    }

    var outcome = await attempt();
    for (var retry = 0;
        outcome.$1 == AcceptPendingGroupInviteResult.bridgeError &&
            outcome.$2 == null &&
            retry < _acceptRecoveryRetryCount;
        retry++) {
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

  Future<void> _onDeclinePendingInvite(PendingGroupInvite invite) async {
    final inviteListener = widget.groupInviteListener;
    if (inviteListener == null ||
        _processingInviteIds.contains(invite.groupId)) {
      return;
    }

    setState(() => _processingInviteIds.add(invite.groupId));
    try {
      final result = await declinePendingGroupInvite(
        pendingInviteRepo: inviteListener.pendingInviteRepo,
        groupId: invite.groupId,
      );
      await _loadGroups();
      if (!mounted) {
        return;
      }
      final l10n = AppLocalizations.of(context)!;

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
    } catch (e) {
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
      await _loadGroups();
      if (mounted) {
        _showSnackBar(
          AppLocalizations.of(context)!.group_invite_decline_failed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingInviteIds.remove(invite.groupId));
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSubscription?.cancel();
    _joinedInviteSubscription?.cancel();
    _pendingInviteSubscription?.cancel();
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
      isLoading: _isLoading,
      loadErrorMessage: _currentLoadErrorMessage,
      onRetryLoad: _retryLoadGroups,
      onGroupTap: _onGroupTap,
      onAcceptPendingInvite: _onAcceptPendingInvite,
      onDeclinePendingInvite: _onDeclinePendingInvite,
      onBack: _onBack,
      backgroundPreference: widget.backgroundPreference,
    );
  }
}
