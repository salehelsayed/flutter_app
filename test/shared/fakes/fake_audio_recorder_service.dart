import 'dart:async';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

class FakeAudioRecorderService implements AudioRecorderService {
  bool _isRecording = false;
  bool _startInProgress = false;
  bool _stopRequestedWhileStarting = false;
  String? _currentOutputPath;
  int fakeDurationMs = 3000;
  int fakeSizeBytes = 48000;
  bool permissionGranted = true;
  bool shouldFailStart = false;
  int startCallCount = 0;
  int stopCallCount = 0;
  int cancelCallCount = 0;
  Completer<void>? startGate;
  Completer<void>? stopGate;

  /// When set, [stop] returns this path instead of [_currentOutputPath].
  String? fakeOutputPath;
  final List<String> deletedPaths = [];
  final _durationController = StreamController<Duration>.broadcast();
  final _amplitudeController = StreamController<double>.broadcast();

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start({required String outputPath}) async {
    startCallCount++;
    if (_isRecording || _startInProgress) {
      throw StateError('Already recording');
    }
    if (shouldFailStart) {
      throw StateError('Recording start failed');
    }
    _startInProgress = true;
    _currentOutputPath = outputPath;

    final gate = startGate;
    if (gate != null) {
      await gate.future;
    }

    _startInProgress = false;
    if (_stopRequestedWhileStarting) {
      _stopRequestedWhileStarting = false;
      _currentOutputPath = null;
      return;
    }
    _isRecording = true;
  }

  @override
  Future<AudioRecording?> stop() async {
    stopCallCount++;
    final gate = stopGate;
    if (_startInProgress) {
      _stopRequestedWhileStarting = true;
      if (gate != null) {
        await gate.future;
      }
      return null;
    }
    if (!_isRecording) return null;
    _isRecording = false;
    final path = fakeOutputPath ?? _currentOutputPath!;
    _currentOutputPath = null;

    if (gate != null) {
      await gate.future;
    }

    if (fakeDurationMs < 500) return null;

    return AudioRecording(
      filePath: path,
      durationMs: fakeDurationMs,
      sizeBytes: fakeSizeBytes,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCallCount++;
    if (!_isRecording) return;
    _isRecording = false;
    if (_currentOutputPath != null) {
      deletedPaths.add(_currentOutputPath!);
    }
    _currentOutputPath = null;
  }

  /// Manually emit a duration update for testing.
  void emitDuration(Duration duration) {
    _durationController.add(duration);
  }

  /// Manually emit a normalized amplitude value for testing.
  void emitAmplitude(double value) {
    _amplitudeController.add(value);
  }

  @override
  Future<void> dispose() async {
    await _durationController.close();
    await _amplitudeController.close();
  }
}
