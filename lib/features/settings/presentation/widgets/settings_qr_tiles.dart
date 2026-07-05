import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 209 — the My QR / Scan pair, re-hosted from the retired Orbit top chrome
/// onto the Settings page directly under the profile header.
///
/// Two large glass tiles with VISIBLE l10n labels (the orbit chrome was
/// icon-only with semantics-only labels) reusing the `orbit_my_qr` /
/// `orbit_scan` strings (INV-196-8). Unlike the chrome's pinned
/// `TextDirection.ltr`, the pair follows ambient directionality, so it mirrors
/// under RTL with the rest of the page. Hit targets stay well above 44px.
class SettingsQrTiles extends StatelessWidget {
  final VoidCallback onMyQr;
  final VoidCallback onScan;

  const SettingsQrTiles({
    super.key,
    required this.onMyQr,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _QrTile(
              tileKey: const ValueKey('settings-my-qr-tile'),
              icon: Icons.qr_code,
              label: l10n.orbit_my_qr,
              onTap: onMyQr,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QrTile(
              tileKey: const ValueKey('settings-scan-tile'),
              icon: Icons.camera_alt_outlined,
              label: l10n.orbit_scan,
              onTap: onScan,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrTile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QrTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: tileKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: readableColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: readableColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: readableColors.textPrimary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: readableColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
