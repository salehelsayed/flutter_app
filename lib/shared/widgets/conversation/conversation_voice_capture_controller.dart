import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

enum ConversationVoiceCapturePhase { idle, arming, recording, stopping }

enum ConversationVoiceCaptureStartStatus {
  started,
  permissionDenied,
  aborted,
  failed,
  busy,
}

enum ConversationVoiceCaptureEndReason { manualStop, autoStop }

@immutable
class ConversationVoiceCaptureViewState {
  const ConversationVoiceCaptureViewState({
    required this.phase,
    required this.duration,
    required this.amplitudeValues,
  });

  static const idle = ConversationVoiceCaptureViewState(
    phase: ConversationVoiceCapturePhase.idle,
    duration: Duration.zero,
    amplitudeValues: <double>[],
  );

  final ConversationVoiceCapturePhase phase;
  final Duration duration;
  final List<double> amplitudeValues;

  bool get isActive => phase != ConversationVoiceCapturePhase.idle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationVoiceCaptureViewState &&
          phase == other.phase &&
          duration == other.duration &&
          listEquals(amplitudeValues, other.amplitudeValues);

  @override
  int get hashCode =>
      Object.hash(phase, duration, Object.hashAll(amplitudeValues));
}

@immutable
class ConversationVoiceCaptureStartResult {
  const ConversationVoiceCaptureStartResult({
    required this.status,
    required this.scopeGeneration,
    this.permissionStatus,
    this.error,
  });

  final ConversationVoiceCaptureStartStatus status;
  final int scopeGeneration;
  final MicPermissionStatus? permissionStatus;
  final Object? error;
}

@immutable
class ConversationVoiceCaptureOutcome {
  const ConversationVoiceCaptureOutcome({
    required this.reason,
    required this.recording,
    required this.waveform,
    required this.scopeGeneration,
    this.error,
  });

  final ConversationVoiceCaptureEndReason reason;
  final AudioRecording? recording;
  final List<double> waveform;
  final int scopeGeneration;
  final Object? error;

  bool get isTooShort => recording == null && error == null;
}

typedef ConversationVoiceAutoStopOutcome =
    void Function(ConversationVoiceCaptureOutcome outcome);

/// Owns one recorder session's mechanics while leaving every lane decision to
/// its caller.
///
/// The recorder instance and permission request are supplied per [start], so a
/// session always retains the exact recorder it acquired even when a hosting
/// widget is rebuilt with different dependencies. A scope invalidation
/// suppresses late view events and callbacks without confusing that retained
/// operation identity with a newly started session.
class ConversationVoiceCaptureController extends ChangeNotifier {
  ConversationVoiceCaptureController({
    this.amplitudeWindowSize = 25,
    this.waveformSampleCount = 50,
    ConversationVoiceAutoStopOutcome? onAutoStopOutcome,
  }) : assert(amplitudeWindowSize > 0),
       assert(waveformSampleCount > 0),
       _onAutoStopOutcome = onAutoStopOutcome;

  final int amplitudeWindowSize;
  final int waveformSampleCount;

  ConversationVoiceAutoStopOutcome? _onAutoStopOutcome;
  ConversationVoiceCaptureViewState _state =
      ConversationVoiceCaptureViewState.idle;
  _VoiceCaptureSession? _activeSession;
  int _scopeGeneration = 0;
  bool _disposed = false;

  ConversationVoiceCaptureViewState get state => _state;

  int get scopeGeneration => _scopeGeneration;

  bool get hasActiveSession => _activeSession != null;

  set onAutoStopOutcome(ConversationVoiceAutoStopOutcome? callback) {
    _onAutoStopOutcome = callback;
  }

  bool isCurrentOutcome(ConversationVoiceCaptureOutcome outcome) =>
      !_disposed && outcome.scopeGeneration == _scopeGeneration;

