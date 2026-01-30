import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

/// Profile avatar with gradient background and camera button.
class ProfileAvatarWidget extends StatelessWidget {
  final VoidCallback? onCameraPressed;

  const ProfileAvatarWidget({
    super.key,
    this.onCameraPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          // Avatar circle with gradient
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryAccent.withValues(alpha: 0.3),
                  AppColors.redGlow.withValues(alpha: 0.2),
                ],
              ),
              border: Border.all(
                color: Colors.white,
                width: 3,
              ),
            ),
            child: const Center(
              child: Text(
                '?',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          // Camera button
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: onCameraPressed,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryAccent,
                      AppColors.secondaryAccent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryAccent.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
