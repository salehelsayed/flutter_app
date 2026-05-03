import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';

/// 36x36 glass circle search button for opening the search dock.
class OrbitSearchTrigger extends StatelessWidget {
  final VoidCallback onSearchTap;

  const OrbitSearchTrigger({super.key, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return GestureDetector(
      onTap: onSearchTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: readableColors.glassSurface,
              border: Border.all(color: readableColors.glassBorder),
            ),
            child: Icon(
              Icons.search,
              size: 22,
              color: readableColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
