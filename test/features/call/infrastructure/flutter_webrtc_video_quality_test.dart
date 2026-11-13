import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_environment.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

// Reuse the existing audio/video preservation fixture, including its real engine
// and native adapter. Importing its library does not register its main().
import 'flutter_webrtc_video_session_test.dart' as harness;
import 'call_video_quality_stats_sampler_test.dart' as feedback;

const wifi = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.wifi,
  lowDataMode: false,
  metered: false,
  thermalState: CallVideoThermalState.nominal,
);
const serious = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.wifi,
  lowDataMode: false,
  metered: false,
  thermalState: CallVideoThermalState.serious,
);
const critical = CallVideoQualityEnvironment(
  networkClass: CallVideoNetworkClass.wifi,
  lowDataMode: false,
  metered: false,
  thermalState: CallVideoThermalState.critical,
);

void environment(harness.Fixture f, CallVideoQualityEnvironment value) {
  expect(f.session, isA<CallVideoQualityEnvironmentConsumer>());
  (f.session as CallVideoQualityEnvironmentConsumer).updateQualityEnvironment(
    value,
  );
}

Future<void> advance(
  WidgetTester tester,
  harness.Fixture f,
  int seconds,
) async {
  for (var i = 0; i < seconds; i++) {
    f.qualityNow += const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }
}

void captures(harness.Fixture f, int count) {
  f.captureResults.add(f.stream);
  for (var i = 1; i < count; i++) {
    f.captureResults.add(harness.StreamFake([harness.Track('video')]));
  }
}

