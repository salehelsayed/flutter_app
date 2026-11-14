import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'flutter_webrtc_video_session_test.dart' as harness;

/// Defect 4 (build 267): on iOS the pinned plugin identifies a transceiver by
/// `mid ?? ''`. In an initial video call audio is added first, so before the
/// first SDP both transceivers have id '' and set/getDirection on the new
/// video transceiver resolve to AUDIO. The offer then carried an inactive
/// video section plus a recvonly one from OfferToReceiveVideo.
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

  int videoSections(String sdp) => 'm=video'.allMatches(sdp).length;

  // The engine prepares initial audio first (its own audio transceiver), so in
  // iOS mode audio and the later video both start with id ''.
  Future<harness.Fixture> iosFixture({bool caller = true}) async {
    final f = harness.Fixture();
    f.peer.iosEmptyIds = true;
    await f.start(caller: caller);
    expect(f.peer.nativeTransceivers.first.receiver.track.kind, 'audio');
    expect(f.peer.nativeTransceivers.first.id, '');
    return f;
  }

  harness.Transceiver audioOf(harness.Fixture f) => f.peer.nativeTransceivers
      .firstWhere((t) => t.receiver.track.kind == 'audio');

  test(
    'DEFECT4 first iOS offer has one sendrecv video, audio untouched',
    () async {
      final f = await iosFixture();
      final audioStart = audioOf(f).direction;
      final token = f.begin();
      final offer = await f.session.createOffer(token);
      expect(videoSections(offer.value), 1);
      expect(
        offer.value,
        contains('m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=sendrecv'),
      );
      expect(f.peer.video.direction, rtc.TransceiverDirection.SendRecv);
      expect(audioOf(f).direction, audioStart);
      // No direction call may go through the ambiguous pre-MID id.
      expect(f.peer.video.directionCalls, 0);
      expect(f.captures, 0); // no capture before committed consent
    },
  );

  test(
    'DEFECT4 after the offer a downgrade and re-upgrade hit video',
    () async {
      final f = await iosFixture();
      final audioStart = audioOf(f).direction;
      await f.committed();
      final down = f.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
      await f.session.createOffer(down);
      expect(f.peer.video.direction, rtc.TransceiverDirection.Inactive);
      expect(audioOf(f).direction, audioStart);
      final up = f.begin(revision: 3, id: 'up');
      final offer = await f.session.createOffer(up);
      expect(videoSections(offer.value), 1);
      expect(f.peer.video.direction, rtc.TransceiverDirection.SendRecv);
      expect(audioOf(f).direction, audioStart);
    },
  );

  test(
    'DEFECT4 the camera reuses the same owned sender after the rebind',
    () async {
      final f = await iosFixture();
      final audioStart = audioOf(f).direction;
      final token = await f.committed();
      expect(f.captures, 0);
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      expect(f.peer.video.sender.track, same(f.track));
      expect(audioOf(f).sender.track, isNull);
      expect(audioOf(f).direction, audioStart);
    },
  );

  test('DEFECT4 a grant lost during the rebind fails closed', () async {
    final f = await iosFixture();
    final audioStart = audioOf(f).direction;
    final token = f.begin();
    final offer = await f.session.createOffer(token);
    f.peer.beforeTransceivers = () async => f.current = false;
    await expectLater(f.session.applyLocal(token, offer), throwsA(anything));
    expect(audioOf(f).direction, audioStart);
  });

  test('DEFECT4 a missing owned sender is never replaced by another', () async {
    final f = await iosFixture();
    final audioStart = audioOf(f).direction;
    final token = f.begin();
    final offer = await f.session.createOffer(token);
    f.peer.transceiversOverride = () => [harness.Transceiver('video')];
    await expectLater(f.session.applyLocal(token, offer), throwsA(anything));
    expect(audioOf(f).direction, audioStart);
  });

  test('DEFECT4 the iOS callee still answers one sendrecv video', () async {
    final f = await iosFixture(caller: false);
    final audioStart = audioOf(f).direction;
    final token = f.begin();
    await f.session.applyRemote(
      token,
      harness.description(CallSessionDescriptionType.offer, video: 'sendrecv'),
    );
    final answer = await f.session.createAnswer(token);
    expect(videoSections(answer.value), 1);
    expect(
      answer.value,
      contains('m=video 9 UDP/TLS/RTP/SAVPF 96\r\na=sendrecv'),
    );
    expect(f.peer.video.direction, rtc.TransceiverDirection.SendRecv);
    expect(audioOf(f).direction, audioStart);
  });

  test('DEFECT4 Android stable ids keep the same downgrade behavior', () async {
    final f = harness.Fixture();
    await f.start();
    await f.committed();
    final down = f.begin(media: CallMediaKind.audio, revision: 2, id: 'down');
    final offer = await f.session.createOffer(down);
    expect(f.peer.video.direction, rtc.TransceiverDirection.Inactive);
    expect(offer.value, contains('a=inactive'));
    expect(f.peer.video.id, startsWith('tx-'));
  });
}
