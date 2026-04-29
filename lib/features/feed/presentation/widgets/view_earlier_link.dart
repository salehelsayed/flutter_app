import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Tappable "View earlier messages" link for feed cards.
class ViewEarlierLink extends StatelessWidget {
  final VoidCallback? onTap;

  const ViewEarlierLink({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final textColor = readableColors.isLightSurface
        ? readableColors.textMuted
        : FeedColors.viewEarlierText;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'View earlier messages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
