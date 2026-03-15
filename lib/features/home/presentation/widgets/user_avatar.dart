import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
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
  static final Map<String, ValueNotifier<String?>> _avatarPathNotifiers = {};
  static final Set<String> _resolvingPeerIds = <String>{};
  static final Set<String> _knownMissingPeerIds = <String>{};

  /// Monotonic counter appended to path to bust image cache on invalidation.
  static int _generation = 0;

  /// Exposes the documents directory for avatar file checks.
  static String? get documentsDir => _documentsDir;

  /// Call once from main() with `getApplicationDocumentsDirectory().path`.
  static void setDocumentsDir(String path) {
    if (_documentsDir == path) return;
    _documentsDir = path;
    _resolvingPeerIds.clear();
    _knownMissingPeerIds.clear();
    for (final notifier in _avatarPathNotifiers.values) {
      notifier.value = null;
    }
  }

  /// Clears any cached resolution for [peerId] and reloads it asynchronously.
  static void invalidatePeer(String peerId) {
    _knownMissingPeerIds.remove(peerId);
    _resolvingPeerIds.remove(peerId);
    _generation++;
    final notifier = _avatarPathNotifiers.putIfAbsent(
      peerId,
      () => ValueNotifier<String?>(null),
    );
    notifier.value = null;
    _resolveAvatarPath(peerId, notifier, force: true);
  }

  static ValueNotifier<String?> avatarPathListenable(String peerId) {
    final notifier = _avatarPathNotifiers.putIfAbsent(
      peerId,
      () => ValueNotifier<String?>(null),
    );
    _resolveAvatarPath(peerId, notifier);
    return notifier;
  }

  static Future<void> _resolveAvatarPath(
    String peerId,
    ValueNotifier<String?> notifier, {
    bool force = false,
  }) async {
    final docsDir = _documentsDir;
    if (docsDir == null) return;
    if (_resolvingPeerIds.contains(peerId)) return;
    if (!force && notifier.value != null) return;
    if (!force && _knownMissingPeerIds.contains(peerId)) return;

    _resolvingPeerIds.add(peerId);
    final filePath = '$docsDir/media/avatars/$peerId.jpg';
    try {
      final exists = await File(filePath).exists();
      if (exists) {
        _knownMissingPeerIds.remove(peerId);
        // Append generation to bust cache when file content changed at same path
        final taggedPath = '$filePath?v=$_generation';
        if (force || notifier.value != taggedPath) {
          notifier.value = taggedPath;
        }
      } else {
        _knownMissingPeerIds.add(peerId);
        if (notifier.value != null) {
          notifier.value = null;
        }
      }
    } catch (_) {
      _knownMissingPeerIds.add(peerId);
      if (notifier.value != null) {
        notifier.value = null;
      }
    } finally {
      _resolvingPeerIds.remove(peerId);
    }
  }

  final String? peerId;
  final Uint8List? avatarBytes;
  final double size;
  final bool showGlow;
  final bool showPhotoFrame;

  const UserAvatar({
    super.key,
    this.peerId,
    this.avatarBytes,
    this.size = 42,
    this.showGlow = true,
    this.showPhotoFrame = true,
  });

  @override
  Widget build(BuildContext context) {
    // Priority 1: In-memory bytes (user's own avatar, pre-loaded by wired layer)
    if (avatarBytes != null) {
      return _wrapWithGlow(
        _buildPhotoAvatar(
          Image.memory(
            avatarBytes!,
            key: ValueKey(avatarBytes.hashCode),
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: _errorBuilder,
          ),
        ),
      );
    }

    // Priority 2: File on disk (contact avatar downloaded by ProfileUpdateListener)
    final resolvedPeerId = peerId;
    if (resolvedPeerId != null && _documentsDir != null) {
      return ValueListenableBuilder<String?>(
        valueListenable: avatarPathListenable(resolvedPeerId),
        builder: (context, avatarPath, child) {
          if (avatarPath == null) {
            return child!;
          }
          // Strip cache-bust suffix to get the real file path
          final realPath = avatarPath.split('?').first;
          return _wrapWithGlow(
            _buildPhotoAvatar(
              Image.file(
                File(realPath),
                key: ValueKey(avatarPath), // unique key forces reload
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: false,
                errorBuilder: _errorBuilder,
              ),
            ),
          );
        },
        child: _wrapWithGlow(RingAvatar(peerId: resolvedPeerId, size: size)),
      );
    }

    // Priority 3: Deterministic ring avatar
    if (resolvedPeerId != null) {
      return _wrapWithGlow(RingAvatar(peerId: resolvedPeerId, size: size));
    }

    // Priority 4: Generic fallback
    return _buildFallbackIcon();
  }

  Widget _wrapWithGlow(Widget child) {
    final resolvedPeerId = peerId;
    if (resolvedPeerId == null || !showGlow) return child;

    final glowColor = RingAvatarGenerator.glowColorForPeerId(resolvedPeerId);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.35),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.05,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPhotoAvatar(Widget imageWidget) {
    if (!showPhotoFrame) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipOval(child: imageWidget),
      );
    }
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

  Widget _errorBuilder(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
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
