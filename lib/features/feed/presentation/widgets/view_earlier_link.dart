import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

/// Tappable "View earlier messages" link for feed cards.
class ViewEarlierLink extends StatelessWidget {
  final VoidCallback? onTap;

  const ViewEarlierLink({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'View earlier messages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: FeedColors.viewEarlierText,
            ),
          ),
        ),
      ),
    );
  }
}
