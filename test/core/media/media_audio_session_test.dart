import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/media_audio_session.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('a call that starts while the session is fetched keeps it', () async {
    const channel = MethodChannel('com.ryanheise.audio_session');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final platformCalls = <String>[];
    final configuration = Completer<Map<String, dynamic>?>();
    messenger.setMockMethodCallHandler(channel, (call) {
      platformCalls.add(call.method);
      return call.method == 'getConfiguration'
          ? configuration.future
          : Future<Object?>.value();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    MediaAudioSession.debugDeactivate = null;
    var callLive = false;
    MediaAudioSession.callOwnsSession = () => callLive;

    final release = MediaAudioSession.release();
    await Future<void>.delayed(Duration.zero);
    callLive = true;
    configuration.complete(null);
    await release;
    expect(platformCalls, ['getConfiguration']);

    callLive = false;
    await MediaAudioSession.release();
    expect(platformCalls, ['getConfiguration', 'setConfiguration']);
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
