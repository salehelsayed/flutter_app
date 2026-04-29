import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';

class PendingGroupInviteCard extends StatelessWidget {
  final PendingGroupInvite invite;
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const PendingGroupInviteCard({
    super.key,
    required this.invite,
    required this.isProcessing,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isExpired = invite.isExpiredAt(DateTime.now().toUtc());
    final acceptLabel = isExpired ? 'Expired' : 'Accept';
    final declineLabel = isExpired ? 'Dismiss' : 'Decline';
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
                      'Invited by ${invite.senderUsername}',
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
                    isExpired ? 'Expired' : _formatExpiry(invite.expiresAt),
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
        ],
      ),
    );
  }

  String _formatExpiry(DateTime expiresAt) {
    final local = expiresAt.toLocal();
    final month = _monthName(local.month);
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return 'Expires $month $day, $hour:$minute $period';
  }

  String _monthName(int month) {
    const names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}
