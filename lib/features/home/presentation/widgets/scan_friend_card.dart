import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/glassmorphism.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Glassmorphic card for scanning a friend's QR code.
class ScanFriendCard extends StatefulWidget {
  final VoidCallback? onTap;

  const ScanFriendCard({super.key, this.onTap});

  @override
  State<ScanFriendCard> createState() => _ScanFriendCardState();
}

class _ScanFriendCardState extends State<ScanFriendCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.985).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final screenHeight = MediaQuery.of(context).size.height;
    final t = ((screenHeight - 650) / 250).clamp(0.0, 1.0);
    final padding = lerpDouble(10, 16, t)!;
    final iconContainer = lerpDouble(40, 48, t)!;
    final iconSize = lerpDouble(20, 24, t)!;
    final titleFont = lerpDouble(14, 16, t)!;
    final subtitleFont = lerpDouble(11.5, 13, t)!;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: GlassmorphicContainer(
          blurSigma: 6.0,
          padding: EdgeInsets.all(padding),
          child: Row(
            children: [
              // Green icon container
              Container(
                width: iconContainer,
                height: iconContainer,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.primaryAccent.withValues(alpha: 0.15),
                ),
                child: Icon(
                  Icons.crop_free,
                  color: AppColors.primaryAccent,
                  size: iconSize,
                ),
              ),
              const SizedBox(width: 16),
              // Title and subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.home_scan_friend_title,
                      style: TextStyle(
                        color: readableColors.textPrimary,
                        fontSize: titleFont,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.home_scan_friend_desc,
                      style: TextStyle(
                        color: readableColors.textSecondary,
                        fontSize: subtitleFont,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                color: readableColors.iconSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
