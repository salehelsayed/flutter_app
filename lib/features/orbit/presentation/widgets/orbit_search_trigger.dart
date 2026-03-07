import 'dart:ui';
import 'package:flutter/material.dart';

/// 36x36 glass circle search button for opening the search dock.
class OrbitSearchTrigger extends StatelessWidget {
  final VoidCallback onSearchTap;

  const OrbitSearchTrigger({
    super.key,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSearchTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
              border: Border.all(
                color: const Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
              ),
            ),
            child: Icon(
              Icons.search,
              size: 20,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
