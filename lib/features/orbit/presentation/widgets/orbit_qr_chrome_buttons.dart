import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 196 — twin "My QR" / "Scan" chrome circle buttons at top-center of the Orbit
/// screen, mounted on BOTH the Inner-Circle and the all-chats surfaces (Layer 1c
/// in [OrbitScreen]'s body Stack, immediately after the view toggle and BEFORE
/// the create-group [ExpandableFab] so an open FAB scrim wins the tap).
///
/// Toggle-species chrome — identical tokens to [OrbitViewToggleButton]: a 40×40
/// circle with a `surfaceSubtle` fill, a 0.5 hairline `border`, and a 20px
/// `textPrimary` glyph. Icon-only, with l10n-sourced button [Semantics].
///
/// Physical (non-mirroring) centered placement: the [Row] is pinned to
/// [TextDirection.ltr] so "My QR" always sits physically left of "Scan" under
/// both LTR and RTL — the same physical-placement rationale as the top-left
/// toggle and the top-right FAB (neither mirrors), which keeps the pair centered
/// and clear of both. The full-width band stays tap-transparent outside the two
/// buttons (only the buttons themselves are opaque hit targets).
class OrbitQrChromeButtons extends StatelessWidget {
  final VoidCallback onMyQR;
  final VoidCallback onScanQR;

  const OrbitQrChromeButtons({
    super.key,
    required this.onMyQR,
    required this.onScanQR,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ChromeButton(
            buttonKey: const ValueKey('orbit-my-qr-button'),
            icon: Icons.qr_code,
            label: l10n.orbit_my_qr,
            onTap: onMyQR,
          ),
          const SizedBox(width: 8),
          _ChromeButton(
            buttonKey: const ValueKey('orbit-scan-button'),
            icon: Icons.camera_alt_outlined,
            label: l10n.orbit_scan,
            onTap: onScanQR,
          ),
        ],
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ChromeButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: buttonKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: readableColors.surfaceSubtle,
            shape: BoxShape.circle,
            border: Border.all(color: readableColors.border, width: 0.5),
          ),
          child: Icon(icon, size: 20, color: readableColors.textPrimary),
        ),
      ),
    );
  }
}
