import 'dart:ui';
import 'package:flutter/material.dart';
import 'nav_bar_button.dart';

/// Bottom glass navigation bar for the feed area.
class FeedNavigationBar extends StatelessWidget {
  final String activeTab;
  final void Function(String) onSwitchView;

  const FeedNavigationBar({
    super.key,
    required this.activeTab,
    required this.onSwitchView,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 285),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.fromRGBO(43, 47, 57, 0.78),
                  Color.fromRGBO(22, 25, 32, 0.86),
                ],
              ),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.1),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.38),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NavBarButton(
                  label: 'Feed',
                  svgAsset: 'assets/icons/nav_feed.svg',
                  isActive: activeTab == 'feed',
                  onTap: () => onSwitchView('feed'),
                ),
                const SizedBox(width: 7),
                NavBarButton(
                  label: 'Remember',
                  svgAsset: 'assets/icons/nav_remember.svg',
                  isActive: activeTab == 'remember',
                  onTap: () => onSwitchView('remember'),
                ),
                const SizedBox(width: 7),
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
      ),
    );
  }
}
