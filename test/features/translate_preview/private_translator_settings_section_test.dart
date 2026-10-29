import 'package:flutter/material.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/private_translator_settings_section.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_model_delivery_controller.dart';

const _total = 2600000000;

Future<FakeModelDeliveryController> _pumpRow(
  WidgetTester tester,
  ModelDeliveryState state, {
  VoidCallback? onFreeUpSpace,
}) async {
  final controller = FakeModelDeliveryController(state);
  await tester.pumpWidget(
    localizedApp(
      Scaffold(
        body: PrivateTranslatorSettingsSection(
          controller: controller,
          onFreeUpSpace: onFreeUpSpace,
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('6b unsupported: one greyed row, no button, no mobile-data '
      'switch, tapping does nothing', (tester) async {
    final controller = await _pumpRow(tester, const ModelUnsupported());
    expect(find.text('Private translator'), findsOneWidget);
    expect(find.text('Not available on this phone'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Download over mobile data'), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.text('Private translator'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0.45,
    );
    await tester.tap(find.text('Private translator'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsNothing);
    expect(controller.calls, isEmpty);
  });

  testWidgets('5a not downloaded: Get opens the offer sheet', (tester) async {
    await _pumpRow(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: true,
      ),
    );
    expect(
      find.text('Translate Thoughts and voice notes. Stays on your phone.'),
      findsOneWidget,
    );
    expect(find.text('Download over mobile data'), findsOneWidget);
    await tester.tap(find.text('Get'));
    await tester.pumpAndSettle();
    expect(find.text('Your private translator'), findsOneWidget);
    expect(find.text('Download on Wi-Fi'), findsOneWidget);
  });

  testWidgets('not enough space: Get · Needs 2.8 GB, and Free up space in the '
      'sheet opens Storage', (tester) async {
    var storageOpened = 0;
    await _pumpRow(
      tester,
      const ModelNotEnoughSpace(
        totalBytes: _total,
        neededBytes: 2800000000,
        freeBytes: 1100000000,
      ),
      onFreeUpSpace: () => storageOpened++,
    );
    expect(find.text('Needs 2.8 GB'), findsOneWidget);
    await tester.tap(find.text('Get'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Free up space'));
    await tester.pumpAndSettle();
    expect(storageOpened, 1);
    expect(find.text('Your private translator'), findsNothing);
  });

  testWidgets('5b downloading: amount, bar, and Pause pauses', (tester) async {
    final controller = await _pumpRow(
      tester,
      const ModelDownloading(receivedBytes: 1100000000, totalBytes: _total),
    );
    expect(find.text('Downloading · 1.1 of 2.6 GB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.42,
    );
    await tester.tap(find.text('Pause'));
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
    testWidgets('$name: Paused · Resume resumes', (tester) async {
      final controller = await _pumpRow(tester, state);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('Resume'));
      expect(controller.calls, ['resume']);
    });
  }

  testWidgets("failed: Didn't finish · Try again retries", (tester) async {
    final controller = await _pumpRow(tester, const ModelFailed());
    expect(find.text("Didn't finish"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(controller.calls, ['retry']);
  });

  testWidgets('5c ready: Remove asks once; Cancel keeps it, Remove removes', (
    tester,
  ) async {
    final controller = await _pumpRow(
      tester,
      const ModelReady(sizeBytes: _total),
    );
    expect(find.text('On this phone · works without internet'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove translation?'), findsOneWidget);
    expect(
      find.text('Frees 2.6 GB. You can download it again any time.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Remove translation?'), findsNothing);
    expect(controller.calls, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.calls, ['remove']);
  });

  testWidgets('the mobile-data switch saves the choice', (tester) async {
    final controller = await _pumpRow(
      tester,
      const ModelNotDownloaded(
        totalBytes: _total,
        freeBytes: 18400000000,
        onWifi: false,
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(controller.calls, ['setAllowMobileData(true)']);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('Settings shows the section in Preferences, under Media & '
      'storage', (tester) async {
    final controller = FakeModelDeliveryController(
      const ModelReady(sizeBytes: _total),
    );
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: SettingsScreen(
            username: 'Sara',
            onOpenMediaStorageSheet: () {},
            privateTranslatorSection: PrivateTranslatorSettingsSection(
              controller: controller,
            ),
            onSwitchView: (_) {},
            activeTab: 'settings',
          ),
        ),
      ),
    );
    final storage = tester.getRect(find.text('Media & storage'));
    final translator = tester.getRect(find.text('Private translator'));
    expect(translator.top, greaterThan(storage.bottom));
    expect(find.text('Download over mobile data'), findsOneWidget);
  });
}
