import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
    final iconColor = isActive
        ? Colors.white
        : const Color.fromRGBO(255, 255, 255, 0.55);
    final textColor = isActive
        ? Colors.white
        : const Color.fromRGBO(255, 255, 255, 0.5);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(19),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 78,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                gradient: isActive
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(255, 255, 255, 0.28),
                          Color.fromRGBO(255, 255, 255, 0.11),
                        ],
                      )
                    : null,
                border: isActive
                    ? Border.all(
                        color: const Color.fromRGBO(255, 255, 255, 0.24))
                    : null,
                boxShadow: isActive
                    ? const [
                        BoxShadow(
                          color: Color.fromRGBO(255, 255, 255, 0.1),
                          blurRadius: 10,
                        ),
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.3),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    svgAsset,
                    width: 20,
                    height: 20,
                    colorFilter:
                        ColorFilter.mode(iconColor, BlendMode.srcIn),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.w500,
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
          Positioned(
            top: -4,
            right: -2,
            child: _NavBadge(count: badgeCount),
          ),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF1DB954), Color(0xFF18A349)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x661DB954),
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
