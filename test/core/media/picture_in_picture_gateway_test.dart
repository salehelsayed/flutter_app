import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'typed PiP session maps native lifecycle exactly once and ignores stale events',
    () async {
      final nativeEvents = StreamController<Object?>();
      final calls = <({String method, Map<String, Object?>? arguments})>[];
      final gateway = PictureInPictureChannelGateway(
        platform: PictureInPictureHostPlatform.android,
        invokeMethod: (method, arguments) async {
          calls.add((method: method, arguments: arguments));
          return switch (method) {
            'capability' => <String, Object?>{'supported': true},
            'start' ||
            'activate' ||
            'stop' => <String, Object?>{'accepted': true},
            _ => null,
          };
        },
        nativeEvents: nativeEvents.stream,
      );
      addTearDown(() async {
        await gateway.dispose();
        await nativeEvents.close();
      });

      final observed = <PictureInPictureEvent>[];
      final subscription = gateway.events.listen(observed.add);
      addTearDown(subscription.cancel);

      final capability = await gateway.capability();
      expect(capability.isVisible, isTrue);
      expect(capability.isSupported, isTrue);

      const first = PictureInPictureRequest(
        session: 'opaque-session-1',
        attachment: 'attachment-1',
        path: '/app/Documents/media/video.mp4',
        positionMs: 1200,
        durationMs: 9000,
      );
      expect(await gateway.start(first), PictureInPictureStartOutcome.started);

      nativeEvents.add(_event(session: 'stale-session', state: 'active'));
      nativeEvents.add(_event(state: 'nativeReady'));
      nativeEvents.add(_event(state: 'active', positionMs: 1250));
      nativeEvents.add(_event(state: 'checkpoint', positionMs: 1600));
      nativeEvents.add(
        _event(state: 'restoring', positionMs: 1700, reason: 'system_return'),
      );
      nativeEvents.add(
        _event(state: 'restoring', positionMs: 1800, reason: 'system_return'),
      );
      nativeEvents.add(_event(state: 'checkpoint', positionMs: 1900));
      await Future<void>.delayed(Duration.zero);

      expect(observed.map((event) => event.state), <PictureInPictureState>[
        PictureInPictureState.nativeReady,
        PictureInPictureState.active,
        PictureInPictureState.checkpoint,
        PictureInPictureState.restoring,
      ]);
      expect(observed.last.isTerminal, isTrue);
      expect(observed.last.reason, PictureInPictureTerminalReason.systemReturn);
      expect(
        (await gateway.activate(first.session, first.attachment)).accepted,
        isFalse,
      );

      const second = PictureInPictureRequest(
        session: 'opaque-session-2',
        attachment: 'attachment-2',
        path: '/app/Documents/media/second.mp4',
        positionMs: 0,
      );
      expect(await gateway.start(second), PictureInPictureStartOutcome.started);
      nativeEvents.add(
        _event(
          session: second.session,
          attachment: second.attachment,
          state: 'active',
          positionMs: 0,
          durationMs: null,
        ),
      );
      nativeEvents.add(
        _event(
          session: second.session,
          attachment: second.attachment,
          state: 'completed',
          positionMs: 0,
          reason: 'completed',
        ),
      );
      nativeEvents.add(
        _event(
          session: second.session,
          attachment: second.attachment,
          state: 'failed',
          reason: 'playback_error',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        observed
            .where((event) => event.session == second.session)
            .map((event) => event.state),
        <PictureInPictureState>[
          PictureInPictureState.active,
          PictureInPictureState.completed,
        ],
      );
      expect(calls.map((call) => call.method), <String>[
        'capability',
        'capability',
        'start',
        'capability',
        'start',
      ]);
    },
  );

  test(
    'iOS and other hosts are hidden without touching native channels',
    () async {
      for (final platform in <PictureInPictureHostPlatform>[
        PictureInPictureHostPlatform.iOS,
        PictureInPictureHostPlatform.other,
      ]) {
        var calls = 0;
        final gateway = PictureInPictureChannelGateway(
          platform: platform,
          invokeMethod: (method, arguments) async {
            calls++;
            return <String, Object?>{'supported': true};
          },
          nativeEvents: const Stream<Object?>.empty(),
        );
        final capability = await gateway.capability();
        expect(capability.isVisible, isFalse);
        expect(capability.isSupported, isFalse);
        expect(
          capability.reason,
          platform == PictureInPictureHostPlatform.iOS
              ? PictureInPictureCapabilityReason.iOSDisabled
              : PictureInPictureCapabilityReason.unsupportedPlatform,
        );
        expect(
          await gateway.start(
            const PictureInPictureRequest(
              session: 'opaque-session',
              attachment: 'attachment',
              path: '/owned/video.mp4',
              positionMs: 0,
            ),
          ),
          PictureInPictureStartOutcome.unsupportedPlatform,
        );
        expect(calls, 0);
        await gateway.dispose();
      }
    },
  );

  test(
    'real factory creates and subscribes no platform channels off Android',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methodChannel = MethodChannel(kPictureInPictureMethodChannel);
      const eventChannel = MethodChannel(kPictureInPictureEventChannel);
      var channelCalls = 0;
      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        channelCalls++;
        return <String, Object?>{'supported': true};
      });
      messenger.setMockMethodCallHandler(eventChannel, (_) async {
        channelCalls++;
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(methodChannel, null);
        messenger.setMockMethodCallHandler(eventChannel, null);
      });

      final gateway = PictureInPictureChannelGateway.platform();
      addTearDown(gateway.dispose);
      expect((await gateway.capability()).isVisible, isFalse);
      expect(
        await gateway.start(
          const PictureInPictureRequest(
            session: 'opaque-session',
            attachment: 'attachment',
            path: '/owned/video.mp4',
            positionMs: 0,
          ),
        ),
        PictureInPictureStartOutcome.unsupportedPlatform,
      );
      await Future<void>.delayed(Duration.zero);

      expect(channelCalls, 0);
    },
  );

  test(
    'unsupported and channel-failure Android capability is hidden',
    () async {
      final unsupported = PictureInPictureChannelGateway(
        platform: PictureInPictureHostPlatform.android,
        invokeMethod: (_, _) async => <String, Object?>{'supported': false},
        nativeEvents: const Stream<Object?>.empty(),
      );
      final failed = PictureInPictureChannelGateway(
        platform: PictureInPictureHostPlatform.android,
        invokeMethod: (_, _) async =>
            throw PlatformException(code: 'pip_unavailable'),
        nativeEvents: const Stream<Object?>.empty(),
      );
      addTearDown(unsupported.dispose);
      addTearDown(failed.dispose);

      expect((await unsupported.capability()).isVisible, isFalse);
      expect((await failed.capability()).isVisible, isFalse);
    },
  );

  test('malformed active-session event fails closed exactly once', () async {
    final nativeEvents = StreamController<Object?>();
    final gateway = PictureInPictureChannelGateway(
      platform: PictureInPictureHostPlatform.android,
      invokeMethod: (method, arguments) async => method == 'capability'
          ? <String, Object?>{'supported': true}
          : <String, Object?>{'accepted': true},
      nativeEvents: nativeEvents.stream,
    );
    addTearDown(() async {
      await gateway.dispose();
      await nativeEvents.close();
    });
    final observed = <PictureInPictureEvent>[];
    gateway.events.listen(observed.add);
    expect(
      await gateway.start(
        const PictureInPictureRequest(
          session: 'opaque-session',
          attachment: 'attachment',
          path: '/owned/video.mp4',
          positionMs: 0,
        ),
      ),
      PictureInPictureStartOutcome.started,
    );

    nativeEvents.add(<String, Object?>{
      'session': 'opaque-session',
      'attachment': 'attachment',
      'state': 'active',
      'positionMs': -1,
      'durationMs': null,
      'reason': null,
    });
    nativeEvents.add(<String, Object?>{'unexpected': true});
    await Future<void>.delayed(Duration.zero);

    expect(observed, hasLength(1));
    expect(observed.single.state, PictureInPictureState.failed);
    expect(
      observed.single.reason,
      PictureInPictureTerminalReason.channelFailure,
    );
  });
}

Map<String, Object?> _event({
  String session = 'opaque-session-1',
  String attachment = 'attachment-1',
  required String state,
  int positionMs = 1200,
  int? durationMs = 9000,
  String? reason,
}) => <String, Object?>{
  'session': session,
  'attachment': attachment,
  'state': state,
  'positionMs': positionMs,
  'durationMs': durationMs,
  'reason': reason,
};
