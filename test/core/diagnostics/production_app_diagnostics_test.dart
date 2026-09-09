import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/bootstrap/production_app_diagnostics.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _UnavailableStartupMetadata extends PathProviderPlatform {
  int supportDirectoryRequests = 0;
  Completer<String?>? pending;

  @override
  Future<String?> getApplicationSupportPath() async {
    supportDirectoryRequests++;
    if (pending != null) return pending!.future;
    throw StateError('startup metadata unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AppDiagnostics diagnostics;
  late PathProviderPlatform previousPathProvider;
  late _UnavailableStartupMetadata metadata;

  // Filesystem initialization runs in the test runner's real async setup,
  // before testWidgets enters its fake clock. The production helper's metadata
  // failure is deliberate: metadata must not suppress launch or observation by
  // an already initialized real collector.
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('startup-observation-');
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
    previousPathProvider = PathProviderPlatform.instance;
    metadata = _UnavailableStartupMetadata();
    PathProviderPlatform.instance = metadata;
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'real startup and first-time milestones survive diagnostic validation',
    () async {
      final phases = <String>{'app_start'};
      final calls = RegExp(r"StartupTiming\.instance\.mark\('([^']+)'\)");
      for (final path in [
        'lib/app/application_root.dart',
        'lib/app/bootstrap/production_application_bootstrap.dart',
        'lib/features/identity/presentation/startup_router.dart',
        'lib/features/home/presentation/screens/first_time_experience_wired.dart',
      ]) {
        phases.addAll(
          calls
              .allMatches(await File(path).readAsString())
              .map((match) => match.group(1)!),
        );
      }
      expect(
        phases,
        containsAll([
          'deferred_runtime_start_begin',
          'deferred_runtime_start_complete',
          'route_pushed',
          'p2p_startup_begin',
          'p2p_startup_complete',
          'fte_init_state',
          'fte_first_frame',
          'fte_qr_ready',
        ]),
      );

      for (final phase in phases) {
        StartupTiming.instance.mark(phase);
      }
      final events = await diagnostics.eventsForTesting();
      expect(
        events.map((event) => (event['values'] as Map)['phase']),
        orderedEquals(phases),
      );
      expect(events.every((event) => event['feature'] == 'startup'), isTrue);
      expect((await diagnostics.status())['droppedEvents'], 0);
    },
  );

  test(
    'unknown startup milestone text stays outside diagnostic reports',
    () async {
      StartupTiming.instance.mark('PRIVATE_STARTUP_MILESTONE');
      expect(await diagnostics.eventsForTesting(), isEmpty);
      expect((await diagnostics.status())['droppedEvents'], 1);
      expect(await diagnostics.exportPreview(), isNot(contains('PRIVATE_')));
    },
  );

  testWidgets(
    'pending diagnostic metadata cannot delay launch or lose the first frame',
    (tester) async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final pending = Completer<String?>();
      metadata.pending = pending;
      var launches = 0;
      Future<void>? launch;
      try {
        await tester.runAsync(() async {
          launch = runWithProductionAppDiagnostics(() async {
            launches++;
          });
          await Future<void>.value();
          expect(
            launches,
            1,
            reason: 'optional metadata must not own application readiness',
          );
          await launch;
        });
        await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
        await tester.runAsync(() async {
          pending.completeError(StateError('metadata unavailable'));
          // Let the controlled metadata future and its continuations drain.
          await Future<void>(() {});
          final events = await diagnostics.eventsForTesting();
          final startup = events.where((e) => e['feature'] == 'startup');
          expect(startup.where((e) => e['stage'] == 'start'), hasLength(1));
          expect(startup.where((e) => e['stage'] == 'present'), hasLength(1));
          expect(
            startup.where((e) => e['stage'] == 'finish').single['outcome'],
            'success',
          );
        });
      } finally {
        if (!pending.isCompleted) pending.completeError(StateError('cleanup'));
        await tester.runAsync(() async {
          await launch;
        });
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    },
  );

  testWidgets(
    'launch failure propagates while diagnostic metadata is pending',
    (tester) async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final pending = Completer<String?>();
      metadata.pending = pending;
      final original = StateError('PRIVATE_BOOTSTRAP_FAILURE');
      Object? caught;
      Future<void>? launch;
      try {
        await tester.runAsync(() async {
          launch =
              runWithProductionAppDiagnostics(() async {
                throw original;
              }).catchError((Object error) {
                caught = error;
              });
          await Future<void>(() {});
          expect(caught, same(original));
          expect(pending.isCompleted, isFalse);
          pending.completeError(StateError('metadata unavailable'));
          await Future<void>(() {});
          await tester.pumpWidget(const SizedBox());
          final startup = (await diagnostics.eventsForTesting()).where(
            (e) => e['feature'] == 'startup',
          );
          expect(startup.where((e) => e['stage'] == 'present'), isEmpty);
          expect(
            startup.where((e) => e['stage'] == 'finish').single['outcome'],
            'failed',
          );
          expect(
            await diagnostics.exportPreview(),
            isNot(contains('PRIVATE_')),
          );
        });
      } finally {
        if (!pending.isCompleted) pending.completeError(StateError('cleanup'));
        await tester.runAsync(() async {
          await launch;
        });
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    },
  );

  testWidgets(
    'launch runs once and startup succeeds only after a Flutter frame',
    (tester) async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      var launches = 0;
      var widgetBuilds = 0;
      try {
        await tester.runAsync(
          () => runWithProductionAppDiagnostics(() async {
            launches++;
            await Future<void>.value();
          }),
        );
        expect(launches, 1);
        expect(metadata.supportDirectoryRequests, 1);
        final beforeFrame = (await tester.runAsync(
          diagnostics.eventsForTesting,
        ))!;
        final startupBefore = beforeFrame.where(
          (e) => e['feature'] == 'startup',
        );
        expect(startupBefore.where((e) => e['stage'] == 'start'), hasLength(1));
        expect(startupBefore.where((e) => e['stage'] == 'finish'), isEmpty);
        expect(startupBefore.where((e) => e['stage'] == 'present'), isEmpty);

        // Run the frame callback in real async too: its diagnostic write must
        // not strand filesystem completion in the widget test's fake clock.
        await tester.runAsync(
          () => tester.pumpWidget(
            Builder(
              builder: (_) {
                widgetBuilds++;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(
          widgetBuilds,
          1,
          reason: 'a real widget frame reached the binding',
        );
        final afterFrame = (await tester.runAsync(
          diagnostics.eventsForTesting,
        ))!;
        final startup = afterFrame
            .where((e) => e['feature'] == 'startup')
            .toList();
        final presented = startup.singleWhere((e) => e['stage'] == 'present');
        final finished = startup.singleWhere((e) => e['stage'] == 'finish');
        expect(presented['outcome'], 'ok');
        expect(presented['values'], containsPair('firstFrame', true));
        expect(finished['outcome'], 'success');
        expect(finished['traceId'], presented['traceId']);
        expect(finished['attemptId'], presented['attemptId']);

        await tester.runAsync(() => tester.pump());
        final repeated = (await tester.runAsync(diagnostics.eventsForTesting))!;
        expect(
          repeated.where(
            (e) => e['feature'] == 'startup' && e['stage'] == 'finish',
          ),
          hasLength(1),
        );
        expect(
          repeated.where(
            (e) => e['feature'] == 'startup' && e['stage'] == 'present',
          ),
          hasLength(1),
        );
        expect(launches, 1);
      } finally {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    },
  );

  for (final asynchronous in [false, true]) {
    testWidgets('launch failure is rethrown unchanged and stays failed after '
        'a frame (asynchronous: $asynchronous)', (tester) async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final original = asynchronous
          ? const FormatException('PRIVATE_LAUNCH_PAYLOAD')
          : StateError('PRIVATE_LAUNCH_PATH');
      final chainedFlutter = <Object>[];
      final chainedPlatform = <Object>[];
      var launches = 0;
      Object? caught;
      try {
        FlutterError.onError = (details) =>
            chainedFlutter.add(details.exception);
        PlatformDispatcher.instance.onError = (error, stack) {
          chainedPlatform.add(error);
          return true;
        };
        // Catch inside runAsync so the widget harness cannot translate the
        // error into tester.takeException; this verifies the helper's caller
        // receives the original object directly.
        await tester.runAsync(() async {
          try {
            await runWithProductionAppDiagnostics(() {
              launches++;
              if (asynchronous) return Future<void>.error(original);
              throw original;
            });
          } catch (error) {
            caught = error;
          }
        });
        expect(caught, same(original));
        expect(launches, 1);
        expect(metadata.supportDirectoryRequests, 1);

        // The installed observers must retain the previous handlers' policy.
        final frameworkFailure = StateError('PRIVATE_FRAMEWORK_CANARY');
        final platformFailure = StateError('PRIVATE_PLATFORM_CANARY');
        bool? platformHandled;
        await tester.runAsync(() async {
          FlutterError.onError!(
            FlutterErrorDetails(exception: frameworkFailure),
          );
          platformHandled = PlatformDispatcher.instance.onError!(
            platformFailure,
            StackTrace.current,
          );
        });
        expect(platformHandled, isTrue);
        expect(chainedFlutter, [same(frameworkFailure)]);
        expect(chainedPlatform, [same(platformFailure)]);

        await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
        final events = (await tester.runAsync(diagnostics.eventsForTesting))!;
        final startup = events.where((e) => e['feature'] == 'startup').toList();
        expect(startup.where((e) => e['stage'] == 'start'), hasLength(1));
        final finished = startup.singleWhere((e) => e['stage'] == 'finish');
        expect(finished['outcome'], 'failed');
        expect(finished['reason'], 'bootstrap');
        expect(startup.where((e) => e['stage'] == 'present'), isEmpty);
        expect(jsonEncode(events), isNot(contains('PRIVATE_')));
        expect(launches, 1);
      } finally {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    });
  }
}
