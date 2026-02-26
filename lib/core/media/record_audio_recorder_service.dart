import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

/// Production implementation of [AudioRecorderService] using the `record` package.
///
/// Records AAC audio in .m4a container. Timer-based duration stream.
/// Auto-stops at 5 minutes.
class RecordAudioRecorderService implements AudioRecorderService {
  static const _maxDuration = Duration(minutes: 5);
  static const _tickInterval = Duration(milliseconds: 100);

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentOutputPath;
  DateTime? _startTime;
  Timer? _ticker;
  Timer? _maxDurationTimer;
  final _durationController = StreamController<Duration>.broadcast();

  @override
  bool get isRecording => _isRecording;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start({required String? outputPath}) async {
    if (_isRecording) {
      throw StateError('Already recording');
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

    _isRecording = true;
    _startTime = DateTime.now();

    _ticker = Timer.periodic(_tickInterval, (_) {
      if (_startTime != null) {
        final elapsed = DateTime.now().difference(_startTime!);
        _durationController.add(elapsed);
      }
    });

    _maxDurationTimer = Timer(_maxDuration, () async {
      if (_isRecording) {
        await stop();
      }
    });
  }

  @override
  Future<AudioRecording?> stop() async {
    if (!_isRecording) return null;

    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    _isRecording = false;

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

    return AudioRecording(
      filePath: path,
      durationMs: elapsed,
      sizeBytes: size,
    );
  }

  @override
  Future<void> cancel() async {
    if (!_isRecording) return;

    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    _isRecording = false;
    _startTime = null;

    await _recorder.stop();

    if (_currentOutputPath != null) {
      final file = File(_currentOutputPath!);
      if (await file.exists()) await file.delete();
    }
    _currentOutputPath = null;
  }

  @override
  Future<void> dispose() async {
    _ticker?.cancel();
    _maxDurationTimer?.cancel();
    await _durationController.close();
    _recorder.dispose();
  }

  Future<String> _defaultOutputPath() async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${tempDir.path}/voice_$timestamp.m4a';
  }
}
