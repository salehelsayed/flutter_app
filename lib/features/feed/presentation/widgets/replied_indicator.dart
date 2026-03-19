import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// "You replied [relative time]" indicator with reply arrow icon.
///
/// Extracted from ThreadCard._buildReplyIndicator() for reuse
/// in both FeedCard and CollapsedModeCardBody.
class RepliedIndicator extends StatelessWidget {
  final DateTime repliedAt;

  const RepliedIndicator({super.key, required this.repliedAt});

  @override
  Widget build(BuildContext context) {
    final relativeTime = formatRelativeTime(repliedAt.toIso8601String());

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.reply_rounded,
          size: 12,
          color: FeedColors.accentTeal.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 3),
        Text(
          AppLocalizations.of(context)!.feed_you_replied(relativeTime),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: FeedColors.accentTeal.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}
