import 'package:flutter/material.dart';

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
    final isExpired = invite.isExpiredAt(DateTime.now().toUtc());
    final acceptLabel = isExpired ? 'Expired' : 'Accept';
    final declineLabel = isExpired ? 'Dismiss' : 'Decline';

    return Container(
      key: ValueKey('pending-group-invite-${invite.groupId}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpired ? const Color(0x26FF8A80) : const Color(0x1FFFFFFF),
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
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Invited by ${invite.senderUsername}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.6),
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
                      color: isExpired
                          ? const Color(0xFFFF8A80)
                          : Colors.white.withOpacity(0.45),
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
                color: Colors.white.withOpacity(0.58),
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
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.16)),
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
                    backgroundColor: isExpired
                        ? Colors.white24
                        : const Color(0xFF64B5F6),
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
