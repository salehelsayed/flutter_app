import 'media_playback_adapter.dart';
import 'media_viewer_item.dart';

/// Minimum wall-clock spacing between durable resume checkpoints while a video
/// plays. A per-frame position-tick storm therefore persists at most once per
/// interval.
const Duration kMediaViewerResumeCheckpointInterval = Duration(seconds: 5);

/// Owner-aware durable resume persistence surface for the shared viewer.
///
/// Callback-only and transport-free: the viewer never imports a repository. A
/// lane owner (plan 228 `MediaLibraryStateRepository`) adapts one to this
/// interface. Every read/write receives the full [MediaViewerItem], so the
/// exact `(ownerLane, attachmentId)` identity travels with each call.
abstract class MediaViewerResumeStore {
  /// Owner-aware read of the durable resume position (ms) for [item], or null
  /// when none is stored. Only ever called for resumable items.
  Future<int?> readResumePosition(MediaViewerItem item);

  /// Owner-aware write of the durable resume position (ms) for [item].
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs);
}

/// Injectable wall clock (tests advance a fake one to prove throttling).
typedef MediaViewerClock = DateTime Function();

/// Drives owner-aware durable video resume for a single viewer page.
///
/// Contract (mirrors plan 228 `updatePlaybackPosition`):
/// - restore: after init, seek once to the persisted position (owner-aware
///   read). Non-video / ownerless / unresolved items never read.
/// - checkpoint: while playing, persist the clamped current position at most
///   once per [checkpointInterval].
/// - flush: on pause / page change / dispose, persist immediately.
/// - clamp: negative -> 0; with a known duration, clamp to `0..duration` and
///   reset to 0 on completion; with an unknown duration store a non-negative
///   position and re-clamp once the duration becomes known.
/// - non-video / ownerless items cause zero reads and zero writes.
class MediaVideoResumeController {
  MediaVideoResumeController({
    required this.item,
    required this.adapter,
    this.store,
    MediaViewerClock? clock,
    this.checkpointInterval = kMediaViewerResumeCheckpointInterval,
  }) : _clock = clock ?? DateTime.now;

  final MediaViewerItem item;
  final MediaPlaybackAdapter adapter;
  final MediaViewerResumeStore? store;
  final Duration checkpointInterval;
  final MediaViewerClock _clock;

  bool _restored = false;
  bool _completionWritten = false;
  DateTime? _lastCheckpointAt;

  bool get _enabled => store != null && item.isResumable;

  /// Reads and applies the durable resume position exactly once after the
  /// adapter is initialized. No-op (and no read) for non-resumable items.
  Future<void> restore() async {
    if (_restored || !_enabled) return;
    _restored = true;
    final stored = await store!.readResumePosition(item);
    if (stored == null || stored <= 0) return;
    final target = _clampMs(stored, adapter.duration.inMilliseconds);
    if (target <= 0) return;
    await adapter.seekTo(Duration(milliseconds: target));
  }

  /// Called from the adapter listener. Persists a throttled checkpoint while
  /// playing, and resets to zero exactly once on genuine completion.
  Future<void> onTick() async {
    if (!_enabled) return;

    // Genuine completion (the video reached its end): reset to 0 exactly once.
    if (adapter.isCompleted) {
      if (_completionWritten) return;
      _completionWritten = true;
      await _write(0);
      return;
    }
    _completionWritten = false;

    if (!adapter.isPlaying) return;

    final now = _clock();
    final last = _lastCheckpointAt;
    if (last != null && now.difference(last) < checkpointInterval) return;
    await _write(_clampMs(adapter.position.inMilliseconds, adapter.duration.inMilliseconds));
  }

  /// Persists the current clamped position immediately (pause / page change /
  /// dispose). No-op for non-resumable items. A genuine completion stores 0;
  /// an overrun (position beyond a newly-known shorter duration) clamps down.
  Future<void> flush() async {
    if (!_enabled) return;
    if (adapter.isCompleted) {
      await _write(0);
      return;
    }
    await _write(_clampMs(adapter.position.inMilliseconds, adapter.duration.inMilliseconds));
  }

  Future<void> _write(int positionMs) async {
    _lastCheckpointAt = _clock();
    await store!.writeResumePosition(item, positionMs);
  }

  /// Clamps a candidate position: negatives become 0; with a known duration,
  /// values above it clamp down; with an unknown duration only the lower bound
  /// applies (a later replay re-clamps once the duration is known).
  int _clampMs(int positionMs, int durationMs) {
    if (positionMs < 0) return 0;
    if (durationMs > 0 && positionMs > durationMs) return durationMs;
    return positionMs;
  }
}
