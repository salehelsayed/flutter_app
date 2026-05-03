import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';

/// System message widget for introduction events in conversations.
///
/// Renders centered, muted bubble-style text for non-interactive events such as:
/// - "You were introduced to [name] by [introducer]"
/// - "You and [name] are now connected -- introduced by [introducer]"
/// - "[name] passed on the introduction"
class IntroSystemMessage extends StatelessWidget {
  final String text;

  const IntroSystemMessage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: readableColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: readableColors.divider),
        ),
        child: Text(
          text,
          textDirection: detectTextDirection(text),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: readableColors.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
