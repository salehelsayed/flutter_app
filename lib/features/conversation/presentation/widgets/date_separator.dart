import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// Date separator between letter cards spanning different days.
///
/// Shows gradient lines flanking an uppercase date label.
class DateSeparator extends StatelessWidget {
  final String label;

  const DateSeparator({
    super.key,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    // Translucent white is invisible on the light Signal canvas; dark keeps the
    // original literals byte-identical.
    final lineColor = isLightSurface
        ? readableColors.emptyDivider
        : const Color.fromRGBO(255, 255, 255, 0.12);
    final labelColor = isLightSurface
        ? readableColors.emptyDate
        : const Color.fromRGBO(255, 255, 255, 0.3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    lineColor,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: labelColor,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    lineColor,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
