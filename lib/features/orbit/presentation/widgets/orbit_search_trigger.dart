import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 52x52 glass circle search button for opening the search dock (212: full
/// glass-chrome vocabulary — border + blur + soft drop shadow — with a
/// Semantics button label and an opaque hit square so the corners of the
/// circle still tap).
class OrbitSearchTrigger extends StatelessWidget {
  final VoidCallback onSearchTap;

  const OrbitSearchTrigger({super.key, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context)!.orbit_search_trigger_semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSearchTap,
        child: Container(
          width: 52,
          height: 52,
          // Shadow lives OUTSIDE the ClipOval — a clipped shadow is invisible.
          // Neutral black reads on both background tones.
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
                child: Icon(
                  Icons.search,
                  size: 24,
                  color: readableColors.iconPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
