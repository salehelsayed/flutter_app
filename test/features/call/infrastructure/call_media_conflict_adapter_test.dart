import 'dart:async';

import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/infrastructure/call_media_conflict_adapter.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_voice_capture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refuses call capture while voice-note recording owns microphone', () {
    final conflicts = CallMediaConflictAdapter(
      isVoiceNoteRecording: () => true,
    );

    expect(conflicts.acquireForCall, throwsA(isA<CallMediaConflictRefused>()));
  });

  test('idle recorder grants one idempotent conflict lease', () async {
    var checks = 0;
    final conflicts = CallMediaConflictAdapter(
      isVoiceNoteRecording: () {
        checks++;
        return false;
      },
    );

    final lease = await conflicts.acquireForCall();
    await lease.release();
    await lease.release();

    expect(checks, 1);
  });

  test(
    'lease ownership is exclusive and stale release cannot clear it',
    () async {
      final conflicts = CallMediaConflictAdapter(
        isVoiceNoteRecording: () => false,
      );

      final first = await conflicts.acquireForCall();
      await expectLater(
        conflicts.acquireForCall(),
        throwsA(isA<CallMediaConflictRefused>()),
      );
      await first.release();

      final second = await conflicts.acquireForCall();
      await first.release();
      await expectLater(
        conflicts.acquireForCall(),
        throwsA(isA<CallMediaConflictRefused>()),
      );
      await second.release();
      await (await conflicts.acquireForCall()).release();
    },
  );

  test(
    'voice-note arming excludes call capture until permission denial exits',
    () async {
      final recorder = _RecorderSpy();
      addTearDown(recorder.dispose);
      final controller = ConversationVoiceCaptureController();
      addTearDown(controller.dispose);
      final permission = Completer<MicPermissionStatus>();
      final conflicts = CallMediaConflictAdapter(
        microphoneCaptureLeases: microphoneCaptureLeasesFor(recorder),
      );

      final arming = controller.start(
        recorder: recorder,
        requestPermission: () => permission.future,
      );
      expect(controller.state.phase, ConversationVoiceCapturePhase.arming);

      await expectLater(
        conflicts.acquireForCall(),
        throwsA(isA<CallMediaConflictRefused>()),
      );

      permission.complete(MicPermissionStatus.denied);
      final denied = await arming;
      expect(
        denied.status,
        ConversationVoiceCaptureStartStatus.permissionDenied,
      );

      final callLease = await conflicts.acquireForCall();
      await callLease.release();
      await callLease.release();
      expect(recorder.startCalls, 0);
      expect(recorder.stopCalls, 0);
      expect(recorder.cancelCalls, 0);
    },
  );

  test(
    'voice-note permission failure releases shared microphone lease',
    () async {
      final recorder = _RecorderSpy();
      addTearDown(recorder.dispose);
      final controller = ConversationVoiceCaptureController();
      addTearDown(controller.dispose);
      final conflicts = CallMediaConflictAdapter(
        microphoneCaptureLeases: microphoneCaptureLeasesFor(recorder),
      );

      final failed = await controller.start(
        recorder: recorder,
        requestPermission: () => Future<MicPermissionStatus>.error(
          StateError('permission unavailable'),
        ),
      );

      expect(failed.status, ConversationVoiceCaptureStartStatus.failed);
      final callLease = await conflicts.acquireForCall();
      await callLease.release();
      expect(recorder.startCalls, 0);
    },
  );

  test(
    'call lease excludes voice-note arming without requesting permission',
    () async {
      final recorder = _RecorderSpy();
      addTearDown(recorder.dispose);
      final controller = ConversationVoiceCaptureController();
      addTearDown(controller.dispose);
      final conflicts = CallMediaConflictAdapter(
        microphoneCaptureLeases: microphoneCaptureLeasesFor(recorder),
      );
      final callLease = await conflicts.acquireForCall();
      var permissionRequests = 0;

      final refused = await controller.start(
        recorder: recorder,
        requestPermission: () async {
          permissionRequests++;
          return MicPermissionStatus.granted;
        },
      );

      expect(refused.status, ConversationVoiceCaptureStartStatus.busy);
      expect(permissionRequests, 0);
      expect(controller.state, ConversationVoiceCaptureViewState.idle);
      await callLease.release();
    },
  );

  test(
    'voice-note lease remains held until stop and cancel cleanup settle',
    () async {
      final recorder = _RecorderSpy();
      addTearDown(recorder.dispose);
      final controller = ConversationVoiceCaptureController();
      addTearDown(controller.dispose);
      final conflicts = CallMediaConflictAdapter(
        microphoneCaptureLeases: microphoneCaptureLeasesFor(recorder),
      );

      expect(
        (await controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        )).status,
        ConversationVoiceCaptureStartStatus.started,
      );
      final stopGate = Completer<void>();
      recorder.stopGate = stopGate;
      final stopping = controller.stop();
      await _flushUntil(() => recorder.stopCalls == 1);
      await expectLater(
        conflicts.acquireForCall(),
        throwsA(isA<CallMediaConflictRefused>()),
      );
      stopGate.complete();
      await stopping;
      final afterStop = await conflicts.acquireForCall();
      await afterStop.release();

      expect(
        (await controller.start(
          recorder: recorder,
          requestPermission: () async => MicPermissionStatus.granted,
        )).status,
        ConversationVoiceCaptureStartStatus.started,
      );
      final cancelGate = Completer<void>();
      recorder.cancelGate = cancelGate;
      final cancelling = controller.cancel();
      await _flushUntil(() => recorder.cancelCalls == 1);
      await expectLater(
        conflicts.acquireForCall(),
        throwsA(isA<CallMediaConflictRefused>()),
      );
      cancelGate.complete();
      await cancelling;
      final afterCancel = await conflicts.acquireForCall();
      await afterCancel.release();
    },
  );

  test('voice-note terminal exits all release the shared lease', () async {
    final failedRecorder = _RecorderSpy()..startError = StateError('start');
    addTearDown(failedRecorder.dispose);
    final failedController = ConversationVoiceCaptureController();
    addTearDown(failedController.dispose);
    final failedConflicts = CallMediaConflictAdapter(
      microphoneCaptureLeases: microphoneCaptureLeasesFor(failedRecorder),
    );
    final failed = await failedController.start(
      recorder: failedRecorder,
      requestPermission: () async => MicPermissionStatus.granted,
    );
    expect(failed.status, ConversationVoiceCaptureStartStatus.failed);
    await (await failedConflicts.acquireForCall()).release();

    final autoRecorder = _RecorderSpy();
    addTearDown(autoRecorder.dispose);
    final autoController = ConversationVoiceCaptureController();
    addTearDown(autoController.dispose);
    final autoConflicts = CallMediaConflictAdapter(
      microphoneCaptureLeases: microphoneCaptureLeasesFor(autoRecorder),
    );
    await autoController.start(
      recorder: autoRecorder,
      requestPermission: () async => MicPermissionStatus.granted,
    );
    autoRecorder.autoStop();
    await (await autoConflicts.acquireForCall()).release();

    final scopedRecorder = _RecorderSpy();
    addTearDown(scopedRecorder.dispose);
    final scopedController = ConversationVoiceCaptureController();
    addTearDown(scopedController.dispose);
    final scopedConflicts = CallMediaConflictAdapter(
      microphoneCaptureLeases: microphoneCaptureLeasesFor(scopedRecorder),
    );
    final permission = Completer<MicPermissionStatus>();
    final scopedStart = scopedController.start(
      recorder: scopedRecorder,
      requestPermission: () => permission.future,
    );
    await scopedController.invalidateSessionScope();
    await (await scopedConflicts.acquireForCall()).release();
    permission.complete(MicPermissionStatus.granted);
    expect(
      (await scopedStart).status,
      ConversationVoiceCaptureStartStatus.aborted,
    );

    final disposedRecorder = _RecorderSpy();
    addTearDown(disposedRecorder.dispose);
    final disposedController = ConversationVoiceCaptureController();
    final disposedConflicts = CallMediaConflictAdapter(
      microphoneCaptureLeases: microphoneCaptureLeasesFor(disposedRecorder),
    );
    await disposedController.start(
      recorder: disposedRecorder,
      requestPermission: () async => MicPermissionStatus.granted,
    );
    final disposeGate = Completer<void>();
    disposedRecorder.cancelGate = disposeGate;
    disposedController.dispose();
    await expectLater(
      disposedConflicts.acquireForCall(),
      throwsA(isA<CallMediaConflictRefused>()),
    );
    disposeGate.complete();
    await _flushUntil(() => !disposedRecorder.isRecording);
    await (await disposedConflicts.acquireForCall()).release();
  });
}

Future<void> _flushUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

final class _RecorderSpy implements AudioRecorderService {
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool _recording = false;
  Object? startError;
  Completer<void>? stopGate;
  Completer<void>? cancelGate;

  @override
  void Function(AudioRecording? recording)? onAutoStopped;

  @override
  Stream<double> get amplitudeStream => _amplitude.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start({required String outputPath}) async {
    startCalls++;
    final error = startError;
    if (error != null) throw error;
    _recording = true;
  }

  @override
  Future<AudioRecording?> stop() async {
    stopCalls++;
    final gate = stopGate;
    if (gate != null) await gate.future;
    _recording = false;
    return null;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final gate = cancelGate;
    if (gate != null) await gate.future;
    _recording = false;
  }

  void autoStop() {
    _recording = false;
    onAutoStopped?.call(null);
  }

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> dispose() async {
    await _duration.close();
    await _amplitude.close();
  }
}
