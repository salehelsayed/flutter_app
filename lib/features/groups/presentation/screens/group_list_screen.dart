import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/group_backlog_retention_notice.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Pure UI screen displaying a list of groups.
///
/// No business logic -- all data passed via props.
/// The ExpandableFab has been moved to OrbitScreen (Phase 1).
class GroupListScreen extends StatelessWidget {
  final List<GroupModel> groups;
  final Map<String, GroupMessage?> latestMessages;
  final Map<String, int> unreadCounts;
  final List<PendingGroupInvite> pendingInvites;
  final Set<String> processingInviteIds;

  /// Group id → rejoin attempt count for groups that materialized but whose
  /// topic-join has not yet succeeded (derived from the 088 group_rejoin_state
  /// table). Drives the "Joining…" / "Couldn't join" badge.
  final Map<String, int> rejoinAttempts;

  /// Per-row accept outcome state keyed by invite id (plan 150). KEPT-invite
  /// outcomes (waitingForKey / retryable) render inline on the live card;
  /// terminal outcomes (whose invite was DELETED, so the id is no longer in
  /// [pendingInvites]) render on a ghost row keyed
  /// `pending-group-invite-outcome-<id>`.
  final Map<String, PendingInviteRowOutcome> inviteRowOutcomes;
  final bool isLoading;
  final String? loadErrorMessage;
  final VoidCallback? onRetryLoad;
  final ValueChanged<GroupModel> onGroupTap;
  final ValueChanged<PendingGroupInvite>? onAcceptPendingInvite;
  final ValueChanged<PendingGroupInvite>? onDeclinePendingInvite;

  /// Invoked when the inline Retry control on a keep-pending (retryable) invite
  /// row is tapped (plan 150). Routes back through the accept handler.
  final ValueChanged<PendingGroupInvite>? onRetryPendingInvite;

  /// Invoked when the user taps "Retry now" on a group whose rejoin has given
  /// up (attempt ≥ [_joinGiveUpThreshold]). Forces the rejoin row eligible and
  /// kicks a fresh rejoin pass (G2).
  final ValueChanged<GroupModel>? onRetryStuckRejoin;

  /// Invoked when the user taps "Leave" on a stuck group — a reachable exit
  /// from the dead-end (G2). Never auto-deletes; the user chooses to leave.
  final ValueChanged<GroupModel>? onLeaveStuckGroup;
  final VoidCallback onBack;
  final BackgroundPreference backgroundPreference;

  const GroupListScreen({
    super.key,
    required this.groups,
    this.latestMessages = const {},
    this.unreadCounts = const {},
    this.pendingInvites = const [],
    this.processingInviteIds = const <String>{},
    this.inviteRowOutcomes = const <String, PendingInviteRowOutcome>{},
    this.rejoinAttempts = const <String, int>{},
    this.isLoading = false,
    this.loadErrorMessage,
    this.onRetryLoad,
    required this.onGroupTap,
    this.onAcceptPendingInvite,
    this.onDeclinePendingInvite,
    this.onRetryPendingInvite,
    this.onRetryStuckRejoin,
    this.onLeaveStuckGroup,
    required this.onBack,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: backgroundPreference,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child:
                        groups.isNotEmpty ||
                            pendingInvites.isNotEmpty ||
                            _hasGhostOutcomes
                        ? _buildContent(context)
                        : isLoading
                        ? _buildLoadingState(context)
                        : loadErrorMessage != null
                        ? _buildLoadErrorState(context)
                        : _buildEmptyState(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            color: readableColors.iconPrimary,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.groups_title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: readableColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_outlined, size: 64, color: readableColors.iconMuted),
          const SizedBox(height: 16),
          Text(
            l10n.groups_empty_title,
            style: TextStyle(fontSize: 16, color: readableColors.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.groups_empty_desc,
            style: TextStyle(
              fontSize: 13,
              color: readableColors.disabledForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: readableColors.iconMuted,
            ),
            const SizedBox(height: 16),
            Text(
              loadErrorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.load_retry_hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: readableColors.disabledForeground,
              ),
            ),
            if (onRetryLoad != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onRetryLoad,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.btn_retry),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// True when a terminal outcome (its invite already deleted) needs a ghost
  /// row even though no live invite / group remains to render.
  bool get _hasGhostOutcomes {
    if (inviteRowOutcomes.isEmpty) return false;
    final pendingInviteIds = pendingInvites
        .map((invite) => invite.groupId)
        .toSet();
    return inviteRowOutcomes.keys.any((id) => !pendingInviteIds.contains(id));
  }

  /// A compact one-line ghost row that survives the deletion of a terminal
  /// invite (plan 150 C1). Keyed `pending-group-invite-outcome-<id>`.
  Widget _buildInviteOutcomeRow(
    BuildContext context,
    String inviteId,
    PendingInviteRowOutcome outcome,
  ) {
    final readableColors = context.backgroundReadableColors;
    return Container(
      key: ValueKey('pending-group-invite-outcome-$inviteId'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: readableColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: readableColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  outcome.groupName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textPrimary,
                  ),
                ),
                if (outcome.reason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    outcome.reason!,
                    style: TextStyle(
                      fontSize: 13,
                      color: readableColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Ghost rows: terminal outcomes whose invite was deleted by the use-case
    // (so the id is no longer a live pending invite). They keep the "which
    // invite failed & why" feedback after the live card is gone (plan 150 C1).
    final pendingInviteIds = pendingInvites
        .map((invite) => invite.groupId)
        .toSet();
    final ghostOutcomes = inviteRowOutcomes.entries
        .where((entry) => !pendingInviteIds.contains(entry.key))
        .toList();
    final hasPendingSection =
        pendingInvites.isNotEmpty || ghostOutcomes.isNotEmpty;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (hasPendingSection) ...[
          _buildSectionLabel(context, l10n.groups_pending_invites),
          const SizedBox(height: 12),
          ...pendingInvites.map((invite) {
            final outcome = inviteRowOutcomes[invite.groupId];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PendingGroupInviteCard(
                invite: invite,
                isProcessing: processingInviteIds.contains(invite.groupId),
                rowState: outcome?.state ?? PendingInviteRowState.idle,
                onAccept: onAcceptPendingInvite != null
                    ? () => onAcceptPendingInvite!(invite)
                    : null,
                onDecline: onDeclinePendingInvite != null
                    ? () => onDeclinePendingInvite!(invite)
                    : null,
                onRetry: onRetryPendingInvite != null
                    ? () => onRetryPendingInvite!(invite)
                    : null,
              ),
            );
          }),
          ...ghostOutcomes.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildInviteOutcomeRow(context, entry.key, entry.value),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (groups.isNotEmpty) ...[
          if (pendingInvites.isNotEmpty) ...[
            _buildSectionLabel(context, l10n.groups_joined),
            const SizedBox(height: 12),
          ],
          ...groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildGroupCard(context, group),
            ),
          ),
        ] else if (pendingInvites.isNotEmpty) ...[
          _buildNoJoinedGroupsCard(context),
        ],
      ],
    );
  }

  /// Mirrors the rejoin use-case's attempt cap; at/above it the bounded
  /// retrier has given up and surfaces a manual-retry affordance instead of
  /// "Joining…".
  static const int _joinGiveUpThreshold = 10;

  Widget _buildGroupCard(BuildContext context, GroupModel group) {
    final l10n = AppLocalizations.of(context)!;
    final lastMsg = latestMessages[group.id];
    final unread = unreadCounts[group.id] ?? 0;
    final retentionNotice = groupBacklogRetentionNoticeFor(group, l10n);

    // A half-materialized group (key persisted, topic-join not yet succeeded)
    // shows a join-status badge in place of the retention notice.
    final rejoinAttempt = rejoinAttempts[group.id];
    final isStuck =
        rejoinAttempt != null && rejoinAttempt >= _joinGiveUpThreshold;
    String? joinStatusText;
    if (rejoinAttempt != null) {
      joinStatusText = isStuck
          ? l10n.group_join_failed_retry
          : l10n.group_joining_in_progress;
    }

    final card = GroupCard(
      group: group,
      statusText: joinStatusText ?? retentionNotice?.listSummary,
      lastMessageSender: lastMsg != null
          ? lastMsg.senderUsername ?? l10n.groups_unknown_sender
          : null,
      lastMessageBody: lastMsg == null
          ? null
          : lastMsg.privateMediaPolicy.requiresRedaction
          ? l10n.media_unavailable
          : lastMsg.text,
      lastMessageTime: lastMsg != null
          ? _formatTime(context, lastMsg.timestamp)
          : null,
      unreadCount: unread,
      onTap: () => onGroupTap(group),
    );

    // The give-up badge is a user-facing dead-end without an action: surface a
    // manual "Retry now" (force-eligible + rejoin) and a "Leave" exit (G2).
    if (isStuck && (onRetryStuckRejoin != null || onLeaveStuckGroup != null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card, _buildStuckGroupActions(context, group)],
      );
    }

    return card;
  }

