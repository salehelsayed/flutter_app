import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// "Close Friends" list title.
///
/// 196: the My QR / Scan entries moved to the Orbit top chrome
/// ([OrbitQrChromeButtons]), so this header is now title-only.
class FriendsListHeader extends StatelessWidget {
  const FriendsListHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context)!.orbit_close_friends,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: readableColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
