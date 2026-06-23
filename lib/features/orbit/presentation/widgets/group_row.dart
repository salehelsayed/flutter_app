import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Glassmorphic tappable group card for the orbit list.
///
/// Parallels [FriendRow] in visual style but displays group-specific info
/// (group name, type badge, latest message preview).
class GroupRow extends StatelessWidget {
  /// Mirrors the rejoin use-case's attempt cap; at/above it the bounded
  /// retrier has given up and the row shows a manual-retry prompt.
  static const int _joinGiveUpThreshold = 10;

  final OrbitGroup group;
  final VoidCallback onTap;

  /// Invoked when the user taps "Retry now" on a group whose rejoin has given
  /// up (attempt ≥ [_joinGiveUpThreshold]) — force-eligible + fresh rejoin (G2).
  final VoidCallback? onRetryStuckRejoin;

  /// Invoked when the user taps "Leave" on a stuck group — a reachable exit
  /// from the dead-end (G2). Never auto-deletes.
  final VoidCallback? onLeaveStuckGroup;

  const GroupRow({
    super.key,
    required this.group,
    required this.onTap,
    this.onRetryStuckRejoin,
    this.onLeaveStuckGroup,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final rejoinAttempt = group.rejoinAttemptCount;
    final isStuck =
        rejoinAttempt != null && rejoinAttempt >= _joinGiveUpThreshold;
    String? joinStatusLabel;
    if (rejoinAttempt != null) {
      joinStatusLabel = isStuck
          ? l10n.group_join_failed_retry
          : l10n.group_joining_in_progress;
    }
    final relativeTime = group.lastActivityTimestamp != null
        ? formatRelativeTime(
            group.lastActivityTimestamp!.toUtc().toIso8601String(),
          )
        : '';
    final senderUsername = group.latestMessageSenderUsername;
    final senderDisplayName = senderUsername ?? 'Unknown';
    final rawLatestText = group.latestMessageText ?? group.latestMessage;
    // Caption wins; else a localized media label ("Photo"/"2 photos"/"Voice
    // message"). Empty-but-present text on a media-only message no longer
    // renders "Sender: " then a blank body.
    final previewText = orbitMediaPreviewLabel(
      l10n: l10n,
      caption: rawLatestText,
      media: group.latestMedia,
    );
    final hasStructuredPreview = previewText.isNotEmpty;

    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: readableColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: readableColors.border),
        ),
        child: Row(
          children: [
            // Group avatar placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: readableColors.disabledSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _initials(group.name),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: readableColors.iconMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: readableColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GroupTypeBadge(type: group.type),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (joinStatusLabel != null)
                    Text(
                      joinStatusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: readableColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (hasStructuredPreview)
                    Row(
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            senderDisplayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: readableColors.textMuted,
                            ),
                            textDirection: detectTextDirection(
                              senderDisplayName,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          ': ',
                          style: TextStyle(
                            fontSize: 12,
                            color: readableColors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            previewText,
                            style: TextStyle(
                              fontSize: 12,
                              color: readableColors.textMuted,
                            ),
                            textDirection: detectTextDirection(previewText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      l10n.group_no_messages,
                      style: TextStyle(
                        fontSize: 12,
                        color: readableColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Meta column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (relativeTime.isNotEmpty)
                  Text(
                    relativeTime,
                    style: TextStyle(
                      fontSize: 12,
                      color: readableColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 4),
                if (group.unreadCount > 0)
                  UnreadCountBadge(count: group.unreadCount)
                else
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: readableColors.iconMuted,
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    // The give-up badge is a dead-end without an action: surface a manual
    // "Retry now" (force-eligible + rejoin) and a "Leave" exit (G2).
    if (isStuck && (onRetryStuckRejoin != null || onLeaveStuckGroup != null)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [card, _buildStuckActions(context)],
      );
    }

    return card;
  }

  Widget _buildStuckActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dangerColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onRetryStuckRejoin != null)
            TextButton.icon(
              key: ValueKey('orbit-group-stuck-retry-${group.groupId}'),
              onPressed: onRetryStuckRejoin,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.btn_retry),
            ),
          if (onLeaveStuckGroup != null)
            TextButton.icon(
              key: ValueKey('orbit-group-stuck-leave-${group.groupId}'),
              onPressed: onLeaveStuckGroup,
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

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    if (words.length == 1) return words[0][0].toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}
