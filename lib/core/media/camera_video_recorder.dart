import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Returns one clip, including any front/back changes made while recording.
Future<XFile?> captureCameraVideo(BuildContext context) async {
  final result = await Navigator.of(context).push<_CameraCaptureOutcome>(
    MaterialPageRoute(builder: (_) => const CameraVideoRecorder()),
  );
  if (result?.error case final error?) {
    if (error is CameraException) {
      final code = switch (error.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' => 'camera_access_denied',
        'AudioAccessDenied' ||
        'AudioAccessDeniedWithoutPrompt' ||
        'AudioAccessRestricted' => 'audio_access_denied',
        _ => error.code,
      };
      throw PlatformException(code: code, message: error.description);
    }
    throw error;
  }
  return result?.file;
}

class _CameraCaptureOutcome {
  const _CameraCaptureOutcome({this.file, this.error});
  final XFile? file;
  final Object? error;
}

class CameraVideoRecorder extends StatefulWidget {
  const CameraVideoRecorder({super.key});

  @override
  State<CameraVideoRecorder> createState() => _CameraVideoRecorderState();
}

class _CameraVideoRecorderState extends State<CameraVideoRecorder>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  Future<void>? _operation;
  bool _busy = false;
  bool _ending = false;
  bool _disposed = false;
  final _elapsed = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run(_initialize);
  }

  Future<void> _initialize() async {
    _cameras = await availableCameras();
    if (_ending) return;
    if (_cameras.isEmpty) {
      throw CameraException('camera_unavailable', 'No cameras are available.');
    }
    final back = _cameras.where(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    final controller = CameraController(
      back.firstOrNull ?? _cameras.first,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _camera = controller;
    controller.addListener(_cameraChanged);
    await controller.initialize();
  }

  void _cameraChanged() {
    if (!_disposed && mounted && !_ending) setState(() {});
  }

  // One native transition at a time. Finishing/cancelling joins the current
  // transition before stopping and releasing its controller.
  void _run(Future<void> Function() action, {bool switching = false}) {
    if (_busy || _ending) return;
    setState(() => _busy = true);
    _operation = Future<void>.sync(action)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (switching) {
              if (!_disposed && mounted && !_ending) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.camera_switch_failed,
                    ),
                  ),
                );
              }
            } else {
              unawaited(_end(error: error));
            }
          },
        )
        .whenComplete(() {
          _busy = false;
          if (!_disposed && mounted && !_ending) setState(() {});
        });
  }

  CameraDescription? get _otherCamera {
    final direction = _camera?.description.lensDirection;
    final other = direction == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    return _cameras
        .where((camera) => camera.lensDirection == other)
        .firstOrNull;
  }

  void _switchCamera() {
    final camera = _camera;
    final other = _otherCamera;
    if (camera == null || !camera.value.isInitialized || other == null) return;
    // Recording switches preserve one clip. Preview replacement releases the
    // old camera first, so a failed replacement must exit for a fresh retry.
    _run(
      () => camera.setDescription(other),
      switching: camera.value.isRecordingVideo,
    );
  }

  void _startRecording() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    _run(() async {
      // CameraX needs a persistent recording to retain the same clip/audio
      // while the capture input is rebound to the opposite lens.
      await camera.startVideoRecording(enablePersistentRecording: true);
      if (_ending) return;
      _elapsed.start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed && mounted && !_ending) setState(() {});
      });
    });
  }

  Future<void> _discard(XFile file) async {
    if (kIsWeb) return;
    try {
      await File(file.path).delete();
    } on FileSystemException {
      // A cancelled capture may already have been removed by the platform.
    }
  }

  Future<void> _end({bool keep = false, Object? error}) async {
    if (_ending) return;
    _ending = true;
    _ticker?.cancel();
    _elapsed.stop();
    final camera = _camera;
    _camera = null;
    camera?.removeListener(_cameraChanged);
    if (!_disposed && mounted) setState(() {});
    await _operation;

    XFile? file;
    var failure = error;
    try {
      if (camera != null && camera.value.isRecordingVideo) {
        file = await camera.stopVideoRecording();
      }
    } catch (caught) {
      failure ??= caught;
    } finally {
      try {
        await camera?.dispose();
      } catch (caught) {
        failure ??= caught;
      }
    }
    if (file != null && (!keep || failure != null || _disposed)) {
      await _discard(file);
      file = null;
    }
    if (!_disposed && mounted) {
      Navigator.of(
        context,
      ).pop(_CameraCaptureOutcome(file: keep ? file : null, error: failure));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts can make the app inactive during initialization.
    // Once capture is active, explicitly stop it instead of letting a
    // persistent recording continue behind another app or a locked screen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive &&
            (_camera?.value.isInitialized ?? false))) {
      unawaited(_end(keep: true));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_end());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    final recording = camera?.value.isRecordingVideo ?? false;
    final other = _otherCamera;
    final duration = _elapsed.elapsed.inSeconds;
    final timer =
        '${(duration ~/ 60).toString().padLeft(2, '0')}:'
        '${(duration % 60).toString().padLeft(2, '0')}';
    return PopScope<_CameraCaptureOutcome>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_end());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('camera-video-cancel'),
                    tooltip: l10n.btn_cancel,
                    color: Colors.white,
                    onPressed: _ending ? null : () => unawaited(_end()),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      recording ? timer : l10n.picker_record_video,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('camera-video-switch'),
                    tooltip: l10n.camera_switch,
                    color: Colors.white,
                    onPressed: ready && !_busy && !_ending && other != null
                        ? _switchCamera
                        : null,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
                ],
              ),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('camera-video-preview'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: ready && !_busy && !_ending && other != null
                      ? _switchCamera
                      : null,
                  child: Center(
                    child: camera != null && ready && !_ending
                        ? CameraPreview(camera)
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
              if (other != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.camera_double_tap_hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: IconButton.filled(
                  key: const ValueKey('camera-video-record'),
                  tooltip: recording
                      ? l10n.camera_stop_recording
                      : l10n.picker_record_video,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(72, 72),
                  ),
                  onPressed: !ready || _ending || (!recording && _busy)
                      ? null
                      : recording
                      ? () => unawaited(_end(keep: true))
                      : _startRecording,
                  icon: Icon(recording ? Icons.stop : Icons.videocam),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
