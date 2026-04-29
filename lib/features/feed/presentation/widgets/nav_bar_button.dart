import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'nav_bar_theme.dart';

/// A single button in the bottom feed navigation bar.
class NavBarButton extends StatelessWidget {
  final String label;
  final String svgAsset;
  final bool isActive;
  final VoidCallback onTap;
  final int badgeCount;

  const NavBarButton({
    super.key,
    required this.label,
    required this.svgAsset,
    required this.isActive,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final isLightSurface = readableColors.isLightSurface;
    final iconColor = isLightSurface
        ? (isActive ? readableColors.iconPrimary : readableColors.iconMuted)
        : (isActive
              ? NavBarTheme.activeIconColor
              : NavBarTheme.inactiveIconColor);
    final textColor = isLightSurface
        ? (isActive ? readableColors.textPrimary : readableColors.textMuted)
        : (isActive
              ? NavBarTheme.activeTextColor
              : NavBarTheme.inactiveTextColor);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(NavBarTheme.buttonBorderRadius),
            child: AnimatedContainer(
              duration: NavBarTheme.animationDuration,
              curve: NavBarTheme.animationCurve,
              width: NavBarTheme.buttonWidth,
              padding: NavBarTheme.buttonPadding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  NavBarTheme.buttonBorderRadius,
                ),
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isLightSurface
                            ? [
                                readableColors.surfaceSubtle.withValues(
                                  alpha: 0.96,
                                ),
                                readableColors.surfaceRaised.withValues(
                                  alpha: 0.92,
                                ),
                              ]
                            : NavBarTheme.activePillGradient,
                      )
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    svgAsset,
                    width: NavBarTheme.iconSize,
                    height: NavBarTheme.iconSize,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  ),
                  const SizedBox(height: NavBarTheme.iconTextGap),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NavBarTheme.textSize,
                      fontWeight: isActive
                          ? NavBarTheme.activeWeight
                          : NavBarTheme.inactiveWeight,
                      color: textColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(top: -4, right: -2, child: _NavBadge(count: badgeCount)),
      ],
    );
  }
}

class _NavBadge extends StatelessWidget {
  final int count;

  const _NavBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(colors: NavBarTheme.badgeGradientColors),
        boxShadow: const [
          BoxShadow(
            color: NavBarTheme.badgeShadowColor,
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
