import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_app/features/update_check/domain/update_check_state.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

// SE-41 T4a AC3: merge-on-write, the never-lower ratchet, the rank floor and
// the locks.

UpdateCheckState verified(int rank, int sequence) => UpdateCheckState(
  lastEnvelope: Uint8List.fromList([rank, sequence & 0xff]),
  highestAcceptedRank: rank,
  sequence: sequence,
);

/// A job for another isolate: its own store on the same directory. Built in
/// its own scope so the closure captures only the three values.
Future<void> Function() _saveInOtherIsolate(String path, int rank, int sequence) =>
    () => UpdateCheckStateStore(
      directoryProvider: () async => Directory(path),
    ).save(verified(rank, sequence));

void main() {
  late Directory dir;
  late UpdateCheckStateStore store;

  File stateFile() => File('${dir.path}/${UpdateCheckStateStore.fileName}');
  File floorMarker(int rank) =>
      File('${dir.path}/${UpdateCheckStateStore.rankFloorPrefix}$rank');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('se41_store_');
    store = UpdateCheckStateStore(directoryProvider: () async => dir);
  });

  tearDown(() async {
    if (stateFile().existsSync()) {
      await Process.run('chmod', ['644', stateFile().path]);
    }
    await dir.delete(recursive: true);
  });

  group('never lower (stale writers)', () {
    test('a stale writer cannot lower the rank', () async {
      await store.save(verified(2, 3));
      await store.save(verified(1, 99));
      final state = await store.load();
      expect(state.highestAcceptedRank, 2);
      expect(state.sequence, 3);
      expect(state.lastEnvelope, verified(2, 3).lastEnvelope);
    });

    test('a stale writer cannot lower the sequence within a rank', () async {
      await store.save(verified(1, 5));
      await store.save(verified(1, 4));
      final state = await store.load();
      expect(state.sequence, 5);
      expect(state.lastEnvelope, verified(1, 5).lastEnvelope);
    });

    test('the envelope follows the winning rank and sequence', () async {
      await store.save(verified(1, 9));
      await store.save(verified(2, 1));
      final state = await store.load();
      expect((state.highestAcceptedRank, state.sequence), (2, 1));
      expect(state.lastEnvelope, verified(2, 1).lastEnvelope);
    });

    test('a writer may drop an envelope but keeps its rank and sequence', () async {
      await store.save(verified(1, 5));
      await store.save((await store.load()).withoutVerifiedFile());
      final state = await store.load();
      expect(state.lastEnvelope, isNull);
      expect((state.highestAcceptedRank, state.sequence), (1, 5));
    });
  });

  group('notify and dismissal fields', () {
    test('merge by max; lastCheckAt follows the writer', () async {
      final t0 = DateTime.utc(2026, 10, 12);
      await store.save(
        UpdateCheckState(
          lastCheckAt: t0,
          dismissedLatestBuild: 130,
          notifiedSoftLatestBuild: 130,
        ),
      );
      await store.save(
        UpdateCheckState(
          // The clock went back: the schedule may move back.
          lastCheckAt: t0.subtract(const Duration(days: 1)),
          dismissedLatestBuild: 120,
          notifiedSoftLatestBuild: 125,
        ),
      );
      final state = await store.load();
      expect(state.dismissedLatestBuild, 130);
      expect(state.notifiedSoftLatestBuild, 130);
      expect(state.lastCheckAt, t0.subtract(const Duration(days: 1)));
    });

    test('hard reminder fields merge as one tuple; a higher minBuild restarts', () async {
      final t0 = DateTime.utc(2026, 10, 12);
      await store.save(
        UpdateCheckState(
          notifiedHardMinBuild: 100,
          hardReminderCount: 5,
          lastHardNotifyAt: t0,
        ),
      );
      // Stale: a lower count for the same minBuild loses.
      await store.save(
        UpdateCheckState(
          notifiedHardMinBuild: 100,
          hardReminderCount: 3,
          lastHardNotifyAt: t0.add(const Duration(days: 9)),
        ),
      );
      var state = await store.load();
      expect((state.hardReminderCount, state.lastHardNotifyAt), (5, t0));
      // A new hard episode starts its count over.
      await store.save(
        UpdateCheckState(
          notifiedHardMinBuild: 110,
          hardReminderCount: 1,
          lastHardNotifyAt: t0.add(const Duration(days: 1)),
        ),
      );
      state = await store.load();
      expect(state.notifiedHardMinBuild, 110);
      expect(state.hardReminderCount, 1);
    });

    test('a foreground dismissSoft and a background write lose nothing', () async {
      await store.save(verified(1, 1));
      final base = await store.load();
      // Both read the same state, then write concurrently through separate
      // store instances.
      final foreground = UpdateCheckStateStore(directoryProvider: () async => dir);
      final background = UpdateCheckStateStore(directoryProvider: () async => dir);
      await Future.wait([
        foreground.save(base.copyWith(dismissedLatestBuild: 120)),
        background.save(
          base.copyWith(
            notifiedSoftLatestBuild: 120,
            lastCheckAt: DateTime.utc(2026, 10, 12),
          ),
        ),
        Isolate.run(_saveInOtherIsolate(dir.path, 1, 2)),
      ]);
      final state = await store.load();
      expect(state.dismissedLatestBuild, 120);
      expect(state.notifiedSoftLatestBuild, 120);
      expect(state.lastCheckAt, DateTime.utc(2026, 10, 12));
      expect((state.highestAcceptedRank, state.sequence), (1, 2));
    });
  });

  group('injected race', () {
    test('a writer in another isolate waits for the lock, then merges', () async {
      await store.save(verified(1, 7));
      final stale = await store.load();

      final paused = Completer<void>();
      final resume = Completer<void>();
      final slow = UpdateCheckStateStore(
        directoryProvider: () async => dir,
        beforeRenameForTest: () async {
          paused.complete();
          await resume.future;
        },
      );
      // Writer A re-read the file (rank 1) and stops right before its rename.
      final writerA = slow.save(stale.copyWith(lastCheckAt: DateTime.utc(2026)));
      await paused.future;

      // Writer B (another isolate) accepts rank 2 meanwhile.
      var bDone = false;
      final writerB = Isolate.run(
        _saveInOtherIsolate(dir.path, 2, 1),
      ).then((_) => bDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(bDone, isFalse, reason: 'B must wait for A to release the lock');
      expect(File('${stateFile().path}.lock').existsSync(), isTrue);

      resume.complete();
      await Future.wait([writerA, writerB]);
      final state = await store.load();
      expect((state.highestAcceptedRank, state.sequence), (2, 1));
      expect(state.lastEnvelope, verified(2, 1).lastEnvelope);
      expect(state.lastCheckAt, DateTime.utc(2026));
      expect(File('${stateFile().path}.lock').existsSync(), isFalse);
    });

    test('a stale writer after a rank rise in another isolate loses', () async {
      await store.save(verified(1, 7));
      final stale = await store.load();
      await Isolate.run(_saveInOtherIsolate(dir.path, 2, 1));
      await store.save(stale.copyWith(sequence: 8));
      final state = await store.load();
      expect((state.highestAcceptedRank, state.sequence), (2, 1));
    });
  });

  group('rank floor marker', () {
    test('created at rank 2 and never deleted', () async {
      await store.save(verified(1, 1));
      expect(floorMarker(2).existsSync(), isFalse);
      await store.save(verified(2, 1));
      expect(floorMarker(2).existsSync(), isTrue);
      await store.save(verified(2, 2));
      await store.save(UpdateCheckState.empty);
      expect(floorMarker(2).existsSync(), isTrue);
    });

    test('a deleted, corrupt or rolled-back state file keeps rank 2', () async {
      await store.save(verified(2, 4));

      await stateFile().delete();
      expect((await store.load()).highestAcceptedRank, 2);

      await stateFile().writeAsString('{{{ not json');
      expect((await store.load()).highestAcceptedRank, 2);

      // An old rank-1 file put back: its envelope and sequence are dropped.
      await stateFile().writeAsString(
        '{"format":1,"highestAcceptedRank":1,"sequence":50,"lastEnvelope":"AQI="}',
      );
      final state = await store.load();
      expect(state.highestAcceptedRank, 2);
      expect(state.sequence, isNull);
      expect(state.lastEnvelope, isNull);

      // Saving that stale file through the store cannot lower it either.
      await store.save(verified(1, 50));
      expect((await store.load()).highestAcceptedRank, 2);
    });
  });

  group('locks', () {
    test('a fresh lock file blocks a writer until it is released', () async {
      final lock = File('${stateFile().path}.lock')..createSync();
      var done = false;
      final save = store.save(verified(1, 1)).then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(done, isFalse);
      lock.deleteSync();
      await save;
      expect((await store.load()).sequence, 1);
    });

    test('a stale lock file (dead writer, > 30 s) is taken over', () async {
      File('${stateFile().path}.lock')
        ..createSync()
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 1)));
      await store.save(verified(1, 3));
      expect((await store.load()).sequence, 3);
      expect(
        dir.listSync().map((e) => e.uri.pathSegments.last),
        [UpdateCheckStateStore.fileName],
      );
    });
  });

  group('unreadable state (iOS before the first unlock)', () {
    test('load and save throw and the file is never reset', () async {
      await store.save(verified(2, 4));
      final before = await stateFile().readAsBytes();
      await Process.run('chmod', ['000', stateFile().path]);

      await expectLater(store.load(), throwsA(isA<UpdateCheckStateUnavailable>()));
      await expectLater(
        store.save(UpdateCheckState.empty),
        throwsA(isA<UpdateCheckStateUnavailable>()),
      );

      await Process.run('chmod', ['644', stateFile().path]);
      expect(await stateFile().readAsBytes(), before);
      expect(File('${stateFile().path}.lock').existsSync(), isFalse);
    });
  });

  test('nothing in the store sets a file protection class', () {
    for (final path in [
      'lib/features/update_check/infrastructure/update_check_state_store.dart',
      'lib/features/update_check/infrastructure/update_check_state_lock.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('NSFileProtection')), reason: path);
      expect(source, isNot(contains('FileProtectionType')), reason: path);
    }
    // The app's default class is completeUntilFirstUserAuthentication: no
    // stricter default in the entitlements.
    final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, isNot(contains('default-data-protection')));
  });
}
