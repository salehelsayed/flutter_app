import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Per-row inline state for a pending group invite (plan 150).
///
/// Drives the KEPT-invite states rendered directly on the live
/// [PendingGroupInviteCard]:
///   - [idle]: the default accept / decline buttons.
///   - [processing]: in-button accept spinner (driven by `isProcessing`).
///   - [waitingForKey]: trailing spinner + "Waiting for key" (repairPending).
///   - [retryable]: an inline Retry control (keep-pending bridgeError).
///
/// Terminal outcomes (the invite is DELETED by the use-case) render on a
/// separate ghost row owned by the list screen, NOT on this card.
enum PendingInviteRowState { idle, processing, waitingForKey, retryable }

/// A resolved accept outcome carried by the list screen so it can render either
/// an inline state on the live card or a ghost row after the invite is deleted.
///
/// [groupName] is a snapshot taken BEFORE the invite was removed, so the ghost
/// row can still name the group it belonged to.
class PendingInviteRowOutcome {
  final PendingInviteRowState state;
  final String? reason;
  final String groupName;

  /// Inviter identity snapshotted before a terminal outcome deletes the live
  /// invite. This is only a candidate conversation target: wired surfaces
  /// must still resolve an active, unblocked, non-archived contact both when
  /// rendering and when the action is tapped.
  final String? inviterPeerId;
  final String? inviterUsername;

  const PendingInviteRowOutcome({
    required this.state,
    required this.groupName,
    this.reason,
    this.inviterPeerId,
    this.inviterUsername,
  });
}

class PendingGroupInviteCard extends StatelessWidget {
  final PendingGroupInvite invite;
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// Per-row inline state (plan 150). Defaults to [PendingInviteRowState.idle]
  /// so existing callsites (e.g. orbit_screen.dart) keep the legacy render.
  final PendingInviteRowState rowState;

  /// Invoked when the inline Retry control (retryable state) is tapped.
  /// Defaulted null so non-group-list callsites stay unchanged.
  final VoidCallback? onRetry;

  /// Optional localized detail for a live-row outcome (for example a thrown
  /// accept/decline that kept the invite in the repository).
  final String? rowReason;

  /// Available only for an expired invite whose inviter still resolves to an
  /// active contact. The wired owner re-checks that authority on tap.
  final VoidCallback? onAskForNewInvite;
  final bool inviteContactUnavailable;

  const PendingGroupInviteCard({
    super.key,
    required this.invite,
    required this.isProcessing,
    required this.onAccept,
    required this.onDecline,
    this.rowState = PendingInviteRowState.idle,
    this.onRetry,
    this.rowReason,
    this.onAskForNewInvite,
    this.inviteContactUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final isExpired = invite.isExpiredAt(DateTime.now().toUtc());
    final acceptLabel = isExpired
        ? l10n.pending_invite_expired
        : l10n.pending_invite_accept;
    final declineLabel = isExpired
        ? l10n.pending_invite_dismiss
        : l10n.pending_invite_decline;
    final actionBlue = readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
    final danger = readableColors.isLightSurface
        ? const Color(0xFF9D1C12)
        : const Color(0xFFFF8A80);
    final onAction = readableColors.isLightSurface
        ? Colors.white
        : Colors.black;

    return Container(
      key: ValueKey('pending-group-invite-${invite.groupId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: readableColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpired
              ? danger.withOpacity(readableColors.isLightSurface ? 0.32 : 0.22)
              : readableColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.groupName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ).copyWith(color: readableColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.pending_invite_invited_by(invite.senderUsername),
                      style: TextStyle(
                        fontSize: 13,
                        color: readableColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GroupTypeBadge(type: invite.groupType),
                  const SizedBox(height: 8),
                  Text(
                    isExpired
                        ? l10n.pending_invite_expired
                        : _formatExpiry(invite.expiresAt, l10n),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isExpired ? danger : readableColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (invite.groupDescription != null &&
              invite.groupDescription!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              invite.groupDescription!,
              style: TextStyle(
                fontSize: 13,
                color: readableColors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey(
                    'pending-group-invite-decline-${invite.groupId}',
                  ),
                  onPressed: isProcessing ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: readableColors.textSecondary,
                    disabledForegroundColor: readableColors.disabledForeground,
                    side: BorderSide(color: readableColors.inputBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(declineLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: ValueKey(
                    'pending-group-invite-accept-${invite.groupId}',
                  ),
                  onPressed: isProcessing || isExpired ? null : onAccept,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: isExpired
                        ? readableColors.disabledForeground
                        : onAction,
                    disabledForegroundColor: readableColors.disabledForeground,
                    backgroundColor: isExpired
                        ? readableColors.disabledSurface
                        : actionBlue,
                    disabledBackgroundColor: readableColors.disabledSurface,
                  ),
                  child: isProcessing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onAction,
                          ),
                        )
                      : Text(acceptLabel),
                ),
              ),
            ],
          ),
          if (rowState == PendingInviteRowState.waitingForKey) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: readableColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.group_invite_waiting_for_key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (rowState == PendingInviteRowState.retryable) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('pending-group-invite-retry-${invite.groupId}'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.btn_retry),
              ),
            ),
          ],
          if (rowReason != null) ...[
            const SizedBox(height: 8),
            Text(
              rowReason!,
              key: ValueKey(
                'pending-group-invite-outcome-reason-${invite.groupId}',
              ),
              style: TextStyle(
                fontSize: 13,
                color: readableColors.textSecondary,
              ),
            ),
          ],
          if (isExpired && onAskForNewInvite != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('pending-group-invite-ask-new-${invite.groupId}'),
                onPressed: onAskForNewInvite,
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(l10n.group_invite_ask_new),
              ),
            ),
          ] else if (isExpired && inviteContactUnavailable) ...[
            const SizedBox(height: 8),
            Text(
              l10n.group_invite_contact_unavailable,
              key: ValueKey(
                'pending-group-invite-contact-unavailable-${invite.groupId}',
              ),
              style: TextStyle(
                fontSize: 13,
                color: readableColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatExpiry(DateTime expiresAt, AppLocalizations l10n) {
    final local = expiresAt.toLocal();
    final formatted = intl.DateFormat.MMMd(
      l10n.localeName,
    ).add_jm().format(local);
    return l10n.pending_invite_expires(formatted);
  }
}

/// Compact feedback row for a terminal invite outcome whose repository row no
/// longer exists. The inviter snapshot is deliberately not trusted here; the
/// wired owner decides whether the optional ask action is available.
class PendingInviteOutcomeRow extends StatelessWidget {
  final String inviteId;
  final PendingInviteRowOutcome outcome;
  final VoidCallback? onAskForNewInvite;
  final bool inviteContactUnavailable;

  const PendingInviteOutcomeRow({
    super.key,
    required this.inviteId,
    required this.outcome,
    this.onAskForNewInvite,
    this.inviteContactUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
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
                if (onAskForNewInvite != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    key: ValueKey('pending-group-invite-ask-new-$inviteId'),
                    onPressed: onAskForNewInvite,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(l10n.group_invite_ask_new),
                  ),
                ] else if (inviteContactUnavailable) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.group_invite_contact_unavailable,
                    key: ValueKey(
                      'pending-group-invite-contact-unavailable-$inviteId',
                    ),
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
}
