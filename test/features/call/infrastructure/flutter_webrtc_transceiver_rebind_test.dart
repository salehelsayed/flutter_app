import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'flutter_webrtc_video_session_test.dart' as harness;

const _budget = Duration(seconds: 3);
Future<T> _bounded<T>(Future<T> work) => work.timeout(_budget);

Future<harness.Fixture> _fixture({
  bool caller = true,
  bool opaqueAndroidHandle = true,
}) async {
  final f = harness.Fixture();
  f.peer.androidOpaqueIds = opaqueAndroidHandle;
  await _bounded(f.start(caller: caller));
  addTearDown(() async {
    f.current = false;
    await _bounded(f.session.retireVideo());
  });
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('FlutterWebRTC.Event');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  test('V291-TX001 opaque pre-MID caller handle survives a two-peer audio downgrade', () async {
    final caller = await _bounded(_fixture());
    final callee = await _bounded(_fixture(caller: false, opaqueAndroidHandle: false));
    final initial = caller.begin();
    final remoteInitial = callee.begin();
    final videoOffer = await _bounded(caller.session.createOffer(initial));
    await _bounded(caller.session.applyLocal(initial, videoOffer));
    await _bounded(callee.session.applyRemote(remoteInitial, videoOffer));
    final videoAnswer = await _bounded(callee.session.createAnswer(remoteInitial));
    await _bounded(callee.session.applyLocal(remoteInitial, videoAnswer));
    await _bounded(caller.session.applyRemote(initial, videoAnswer));
    await _bounded(caller.session.commit(initial));
    await _bounded(callee.session.commit(remoteInitial));
    final audioDirection = caller.peer.nativeTransceivers.first.direction;
    expect(caller.peer.video.id, isNotEmpty);
    expect(caller.peer.video.id, isNot(caller.peer.video.nativeMid),
      reason: 'Android originally returns an opaque nonempty pre-MID id');

    final down = caller.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
    final remoteDown = callee.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
    final pendingOffer = _bounded(caller.session.createOffer(down));
    await _bounded(expectLater(pendingOffer, completes));
    final offer = await _bounded(pendingOffer);
    expect(offer.value, contains('a=inactive'));
    await _bounded(caller.session.applyLocal(down, offer));
    await _bounded(callee.session.applyRemote(remoteDown, offer));
    final answer = await _bounded(callee.session.createAnswer(remoteDown));
    expect(answer.value, contains('a=inactive'));
    await _bounded(callee.session.applyLocal(remoteDown, answer));
    await _bounded(caller.session.applyRemote(down, answer));
    await _bounded(caller.session.commit(down));
    await _bounded(callee.session.commit(remoteDown));
    expect(caller.peer.video.direction, rtc.TransceiverDirection.Inactive);
    expect(callee.peer.video.direction, rtc.TransceiverDirection.Inactive);
    expect(caller.peer.nativeTransceivers.first.direction, audioDirection);
    expect(caller.captures + callee.captures, 0);
    caller.preserved();
    callee.preserved();
  });

  test('V291-TX002 stable Android handles retain the existing downgrade', () async {
    final f = await _bounded(_fixture(opaqueAndroidHandle: false));
    await _bounded(f.committed());
    final down = f.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
    final offer = await _bounded(f.session.createOffer(down));
    expect(offer.value, contains('a=inactive'));
    expect(f.peer.video.direction, rtc.TransceiverDirection.Inactive);
    f.preserved();
  });

  for (final failure in ['missing', 'ambiguous', 'retired']) {
    test('V291-TX refresh $failure ownership refuses before native direction mutation', () async {
      final f = await _bounded(_fixture());
      await _bounded(f.committed());
      final fresh = await _bounded(f.peer.getTransceivers());
      if (failure == 'missing') {
        f.peer.transceiversOverride = () => [harness.Transceiver('video')];
      } else if (failure == 'ambiguous') {
        f.peer.transceiversOverride = () => [...fresh, ...fresh];
      } else {
        f.peer.beforeTransceivers = () async { f.current = false; };
      }
      final down = f.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
      await _bounded(expectLater(_bounded(f.session.createOffer(down)),
        throwsA(isA<CallEngineException>().having(
          (e) => e.code, 'code', CallEngineErrorCode.notReady))));
      expect(f.peer.video.direction, rtc.TransceiverDirection.SendRecv);
      f.preserved();
    });
  }
}
