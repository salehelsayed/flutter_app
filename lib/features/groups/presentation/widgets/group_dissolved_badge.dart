import 'package:flutter/material.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';

class GroupDissolvedBadge extends StatelessWidget {
  final bool dense;

  const GroupDissolvedBadge({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final danger = readableColors.isLightSurface
        ? const Color(0xFF9D1C12)
        : const Color(0xFFFFB3AD);

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: danger.withOpacity(readableColors.isLightSurface ? 0.10 : 0.20),
        borderRadius: BorderRadius.circular(dense ? 10 : 12),
        border: Border.all(
          color: danger.withOpacity(
            readableColors.isLightSurface ? 0.28 : 0.40,
          ),
          width: 0.5,
        ),
      ),
      child: Text(
        'Dissolved',
        style: TextStyle(
          fontSize: dense ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: danger,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