  Future<ConversationVoiceCaptureStartResult> start({
    required AudioRecorderService recorder,
    required Future<MicPermissionStatus> Function() requestPermission,
    String outputPath = '',
  }) async {
    if (_disposed || _activeSession != null || _state.isActive) {
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.busy,
        scopeGeneration: _scopeGeneration,
      );
    }

    final session = _VoiceCaptureSession(
      generation: _scopeGeneration,
      recorder: recorder,
      amplitudeWindowSize: amplitudeWindowSize,
    );
    session.autoStopHandler = (recording) {
      _handleAutoStopped(session, recording);
    };
    _activeSession = session;
    _publish(
      const ConversationVoiceCaptureViewState(
        phase: ConversationVoiceCapturePhase.arming,
        duration: Duration.zero,
        amplitudeValues: <double>[],
      ),
    );

    MicPermissionStatus permissionStatus;
    try {
      permissionStatus = await requestPermission();
    } catch (error) {
      _finishArmingWithoutRecorder(session);
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.failed,
        scopeGeneration: session.generation,
        error: error,
      );
    }

    if (!_canContinueArming(session)) {
      _finishArmingWithoutRecorder(session);
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.aborted,
        scopeGeneration: session.generation,
        permissionStatus: permissionStatus,
      );
    }
    if (permissionStatus != MicPermissionStatus.granted) {
      _finishArmingWithoutRecorder(session);
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.permissionDenied,
        scopeGeneration: session.generation,
        permissionStatus: permissionStatus,
      );
    }

    recorder.onAutoStopped = session.autoStopHandler;
    session.startInFlight = true;
    try {
      await recorder.start(outputPath: outputPath);
    } catch (error) {
      session.startInFlight = false;
      _clearOwnedAutoStopHandler(session);
      _finishLocalSession(session);
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.failed,
        scopeGeneration: session.generation,
        permissionStatus: permissionStatus,
        error: error,
      );
    }
    session.startInFlight = false;

    if (!_canContinueArming(session)) {
      await _cancelRecorderAfterCompletedStart(session);
      _finishLocalSession(session);
      return ConversationVoiceCaptureStartResult(
        status: ConversationVoiceCaptureStartStatus.aborted,
        scopeGeneration: session.generation,
        permissionStatus: permissionStatus,
      );
    }

    session.durationSubscription = recorder.durationStream.listen((duration) {
      if (!_ownsLiveSession(session)) return;
      _publish(
        ConversationVoiceCaptureViewState(
          phase: ConversationVoiceCapturePhase.recording,
          duration: duration,
          amplitudeValues: List<double>.unmodifiable(
            session.amplitudeBuffer.values,
          ),
        ),
      );
    });
    session.amplitudeSubscription = recorder.amplitudeStream.listen((value) {
      if (!_ownsLiveSession(session)) return;
      session.amplitudeBuffer.push(value);
      session.waveformSamples.add(value);
      _publish(
        ConversationVoiceCaptureViewState(
          phase: ConversationVoiceCapturePhase.recording,
          duration: _state.duration,
          amplitudeValues: List<double>.unmodifiable(
            session.amplitudeBuffer.values,
          ),
        ),
      );
    });
    _publish(
      ConversationVoiceCaptureViewState(
        phase: ConversationVoiceCapturePhase.recording,
        duration: Duration.zero,
        amplitudeValues: List<double>.unmodifiable(
          session.amplitudeBuffer.values,
        ),
      ),
    );

    return ConversationVoiceCaptureStartResult(
      status: ConversationVoiceCaptureStartStatus.started,
      scopeGeneration: session.generation,
      permissionStatus: permissionStatus,
    );
  }

  Future<ConversationVoiceCaptureOutcome?> stop() async {
    final session = _activeSession;
    if (session == null || session.terminal) return null;
    if (_state.phase == ConversationVoiceCapturePhase.arming ||
        session.startInFlight) {
      _requestArmingAbort(session);
      return null;
    }
    if (!_ownsRecorderCallback(session)) {
      session.terminal = true;
      _detachSessionStreams(session);
      _finishLocalSession(session);
      return null;
    }

    session.terminal = true;
    _publish(
      ConversationVoiceCaptureViewState(
        phase: ConversationVoiceCapturePhase.stopping,
        duration: _state.duration,
        amplitudeValues: _state.amplitudeValues,
      ),
    );
    _clearOwnedAutoStopHandler(session);
    final waveform = _detachSessionStreams(session);

    AudioRecording? recording;
    Object? stopError;
    try {
      recording = await session.recorder.stop();
    } catch (error) {
      stopError = error;
    } finally {
      _finishLocalSession(session);
    }

    return ConversationVoiceCaptureOutcome(
      reason: ConversationVoiceCaptureEndReason.manualStop,
      recording: recording,
      waveform: waveform,
      scopeGeneration: session.generation,
      error: stopError,
    );
  }

  Future<void> cancel() async {
    final session = _activeSession;
    if (session == null || session.terminal) return;
    if (_state.phase == ConversationVoiceCapturePhase.arming ||
        session.startInFlight) {
      _requestArmingAbort(session);
      return;
    }

    session.terminal = true;
    _publish(
      ConversationVoiceCaptureViewState(
        phase: ConversationVoiceCapturePhase.stopping,
        duration: _state.duration,
        amplitudeValues: _state.amplitudeValues,
      ),
    );
    final ownsRecorder = _ownsRecorderCallback(session);
    if (ownsRecorder) _clearOwnedAutoStopHandler(session);
    _detachSessionStreams(session);
    try {
      if (ownsRecorder) await session.recorder.cancel();
    } finally {
      _finishLocalSession(session);
    }
  }

  /// Invalidates view/session generation before a host rebinds to another lane.
  ///
  /// An in-flight `start()` performs its own owner-checked cancellation after
  /// the recorder future settles. A live session is cancelled only when this
  /// controller's exact callback still owns the recorder.
  Future<void> invalidateSessionScope() async {
    final session = _activeSession;
    _scopeGeneration += 1;
    _activeSession = null;
    if (session == null) {
      _publish(ConversationVoiceCaptureViewState.idle);
      return;
    }

    session.abortRequested = true;
    final ownsRecorder = _ownsRecorderCallback(session);
    if (ownsRecorder) _clearOwnedAutoStopHandler(session);
    _detachSessionStreams(session);
    _publish(ConversationVoiceCaptureViewState.idle);
    if (!session.startInFlight && ownsRecorder && !session.terminal) {
      session.terminal = true;
      await session.recorder.cancel();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scopeGeneration += 1;
    _onAutoStopOutcome = null;
    final session = _activeSession;
    _activeSession = null;
    if (session != null) {
      session.abortRequested = true;
      final ownsRecorder = _ownsRecorderCallback(session);
      if (ownsRecorder) _clearOwnedAutoStopHandler(session);
      _detachSessionStreams(session);
      if (!session.startInFlight && ownsRecorder && !session.terminal) {
        session.terminal = true;
        unawaited(session.recorder.cancel());
      }
    }
    super.dispose();
  }

  bool _canContinueArming(_VoiceCaptureSession session) =>
      !_disposed &&
      !session.abortRequested &&
      identical(_activeSession, session) &&
      session.generation == _scopeGeneration;

  bool _ownsRecorderCallback(_VoiceCaptureSession session) =>
      identical(session.recorder.onAutoStopped, session.autoStopHandler);

  bool _ownsLiveSession(_VoiceCaptureSession session) =>
      !session.terminal &&
      _canContinueArming(session) &&
      _ownsRecorderCallback(session);

  void _requestArmingAbort(_VoiceCaptureSession session) {
    session.abortRequested = true;
    _publish(
      ConversationVoiceCaptureViewState(
        phase: ConversationVoiceCapturePhase.stopping,
        duration: _state.duration,
        amplitudeValues: _state.amplitudeValues,
      ),
    );
  }

  void _finishArmingWithoutRecorder(_VoiceCaptureSession session) {
    if (identical(_activeSession, session)) {
      _activeSession = null;
    }
    if (!_disposed && session.generation == _scopeGeneration) {
      _publish(ConversationVoiceCaptureViewState.idle);
    }
  }

  Future<void> _cancelRecorderAfterCompletedStart(
    _VoiceCaptureSession session,
  ) async {
    final currentHandler = session.recorder.onAutoStopped;
    if (!identical(currentHandler, session.autoStopHandler) &&
        currentHandler != null) {
      return;
    }
    if (identical(currentHandler, session.autoStopHandler)) {
      session.recorder.onAutoStopped = null;
    }
    try {
      await session.recorder.cancel();
    } catch (_) {
      // Local ownership is already cleared. The caller receives `aborted`
      // regardless of a best-effort recorder cleanup failure.
    }
  }

  void _clearOwnedAutoStopHandler(_VoiceCaptureSession session) {
    if (_ownsRecorderCallback(session)) {
      session.recorder.onAutoStopped = null;
    }
  }

  List<double> _detachSessionStreams(_VoiceCaptureSession session) {
    final durationSubscription = session.durationSubscription;
    session.durationSubscription = null;
    if (durationSubscription != null) {
      unawaited(durationSubscription.cancel());
    }
    final amplitudeSubscription = session.amplitudeSubscription;
    session.amplitudeSubscription = null;
    if (amplitudeSubscription != null) {
      unawaited(amplitudeSubscription.cancel());
    }
    final waveform = List<double>.unmodifiable(
      downsampleWaveform(session.waveformSamples, waveformSampleCount),
    );
    session.amplitudeBuffer.reset();
    session.waveformSamples.clear();
    return waveform;
  }

  void _finishLocalSession(_VoiceCaptureSession session) {
    if (identical(_activeSession, session)) {
      _activeSession = null;
    }
    if (!_disposed && session.generation == _scopeGeneration) {
      _publish(ConversationVoiceCaptureViewState.idle);
    }
  }

  void _handleAutoStopped(
    _VoiceCaptureSession session,
    AudioRecording? recording,
  ) {
    if (_disposed || session.terminal || !_ownsLiveSession(session)) {
      return;
    }
    session.terminal = true;
    _clearOwnedAutoStopHandler(session);
    final waveform = _detachSessionStreams(session);
    if (identical(_activeSession, session)) {
      _activeSession = null;
    }

    // The lane callback owns the final composer projection. Updating the
    // controller's snapshot without notifying avoids an intermediate terminal
    // publication that could overwrite the adapter's chosen presentation.
    _state = ConversationVoiceCaptureViewState.idle;
    final outcome = ConversationVoiceCaptureOutcome(
      reason: ConversationVoiceCaptureEndReason.autoStop,
      recording: recording,
      waveform: waveform,
      scopeGeneration: session.generation,
    );
    _onAutoStopOutcome?.call(outcome);
  }

  void _publish(ConversationVoiceCaptureViewState next) {
    if (_disposed || next == _state) return;
    _state = next;
    notifyListeners();
  }
}

class _VoiceCaptureSession {
  _VoiceCaptureSession({
    required this.generation,
    required this.recorder,
    required int amplitudeWindowSize,
  }) : amplitudeBuffer = AmplitudeBuffer(size: amplitudeWindowSize);

  final int generation;
  final AudioRecorderService recorder;
  final AmplitudeBuffer amplitudeBuffer;
  final List<double> waveformSamples = <double>[];
  late final void Function(AudioRecording? recording) autoStopHandler;

  StreamSubscription<Duration>? durationSubscription;
  StreamSubscription<double>? amplitudeSubscription;
  bool abortRequested = false;
  bool startInFlight = false;
  bool terminal = false;
}
