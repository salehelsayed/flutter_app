import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/presentation/widgets/unread_count_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';

/// Glassmorphic tappable group card for the orbit list.
///
/// Parallels [FriendRow] in visual style but displays group-specific info
/// (group name, type badge, latest message preview).
class GroupRow extends StatelessWidget {
  final OrbitGroup group;
  final VoidCallback onTap;

  const GroupRow({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final relativeTime = group.lastActivityTimestamp != null
        ? formatRelativeTime(
            group.lastActivityTimestamp!.toUtc().toIso8601String())
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
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0x1FFFFFFF),
          ),
        ),
        child: Row(
          children: [
            // Group avatar placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  _initials(group.name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0x99FFFFFF),
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
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xF2FFFFFF),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GroupTypeBadge(type: group.type),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (hasStructuredPreview)
                    Row(
                      children: [
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            senderDisplayName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0x99FFFFFF),
                            ),
                            textDirection: detectTextDirection(
                              senderDisplayName,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Text(
                          ': ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0x99FFFFFF),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            latestMessageText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0x99FFFFFF),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0x99FFFFFF),
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
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0x66FFFFFF),
                    ),
                  ),
                const SizedBox(height: 4),
                if (group.unreadCount > 0)
                  UnreadCountBadge(count: group.unreadCount)
                else
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Color(0x66FFFFFF),
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
