import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

// Fast local run:
//   flutter test integration_test/identity_progress_performance_test.dart -d macos
//
// Profile-mode validation:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/identity_progress_performance_test.dart \
//     -d <device-id> --profile

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    savedIdentity = identity;
  }
}

const _fakeIdentityJson = {
  'peerId': '12D3KooWPerfPeerId',
  'publicKey': 'publicKeyBase64',
  'privateKey': 'privateKeyBase64',
  'mnemonic12':
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  'createdAt': '2024-01-01T00:00:00Z',
  'updatedAt': '2024-01-01T00:00:00Z',
};

const _fakeMlKemResponse = {
  'ok': true,
  'publicKey': 'mlkemPublicKeyBase64',
  'secretKey': 'mlkemSecretKeyBase64',
};

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _pumpPastAnimations(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1300));
}

class _FrameTimingCollector {
  final _timings = <FrameTiming>[];
  TimingsCallback? _callback;

  void start() {
    _timings.clear();
    _callback = (List<FrameTiming> timings) => _timings.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(_callback!);
  }

  Future<void> stop() async {
    if (_callback == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    SchedulerBinding.instance.removeTimingsCallback(_callback!);
    _callback = null;
  }

  bool get hasData => _timings.isNotEmpty;

  void printSummary(String label) {
    if (_timings.isEmpty) {
      debugPrint('[$label] No frame data');
      return;
    }

    final buildTimesMs =
        _timings
            .map((timing) => timing.buildDuration.inMicroseconds / 1000.0)
            .toList()
          ..sort();
    final average = buildTimesMs.reduce((a, b) => a + b) / buildTimesMs.length;
    final worst = buildTimesMs.last;

    debugPrint(
      '[$label] Frames: ${buildTimesMs.length} | '
      'Avg: ${average.toStringAsFixed(2)}ms | '
      'Worst: ${worst.toStringAsFixed(2)}ms',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Identity progress route performance', () {
    testWidgets(
      'pushes a rendered progress frame before identity generation begins',
      (tester) async {
        final repo = _FakeIdentityRepo();
        final generateCompleter = Completer<Map<String, dynamic>>();
        final firstFrameCompleter = Completer<void>();
        final events = <String>[];
        final collector = _FrameTimingCollector();
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        await tester.pumpWidget(
          _wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () {
                events.add('generate-start');
                return generateCompleter.future;
              },
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (progressContext) async {
                Navigator.of(progressContext).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text('Done'))),
                  ),
                );
              },
              onProgressRouteFirstFrame: () {
                events.add('progress-first-frame');
                if (!firstFrameCompleter.isCompleted) {
                  firstFrameCompleter.complete();
                }
              },
            ),
          ),
        );
        await _pumpPastAnimations(tester);

        collector.start();

        final newHereFinder = find.text(l10n.onboarding_new_here);
        expect(newHereFinder, findsOneWidget);
        await tester.tap(newHereFinder);
        expect(
          events,
          isNot(contains('generate-start')),
          reason: 'generation should wait until the progress route paints',
        );

        await tester.pump();
        await firstFrameCompleter.future.timeout(const Duration(seconds: 5));

        expect(
          events,
          equals(<String>['progress-first-frame', 'generate-start']),
          reason:
              'the first rendered progress frame must land before generation starts',
        );

        generateCompleter.complete({'ok': true, 'identity': _fakeIdentityJson});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        await collector.stop();
        collector.printSummary('Identity progress route push');
        expect(
          collector.hasData,
          isTrue,
          reason:
              'No FrameTiming data collected; rerun on macOS/iOS/Android for a real engine-backed validation',
        );

        expect(find.text('Done'), findsOneWidget);
      },
    );
  });
}
