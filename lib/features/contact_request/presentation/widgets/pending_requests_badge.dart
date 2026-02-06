import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Badge widget showing the count of pending contact requests.
///
/// Displays a small circular badge with the count number.
/// Hides when count is 0.
class PendingRequestsBadge extends StatelessWidget {
  final int count;
  final double size;

  const PendingRequestsBadge({
    super.key,
    required this.count,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: count > 99 ? 8 : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
