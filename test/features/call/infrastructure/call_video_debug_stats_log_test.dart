import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/infrastructure/call_video_debug_stats_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'flutter_webrtc_video_session_test.dart' as harness;

List<rtc.StatsReport> sample(int second, {int sent = 0, int received = 0}) {
  final ts = second * 1000000.0;
  return [
    rtc.StatsReport('v-out', 'outbound-rtp', ts, {
      'kind': 'video',
      'rid': 'h',
      'bytesSent': sent,
      'frameWidth': 640,
      'frameHeight': 360,
      'framesPerSecond': 24,
      'qualityLimitationReason': 'bandwidth',
    }),
    rtc.StatsReport('v-in', 'inbound-rtp', ts, {
      'mediaType': 'video',
      'bytesReceived': received,
      'frameWidth': 1280,
      'frameHeight': 720,
      'framesPerSecond': 30,
    }),
    rtc.StatsReport('a-out', 'outbound-rtp', ts, {
      'kind': 'audio',
      'bytesSent': 999,
    }),
    rtc.StatsReport('pair', 'candidate-pair', ts, {'state': 'succeeded'}),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('FlutterWebRTC.Event');
  final printed = <String>[];
  // testWidgets checks foundation variables before tearDown, so each body
  // restores debugPrint itself.
  Future<void> capturing(Future<void> Function() body) async {
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('[STATS]')) {
        printed.add(message);
      }
    };
    try {
      await body();
    } finally {
      debugPrint = saved;
    }
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
    printed.clear();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  test('STATS-LOG formats video rtp only, kbps from the previous sample', () {
    final log = CallVideoDebugStatsLog();
    expect(log.lines(sample(1, sent: 125000, received: 50000)), [
      '[STATS] outbound-rtp ts=1000000 id=v-out rid=h bytesSent=125000 '
          'kbps=- frameWidth=640 frameHeight=360 framesPerSecond=24 '
          'qualityLimitationReason=bandwidth',
      '[STATS] inbound-rtp ts=1000000 id=v-in rid=- bytesReceived=50000 '
          'kbps=- frameWidth=1280 frameHeight=720 framesPerSecond=30 '
          'qualityLimitationReason=-',
    ]);
    expect(log.lines(sample(3, sent: 625000, received: 300000)), [
      '[STATS] outbound-rtp ts=3000000 id=v-out rid=h bytesSent=625000 '
          'kbps=2000 frameWidth=640 frameHeight=360 framesPerSecond=24 '
          'qualityLimitationReason=bandwidth',
      '[STATS] inbound-rtp ts=3000000 id=v-in rid=- bytesReceived=300000 '
          'kbps=1000 frameWidth=1280 frameHeight=720 framesPerSecond=30 '
          'qualityLimitationReason=-',
    ]);
    // A counter reset gives no rate instead of a negative one.
    expect(
      log.lines(sample(5, sent: 1000, received: 300000)).first,
      contains('bytesSent=1000 kbps=-'),
    );
  });

  testWidgets('STATS-LOG opt-in interval logs while video is prepared and '
      'stops on retire', (tester) async {
    await capturing(() async {
      final f = harness.Fixture();
      await f.start(debugStatsInterval: const Duration(seconds: 2));
      var second = 0;
      f.peer.stats = () async {
        second += 2;
        return sample(second, sent: second * 100000);
      };
      await f.committed();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(f.peer.statsReads, 2);
      expect(printed.where((l) => l.startsWith('[STATS] outbound-rtp')), [
        contains('ts=2000000 id=v-out rid=h bytesSent=200000 kbps=-'),
        contains('ts=4000000 id=v-out rid=h bytesSent=400000 kbps=800'),
      ]);
      // Camera stays off in this test: the log does not depend on capture.
      expect(f.captures, 0);
      await f.session.retireVideo();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(f.peer.statsReads, 2);
      expect(printed, hasLength(4));
      f.preserved();
    });
  });

  testWidgets('STATS-LOG is off without the define: no reads, no lines', (
    tester,
  ) async {
    await capturing(() async {
      final f = harness.Fixture();
      await f.start();
      f.peer.stats = () async => sample(1, sent: 1);
      await f.committed();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(f.peer.statsReads, 0);
      expect(printed, isEmpty);
      await f.session.retireVideo();
    });
  });
}
