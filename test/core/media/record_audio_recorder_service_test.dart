import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/media_audio_session.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

import '../../shared/fakes/fake_upload_wake_lock_driver.dart';

/// In-file fake of the `record` package's [AudioRecorder].
///
/// Only the members [RecordAudioRecorderService] actually touches are
/// implemented explicitly; everything else falls through to [noSuchMethod] so
/// record minor-version upgrades that add members keep this fake compiling.
class _FakeAudioRecorder implements AudioRecorder {
  bool throwOnStart = false;
  bool throwOnStop = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? stopReturnsPath;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    startCalls += 1;
    if (throwOnStart) {
      throw StateError('forced start failure');
    }
  }

  @override
  Future<String?> stop() async {
    stopCalls += 1;
    if (throwOnStop) {
      throw StateError('forced stop failure');
    }
    return stopReturnsPath;
  }

  int pauseCalls = 0;
  int resumeCalls = 0;

  Completer<void>? pauseGate;

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    await pauseGate?.future;
  }

  Completer<void>? resumeGate;

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    await resumeGate?.future;
  }

  @override
  Future<void> dispose() async {}

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      Stream<Amplitude>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Simulates wakelock_plus failing at the platform layer (e.g. Android
/// NoActivityException when the activity is detached).
class _ThrowingEnableDriver implements UploadWakeLockDriver {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async {
    enableCalls += 1;
    throw StateError('wakelock requires a foreground activity');
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
  }
}

void main() {
  // Explicit output path on every start(): an empty path falls through to
  // getTemporaryDirectory(), a platform channel unavailable in `flutter test`.
  const testOutputPath = '/tmp/wake_lock_test.m4a';

  late _FakeAudioRecorder fakeRecorder;
  late FakeUploadWakeLockDriver fakeDriver;
  late RecordAudioRecorderService service;

  setUp(() {
    fakeRecorder = _FakeAudioRecorder();
    fakeDriver = FakeUploadWakeLockDriver();
    UploadWakeLockController.debugReset(driver: fakeDriver);
    service = RecordAudioRecorderService(recorder: fakeRecorder);
  });

  tearDown(() async {
    await service.dispose();
    // The controller is static — never leak holds into other test files.
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  test(
    'finalized M4A duration defines sent metadata without altering audio',
    () async {
      final directory = await Directory.systemTemp.createTemp('r2-recording-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/encoded.m4a';
      final bytes = Uint8List(40);
      final data = ByteData.sublistView(bytes);
      data.setUint32(0, 40);
      bytes.setRange(4, 8, 'moov'.codeUnits);
      data.setUint32(8, 32);
      bytes.setRange(12, 16, 'mvhd'.codeUnits);
      data.setUint32(28, 1000);
      data.setUint32(32, 17000);
      await File(path).writeAsBytes(bytes);
      fakeRecorder.stopReturnsPath = path;
      await service.start(outputPath: path);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      final recording = await service.stop();
      expect(recording!.durationMs, 17000);
      expect(await File(path).readAsBytes(), bytes);
    },
  );

  group('wake lock on start/stop', () {
    test(
      'start() acquires the wake lock after recorder start succeeds',
      () async {
        await service.start(outputPath: testOutputPath);

        expect(UploadWakeLockController.debugActiveHolds, 1);
        expect(fakeDriver.enableCalls, 1);
      },
    );

    test('stop() releases the wake lock', () async {
      await service.start(outputPath: testOutputPath);
      await service.stop();

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(fakeDriver.disableCalls, 1);
    });

    test(
      'stop() when never started does not release an external hold',
      () async {
        // Simulates a concurrent upload holding the shared ref-counted lock.
        await UploadWakeLockController.acquire();

        await service.stop();

        expect(UploadWakeLockController.debugActiveHolds, 1);
        expect(fakeDriver.disableCalls, 0);
      },
    );
  });

  group('wake lock on cancel/dispose', () {
    test('cancel() releases the wake lock', () async {
      await service.start(outputPath: testOutputPath);
      await service.cancel();

      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    test('dispose() while recording releases the wake lock', () async {
      await service.start(outputPath: testOutputPath);
      await service.dispose();

      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    test('stop() then cancel() then dispose() releases exactly once', () async {
      await service.start(outputPath: testOutputPath);
      await service.stop();
      await service.cancel();
      await service.dispose();

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(fakeDriver.disableCalls, 1);
    });
  });

  group('wake lock on failure paths', () {
    test('start() failure does not acquire the wake lock', () async {
      fakeRecorder.throwOnStart = true;

      await expectLater(
        service.start(outputPath: testOutputPath),
        throwsA(isA<StateError>()),
      );

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(fakeDriver.enableCalls, 0);
    });

    test('stop() releases even when the plugin stop throws', () async {
      await service.start(outputPath: testOutputPath);
      fakeRecorder.throwOnStop = true;

      await expectLater(service.stop(), throwsA(isA<StateError>()));

      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    test('cancel() releases even when the plugin stop throws', () async {
      await service.start(outputPath: testOutputPath);
      fakeRecorder.throwOnStop = true;

      await expectLater(service.cancel(), throwsA(isA<StateError>()));

      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    test(
      'start() rolls back fully when the wake-lock driver enable throws',
      () async {
        final throwingDriver = _ThrowingEnableDriver();
        UploadWakeLockController.debugReset(driver: throwingDriver);

        await expectLater(
          service.start(outputPath: testOutputPath),
          throwsA(isA<StateError>()),
        );

        // Invariant the UI relies on: throw out of start() == service holds
        // nothing — no counted hold, not recording, plugin recording stopped.
        expect(UploadWakeLockController.debugActiveHolds, 0);
        expect(service.isRecording, isFalse);
        expect(fakeRecorder.stopCalls, 1);

        // The controller is not poisoned: a later recording works normally.
        UploadWakeLockController.debugReset(driver: fakeDriver);
        await service.start(outputPath: testOutputPath);
        expect(UploadWakeLockController.debugActiveHolds, 1);
        await service.stop();
        expect(UploadWakeLockController.debugActiveHolds, 0);
      },
    );

    test(
      'second start() failing after force-stop leaves no held lock',
      () async {
        await service.start(outputPath: testOutputPath);
        fakeRecorder.throwOnStart = true;

        await expectLater(
          service.start(outputPath: testOutputPath),
          throwsA(isA<StateError>()),
        );

        expect(UploadWakeLockController.debugActiveHolds, 0);
        expect(fakeDriver.disableCalls, 1);
      },
    );
  });

  group('audio session handed back', () {
    late int deactivations;
    setUp(() {
      deactivations = 0;
      MediaAudioSession.debugDeactivate = () async => deactivations++;
    });
    tearDown(() {
      MediaAudioSession.debugDeactivate = null;
      MediaAudioSession.callOwnsSession = MediaAudioSession.noCall;
    });

    test('stop() hands the session back', () async {
      await service.start(outputPath: testOutputPath);
      await service.stop();
      expect(deactivations, 1);
    });

    test('cancel() hands the session back', () async {
      await service.start(outputPath: testOutputPath);
      await service.cancel();
      expect(deactivations, 1);
    });

    test('dispose() while recording hands the session back', () async {
      await service.start(outputPath: testOutputPath);
      await service.dispose();
      expect(deactivations, 1);
    });

    test('dispose() without a recording leaves the session alone', () async {
      await service.dispose();
      expect(deactivations, 0);
    });

    test('during a call the session is left to the call', () async {
      MediaAudioSession.callOwnsSession = () => true;
      await service.start(outputPath: testOutputPath);
      await service.stop();
      expect(deactivations, 0);
    });

    test('stop() hands the session back even when the plugin stop throws',
        () async {
      await service.start(outputPath: testOutputPath);
      fakeRecorder.throwOnStop = true;
      await expectLater(service.stop(), throwsA(anything));
      expect(deactivations, 1);
    });
  });

  group('wake lock on auto-stop', () {
    test('auto-stop at max duration releases the wake lock', () async {
      await service.dispose();
      service = RecordAudioRecorderService(
        recorder: fakeRecorder,
        maxDuration: const Duration(milliseconds: 50),
      );

      await service.start(outputPath: testOutputPath);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(service.isRecording, isFalse);
      expect(UploadWakeLockController.debugActiveHolds, 0);
    });
  });

  group('auto-stop notification', () {
    test('auto-stop invokes onAutoStopped with the stop result', () async {
      await service.dispose();
      service = RecordAudioRecorderService(
        recorder: fakeRecorder,
        maxDuration: const Duration(milliseconds: 50),
      );
      final captured = <AudioRecording?>[];
      final completed = Completer<void>();
      service.onAutoStopped = (recording) {
        captured.add(recording);
        completed.complete();
      };

      await service.start(outputPath: testOutputPath);
      await completed.future.timeout(const Duration(seconds: 3));

      expect(service.isRecording, isFalse);
      expect(captured, hasLength(1));
      // Sub-500ms recording: stop() reports it as too short (null).
      expect(captured.single, isNull);
    });

    test(
      'auto-stop yields a non-null recording for a full-length capture',
      () async {
        // 117 Session 3 depends on the auto-stop handing back a VALID
        // recording (not null) so it can be held for review rather than
        // silently discarded. Guard that seam: a >=500ms capture with a real
        // file produces a non-null AudioRecording at the limit.
        await service.dispose();
        service = RecordAudioRecorderService(
          recorder: fakeRecorder,
          maxDuration: const Duration(milliseconds: 550),
        );
        final captureFile = File(
          '${Directory.systemTemp.path}/autostop_capture_'
          '${DateTime.now().microsecondsSinceEpoch}.m4a',
        )..writeAsBytesSync(List<int>.filled(2048, 7));
        addTearDown(() {
          if (captureFile.existsSync()) captureFile.deleteSync();
        });
        fakeRecorder.stopReturnsPath = captureFile.path;

        final captured = <AudioRecording?>[];
        final completed = Completer<void>();
        service.onAutoStopped = (recording) {
          captured.add(recording);
          completed.complete();
        };

        await service.start(outputPath: testOutputPath);
        await completed.future.timeout(const Duration(seconds: 3));

        expect(service.isRecording, isFalse);
        expect(captured, hasLength(1));
        expect(captured.single, isNotNull);
        expect(captured.single!.filePath, captureFile.path);
        expect(captured.single!.sizeBytes, 2048);
        expect(captured.single!.durationMs, greaterThanOrEqualTo(500));
      },
    );

    test('manual stop() does not invoke onAutoStopped', () async {
      var calls = 0;
      service.onAutoStopped = (_) => calls += 1;

      await service.start(outputPath: testOutputPath);
      await service.stop();

      expect(calls, 0);
    });

    test('cancel() does not invoke onAutoStopped', () async {
      var calls = 0;
      service.onAutoStopped = (_) => calls += 1;

      await service.start(outputPath: testOutputPath);
      await service.cancel();

      expect(calls, 0);
    });
  });

  group('wake lock on rapid restart', () {
    test('start() while already recording keeps exactly one hold', () async {
      await service.start(outputPath: testOutputPath);
      await service.start(outputPath: testOutputPath);

      expect(UploadWakeLockController.debugActiveHolds, 1);
      // Pins the release/re-acquire cycle, not a no-op carry-over of the
      // first hold: the force-stop branch must release before the fresh
      // acquire.
      expect(fakeDriver.enableCalls, 2);
      expect(fakeDriver.disableCalls, 1);

      await service.stop();
      expect(UploadWakeLockController.debugActiveHolds, 0);
    });

    test('rapid start/stop/start/stop ends at zero holds', () async {
      await service.start(outputPath: testOutputPath);
      await service.stop();
      await service.start(outputPath: testOutputPath);
      await service.stop();

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(fakeDriver.enableCalls, fakeDriver.disableCalls);
    });
  });

  group('pause and resume', () {
    test('pause and resume reach the recorder; the mic stays held', () async {
      await service.start(outputPath: testOutputPath);

      await service.pause();
      expect(fakeRecorder.pauseCalls, 1);
      expect(service.isPaused, isTrue);
      expect(service.isRecording, isTrue);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      await service.resume();
      expect(fakeRecorder.resumeCalls, 1);
      expect(service.isPaused, isFalse);
    });

    test('the clock stops while paused', () async {
      await service.start(outputPath: testOutputPath);
      final ticks = <Duration>[];
      final sub = service.durationStream.listen(ticks.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      await service.pause();
      final pausedAt = ticks.last;
      final count = ticks.length;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(ticks.length, count);

      await service.resume();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        ticks.last - pausedAt,
        lessThan(const Duration(milliseconds: 400)),
      );
    });

    test('a pause holds off the auto-stop by the time it lasted', () async {
      final short = RecordAudioRecorderService(
        recorder: fakeRecorder,
        maxDuration: const Duration(milliseconds: 300),
      );
      addTearDown(short.dispose);
      var autoStops = 0;
      short.onAutoStopped = (_) => autoStops += 1;
      await short.start(outputPath: testOutputPath);
      await short.pause();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(autoStops, 0);

      await short.resume();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(autoStops, 1);
    });

    test(
      'a resume still pending at cancel cannot stop the next recording',
      () async {
        final short = RecordAudioRecorderService(
          recorder: fakeRecorder,
          maxDuration: const Duration(milliseconds: 300),
        );
        addTearDown(short.dispose);
        final autoStops = <AudioRecording?>[];
        short.onAutoStopped = autoStops.add;
        await short.start(outputPath: testOutputPath);
        // Most of the 300 ms is used, so a stale clock would fire first.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await short.pause();
        final gate = fakeRecorder.resumeGate = Completer<void>();
        final resuming = short.resume();
        await short.cancel();
        gate.complete();
        await resuming;

        await short.start(outputPath: testOutputPath);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(short.isRecording, isTrue, reason: 'old clock stopped it');
        expect(autoStops, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(autoStops, hasLength(1), reason: 'its own clock still runs');
      },
    );

    test(
      'a resume still pending at stop cannot stop the next recording',
      () async {
        final short = RecordAudioRecorderService(
          recorder: fakeRecorder,
          maxDuration: const Duration(milliseconds: 300),
        );
        addTearDown(short.dispose);
        var autoStops = 0;
        short.onAutoStopped = (_) => autoStops += 1;
        await short.start(outputPath: testOutputPath);
        // Most of the 300 ms is used, so a stale clock would fire first.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await short.pause();
        final gate = fakeRecorder.resumeGate = Completer<void>();
        final resuming = short.resume();
        await short.stop();
        gate.complete();
        await resuming;
        await short.start(outputPath: testOutputPath);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(short.isRecording, isTrue, reason: 'old clock stopped it');
        expect(autoStops, 0);
      },
    );

    test('a second resume while one is pending runs one clock', () async {
      final short = RecordAudioRecorderService(
        recorder: fakeRecorder,
        maxDuration: const Duration(milliseconds: 300),
      );
      addTearDown(short.dispose);
      var autoStops = 0;
      short.onAutoStopped = (_) => autoStops += 1;
      await short.start(outputPath: testOutputPath);
      await short.pause();
      final gate = fakeRecorder.resumeGate = Completer<void>();
      final first = short.resume();
      final second = short.resume();
      gate.complete();
      await Future.wait([first, second]);
      expect(fakeRecorder.resumeCalls, 1);
      final ticks = <Duration>[];
      final sub = short.durationStream.listen(ticks.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(ticks.length, lessThan(4), reason: 'one ticker, 100 ms apart');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(autoStops, 1);
    });

    test('a second pause while one is pending counts the time once', () async {
      final short = RecordAudioRecorderService(
        recorder: fakeRecorder,
        maxDuration: const Duration(milliseconds: 400),
      );
      addTearDown(short.dispose);
      var autoStops = 0;
      short.onAutoStopped = (_) => autoStops += 1;
      await short.start(outputPath: testOutputPath);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final gate = fakeRecorder.pauseGate = Completer<void>();
      final first = short.pause();
      final second = short.pause();
      gate.complete();
      await Future.wait([first, second]);
      expect(fakeRecorder.pauseCalls, 1);
      expect(short.isPaused, isTrue);

      await short.resume();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(autoStops, 0, reason: 'about 250 ms of 400 were left');
      expect(short.isRecording, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(autoStops, 1);
    });

    test('pause and resume before start do nothing', () async {
      await service.pause();
      await service.resume();
      expect(fakeRecorder.pauseCalls, 0);
      expect(fakeRecorder.resumeCalls, 0);
    });
  });
}
