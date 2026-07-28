import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_voice_capture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationVoiceCaptureController', () {
    test(
      'owns callbacks subscriptions and waveform only for its recorder session',
      () async {
        final recorder = _ControlledRecorder();
        addTearDown(recorder.dispose);
        final controller = ConversationVoiceCaptureController(
          amplitudeWindowSize: 3,
          waveformSampleCount: 5,
        );
        addTearDown(controller.dispose);

        final startGate = Completer<void>();
        recorder.startGate = startGate;
        final arming = controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        );
        await _flushUntil(() => recorder.startCalls == 1);
        expect(controller.state.phase, ConversationVoiceCapturePhase.arming);

        await controller.cancel();
        expect(controller.state.phase, ConversationVoiceCapturePhase.stopping);
        startGate.complete();
        final aborted = await arming;
        expect(aborted.status, ConversationVoiceCaptureStartStatus.aborted);
        expect(recorder.cancelCalls, 1);
        expect(recorder.onAutoStopped, isNull);
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        recorder.startGate = null;
        final started = await controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        );
        expect(started.status, ConversationVoiceCaptureStartStatus.started);
        final ownedHandler = recorder.onAutoStopped;
        expect(ownedHandler, isNotNull);

        recorder.emitDuration(const Duration(seconds: 2));
        recorder.emitAmplitude(0.1);
        recorder.emitAmplitude(0.4);
        recorder.emitAmplitude(0.9);
        await _flushEvents();
        expect(controller.state.duration, const Duration(seconds: 2));
        expect(controller.state.amplitudeValues, <double>[0.1, 0.4, 0.9]);

        final stopped = await controller.stop();
        expect(stopped, isNotNull);
        expect(stopped!.reason, ConversationVoiceCaptureEndReason.manualStop);
        expect(stopped.recording?.filePath, '/tmp/voice.m4a');
        expect(stopped.waveform, <double>[0, 0, 0.1, 0.4, 0.9]);
        expect(recorder.stopCalls, 1);
        expect(recorder.onAutoStopped, isNull);
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        recorder.emitDuration(const Duration(seconds: 9));
        recorder.emitAmplitude(0.7);
        await _flushEvents();
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        expect(
          (await controller.start(
            recorder: recorder,
            requestPermission: () async => MicPermissionStatus.granted,
          )).status,
          ConversationVoiceCaptureStartStatus.started,
        );
        await controller.cancel();
        expect(recorder.cancelCalls, 2);
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        expect(
          (await controller.start(
            recorder: recorder,
            requestPermission: () async => MicPermissionStatus.granted,
          )).status,
          ConversationVoiceCaptureStartStatus.started,
        );
        void foreignHandler(AudioRecording? _) {}
        recorder.onAutoStopped = foreignHandler;
        await controller.cancel();

        expect(
          recorder.cancelCalls,
          2,
          reason: 'a stale surface must not cancel the recorder owner',
        );
        expect(recorder.onAutoStopped, same(foreignHandler));
        expect(controller.state, ConversationVoiceCaptureViewState.idle);
        expect(ownedHandler, isNot(same(foreignHandler)));
      },
    );

    test(
      'auto-stop emits one lane outcome without choosing review or discard',
      () async {
        final recorder = _ControlledRecorder();
        addTearDown(recorder.dispose);
        final outcomes = <ConversationVoiceCaptureOutcome>[];
        final controller = ConversationVoiceCaptureController(
          waveformSampleCount: 4,
          onAutoStopOutcome: outcomes.add,
        );
        addTearDown(controller.dispose);

        final started = await controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        );
        expect(started.status, ConversationVoiceCaptureStartStatus.started);
        recorder.emitAmplitude(0.2);
        recorder.emitAmplitude(0.8);
        await _flushEvents();

        final ownedHandler = recorder.onAutoStopped!;
        final capture = AudioRecording(
          filePath: '/tmp/auto.m4a',
          durationMs: 300000,
          sizeBytes: 4096,
        );
        ownedHandler(capture);
        ownedHandler(capture);
        await _flushEvents();

        expect(outcomes, hasLength(1));
        expect(
          outcomes.single.reason,
          ConversationVoiceCaptureEndReason.autoStop,
        );
        expect(outcomes.single.recording, same(capture));
        expect(outcomes.single.waveform, <double>[0, 0, 0.2, 0.8]);
        expect(recorder.onAutoStopped, isNull);
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        final source = File(
          'lib/shared/widgets/conversation/'
          'conversation_voice_capture_controller.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('VoiceRecordingState')));
        expect(source, isNot(contains("compose_area.dart")));
        expect(
          ConversationVoiceCaptureEndReason.values,
          <ConversationVoiceCaptureEndReason>[
            ConversationVoiceCaptureEndReason.manualStop,
            ConversationVoiceCaptureEndReason.autoStop,
          ],
        );
      },
    );

    test(
      'scope invalidation suppresses a late start and stale auto-stop callback',
      () async {
        final recorder = _ControlledRecorder();
        addTearDown(recorder.dispose);
        final outcomes = <ConversationVoiceCaptureOutcome>[];
        final controller = ConversationVoiceCaptureController(
          onAutoStopOutcome: outcomes.add,
        );
        addTearDown(controller.dispose);
        final startGate = Completer<void>();
        recorder.startGate = startGate;

        final pendingStart = controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        );
        await _flushUntil(() => recorder.startCalls == 1);
        final staleHandler = recorder.onAutoStopped!;

        await controller.invalidateSessionScope();
        expect(controller.scopeGeneration, 1);
        expect(controller.state, ConversationVoiceCaptureViewState.idle);

        void replacementHandler(AudioRecording? _) {}
        recorder.onAutoStopped = replacementHandler;
        startGate.complete();
        final result = await pendingStart;
        expect(result.status, ConversationVoiceCaptureStartStatus.aborted);
        expect(recorder.cancelCalls, 0);
        expect(recorder.onAutoStopped, same(replacementHandler));

        staleHandler(
          AudioRecording(
            filePath: '/tmp/stale.m4a',
            durationMs: 300000,
            sizeBytes: 2048,
          ),
        );
        await _flushEvents();
        expect(outcomes, isEmpty);
        expect(recorder.onAutoStopped, same(replacementHandler));
      },
    );
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _flushUntil(bool Function() condition) async {
  for (var index = 0; index < 20 && !condition(); index++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _ControlledRecorder implements AudioRecorderService {
  final _durationController = StreamController<Duration>.broadcast();
  final _amplitudeController = StreamController<double>.broadcast();

  Completer<void>? startGate;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool _isRecording = false;

  @override
  void Function(AudioRecording? recording)? onAutoStopped;

  @override
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  bool get isRecording => _isRecording;

  @override
  Future<void> start({required String outputPath}) async {
    startCalls++;
    final gate = startGate;
    if (gate != null) await gate.future;
    _isRecording = true;
  }

  @override
  Future<AudioRecording?> stop() async {
    stopCalls++;
    if (!_isRecording) return null;
    _isRecording = false;
    return AudioRecording(
      filePath: '/tmp/voice.m4a',
      durationMs: 2000,
      sizeBytes: 2048,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _isRecording = false;
  }

  void emitDuration(Duration value) => _durationController.add(value);

  void emitAmplitude(double value) => _amplitudeController.add(value);

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> dispose() async {
    await _durationController.close();
    await _amplitudeController.close();
  }
}
