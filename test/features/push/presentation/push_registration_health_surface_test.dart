import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_surface.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_warning.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({
    required Locale locale,
    required PushRegistrationHealthNotifier notifier,
    VoidCallback? onRetry,
    VoidCallback? onOpenNotificationSettings,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PushRegistrationHealthWarning(
          healthListenable: notifier,
          onRetry: onRetry ?? () {},
          onOpenNotificationSettings: onOpenNotificationSettings ?? () {},
        ),
      ),
    );
  }

  testWidgets('healthy state is hidden and unhealthy state clears live', (
    tester,
  ) async {
    final notifier = PushRegistrationHealthNotifier();
    await tester.pumpWidget(
      wrap(locale: const Locale('en'), notifier: notifier),
    );
    expect(
      find.byKey(const ValueKey('push-registration-health-warning')),
      findsNothing,
    );

    notifier.publish(
      PushRegistrationHealthRecord.permissionDenied(
        at: DateTime.utc(2026, 8, 1),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('push-registration-health-warning')),
      findsOneWidget,
    );

    notifier.publish(
      PushRegistrationHealthRecord.healthy(at: DateTime.utc(2026, 8, 1, 1)),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('push-registration-health-warning')),
      findsNothing,
    );
    notifier.dispose();
  });

  testWidgets(
    'permission warning is localized and opens notification settings',
    (tester) async {
      const expectedCopy = <String, ({String title, String action})>{
        'en': (
          title: 'Notifications need attention',
          action: 'Open notification settings',
        ),
        'de': (
          title: 'Benachrichtigungen prüfen',
          action: 'Benachrichtigungseinstellungen öffnen',
        ),
        'ar': (
          title: 'تحتاج الإشعارات إلى انتباهك',
          action: 'فتح إعدادات الإشعارات',
        ),
      };

      for (final entry in expectedCopy.entries) {
        final notifier = PushRegistrationHealthNotifier();
        notifier.publish(
          PushRegistrationHealthRecord.permissionDenied(
            at: DateTime.utc(2026, 8, 1),
          ),
        );
        var settingsCalls = 0;
        await tester.pumpWidget(
          wrap(
            locale: Locale(entry.key),
            notifier: notifier,
            onOpenNotificationSettings: () => settingsCalls++,
          ),
        );

        expect(find.text(entry.value.title), findsOneWidget);
        expect(find.text(entry.value.action), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('push-registration-health-action')),
        );
        expect(settingsCalls, 1);
        notifier.dispose();
      }
    },
  );

  testWidgets('safe transient reason uses Retry and never renders raw errors', (
    tester,
  ) async {
    final notifier = PushRegistrationHealthNotifier();
    notifier.publish(
      PushRegistrationHealthRecord.retrying(
        reason: PushRegistrationHealthReason.exception,
        consecutiveFailures: 3,
        firstFailureAt: DateTime.utc(2026, 8, 1),
        lastAttemptAt: DateTime.utc(2026, 8, 1, 1),
      ),
    );
    var retryCalls = 0;
    await tester.pumpWidget(
      wrap(
        locale: const Locale('en'),
        notifier: notifier,
        onRetry: () => retryCalls++,
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('push-registration-health-action')),
    );
    expect(retryCalls, 1);
    notifier.dispose();
  });

  testWidgets(
    'one warning owner covers Feed Orbit Settings and Posts on a short screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final notifier = PushRegistrationHealthNotifier();
      notifier.publish(
        PushRegistrationHealthRecord.permissionDenied(
          at: DateTime.utc(2026, 8, 1),
        ),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      var reachableActionCalls = 0;
      var settingsCalls = 0;
      Widget route(String name) => Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              Text(name, key: ValueKey('health-route-$name')),
              const SizedBox(height: 680),
              TextButton(
                key: ValueKey('health-route-action-$name'),
                onPressed: () => reachableActionCalls++,
                child: Text('$name action'),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => PushRegistrationHealthSurface(
            healthListenable: notifier,
            onRetry: () {},
            onOpenNotificationSettings: () => settingsCalls++,
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: '/feed',
          routes: {
            '/feed': (_) => route('Feed'),
            '/orbit': (_) => route('Orbit'),
            '/settings': (_) => route('Settings'),
            '/posts': (_) => route('Posts'),
          },
        ),
      );

      for (final name in <String>['Feed', 'Orbit', 'Settings', 'Posts']) {
        final routeName = '/${name.toLowerCase()}';
        if (name != 'Feed') {
          navigatorKey.currentState!.pushReplacementNamed(routeName);
          await tester.pumpAndSettle();
        }
        expect(find.byKey(ValueKey('health-route-$name')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('push-registration-health-warning')),
          findsOneWidget,
        );
        final action = find.byKey(ValueKey('health-route-action-$name'));
        await tester.ensureVisible(action);
        await tester.tap(action);
      }
      expect(reachableActionCalls, 4);

      await tester.tap(
        find.byKey(const ValueKey('push-registration-health-action')),
      );
      expect(settingsCalls, 1);
      notifier.dispose();
    },
  );

  test('production composes one shared account-bound health surface', () {
    final root = File('lib/app/application_root.dart').readAsStringSync();
    final bootstrap = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();

    expect('PushRegistrationHealthSurface('.allMatches(root), hasLength(1));
    expect(root, contains('pushRegistrationHealthNotifier?.dispose();'));
    expect(root, contains('PlatformPushNotificationSettingsGateway'));
    expect(root, contains('pushRegistration?.beginAccountBindingCutover();'));
    expect(
      root,
      contains('pushRegistration?.completeAccountBindingCutover();'),
    );
    expect(bootstrap, contains('ResolvingPushRegistrationHealthStore('));
    expect(bootstrap, contains('accountPeerId: identity.peerId'));
    expect(bootstrap, contains('installationId: transportPeerId'));
    expect(
      bootstrap,
      contains('healthNotifier: pushRegistrationHealthNotifier'),
    );
    expect(
      bootstrap,
      contains(
        'pushRegistrationHealthNotifier: pushRegistrationHealthNotifier',
      ),
    );

    for (final path in <String>[
      'lib/features/feed/presentation/screens/feed_wired.dart',
      'lib/features/orbit/presentation/screens/orbit_wired.dart',
      'lib/features/settings/presentation/screens/settings_wired.dart',
      'lib/features/posts/presentation/screens/posts_wired.dart',
    ]) {
      final routeSource = File(path).readAsStringSync();
      expect(routeSource, isNot(contains('PushRegistrationHealthSurface(')));
      expect(routeSource, isNot(contains('PushRegistrationHealthWarning(')));
    }
  });
}
