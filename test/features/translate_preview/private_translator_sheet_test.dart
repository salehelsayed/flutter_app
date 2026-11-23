import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/private_translator_settings_section.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/helpers/readability_test_helpers.dart';
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

({Color middle, Color tail}) _paintedProgressColors(WidgetTester tester) {
  final progressPaint = find.descendant(
    of: find.byType(LinearProgressIndicator),
    matching: find.byType(CustomPaint),
  );
  final size = tester.getSize(progressPaint);
  final middlePoint = Offset(size.width / 2, size.height / 2);
  final tailPoint = Offset(size.width * 0.875, size.height / 2);
  Color? middle;
  Color? tail;
  expect(
    progressPaint,
    paints..everything((method, args) {
      final bounds = switch (method) {
        #drawRect => args[0] as Rect,
        #drawRRect => (args[0] as RRect).outerRect,
        _ => null,
      };
      if (bounds != null) {
        final color = (args[1] as Paint).color;
        if (bounds.contains(middlePoint)) middle = color;
        if (bounds.contains(tailPoint)) tail = color;
      }
      return true;
    }),
  );
  expect(middle, isNotNull, reason: 'the center of the bar is painted');
  expect(tail, isNotNull, reason: 'the remaining track is painted');
  return (middle: middle!, tail: tail!);
}

void _testDownloadProgress(
  String surface,
  Widget Function(ModelDeliveryController) build,
) {
  final theme = AppTheme.darkTheme.copyWith(platform: TargetPlatform.android);

  Future<FakeModelDeliveryController> pumpDownload(
    WidgetTester tester,
    ModelDownloading state,
  ) async {
    final controller = FakeModelDeliveryController(state);
    addTearDown(() {
      controller.state.dispose();
      controller.deviceSupported.dispose();
      controller.allowMobileData.dispose();
      controller.memoryNoticePending.dispose();
    });
    await tester.pumpWidget(
      localizedApp(
        Theme(data: theme, child: Scaffold(body: build(controller))),
      ),
    );
    return controller;
  }

  testWidgets('BL-46 $surface shows progress against a contrasting track', (
    tester,
  ) async {
    final controller = await pumpDownload(
      tester,
      const ModelDownloading(
        receivedBytes: 650000000,
        totalBytes: _total,
        remaining: Duration(minutes: 6),
      ),
    );
    final progress = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(progress).value, 0.25);
    final quarter = _paintedProgressColors(tester);
    expect(quarter.middle, quarter.tail);

    controller.state.value = const ModelDownloading(
      receivedBytes: 1950000000,
      totalBytes: _total,
      remaining: Duration(minutes: 2),
    );
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(progress).value, 0.75);
    final threeQuarters = _paintedProgressColors(tester);
    expect(threeQuarters.tail, quarter.tail);
    expectComponentContrast(
      threeQuarters.middle,
      Color.alphaBlend(threeQuarters.tail, theme.colorScheme.surface),
      reason: 'the growing fill must be distinguishable from the track',
    );
  }, timeout: const Timeout(Duration(seconds: 3)));

  testWidgets('BL-46 $surface shows indeterminate progress without a total', (
    tester,
  ) async {
    await pumpDownload(
      tester,
      const ModelDownloading(receivedBytes: 650000000, totalBytes: 0),
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  }, timeout: const Timeout(Duration(seconds: 3)));
}

void main() {
  _testDownloadProgress(
    'download sheet',
    (controller) => PrivateTranslatorSheet(controller: controller),
  );
  _testDownloadProgress(
    'Settings',
    (controller) => PrivateTranslatorSettingsSection(controller: controller),
  );

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
        'You can leave this screen. Your download can continue in the '
        'background and picks up where it stopped.',
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

  testWidgets(
    'download explains background resume and keeps progress on reopen',
    (tester) async {
      const bound = Duration(seconds: 3);
      final controller = await _openSheet(
        tester,
        const ModelDownloading(receivedBytes: 1100000000, totalBytes: _total),
      ).timeout(bound);
      final progress = find.byType(LinearProgressIndicator);
      expect(tester.widget<LinearProgressIndicator>(progress).value, 0.42);

      await tester.tap(find.text('Close')).timeout(bound);
      await tester.pump().timeout(bound);
      await tester.pump(const Duration(milliseconds: 350)).timeout(bound);
      expect(progress, findsNothing);

      await tester.tap(find.text('open')).timeout(bound);
      await tester.pump().timeout(bound);
      await tester.pump(const Duration(milliseconds: 350)).timeout(bound);
      expect(tester.widget<LinearProgressIndicator>(progress).value, 0.42);
      expect(controller.calls, isEmpty);

      await tester.tap(find.text('Pause')).timeout(bound);
      expect(controller.calls, ['pause']);
      expect(
        find.text(
          'You can leave this screen. Your download can continue in the '
          'background and picks up where it stopped.',
        ),
        findsOneWidget,
        reason:
            'the download sheet explains background continuation and resume',
      );
    },
  );

  testWidgets(
    '3c waiting for Wi-Fi: Use mobile data continues on mobile data',
    (tester) async {
      const bound = Duration(seconds: 3);
      final controller = await _openSheet(
        tester,
        const ModelWaitingForWifi(
          receivedBytes: 1100000000,
          totalBytes: _total,
        ),
      ).timeout(bound);
      expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
      expect(find.text('1.1 of 2.6 GB'), findsOneWidget);
      expect(find.text('paused'), findsOneWidget);
      expect(
        find.textContaining("when you're back online to check your download."),
        findsOneWidget,
      );
      controller.state.value = const ModelWaitingForWifi(
        receivedBytes: 1100000000,
        totalBytes: _total,
        resumesInBackground: true,
      );
      await tester.pump().timeout(bound);
      expect(
        find.text(
          'Your download is safe at 42%. It continues by itself when '
          "you're back online.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Use mobile data')).timeout(bound);
      expect(controller.calls, ['start(allowMobileData: true)']);
      await tester.tap(find.text('Close')).timeout(bound);
      await tester.pumpAndSettle().timeout(bound);
      expect(find.text('Waiting for Wi-Fi'), findsNothing);
    },
  );

  testWidgets('manual Pause with mobile data allowed shows Paused and Resume '
      'without changing consent', (tester) async {
    final controller = await _openSheet(
      tester,
      const ModelDownloading(receivedBytes: 1100000000, totalBytes: _total),
    );
    controller.allowMobileData.value = true;
    await tester.tap(find.text('Pause'));
    controller.state.value = const ModelPaused(
      receivedBytes: 1100000000,
      totalBytes: _total,
    );
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Translation paused · 42%'), findsOneWidget);
    expect(find.text('1.1 of 2.6 GB'), findsOneWidget);
    expect(find.text('Waiting for Wi-Fi'), findsNothing);
    expect(find.text('Use mobile data'), findsNothing);
    await tester.tap(find.text('Resume'));
    expect(controller.calls, ['pause', 'resume']);
    expect(controller.allowMobileData.value, isTrue);
  });

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
