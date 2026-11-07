import 'package:flutter_app/core/media/media_audio_session.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int deactivations;

  setUp(() {
    deactivations = 0;
    MediaAudioSession.debugDeactivate = () async => deactivations++;
  });

  tearDown(() {
    MediaAudioSession.debugDeactivate = null;
    MediaAudioSession.callOwnsSession = MediaAudioSession.noCall;
  });

  test('a finished voice note hands the audio session back', () async {
    await MediaAudioSession.release();
    expect(deactivations, 1);
  });

  test('during a call the session is left to the call', () async {
    MediaAudioSession.callOwnsSession = () => true;
    await MediaAudioSession.release();
    expect(deactivations, 0);
  });

  test('a refused hand-back is logged, never thrown', () async {
    final events = <String>[];
    debugSetFlowEventSink((event) => events.add('${event['event']}'));
    addTearDown(() => debugSetFlowEventSink(null));
    MediaAudioSession.debugDeactivate = () async =>
        throw StateError('session busy');
    await MediaAudioSession.release();
    expect(events, contains('MEDIA_AUDIO_SESSION_RELEASE_FAILED'));
  });
}
