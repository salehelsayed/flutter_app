import 'dart:async';

import 'package:audio_session/audio_session.dart' as audio;

import '../application/call_audio_controller.dart';

typedef CallAudioSessionConfigure = Future<void> Function();
typedef CallAudioSessionRestore = Future<void> Function();
typedef CallAudioSessionSetActive = Future<bool> Function(bool active);

/// Plugin-independent events accepted by the foreground-session adapter.
enum CallAudioSessionPlatformInterruption { begin, end, ownershipLost }

enum CallForegroundAudioSessionErrorCode {
  activationRejected,
  activationFailed,
  deactivationFailed,
  closed,
}

/// Fixed-shape session failure that excludes platform and plugin details.
final class CallForegroundAudioSessionException implements Exception {
  const CallForegroundAudioSessionException(this.code);

  final CallForegroundAudioSessionErrorCode code;

  @override
  String toString() => 'CallForegroundAudioSessionException(${code.name})';
}

/// Owns foreground voice-call focus while leaving playback restoration to the
/// existing audio-session interruption owner.
final class CallForegroundAudioSessionAdapter
    implements CallForegroundAudioSession {
  CallForegroundAudioSessionAdapter({
    required CallAudioSessionConfigure configure,
    required CallAudioSessionRestore restore,
    required CallAudioSessionSetActive setActive,
    required Stream<CallAudioSessionPlatformInterruption> platformInterruptions,
  }) : _configure = configure,
       _restore = restore,
       _setActive = setActive,
       _platformInterruptions = platformInterruptions;

  factory CallForegroundAudioSessionAdapter.fromAudioSession(
    audio.AudioSession session,
  ) {
    audio.AudioSessionConfiguration? previousConfiguration;
    var capturedPreviousConfiguration = false;
    return CallForegroundAudioSessionAdapter(
      configure: () {
        if (!capturedPreviousConfiguration) {
          previousConfiguration = session.configuration;
          capturedPreviousConfiguration = true;
        }
        return session.configure(audioSessionConfiguration);
      },
      restore: () {
        final previous = previousConfiguration;
        return previous == null
            ? Future<void>.value()
            : session.configure(previous);
      },
      setActive: (active) => session.setActive(
        active,
        avAudioSessionSetActiveOptions: active
            ? null
            : audio.AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      ),
      platformInterruptions: session.interruptionEventStream.map(
        mapAudioSessionInterruption,
      ),
    );
  }

  static Future<CallForegroundAudioSessionAdapter> create() async =>
      CallForegroundAudioSessionAdapter.fromAudioSession(
        await audio.AudioSession.instance,
      );

  static final audioSessionConfiguration = audio.AudioSessionConfiguration(
    avAudioSessionCategory: audio.AVAudioSessionCategory.playAndRecord,
    avAudioSessionCategoryOptions:
        audio.AVAudioSessionCategoryOptions.allowBluetooth |
        audio.AVAudioSessionCategoryOptions.allowBluetoothA2dp,
    avAudioSessionMode: audio.AVAudioSessionMode.voiceChat,
    androidAudioAttributes: const audio.AndroidAudioAttributes(
      contentType: audio.AndroidAudioContentType.speech,
      usage: audio.AndroidAudioUsage.voiceCommunication,
    ),
    androidAudioFocusGainType: audio.AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: true,
  );

  final CallAudioSessionConfigure _configure;
  final CallAudioSessionRestore _restore;
  final CallAudioSessionSetActive _setActive;
  final Stream<CallAudioSessionPlatformInterruption> _platformInterruptions;
  final StreamController<CallAudioSessionInterruption> _interruptions =
      StreamController<CallAudioSessionInterruption>.broadcast(sync: true);

  StreamSubscription<CallAudioSessionPlatformInterruption>?
  _platformSubscription;
  Future<void>? _activationFuture;
  Future<void>? _deactivationFuture;
  bool _activationAttempted = false;
  bool _activationCompleted = false;
  bool _deactivationRequested = false;
  bool _ownsSession = false;

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      _interruptions.stream;

  @override
  bool get ownsSession => _ownsSession;

  @override
  Future<void> activate() {
    if (_deactivationRequested) {
      return Future<void>.error(
        const CallForegroundAudioSessionException(
          CallForegroundAudioSessionErrorCode.closed,
        ),
      );
    }
    return _activationFuture ??= _activateOnce();
  }

  Future<void> _activateOnce() async {
    _activationAttempted = true;
    _platformSubscription = _platformInterruptions.listen(
      _onPlatformInterruption,
      onError: (_) => _loseOwnership(),
    );
    try {
      await _configure();
      final accepted = await _setActive(true);
      if (!accepted) {
        throw const CallForegroundAudioSessionException(
          CallForegroundAudioSessionErrorCode.activationRejected,
        );
      }
      _activationCompleted = true;
      _ownsSession = !_deactivationRequested;
    } on CallForegroundAudioSessionException {
      rethrow;
    } catch (_) {
      throw const CallForegroundAudioSessionException(
        CallForegroundAudioSessionErrorCode.activationFailed,
      );
    }
  }

  @override
  Future<void> deactivate() {
    _deactivationRequested = true;
    _ownsSession = false;
    return _deactivationFuture ??= _deactivateOnce();
  }

  Future<void> _deactivateOnce() async {
    var failed = false;
    final activation = _activationFuture;
    if (activation != null) {
      try {
        await activation;
      } catch (_) {}
    }

    final subscription = _platformSubscription;
    _platformSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        failed = true;
      }
    }
    if (_activationAttempted) {
      try {
        await _restore();
      } catch (_) {
        failed = true;
      }
      try {
        if (!await _setActive(false)) failed = true;
      } catch (_) {
        failed = true;
      }
    }
    if (!_interruptions.isClosed) {
      try {
        await _interruptions.close();
      } catch (_) {
        failed = true;
      }
    }
    _activationCompleted = false;
    if (failed) {
      throw const CallForegroundAudioSessionException(
        CallForegroundAudioSessionErrorCode.deactivationFailed,
      );
    }
  }

  void _onPlatformInterruption(CallAudioSessionPlatformInterruption event) {
    if (!_activationCompleted || _deactivationRequested) return;
    switch (event) {
      case CallAudioSessionPlatformInterruption.begin:
        _interruptions.add(const CallAudioSessionInterruption.begin());
      case CallAudioSessionPlatformInterruption.end:
        _interruptions.add(const CallAudioSessionInterruption.end());
      case CallAudioSessionPlatformInterruption.ownershipLost:
        _ownsSession = false;
        _interruptions.add(const CallAudioSessionInterruption.end());
    }
  }

  void _loseOwnership() {
    if (!_activationCompleted || _deactivationRequested) return;
    _ownsSession = false;
    if (!_interruptions.isClosed) {
      _interruptions.add(const CallAudioSessionInterruption.begin());
    }
  }

  static CallAudioSessionPlatformInterruption mapAudioSessionInterruption(
    audio.AudioInterruptionEvent event,
  ) {
    if (!event.begin && event.type == audio.AudioInterruptionType.unknown) {
      return CallAudioSessionPlatformInterruption.ownershipLost;
    }
    return event.begin
        ? CallAudioSessionPlatformInterruption.begin
        : CallAudioSessionPlatformInterruption.end;
  }
}
