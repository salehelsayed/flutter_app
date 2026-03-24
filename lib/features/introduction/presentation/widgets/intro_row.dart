import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';

/// A single introduction row displayed in the Intros tab.
///
/// Shows the introduced person's avatar, username, introducer attribution,
/// and either Accept/Pass action buttons (pending) or a status label (responded).
class IntroRow extends StatelessWidget {
  final IntroductionModel introduction;
  final String displayUsername;
  final String? displayPeerId;
  final bool showActions;
  final VoidCallback? onAccept;
  final VoidCallback? onPass;
  final IntroductionStatus? ownPartyStatus;
  final String? waitingForUsername;
  final VoidCallback? onSendMessage;
  final bool isOtherBlocked;

  const IntroRow({
    super.key,
    required this.introduction,
    required this.displayUsername,
    this.displayPeerId,
    required this.showActions,
    this.onAccept,
    this.onPass,
    this.ownPartyStatus,
    this.waitingForUsername,
    this.onSendMessage,
    this.isOtherBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final introducerUsername = introduction.introducerUsername ?? 'someone';
    const attributionStyle = TextStyle(
      fontSize: 12,
      color: Color(0x66FFFFFF),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          // Avatar
          UserAvatar(peerId: displayPeerId, size: 42),
          const SizedBox(width: 12),

          // Info column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayUsername,
                  textDirection: detectTextDirection(displayUsername),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xF2FFFFFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Text(
                      'Introduced by',
                      style: attributionStyle,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        introducerUsername,
                        textDirection: detectTextDirection(introducerUsername),
                        style: attributionStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Actions or status
          if (showActions && !isOtherBlocked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pass button
                _ActionButton(
                  label: 'Pass',
                  onTap: onPass,
                  backgroundColor: const Color(0x14FFFFFF),
                  textColor: const Color(0x99FFFFFF),
                ),
                const SizedBox(width: 8),
                // Accept button
                _ActionButton(
                  label: 'Accept',
                  onTap: onAccept,
                  backgroundColor: const Color(0xFF1DB954),
                  textColor: Colors.black,
                ),
              ],
            )
          else if (showActions && isOtherBlocked)
            const Text(
              'Unavailable',
              style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF)),
            )
          else if (introduction.status == IntroductionOverallStatus.mutualAccepted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusLabel(status: introduction.status),
                if (onSendMessage != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onSendMessage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1DB954),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else if (ownPartyStatus == IntroductionStatus.accepted &&
                   introduction.status == IntroductionOverallStatus.pending)
            Text(
              'Waiting for ${waitingForUsername ?? 'them'}',
              style: const TextStyle(fontSize: 11, color: Color(0x66FFFFFF)),
            )
          else
            _StatusLabel(status: introduction.status),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color textColor;

  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final IntroductionOverallStatus status;

  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    switch (status) {
      case IntroductionOverallStatus.mutualAccepted:
        label = 'Connected';
        color = const Color(0xFF1DB954);
      case IntroductionOverallStatus.passed:
        label = 'Passed';
        color = const Color(0x66FFFFFF);
      case IntroductionOverallStatus.expired:
        label = 'Expired';
        color = const Color(0x66FFFFFF);
      case IntroductionOverallStatus.pending:
        label = 'Pending';
        color = const Color(0x99FFFFFF);
      case IntroductionOverallStatus.alreadyConnected:
        label = 'Already connected';
        color = const Color(0xFF1DB954);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
