import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_model_delivery_controller.dart';

const _total = 2600000000;

Future<FakeModelDeliveryController> _openSheet(
  WidgetTester tester,
  ModelDeliveryState state, {
  Locale locale = const Locale('en'),
  VoidCallback? onFreeUpSpace,
}) async {
  final controller = FakeModelDeliveryController(state);
  await tester.pumpWidget(
    localizedApp(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPrivateTranslatorSheet(
              context,
              controller: controller,
              onFreeUpSpace: onFreeUpSpace,
            ),
            child: const Text('open'),
          ),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return controller;
}

bool _isEnabled(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .enabled;

void main() {
  for (final (language, message) in [
    ('en', 'Something went wrong. Please try again.'),
    ('ar', 'حدث خطأ ما. حاول مجددًا.'),
    ('de', 'Etwas ist schiefgelaufen. Bitte versuch es erneut.'),
  ]) {
    testWidgets('failed copy avoids retained-progress promise in $language', (
      tester,
    ) async {
      await _openSheet(tester, const ModelFailed(), locale: Locale(language));
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('reopening after freeing space refreshes admission without '
      'starting a download', (tester) async {
    final controller = FakeModelDeliveryController(
      const ModelNotEnoughSpace(
        totalBytes: _total,
        neededBytes: 2800000000,
        freeBytes: 1100000000,
      ),
    );
    var freeBytes = 1100000000;
    Completer<void>? pendingMeasurement;
    controller.onRefresh = () async {
      await pendingMeasurement?.future;
      if (freeBytes >= 2800000000) {
        controller.state.value = ModelNotDownloaded(
          totalBytes: _total,
          freeBytes: freeBytes,
          onWifi: true,
        );
      }
    };
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPrivateTranslatorSheet(
                context,
                controller: controller,
                onFreeUpSpace: () => freeBytes = 4000000000,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(_isEnabled(tester, 'Download on Wi-Fi'), isFalse);
    await tester.tap(find.text('Free up space'));
    await tester.pumpAndSettle();
    pendingMeasurement = Completer<void>();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsOneWidget);
    expect(_isEnabled(tester, 'Download on Wi-Fi'), isFalse);
    pendingMeasurement.complete();
    await tester.pumpAndSettle();
    expect(find.text('4.0 GB free'), findsOneWidget);
    expect(_isEnabled(tester, 'Download on Wi-Fi'), isTrue);
    expect(controller.refreshCalls, 2);
    expect(controller.calls, isEmpty);
  });

  testWidgets('2a offer on Wi-Fi: Download on Wi-Fi starts without mobile '
      'data, Not now closes', (tester) async {
    final controller = await _openSheet(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
    );
    expect(find.text('Your private translator'), findsOneWidget);
    expect(
      find.text('One download (2.6 GB). Works without internet.'),
      findsOneWidget,
    );
    expect(find.text('2.6 GB download'), findsOneWidget);
    expect(find.text('18.4 GB free'), findsOneWidget);
    expect(
      find.text('Nobody sees what you translate, not even Mknoon.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Download on Wi-Fi'));
    expect(controller.calls, ['start(allowMobileData: false)']);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsNothing);
  });

  testWidgets('2b offer on mobile data: the main button waits for Wi-Fi, the '
      'second one uses mobile data', (tester) async {
    final controller = await _openSheet(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: false,
      ),
    );
    expect(find.text('Not now'), findsNothing);
    await tester.tap(find.text('Download when on Wi-Fi'));
    await tester.tap(find.text('Use mobile data instead'));
    expect(controller.calls, [
      'start(allowMobileData: false)',
      'start(allowMobileData: true)',
    ]);
  });

  testWidgets('2c not enough space: download greyed, Free up space closes the '
      'sheet and opens Storage', (tester) async {
    var storageOpened = 0;
    final controller = await _openSheet(
      tester,
      const ModelNotEnoughSpace(
        totalBytes: _total,
        neededBytes: 2800000000,
        freeBytes: 1100000000,
      ),
      onFreeUpSpace: () => storageOpened++,
    );
    expect(find.text('Needs 2.8 GB'), findsOneWidget);
    expect(find.text('1.1 GB free'), findsOneWidget);
    expect(_isEnabled(tester, 'Download on Wi-Fi'), isFalse);

    await tester.tap(find.text('Free up space'));
    await tester.pumpAndSettle();
    expect(storageOpened, 1);
    expect(find.text('Your private translator'), findsNothing);
    expect(controller.calls, isEmpty);
  });

  testWidgets('3a progress: amount, time left, Pause pauses, Close keeps it '
      'going', (tester) async {
    final controller = await _openSheet(
      tester,
      const ModelDownloading(
        receivedBytes: 1100000000,
        totalBytes: _total,
        remaining: Duration(minutes: 5, seconds: 40),
      ),
    );
    expect(find.text('Getting translation ready'), findsOneWidget);
    expect(find.text('1.1 of 2.6 GB'), findsOneWidget);
    expect(find.text('about 6 min left'), findsOneWidget);
    expect(
      find.text(
        'You can close this. It keeps going, even if you leave Mknoon.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.42,
    );

    await tester.tap(find.text('Pause'));
    expect(controller.calls, ['pause']);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Getting translation ready'), findsNothing);
    expect(controller.calls, ['pause']);
  });

  for (final (name, state) in [
    (
      'waiting for Wi-Fi',
      const ModelWaitingForWifi(receivedBytes: 1100000000, totalBytes: _total),
    ),
    (
      'paused',
      const ModelPaused(receivedBytes: 1100000000, totalBytes: _total),
    ),
  ]) {
    testWidgets('3c $name: Use mobile data continues on mobile data', (
      tester,
    ) async {
      final controller = await _openSheet(tester, state);
      expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
      expect(find.text('1.1 of 2.6 GB'), findsOneWidget);
      expect(find.text('paused'), findsOneWidget);
      expect(
        find.text("It picks up where it stopped when you're back on Wi-Fi."),
        findsOneWidget,
      );
      await tester.tap(find.text('Use mobile data'));
      expect(controller.calls, ['start(allowMobileData: true)']);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Wi-Fi'), findsNothing);
    });
  }

  testWidgets('3d failed: Try again retries, Not now closes', (tester) async {
    final controller = await _openSheet(tester, const ModelFailed());
    expect(find.text("The download didn't finish"), findsOneWidget);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(controller.calls, ['retry']);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text("The download didn't finish"), findsNothing);
  });

  testWidgets('the sheet follows the controller in place and closes when '
      'ready', (tester) async {
    final controller = await _openSheet(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
    );
    controller.state.value = const ModelDownloading(
      receivedBytes: 260000000,
      totalBytes: _total,
    );
    await tester.pump();
    expect(find.text('Getting translation ready'), findsOneWidget);
    expect(find.text('0.3 of 2.6 GB'), findsOneWidget);
    expect(find.textContaining('min left'), findsNothing);

    controller.state.value = const ModelReady(sizeBytes: _total);
    await tester.pumpAndSettle();
    expect(find.text('Getting translation ready'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Arabic: the approved copy, laid out right to left', (
    tester,
  ) async {
    await _openSheet(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
      locale: const Locale('ar'),
    );
    final title = find.text('مترجمك الخاص');
    expect(title, findsOneWidget);
    expect(
      find.text('تنزيل واحد (2.6 غيغابايت). يعمل بدون إنترنت.'),
      findsOneWidget,
    );
    expect(find.text('لا أحد يرى ما تترجمه، ولا حتى مكنون.'), findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);

    final dot = tester.getRect(find.byIcon(Icons.circle));
    final privacy = tester.getRect(
      find.text('لا أحد يرى ما تترجمه، ولا حتى مكنون.'),
    );
    expect(dot.left, greaterThanOrEqualTo(privacy.right));

    final download = tester.getRect(find.text('تنزيل 2.6 غيغابايت'));
    final free = tester.getRect(find.text('18.4 غيغابايت متاحة'));
    expect(download.left, greaterThanOrEqualTo(free.right));
  });

  testWidgets('German: sizes use a decimal comma', (tester) async {
    await _openSheet(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
      locale: const Locale('de'),
    );
    expect(find.text('Dein privater Übersetzer'), findsOneWidget);
    expect(
      find.text('Ein Download (2,6 GB). Geht ohne Internet.'),
      findsOneWidget,
    );
    expect(find.text('18,4 GB frei'), findsOneWidget);
  });
}
