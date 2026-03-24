import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/navigation/startup_route_transition.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_progress_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? savedIdentity;
  Completer<void>? saveCompleter;
  bool shouldThrowOnSave = false;

  @override
  Future<IdentityModel?> loadIdentity() async => savedIdentity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    if (shouldThrowOnSave) {
      throw Exception('DB write failed');
    }
    savedIdentity = identity;
    if (saveCompleter != null) {
      await saveCompleter!.future;
    }
  }
}

const _fakeIdentityJson = {
  'peerId': '12D3KooWTestPeerId',
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

void main() {
  Widget wrap(Widget child, {List<NavigatorObserver>? navigatorObservers}) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
        navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      );

  Future<void> pumpPastAnimations(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1300));
  }

  Opacity findChoiceCardOpacity(WidgetTester tester, String title) {
    return tester.widget<Opacity>(
      find.byKey(ValueKey('choice-card-opacity-$title')),
    );
  }

  group('IdentityChoiceWired', () {
    testWidgets(
      'tap on "I\'m new here" pushes progress route before generation completes',
      (tester) async {
        final repo = _FakeIdentityRepo();
        final generateCompleter = Completer<Map<String, dynamic>>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () => generateCompleter.future,
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
            ),
            navigatorObservers: [observer],
          ),
        );
        await pumpPastAnimations(tester);
        final initialPushCount = observer.pushCount;

        await tester.tap(find.text("I'm new here"));
        await tester.pump(const Duration(milliseconds: 20));
        expect(observer.pushCount, initialPushCount + 1);

        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(IdentityProgressScreen), findsOneWidget);
        expect(find.text('Creating your secure identity'), findsOneWidget);
      },
    );

    testWidgets(
      'identity generation waits until after the pushed progress route gets a frame',
      (tester) async {
        final repo = _FakeIdentityRepo();
        final generateCompleter = Completer<Map<String, dynamic>>();
        final observer = _RecordingNavigatorObserver();
        final events = <String>[];

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () {
                events.add('generate-start');
                return generateCompleter.future;
              },
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
              onProgressRouteFirstFrame: () {
                events.add('progress-first-frame');
              },
            ),
            navigatorObservers: [observer],
          ),
        );
        await pumpPastAnimations(tester);
        final initialPushCount = observer.pushCount;

        await tester.tap(find.text("I'm new here"));

        expect(observer.pushCount, initialPushCount + 1);
        expect(
          events,
          isNot(contains('generate-start')),
          reason: 'generate should wait for the pushed route to finish a frame',
        );
        expect(
          events,
          isNot(contains('progress-first-frame')),
          reason: 'the route has not painted before the next frame is pumped',
        );

        await tester.pump();

        expect(
          events,
          equals(<String>['progress-first-frame', 'generate-start']),
          reason:
              'the progress route must render a frame before generation begins',
        );
      },
    );

    testWidgets(
      'progress route first-frame hook fires only once across stage updates',
      (tester) async {
        final repo = _FakeIdentityRepo()..saveCompleter = Completer<void>();
        final generateCompleter = Completer<Map<String, dynamic>>();
        var firstFrameCallbacks = 0;

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () => generateCompleter.future,
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
              onProgressRouteFirstFrame: () {
                firstFrameCallbacks += 1;
              },
            ),
          ),
        );
        await pumpPastAnimations(tester);

        await tester.tap(find.text("I'm new here"));
        await tester.pump(const Duration(milliseconds: 200));

        generateCompleter.complete({'ok': true, 'identity': _fakeIdentityJson});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          firstFrameCallbacks,
          1,
          reason: 'stage transitions should not re-report the initial frame',
        );
      },
    );

    testWidgets('buttons visually disable during identity generation handoff', (
      tester,
    ) async {
      final repo = _FakeIdentityRepo();
      final generateCompleter = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        wrap(
          IdentityChoiceWired(
            repository: repo,
            callIdentityGenerate: () => generateCompleter.future,
            callIdentityRestore: (_) async => {'ok': true},
            callMlKemKeygen: () async => _fakeMlKemResponse,
            onNavigateToMain: (_) async {},
          ),
        ),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.text("I'm new here"));
      await tester.pump();

      expect(findChoiceCardOpacity(tester, "I'm new here").opacity, 0.5);
      expect(findChoiceCardOpacity(tester, 'Load my key').opacity, 0.5);
    });

    testWidgets('progress route advances from generating_keys to saving', (
      tester,
    ) async {
      final repo = _FakeIdentityRepo()..saveCompleter = Completer<void>();
      final generateCompleter = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        wrap(
          IdentityChoiceWired(
            repository: repo,
            callIdentityGenerate: () => generateCompleter.future,
            callIdentityRestore: (_) async => {'ok': true},
            callMlKemKeygen: () async => _fakeMlKemResponse,
            onNavigateToMain: (_) async {},
          ),
        ),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.text("I'm new here"));
      await tester.pump(const Duration(milliseconds: 200));

      generateCompleter.complete({'ok': true, 'identity': _fakeIdentityJson});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Securing your identity'), findsOneWidget);
      expect(find.text('Almost there.'), findsOneWidget);
    });

    testWidgets(
      'successful generation hands off to main from the progress route context',
      (tester) async {
        final repo = _FakeIdentityRepo();
        var navigateCalls = 0;

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () async => {
                'ok': true,
                'identity': _fakeIdentityJson,
              },
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (progressContext) async {
                navigateCalls += 1;
                await Navigator.of(progressContext).pushAndRemoveUntil(
                  buildStartupReplacementRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('First-time setup')),
                    ),
                  ),
                  (_) => false,
                );
              },
            ),
          ),
        );
        await pumpPastAnimations(tester);

        await tester.tap(find.text("I'm new here"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(navigateCalls, 1);
        expect(find.byType(IdentityProgressScreen), findsNothing);
        expect(find.text("I'm new here"), findsNothing);
        expect(find.text('First-time setup'), findsOneWidget);
      },
    );

    testWidgets(
      'core lib failure dismisses progress route and shows failed to generate identity snackbar',
      (tester) async {
        final repo = _FakeIdentityRepo();

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () async => {
                'ok': false,
                'errorCode': 'KEYGEN_FAILED',
                'errorMessage': 'Key generation failed',
              },
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
            ),
          ),
        );
        await pumpPastAnimations(tester);

        await tester.tap(find.text("I'm new here"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(IdentityProgressScreen), findsNothing);
        expect(find.text("I'm new here"), findsOneWidget);
        expect(find.text('Failed to generate identity'), findsOneWidget);
      },
    );

    testWidgets(
      'db save failure dismisses progress route and shows failed to save identity snackbar',
      (tester) async {
        final repo = _FakeIdentityRepo()..shouldThrowOnSave = true;

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () async => {
                'ok': true,
                'identity': _fakeIdentityJson,
              },
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
            ),
          ),
        );
        await pumpPastAnimations(tester);

        await tester.tap(find.text("I'm new here"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(IdentityProgressScreen), findsNothing);
        expect(find.text("I'm new here"), findsOneWidget);
        expect(find.text('Failed to save identity'), findsOneWidget);
      },
    );

    testWidgets(
      'repeated taps while generation is in flight do not push a second progress route',
      (tester) async {
        final repo = _FakeIdentityRepo();
        final generateCompleter = Completer<Map<String, dynamic>>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          wrap(
            IdentityChoiceWired(
              repository: repo,
              callIdentityGenerate: () => generateCompleter.future,
              callIdentityRestore: (_) async => {'ok': true},
              callMlKemKeygen: () async => _fakeMlKemResponse,
              onNavigateToMain: (_) async {},
            ),
            navigatorObservers: [observer],
          ),
        );
        await pumpPastAnimations(tester);
        final initialPushCount = observer.pushCount;

        await tester.tap(find.text("I'm new here"));
        await tester.tap(find.text("I'm new here"), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));
        expect(observer.pushCount, initialPushCount + 1);

        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byType(IdentityProgressScreen), findsOneWidget);
      },
    );
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushCount += 1;
  }
}
