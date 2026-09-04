import '../../../core/media/audio_recorder_service.dart';
import '../application/call_audio_controller.dart';

typedef IsVoiceNoteRecording = bool Function();

/// Refuses foreground call capture while the existing voice-note recorder owns
/// the microphone. Eligible playback pause/resume remains owned by the shared
/// audio-session interruption policy; microphone recording is never resumed.
final class CallMediaConflictAdapter implements CallMediaConflictPort {
  CallMediaConflictAdapter({
    IsVoiceNoteRecording? isVoiceNoteRecording,
    MicrophoneCaptureLeaseCoordinator? microphoneCaptureLeases,
  }) : assert(isVoiceNoteRecording != null || microphoneCaptureLeases != null),
       _microphoneCaptureLeases =
           microphoneCaptureLeases ??
           MicrophoneCaptureLeaseCoordinator(
             isCaptureActive: isVoiceNoteRecording!,
           );

  final MicrophoneCaptureLeaseCoordinator _microphoneCaptureLeases;

  @override
  Future<CallMediaConflictLease> acquireForCall() async {
    try {
      return _CallMediaConflictLease(_microphoneCaptureLeases.acquire());
    } on MicrophoneCaptureLeaseRefused {
      throw const CallMediaConflictRefused();
    }
  }
}

final class _CallMediaConflictLease implements CallMediaConflictLease {
  _CallMediaConflictLease(this._captureLease);

  final MicrophoneCaptureLease _captureLease;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _captureLease.release();
  }
}
