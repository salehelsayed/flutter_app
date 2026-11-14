import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/application/call_picture_in_picture.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/infrastructure/platform_call_picture_in_picture_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Token implements CallVideoNegotiation {
  @override
  final callId = CallId.parse('11111111-1111-4111-8111-111111111111');
  @override
  String get negotiationId => 'negotiation';
  @override
  int get mediaRevision => 3;
  @override
  CallMediaKind get media => CallMediaKind.video;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel(
    PlatformCallPictureInPictureBridge.methodChannelName,
  );
  const events = EventChannel(
    PlatformCallPictureInPictureBridge.eventChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final token = _Token();
  final identity = CallPipIdentity(
    token.callId,
    7,
    instanceId: '22222222-2222-4222-8222-222222222222',
  );
  final wireIdentity = <String, Object>{
    'version': 1,
    'instanceId': identity.instanceId,
    'callId': token.callId.value,
    'leaseId': 7,
  };
  late List<MethodCall> calls;
  late int listens;
  late MockStreamHandlerEventSink? sink;
  late PlatformCallPictureInPictureBridge bridge;

  setUp(() {
    calls = [];
    listens = 0;
    sink = null;
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return switch (call.method) {
        'availability' => {
          'supported': true,
          'cameraInPip': false,
          'reason': 'ready',
        },
        'arm' => {'armed': true, 'reason': 'ready'},
        _ => true,
      };
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, target) {
          listens++;
          sink = target;
        },
      ),
    );
    bridge = PlatformCallPictureInPictureBridge(videoEnabled: true);
  });
  tearDown(() async {
    await bridge.close();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(events, null);
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('PiP bridge gate OFF makes no channel calls or subscriptions', () async {
    await bridge.close();
    bridge = PlatformCallPictureInPictureBridge();
    final sub = bridge.events.listen((_) {});
    expect((await bridge.availability(identity)).supported, isFalse);
    expect(await bridge.enter(identity), isFalse);
    await flush();
    expect(calls, isEmpty);
    expect(listens, 0);
    await sub.cancel();
  });

  test('PiP bridge transmits exact identity and remote descriptor', () async {
    final available = await bridge.availability(identity);
    expect(available.supported, isTrue);
    expect(available.cameraInPip, isFalse);
    expect(calls.single.arguments, wireIdentity);
    expect(
      await bridge.arm(
        identity,
        CallPipSource(
          negotiation: token,
          rendererEpoch: 4,
          peerConnectionId: 'peer',
          remoteTrackId: 'remote',
          isCurrent: () => true,
        ),
        muted: true,
        cameraOn: false,
        cameraEnabled: false,
      ),
      isTrue,
    );
    expect(calls.last.arguments, {
      ...wireIdentity,
      'negotiationId': 'negotiation',
      'mediaRevision': 3,
      'rendererEpoch': 4,
      'peerConnectionId': 'peer',
      'remoteTrackId': 'remote',
      'muted': true,
      'cameraOn': false,
      'cameraEnabled': false,
    });
    expect(await bridge.enter(identity), isTrue);
    expect(calls.last.arguments, wireIdentity);
    expect(await bridge.disarm(identity, 'end'), isTrue);
    expect(calls.last.arguments, {...wireIdentity, 'reason': 'end'});
  });

  test(
    'PiP bridge rejects malformed availability and platform failures',
    () async {
      messenger.setMockMethodCallHandler(
        method,
        (_) async => {
          'supported': true,
          'cameraInPip': 'yes',
          'reason': 'ready',
        },
      );
      expect((await bridge.availability(identity)).supported, isFalse);
      messenger.setMockMethodCallHandler(
        method,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      expect((await bridge.availability(identity)).supported, isFalse);
      expect(await bridge.enter(identity), isFalse);
      expect(await bridge.disarm(identity, 'end'), isFalse);
    },
  );

  test(
    'PiP bridge parses qualified events and drops malformed envelopes',
    () async {
      final seen = <CallPipEvent>[];
      final sub = bridge.events.listen(seen.add);
      await flush();
      expect(listens, 1);
      sink!.success({...wireIdentity, 'seq': 1, 'type': 'entered'});
      sink!.success({
        ...wireIdentity,
        'seq': 2,
        'type': 'action',
        'kind': 'camera',
      });
      sink!.success({
        ...wireIdentity,
        'seq': 3,
        'type': 'exited',
        'reason': 'closed',
      });
      sink!.success({
        ...wireIdentity,
        'seq': 4,
        'type': 'action',
        'kind': 'unknown',
      });
      sink!.success({
        ...wireIdentity,
        'version': 2,
        'seq': 5,
        'type': 'entered',
      });
      sink!.success({
        ...wireIdentity,
        'instanceId': '',
        'seq': 6,
        'type': 'entered',
      });
      sink!.success({...wireIdentity, 'seq': 0, 'type': 'entered'});
      await flush();
      expect(seen.map((e) => (e.type, e.detail)), [
        (CallPipEventType.entered, null),
        (CallPipEventType.action, 'camera'),
        (CallPipEventType.exited, 'closed'),
      ]);
      expect(seen.every((e) => e.identity == identity), isTrue);
      await sub.cancel();
    },
  );
}
