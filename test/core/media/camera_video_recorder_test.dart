import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/camera_video_recorder.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);
const _front = CameraDescription(
  name: 'front',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

/// Only the camera plugin's platform boundary is replaced. Its real
/// CameraController and the app's gesture/record/close paths execute.
class _Camera extends CameraPlatform {
  _Camera(this.file);
  final File file;
  final initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();
  List<CameraDescription> cameras = [_back, _front];
  final created = <CameraDescription>[];
  final settings = <MediaSettings>[];
  final captures = <VideoCaptureOptions>[];
  final switches = <CameraDescription>[];
  final disposed = <int>[];
  int stops = 0;
  Completer<void>? createGate;
  Completer<void>? switchGate;
  Completer<void>? startGate;
  PlatformException? createError;
  Object? switchError;

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    await createGate?.future;
    if (createError case final error?) throw error;
    created.add(description);
    settings.add(mediaSettings);
    return created.length;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((event) => event.cameraId == cameraId);

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initialized.add(
      CameraInitializedEvent.fromJson({
        'cameraId': cameraId,
        'previewWidth': 1280.0,
        'previewHeight': 720.0,
        'exposureMode': 'auto',
        'focusMode': 'auto',
        'exposurePointSupported': true,
        'focusPointSupported': true,
      }),
    );
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    captures.add(options);
    await startGate?.future;
  }

  @override
  Future<void> setDescriptionWhileRecording(
    CameraDescription description,
  ) async {
    switches.add(description);
    await switchGate?.future;
    if (switchError case final error?) throw error;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stops++;
    return XFile(file.path);
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposed.add(cameraId);
  }

  Future<void> close() async {
    // Complete the plugin's pending error-event reads only after its real
    // controllers are disposed, then close the fake streams cleanly.
    for (var id = 1; id <= created.length; id++) {
      errors.add(CameraErrorEvent(id, 'fixture teardown'));
    }
    await initialized.close();
    await errors.close();
  }
}

