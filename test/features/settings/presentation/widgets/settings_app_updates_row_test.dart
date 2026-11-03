import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_app_updates_row.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_app/features/update_check/presentation/update_required_gate.dart';
import 'package:flutter_app/features/update_check/presentation/update_store_launcher.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../features/update_check/support/fake_update_check_service.dart';

void main() {
  late FakeUpdateCheckService service;
  late UpdateCheckController controller;

  PackageInfo packageInfo() => PackageInfo(
    appName: 'Mknoon',
    packageName: 'com.mknoon.app',
    version: '1.0.1',
    buildNumber: '130',
  );

  Future<void> useStatus(
    UpdateAvailability availability, {
    UpdatePlatform platform = UpdatePlatform.ios,
  }) async {
    service = FakeUpdateCheckService(
      availability: availability,
      platform: platform,
    );
    controller = UpdateCheckController(service: service);
    addTearDown(controller.dispose);
    await controller.refresh(force: true);
  }

  Widget app({
    Locale locale = const Locale('en'),
    double textScale = 1,
    UpdateStoreLauncher? launch,
    Future<PackageInfo> Function()? loadPackageInfo,
    bool withController = true,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) {
      final media = MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      );
      return withController
          ? UpdateCheckScope(controller: controller, child: media)
          : media;
    },
    home: Scaffold(
      body: SingleChildScrollView(
        child: SettingsAppUpdatesRow(
          launchStore: launch ?? (_) async => true,
          loadPackageInfo: loadPackageInfo ?? () async => packageInfo(),
        ),
      ),
    ),
  );

  Future<void> pumpRow(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('current status shows installed version and build', (
    tester,
  ) async {
    await useStatus(UpdateAvailability.current);
    await pumpRow(tester, app());
    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Your version: 1.0.1 (130)'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Update now'), findsNothing);
    expect(service.checks, 1);
  });

  testWidgets('unknown does not claim current or show a check error', (
    tester,
  ) async {
    await useStatus(UpdateAvailability.unknown);
    await pumpRow(tester, app());
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Up to date'), findsNothing);
    expect(find.text('Update now'), findsNothing);
    expect(
      find.text("Couldn't open the store. Try updating again."),
      findsNothing,
    );
  });

  testWidgets(
    'no update scope still displays package metadata and neutral status',
    (tester) async {
      await useStatus(UpdateAvailability.unknown);
      await pumpRow(tester, app(withController: false));
      expect(find.text('Your version: 1.0.1 (130)'), findsOneWidget);
      expect(find.text('Status unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable package metadata does not block the row or invent a version',
    (tester) async {
      await useStatus(UpdateAvailability.unknown);
      await pumpRow(
        tester,
        app(loadPackageInfo: () async => throw StateError('unavailable')),
      );
      expect(find.text('App updates'), findsOneWidget);
      expect(find.text('Status unavailable'), findsOneWidget);
      expect(find.textContaining('Your version:'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in UpdatePlatform.values) {
    testWidgets('${platform.name} opens the existing platform update link', (
      tester,
    ) async {
      await useStatus(UpdateAvailability.available, platform: platform);
      final launches = <Uri>[];
      await pumpRow(
        tester,
        app(
          launch: (uri) async {
            launches.add(uri);
            return true;
          },
        ),
      );
      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(launches, [updateStoreUrlFor(platform)]);
      expect(
        launches.single.toString(),
        platform == UpdatePlatform.ios
            ? updateStoreUrlIos
            : updateStoreUrlAndroid,
      );
    });
  }

  testWidgets(
    'store refusal and exception stay retryable and success clears feedback',
    (tester) async {
      await useStatus(UpdateAvailability.available);
      var attempts = 0;
      await pumpRow(
        tester,
        app(
          launch: (_) async {
            attempts++;
            if (attempts == 2) throw StateError('launch failed');
            return attempts >= 3;
          },
        ),
      );
      for (var attempt = 1; attempt <= 3; attempt++) {
        await tester.tap(find.text('Update now'));
        await tester.pump();
        expect(attempts, attempt);
        expect(
          find.text("Couldn't open the store. Try updating again."),
          attempt < 3 ? findsOneWidget : findsNothing,
        );
        expect(find.text('Update now'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a pending store handoff cannot launch twice', (tester) async {
    await useStatus(UpdateAvailability.available);
    final handoff = Completer<bool>();
    var launches = 0;
    await pumpRow(
      tester,
      app(
        launch: (_) {
          launches++;
          return handoff.future;
        },
      ),
    );
    await tester.tap(find.text('Update now'));
    await tester.pump();
    await tester.tap(find.text('Update now'));
    expect(launches, 1);
    handoff.complete(true);
    await tester.pump();
  });

  testWidgets(
    'manual refresh checks once and retains known status while pending',
    (tester) async {
      await useStatus(UpdateAvailability.current);
      await pumpRow(tester, app());
      service.gate = Completer<void>();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      expect(service.checks, 2);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.availability = UpdateAvailability.available;
      service.gate!.complete();
      await tester.pump();
      expect(find.text('Update now'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'opening Settings checks when due and does not wait on package metadata',
    (tester) async {
      await useStatus(UpdateAvailability.current);
      service.due = true;
      final metadata = Completer<PackageInfo>();
      await pumpRow(tester, app(loadPackageInfo: () => metadata.future));
      expect(service.checks, 2);
      expect(find.text('App updates'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      metadata.complete(packageInfo());
      await tester.pump();
      await tester.pump();
      expect(find.text('Your version: 1.0.1 (130)'), findsOneWidget);
    },
  );

  testWidgets(
    'late metadata and store results after closing Settings are harmless',
    (tester) async {
      await useStatus(UpdateAvailability.available);
      final metadata = Completer<PackageInfo>();
      final store = Completer<bool>();
      await pumpRow(
        tester,
        app(
          loadPackageInfo: () => metadata.future,
          launch: (_) => store.future,
        ),
      );
      await tester.tap(find.text('Update now'));
      await tester.pumpWidget(const SizedBox.shrink());
      metadata.complete(packageInfo());
      store.complete(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in [
    ('en', 'App updates', 'Up to date', 'Update now'),
    ('de', 'App-Updates', 'Auf dem neuesten Stand', 'Jetzt aktualisieren'),
    ('ar', 'تحديث التطبيق', 'التطبيق محدّث', 'حدّث الآن'),
  ]) {
    testWidgets(
      '${entry.$1} narrow large text keeps status and action reachable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await useStatus(UpdateAvailability.current);
        await pumpRow(tester, app(locale: Locale(entry.$1), textScale: 2));
        expect(find.text(entry.$2), findsOneWidget);
        expect(find.text(entry.$3), findsOneWidget);
        if (entry.$1 == 'ar') {
          expect(
            Directionality.of(tester.element(find.text(entry.$2))),
            TextDirection.rtl,
          );
        }
        expect(tester.takeException(), isNull);
        service.availability = UpdateAvailability.available;
        await controller.refresh(force: true);
        await tester.pump();
        expect(find.text(entry.$4), findsOneWidget);
        await tester.ensureVisible(find.text(entry.$4));
        expect(
          tester.getSize(find.widgetWithText(TextButton, entry.$4)).height,
          greaterThanOrEqualTo(44),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
