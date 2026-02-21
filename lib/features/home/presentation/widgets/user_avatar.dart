import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar.dart';

/// Unified avatar widget used across all screens.
///
/// Priority: avatarBytes (in-memory) → file on disk → RingAvatar → fallback icon.
///
/// For the user's own avatar, callers pass [avatarBytes] (loaded by wired layer).
/// For contacts, the widget auto-checks `{documentsDir}/media/avatars/{peerId}.jpg`.
class UserAvatar extends StatelessWidget {
  /// Set once at app startup via [setDocumentsDir].
  static String? _documentsDir;

  /// Call once from main() with `getApplicationDocumentsDirectory().path`.
  static void setDocumentsDir(String path) => _documentsDir = path;

  final String? peerId;
  final Uint8List? avatarBytes;
  final double size;

  const UserAvatar({
    super.key,
    this.peerId,
    this.avatarBytes,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    // Priority 1: In-memory bytes (user's own avatar, pre-loaded by wired layer)
    if (avatarBytes != null) {
      return _buildPhotoAvatar(Image.memory(
        avatarBytes!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: _errorBuilder,
      ));
    }

    // Priority 2: File on disk (contact avatar downloaded by ProfileUpdateListener)
    if (peerId != null && _documentsDir != null) {
      final file = File('$_documentsDir/media/avatars/$peerId.jpg');
      if (file.existsSync()) {
        return _buildPhotoAvatar(Image.file(
          file,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: _errorBuilder,
        ));
      }
    }

    // Priority 3: Deterministic ring avatar
    if (peerId != null) {
      return RingAvatar(peerId: peerId!, size: size);
    }

    // Priority 4: Generic fallback
    return _buildFallbackIcon();
  }

  Widget _buildPhotoAvatar(Widget imageWidget) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.35)),
        color: const Color.fromRGBO(22, 24, 30, 0.7),
      ),
      child: ClipOval(child: imageWidget),
    );
  }

  Widget _errorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    if (peerId != null) {
      return RingAvatar(peerId: peerId!, size: size);
    }
    return Icon(
      Icons.person_outline_rounded,
      color: const Color.fromRGBO(255, 255, 255, 0.8),
      size: size * 0.48,
    );
  }

  Widget _buildFallbackIcon() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.35)),
        color: const Color.fromRGBO(22, 24, 30, 0.7),
      ),
      child: Icon(
        Icons.person_outline_rounded,
        color: const Color.fromRGBO(255, 255, 255, 0.8),
        size: size * 0.48,
      ),
    );
  }
}
