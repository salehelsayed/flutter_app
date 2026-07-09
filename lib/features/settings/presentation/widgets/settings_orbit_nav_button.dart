import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Settings-local Orbit affordance matching the Orbit search trigger's
/// 52px glass-circle vocabulary while preserving a square hit target.
class SettingsOrbitNavButton extends StatelessWidget {
  final VoidCallback onTap;

  const SettingsOrbitNavButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context)!.nav_orbit,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: readableColors.glassSurface,
                  border: Border.all(color: readableColors.glassBorder),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/nav_orbit.svg',
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      readableColors.iconPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
