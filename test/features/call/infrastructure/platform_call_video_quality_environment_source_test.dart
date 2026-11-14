import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/domain/call_video_quality_environment.dart';
import 'package:flutter_app/features/call/infrastructure/platform_call_video_quality_environment_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel(
    PlatformCallVideoQualityEnvironmentSource.eventChannelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late int listens;
  late int cancels;
  late MockStreamHandlerEventSink? sink;

  setUp(() {
    listens = 0;
    cancels = 0;
    sink = null;
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          listens++;
          sink = events;
        },
        onCancel: (arguments) => cancels++,
      ),
    );
  });

  tearDown(() => messenger.setMockStreamHandler(channel, null));

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  group('U3j-QN platform source', () {
    test('video off: start never listens and current stays unknown', () async {
      final source = PlatformCallVideoQualityEnvironmentSource();
      await source.start();
      await flush();
      expect(listens, 0);
      expect(source.current, same(CallVideoQualityEnvironment.unknown));
      await source.close();
      expect(cancels, 0);
    });

    test('video on: start listens once and parses a full snapshot', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      await source.start();
      await source.start();
      await flush();
      expect(listens, 1);
      sink!.success(<String, Object?>{
        'networkClass': 'cellular',
        'lowDataMode': true,
        'metered': false,
        'thermalState': 'serious',
      });
      await flush();
      final current = source.current;
      expect(current.networkClass, CallVideoNetworkClass.cellular);
      expect(current.lowDataMode, isTrue);
      expect(current.metered, isFalse);
      expect(current.thermalState, CallVideoThermalState.serious);
      await source.close();
    });

    test('missing or malformed fields stay unknown, not healthy', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      await source.start();
      await flush();
      expect(listens, 1);
      sink!.success(<String, Object?>{
        'networkClass': 'satellite',
        'lowDataMode': 'yes',
        'thermalState': 3,
      });
      await flush();
      final current = source.current;
      expect(current.networkClass, CallVideoNetworkClass.unknown);
      expect(current.lowDataMode, isNull);
      expect(current.metered, isNull);
      expect(current.thermalState, CallVideoThermalState.unknown);
      sink!.success('not a map');
      await flush();
      expect(source.current.networkClass, CallVideoNetworkClass.unknown);
      await source.close();
    });

    test('a channel error becomes unknown, not a stream error', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      final seen = <CallVideoQualityEnvironment>[];
      final errors = <Object>[];
      final sub = source.changes.listen(seen.add, onError: errors.add);
      await source.start();
      await flush();
      expect(listens, 1);
      sink!.success(<String, Object?>{
        'networkClass': 'wifi',
        'thermalState': 'nominal',
      });
      await flush();
      sink!.error(code: 'read_failed');
      await flush();
      expect(errors, isEmpty);
      expect(seen.last.networkClass, CallVideoNetworkClass.unknown);
      expect(seen.last.thermalState, CallVideoThermalState.unknown);
      await sub.cancel();
      await source.close();
    });

    test('changes replays current first, then live snapshots', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      await source.start();
      await flush();
      expect(listens, 1);
      sink!.success(<String, Object?>{'networkClass': 'wifi'});
      await flush();
      final seen = <CallVideoNetworkClass>[];
      final sub = source.changes.listen((s) => seen.add(s.networkClass));
      await flush();
      expect(seen, [CallVideoNetworkClass.wifi]);
      sink!.success(<String, Object?>{'networkClass': 'cellular'});
      await flush();
      expect(seen, [CallVideoNetworkClass.wifi, CallVideoNetworkClass.cellular]);
      await sub.cancel();
      await source.close();
    });

    test('close fences late events and cannot restart', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      final done = Completer<void>();
      source.changes.listen((_) {}, onDone: done.complete);
      await source.start();
      await flush();
      expect(listens, 1);
      sink!.success(<String, Object?>{'networkClass': 'wifi'});
      await flush();
      final staleSink = sink!;
      final closing = source.close();
      expect(source.current, same(CallVideoQualityEnvironment.unknown));
      staleSink.success(<String, Object?>{'networkClass': 'cellular'});
      await closing;
      await flush();
      expect(source.current, same(CallVideoQualityEnvironment.unknown));
      expect(done.isCompleted, isTrue);
      expect(cancels, 1);
      await source.start();
      await flush();
      expect(listens, 1);
      await source.close();
      expect(cancels, 1);
    });

    test('a subscriber after close gets no snapshot and is done', () async {
      final source = PlatformCallVideoQualityEnvironmentSource(
        videoEnabled: true,
      );
      await source.close();
      final seen = <CallVideoQualityEnvironment>[];
      var finished = false;
      source.changes.listen(seen.add, onDone: () => finished = true);
      await flush();
      expect(seen, isEmpty);
      expect(finished, isTrue);
    });
  });
}
