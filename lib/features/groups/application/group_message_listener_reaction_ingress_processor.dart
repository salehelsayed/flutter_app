part of 'group_message_listener.dart';

final class _GroupReactionIngressProcessor {
  _GroupReactionIngressProcessor({
    required GroupRepository groupRepo,
    required GroupMessageRepository msgRepo,
    required ReactionRepository? reactionRepo,
    required MediaAttachmentRepository? mediaAttachmentRepo,
    required GroupPendingReactionRepository? pendingReactionRepo,
    required NotificationService? notificationService,
    required ActiveConversationTracker? groupConversationTracker,
    required AppLifecycleState Function()? getAppLifecycleState,
    required NotificationToneTracker? notificationToneTracker,
    required GroupNotificationPresentationCoordinator?
    notificationPresentationCoordinator,
    required RecentRemoteNotificationGate remoteNotificationGate,
    required bool Function() isStoppingOrDisposed,
    required Future<String?> Function() resolveSelfPeerId,
    required Future<DurableNotificationToneLease?> Function()
    resolveDurableNotificationCoordinator,
    required Future<ConversationNotificationSnapshot?> Function(String groupId)
    loadGroupConversationNotificationSnapshot,
    required void Function(ReactionChange) emitReactionChange,
    required Future<void> Function(
      GroupReactionPayload payload,
      String groupId,
    )?
    stageNotificationDisplayCustody,
    required Future<void> Function(String eventId)?
    reconcileNotificationDisplayCustody,
    required Future<void> Function()? retryNotificationDisplays,
  }) : _groupRepo = groupRepo,
       _msgRepo = msgRepo,
       _reactionRepo = reactionRepo,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _pendingReactionRepo = pendingReactionRepo,
       _notificationService = notificationService,
       _groupConversationTracker = groupConversationTracker,
       _getAppLifecycleState = getAppLifecycleState,
       _notificationToneTracker = notificationToneTracker,
       _notificationPresentationCoordinator =
           notificationPresentationCoordinator,
       _remoteNotificationGate = remoteNotificationGate,
       _isStoppingOrDisposed = isStoppingOrDisposed,
       _resolveSelfPeerId = resolveSelfPeerId,
       _resolveDurableNotificationCoordinator =
           resolveDurableNotificationCoordinator,
       _loadGroupConversationNotificationSnapshot =
           loadGroupConversationNotificationSnapshot,
       _emitReactionChange = emitReactionChange,
       _stageNotificationDisplayCustody = stageNotificationDisplayCustody,
       _reconcileNotificationDisplayCustody =
           reconcileNotificationDisplayCustody,
       _retryNotificationDisplays = retryNotificationDisplays;

  final GroupRepository _groupRepo;
  final GroupMessageRepository _msgRepo;
  final ReactionRepository? _reactionRepo;
  final MediaAttachmentRepository? _mediaAttachmentRepo;
  final GroupPendingReactionRepository? _pendingReactionRepo;
  final NotificationService? _notificationService;
  final ActiveConversationTracker? _groupConversationTracker;
  final AppLifecycleState Function()? _getAppLifecycleState;
  final NotificationToneTracker? _notificationToneTracker;
  final GroupNotificationPresentationCoordinator?
  _notificationPresentationCoordinator;
  final RecentRemoteNotificationGate _remoteNotificationGate;
  final bool Function() _isStoppingOrDisposed;
  final Future<String?> Function() _resolveSelfPeerId;
  final Future<DurableNotificationToneLease?> Function()
  _resolveDurableNotificationCoordinator;
  final Future<ConversationNotificationSnapshot?> Function(String groupId)
  _loadGroupConversationNotificationSnapshot;
  final void Function(ReactionChange) _emitReactionChange;
  final Future<void> Function(GroupReactionPayload payload, String groupId)?
  _stageNotificationDisplayCustody;
  final Future<void> Function(String eventId)?
  _reconcileNotificationDisplayCustody;
  final Future<void> Function()? _retryNotificationDisplays;
  final Set<String> _pendingReactionClaims = <String>{};

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

