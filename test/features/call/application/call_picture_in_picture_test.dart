import 'dart:async';

import 'package:flutter_app/features/call/application/call_picture_in_picture.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_call_picture_in_picture_bridge.dart';

final class _Token implements CallVideoNegotiation {
  _Token(this.callId, this.negotiationId);
  @override
  final CallId callId;
  @override
  final String negotiationId;
  @override
  int get mediaRevision => 1;
  @override
  CallMediaKind get media => CallMediaKind.video;
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final call = CallId.parse('11111111-1111-4111-8111-111111111111');
  late _Token token;
  late CallPipSource source;
  late FakeCallPictureInPictureBridge bridge;
  late CallPictureInPictureController owner;
  late List<CallPipEvent> handled;
  late bool valid;

  CallPipSource descriptor({int epoch = 1, String track = 'remote'}) =>
      CallPipSource(
        negotiation: token,
        rendererEpoch: epoch,
        peerConnectionId: 'exact-peer',
        remoteTrackId: track,
        isCurrent: () => valid,
      );

  setUp(() {
    token = _Token(call, 'negotiation');
    valid = true;
    source = descriptor();
    bridge = FakeCallPictureInPictureBridge();
    handled = [];
    owner = CallPictureInPictureController(
      videoEnabled: true,
      bridge: bridge,
      canApply: (_) => valid,
      onEvent: (_, event) => handled.add(event),
    );
  });
  tearDown(() => owner.close());

  Future<CallPipIdentity> bind() async {
    owner.bind(source, muted: false, cameraOn: false);
    await _flush();
    expect(bridge.arms, hasLength(1));
    return bridge.arms.single;
  }

  test('PiP gate OFF has no native listener or command', () async {
    await owner.close();
    bridge = FakeCallPictureInPictureBridge();
    owner = CallPictureInPictureController(
      bridge: bridge,
      canApply: (_) => true,
      onEvent: (_, event) => handled.add(event),
    );
    owner.bind(source, muted: false, cameraOn: true);
    owner.background();
    await _flush();
    expect(bridge.listens, 0);
    expect(bridge.availabilityCalls, 0);
    expect(bridge.arms, isEmpty);
    expect(bridge.enters, isEmpty);
  });

  test(
    'PiP arms exact remote source and requests entry once on background',
    () async {
      final id = await bind();
      expect(bridge.sources.single, same(source));
      expect(bridge.enters, isEmpty);
      owner.background();
      owner.background();
      await _flush();
      expect(bridge.enters, [id]);
    },
  );

  test('PiP unavailable fails closed without arming', () async {
    bridge.supported = false;
    owner.bind(source, muted: false, cameraOn: true);
    owner.background();
    await _flush();
    expect(bridge.availabilityCalls, 1);
    expect(bridge.arms, isEmpty);
    expect(owner.current, isNull);
    expect(handled.single.type, CallPipEventType.failed);
  });

  test(
    'PiP entered and actions are current-lease and sequence qualified',
    () async {
      final id = await bind();
      bridge.emit(id, 1, CallPipEventType.action, 'end');
      bridge.emit(id, 2, CallPipEventType.entered);
      bridge.emit(id, 3, CallPipEventType.entered);
      bridge.emit(id, 4, CallPipEventType.action, 'mute');
      bridge.emit(id, 4, CallPipEventType.action, 'mute');
      bridge.emit(
        CallPipIdentity(
          CallId.parse('22222222-2222-4222-8222-222222222222'),
          id.leaseId,
          instanceId: id.instanceId,
        ),
        5,
        CallPipEventType.action,
        'end',
      );
      expect(handled.map((e) => (e.type, e.detail)), [
        (CallPipEventType.entered, null),
        (CallPipEventType.action, 'mute'),
      ]);
    },
  );

  test('PiP same-call remote epoch replacement rejects old close', () async {
    final old = await bind();
    source = descriptor(epoch: 2, track: 'replacement');
    owner.bind(source, muted: true, cameraOn: false);
    await _flush();
    expect(bridge.arms, hasLength(2));
    final current = bridge.arms.last;
    expect(current.leaseId, greaterThan(old.leaseId));
    bridge.emit(old, 99, CallPipEventType.exited, 'closed');
    expect(owner.current!.identity, current);
    expect(handled, isEmpty);
    expect(bridge.disarms, contains(old));
  });

  test(
    'PiP reconstructed owner rejects prior instance with same call and lease',
    () async {
      final old = await bind();
      await owner.close();
      bridge = FakeCallPictureInPictureBridge();
      owner = CallPictureInPictureController(
        videoEnabled: true,
        bridge: bridge,
        canApply: (_) => valid,
        onEvent: (_, event) => handled.add(event),
      );
      final current = await bind();
      expect(current.instanceId, isNot(old.instanceId));
      expect(current.callId, old.callId);
      expect(current.leaseId, old.leaseId);
      bridge.emit(old, 100, CallPipEventType.exited, 'closed');
      expect(owner.current!.identity, current);
      expect(handled, isEmpty);
    },
  );

  test('PiP old close cannot affect a successor call', () async {
    final old = await bind();
    token = _Token(
      CallId.parse('33333333-3333-4333-8333-333333333333'),
      'next',
    );
    source = descriptor();
    owner.bind(source, muted: false, cameraOn: false);
    await _flush();
    expect(bridge.arms, hasLength(2));
    bridge.emit(old, 1, CallPipEventType.exited, 'closed');
    expect(owner.current!.identity.callId, token.callId);
    expect(handled, isEmpty);
  });

  test('PiP End before attach retires first and cleans late success', () async {
    bridge.pendingArm = Completer<bool>();
    final old = await bind();
    owner.invalidate('end');
    expect(owner.current, isNull);
    await _flush();
    final before = bridge.disarms.length;
    bridge.pendingArm!.complete(true);
    await _flush();
    expect(bridge.disarms.length, greaterThan(before));
    expect(bridge.disarms.last, old);
    expect(handled, isEmpty);
  });

  test('PiP revoked source during attach never becomes ready', () async {
    bridge.pendingArm = Completer<bool>();
    final old = await bind();
    valid = false;
    bridge.pendingArm!.complete(true);
    await _flush();
    expect(owner.current, isNull);
    expect(bridge.disarms, contains(old));
  });

  test('PiP failed cleanup remains owned until retry succeeds', () async {
    final old = await bind();
    bridge.disarmResult = false;
    owner.invalidate('end');
    await _flush();
    expect(owner.current, isNull);
    expect(owner.hasPendingCleanup, isTrue);
    bridge.disarmResult = true;
    expect(await owner.retryCleanup(), isTrue);
    expect(owner.hasPendingCleanup, isFalse);
    expect(bridge.disarms.where((id) => id == old).length, greaterThan(1));
  });

  test(
    'PiP close is an exit, never an End action; late action ignored',
    () async {
      final id = await bind();
      bridge.emit(id, 1, CallPipEventType.entered);
      bridge.emit(id, 2, CallPipEventType.exited, 'closed');
      bridge.emit(id, 3, CallPipEventType.action, 'end');
      expect(handled.map((e) => e.type), [
        CallPipEventType.entered,
        CallPipEventType.exited,
      ]);
      expect(owner.current, isNull);
    },
  );
}
