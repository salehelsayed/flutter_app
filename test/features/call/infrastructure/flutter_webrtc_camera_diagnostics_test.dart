import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_video_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

// Reuse the closed U3j-Q fixture: real engine, fake native peer and sender.
import 'flutter_webrtc_video_quality_test.dart' as quality;

/// CAM-DIAG: each capture give-up branch names a fixed stage in debug; with
/// diagnostics off (release default) nothing is printed. No behavior change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('FlutterWebRTC.Event');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    FlutterWebRtcVideoSession.cameraDiagnostics = kDebugMode;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  // testWidgets checks foundation variables before tearDown, so restore here.
  Future<List<String>> cameraLines(
    Future<void> Function() body, {
    String prefix = '[CAMERA]',
  }) async {
    final lines = <String>[];
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith(prefix)) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = saved;
    }
    return lines;
  }

  quality.qualityTest('CAM-DIAG rejected parameters name stage and encodings', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.acceptParameters = false;
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    });
    expect(
      lines,
      contains('[CAMERA] capture_stop stage=set_parameters_false encodings=1'),
    );
    expect(lines.every((l) => !l.contains('call')), isTrue);
  });

  quality.qualityTest('CAM-DIAG a throwing setParameters names its stage', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.acceptParameters = false;
    f.peer.video.sender.failParameters = true;
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    });
    expect(
      lines,
      containsAllInOrder(<String>[
        '[CAMERA] capture_stop stage=set_parameters_threw encodings=1',
        '[CAMERA] capture_stop stage=threw',
      ]),
    );
  });

  quality.qualityTest('CAM-DIAG an unknown encoding layout names its count', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.parameters.encodings = [
      rtc.RTCRtpEncoding(ssrc: 42),
      rtc.RTCRtpEncoding(ssrc: 43),
    ];
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    });
    expect(
      lines,
      contains('[CAMERA] capture_stop stage=encodings encodings=2'),
    );
  });

  quality.qualityTest('CAM-DIAG a camera that starts prints nothing', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
    });
    expect(lines, isEmpty);
  });

  quality.qualityTest('CAM-DIAG off (release default) prints nothing', (
    tester,
    f,
  ) async {
    FlutterWebRtcVideoSession.cameraDiagnostics = false;
    final token = await f.committed();
    f.peer.video.sender.acceptParameters = false;
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    });
    expect(lines, isEmpty);
  });

  quality.qualityTest('CAM-DIAG prepare names media, direction and readback', (
    tester,
    f,
  ) async {
    final lines = await cameraLines(() async {
      await f.committed();
    }, prefix: '[VIDEO]');
    expect(
      lines,
      containsAllInOrder(<String>[
        '[VIDEO] prepare media=video direction=SendRecv readback=created',
        '[VIDEO] stats_start=disabled',
      ]),
    );
  });

  quality.qualityTest('CAM-DIAG a refreshed sender reports its fresh count', (
    tester,
    f,
  ) async {
    final token = await f.committed();
    f.peer.video.sender.parameters.encodings = [];
    f.peer.video.sender.nativeParameters = rtc.RTCRtpParameters(encodings: []);
    final lines = await cameraLines(() async {
      expect(await f.session.setLocalCamera(token, f.grant()), isFalse);
    });
    expect(
      lines,
      containsAllInOrder(<String>[
        '[CAMERA] encodings_refresh cached=0 fresh=0',
        '[CAMERA] capture_stop stage=encodings_fresh encodings=0',
      ]),
    );
  });

  quality.qualityTest(
    'DEFECT4 create, local and remote SDP each log one line',
    (tester, f) async {
      final lines = await cameraLines(() async {
        await f.committed();
      }, prefix: '[VIDEO] sdp');
      expect(lines.map((l) => l.split(' ')[2]), [
        'phase=create',
        'phase=local',
        'phase=remote',
      ]);
      final shape = RegExp(
        r'^\[VIDEO\] sdp phase=(create|local|remote) type=(offer|answer) '
        r'mediaRevision=\d+ videoSections=\d+ rejectedVideo=\d+ '
        r'directions=[a-z,\-]+ hasVideoMsid=(true|false) '
        r'hasVideoSsrc=(true|false) senderTrackPresent=(true|false)$',
      );
      for (final line in lines) {
        expect(shape.hasMatch(line), isTrue, reason: line);
      }
    },
  );

  quality.qualityTest('DEFECT4 SDP lines are off in release default', (
    tester,
    f,
  ) async {
    FlutterWebRtcVideoSession.cameraDiagnostics = false;
    final lines = await cameraLines(() async {
      await f.committed();
    }, prefix: '[VIDEO] sdp');
    expect(lines, isEmpty);
  });
}
