import 'dart:ui';
import 'package:flutter/material.dart';
import 'nav_bar_button.dart';
import 'nav_bar_theme.dart';

/// Bottom glass navigation bar for the feed area.
class FeedNavigationBar extends StatelessWidget {
  final String activeTab;
  final void Function(String) onSwitchView;
  final int feedBadgeCount;

  const FeedNavigationBar({
    super.key,
    required this.activeTab,
    required this.onSwitchView,
    this.feedBadgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(NavBarTheme.barBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: NavBarTheme.blurSigma,
          sigmaY: NavBarTheme.blurSigma,
        ),
        child: Container(
          padding: NavBarTheme.barPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NavBarTheme.barBorderRadius),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: NavBarTheme.barGradientColors,
            ),
            border: Border.all(color: NavBarTheme.barBorderColor),
            boxShadow: const [
              BoxShadow(
                color: NavBarTheme.barShadowColor,
                blurRadius: NavBarTheme.barShadowBlur,
                offset: NavBarTheme.barShadowOffset,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NavBarButton(
                label: 'Feed',
                svgAsset: 'assets/icons/nav_feed.svg',
                isActive: activeTab == 'feed',
                onTap: () => onSwitchView('feed'),
                badgeCount: feedBadgeCount,
              ),
              const SizedBox(width: NavBarTheme.buttonSpacing),
              NavBarButton(
                label: 'Remember',
                svgAsset: 'assets/icons/nav_remember.svg',
                isActive: activeTab == 'remember',
                onTap: () => onSwitchView('remember'),
              ),
              const SizedBox(width: NavBarTheme.buttonSpacing),
              NavBarButton(
                label: 'Orbit',
                svgAsset: 'assets/icons/nav_orbit.svg',
                isActive: activeTab == 'orbit',
                onTap: () => onSwitchView('orbit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
