import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_app/features/update_check/application/update_check_service.dart';
import 'package:flutter_app/features/update_check/application/update_check_switch.dart';
import 'package:flutter_app/features/update_check/background/update_check_background_runner.dart';
import 'package:flutter_app/features/update_check/background/update_check_notifier.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_check_notify_policy.dart';
import 'package:flutter_app/features/update_check/domain/update_check_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/update_check_test_keys.dart';

// SE-41 T4a AC2 (notify rules end to end, fake clock), AC4 (budget abort),
// AC5 (no frame, locked state), AC1 (kill switch).

const _on = UpdateCheckSwitch(
  mode: 'on',
  isDebugBuild: false,
  e2eTestMode: false,
  simsBuildProfileId: '',
);

class RecordingPoster implements UpdateNotificationPoster {
  final posts = <(UpdateNotifyKind, String, String)>[];
  bool allowed = true;

  @override
  Future<bool> post({
    required UpdateNotifyKind kind,
    required String title,
    required String body,
  }) async {
    if (!allowed) return false;
    posts.add((kind, title, body));
    return true;
  }
}

class HangingFetcher extends FakeVersionFileFetcher {
  @override
  Future<Uint8List?> fetch(Uri url) {
    calls++;
    return Completer<Uint8List?>().future;
  }
}

