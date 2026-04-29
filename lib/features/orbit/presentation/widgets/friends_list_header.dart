import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// "Friends" title with My QR / Scan pill buttons.
///
/// Pill buttons are hidden during search (only title visible).
class FriendsListHeader extends StatelessWidget {
  final VoidCallback onMyQR;
  final VoidCallback onScanQR;
  final bool searchActive;

  const FriendsListHeader({
    super.key,
    required this.onMyQR,
    required this.onScanQR,
    required this.searchActive,
  });

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
          const Spacer(),
          if (!searchActive) ...[
            _PillButton(
              label: AppLocalizations.of(context)!.orbit_my_qr,
              icon: Icons.qr_code,
              onTap: onMyQR,
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: AppLocalizations.of(context)!.orbit_scan,
              icon: Icons.camera_alt_outlined,
              onTap: onScanQR,
            ),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    const accentColor = Color(0xFF157A39);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: readableColors.isLightSurface
              ? const Color(0xFFE5F4EA)
              : const Color(0x261DB954),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: readableColors.isLightSurface
                ? const Color(0xFF78B58D)
                : const Color(0x4D1DB954),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
