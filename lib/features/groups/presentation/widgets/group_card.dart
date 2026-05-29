import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_dissolved_badge.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    final readableColors = context.backgroundReadableColors;
    final unreadAccent = _blueAccent(readableColors);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: readableColors.divider, width: 0.5),
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
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: readableColors.textPrimary,
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
                                  ? unreadAccent
                                  : readableColors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Bottom row: preview + unread
                  Row(
                    children: [
                      Expanded(child: _buildPreviewText(context)),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: unreadAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: readableColors.isLightSurface
                                  ? Colors.white
                                  : Colors.black,
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

  Widget _buildPreviewText(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final sender = lastMessageSender;
    final body = lastMessageBody;
    final status = statusText;
    final statusColor = readableColors.isLightSurface
        ? const Color(0xFF8A4A00)
        : const Color(0xFFE6C36A);

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
            ).copyWith(color: statusColor),
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
                color: readableColors.textSecondary,
              ),
              textDirection: detectTextDirection(sender),
            ),
          if (body != null)
            Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: readableColors.textMuted),
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
                color: readableColors.textSecondary,
              ),
              textDirection: detectTextDirection(sender),
            ),
          if (body != null)
            Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: readableColors.textMuted),
              textDirection: detectTextDirection(body),
            ),
        ],
      );
    }

    return Text(
      lastMessagePreview ??
          (group.isDissolved
              ? AppLocalizations.of(context)!.group_dissolved
              : AppLocalizations.of(context)!.group_card_no_messages),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: readableColors.textMuted),
    );
  }

  Color _blueAccent(BackgroundReadableColors readableColors) {
    return readableColors.isLightSurface
        ? const Color(0xFF0F5F9C)
        : const Color(0xFF64B5F6);
  }
}
