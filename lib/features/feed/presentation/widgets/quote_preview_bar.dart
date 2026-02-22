import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Compose preview bar shown above the expanded input when quoting a message.
///
/// Teal vertical accent bar + "Replying to" label + quoted text snippet + close button.
class QuotePreviewBar extends StatelessWidget {
  final String text;
  final VoidCallback? onDismiss;

  const QuotePreviewBar({
    super.key,
    required this.text,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Teal vertical accent bar
          Container(
            width: 2,
            height: 36,
            decoration: BoxDecoration(
              color: FeedColors.accentTeal.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          // Label + quoted text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: FeedColors.accentTeal.withValues(alpha: 0.60),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color.fromRGBO(255, 255, 255, 0.50),
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