void qualityTest(
  String name,
  Future<void> Function(WidgetTester, harness.Fixture) body, {
  bool nativeCapture = false,
}) {
  testWidgets('U3j-Q $name', (tester) async {
    final f = harness.Fixture();
    await f.start(nativeVideoCapture: nativeCapture);
    try {
      await body(tester, f);
    } finally {
      f.current = false;
      final capture = f.captureGate;
      if (capture != null && !capture.isCompleted) capture.complete(f.stream);
      for (final transceiver in f.peer.nativeTransceivers) {
        final sender = transceiver.sender;
        final parameters = sender.parametersGate;
        if (parameters != null && !parameters.isCompleted) {
          parameters.complete(false);
        }
        final replacement = sender.gate;
        if (replacement != null && !replacement.isCompleted) {
          replacement.complete();
        }
      }
      await f.engine.close();
      await tester.pump();
    }
  });
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

  qualityTest('initial sender cap is accepted before enabling video', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    final sender = f.peer.video.sender;
    sender.onParameters = () => expect(f.track.enabled, isFalse);
    expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    expect(sender.parameterWrites, hasLength(1));
    final value = sender.parameterWrites.single;
    expect(value['transactionId'], 'native-transaction');
    final encoding = (value['encodings'] as List).single as Map;
    expect(encoding['ssrc'], 42);
    expect(encoding['maxBitrate'], 600000);
    expect(encoding['maxFramerate'], 24);
    expect(encoding['minBitrate'], anyOf(isNull, 0));
    expect(f.peer.audio.parameterWrites, isEmpty);
    f.preserved();
  });

  qualityTest('default SDK capture requests 360p24 and never audio', (
    tester,
    f,
  ) async {
    const channel = MethodChannel('FlutterWebRTC.Method');
    final requests = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getUserMedia') {
            requests.add((call.arguments as Map)['constraints'] as Map);
            return {
              'streamId': 'quality-stream',
              'audioTracks': <Object>[],
              'videoTracks': [
                {
                  'id': 'quality-camera',
                  'label': 'camera',
                  'kind': 'video',
                  'enabled': true,
                  'settings': {'width': 640, 'height': 360},
                },
              ],
            };
          }
          if ([
            'initialize',
            'mediaStreamTrackSetEnable',
            'trackDispose',
            'mediaStreamDispose',
          ].contains(call.method)) {
            return null;
          }
          throw StateError('Unexpected native operation ${call.method}');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final token = await f.committed();
    expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single['audio'], isFalse);
    expect(requests.single['video'], isA<Map>());
    final video = requests.single['video'] as Map;
    expect(video['width'], 640);
    expect(video['height'], 360);
    expect(video['frameRate'], 24);
    f.preserved();
  }, nativeCapture: true);

  for (final throws in [false, true]) {
    qualityTest('native parameter rejection throws=$throws stops only video', (
      tester,
      f,
    ) async {
      final token = await f.committed();
      f.peer.video.sender.acceptParameters = false;
      f.peer.video.sender.failParameters = throws;
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
      expect(f.track.enabled, isFalse);
      expect(f.track.stops, 1);
      expect(f.peer.video.sender.track, isNull);
      await advance(tester, f, 20);
      expect(f.captures, 1);
      expect(f.peer.statsReads, 0);
      f.preserved();
    });
  }

  qualityTest('unknown encoding layout cannot bypass the video ceiling', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.parameters.encodings = [];
    expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    expect(f.track.enabled, isFalse);
    expect(f.peer.video.sender.parameterWrites, isEmpty);
    f.preserved();
  });

  qualityTest('multiple encodings cannot multiply the per-sender ceiling', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.parameters.encodings = [
      rtc.RTCRtpEncoding(ssrc: 42),
      rtc.RTCRtpEncoding(ssrc: 43),
    ];
    expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    expect(f.track.enabled, isFalse);
    expect(f.peer.video.sender.parameterWrites, isEmpty);
    f.preserved();
  });

  qualityTest(
    'native capture reconfiguration preserves the chosen camera and applies low dimensions',
    (tester, f) async {
      const channel = MethodChannel('FlutterWebRTC.Method');
      final requests = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getUserMedia') {
              requests.add((call.arguments as Map)['constraints'] as Map);
              return {
                'streamId': 'stream-${requests.length}',
                'audioTracks': <Object>[],
                'videoTracks': [
                  {
                    'id': 'camera-${requests.length}',
                    'label': 'camera',
                    'kind': 'video',
                    'enabled': true,
                    'settings': {'width': 640, 'height': 360},
                  },
                ],
              };
            }
            if (call.method == 'mediaStreamTrackSwitchCamera') {
              return false; // rear, not failure
            }
            if ([
              'initialize',
              'mediaStreamTrackSetEnable',
              'trackDispose',
              'mediaStreamDispose',
            ].contains(call.method)) {
              return null;
            }
            throw StateError('Unexpected native operation ${call.method}');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final token = await f.committed();
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      expect(
        await (f.session as CallVideoCameraSwitch).switchCamera(
          token,
          f.grant(),
        ),
        isTrue,
      );
      environment(f, serious);
      await tester.pump();
      expect(requests, hasLength(2));
      final video = requests.last['video'] as Map;
      expect(requests.last['audio'], isFalse);
      expect(video['width'], 320);
      expect(video['height'], 180);
      expect(video['frameRate'], 15);
      expect(video['facingMode'], 'environment');
      final encoding =
          (f.peer.video.sender.parameterWrites.last['encodings'] as List).single
              as Map;
      expect(
        encoding['scaleResolutionDownBy'],
        2.0,
      ); // native camera supplied a larger format
      f.preserved();
    },
    nativeCapture: true,
  );

  qualityTest('held sender acceptance cannot revive camera off', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    final gate = Completer<bool>();
    f.peer.video.sender.parametersGate = gate;
    final starting = f.session.setLocalCamera(token, f.grant());
    await tester.pump();
    expect(f.peer.video.sender.parameterWrites, hasLength(1));
    expect(f.track.enabled, isFalse);
    final stopping = f.session.stopLocalCamera();
    gate.complete(true);
    expect(await starting, isFalse);
    expect(await stopping, isTrue);
    expect(f.track.enabled, isFalse);
    expect(f.peer.video.sender.track, isNull);
    f.preserved();
  });

  qualityTest('critical heat rejects a delayed capture before it can send', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.captureGate = Completer<rtc.MediaStream>();
    final starting = f.session.setLocalCamera(token, f.grant());
    await tester.pump();
    expect(f.captures, 1);
    environment(f, critical);
    f.captureGate!.complete(f.stream);
    expect(await starting, isFalse);
    expect(f.track.enabled, isFalse);
    expect(f.track.stops, 1);
    expect(f.peer.video.sender.track, isNull);
    f.preserved();
  });

  qualityTest(
    'critical heat closes the live gate synchronously and preserves audio',
    (tester, f) async {
      final token = await f.committed();
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      environment(f, critical);
      expect(f.track.enabled, isFalse);
      await tester.pump();
      expect(f.track.stops, 1);
      expect(f.peer.video.sender.track, isNull);
      f.preserved();
    },
  );

  qualityTest('serious heat reacquires a lower tier through the same sender', (
    tester,
    f,
  ) async {
    captures(f, 2);
    final token = await f.committed();
    final sender = f.peer.video.sender;
    expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    environment(f, serious);
    expect(f.track.enabled, isFalse);
    await tester.pump();
    expect(f.track.stops, 1);
    expect(f.captures, 2);
    expect(identical(f.peer.video.sender, sender), isTrue);
    final encoding =
        (sender.parameterWrites.last['encodings'] as List).single as Map;
    expect(encoding['maxBitrate'], 250000);
    expect(encoding['maxFramerate'], 15);
    expect(sender.track!.enabled, isTrue);
    f.preserved();
  });

  qualityTest(
    'one-second healthy polling restores tiers without a new SDP exchange',
    (tester, f) async {
      captures(f, 3);
      environment(f, wifi);
      final token = await f.committed();
      f.peer.stats = () async =>
          feedback.reports(f.qualityNow.inSeconds, track: 'video');
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      await advance(tester, f, 16);
      expect(f.captures, 1);
      await advance(tester, f, 1);
      expect(f.captures, 2);
      await advance(tester, f, 15);
      expect(f.captures, 3);
      final encoding =
          (f.peer.video.sender.parameterWrites.last['encodings'] as List).single
              as Map;
      expect(encoding['maxBitrate'], 2000000);
      expect(encoding['maxFramerate'], 30);
      expect(f.peer.offers, hasLength(1));
      expect(
        f.peer.nativeTransceivers.where(
          (t) => t.receiver.track.kind == 'video',
        ),
        hasLength(1),
      );
      f.preserved();
    },
  );

  qualityTest('two seconds of native limitation lowers the existing capture', (
    tester,
    f,
  ) async {
    captures(f, 2);
    final token = await f.committed();
    f.peer.stats = () async => feedback.reports(
      f.qualityNow.inSeconds,
      track: 'video',
      reason: 'bandwidth',
    );
    expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    await advance(tester, f, 2);
    expect(f.captures, 1);
    await advance(tester, f, 1);
    expect(f.captures, 2);
    expect(
      ((f.peer.video.sender.parameterWrites.last['encodings'] as List).single
          as Map)['maxBitrate'],
      250000,
    );
    f.preserved();
  });

  qualityTest(
    'stalled stats never blocks heat shutdown, close or starts duplicate reads',
    (tester, f) async {
      final token = await f.committed();
      final held = Completer<List<rtc.StatsReport>>();
      f.peer.stats = () => held.future;
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      await advance(tester, f, 5);
      expect(f.peer.statsReads, 1);
      environment(f, critical);
      expect(f.track.enabled, isFalse);
      await tester.pump();
      await f.session.close();
      expect(f.track.stops, 1);
      held.completeError(StateError('late native read'));
      await tester.pump();
      expect(f.captures, 1);
      f.preserved();
    },
  );

  qualityTest('camera off retires polling and prevents thermal recovery', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.stats = () async =>
        feedback.reports(f.qualityNow.inSeconds, track: 'video');
    expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    environment(f, critical);
    await tester.pump();
    await f.session.stopLocalCamera();
    final reads = f.peer.statsReads;
    environment(f, wifi);
    await advance(tester, f, 40);
    expect(f.captures, 1);
    expect(f.peer.statsReads, reads);
    expect(f.track.enabled, isFalse);
    f.preserved();
  });

  qualityTest(
    'critical cooling resumes only the still-current grant at the low tier',
    (tester, f) async {
      captures(f, 2);
      final token = await f.committed();
      f.peer.stats = () async => feedback.reports(
        f.qualityNow.inSeconds,
        track: 'video',
        video: false,
      );
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      environment(f, critical);
      await tester.pump();
      environment(f, wifi);
      await advance(tester, f, 16);
      expect(f.captures, 1);
      await advance(tester, f, 1);
      expect(f.captures, 2);
      expect(
        ((f.peer.video.sender.parameterWrites.last['encodings'] as List).single
            as Map)['maxBitrate'],
        250000,
      );
      f.preserved();
    },
  );

  qualityTest('expired foreground grant cannot be renewed by healthy stats', (
    tester,
    f,
  ) async {
    var foreground = true;
    final token = await f.committed();
    f.peer.stats = () async =>
        feedback.reports(f.qualityNow.inSeconds, track: 'video');
    expect(
      await f.session.setLocalCamera(token, f.grant(fresh: () => foreground)),
      isTrue,
    );
    environment(f, critical);
    await tester.pump();
    foreground = false;
    environment(f, wifi);
    await advance(tester, f, 40);
    expect(f.captures, 1);
    expect(f.peer.video.sender.track, isNull);
    f.preserved();
  });

  testWidgets(
    'U3j-Q unbound audio peer never starts quality polling or capture',
    (tester) async {
      final f = harness.Fixture();
      await f.start(bind: false);
      await advance(tester, f, 40);
      expect(f.captures, 0);
      expect(f.peer.statsReads, 0);
      expect(f.peer.nativeTransceivers, isEmpty);
      await f.engine.close();
    },
  );
}
