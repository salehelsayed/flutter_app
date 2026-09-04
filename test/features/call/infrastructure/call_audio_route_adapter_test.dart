import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('enumerates only coarse app-owned output routes', () async {
    final adapter = CallAudioRouteAdapter(
      enumerateOutputs: () async => const <CallAudioOutputRoute>[
        CallAudioOutputRoute.wiredHeadset,
        CallAudioOutputRoute.bluetooth,
        CallAudioOutputRoute.earpiece,
      ],
      selectOutput: (_) async {},
      setSpeakerphone: (_) async {},
    );

    final routes = await adapter.supportedOutputRoutes();

    expect(routes, <CallAudioOutputRoute>[
      CallAudioOutputRoute.systemDefault,
      CallAudioOutputRoute.earpiece,
      CallAudioOutputRoute.speaker,
      CallAudioOutputRoute.wiredHeadset,
      CallAudioOutputRoute.bluetooth,
    ]);
  });

  test('uses speaker operation and coarse route selection', () async {
    final speakerValues = <bool>[];
    final selectedRoutes = <String>[];
    final adapter = CallAudioRouteAdapter(
      enumerateOutputs: () async => const <CallAudioOutputRoute>[
        CallAudioOutputRoute.bluetooth,
      ],
      selectOutput: (route) async {
        selectedRoutes.add(route.name);
      },
      setSpeakerphone: (enabled) async {
        speakerValues.add(enabled);
      },
    );
    await adapter.supportedOutputRoutes();

    await adapter.selectOutputRoute(CallAudioOutputRoute.speaker);
    await adapter.selectOutputRoute(CallAudioOutputRoute.bluetooth);
    await adapter.selectOutputRoute(CallAudioOutputRoute.systemDefault);

    expect(speakerValues, <bool>[true, false]);
    expect(selectedRoutes, <String>['bluetooth']);
    expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
  });

  test(
    'unsupported selection is stable and never pretends to succeed',
    () async {
      var selections = 0;
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () async => const <CallAudioOutputRoute>[],
        selectOutput: (_) async => selections++,
        setSpeakerphone: null,
      );

      final first = adapter.selectOutputRoute(CallAudioOutputRoute.bluetooth);
      final second = adapter.selectOutputRoute(CallAudioOutputRoute.bluetooth);

      await expectLater(
        first,
        throwsA(
          isA<CallAudioRouteException>().having(
            (error) => error.code,
            'code',
            CallAudioRouteErrorCode.unsupported,
          ),
        ),
      );
      await expectLater(
        second,
        throwsA(
          isA<CallAudioRouteException>().having(
            (error) => error.code,
            'code',
            CallAudioRouteErrorCode.unsupported,
          ),
        ),
      );
      expect(selections, 0);
      expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
    },
  );

  test('selection failure does not leak platform identifier', () async {
    final adapter = CallAudioRouteAdapter(
      enumerateOutputs: () async => const <CallAudioOutputRoute>[
        CallAudioOutputRoute.bluetooth,
      ],
      selectOutput: (_) async => throw StateError('private plugin detail'),
      setSpeakerphone: (_) async {},
    );
    await adapter.supportedOutputRoutes();

    Object? failure;
    try {
      await adapter.selectOutputRoute(CallAudioOutputRoute.bluetooth);
    } catch (error) {
      failure = error;
    }

    expect(failure, isA<CallAudioRouteException>());
    expect(
      (failure! as CallAudioRouteException).code,
      CallAudioRouteErrorCode.selectionFailed,
    );
    expect('$failure', isNot(contains('private')));
    expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
  });

  test(
    'device changes invalidate stale route and observer closes cleanly',
    () async {
      void Function()? deviceChangeObserver;
      var observerRemovals = 0;
      var now = DateTime.utc(2026, 9, 4, 12);
      final adapter = CallAudioRouteAdapter(
        enumerateOutputs: () async => const <CallAudioOutputRoute>[],
        selectOutput: (_) async {},
        setSpeakerphone: (_) async {},
        installDeviceChangeObserver: (observer) {
          deviceChangeObserver = observer;
        },
        removeDeviceChangeObserver: () {
          observerRemovals++;
          deviceChangeObserver = null;
        },
        clock: () => now,
      );
      final routeChanges = <CallAudioOutputRoute>[];
      final subscription = adapter.outputRouteChanges.listen(routeChanges.add);

      await adapter.selectOutputRoute(CallAudioOutputRoute.speaker);
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);

      // The platform echoes the selection itself as a device change; that
      // echo must not undo the selection.
      deviceChangeObserver!();
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);
      expect(routeChanges, isEmpty);

      now = now.add(const Duration(seconds: 2));
      deviceChangeObserver!();

      expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
      expect(routeChanges, <CallAudioOutputRoute>[
        CallAudioOutputRoute.systemDefault,
      ]);

      await adapter.selectOutputRoute(CallAudioOutputRoute.speaker);
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);

      await adapter.close();
      expect(observerRemovals, 1);
      expect(deviceChangeObserver, isNull);
      await subscription.cancel();
    },
  );

  test(
    'production factory keeps flutter_webrtc behind infrastructure',
    () async {
      final adapter = CallAudioRouteAdapter.flutterWebRtc();

      expect(adapter, isA<CallAudioRoutePort>());

      await adapter.close();
    },
  );
}
