import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
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

  const GroupRow({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final rejoinAttempt = group.rejoinAttemptCount;
    String? joinStatusLabel;
    if (rejoinAttempt != null) {
      joinStatusLabel = rejoinAttempt >= _joinGiveUpThreshold
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
    final latestMessageText = group.latestMessageText ?? group.latestMessage;
    final hasStructuredPreview = latestMessageText != null;

    return GestureDetector(
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
                            latestMessageText,
                            style: TextStyle(
                              fontSize: 12,
                              color: readableColors.textMuted,
                            ),
                            textDirection: detectTextDirection(
                              latestMessageText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      latestMessageText ?? 'No messages yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: readableColors.textMuted,
                      ),
                      textDirection: latestMessageText != null
                          ? detectTextDirection(latestMessageText)
                          : null,
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
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    if (words.length == 1) return words[0][0].toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}
