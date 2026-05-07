import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
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
  final bool isProcessing;
  final VoidCallback? onAccept;
  final VoidCallback? onPass;
  final IntroductionStatus? ownPartyStatus;
  final String? waitingForUsername;
  final VoidCallback? onSendMessage;
  final bool isOtherBlocked;
  final List<String>? introducerAttributionNames;

  const IntroRow({
    super.key,
    required this.introduction,
    required this.displayUsername,
    this.displayPeerId,
    this.introducerAttributionNames,
    required this.showActions,
    this.isProcessing = false,
    this.onAccept,
    this.onPass,
    this.ownPartyStatus,
    this.waitingForUsername,
    this.onSendMessage,
    this.isOtherBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final successColor = readableColors.isLightSurface
        ? const Color(0xFF157A39)
        : const Color(0xFF1DB954);
    final onSuccessColor = readableColors.isLightSurface
        ? Colors.white
        : Colors.black;
    final providedAttributionNames = introducerAttributionNames
        ?.map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final introducerUsername =
        providedAttributionNames != null && providedAttributionNames.isNotEmpty
        ? providedAttributionNames.join(', ')
        : introduction.introducerUsername ?? 'someone';
    final attributionStyle = TextStyle(
      fontSize: 12,
      color: readableColors.textMuted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: readableColors.border),
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: readableColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('Introduced by', style: attributionStyle),
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
                  buttonKey: ValueKey('intro-pass-${introduction.id}'),
                  label: 'Pass',
                  onTap: isProcessing ? null : onPass,
                  isPrimary: false,
                ),
                const SizedBox(width: 8),
                // Accept button
                _ActionButton(
                  buttonKey: ValueKey('intro-accept-${introduction.id}'),
                  label: isProcessing ? 'Accepting...' : 'Accept',
                  onTap: isProcessing ? null : onAccept,
                  isPrimary: true,
                  isProcessing: isProcessing,
                ),
              ],
            )
          else if (showActions && isOtherBlocked)
            Text(
              'Unavailable',
              style: TextStyle(fontSize: 11, color: readableColors.textMuted),
            )
          else if (introduction.status ==
              IntroductionOverallStatus.mutualAccepted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusLabel(status: introduction.status),
                if (onSendMessage != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onSendMessage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: successColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onSuccessColor,
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
              style: TextStyle(fontSize: 11, color: readableColors.textMuted),
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
  final Key? buttonKey;
  final bool isPrimary;
  final bool isProcessing;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    this.buttonKey,
    required this.isPrimary,
    required this.onTap,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final foregroundColor = readableColors.isLightSurface
        ? Colors.white
        : Colors.black;
    final primaryColor = readableColors.isLightSurface
        ? const Color(0xFF157A39)
        : const Color(0xFF1DB954);

    final child = isProcessing && isPrimary
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          )
        : Text(label);

    if (isPrimary) {
      return FilledButton(
        key: buttonKey,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          backgroundColor: primaryColor,
          foregroundColor: foregroundColor,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      key: buttonKey,
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        foregroundColor: readableColors.textSecondary,
        disabledForegroundColor: readableColors.disabledForeground,
        side: BorderSide(color: readableColors.inputBorder),
        backgroundColor: readableColors.surfaceRaised,
        disabledBackgroundColor: readableColors.disabledSurface,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: child,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final IntroductionOverallStatus status;

  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final successColor = readableColors.isLightSurface
        ? const Color(0xFF157A39)
        : const Color(0xFF1DB954);
    final String label;
    final Color color;

    switch (status) {
      case IntroductionOverallStatus.mutualAccepted:
        label = 'Connected';
        color = successColor;
      case IntroductionOverallStatus.passed:
        label = 'Passed';
        color = readableColors.textMuted;
      case IntroductionOverallStatus.expired:
        label = 'Expired';
        color = readableColors.textMuted;
      case IntroductionOverallStatus.pending:
        label = 'Pending';
        color = readableColors.textSecondary;
      case IntroductionOverallStatus.alreadyConnected:
        label = 'Already connected';
        color = successColor;
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
