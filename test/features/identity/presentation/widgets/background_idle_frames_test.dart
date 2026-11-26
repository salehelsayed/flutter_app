import 'package:flutter/material.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget scene(BackgroundPreference preference, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: reduceMotion,
          ),
          child: AmbientBackground(
            preference: preference,
            child: const Center(child: Text('Content')),
          ),
        ),
      );

  Future<void> idle(WidgetTester tester, Duration duration) async {
    final end = tester.binding.clock.now().add(duration);
    while (tester.binding.clock.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  for (final preference in [
    BackgroundPreference.defaultBackground,
    BackgroundPreference.cosmic,
    BackgroundPreference.aurora,
  ]) {
    testWidgets('BL98 ${preference.name} background stops scheduling frames '
        'when idle and wakes on a touch', (tester) async {
      await tester.pumpWidget(scene(preference));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'the background still moves right after it appears',
      );

      await idle(tester, const Duration(seconds: 12));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'an idle screen holds a still background',
      );

      await tester.tap(find.text('Content'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'a touch brings the motion back',
      );

      await idle(tester, const Duration(seconds: 12));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  for (final preference in [
    BackgroundPreference.defaultBackground,
    BackgroundPreference.cosmic,
    BackgroundPreference.aurora,
  ]) {
    testWidgets('BL98 ${preference.name} background moves again when motion '
        'is turned back on after it settled', (tester) async {
      await tester.pumpWidget(scene(preference));
      await idle(tester, const Duration(seconds: 12));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(scene(preference, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(scene(preference));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.binding.hasScheduledFrame,
        isTrue,
        reason: 'turning motion back on wakes the background without a touch',
      );
    });
  }

  testWidgets('BL98 reduce motion keeps the background still from the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      scene(BackgroundPreference.defaultBackground, reduceMotion: true),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
