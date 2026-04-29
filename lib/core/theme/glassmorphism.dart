import 'dart:ui';
import 'package:flutter/material.dart';
import 'background_readable_colors.dart';
import 'app_colors.dart';

/// A container with glassmorphic effect using backdrop blur.
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.blurSigma = 10.0,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final readableColors = Theme.of(
      context,
    ).extension<BackgroundReadableColors>();
    final useReadableRoles = readableColors?.isLightSurface ?? false;
    final surfaceColor = useReadableRoles
        ? readableColors!.glassSurface
        : AppColors.glassBackground;
    final borderColor = useReadableRoles
        ? readableColors!.glassBorder
        : AppColors.glassBorder;

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
