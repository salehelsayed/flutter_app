import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

/// Deterministic in-memory [MediaPlaybackAdapter] for tests.
///
/// Extends (not implements) so it inherits the production [seekBy] clamp — a
/// mutation to that clamp re-reds through this fake. Records every command and
/// exposes settable state; call [notify] to fire listeners like a position
/// tick.
class FakeMediaPlaybackAdapter extends MediaPlaybackAdapter {
  FakeMediaPlaybackAdapter({
    Duration duration = const Duration(minutes: 1),
    Duration position = Duration.zero,
    this.failInitialize = false,
    double aspectRatio = 1.0,
  }) : _duration = duration,
       _position = position,
       _aspectRatio = aspectRatio;

  Duration _duration;
  Duration _position;
  double _aspectRatio;
  bool failInitialize;

  final List<VoidCallback> _listeners = <VoidCallback>[];

  bool _initialized = false;
  Object? _initError;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isCompleted = false;
  double _speed = 1.0;

  // Recording.
  int initializeCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  final List<Duration> seekTargets = <Duration>[];
  final List<double> setSpeedCalls = <double>[];
  final List<bool> setMutedCalls = <bool>[];

  // Test mutators.
  set duration(Duration value) => _duration = value;
  set position(Duration value) => _position = value;
  set aspectRatio(double value) => _aspectRatio = value;
  set isPlaying(bool value) => _isPlaying = value;
  set isCompleted(bool value) => _isCompleted = value;

  /// Fire listeners (simulates a position/state tick).
  void notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  Future<void> initialize() async {
    initializeCount++;
    if (failInitialize) {
      _initError = StateError('fake init failure');
      throw _initError!;
    }
    _initialized = true;
  }

  @override
  bool get isInitialized => _initialized;

  @override
  Object? get initializationError => _initError;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  bool get isCompleted => _isCompleted;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isMuted => _isMuted;

  @override
  double get speed => _speed;

  @override
  double get aspectRatio => _aspectRatio;

  @override
  Future<void> play() async {
    playCount++;
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _isPlaying = false;
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekTargets.add(position);
    _position = position;
  }

  @override
  Future<void> setSpeed(double speed) async {
    setSpeedCalls.add(speed);
    _speed = speed;
  }

  @override
  Future<void> setMuted(bool muted) async {
    setMutedCalls.add(muted);
    _isMuted = muted;
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Widget buildSurface() =>
      const SizedBox(key: ValueKey('fake-video-surface'));

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

/// One recorded owner-aware resume write.
class ResumeWrite {
  const ResumeWrite(this.owner, this.attachmentId, this.positionMs);

  final MediaOwnerLane owner;
  final String attachmentId;
  final int positionMs;

  @override
  String toString() => 'ResumeWrite($owner, $attachmentId, $positionMs)';
}

/// Strict, owner-enforcing [MediaViewerResumeStore] for tests.
///
/// Every read/write MUST carry a trusted owner: an ownerless call throws, so a
/// controller that persisted resume for a non-video / unresolved item fails
/// loudly instead of being silently accepted. [stored] seeds the durable
/// position returned by [readResumePosition] (per attachment ID, else the
/// default).
class RecordingResumeStore implements MediaViewerResumeStore {
  RecordingResumeStore({this.defaultStored, Map<String, int>? stored})
    : _stored = stored ?? <String, int>{};

  final int? defaultStored;
  final Map<String, int> _stored;

  final List<MediaViewerItem> reads = <MediaViewerItem>[];
  final List<ResumeWrite> writes = <ResumeWrite>[];

  @override
  Future<int?> readResumePosition(MediaViewerItem item) async {
    if (item.owner == null) {
      throw StateError('resume read attempted for an ownerless item');
    }
    reads.add(item);
    return _stored[item.attachmentId] ?? defaultStored;
  }

  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    if (item.owner == null) {
      throw StateError('resume write attempted for an ownerless item');
    }
    writes.add(ResumeWrite(item.owner!, item.attachmentId, positionMs));
    _stored[item.attachmentId] = positionMs;
  }
}
