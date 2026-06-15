import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/normalize_amplitude.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

/// Production implementation of [AudioRecorderService] using the `record` package.
///
/// Records AAC audio in .m4a container. Timer-based duration stream.
/// Auto-stops at [maxDuration] (5 minutes by default).
///
/// Holds a screen wake lock for the whole recording so the screen cannot idle
/// off mid-recording: acquired after the recorder starts, released on
/// stop/cancel/dispose/auto-stop. This is the only wake-lock call site outside
/// the presentation layer; the ref-counted [UploadWakeLockController] keeps it
/// safe alongside concurrent upload/migration holds.
class RecordAudioRecorderService implements AudioRecorderService {
  /// [recorder] and [maxDuration] are test seams: unit tests inject a fake
  /// recorder (no platform channel) and a short auto-stop duration.
  RecordAudioRecorderService({
    AudioRecorder? recorder,
    this.maxDuration = const Duration(minutes: 5),
  }) : _recorder = recorder ?? AudioRecorder();

  static const _tickInterval = Duration(milliseconds: 100);

  @override
  void Function(AudioRecording? recording)? onAutoStopped;

  final Duration maxDuration;
  final AudioRecorder _recorder;
  bool _isRecording = false;
  bool _wakeLockHeld = false;
  String? _currentOutputPath;
  DateTime? _startTime;
  Timer? _ticker;
  Timer? _maxDurationTimer;
  final _durationController = StreamController<Duration>.broadcast();
  final _amplitudeController = StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeBridgeSub;

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start({required String? outputPath}) async {
    if (_isRecording) {
      // Force-stop stale recording so we can start fresh.
      _ticker?.cancel();
      _maxDurationTimer?.cancel();
      _startTime = null;
      try {
        await _recorder.stop();
      } catch (_) {}
      if (_currentOutputPath != null) {
        final old = File(_currentOutputPath!);
        if (await old.exists()) await old.delete();
      }
      _currentOutputPath = null;
      _isRecording = false;
      await _releaseWakeLock();
    }

    final path = (outputPath == null || outputPath.isEmpty)
        ? await _defaultOutputPath()
        : outputPath;
    _currentOutputPath = path;

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );

    try {
      _isRecording = true;
      await _acquireWakeLock();
      _startTime = DateTime.now();
      _ensureAmplitudeStreamBridge();

      _ticker = Timer.periodic(_tickInterval, (_) {
        if (_startTime != null) {
          final elapsed = DateTime.now().difference(_startTime!);
          _durationController.add(elapsed);
        }
      });

      _maxDurationTimer = Timer(maxDuration, () async {
        if (_isRecording) {
          final recording = await stop();
          onAutoStopped?.call(recording);
        }
      });
    } catch (_) {
      // Roll back so a throw out of start() always means "the service holds
      // nothing": no lock, no timers, no plugin recording. The UI catch
      // handlers rely on that invariant — they reset composer state without
      // calling cancel(). Without this, a throwing wake-lock driver (e.g.
      // wakelock_plus NoActivityException) would leak a counted hold with no
      // auto-stop bound while the plugin keeps recording.
      _isRecording = false;
      _startTime = null;
      _ticker?.cancel();
      _maxDurationTimer?.cancel();
      try {
        await _releaseWakeLock();
      } catch (_) {}
      try {
        await _recorder.stop();
      } catch (_) {}
      _currentOutputPath = null;
      rethrow;
    }
  }

  @override
  Future<AudioRecording?> stop() async {
    if (!_isRecording) return null;

    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    _isRecording = false;
    // Release before the plugin call: a throwing stop() must not leak a hold.
    await _releaseWakeLock();

    final path = await _recorder.stop();
    final elapsed = _startTime != null
        ? DateTime.now().difference(_startTime!).inMilliseconds
        : 0;
    _startTime = null;

    if (path == null || elapsed < 500) {
      // Too short — clean up
      if (_currentOutputPath != null) {
        final file = File(_currentOutputPath!);
        if (await file.exists()) await file.delete();
      }
      _currentOutputPath = null;
      return null;
    }

    final file = File(path);
    final size = await file.exists() ? await file.length() : 0;
    _currentOutputPath = null;

    return AudioRecording(filePath: path, durationMs: elapsed, sizeBytes: size);
  }

  @override
  Future<void> cancel() async {
    if (!_isRecording) return;

    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    _isRecording = false;
    _startTime = null;
    await _releaseWakeLock();

    await _recorder.stop();

    if (_currentOutputPath != null) {
      final file = File(_currentOutputPath!);
      if (await file.exists()) await file.delete();
    }
    _currentOutputPath = null;
  }

  @override
  Future<void> dispose() async {
    await _releaseWakeLock();
    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    try {
      // Some device/emulator plugin backends can stall while tearing down the
      // amplitude event stream. Keep recorder disposal bounded so app shutdown
      // and device integration tests do not hang indefinitely.
      await _amplitudeBridgeSub
          ?.cancel()
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    _amplitudeBridgeSub = null;
    await _durationController.close();
    await _amplitudeController.close();
    _recorder.dispose();
  }

  Future<void> _acquireWakeLock() async {
    if (_wakeLockHeld) return;
    _wakeLockHeld = true;
    await UploadWakeLockController.acquire();
  }

  Future<void> _releaseWakeLock() async {
    // Guarded so this service can never decrement a hold it doesn't own.
    if (!_wakeLockHeld) return;
    _wakeLockHeld = false;
    await UploadWakeLockController.release();
  }

  void _ensureAmplitudeStreamBridge() {
    if (_amplitudeBridgeSub != null) return;
    _amplitudeBridgeSub = _recorder.onAmplitudeChanged(_tickInterval).listen((
      event,
    ) {
      _amplitudeController.add(normalizeAmplitude(event.current));
    });
  }

  Future<String> _defaultOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/voice_$timestamp.m4a';
  }
}
