/// Android native microphone recorder smoke test.
///
/// Proves the production `record` plugin can record AAC in an M4A container on
/// a physical Android target. It does not prove voice-message send, receive, or
/// playback; those remain separate two-peer media-journey requirements.
///
/// The owning harness must pregrant `android.permission.RECORD_AUDIO`, pin an
/// explicit physical Android ID, and restore permission state after the run.
/// A wrong platform, missing permission, or missing plugin fails closed. The
/// same callable proof is registered by `integration_test/sims_dispatcher.dart`.
///
/// Run with:
/// flutter test integration_test/voice_message_e2e_test.dart -d ANDROID_SERIAL
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/android_voice_recorder_smoke.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android native microphone recorder smoke', () {
    testWidgets(
      'physical Android records a nonempty AAC/M4A file with valid duration',
      (_) => runAndroidVoiceRecorderSmoke(),
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