void main() {
  late TempStateStore temp;
  late FakeVersionFileFetcher fetcher;
  late RecordingPoster poster;
  late DateTime now;
  var foreground = false;
  var inCall = false;

  setUp(() async {
    temp = await TempStateStore.create();
    fetcher = FakeVersionFileFetcher();
    poster = RecordingPoster();
    now = DateTime.utc(2026, 10, 12, 9);
    foreground = false;
    inCall = false;
  });

  tearDown(() async {
    if (temp.file.existsSync()) {
      await Process.run('chmod', ['644', temp.file.path]);
    }
    await temp.dispose();
  });

  UpdateCheckBackgroundRunner runner({
    String installed = '110',
    UpdateCheckSwitch updateSwitch = _on,
    FakeVersionFileFetcher? withFetcher,
  }) => UpdateCheckBackgroundRunner(
    service: UpdateCheckService(
      updateSwitch: updateSwitch,
      verifier: testVerifier(),
      fetcher: withFetcher ?? fetcher,
      store: temp.store,
      installedBuildNumber: () async => installed,
      platform: UpdatePlatform.ios,
      clock: () => now,
    ),
    store: temp.store,
    poster: poster,
    isForeground: () async => foreground,
    isInCall: () async => inCall,
    clock: () => now,
    locale: const Locale('en'),
  );

  Uint8List file(int sequence, {int latest = 120, int min = 100, String? reason}) =>
      signedEnvelope(
        payloadBytes(sequence: sequence, ios: section(latest, min, reason)),
      );

  Future<UpdateCheckBackgroundOutcome> run({
    String installed = '110',
    Duration budget = const Duration(seconds: 5),
  }) async => (await runner(
    installed: installed,
  ).run(reason: 'test', budget: budget)).outcome;

  group('soft (AC2)', () {
    test('once per latestBuild; a higher latestBuild notifies again', () async {
      fetcher.responses.addAll([file(1), file(1), file(2, latest: 130)]);
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      now = now.add(const Duration(hours: 7));
      expect(await run(), UpdateCheckBackgroundOutcome.notDue);
      now = now.add(const Duration(hours: 7));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      expect(poster.posts.map((p) => p.$1), [
        UpdateNotifyKind.soft,
        UpdateNotifyKind.soft,
      ]);
      expect((await temp.load()).notifiedSoftLatestBuild, 130);
    });

    test('the installed build is current -> nothing', () async {
      fetcher.responses.add(file(1));
      expect(await run(installed: '120'), UpdateCheckBackgroundOutcome.noUpdate);
      expect(poster.posts, isEmpty);
    });
  });

  group('hard (AC2)', () {
    test('once, then daily x7, then weekly, with the fixed kind', () async {
      fetcher.responses.add(file(1, min: 115));
      final start = now;
      final postedAt = <Duration>[];
      // Walk 30 days in 6 h steps; downloads fail after the first, so the
      // stored file decides (and the 6 h gate is respected).
      for (var step = 0; step <= 30 * 4; step++) {
        now = start.add(Duration(hours: 6 * step));
        final before = poster.posts.length;
        await run();
        if (poster.posts.length > before) postedAt.add(now.difference(start));
      }
      expect(postedAt, [
        Duration.zero,
        for (var day = 1; day <= 7; day++) Duration(days: day),
        const Duration(days: 14),
        const Duration(days: 21),
        const Duration(days: 28),
      ]);
      expect(poster.posts.every((p) => p.$1 == UpdateNotifyKind.hard), isTrue);
      final state = await temp.load();
      expect(state.hardReminderCount, 11);
      expect(state.notifiedHardMinBuild, 115);
    });

    test('a clock that went back makes the reminder due', () async {
      fetcher.responses.add(file(1, min: 115));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      now = now.add(const Duration(hours: 2));
      expect(await run(), UpdateCheckBackgroundOutcome.notDue);
      now = now.subtract(const Duration(days: 3));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
    });

    test('F1: a lowered minBuild does not post on every run', () async {
      fetcher.responses.addAll([file(1, min: 118), file(2, min: 115)]);
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      // Every 6 h for 3 days with the lowered file stored.
      final start = now;
      for (var step = 1; step <= 12; step++) {
        now = start.add(Duration(hours: 6 * step));
        await run();
      }
      // First post, then one daily reminder per day: days 1, 2 and 3.
      expect(poster.posts.length, 4);
      expect((await temp.load()).notifiedHardMinBuild, 118);
    });

    test('a higher minBuild starts the reminders over', () async {
      fetcher.responses.addAll([file(1, min: 115), file(2, min: 118)]);
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      now = now.add(const Duration(hours: 7));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      final state = await temp.load();
      expect((state.notifiedHardMinBuild, state.hardReminderCount), (118, 1));
    });
  });

  test('security has its own copy; other reasons use the general copy', () async {
    fetcher.responses.addAll([
      file(1, min: 115, reason: 'security'),
      file(2, latest: 130, reason: 'protocol_change'),
    ]);
    await run();
    now = now.add(const Duration(hours: 7));
    await run(installed: '119');
    final security = updateNotificationText(
      UpdateNotifyCopy.security,
      locale: const Locale('en'),
    );
    final general = updateNotificationText(
      UpdateNotifyCopy.general,
      locale: const Locale('en'),
    );
    expect(poster.posts[0].$2, security.title);
    expect(poster.posts[0].$3, security.body);
    expect(poster.posts[1].$2, general.title);
    expect(security.title, isNot(general.title));
  });

  group('defer and skip (AC2, AC6)', () {
    test('never in the foreground; nothing recorded', () async {
      foreground = true;
      fetcher.responses.add(file(1, min: 115));
      expect(await run(), UpdateCheckBackgroundOutcome.foreground);
      expect(poster.posts, isEmpty);
      expect((await temp.load()).hardReminderCount, 0);
    });

    test('never during a call; posted on a later run', () async {
      inCall = true;
      fetcher.responses.add(file(1, min: 115));
      expect(await run(), UpdateCheckBackgroundOutcome.inCall);
      inCall = false;
      now = now.add(const Duration(minutes: 30));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
    });

    test('notifications not allowed: skipped silently, nothing recorded', () async {
      poster.allowed = false;
      fetcher.responses.add(file(1));
      expect(await run(), UpdateCheckBackgroundOutcome.notPermitted);
      expect((await temp.load()).notifiedSoftLatestBuild, isNull);
    });
  });

  group('budget and engine safety (AC4, AC5)', () {
    test('the budget abort writes nothing after the deadline', () async {
      final hanging = HangingFetcher();
      final stopwatch = Stopwatch()..start();
      final result = await runner(
        withFetcher: hanging,
      ).run(reason: 'test', budget: const Duration(milliseconds: 150));
      expect(result.outcome, UpdateCheckBackgroundOutcome.aborted);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(poster.posts, isEmpty);
      expect(temp.file.existsSync(), isFalse, reason: 'no partial state');
    });

    test('runs with no first frame, no binding and no bootstrap', () async {
      // Plain `test`: no WidgetsBinding, no runApp, no Go bridge, no
      // SQLCipher. A bootstrap that never finishes does not matter.
      final bootstrap = Completer<void>();
      fetcher.responses.add(file(1));
      expect(await run(), UpdateCheckBackgroundOutcome.notified);
      expect(bootstrap.isCompleted, isFalse);
    });

    test('state unreadable (before the first unlock): skip, never reset', () async {
      await temp.store.save(
        UpdateCheckState(notifiedSoftLatestBuild: 120, lastCheckAt: now),
      );
      final before = await temp.file.readAsBytes();
      await Process.run('chmod', ['000', temp.file.path]);
      fetcher.responses.add(file(1));
      expect(await run(), UpdateCheckBackgroundOutcome.stateUnavailable);
      expect(fetcher.calls, 0);
      expect(poster.posts, isEmpty);
      await Process.run('chmod', ['644', temp.file.path]);
      expect(await temp.file.readAsBytes(), before);
    });

    test('the 6 h gate holds: no download, the stored file still decides', () async {
      fetcher.responses.add(file(1, min: 115));
      await run();
      now = now.add(const Duration(days: 1));
      await run();
      expect(fetcher.calls, 2);
      now = now.add(const Duration(hours: 1));
      await run();
      expect(fetcher.calls, 2, reason: 'last check 1 h ago');
    });
  });

  group('kill switch (AC1)', () {
    for (final (name, updateSwitch) in [
      (
        'E2E_TEST_MODE',
        const UpdateCheckSwitch(
          mode: 'on',
          isDebugBuild: false,
          e2eTestMode: true,
          simsBuildProfileId: '',
        ),
      ),
      (
        'SIMS_BUILD_PROFILE_ID',
        const UpdateCheckSwitch(
          mode: 'on',
          isDebugBuild: false,
          e2eTestMode: false,
          simsBuildProfileId: 'ios.simulator.app',
        ),
      ),
      (
        'debug default',
        const UpdateCheckSwitch(
          mode: '',
          isDebugBuild: true,
          e2eTestMode: false,
          simsBuildProfileId: '',
        ),
      ),
      (
        'MKNOON_UPDATE_CHECK=off',
        const UpdateCheckSwitch(
          mode: 'off',
          isDebugBuild: false,
          e2eTestMode: false,
          simsBuildProfileId: '',
        ),
      ),
    ]) {
      test('$name: disabled, no download, no notification', () async {
        fetcher.responses.add(file(1, min: 115));
        final result = await runner(
          updateSwitch: updateSwitch,
        ).run(reason: 'test', budget: const Duration(seconds: 5));
        expect(result.outcome, UpdateCheckBackgroundOutcome.disabled);
        expect(result.toWire()['enabled'], isFalse);
        expect(fetcher.calls, 0);
        expect(poster.posts, isEmpty);
      });
    }
  });
}
