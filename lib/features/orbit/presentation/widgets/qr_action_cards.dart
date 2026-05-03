import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Two side-by-side QR action cards at the bottom of the friends list.
class QRActionCards extends StatelessWidget {
  final VoidCallback onMyQR;
  final VoidCallback onScanQR;

  const QRActionCards({
    super.key,
    required this.onMyQR,
    required this.onScanQR,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.qr_code,
            title: l10n.qr_my_code,
            subtitle: l10n.orbit_qr_share,
            onTap: onMyQR,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionCard(
            icon: Icons.camera_alt_outlined,
            title: l10n.qr_scan_title,
            subtitle: l10n.orbit_qr_scan_desc,
            onTap: onScanQR,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final cardSurface = readableColors.isLightSurface
        ? const Color(0xFFE5F4EA)
        : const Color(0x141DB954);
    final cardBorder = readableColors.isLightSurface
        ? const Color(0xFF78B58D)
        : const Color(0x331DB954);
    final iconSurface = readableColors.isLightSurface
        ? const Color(0xFFD2EBDC)
        : const Color(0x331DB954);
    final accentColor = readableColors.isLightSurface
        ? const Color(0xFF157A39)
        : const Color(0xFF1DB954);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          color: cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cardBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: readableColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: readableColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
