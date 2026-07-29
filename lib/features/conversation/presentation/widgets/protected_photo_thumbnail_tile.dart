import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_app/shared/widgets/media/ios_capture_protected_image.dart';

/// Restricted real-pixel thumbnail for a protected photo bubble (plan 301).
///
/// Renders the actual image with a lock badge while keeping every restriction
/// intact: the tile's ONLY action is the injected protected open flow, it owns
/// no long-press handler (the bubble's context overlay and swipe-to-quote stay
/// ancestors), and it exposes exactly one combined semantics node (button +
/// label + reopen value).
///
/// Platform split: on iOS pixels render through the shipped capture-protected
/// platform view (excluded from screenshots/recordings per-view); on Android
/// and everywhere else a plain bounded [Image.file] — the conversation route
/// holds the window-level FLAG_SECURE owner while any tile is visible, so the
/// factory only constructs this widget inside a protected window.
///
/// Pixel failures (undecodable file, platform-view failure) fail closed to the
/// familiar no-pixel lock visual in place — never a broken-image state — and
/// the tap still routes to the same protected open flow.
class ProtectedPhotoThumbnailTile extends StatefulWidget {
  static const tileKey = ValueKey('private-media-thumbnail-tile');
  static const fallbackVisualKey = ValueKey(
    'private-media-thumbnail-fallback-visual',
  );

  const ProtectedPhotoThumbnailTile({
    super.key,
    required this.imagePath,
    required this.semanticsLabel,
    this.semanticsValue,
    this.onOpen,
  });

  /// Absolute path of the local pixel source (receiver: the persisted inline
  /// thumbnail sibling; sender: the full local media file).
  final String imagePath;

  /// Reused protected copy (the `private_media_card_title_protected_photo`
  /// family) — announced once on the tile's single semantics node.
  final String semanticsLabel;

  /// Optional secondary announcement (the sender-side reopen disclosure).
  final String? semanticsValue;

  /// The exact existing protected open flow; null renders a disabled tile.
  final VoidCallback? onOpen;

  @override
  State<ProtectedPhotoThumbnailTile> createState() =>
      _ProtectedPhotoThumbnailTileState();
}

class _ProtectedPhotoThumbnailTileState
    extends State<ProtectedPhotoThumbnailTile> {
  bool _pixelsFailed = false;

  void _failPixelsClosed() {
    if (_pixelsFailed || !mounted) return;
    setState(() => _pixelsFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final Widget pixels;
    if (_pixelsFailed) {
      pixels = Container(
        key: ProtectedPhotoThumbnailTile.fallbackVisualKey,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withValues(alpha: 0.30),
              colors.tertiary.withValues(alpha: 0.14),
              colors.surfaceContainerHighest.withValues(alpha: 0.78),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.lock_outline_rounded,
            size: 38,
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      pixels = IosCaptureProtectedImage(
        path: widget.imagePath,
        // Auto-reveal: the bubble consumes no view budget, so there is no
        // pre-frame authorization handshake here.
        onFirstRenderedFrame: null,
        onPreFrameFailure: _failPixelsClosed,
        onPostFrameFailure: _failPixelsClosed,
      );
    } else {
      pixels = Image.file(
        File(widget.imagePath),
        fit: BoxFit.cover,
        cacheWidth: 400,
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _failPixelsClosed(),
          );
          return Container(
            key: ProtectedPhotoThumbnailTile.fallbackVisualKey,
            color: colors.surfaceContainerHighest,
          );
        },
      );
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: widget.onOpen != null,
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      onTap: widget.onOpen,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: widget.onOpen,
        child: ClipRRect(
          key: ProtectedPhotoThumbnailTile.tileKey,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                pixels,
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(0, 0, 0, 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
