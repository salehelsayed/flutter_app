import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/production_audio_call_local_fixture.dart';
import '../../integration_test/scripts/run_production_audio_call_sims.dart';

void main() {
  group('fixture go-test timeout', () {
    test('keeps the 45 minute Sims budget by default', () {
      expect(productionAudioCallFixtureGoTimeoutFlag({}), '-timeout=45m');
      expect(
        productionAudioCallFixtureGoTimeoutFlag({
          'PLAN399_FIXTURE_GO_TIMEOUT': ' ',
        }),
        '-timeout=45m',
      );
    });

    test('accepts a bounded override for hand-driven campaigns', () {
      expect(
        productionAudioCallFixtureGoTimeoutFlag({
          'PLAN399_FIXTURE_GO_TIMEOUT': '180m',
        }),
        '-timeout=180m',
      );
    });

    test('refuses values outside 45m to 240m', () {
      for (final value in ['30m', '241m', '2h', '180', 'abc']) {
        expect(
          () => productionAudioCallFixtureGoTimeoutFlag({
            'PLAN399_FIXTURE_GO_TIMEOUT': value,
          }),
          throwsFormatException,
          reason: value,
        );
      }
    });
  });

  group('manual hold', () {
    test('is off without a hold file', () {
      expect(productionAudioCallManualHold({}), isNull);
    });

    test('defaults to 120 minutes and is bounded to 180', () {
      expect(
        productionAudioCallManualHold({'PLAN399_MANUAL_HOLD_FILE': '/tmp/h'}),
        const Duration(minutes: 120),
      );
      expect(
        productionAudioCallManualHold({
          'PLAN399_MANUAL_HOLD_FILE': '/tmp/h',
          'PLAN399_MANUAL_HOLD_MINUTES': '30',
        }),
        const Duration(minutes: 30),
      );
      for (final value in ['0', '181', 'x']) {
        expect(
          () => productionAudioCallManualHold({
            'PLAN399_MANUAL_HOLD_FILE': '/tmp/h',
            'PLAN399_MANUAL_HOLD_MINUTES': value,
          }),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('ends when the operator deletes the hold file', () async {
      final dir = await Directory.systemTemp.createTemp('plan399-hold-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/hold');
      final waiting = waitForProductionAudioCallManualHold(
        file,
        const Duration(minutes: 5),
        poll: const Duration(milliseconds: 10),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await file.exists(), isTrue);
      await file.delete();
      await waiting.timeout(const Duration(seconds: 2));
    });

    test('ends at the bound when the file stays', () async {
      final dir = await Directory.systemTemp.createTemp('plan399-hold-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/hold');
      final stopwatch = Stopwatch()..start();
      await waitForProductionAudioCallManualHold(
        file,
        const Duration(milliseconds: 100),
        poll: const Duration(milliseconds: 10),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(await file.exists(), isTrue);
    });
  });
}
