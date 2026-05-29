import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Section header for a group of introductions from the same introducer.
///
/// Displays "From [username]" in muted style with small font and padding.
class IntroGroupHeader extends StatelessWidget {
  final String introducerUsername;

  const IntroGroupHeader({super.key, required this.introducerUsername});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: readableColors.textSecondary,
    );

    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
      child: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.intro_from, style: style),
          Text(
            introducerUsername,
            textDirection: detectTextDirection(introducerUsername),
            style: style,
          ),
        ],
      ),
    );
  }
}
