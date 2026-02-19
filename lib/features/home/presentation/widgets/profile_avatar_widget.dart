import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'ring_avatar.dart';

/// Profile avatar with ring avatar default and camera button.
///
/// When [avatarBytes] is provided, displays the user's photo from memory.
/// When [avatarBytes] is null but [peerId] is provided, displays
/// a unique ring avatar generated from the peerId.
class ProfileAvatarWidget extends StatelessWidget {
  /// Raw image bytes for the user's avatar (stored in encrypted DB).
  final Uint8List? avatarBytes;

  /// The user's peer ID for generating the default ring avatar.
  final String? peerId;

  /// Callback when the camera button is pressed.
  final VoidCallback? onCameraPressed;

  /// Size of the avatar in logical pixels.
  final double size;

  const ProfileAvatarWidget({
    super.key,
    this.avatarBytes,
    this.peerId,
    this.onCameraPressed,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Avatar content
          _buildAvatar(),
          // Camera button
          if (onCameraPressed != null) _buildCameraButton(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    // Priority 1: User's photo
    if (avatarBytes != null) {
      return _buildImageAvatar();
    }

    // Priority 2: Ring avatar from peerId
    if (peerId != null) {
      return RingAvatar(peerId: peerId!, size: size);
    }

    // Priority 3: Placeholder (edge case)
    return _buildPlaceholder();
  }

  Widget _buildImageAvatar() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
      ),
      child: ClipOval(
        child: Image.memory(
          avatarBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
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
    );
  }

  Widget _buildCameraButton() {
    final buttonSize = size * 0.35;
    final iconSize = size * 0.175;

    return Positioned(
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: onCameraPressed,
        child: Container(
          width: buttonSize,
          height: buttonSize,
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
          child: Icon(
            Icons.camera_alt,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}