void main() {
  late _Camera platform;
  late Directory directory;
  late CameraPlatform original;
  XFile? result;
  Object? error;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('camera-video-test-');
    final file = File('${directory.path}/clip.mp4');
    await file.writeAsBytes([1, 2, 3]);
    platform = _Camera(file);
    original = CameraPlatform.instance;
    CameraPlatform.instance = platform;
    result = null;
    error = null;
  });

  tearDown(() async {
    CameraPlatform.instance = original;
    await platform.close();
    await directory.delete(recursive: true);
  });

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  result = await captureCameraVideo(context);
                } catch (caught) {
                  error = caught;
                }
              },
              child: const Text('open camera'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open camera'));
    await frames(tester);
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('camera-video-record')));
    await frames(tester);
  }

  Future<void> doubleTap(WidgetTester tester) async {
    final preview = find.byKey(const ValueKey('camera-video-preview'));
    await tester.tap(preview);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(preview);
    await frames(tester);
  }

  testWidgets(
    'double-tap changes both lenses inside one persistent audio clip',
    (tester) async {
      await open(tester);
      await start(tester);
      expect(platform.created, [_back]);
      expect(platform.settings.single.enableAudio, isTrue);
      expect(platform.captures.single.enablePersistentRecording, isTrue);
      await doubleTap(tester);
      await doubleTap(tester);
      expect(platform.switches, [_front, _back]);
      expect(platform.captures, hasLength(1));
      expect(platform.created, hasLength(1));
      expect(platform.stops, 0, reason: 'flipping must not end the clip');

      await tester.tap(find.byKey(const ValueKey('camera-video-record')));
      await frames(tester);
      expect(platform.stops, 1);
      expect(platform.disposed, [1]);
      expect(result?.path, platform.file.path);
      expect(await platform.file.exists(), isTrue);
      expect(error, isNull);
    },
  );

  for (final keep in [true, false]) {
    testWidgets(
      'a pending flip is serialized with ${keep ? 'stop' : 'cancel'}',
      (tester) async {
        await open(tester);
        await start(tester);
        platform.switchGate = Completer<void>();
        await doubleTap(tester);
        await doubleTap(tester);
        expect(platform.switches, [_front]);
        await tester.tap(
          find.byKey(
            ValueKey(keep ? 'camera-video-record' : 'camera-video-cancel'),
          ),
        );
        await frames(tester);
        expect(platform.stops, 0);
        expect(platform.disposed, isEmpty);
        platform.switchGate!.complete();
        await frames(tester);
        expect(platform.captures, hasLength(1));
        expect(platform.stops, 1);
        expect(platform.disposed, [1]);
        expect(result?.path, keep ? platform.file.path : null);
        expect(await platform.file.exists(), keep);
        expect(error, isNull);
      },
    );
  }

  testWidgets('a failed flip keeps the recording stoppable and retryable', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    platform.switchError = PlatformException(code: 'camera-in-use');
    await doubleTap(tester);
    expect(find.text("Couldn't switch cameras."), findsOneWidget);
    platform.switchError = null;
    await doubleTap(tester);
    expect(platform.switches, [_front, _front]);
    expect(platform.captures, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('camera-video-record')));
    await frames(tester);
    expect(result?.path, platform.file.path);
    expect(error, isNull);
  });

  testWidgets(
    'a lens chosen before recording becomes the initial capture lens',
    (tester) async {
      await open(tester);
      await doubleTap(tester);
      expect(platform.created, [_back, _front]);
      await start(tester);
      expect(platform.captures.single.cameraId, 2);
      await tester.tap(find.byKey(const ValueKey('camera-video-record')));
      await frames(tester);
      expect(platform.disposed, [1, 2]);
      expect(result?.path, platform.file.path);
    },
  );

  testWidgets(
    'cancel waits for a pending recording start and removes its clip',
    (tester) async {
      await open(tester);
      platform.startGate = Completer<void>();
      await start(tester);
      await tester.tap(find.byKey(const ValueKey('camera-video-cancel')));
      await frames(tester);
      expect(platform.stops, 0);
      platform.startGate!.complete();
      await frames(tester);
      expect(platform.stops, 1);
      expect(platform.disposed, [1]);
      expect(result, isNull);
      expect(await platform.file.exists(), isFalse);
    },
  );

  testWidgets('system back cancels and releases an active recording', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    await tester.binding.handlePopRoute();
    await frames(tester);
    expect(platform.stops, 1);
    expect(platform.disposed, [1]);
    expect(result, isNull);
    expect(await platform.file.exists(), isFalse);
    expect(find.byType(CameraVideoRecorder), findsNothing);
  });

  testWidgets('one camera still records without offering an unavailable flip', (
    tester,
  ) async {
    platform.cameras = [_back];
    await open(tester);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('camera-video-switch')))
          .onPressed,
      isNull,
    );
    await start(tester);
    await doubleTap(tester);
    expect(platform.switches, isEmpty);
    await tester.tap(find.byKey(const ValueKey('camera-video-record')));
    await frames(tester);
    expect(result?.path, platform.file.path);
  });

  testWidgets('backgrounding stops capture and retains the interrupted clip', (
    tester,
  ) async {
    await open(tester);
    await start(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await frames(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(platform.stops, 1);
    expect(platform.disposed, [1]);
    expect(result?.path, platform.file.path);
    expect(await platform.file.exists(), isTrue);
  });

  testWidgets(
    'background during initialization cannot leave a late camera open',
    (tester) async {
      platform.createGate = Completer<void>();
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await frames(tester);
      platform.createGate!.complete();
      await frames(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(platform.disposed, [1]);
      expect(platform.captures, isEmpty);
      expect(result, isNull);
      expect(find.byType(CameraVideoRecorder), findsNothing);
    },
  );

  for (final denial in [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'AudioAccessDenied',
    'AudioAccessDeniedWithoutPrompt',
    'AudioAccessRestricted',
  ]) {
    testWidgets('$denial reaches the existing permission recovery boundary', (
      tester,
    ) async {
      platform.createError = PlatformException(code: denial);
      await open(tester);
      expect(error, isA<PlatformException>());
      expect(
        (error! as PlatformException).code,
        denial.startsWith('Camera')
            ? 'camera_access_denied'
            : 'audio_access_denied',
      );
      expect(platform.captures, isEmpty);
      expect(find.byType(CameraVideoRecorder), findsNothing);
    });
  }
}
