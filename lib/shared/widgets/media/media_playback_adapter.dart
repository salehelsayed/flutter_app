import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'media_viewer_item.dart';

/// The four playback speeds the shared video controls expose, in cycle order
/// (1x is the resting default; cycling advances to the next).
const List<double> kMediaPlaybackSpeeds = <double>[1.0, 1.5, 2.0, 0.5];

/// How far each skip button jumps.
const Duration kMediaViewerSkipInterval = Duration(seconds: 10);

/// Pure clamp for a relative seek: `current + delta`, bounded to
/// `0..duration`. With an unknown duration ([duration] == [Duration.zero])
/// only the lower bound applies. Shared by the controls and the adapter so a
/// single edit here re-reds the clamp mutation regardless of the seek entry
/// point.
Duration mediaPlaybackClampSeek(
  Duration current,
  Duration delta,
  Duration duration,
) {
  final target = current + delta;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// Injectable playback surface around a concrete video controller.
///
/// Tests inject a fake implementation to prove control, resume, and lifecycle
/// decisions deterministically without a plugin texture. Production uses
/// [VideoPlayerControllerAdapter] over [VideoPlayerController].
abstract class MediaPlaybackAdapter {
  /// Prepares the underlying controller. Completes when [isInitialized] is
  /// true, or throws / sets [initializationError] on failure.
  Future<void> initialize();

  bool get isInitialized;
  Object? get initializationError;

  /// Synchronous snapshot of the current position (mirrors
  /// `VideoPlayerController.value.position`).
  Duration get position;

  /// Total duration, or [Duration.zero] when not yet known.
  Duration get duration;

  /// True once the video has naturally reached its end. Distinguishes a
  /// genuine completion (resume resets to 0) from a mere position >= duration
  /// overrun caused by a previously-unknown duration (resume clamps down).
  bool get isCompleted;

  bool get isPlaying;
  bool get isMuted;
  double get speed;
  double get aspectRatio;

  Future<void> play();
  Future<void> pause();

  /// Absolute seek.
  Future<void> seekTo(Duration position);

  /// Relative seek, clamped to `0..duration` via [mediaPlaybackClampSeek].
  /// Concrete: delegates to [seekTo]. Subclasses do not override this so the
  /// clamp stays in one place.
  Future<void> seekBy(Duration delta) =>
      seekTo(mediaPlaybackClampSeek(position, delta, duration));

  Future<void> setSpeed(double speed);
  Future<void> setMuted(bool muted);

  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);

  /// Builds the concrete render surface (the real video texture, or a fake
  /// placeholder in tests). Keeps [VideoPlayerController] out of the interface.
  Widget buildSurface();

  Future<void> dispose();
}

/// Signature the viewer uses to build one adapter per video item. Tests pass a
/// factory that returns a fake keyed by item; production uses
/// [defaultMediaPlaybackAdapterFactory].
typedef MediaPlaybackAdapterFactory =
    MediaPlaybackAdapter Function(MediaViewerItem item);

/// Production factory: a real [VideoPlayerController] over the item's local
/// file. Requires a downloaded video (`localPath != null`).
MediaPlaybackAdapter defaultMediaPlaybackAdapterFactory(MediaViewerItem item) =>
    VideoPlayerControllerAdapter(item.localPath!);

/// Concrete [MediaPlaybackAdapter] over the `video_player` plugin.
///
/// Extends (not implements) so it inherits the shared [seekBy] clamp; only the
/// leaf controller operations are overridden here.
class VideoPlayerControllerAdapter extends MediaPlaybackAdapter {
  VideoPlayerControllerAdapter(this._filePath);

  final String _filePath;
  VideoPlayerController? _controller;
  Object? _initializationError;
  double _speed = 1.0;

  @override
  Future<void> initialize() async {
    final controller = VideoPlayerController.file(File(_filePath));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
    } catch (error) {
      _initializationError = error;
      rethrow;
    }
  }

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Object? get initializationError => _initializationError;

  @override
  Duration get position => _controller?.value.position ?? Duration.zero;

  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;

  @override
  bool get isCompleted => _controller?.value.isCompleted ?? false;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isMuted => (_controller?.value.volume ?? 1.0) <= 0.0;

  @override
  double get speed => _speed;

  @override
  double get aspectRatio {
    final ratio = _controller?.value.aspectRatio ?? 1.0;
    return ratio > 0 ? ratio : 1.0;
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<void> setMuted(bool muted) async =>
      _controller?.setVolume(muted ? 0.0 : 1.0);

  @override
  void addListener(VoidCallback listener) => _controller?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller?.removeListener(listener);

  @override
  Widget buildSurface() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(controller);
  }

  @override
  Future<void> dispose() async => _controller?.dispose();
}
