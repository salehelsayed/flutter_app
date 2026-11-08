import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Hands the shared iOS audio session back when a voice note stops playing
/// or recording, so calls (Mknoon's and other apps') can always take it.
abstract final class MediaAudioSession {
  /// The call layer points this at "a call is live"; while it returns true
  /// media never touches the session.
  static bool Function() callOwnsSession = noCall;

  static bool noCall() => false;

  /// Test seam replacing the platform deactivation.
  static Future<void> Function()? debugDeactivate;

  static Future<void> release() async {
    if (callOwnsSession()) return;
    try {
      final deactivate = debugDeactivate;
      if (deactivate != null) {
        await deactivate();
        return;
      }
      if (Platform.isIOS) {
        // No await between the call check and this send, so a call starting
        // now cannot lose its session.
        await AVAudioSession().setActive(
          false,
          avOptions: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        );
        return;
      }
      final session = await AudioSession.instance;
      if (callOwnsSession()) return;
      await session.setActive(false);
    } catch (error) {
      // iOS refuses while other audio of the app still runs; the session then
      // stays with that audio, which is the right owner.
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_AUDIO_SESSION_RELEASE_FAILED',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }
}
