import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

typedef IsMicrophoneCaptureActive = bool Function();

/// A synchronous, exclusive token for one microphone-capture operation.
///
/// This scope intentionally knows nothing about playback. Audio playback
/// interruption and recovery remain owned by their existing session policy.
abstract interface class MicrophoneCaptureLease {
  void release();
}

/// Raised when another capture operation already owns the microphone.
final class MicrophoneCaptureLeaseRefused implements Exception {
  const MicrophoneCaptureLeaseRefused();

  @override
  String toString() => 'MicrophoneCaptureLeaseRefused';
}

/// Serializes all capture operations that share this exact coordinator.
///
/// Acquisition and release update ownership synchronously, so no permission or
/// plugin await can open a check-then-act race. Each returned lease is
/// idempotent and can only clear its own token.
final class MicrophoneCaptureLeaseCoordinator {
  MicrophoneCaptureLeaseCoordinator({
    required IsMicrophoneCaptureActive isCaptureActive,
  }) : _isCaptureActive = isCaptureActive;

  final IsMicrophoneCaptureActive _isCaptureActive;
  Object? _owner;

  MicrophoneCaptureLease acquire() {
    if (_owner != null || _isCaptureActive()) {
      throw const MicrophoneCaptureLeaseRefused();
    }
    final token = Object();
    _owner = token;
    return _ExclusiveMicrophoneCaptureLease(this, token);
  }

  void _release(Object token) {
    if (identical(_owner, token)) _owner = null;
  }
}

final Expando<MicrophoneCaptureLeaseCoordinator>
_microphoneCaptureLeaseCoordinators =
    Expando<MicrophoneCaptureLeaseCoordinator>();

/// Returns the one capture coordinator associated with [recorder]'s identity.
///
/// Production shares one recorder across conversation surfaces and call
/// composition. Identity scoping keeps tests and independent recorder
/// instances isolated while preserving the existing `isRecording` sentinel
/// for capture paths that have not yet been moved behind a lease.
MicrophoneCaptureLeaseCoordinator microphoneCaptureLeasesFor(
  AudioRecorderService recorder,
) {
  final existing = _microphoneCaptureLeaseCoordinators[recorder];
  if (existing != null) return existing;
  final created = MicrophoneCaptureLeaseCoordinator(
    isCaptureActive: () => recorder.isRecording,
  );
  _microphoneCaptureLeaseCoordinators[recorder] = created;
  return created;
}

final class _ExclusiveMicrophoneCaptureLease implements MicrophoneCaptureLease {
  _ExclusiveMicrophoneCaptureLease(this._coordinator, this._token);

  final MicrophoneCaptureLeaseCoordinator _coordinator;
  final Object _token;
  bool _released = false;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _coordinator._release(_token);
  }
}

/// Abstract interface for audio recording.
///
/// Production implementation wraps the `record` package.
/// Test implementation uses [FakeAudioRecorderService].
abstract class AudioRecorderService {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> start({required String outputPath});
  Future<AudioRecording?> stop();
  Future<void> cancel();
  bool get isRecording;
  Stream<Duration> get durationStream;
  Stream<double> get amplitudeStream;
  Future<void> dispose();

  /// Invoked after the recorder stops itself at the max recording duration,
  /// with the result of that internal stop. Auto-stop happens without any user
  /// gesture, so the active UI surface sets this to resync its composer state
  /// and clears it again on its own stop/cancel paths.
  void Function(AudioRecording? recording)? onAutoStopped;
}
