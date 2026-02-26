import 'dart:async';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

class FakeAudioRecorderService implements AudioRecorderService {
  bool _isRecording = false;
  String? _currentOutputPath;
  int fakeDurationMs = 3000;
  int fakeSizeBytes = 48000;
  bool permissionGranted = true;
  bool shouldFailStart = false;
  final List<String> deletedPaths = [];
  final _durationController = StreamController<Duration>.broadcast();

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start({required String outputPath}) async {
    if (_isRecording) {
      throw StateError('Already recording');
    }
    if (shouldFailStart) {
      throw StateError('Recording start failed');
    }
    _isRecording = true;
    _currentOutputPath = outputPath;
  }

  @override
  Future<AudioRecording?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;
    final path = _currentOutputPath!;
    _currentOutputPath = null;

    if (fakeDurationMs < 500) return null;

    return AudioRecording(
      filePath: path,
      durationMs: fakeDurationMs,
      sizeBytes: fakeSizeBytes,
    );
  }

  @override
  Future<void> cancel() async {
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

  @override
  Future<void> dispose() async {
    await _durationController.close();
  }
}