  /// Replays buffered reactions whose target [message] has just been persisted
  /// (INV-R4). An in-process claim serializes overlapping startup/live flushes,
  /// while the durable row is deleted only after reaction handling succeeds.
  /// A crash or repository exception therefore leaves retryable custody rather
  /// than deleting the only copy before applying it (INV-R5).
  Future<void> _flushPendingReactionsForMessage(
    GroupMessage message, {
    bool membershipPhaseHeld = false,
    bool notificationInert = false,
  }) async {
    final repo = _pendingReactionRepo;
    final reactionRepo = _reactionRepo;
    if (repo == null || reactionRepo == null) return;
    if (_isStoppingOrDisposed()) return;

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
      if (_isStoppingOrDisposed()) return;
      if (membershipPhaseHeld) {
        await _flushPendingReactionLocked(
          message: message,
          loaded: pending,
          repo: repo,
          reactionRepo: reactionRepo,
          notificationInert: notificationInert,
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
            notificationInert: notificationInert,
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
    required bool notificationInert,
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

    if (!_pendingReactionClaims.add(pending.id)) return;
    try {
      final pendingGroupId = pending.groupId;
      final wireReaction = GroupReactionPayload.fromDecryptedJson(
        pending.reactionJson,
      );
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
        stageNotificationDisplayCustody:
            notificationInert || _stageNotificationDisplayCustody == null
            ? null
            : (payload) =>
                  _stageNotificationDisplayCustody(payload, pendingGroupId),
        markNotificationDisplayCustodyReady:
            notificationInert || _reconcileNotificationDisplayCustody == null
            ? null
            : (payload) => _reconcileNotificationDisplayCustody(
                _notificationEventId(payload),
              ),
      );
      if (!notificationInert &&
          result == HandleGroupReactionResult.success &&
          wireReaction != null &&
          wireReaction.action == GroupReactionPayload.actionAdd &&
          _reconcileNotificationDisplayCustody != null) {
        // Reconcile an exact/stale replay whose canonical mutation may have
        // committed before an earlier process died while the marker was
        // still `not_ready`.
        await _reconcileNotificationDisplayCustody(
          _notificationEventId(wireReaction),
        );
      }
      if (result == HandleGroupReactionResult.success && change != null) {
        final targetMessage = await _loadReactionDerivativeTarget(
          groupId: pending.groupId,
          change: change,
        );
        if (targetMessage != null) {
          _emitReactionChange(change);
          if (!notificationInert && _stageNotificationDisplayCustody == null) {
            await _maybeNotifyGroupReaction(
              groupId: pending.groupId,
              reactorPeerId: pending.senderPeerId,
              change: change,
              targetMessage: targetMessage,
              eventId: wireReaction == null
                  ? null
                  : _notificationEventId(wireReaction),
            );
          }
        }
      }
      if (!notificationInert && result == HandleGroupReactionResult.success) {
        await _retryNotificationDisplays?.call();
      }
      await repo.deletePendingReaction(pending.id);
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
    } finally {
      _pendingReactionClaims.remove(pending.id);
    }
  }

  /// Startup flush: replays buffered reactions whose target message already
  /// exists locally.
  Future<void> _flushStartupDurablePendingReactions() async {
    final repo = _pendingReactionRepo;
    if (repo == null || _isStoppingOrDisposed()) return;
    try {
      final pending = await repo.getPendingReactions(
        limit: kMaxBufferedGroupReactionsPerGroup * 8,
      );
      final flushedKeys = <String>{};
      for (final row in pending) {
        if (_isStoppingOrDisposed()) return;
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

  /// Handles an incoming group reaction event from the bridge.
  Future<void> _handleReaction(
    Map<String, dynamic> data, {
    bool rethrowOnError = false,
  }) async {
    try {
      final groupId = data['groupId'] as String? ?? '';
      final senderId = data['senderId'] as String? ?? '';
      final senderDeviceId = data['senderDeviceId'] as String?;
      final transportPeerId = data['transportPeerId'] as String?;
      final senderPublicKey = data['senderPublicKey'] as String?;
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
        senderPublicKey: senderPublicKey,
        reactionJson: reactionJson,
        stageNotificationDisplayCustody:
            _stageNotificationDisplayCustody == null
            ? null
            : (payload) => _stageNotificationDisplayCustody(payload, groupId),
        markNotificationDisplayCustodyReady:
            _reconcileNotificationDisplayCustody == null
            ? null
            : (payload) => _reconcileNotificationDisplayCustody(
                _notificationEventId(payload),
              ),
      );

      if (result == HandleGroupReactionResult.success &&
          wireReaction != null &&
          wireReaction.action == GroupReactionPayload.actionAdd &&
          _reconcileNotificationDisplayCustody != null) {
        await _reconcileNotificationDisplayCustody(
          _notificationEventId(wireReaction),
        );
      }

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
          if (_stageNotificationDisplayCustody == null) {
            await _maybeNotifyGroupReaction(
              groupId: groupId,
              reactorPeerId: senderId,
              change: change,
              targetMessage: targetMessage,
              eventId: wireReaction == null
                  ? null
                  : _notificationEventId(wireReaction),
            );
          }
        }
      }
      if (result == HandleGroupReactionResult.success) {
        await _retryNotificationDisplays?.call();
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REACTION_LISTENER_ERROR',
        details: {'error': e.toString()},
      );
      if (rethrowOnError) rethrow;
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
  /// stay silent).
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
    final selfMember = group == null
        ? null
        : await _groupRepo.getMember(groupId, selfPeerId);
    final displayEligibility = evaluateGroupNotificationDisplayPolicy(
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
    if (!displayEligibility.shouldDisplay || group == null) return;

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

    final targetAttachments = _mediaAttachmentRepo == null
        ? const <MediaAttachment>[]
        : await _mediaAttachmentRepo.getAttachmentsForMessage(
            targetMessage.id,
            owner: MediaOwnerLane.group,
          );
    final body = localizedGroupReactionNotificationBody(
      actorName: reactorName,
      targetAttachments: targetAttachments,
    );
    final notificationEventId = eventId?.trim().isNotEmpty == true
        ? eventId!.trim()
        : reaction.id;

    Future<NotificationPresentationResult> present() => maybeShowNotification(
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
      loadConversationNotificationSnapshot: () =>
          _loadGroupConversationNotificationSnapshot(groupId),
      consumeRecentRemoteNotificationAnnouncement:
          ({required payload, String? messageId}) =>
              _remoteNotificationGate.consumeIfRecentAnnouncement(
                payload: payload,
                messageId: messageId,
              ),
    );
    final presentationCoordinator = _notificationPresentationCoordinator;
    if (presentationCoordinator == null) {
      await present();
    } else {
      await presentationCoordinator.runForGroup(groupId, present);
    }
  }

  String _notificationEventId(GroupReactionPayload payload) {
    return payload.notificationTransitionId;
  }
}