  Widget _buildStuckGroupActions(BuildContext context, GroupModel group) {
    final l10n = AppLocalizations.of(context)!;
    final dangerColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onRetryStuckRejoin != null)
            TextButton.icon(
              key: ValueKey('group-stuck-retry-${group.id}'),
              onPressed: () => onRetryStuckRejoin!(group),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.btn_retry),
            ),
          if (onLeaveStuckGroup != null)
            TextButton.icon(
              key: ValueKey('group-stuck-leave-${group.id}'),
              onPressed: () => onLeaveStuckGroup!(group),
              icon: Icon(Icons.logout, size: 18, color: dangerColor),
              label: Text(
                l10n.group_leave,
                style: TextStyle(color: dangerColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    final readableColors = context.backgroundReadableColors;

    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: readableColors.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildNoJoinedGroupsCard(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.divider),
      ),
      child: Text(
        l10n.groups_no_joined,
        style: TextStyle(
          fontSize: 13,
          color: readableColors.textSecondary,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: readableColors.iconMuted,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _GroupLoadingRow(index: 0),
        const SizedBox(height: 12),
        const _GroupLoadingRow(index: 1),
        const SizedBox(height: 12),
        const _GroupLoadingRow(index: 2),
      ],
    );
  }

  String _formatTime(BuildContext context, DateTime timestamp) {
    final locale = Localizations.localeOf(context).toString();
    return intl.DateFormat.jm(locale).format(timestamp.toLocal());
  }
}

class _GroupLoadingRow extends StatelessWidget {
  final int index;

  const _GroupLoadingRow({required this.index});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: ValueKey('group-loading-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.divider),
      ),
      child: Row(
        children: const [
          _GroupLoadingAvatar(),
          SizedBox(width: 14),
          Expanded(child: _GroupLoadingTextBlock()),
        ],
      ),
    );
  }
}

class _GroupLoadingAvatar extends StatelessWidget {
  const _GroupLoadingAvatar();

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _GroupLoadingTextBlock extends StatelessWidget {
  const _GroupLoadingTextBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupLoadingBar(widthFactor: 0.42, height: 14),
        SizedBox(height: 10),
        _GroupLoadingBar(widthFactor: 0.68),
        SizedBox(height: 10),
        _GroupLoadingBar(widthFactor: 0.28, height: 10),
      ],
    );
  }
}

class _GroupLoadingBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _GroupLoadingBar({required this.widthFactor, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: readableColors.disabledSurface,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
