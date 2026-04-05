import 'package:flutter/material.dart';

import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';

/// Card widget showing group name, type badge, last message preview,
/// unread count, and timestamp.
class GroupCard extends StatelessWidget {
  final GroupModel group;
  final String? lastMessageSender;
  final String? lastMessageBody;
  final String? lastMessagePreview;
  final String? lastMessageTime;
  final String? statusText;
  final int unreadCount;
  final VoidCallback? onTap;

  const GroupCard({
    super.key,
    required this.group,
    this.lastMessageSender,
    this.lastMessageBody,
    this.lastMessagePreview,
    this.lastMessageTime,
    this.statusText,
    this.unreadCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            GroupAvatar(
              groupId: group.id,
              name: group.name,
              avatarPath: group.avatarPath,
              cacheBustKey: group.lastMetadataEventAt?.toIso8601String(),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: name + badge + time
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            GroupTypeBadge(type: group.type),
                            if (group.isDissolved) ...[
                              const SizedBox(width: 6),
                              const GroupDissolvedBadge(dense: true),
                            ],
                          ],
                        ),
                      ),
                      if (lastMessageTime != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            lastMessageTime!,
                            style: TextStyle(
                              fontSize: 12,
                              color: unreadCount > 0
                                  ? const Color(0xFF64B5F6)
                                  : Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Bottom row: preview + unread
                  Row(
                    children: [
                      Expanded(child: _buildPreviewText()),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF64B5F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewText() {
    final sender = lastMessageSender;
    final body = lastMessageBody;
    final status = statusText;

    if (status != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE6C36A),
            ),
            textDirection: detectTextDirection(status),
          ),
          if (sender != null || body != null) const SizedBox(height: 2),
          if (sender != null)
            Text(
              sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.6),
              ),
              textDirection: detectTextDirection(sender),
            ),
          if (body != null)
            Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.45),
              ),
              textDirection: detectTextDirection(body),
            ),
        ],
      );
    }

    if (sender != null || body != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Text(
              sender,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.6),
              ),
              textDirection: detectTextDirection(sender),
            ),
          if (body != null)
            Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.45),
              ),
              textDirection: detectTextDirection(body),
            ),
        ],
      );
    }

    return Text(
      lastMessagePreview ??
          (group.isDissolved ? 'Group dissolved' : 'No messages yet'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.45)),
    );
  }
}
