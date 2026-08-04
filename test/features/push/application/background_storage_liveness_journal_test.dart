import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/push/application/background_storage_liveness_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('storage-liveness-journal-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('entry capacity is a release-mode hard bound', () {
    for (final invalid in <int>[0, 33]) {
      expect(
        () => BackgroundStorageLivenessJournal(
          directoryResolver: () async => root,
          maxEntries: invalid,
        ),
        throwsRangeError,
      );
    }
  });

  test(
    'release records use complete atomic slots, stay bounded, and redact',
    () async {
      final fixedNow = DateTime.utc(2026, 8, 3, 20, 30);
      final journal = BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        now: () => fixedNow,
        randomNonce: () => 7,
        buildMode: BackgroundStorageBuildMode.release,
      );
      File(
          '${root.path}${Platform.pathSeparator}'
          '.terminal-v1-tmp-s00-abandoned.tmp',
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('partial')
        ..setLastModifiedSync(fixedNow.subtract(const Duration(hours: 2)));

      for (var index = 0; index < 40; index += 1) {
        await journal.recordTerminal(
          kind: BackgroundStorageMessageKind.groupMessage,
          phase: BackgroundStorageLivenessPhase.displayEligibility,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: const Duration(milliseconds: 2300),
        );
      }

      final entities = root.listSync(followLinks: false);
      final records = entities.whereType<File>().where((file) {
        return file.path.endsWith('.json');
      }).toList();
      expect(records, hasLength(backgroundStorageLivenessJournalMaxEntries));
      expect(
        records.map((file) => file.path).toSet(),
        hasLength(records.length),
      );
      expect(
        entities.where((entity) => entity.path.endsWith('.tmp')),
        isEmpty,
        reason: 'only atomically published targets may survive',
      );
      expect(
        entities.where((entity) => entity.path.endsWith('.lock')),
        isEmpty,
        reason: 'the journal must never introduce a shared lock',
      );

      const allowedKeys = <String>{
        'kind',
        'phase',
        'outcome',
        'elapsedBucket',
        'buildMode',
        'engineRole',
      };
      for (final file in records) {
        final decoded = jsonDecode(await file.readAsString());
        expect(decoded, isA<Map<String, dynamic>>());
        final record = decoded as Map<String, dynamic>;
        expect(record.keys.toSet(), allowedKeys);
        expect(record, <String, dynamic>{
          'kind': 'group_message',
          'phase': 'display_eligibility',
          'outcome': 'storage_deferred',
          'elapsedBucket': '2s_to_8s',
          'buildMode': 'release',
          'engineRole': 'flutterfire_background',
        });
        final serialized = jsonEncode(record);
        for (final forbidden in <String>[
          'groupId',
          'peerId',
          'eventId',
          'messageId',
          'ciphertext',
          'nonce',
          'dbPath',
          'filename',
          'encryptionKey',
        ]) {
          expect(serialized, isNot(contains(forbidden)));
        }
      }
    },
  );

  test(
    'fixed clock and random source still fill distinct concurrent slots',
    () async {
      final journal = BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        now: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        randomNonce: () => 0,
        buildMode: BackgroundStorageBuildMode.debug,
      );

      await Future.wait(
        List<Future<void>>.generate(
          12,
          (_) => journal.recordTerminal(
            kind: BackgroundStorageMessageKind.directMessage,
            phase: BackgroundStorageLivenessPhase.localState,
            outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
            elapsed: const Duration(milliseconds: 10),
          ),
        ),
      );

      final files = root
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(12));
      expect(files.map((file) => file.path).toSet(), hasLength(12));
    },
  );

  test('overlapping writers cannot exceed the fixed 32 slots', () async {
    final journals = List<BackgroundStorageLivenessJournal>.generate(
      4,
      (_) => BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        now: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        randomNonce: () => 0,
      ),
    );

    await Future.wait<void>(
      List<Future<void>>.generate(
        80,
        (index) => journals[index % journals.length].recordTerminal(
          kind: BackgroundStorageMessageKind.groupMessage,
          phase: BackgroundStorageLivenessPhase.localState,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
        ),
      ),
    );

    final entities = root.listSync(followLinks: false);
    final records = entities
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList(growable: false);
    expect(
      records.length,
      lessThanOrEqualTo(backgroundStorageLivenessJournalMaxEntries),
    );
    expect(records.map((file) => file.path).toSet(), hasLength(records.length));
    for (final record in records) {
      expect(
        jsonDecode(await record.readAsString()),
        isA<Map<String, dynamic>>(),
      );
    }
  });

  test(
    'fresh journal instances fill all fixed slots before replacement',
    () async {
      for (
        var index = 0;
        index < backgroundStorageLivenessJournalMaxEntries + 4;
        index += 1
      ) {
        final journal = BackgroundStorageLivenessJournal(
          directoryResolver: () async => root,
          now: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          randomNonce: () => 0,
        );
        await journal.recordTerminal(
          kind: BackgroundStorageMessageKind.directMessage,
          phase: BackgroundStorageLivenessPhase.localState,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
        );
      }

      final records = root
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList(growable: false);
      expect(records, hasLength(backgroundStorageLivenessJournalMaxEntries));
      expect(
        records.map((file) => file.path).toSet(),
        hasLength(records.length),
      );
    },
  );

  test('failed publication preserves the previous complete slot', () async {
    final seed = BackgroundStorageLivenessJournal(
      directoryResolver: () async => root,
      randomNonce: () => 0,
    );
    for (
      var index = 0;
      index < backgroundStorageLivenessJournalMaxEntries;
      index += 1
    ) {
      await seed.recordTerminal(
        kind: BackgroundStorageMessageKind.groupMessage,
        phase: BackgroundStorageLivenessPhase.localState,
        outcome: BackgroundStorageTerminalOutcome.storageDeferred,
        elapsed: Duration.zero,
      );
    }
    final before = <String, String>{
      for (final file
          in root
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('.json')))
        file.path: file.readAsStringSync(),
    };

    final failing = BackgroundStorageLivenessJournal(
      directoryResolver: () async => root,
      randomNonce: () => 0,
      atomicWriter:
          ({required temporary, required target, required contents}) async {
            await temporary.writeAsString(contents, flush: true);
            throw const FileSystemException('injected pre-rename failure');
          },
    );
    await failing.recordTerminal(
      kind: BackgroundStorageMessageKind.directReaction,
      phase: BackgroundStorageLivenessPhase.recentGate,
      outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
      elapsed: Duration.zero,
    );

    final after = <String, String>{
      for (final file
          in root
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith('.json')))
        file.path: file.readAsStringSync(),
    };
    expect(after, before);
    expect(
      root.listSync().where((entity) => entity.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test(
    'stalled writer cannot delay the caller beyond its impact budget',
    () async {
      final writerEntered = Completer<void>();
      final releaseWriter = Completer<void>();
      final journal = BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        maxCallerImpact: const Duration(milliseconds: 20),
        atomicWriter:
            ({required temporary, required target, required contents}) {
              writerEntered.complete();
              return releaseWriter.future;
            },
      );

      final stopwatch = Stopwatch()..start();
      final write = journal.recordTerminal(
        kind: BackgroundStorageMessageKind.groupReaction,
        phase: BackgroundStorageLivenessPhase.encryptedOpen,
        outcome: BackgroundStorageTerminalOutcome.storageDeferred,
        elapsed: const Duration(seconds: 8),
      );
      await writerEntered.future;
      await write;
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 150)));
      releaseWriter.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'stalled prune and journal failures are swallowed within the bound',
    () async {
      final seedJournal = BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
      );
      for (
        var index = 0;
        index < backgroundStorageLivenessJournalMaxEntries;
        index += 1
      ) {
        await seedJournal.recordTerminal(
          kind: BackgroundStorageMessageKind.groupMessage,
          phase: BackgroundStorageLivenessPhase.localState,
          outcome: BackgroundStorageTerminalOutcome.storageDeferred,
          elapsed: Duration.zero,
        );
      }
      final releasePrune = Completer<void>();
      final stalledPrune = BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        maxCallerImpact: const Duration(milliseconds: 20),
        pruner: (directory, maxEntries) => releasePrune.future,
      );
      final stopwatch = Stopwatch()..start();
      await stalledPrune.recordTerminal(
        kind: BackgroundStorageMessageKind.directReaction,
        phase: BackgroundStorageLivenessPhase.recentGate,
        outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
        elapsed: const Duration(milliseconds: 100),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 150)));
      expect(
        root.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.json'),
        ),
        hasLength(backgroundStorageLivenessJournalMaxEntries),
        reason: 'a stalled capacity prune must not publish a 33rd record',
      );
      releasePrune.complete();

      final failedJournal = BackgroundStorageLivenessJournal(
        directoryResolver: () => Future<Directory>.error(
          const FileSystemException('app-private storage unavailable'),
        ),
        maxCallerImpact: const Duration(milliseconds: 20),
      );
      await expectLater(
        failedJournal.recordTerminal(
          kind: BackgroundStorageMessageKind.unknown,
          phase: BackgroundStorageLivenessPhase.displayEligibility,
          outcome: BackgroundStorageTerminalOutcome.notificationSuppressed,
          elapsed: Duration.zero,
        ),
        completes,
      );
    },
  );

  test('elapsed bucketing is boundary exact', () {
    expect(
      bucketBackgroundStorageElapsed(
        const Duration(seconds: 2) - const Duration(microseconds: 1),
      ),
      BackgroundStorageElapsedBucket.underTwoSeconds,
    );
    expect(
      bucketBackgroundStorageElapsed(const Duration(seconds: 2)),
      BackgroundStorageElapsedBucket.twoToEightSeconds,
    );
    expect(
      bucketBackgroundStorageElapsed(const Duration(seconds: 8)),
      BackgroundStorageElapsedBucket.eightSecondsOrMore,
    );
  });
}
