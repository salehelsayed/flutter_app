import 'package:flutter/material.dart';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context)!.orbit_close_friends,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xF2FFFFFF), // rgba(255,255,255,0.95)
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x261DB954), // rgba(29,185,84,0.15)
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0x4D1DB954), // rgba(29,185,84,0.3)
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF1DB954)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1DB954),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
